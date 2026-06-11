# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  class ChallengeSerializer < ApplicationSerializer
    attributes :wordpress_challenge_id, :title, :slug, :starts_at, :ends_at, :url, :description
  end
end
