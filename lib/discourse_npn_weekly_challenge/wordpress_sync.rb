# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # Keeps the challenge archive current by pulling the Weekly Challenge custom
  # post type from WordPress and upserting each one into ChallengeStore. The
  # WordPress feed only exposes a rolling window of recent challenges, so this
  # runs on a schedule and accumulates them durably — once a challenge lands in
  # the store it stays in the archive even after WordPress drops it.
  #
  # The shipped seed already covers history through its generation date, so we
  # only store weeks the seed doesn't have. That keeps the store to genuine
  # deltas and avoids any chance of a WordPress title drift creating a duplicate
  # week alongside the seed's copy.
  #
  # Like the submissions plugin's WeeklyChallengeInfo, the fetch is deliberately
  # defensive: server-side only, short timeouts, SSRF-protected
  # (FinalDestination::HTTP), tolerant of the ACF-in-REST shape, and it NEVER
  # raises. A failure is logged and leaves the store untouched.
  module WordpressSync
    HTTP_TIMEOUT = 5
    PER_PAGE = 100
    MAX_TITLE = 200
    MAX_DESCRIPTION = 2000
    # The real feed (a few dozen challenges) is well under 100KB; this only
    # bounds memory if a wrong URL or misbehaving upstream streams something huge.
    MAX_BYTES = 5.megabytes

    module_function

    def enabled?
      SiteSetting.npn_weekly_challenges_enabled && api_url.present?
    end

    def api_url
      SiteSetting.npn_weekly_challenge_wordpress_api_url.to_s.strip
    end

    # Fetch the collection and upsert any weeks the seed doesn't already cover.
    # Returns true when the store changed, false otherwise (including no-op
    # cases: disabled, fetch failure, nothing new). Never raises.
    def refresh
      return false unless enabled?

      posts = fetch_collection(api_url)
      return false if posts.blank?

      seed_starts = Registry.seed_challenges.map(&:starts_at).to_set
      records =
        posts
          .filter_map { |post| normalize(post) }
          .reject { |record| seed_starts.include?(Time.zone.parse(record["starts_at"])) }

      changed = ChallengeStore.upsert_all(records)
      Registry.clear_cache if changed
      changed
    rescue => e
      log_failure("unexpected error", e)
      false
    end

    # Map one WordPress post to a seed-shaped hash, or nil when it lacks the data
    # we need. Title and start date are required; the WordPress numeric post
    # "title" is ignored — the real challenge title lives in acf.wc_title.
    def normalize(post)
      return nil unless post.is_a?(Hash)

      acf = post["acf"].is_a?(Hash) ? post["acf"] : {}
      title = clean(acf["wc_title"], MAX_TITLE)
      return nil if title.blank?

      starts_at = ChallengeTime.parse_start(acf["wc_dates"])
      return nil if starts_at.nil?

      date = starts_at.in_time_zone(ChallengeTime.zone).to_date
      id = post["id"].to_i

      {
        "wordpress_challenge_id" => (id.positive? ? id.to_s : nil),
        "title" => title,
        "slug" => "#{date.strftime("%Y-%m-%d")}-#{slugify(title)}",
        "starts_at" => starts_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "ends_at" => ChallengeTime.default_end(starts_at)&.utc&.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "url" => clean_url(post["link"]),
        "description" => clean(acf["wc_description"], MAX_DESCRIPTION),
      }
    end

    # Must match scripts/generate_seed.rb so a synced week and a seed week with
    # the same title produce the same slug.
    def slugify(str)
      str.downcase.gsub("&", " and ").gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    end

    # GET the collection endpoint and return the parsed array of posts, or nil.
    def fetch_collection(url)
      body = fetch_remote(collection_uri(url))
      return nil if body.blank?

      parsed = JSON.parse(body)
      parsed.is_a?(Array) ? parsed : [parsed]
    rescue JSON::ParserError => e
      log_failure("malformed JSON", e)
      nil
    end

    # Ensure a bounded per_page so a misconfigured endpoint can't stream the
    # entire post type. Preserves any query the admin already put on the URL.
    def collection_uri(url)
      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query.to_s)
      params << ["per_page", PER_PAGE.to_s] unless params.any? { |k, _| k == "per_page" }
      uri.query = URI.encode_www_form(params)
      uri
    end

    # Server-side, SSRF-protected, short-timeout GET. Returns the body on 2xx,
    # else nil. Redirects are not followed.
    def fetch_remote(uri)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

      body = nil
      FinalDestination::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.is_a?(URI::HTTPS),
        open_timeout: HTTP_TIMEOUT,
      ) do |http|
        http.read_timeout = HTTP_TIMEOUT
        request =
          Net::HTTP::Get.new(
            uri.request_uri,
            { "Accept" => "application/json", "User-Agent" => "Discourse NPN Weekly Challenge" },
          )
        body = read_capped_body(http, request)
      end
      body
    rescue URI::InvalidURIError => e
      log_failure("invalid URL", e)
      nil
    rescue => e
      log_failure("fetch failed", e)
      nil
    end

    # Stream a 2xx response body, aborting if it exceeds MAX_BYTES so a wrong or
    # hostile endpoint can't balloon memory. Returns the body, or nil on a
    # non-2xx response or when the cap is hit.
    def read_capped_body(http, request)
      http.request(request) do |response|
        return nil unless response.is_a?(Net::HTTPSuccess)
        return nil if response["Content-Length"].to_i > MAX_BYTES

        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          if buffer.bytesize > MAX_BYTES
            log_failure("response too large", StandardError.new("exceeded #{MAX_BYTES} bytes"))
            return nil
          end
        end
        return buffer
      end
      nil
    end

    # Reduce a WordPress value to safe, length-capped plain text.
    def clean(value, max)
      return nil if value.nil?

      # \s does not match the non-breaking spaces HTML entities leave behind,
      # so collapse U+00A0 explicitly too.
      text = Nokogiri::HTML5.fragment(value.to_s).text.gsub(/[\s\u00A0]+/, " ").strip
      return nil if text.blank?

      text.length > max ? "#{text[0, max].rstrip}…" : text
    end

    def clean_url(value)
      url = value.to_s.strip
      return nil if url.blank?

      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present? ? url : nil
    rescue URI::InvalidURIError
      nil
    end

    def log_failure(reason, error)
      Rails.logger.warn(
        "[#{PLUGIN_NAME}] WordPress sync #{reason}: #{error.class}: #{error.message}",
      )
    end
  end
end
