# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::Registry do
  before { described_class.clear_cache }
  after { described_class.clear_cache }

  def set_registry(entries)
    SiteSetting.npn_weekly_challenge_registry_json =
      entries.is_a?(String) ? entries : entries.to_json
  end

  def entry(slug:, starts_at:, **overrides)
    {
      "wordpress_challenge_id" => "123",
      "title" => "A Challenge",
      "slug" => slug,
      "starts_at" => starts_at,
    }.merge(overrides.transform_keys(&:to_s))
  end

  describe ".all" do
    it "returns challenges sorted newest first" do
      set_registry(
        [
          entry(slug: "older", starts_at: "2026-05-01T00:00:00Z"),
          entry(slug: "newest", starts_at: "2026-06-01T00:00:00Z"),
          entry(slug: "oldest", starts_at: "2026-04-01T00:00:00Z"),
        ],
      )

      expect(described_class.all.map(&:slug)).to eq(%w[newest older oldest])
    end

    it "returns an empty array for malformed JSON without raising" do
      set_registry("[{not json")
      expect(described_class.all).to eq([])
    end

    it "returns an empty array when the JSON is not an array" do
      set_registry({ "slug" => "not-a-list" }.to_json)
      expect(described_class.all).to eq([])
    end

    it "skips invalid entries but keeps valid ones" do
      set_registry(
        [
          entry(slug: "valid", starts_at: "2026-06-01T00:00:00Z"),
          entry(slug: "no-start", starts_at: nil),
          entry(slug: "bad date", starts_at: "2026-06-01T00:00:00Z"),
          entry(slug: "no-title", starts_at: "2026-05-01T00:00:00Z", title: ""),
          "not even a hash",
        ],
      )

      expect(described_class.all.map(&:slug)).to eq(["valid"])
    end

    it "skips entries with duplicate slugs, keeping the first" do
      set_registry(
        [
          entry(slug: "dupe", starts_at: "2026-06-01T00:00:00Z", title: "First"),
          entry(slug: "dupe", starts_at: "2026-05-01T00:00:00Z", title: "Second"),
        ],
      )

      challenges = described_class.all
      expect(challenges.size).to eq(1)
      expect(challenges.first.title).to eq("First")
    end

    it "re-parses when the setting changes" do
      set_registry([entry(slug: "one", starts_at: "2026-06-01T00:00:00Z")])
      expect(described_class.all.map(&:slug)).to eq(["one"])

      set_registry([entry(slug: "two", starts_at: "2026-06-08T00:00:00Z")])
      expect(described_class.all.map(&:slug)).to eq(["two"])
    end

    it "normalizes optional fields" do
      set_registry(
        [
          entry(
            slug: "full",
            starts_at: "2026-06-01T00:00:00Z",
            wordpress_challenge_id: "0123",
            ends_at: "2026-06-08T00:00:00Z",
            url: "https://example.com/challenge",
          ),
          entry(
            slug: "bare",
            starts_at: "2026-05-01T00:00:00Z",
            wordpress_challenge_id: nil,
            url: "not a url",
          ),
        ],
      )

      full, bare = described_class.all
      expect(full.wordpress_challenge_id).to eq("123")
      expect(full.ends_at).to eq_time(Time.zone.parse("2026-06-08T00:00:00Z"))
      expect(full.url).to eq("https://example.com/challenge")
      expect(bare.wordpress_challenge_id).to be_nil
      expect(bare.ends_at).to be_nil
      expect(bare.url).to be_nil
    end
  end

  describe ".find_by_slug" do
    before { set_registry([entry(slug: "findable", starts_at: "2026-06-01T00:00:00Z")]) }

    it "finds a challenge case-insensitively" do
      expect(described_class.find_by_slug("FindAble").slug).to eq("findable")
    end

    it "returns nil for unknown or blank slugs" do
      expect(described_class.find_by_slug("missing")).to be_nil
      expect(described_class.find_by_slug("")).to be_nil
      expect(described_class.find_by_slug(nil)).to be_nil
    end
  end

  describe "adjacent challenges and windows" do
    before do
      set_registry(
        [
          entry(slug: "week-1", starts_at: "2026-05-18T00:00:00Z"),
          entry(slug: "week-2", starts_at: "2026-05-25T00:00:00Z", ends_at: "2026-05-30T00:00:00Z"),
          entry(slug: "week-3", starts_at: "2026-06-03T00:00:00Z", ends_at: "2026-06-10T00:00:00Z"),
        ],
      )
    end

    def challenge(slug)
      described_class.find_by_slug(slug)
    end

    it "navigates chronologically" do
      expect(described_class.next_challenge(challenge("week-1")).slug).to eq("week-2")
      expect(described_class.previous_challenge(challenge("week-2")).slug).to eq("week-1")
      expect(described_class.next_challenge(challenge("week-3"))).to be_nil
      expect(described_class.previous_challenge(challenge("week-1"))).to be_nil
    end

    it "ends the window at the next challenge's start, even when ends_at differs" do
      # week-2 has ends_at 2026-05-30 but week-3 starts 2026-06-03; the next
      # start wins so no topic can fall into two windows.
      expect(described_class.window_for(challenge("week-2"))).to eq(
        [Time.zone.parse("2026-05-25T00:00:00Z"), Time.zone.parse("2026-06-03T00:00:00Z")],
      )
    end

    it "falls back to ends_at for the latest challenge" do
      expect(described_class.window_for(challenge("week-3"))).to eq(
        [Time.zone.parse("2026-06-03T00:00:00Z"), Time.zone.parse("2026-06-10T00:00:00Z")],
      )
    end

    it "falls back to starts_at + 7 days when there is no next challenge or ends_at" do
      set_registry([entry(slug: "solo", starts_at: "2026-06-01T00:00:00Z")])

      expect(described_class.window_for(challenge("solo"))).to eq(
        [Time.zone.parse("2026-06-01T00:00:00Z"), Time.zone.parse("2026-06-08T00:00:00Z")],
      )
    end
  end
end
