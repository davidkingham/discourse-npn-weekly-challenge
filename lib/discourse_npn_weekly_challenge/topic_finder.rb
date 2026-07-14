# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # Finds the entry topics for one challenge. A topic qualifies through either
  # path, in a single pass over `topics` (so a topic matching both can never
  # appear twice):
  #
  #   1. Modern submissions: the npn_wordpress_challenge_id topic custom field
  #      (written by discourse-npn-submissions' TopicMetadata) equals the
  #      challenge's WordPress id. Served by the partial
  #      topic_custom_fields (value, name) index.
  #   2. Legacy topics: tagged with the configured Weekly Challenge tag and
  #      created inside the challenge's [start, end) window.
  #
  # Visibility is delegated to TopicQuery#default_results (via
  # TopicQueryExtension) — secured categories, unlisted/deleted topics, and
  # pagination are core's problem, and we only ever narrow its relation.
  module TopicFinder
    WP_CHALLENGE_ID_FIELD = "npn_wordpress_challenge_id"

    module_function

    # A TopicList (compatible with TopicListSerializer) for one page of the
    # challenge's entries, newest first.
    def list(challenge, user:, page: 0)
      TopicQuery.new(
        user,
        per_page: SiteSetting.npn_weekly_challenge_page_size,
        page: [page.to_i, 0].max,
        order: "created",
      ).list_npn_weekly_challenge(challenge)
    end

    # Total entries visible to the user. Uses the same secured relation as
    # #list so the count can never exceed what the user is allowed to see.
    def count(challenge, user:)
      TopicQuery.new(user, limit: false).npn_weekly_challenge_count(challenge)
    end

    def scope_to_challenge(results, challenge)
      clauses = []
      params = {}

      if challenge.wordpress_challenge_id.present?
        clauses << "topics.id IN (SELECT topic_id FROM topic_custom_fields " \
          "WHERE name = :field_name AND value = :field_value)"
        params[:field_name] = WP_CHALLENGE_ID_FIELD
        params[:field_value] = challenge.wordpress_challenge_id
      end

      if (tag_ids = challenge_tag_ids).present?
        window_start, window_end = Registry.window_for(challenge)
        clauses << "(topics.id IN (SELECT topic_id FROM topic_tags WHERE tag_id IN (:tag_ids)) " \
          "AND topics.created_at >= :window_start AND topics.created_at < :window_end)"
        params[:tag_ids] = tag_ids
        params[:window_start] = window_start
        params[:window_end] = window_end
      end

      return Topic.none if clauses.empty?

      results = results.where(clauses.join(" OR "), **params)

      # The auto-published announcement topic is tagged and lives inside its own
      # challenge's window, so it matches the legacy path above — it would list
      # itself as an entry and inflate the count. It is the prompt, not an entry.
      announcement = TopicPublisher.topic_for(challenge)
      results = results.where.not(id: announcement.id) if announcement

      category_ids = scoped_category_ids
      results = results.where(category_id: category_ids) if category_ids.present?
      results
    end

    def scoped_category_ids
      SiteSetting
        .npn_weekly_challenge_category_ids
        .to_s
        .split("|")
        .filter_map { |id| id.to_i if id.match?(/\A\d+\z/) }
    end

    def challenge_tag_ids
      names = SiteSetting.npn_weekly_challenge_tag_name.to_s.split("|").map(&:strip).compact_blank
      return [] if names.empty?
      Tag.where(name: names).pluck(:id)
    end
  end
end
