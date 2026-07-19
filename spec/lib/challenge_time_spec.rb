# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::ChallengeTime do
  describe ".parse_start" do
    it "treats a winter date as midnight PST (08:00 UTC)" do
      expect(described_class.parse_start("1/25/26 - 1/31/26")).to eq_time(
        Time.utc(2026, 1, 25, 8, 0, 0),
      )
    end

    it "treats a summer date as midnight PDT (07:00 UTC)" do
      expect(described_class.parse_start("6/7/26 - 6/13/26")).to eq_time(
        Time.utc(2026, 6, 7, 7, 0, 0),
      )
    end

    it "accepts a single date without a range" do
      expect(described_class.parse_start("6/7/26")).to eq_time(Time.utc(2026, 6, 7, 7, 0, 0))
    end

    it "returns nil for blank or unparseable input" do
      expect(described_class.parse_start("")).to be_nil
      expect(described_class.parse_start(nil)).to be_nil
      expect(described_class.parse_start("not a date")).to be_nil
    end
  end

  describe ".default_end" do
    it "is the same local time one week later, DST-aware across the spring change" do
      # DST flips at 02:00 local, so midnight on the 3/8 change day itself is
      # still PST (08:00Z); the week containing the change ends at the next
      # midnight in PDT (07:00Z) — 6 days and 23 hours apart, not 7×24.
      start = described_class.parse_start("3/8/26")
      expect(start).to eq_time(Time.utc(2026, 3, 8, 8, 0, 0))
      expect(described_class.default_end(start)).to eq_time(Time.utc(2026, 3, 15, 7, 0, 0))
    end

    it "returns nil when given nil" do
      expect(described_class.default_end(nil)).to be_nil
    end
  end

  describe ".display_range" do
    # ends_at is the exclusive end of the window — the moment the next challenge
    # starts — so the last day people can enter is the day before it. This is
    # the real 2026-07-12 challenge, which the moderator announces as "July 12–18".
    it "prints the last day people can enter, not the exclusive window end" do
      expect(
        described_class.display_range(
          Time.zone.parse("2026-07-12T14:00:00Z"),
          Time.zone.parse("2026-07-19T14:00:00Z"),
        ),
      ).to eq("July 12–18")
    end

    it "spells out the month again when the week crosses a boundary" do
      expect(
        described_class.display_range(
          Time.zone.parse("2026-07-26T14:00:00Z"),
          Time.zone.parse("2026-08-02T14:00:00Z"),
        ),
      ).to eq("July 26–August 1")
    end

    it "assumes a one-week window when there is no ends_at" do
      expect(described_class.display_range(Time.zone.parse("2026-07-12T14:00:00Z"))).to eq(
        "July 12–18",
      )
    end

    it "returns nil without a start" do
      expect(described_class.display_range(nil)).to be_nil
    end
  end

  describe ".parse_mdy" do
    it "expands two-digit years into the 2000s" do
      expect(described_class.parse_mdy("12/31/23")).to eq(Date.new(2023, 12, 31))
    end

    it "accepts four-digit years and zero padding" do
      expect(described_class.parse_mdy("01/06/2024")).to eq(Date.new(2024, 1, 6))
    end

    it "returns nil for nonsense" do
      expect(described_class.parse_mdy("13/40/99 nope")).to be_nil
    end
  end
end
