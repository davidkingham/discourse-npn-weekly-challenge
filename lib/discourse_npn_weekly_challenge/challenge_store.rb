# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # Durable store for challenges discovered by the WordPress sync. The shipped
  # seed (config/weekly_challenge_seed.json) is the historical baseline; this
  # holds everything that has appeared since — typically just the current week
  # and any future weeks WordPress has published but the seed predates.
  #
  # Backed by a single PluginStore row (a JSON array of seed-shaped hashes),
  # keyed by slug. Volume is tiny (one challenge a week), so read-modify-write of
  # the whole array is fine and keeps reads dependency-free.
  module ChallengeStore
    KEY = "synced_challenges"

    module_function

    # Array of stored challenge hashes (string keys, seed schema). Newest first
    # is not guaranteed here — Registry sorts the merged set.
    def all
      value = PluginStore.get(PLUGIN_NAME, KEY)
      value.is_a?(Array) ? value : []
    end

    # Insert or replace. Returns true when the stored set changed, false when the
    # record was identical to what was already there (so the sync can avoid
    # needless cache busting). Records without a slug are ignored.
    #
    # Matching prefers the stable WordPress challenge id over the slug: the slug
    # is derived from the (mutable) title and start date, so editing either in
    # WordPress would otherwise strand the old row and insert a duplicate. When
    # the id is present we replace the row that already carries it, even if its
    # slug changed; only records with no id fall back to slug matching.
    def upsert(record)
      slug = record && record["slug"]
      return false if slug.blank?

      wp_id = record["wordpress_challenge_id"].presence

      records = all
      existing = nil
      existing = records.index { |r| r["wordpress_challenge_id"].to_s == wp_id.to_s } if wp_id
      existing ||= records.index { |r| r["slug"] == slug }
      return false if existing && records[existing] == record

      if existing
        records[existing] = record
      else
        records << record
      end
      PluginStore.set(PLUGIN_NAME, KEY, records)
      true
    end

    # Upsert many; returns true if anything changed.
    def upsert_all(new_records)
      changed = false
      new_records.each { |record| changed = true if upsert(record) }
      changed
    end

    def clear
      PluginStore.remove(PLUGIN_NAME, KEY)
    end
  end
end
