# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # The v1 challenge data source: a JSON array in the
  # npn_weekly_challenge_registry_json site setting, parsed into frozen
  # Challenge objects. This module is the only place that knows where
  # challenge data comes from — a future WordPress sync replaces the inside
  # of .all without touching the controller or TopicFinder.
  #
  # Parsing is defensive and never raises: malformed JSON yields an empty
  # registry and invalid entries are skipped, with a warning logged either
  # way, so a typo in the setting can't take down the archive pages.
  module Registry
    module_function

    # All challenges, newest first by starts_at. Memoized per-process keyed
    # on the raw setting string, so edits take effect immediately and
    # repeated requests don't re-parse.
    def all
      raw = SiteSetting.npn_weekly_challenge_registry_json.to_s

      cached = @cache
      return cached[1] if cached && cached[0] == raw

      challenges = parse(raw)
      @cache = [raw, challenges]
      challenges
    end

    def clear_cache
      @cache = nil
    end

    def find_by_slug(slug)
      slug = slug.to_s.strip.downcase
      return nil if slug.blank?
      all.find { |challenge| challenge.slug == slug }
    end

    # Chronologically adjacent challenges (`all` is sorted newest first).
    def next_challenge(challenge)
      index = all.index(challenge)
      return nil if index.nil? || index.zero?
      all[index - 1]
    end

    def previous_challenge(challenge)
      index = all.index(challenge)
      return nil if index.nil?
      all[index + 1]
    end

    # The [start, end) window used for legacy tag+date matching.
    def window_for(challenge)
      [challenge.starts_at, challenge.window_end(next_challenge(challenge)&.starts_at)]
    end

    def parse(raw)
      return [] if raw.strip.blank?

      parsed = JSON.parse(raw)
      unless parsed.is_a?(Array)
        log_warning("registry JSON must be an array, got #{parsed.class}")
        return []
      end

      challenges = []
      seen_slugs = Set.new
      parsed.each do |entry|
        challenge = Challenge.from_hash(entry)
        if challenge.nil?
          log_warning("skipping invalid registry entry: #{entry.inspect.truncate(200)}")
        elsif !seen_slugs.add?(challenge.slug)
          log_warning("skipping duplicate registry slug: #{challenge.slug}")
        else
          challenges << challenge
        end
      end

      challenges.sort_by(&:starts_at).reverse.freeze
    rescue JSON::ParserError => e
      log_warning("registry JSON is malformed: #{e.message}")
      []
    end

    def log_warning(message)
      Rails.logger.warn("[#{PLUGIN_NAME}] #{message}")
    end
  end
end
