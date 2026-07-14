# frozen_string_literal: true

require "rails_helper"

describe Jobs::NpnWeeklyChallengePublish do
  it "delegates to the publisher" do
    allow(DiscourseNpnWeeklyChallenge::TopicPublisher).to receive(:publish_due)

    described_class.new.execute(nil)

    expect(DiscourseNpnWeeklyChallenge::TopicPublisher).to have_received(:publish_due)
  end

  it "publishes nothing when auto-publishing is disabled" do
    SiteSetting.npn_weekly_challenges_enabled = true
    SiteSetting.npn_weekly_challenge_auto_topic_enabled = false

    expect { described_class.new.execute(nil) }.not_to change { Topic.count }
  end
end
