# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::ChallengesController do
  fab!(:user)
  fab!(:tag) { Fabricate(:tag, name: "weekly-challenge") }
  fab!(:category)

  let(:registry) do
    [
      {
        wordpress_challenge_id: "124",
        title: "Light and Shadow",
        slug: "2026-06-08-light-and-shadow",
        starts_at: "2026-06-08T00:00:00Z",
        ends_at: "2026-06-15T00:00:00Z",
        url: "https://example.com/weekly-challenge/light-and-shadow",
      },
      {
        wordpress_challenge_id: "123",
        title: "Quiet Geometry",
        slug: "2026-06-01-quiet-geometry",
        starts_at: "2026-06-01T00:00:00Z",
        ends_at: "2026-06-08T00:00:00Z",
      },
    ]
  end

  before do
    SiteSetting.npn_weekly_challenges_enabled = true
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_weekly_challenge_tag_name = "weekly-challenge"
    SiteSetting.npn_weekly_challenge_registry_json = registry.to_json
    DiscourseNpnWeeklyChallenge::Registry.clear_cache
    # Drive these specs purely from the registry setting: neutralize the shipped
    # seed and the WordPress store so assertions see only the fixture challenges.
    allow(DiscourseNpnWeeklyChallenge::Registry).to receive(:seed_challenges).and_return([])
    allow(DiscourseNpnWeeklyChallenge::ChallengeStore).to receive(:all).and_return([])
  end

  describe "#index" do
    it "returns 404 when the plugin is disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false
      get "/weekly-challenges.json"
      expect(response.status).to eq(404)
    end

    it "lists challenges newest first for anonymous users" do
      get "/weekly-challenges.json"

      expect(response.status).to eq(200)
      challenges = response.parsed_body["challenges"]
      expect(challenges.map { |c| c["slug"] }).to eq(
        %w[2026-06-08-light-and-shadow 2026-06-01-quiet-geometry],
      )
      expect(challenges.first["title"]).to eq("Light and Shadow")
      expect(challenges.first["url"]).to eq("https://example.com/weekly-challenge/light-and-shadow")
    end

    it "returns an empty list for an invalid registry" do
      SiteSetting.npn_weekly_challenge_registry_json = "{nope"
      get "/weekly-challenges.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["challenges"]).to eq([])
    end

    it "renders the Ember shell for HTML requests" do
      get "/weekly-challenges"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end
  end

  describe "#show" do
    fab!(:field_topic) { Fabricate(:topic, category: category) }
    fab!(:tagged_topic) do
      Fabricate(
        :topic,
        category: category,
        tags: [Tag.find_by(name: "weekly-challenge")],
        created_at: Time.zone.parse("2026-06-03T00:00:00Z"),
      )
    end

    before { field_topic.upsert_custom_fields("npn_wordpress_challenge_id" => "123") }

    it "returns the challenge with entries from both match paths" do
      get "/weekly-challenges/2026-06-01-quiet-geometry.json"

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["challenge"]["slug"]).to eq("2026-06-01-quiet-geometry")
      expect(body["entry_count"]).to eq(2)
      expect(body["topic_list"]["topics"].map { |t| t["id"] }).to contain_exactly(
        field_topic.id,
        tagged_topic.id,
      )
    end

    it "sideloads poster users at the payload root" do
      get "/weekly-challenges/2026-06-01-quiet-geometry.json"

      expect(response.parsed_body["users"].map { |u| u["id"] }).to include(field_topic.user_id)
    end

    it "rejects an out-of-range page param" do
      get "/weekly-challenges/2026-06-01-quiet-geometry.json?page=99999999999999999999"
      expect(response.status).to eq(400)
    end

    it "includes previous and next challenge navigation" do
      get "/weekly-challenges/2026-06-01-quiet-geometry.json"
      body = response.parsed_body
      expect(body["previous_challenge"]).to be_nil
      expect(body["next_challenge"]["slug"]).to eq("2026-06-08-light-and-shadow")

      get "/weekly-challenges/2026-06-08-light-and-shadow.json"
      body = response.parsed_body
      expect(body["previous_challenge"]["slug"]).to eq("2026-06-01-quiet-geometry")
      expect(body["next_challenge"]).to be_nil
    end

    it "hides topics the user cannot see and keeps the count consistent" do
      group = Fabricate(:group)
      secret_topic = Fabricate(:topic, category: Fabricate(:private_category, group: group))
      secret_topic.upsert_custom_fields("npn_wordpress_challenge_id" => "123")

      get "/weekly-challenges/2026-06-01-quiet-geometry.json"
      body = response.parsed_body
      expect(body["entry_count"]).to eq(2)
      expect(body["topic_list"]["topics"].map { |t| t["id"] }).not_to include(secret_topic.id)

      group.add(user)
      sign_in(user)
      get "/weekly-challenges/2026-06-01-quiet-geometry.json"
      body = response.parsed_body
      expect(body["entry_count"]).to eq(3)
      expect(body["topic_list"]["topics"].map { |t| t["id"] }).to include(secret_topic.id)
    end

    it "paginates" do
      SiteSetting.npn_weekly_challenge_page_size = 5
      6.times do |i|
        Fabricate(
          :topic,
          category: category,
          tags: [Tag.find_by(name: "weekly-challenge")],
          created_at: Time.zone.parse("2026-06-02T00:00:00Z") + i.hours,
        )
      end

      get "/weekly-challenges/2026-06-01-quiet-geometry.json"
      expect(response.parsed_body["topic_list"]["topics"].size).to eq(5)

      get "/weekly-challenges/2026-06-01-quiet-geometry.json?page=1"
      page_two = response.parsed_body["topic_list"]["topics"]
      expect(page_two.size).to eq(3)
    end

    it "returns an empty list for a challenge with no entries" do
      get "/weekly-challenges/2026-06-08-light-and-shadow.json"

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["entry_count"]).to eq(0)
      expect(body["topic_list"]["topics"]).to eq([])
    end

    it "returns 404 for an unknown slug" do
      get "/weekly-challenges/not-a-challenge.json"
      expect(response.status).to eq(404)
    end

    it "returns 404 when the plugin is disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false
      get "/weekly-challenges/2026-06-01-quiet-geometry.json"
      expect(response.status).to eq(404)
    end

    it "renders the Ember shell for HTML requests" do
      get "/weekly-challenges/2026-06-01-quiet-geometry"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end
  end
end
