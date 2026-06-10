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
          render json: { challenges: serialize_data(Registry.all, ChallengeSerializer) }
        end
      end
    end

    # GET /weekly-challenges/:slug
    # HTML renders the Ember app; JSON returns the challenge, its adjacent
    # challenges, the visible entry count, and one page of entry topics.
    def show
      challenge = Registry.find_by_slug(params[:slug])
      raise Discourse::NotFound if challenge.nil?

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
              next_challenge: serialize_challenge(Registry.next_challenge(challenge)),
              entry_count: TopicFinder.count(challenge, user: current_user),
            ),
          )
        end
      end
    end

    private

    def serialize_challenge(challenge)
      return nil if challenge.nil?
      serialize_data(challenge, ChallengeSerializer, root: false)
    end
  end
end
