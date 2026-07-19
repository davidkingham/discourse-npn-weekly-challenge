# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  class ChallengesController < ::ApplicationController
    requires_plugin DiscourseNpnWeeklyChallenge::PLUGIN_NAME

    # #current is a server-side redirect and #announcements is an RSS feed, not
    # Ember entry points, so they must run for plain non-XHR requests.
    # ApplicationController#check_xhr would otherwise preempt them with the SPA
    # bootstrap shell.
    skip_before_action :check_xhr, only: %i[current announcements]

    # Feed length. Kit and friends only care about the newest item; a page of
    # recent weeks is plenty for any reader while keeping the response small.
    ANNOUNCEMENTS_FEED_SIZE = 10

    # GET /weekly-challenges
    # HTML renders the Ember app; JSON returns the challenge list.
    def index
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          challenges = Registry.all.select { |challenge| published?(challenge) }
          render json: {
                   challenges: serialize_data(challenges, ChallengeSerializer),
                   current_slug: Registry.current&.slug,
                 }
        end
      end
    end

    # GET /weekly-challenges/upcoming
    # The published schedule: challenges that have been announced but have not
    # started. The complement of #index, which lists only what has started.
    # Nothing here is linkable — #show 404s until a challenge starts — so the
    # JSON carries no current_slug and the page renders no links.
    def upcoming
      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          render json: { challenges: serialize_data(Registry.upcoming, ChallengeSerializer) }
        end
      end
    end

    # GET /weekly-challenges/current
    # A stable entry point (e.g. a fixed link from the WordPress site) that
    # 302-redirects to whichever challenge is active right now, resolved per
    # request so the link tracks the weekly rollover on its own. Falls back to
    # the archive index when none has started yet. Never a 301 — the
    # destination changes every week.
    def current
      # The anonymous cache only stores 200s, but be explicit so no browser or
      # CDN pins this redirect to one week's challenge.
      response.headers["Cache-Control"] = "no-store"

      challenge = Registry.current
      return redirect_to(path("/weekly-challenges")) if challenge.nil?

      redirect_to path("/weekly-challenges/#{challenge.slug}")
    end

    # GET /weekly-challenges/announcements.rss
    # The auto-published announcement topics as an RSS feed, for external
    # automations (the Kit email) that need announcements only. The shared
    # weekly-challenge tag also carries members' entry topics, so the feed keys
    # off the topic custom field TopicPublisher stamps instead: exactly the
    # topics this plugin created, and nothing a human can add by mis-tagging.
    def announcements
      discourse_expires_in 1.minute

      # Secured as anonymous no matter who is asking: the response is
      # anonymously cacheable and consumed by logged-out services, so it must
      # never widen to a logged-in viewer's visibility.
      @topics =
        Topic
          .secured(Guardian.new)
          .listable_topics
          .visible
          .joins(:_custom_fields)
          .where(topic_custom_fields: { name: TopicPublisher::TOPIC_SLUG_FIELD })
          .includes(:user, :category, :first_post)
          .order(created_at: :desc)
          .limit(ANNOUNCEMENTS_FEED_SIZE)

      render formats: [:rss]
    end

    # GET /weekly-challenges/:slug
    # HTML renders the Ember app; JSON returns the challenge, its adjacent
    # challenges, the visible entry count, and one page of entry topics.
    def show
      challenge = Registry.find_by_slug(params[:slug])
      # Future challenges are seeded ahead of time (the published schedule) but
      # only join the archive once they have started.
      raise Discourse::NotFound if challenge.nil? || !published?(challenge)

      respond_to do |format|
        format.html { render html: nil, layout: true }
        format.json do
          if params[:page].present? && !TopicQuery.validate?(:page, params[:page])
            raise Discourse::InvalidParameters.new(:page)
          end

          list = TopicFinder.list(challenge, user: current_user, page: params[:page].to_i)

          # Serialized with its root so the poster `users` / `primary_groups`
          # sideloads land alongside `topic_list`, where the client-side
          # TopicList.topicsFrom expects them.
          render_json_dump(
            serialize_data(list, TopicListSerializer).merge(
              challenge: serialize_challenge(challenge),
              previous_challenge: serialize_challenge(Registry.previous_challenge(challenge)),
              next_challenge: serialize_challenge(published_next_challenge(challenge)),
              entry_count: TopicFinder.count(challenge, user: current_user),
            ),
          )
        end
      end
    end

    private

    # The next challenge for navigation, but only once it has started — so the
    # current week never links forward to an unpublished one.
    def published_next_challenge(challenge)
      nxt = Registry.next_challenge(challenge)
      nxt if nxt && published?(nxt)
    end

    def published?(challenge)
      challenge.starts_at <= Time.zone.now
    end

    def serialize_challenge(challenge)
      return nil if challenge.nil?
      serialize_data(challenge, ChallengeSerializer, root: false)
    end
  end
end
