# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::ChallengeStore do
  after { described_class.clear }

  def record(slug, title: "Title")
    { "title" => title, "slug" => slug, "starts_at" => "2026-06-07T14:00:00Z" }
  end

  describe ".upsert" do
    it "adds a new record and reports the change" do
      expect(described_class.upsert(record("week-1"))).to eq(true)
      expect(described_class.all.map { |r| r["slug"] }).to eq(["week-1"])
    end

    it "replaces an existing record by slug in place" do
      described_class.upsert(record("week-1", title: "Old"))
      expect(described_class.upsert(record("week-1", title: "New"))).to eq(true)

      expect(described_class.all.size).to eq(1)
      expect(described_class.all.first["title"]).to eq("New")
    end

    it "is a no-op when the record is unchanged" do
      described_class.upsert(record("week-1"))
      expect(described_class.upsert(record("week-1"))).to eq(false)
    end

    it "ignores records without a slug" do
      expect(described_class.upsert("title" => "No slug")).to eq(false)
      expect(described_class.all).to eq([])
    end
  end

  describe ".upsert_all" do
    it "reports true when any record changed and persists each" do
      expect(described_class.upsert_all([record("a"), record("b")])).to eq(true)
      expect(described_class.all.map { |r| r["slug"] }).to contain_exactly("a", "b")
    end

    it "reports false when nothing changed" do
      described_class.upsert_all([record("a"), record("b")])
      expect(described_class.upsert_all([record("a"), record("b")])).to eq(false)
    end
  end

  describe ".clear" do
    it "empties the store" do
      described_class.upsert(record("week-1"))
      described_class.clear
      expect(described_class.all).to eq([])
    end
  end
end
