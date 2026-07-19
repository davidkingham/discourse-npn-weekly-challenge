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
        description: "Find calm, geometric order in nature.",
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

    it "flags the most recently started challenge as current" do
      get "/weekly-challenges.json"

      expect(response.parsed_body["current_slug"]).to eq("2026-06-08-light-and-shadow")
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

  describe "#current" do
    it "redirects to the most recently started challenge" do
      get "/weekly-challenges/current"

      expect(response).to redirect_to("/weekly-challenges/2026-06-08-light-and-shadow")
      expect(response.status).to eq(302)
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "wins over the :slug route" do
      # "current" matches the slug constraint, so the action must take priority.
      get "/weekly-challenges/current"
      expect(response).to redirect_to("/weekly-challenges/2026-06-08-light-and-shadow")
    end

    it "falls back to the archive index when nothing has started" do
      SiteSetting.npn_weekly_challenge_registry_json = [
        {
          title: "Upcoming Week",
          slug: "2999-01-06-upcoming-week",
          starts_at: "2999-01-06T00:00:00Z",
        },
      ].to_json
      DiscourseNpnWeeklyChallenge::Registry.clear_cache

      get "/weekly-challenges/current"
      expect(response).to redirect_to("/weekly-challenges")
    end

    it "returns 404 when the plugin is disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false
      get "/weekly-challenges/current"
      expect(response.status).to eq(404)
    end
  end

  describe "#upcoming" do
    let(:registry) do
      [
        {
          title: "Started Week",
          slug: "2026-06-01-started-week",
          starts_at: "2026-06-01T00:00:00Z",
        },
        { title: "Later Week", slug: "2999-01-13-later-week", starts_at: "2999-01-13T00:00:00Z" },
        {
          title: "Sooner Week",
          slug: "2999-01-06-sooner-week",
          starts_at: "2999-01-06T00:00:00Z",
          ends_at: "2999-01-13T00:00:00Z",
          description: "Photograph the quiet hour before sunrise.",
        },
      ]
    end

    it "lists only unstarted challenges, soonest first" do
      get "/weekly-challenges/upcoming.json"

      expect(response.status).to eq(200)
      challenges = response.parsed_body["challenges"]
      expect(challenges.map { |c| c["slug"] }).to eq(
        %w[2999-01-06-sooner-week 2999-01-13-later-week],
      )
    end

    it "includes the title, dates and description each row renders" do
      get "/weekly-challenges/upcoming.json"

      challenge = response.parsed_body["challenges"].first
      expect(challenge["title"]).to eq("Sooner Week")
      expect(challenge["starts_at"]).to be_present
      expect(challenge["ends_at"]).to be_present
      expect(challenge["description"]).to eq("Photograph the quiet hour before sunrise.")
    end

    it "wins over the :slug route" do
      # "upcoming" matches the slug constraint, so the action must take priority.
      get "/weekly-challenges/upcoming"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end

    it "returns an empty list when every challenge has started" do
      SiteSetting.npn_weekly_challenge_registry_json = [
        {
          title: "Started Week",
          slug: "2026-06-01-started-week",
          starts_at: "2026-06-01T00:00:00Z",
        },
      ].to_json
      DiscourseNpnWeeklyChallenge::Registry.clear_cache

      get "/weekly-challenges/upcoming.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["challenges"]).to eq([])
    end

    it "returns 404 when the plugin is disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false
      get "/weekly-challenges/upcoming.json"
      expect(response.status).to eq(404)
    end
  end

  describe "#announcements" do
    fab!(:announcement_topic) do
      Fabricate(:topic, category: category, title: "Weekly Challenge: Light and Shadow")
    end
    fab!(:announcement_post) do
      Fabricate(:post, topic: announcement_topic, raw: "Create images of light and shadow.")
    end
    fab!(:entry_topic) do
      Fabricate(:topic, category: category, tags: [Tag.find_by(name: "weekly-challenge")])
    end

    before do
      announcement_topic.upsert_custom_fields(
        DiscourseNpnWeeklyChallenge::TopicPublisher::TOPIC_SLUG_FIELD =>
          "2026-06-08-light-and-shadow",
      )
    end

    it "returns an RSS feed of announcement topics only, with the first post as content" do
      get "/weekly-challenges/announcements.rss"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("application/rss+xml")
      expect(response.body).to include(announcement_topic.title)
      expect(response.body).to include("Create images of light and shadow.")
      expect(response.body).to include(announcement_topic.url)
      expect(response.body).not_to include(entry_topic.title)
    end

    it "excludes announcements anonymous users cannot see, even for a signed-in viewer" do
      group = Fabricate(:group)
      secret_topic =
        Fabricate(
          :topic,
          category: Fabricate(:private_category, group: group),
          title: "Weekly Challenge: Hidden Week",
        )
      Fabricate(:post, topic: secret_topic)
      secret_topic.upsert_custom_fields(
        DiscourseNpnWeeklyChallenge::TopicPublisher::TOPIC_SLUG_FIELD => "2026-06-15-hidden-week",
      )

      group.add(user)
      sign_in(user)
      get "/weekly-challenges/announcements.rss"

      expect(response.status).to eq(200)
      expect(response.body).to include(announcement_topic.title)
      expect(response.body).not_to include(secret_topic.title)
    end

    it "returns 404 when the plugin is disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false
      get "/weekly-challenges/announcements.rss"
      expect(response.status).to eq(404)
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
      expect(body["challenge"]["description"]).to eq("Find calm, geometric order in nature.")
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

  describe "upcoming challenges that have not started" do
    before do
      SiteSetting.npn_weekly_challenge_registry_json = [
        {
          title: "Started Week",
          slug: "2026-06-01-started-week",
          starts_at: "2026-06-01T00:00:00Z",
        },
        {
          title: "Upcoming Week",
          slug: "2999-01-06-upcoming-week",
          starts_at: "2999-01-06T00:00:00Z",
        },
      ].to_json
      DiscourseNpnWeeklyChallenge::Registry.clear_cache
    end

    it "omits them from the challenge list" do
      get "/weekly-challenges.json"
      expect(response.parsed_body["challenges"].map { |c| c["slug"] }).to eq(
        %w[2026-06-01-started-week],
      )
    end

    it "never treats an unstarted challenge as current" do
      get "/weekly-challenges.json"
      expect(response.parsed_body["current_slug"]).to eq("2026-06-01-started-week")
    end

    it "returns 404 on direct access" do
      get "/weekly-challenges/2999-01-06-upcoming-week.json"
      expect(response.status).to eq(404)
    end

    it "does not link forward to one from the current challenge" do
      get "/weekly-challenges/2026-06-01-started-week.json"
      expect(response.parsed_body["next_challenge"]).to be_nil
    end
  end
end
