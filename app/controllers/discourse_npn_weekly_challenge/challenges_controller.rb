# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  class ChallengesController < ::ApplicationController
    requires_plugin DiscourseNpnWeeklyChallenge::PLUGIN_NAME

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
