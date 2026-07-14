# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::TopicFinder do
  fab!(:user)
  fab!(:tag) { Fabricate(:tag, name: "weekly-challenge") }
  fab!(:category)

  let(:challenge) do
    DiscourseNpnWeeklyChallenge::Challenge.from_hash(
      "wordpress_challenge_id" => "123",
      "title" => "Quiet Geometry",
      "slug" => "2026-06-01-quiet-geometry",
      "starts_at" => "2026-06-01T00:00:00Z",
      "ends_at" => "2026-06-08T00:00:00Z",
    )
  end

  before do
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_weekly_challenge_tag_name = "weekly-challenge"
    SiteSetting.npn_weekly_challenge_page_size = 30
    DiscourseNpnWeeklyChallenge::Registry.clear_cache
  end

  def create_field_topic(wp_id: "123", **attrs)
    topic = Fabricate(:topic, category: category, **attrs)
    topic.upsert_custom_fields(described_class::WP_CHALLENGE_ID_FIELD => wp_id)
    topic
  end

  def create_tagged_topic(created_at:, **attrs)
    Fabricate(:topic, category: category, tags: [tag], created_at: created_at, **attrs)
  end

  def found_ids(for_user: user)
    described_class.list(challenge, user: for_user).topics.map(&:id)
  end

  it "finds topics by custom field regardless of creation date" do
    topic = create_field_topic(created_at: 1.year.ago)
    expect(found_ids).to contain_exactly(topic.id)
  end

  it "does not match topics with a different challenge id" do
    create_field_topic(wp_id: "999")
    expect(found_ids).to be_empty
  end

  it "finds tagged topics inside the date window, excluding the exclusive end" do
    inside = create_tagged_topic(created_at: Time.zone.parse("2026-06-03T12:00:00Z"))
    at_start = create_tagged_topic(created_at: Time.zone.parse("2026-06-01T00:00:00Z"))
    create_tagged_topic(created_at: Time.zone.parse("2026-06-08T00:00:00Z"))
    create_tagged_topic(created_at: Time.zone.parse("2026-05-31T23:59:59Z"))

    expect(found_ids).to contain_exactly(inside.id, at_start.id)
  end

  it "ignores untagged topics inside the window" do
    Fabricate(:topic, category: category, created_at: Time.zone.parse("2026-06-03T00:00:00Z"))
    expect(found_ids).to be_empty
  end

  it "excludes the challenge's own announcement topic from its entries" do
    entry = create_tagged_topic(created_at: Time.zone.parse("2026-06-03T00:00:00Z"))
    # The announcement is tagged and posted inside the window, so it matches the
    # legacy path — but it is the prompt, not an entry.
    announcement = create_tagged_topic(created_at: Time.zone.parse("2026-06-01T14:00:00Z"))
    announcement.upsert_custom_fields(
      DiscourseNpnWeeklyChallenge::TopicPublisher::TOPIC_SLUG_FIELD => challenge.slug,
    )

    expect(found_ids).to contain_exactly(entry.id)
    expect(described_class.count(challenge, user: user)).to eq(1)
  end

  it "returns a topic matching both paths exactly once" do
    topic = create_tagged_topic(created_at: Time.zone.parse("2026-06-03T00:00:00Z"))
    topic.upsert_custom_fields(described_class::WP_CHALLENGE_ID_FIELD => "123")

    expect(found_ids).to eq([topic.id])
  end

  it "combines both paths in one result, newest first" do
    field_topic = create_field_topic(created_at: Time.zone.parse("2026-06-09T00:00:00Z"))
    tagged_topic = create_tagged_topic(created_at: Time.zone.parse("2026-06-02T00:00:00Z"))

    expect(found_ids).to eq([field_topic.id, tagged_topic.id])
  end

  it "uses the next challenge's start as the window end when the registry has one" do
    SiteSetting.npn_weekly_challenge_registry_json = [
      {
        wordpress_challenge_id: "123",
        title: "This",
        slug: challenge.slug,
        starts_at: "2026-06-01T00:00:00Z",
        ends_at: "2026-06-08T00:00:00Z",
      },
      {
        wordpress_challenge_id: "124",
        title: "Next",
        slug: "next-week",
        starts_at: "2026-06-05T00:00:00Z",
      },
    ].to_json
    registry_challenge = DiscourseNpnWeeklyChallenge::Registry.find_by_slug(challenge.slug)

    excluded = create_tagged_topic(created_at: Time.zone.parse("2026-06-06T00:00:00Z"))
    included = create_tagged_topic(created_at: Time.zone.parse("2026-06-04T00:00:00Z"))

    ids = described_class.list(registry_challenge, user: user).topics.map(&:id)
    expect(ids).to include(included.id)
    expect(ids).not_to include(excluded.id)
  end

  context "when the challenge has no wordpress id" do
    let(:challenge) do
      DiscourseNpnWeeklyChallenge::Challenge.from_hash(
        "title" => "Legacy Week",
        "slug" => "legacy-week",
        "starts_at" => "2026-06-01T00:00:00Z",
      )
    end

    it "still finds tagged topics by date" do
      topic = create_tagged_topic(created_at: Time.zone.parse("2026-06-02T00:00:00Z"))
      create_field_topic(wp_id: "123", created_at: Time.zone.parse("2026-07-01T00:00:00Z"))

      expect(found_ids).to contain_exactly(topic.id)
    end
  end

  it "returns nothing when the configured tag does not exist and there is no wordpress id" do
    legacy =
      DiscourseNpnWeeklyChallenge::Challenge.from_hash(
        "title" => "Legacy Week",
        "slug" => "legacy-week",
        "starts_at" => "2026-06-01T00:00:00Z",
      )
    SiteSetting.npn_weekly_challenge_tag_name = "missing-tag"
    create_tagged_topic(created_at: Time.zone.parse("2026-06-02T00:00:00Z"))

    expect(described_class.list(legacy, user: user).topics).to be_empty
  end

  context "with category scoping" do
    fab!(:other_category, :category)

    before { SiteSetting.npn_weekly_challenge_category_ids = category.id.to_s }

    it "excludes matching topics from other categories" do
      included = create_field_topic
      excluded = Fabricate(:topic, category: other_category)
      excluded.upsert_custom_fields(described_class::WP_CHALLENGE_ID_FIELD => "123")

      expect(found_ids).to contain_exactly(included.id)
    end
  end

  context "with permissions" do
    fab!(:group)
    fab!(:secure_category) { Fabricate(:private_category, group: group) }

    it "hides topics in secured categories from anonymous and unauthorized users" do
      topic = Fabricate(:topic, category: secure_category)
      topic.upsert_custom_fields(described_class::WP_CHALLENGE_ID_FIELD => "123")

      expect(found_ids(for_user: nil)).to be_empty
      expect(found_ids).to be_empty

      group.add(user)
      expect(found_ids).to contain_exactly(topic.id)
    end

    it "hides unlisted topics from regular users" do
      topic = create_field_topic
      topic.update_status("visible", false, Discourse.system_user)

      expect(found_ids).to be_empty
      expect(found_ids(for_user: Fabricate(:admin))).to contain_exactly(topic.id)
    end

    it "hides deleted topics" do
      topic = create_field_topic
      topic.trash!

      expect(found_ids).to be_empty
    end
  end

  describe ".count" do
    it "counts only what the user can see" do
      create_field_topic
      create_tagged_topic(created_at: Time.zone.parse("2026-06-02T00:00:00Z"))

      group = Fabricate(:group)
      secret = Fabricate(:topic, category: Fabricate(:private_category, group: group))
      secret.upsert_custom_fields(described_class::WP_CHALLENGE_ID_FIELD => "123")

      expect(described_class.count(challenge, user: user)).to eq(2)
      expect(described_class.count(challenge, user: nil)).to eq(2)
    end
  end

  describe "pagination" do
    it "limits results to the page size and offsets by page" do
      SiteSetting.npn_weekly_challenge_page_size = 5

      topics =
        7.times.map do |i|
          create_tagged_topic(created_at: Time.zone.parse("2026-06-02T00:00:00Z") + i.hours)
        end

      first_page = described_class.list(challenge, user: user, page: 0).topics
      second_page = described_class.list(challenge, user: user, page: 1).topics

      expect(first_page.size).to eq(5)
      expect(second_page.size).to eq(2)
      expect(first_page.map(&:id) & second_page.map(&:id)).to be_empty
      expect(first_page.first.id).to eq(topics.last.id)
    end
  end
end
