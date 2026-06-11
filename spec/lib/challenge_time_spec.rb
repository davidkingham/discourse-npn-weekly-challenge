# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::ChallengeTime do
  describe ".parse_start" do
    it "treats a winter date as 08:00 MST (15:00 UTC)" do
      expect(described_class.parse_start("1/25/26 - 1/31/26")).to eq_time(
        Time.utc(2026, 1, 25, 15, 0, 0),
      )
    end

    it "treats a summer date as 08:00 MDT (14:00 UTC)" do
      expect(described_class.parse_start("6/7/26 - 6/13/26")).to eq_time(
        Time.utc(2026, 6, 7, 14, 0, 0),
      )
    end

    it "accepts a single date without a range" do
      expect(described_class.parse_start("6/7/26")).to eq_time(Time.utc(2026, 6, 7, 14, 0, 0))
    end

    it "returns nil for blank or unparseable input" do
      expect(described_class.parse_start("")).to be_nil
      expect(described_class.parse_start(nil)).to be_nil
      expect(described_class.parse_start("not a date")).to be_nil
    end
  end

  describe ".default_end" do
    it "is the same local time one week later, DST-aware across the spring change" do
      # 3/1/26 is MST (15:00Z); a week later is past the 3/8 DST change, so the
      # next 08:00 local is MDT (14:00Z) — 6 days and 23 hours apart, not 7×24.
      start = described_class.parse_start("3/1/26")
      expect(described_class.default_end(start)).to eq_time(Time.utc(2026, 3, 8, 14, 0, 0))
    end

    it "returns nil when given nil" do
      expect(described_class.default_end(nil)).to be_nil
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
