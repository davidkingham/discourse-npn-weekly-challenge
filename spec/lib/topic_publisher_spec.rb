# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::TopicPublisher do
  fab!(:category)
  fab!(:author) { Fabricate(:user, username: "challenge-bot") }
  fab!(:tag) { Fabricate(:tag, name: "weekly-challenge") }

  let(:registry) do
    [
      {
        title: "Quiet Geometry",
        slug: "2026-06-01-quiet-geometry",
        starts_at: "2026-06-01T14:00:00Z",
        ends_at: "2026-06-08T14:00:00Z",
      },
      {
        title: "Geological Wonders",
        slug: "2026-06-08-geological-wonders",
        starts_at: "2026-06-08T14:00:00Z",
        ends_at: "2026-06-15T14:00:00Z",
        description: "Photograph striking geological formations.",
      },
    ]
  end

  before do
    SiteSetting.npn_weekly_challenges_enabled = true
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_weekly_challenge_auto_topic_enabled = true
    SiteSetting.npn_weekly_challenge_auto_topic_category = category.id.to_s
    SiteSetting.npn_weekly_challenge_auto_topic_author = "challenge-bot"
    SiteSetting.npn_weekly_challenge_registry_json = registry.to_json
    DiscourseNpnWeeklyChallenge::Registry.clear_cache
    allow(DiscourseNpnWeeklyChallenge::Registry).to receive(:seed_challenges).and_return([])
    allow(DiscourseNpnWeeklyChallenge::ChallengeStore).to receive(:all).and_return([])

    # An hour after the second challenge opens.
    freeze_time Time.zone.parse("2026-06-08T15:00:00Z")
  end

  describe ".publish_due" do
    it "creates the topic for the challenge that just started" do
      topic = described_class.publish_due

      expect(topic).to be_present
      expect(topic.title).to eq("Weekly Challenge: Geological Wonders")
      expect(topic.category_id).to eq(category.id)
      expect(topic.user_id).to eq(author.id)
      expect(topic.custom_fields[described_class::TOPIC_SLUG_FIELD]).to eq(
        "2026-06-08-geological-wonders",
      )
    end

    it "renders the body from the template" do
      raw = described_class.publish_due.first_post.raw

      expect(raw).to include("June 8–14")
      expect(raw).to include("Photograph striking geological formations.")
      expect(raw).to include("[Post to this week's challenge](/submit?type=weekly_challenge)")
      expect(raw).to include("/weekly-challenges/2026-06-08-geological-wonders")
    end

    it "pins the new topic and unpins the challenge it replaces" do
      previous =
        described_class.publish(
          DiscourseNpnWeeklyChallenge::Registry.find_by_slug("2026-06-01-quiet-geometry"),
        )
      expect(previous.reload.pinned_at).to be_present

      topic = described_class.publish_due

      expect(topic.reload.pinned_at).to be_present
      expect(topic.pinned_globally).to eq(false)
      expect(previous.reload.pinned_at).to be_nil
    end

    it "is idempotent — a second run publishes nothing" do
      expect { described_class.publish_due }.to change { Topic.count }.by(1)
      expect { described_class.publish_due }.not_to change { Topic.count }
    end

    # The rail that matters most: the registry holds hundreds of past
    # challenges, and publishing them all would be unrecoverable.
    it "never backfills a challenge that started long ago" do
      freeze_time Time.zone.parse("2026-06-12T15:00:00Z") # four days in

      expect { described_class.publish_due }.not_to change { Topic.count }
      expect(described_class.publish_due).to be_nil
    end

    it "does nothing when auto-publishing is disabled" do
      SiteSetting.npn_weekly_challenge_auto_topic_enabled = false

      expect { described_class.publish_due }.not_to change { Topic.count }
    end

    it "does nothing when the plugin is disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false

      expect { described_class.publish_due }.not_to change { Topic.count }
    end

    it "refuses to publish without a destination category" do
      SiteSetting.npn_weekly_challenge_auto_topic_category = ""

      expect { described_class.publish_due }.not_to change { Topic.count }
      expect(described_class.publish_due).to be_nil
    end

    it "applies the configured tags" do
      SiteSetting.npn_weekly_challenge_auto_topic_tags = "weekly-challenge"

      expect(described_class.publish_due.tags.map(&:name)).to eq(["weekly-challenge"])
    end

    # The setting validates the username on write, so this can only happen when
    # the configured user is deleted after the fact — hence the stub.
    it "falls back to the system user when the author no longer exists" do
      allow(SiteSetting).to receive(:npn_weekly_challenge_auto_topic_author).and_return(
        "someone-who-left",
      )

      expect(described_class.publish_due.user_id).to eq(Discourse.system_user.id)
    end

    it "disambiguates a title already used by an older challenge" do
      Fabricate(:topic, title: "Weekly Challenge: Geological Wonders", category: category)

      expect(described_class.publish_due.title).to eq(
        "Weekly Challenge: Geological Wonders (June 8–14)",
      )
    end

    it "logs and publishes nothing when the body template has a bad placeholder" do
      SiteSetting.npn_weekly_challenge_auto_topic_body = "%{not_a_placeholder}"

      expect { described_class.publish_due }.not_to change { Topic.count }
    end
  end
end
