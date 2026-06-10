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
end
