# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # The challenge data source. Merges three layers, lowest precedence first:
  #
  #   1. the shipped seed (config/weekly_challenge_seed.json) — the historical
  #      baseline backfilled from the "Past and future challenges" topic;
  #   2. the WordPress sync store (ChallengeStore) — challenges discovered since
  #      the seed was generated, refreshed by the scheduled job;
  #   3. the manual npn_weekly_challenge_registry_json setting — an override/
  #      escape hatch for corrections and one-offs.
  #
  # Entries are keyed by slug; a later layer replaces an earlier one with the
  # same slug. This module is the only code that knows where challenges come
  # from — controller, TopicFinder and the frontend are unaffected by the layers.
  #
  # Everything here is defensive and never raises: an unreadable seed, a corrupt
  # store, or malformed manual JSON each degrade to "that layer contributes
  # nothing" with a logged warning, so a bad input can't take down the archive.
  module Registry
    SEED_PATH = File.expand_path("../../config/weekly_challenge_seed.json", __dir__)

    module_function

    # All challenges, newest first by starts_at. The merged result is memoized
    # keyed on the cheap-to-read mutable layers (the store contents and the
    # manual setting), so repeated calls within and across requests don't rebuild
    # ~400 Challenge objects unless something actually changed. The seed is
    # parsed once and reused.
    def all
      manual_raw = SiteSetting.npn_weekly_challenge_registry_json.to_s
      store_records = ChallengeStore.all
      key = [manual_raw, store_records]

      cached = @cache
      return cached[1] if cached && cached[0] == key

      result = merge(seed_challenges, build(store_records), manual_challenges(manual_raw))
      @cache = [key, result]
      result
    end

    def clear_cache
      @cache = nil
      @seed = nil
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

    # The shipped historical baseline, parsed once per process.
    def seed_challenges
      @seed ||= load_seed
    end

    def load_seed
      build(JSON.parse(File.read(SEED_PATH)))
    rescue SystemCallError, JSON::ParserError => e
      log_warning("seed file unreadable (#{e.class}: #{e.message}); archive will be empty")
      []
    end

    def manual_challenges(raw)
      return [] if raw.strip.blank? || raw.strip == "[]"

      parsed = JSON.parse(raw)
      unless parsed.is_a?(Array)
        log_warning("manual registry JSON must be an array, got #{parsed.class}")
        return []
      end
      build(parsed)
    rescue JSON::ParserError => e
      log_warning("manual registry JSON is malformed: #{e.message}")
      []
    end

    # Turn an array of raw hashes into Challenge objects, skipping invalid and
    # intra-layer duplicate slugs (first wins within a layer).
    def build(array)
      return [] unless array.is_a?(Array)

      challenges = []
      seen = Set.new
      array.each do |entry|
        challenge = Challenge.from_hash(entry)
        next if challenge.nil?
        challenges << challenge if seen.add?(challenge.slug)
      end
      challenges
    end

    # Combine layers low-to-high precedence: a later layer's challenge replaces
    # an earlier one with the same slug. Newest first, frozen.
    def merge(*layers)
      by_slug = {}
      layers.each { |layer| layer.each { |challenge| by_slug[challenge.slug] = challenge } }
      by_slug.values.sort_by(&:starts_at).reverse.freeze
    end

    def log_warning(message)
      Rails.logger.warn("[#{PLUGIN_NAME}] #{message}")
    end
  end
end
