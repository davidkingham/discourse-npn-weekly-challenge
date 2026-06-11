# frozen_string_literal: true

require "rails_helper"

describe "Weekly challenges" do
  fab!(:tag) { Fabricate(:tag, name: "weekly-challenge") }

  fab!(:entry_topic) do
    Fabricate(
      :topic,
      title: "My geometric macro shot",
      tags: [tag],
      created_at: Time.zone.parse("2026-06-03T00:00:00Z"),
    )
  end

  fab!(:entry_post) { Fabricate(:post, topic: entry_topic) }

  # Created before either challenge's window starts, so it matches neither.
  fab!(:other_topic) do
    Fabricate(
      :topic,
      title: "Posted outside the window",
      tags: [tag],
      created_at: Time.zone.parse("2026-03-01T00:00:00Z"),
    )
  end

  fab!(:other_post) { Fabricate(:post, topic: other_topic) }

  let(:weekly_challenges_page) { PageObjects::Pages::WeeklyChallenges.new }

  before do
    SiteSetting.npn_weekly_challenges_enabled = true
    SiteSetting.tagging_enabled = true
    SiteSetting.npn_weekly_challenge_tag_name = "weekly-challenge"
    SiteSetting.npn_weekly_challenge_registry_json = [
      {
        wordpress_challenge_id: "123",
        title: "Quiet Geometry",
        slug: "2026-06-01-quiet-geometry",
        starts_at: "2026-06-01T00:00:00Z",
        ends_at: "2026-06-08T00:00:00Z",
      },
      {
        wordpress_challenge_id: "122",
        title: "Empty Week",
        slug: "2026-04-01-empty-week",
        starts_at: "2026-04-01T00:00:00Z",
        ends_at: "2026-04-08T00:00:00Z",
      },
    ].to_json
    DiscourseNpnWeeklyChallenge::Registry.clear_cache
    # Drive the archive purely from the fixture registry: neutralize the shipped
    # seed and the WordPress store so adjacency and listing assertions are stable.
    allow(DiscourseNpnWeeklyChallenge::Registry).to receive(:seed_challenges).and_return([])
    allow(DiscourseNpnWeeklyChallenge::ChallengeStore).to receive(:all).and_return([])
  end

  it "browses from the challenge list to a challenge's entries" do
    weekly_challenges_page.visit_index

    expect(weekly_challenges_page).to have_challenge_listed("Quiet Geometry")

    weekly_challenges_page.open_challenge("Quiet Geometry")

    expect(weekly_challenges_page).to have_challenge_title("Quiet Geometry")
    expect(weekly_challenges_page).to have_entry_topic("My geometric macro shot")
    expect(weekly_challenges_page).to have_no_entry_topic("Posted outside the window")

    # Adjacent-challenge navigation must not carry the previous challenge's
    # entries over (the component is reused across the transition).
    weekly_challenges_page.go_to_previous_challenge

    expect(weekly_challenges_page).to have_challenge_title("Empty Week")
    expect(weekly_challenges_page).to have_no_entry_topic("My geometric macro shot")
    expect(weekly_challenges_page).to have_empty_state
  end

  it "shows an empty state for a challenge with no entries" do
    weekly_challenges_page.visit_challenge("2026-04-01-empty-week")

    expect(weekly_challenges_page).to have_challenge_title("Empty Week")
    expect(weekly_challenges_page).to have_empty_state
  end

  describe "challenge selector on the tag page" do
    fab!(:other_tag) { Fabricate(:tag, name: "landscape") }

    it "lists challenges newest first and navigates to the chosen challenge" do
      weekly_challenges_page.visit_tag("weekly-challenge")

      expect(weekly_challenges_page).to have_challenge_selector
      # Date text depends on the browser timezone, so match title + dash only.
      expect(weekly_challenges_page.challenge_selector_options).to match(
        [a_string_matching(/\AQuiet Geometry – /), a_string_matching(/\AEmpty Week – /)],
      )

      weekly_challenges_page.select_challenge("Quiet Geometry")

      expect(weekly_challenges_page).to have_challenge_title("Quiet Geometry")
      expect(page).to have_current_path("/weekly-challenges/2026-06-01-quiet-geometry")
    end

    it "does not show the selector on unrelated tag pages" do
      weekly_challenges_page.visit_tag("landscape")

      expect(weekly_challenges_page).to have_tag_page
      expect(weekly_challenges_page).to have_no_challenge_selector
    end

    it "does not show the selector on tag intersection pages" do
      weekly_challenges_page.visit_tag_intersection("weekly-challenge", "landscape")

      expect(weekly_challenges_page).to have_tag_page
      expect(weekly_challenges_page).to have_no_challenge_selector
    end

    it "does not show the selector when the plugin is disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false

      weekly_challenges_page.visit_tag("weekly-challenge")

      expect(weekly_challenges_page).to have_tag_page
      expect(weekly_challenges_page).to have_no_challenge_selector
    end

    it "does not show the selector when no challenges are published" do
      SiteSetting.npn_weekly_challenge_registry_json = "[]"

      weekly_challenges_page.visit_tag("weekly-challenge")

      expect(weekly_challenges_page).to have_tag_page
      expect(weekly_challenges_page).to have_no_challenge_selector
    end
  end
end
