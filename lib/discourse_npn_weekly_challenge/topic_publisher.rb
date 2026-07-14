# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # Creates and pins the weekly challenge announcement topic when a challenge
  # starts, replacing the manual staging-and-timer routine. The topic is
  # generated from registry data (title, dates, description) through the
  # title/body templates in the site settings.
  #
  # This is the only part of the plugin that writes to the forum, so it is built
  # to be boring and unsurprising:
  #
  #   * It only ever considers Registry.current, and only within PUBLISH_WINDOW
  #     of its start. The registry holds hundreds of past challenges — a
  #     publisher that asked "which challenges lack a topic?" would post them
  #     all the first time it ran. There is deliberately no backfill, ever.
  #   * A topic custom field (TOPIC_SLUG_FIELD) records which challenge a topic
  #     belongs to, and is the sole answer to "has this week been published?".
  #     Combined with a mutex, a double-run cannot produce a double post.
  #   * Like WordpressSync, it NEVER raises: a missing category, a bad template
  #     or a deleted author degrades to "nothing published", logs a warning, and
  #     leaves the scheduled job green.
  #
  # A consequence of the window: enabling the setting mid-week publishes nothing
  # until the next challenge begins. That is what stops it duplicating a topic a
  # moderator already posted by hand.
  module TopicPublisher
    TOPIC_SLUG_FIELD = "npn_weekly_challenge_slug"
    PUBLISH_WINDOW = 24.hours

    module_function

    def enabled?
      SiteSetting.npn_weekly_challenges_enabled &&
        SiteSetting.npn_weekly_challenge_auto_topic_enabled
    end

    # Publish the current challenge's topic if it has just started and has not
    # been published yet. Returns the Topic on success, nil otherwise.
    def publish_due
      return nil unless enabled?

      challenge = Registry.current
      return nil if challenge.nil?
      # Only the challenge that has *just* started. Anything older is history.
      return nil if challenge.starts_at < PUBLISH_WINDOW.ago
      return nil if topic_for(challenge)

      DistributedMutex.synchronize("npn_weekly_challenge_publish_#{challenge.slug}") do
        # Re-check inside the lock: a concurrent run may have just published.
        next nil if topic_for(challenge)
        publish(challenge)
      end
    rescue => e
      log_failure("unexpected error", e)
      nil
    end

    # Create the topic, pin it, and unpin the previous challenge's.
    def publish(challenge)
      category_id = category_id_for_publishing
      return nil if category_id.nil?

      raw = render(SiteSetting.npn_weekly_challenge_auto_topic_body, challenge)
      title = unique_title(challenge)
      return nil if raw.blank? || title.blank?

      post =
        PostCreator.create!(
          author,
          title: title,
          raw: raw,
          # TopicCreator only accepts an id here; a Category object raises.
          category: category_id,
          tags: tags,
          skip_validations: true,
          topic_opts: {
            custom_fields: {
              TOPIC_SLUG_FIELD => challenge.slug,
            },
          },
        )

      topic = post.topic
      rotate_pin(topic, challenge)
      topic
    end

    # Pin this week's topic and unpin the one it replaces. Only topics this
    # plugin created can be found (they carry the custom field), so a hand-made
    # topic from before the automation has to be unpinned once, by hand.
    def rotate_pin(topic, challenge)
      previous = Registry.previous_challenge(challenge)
      previous_topic = previous && topic_for(previous)
      previous_topic&.update_pinned(false)

      # Category pin, not global — matching how these have always been pinned.
      topic.update_pinned(true, false)
    end

    # The topic already published for a challenge, or nil. The custom field is
    # the record of what has been published; it survives a WordPress re-sync,
    # which rewrites the stored challenge records wholesale.
    def topic_for(challenge)
      Topic
        .joins(:_custom_fields)
        .where(topic_custom_fields: { name: TOPIC_SLUG_FIELD, value: challenge.slug })
        .first
    end

    # Challenge titles repeat over the years ("Fog" has run three times), and a
    # duplicate title is rejected by the Topic model itself — skip_validations
    # does not waive it. Disambiguate with the date range when it's taken.
    def unique_title(challenge)
      title = render(SiteSetting.npn_weekly_challenge_auto_topic_title, challenge)
      return nil if title.blank?
      return title unless title_taken?(title)

      range = ChallengeTime.display_range(challenge.starts_at, challenge.ends_at)
      range.present? ? "#{title} (#{range})" : title
    end

    def title_taken?(title)
      Topic.listable_topics.where("lower(topics.title) = ?", title.downcase).exists?
    end

    # Interpolate a template. A typo'd placeholder must not take the job down,
    # so an unknown one degrades to "publish nothing this week" plus a warning.
    def render(template, challenge)
      template.to_s.strip.%(
        title: challenge.title,
        description: challenge.description.to_s,
        date_range: ChallengeTime.display_range(challenge.starts_at, challenge.ends_at).to_s,
        challenge_url: "/weekly-challenges/#{challenge.slug}",
        prompt_url: challenge.url.to_s,
        slug: challenge.slug,
      )
    rescue KeyError, ArgumentError => e
      log_failure("template is invalid", e)
      nil
    end

    def author
      username = SiteSetting.npn_weekly_challenge_auto_topic_author.to_s.strip.downcase
      user = User.find_by(username_lower: username) if username.present?
      user || Discourse.system_user
    end

    def tags
      SiteSetting.npn_weekly_challenge_auto_topic_tags.to_s.split("|").map(&:strip).compact_blank
    end

    # The destination category. Publishing without one configured would drop the
    # topic into the site's default category, so refuse instead.
    def category_id_for_publishing
      id = SiteSetting.npn_weekly_challenge_auto_topic_category.to_i
      return id if id.positive? && Category.exists?(id)

      log_failure(
        "no destination category",
        StandardError.new("npn_weekly_challenge_auto_topic_category is unset or unknown"),
      )
      nil
    end

    def log_failure(reason, error)
      Rails.logger.warn("[#{PLUGIN_NAME}] auto topic #{reason}: #{error.class}: #{error.message}")
    end
  end
end
