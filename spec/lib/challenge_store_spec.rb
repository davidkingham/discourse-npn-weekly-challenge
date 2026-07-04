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

    it "updates in place by WordPress id when an edited title/date changes the slug" do
      described_class.upsert(
        record("2026-06-07-old-title", title: "Old Title").merge("wordpress_challenge_id" => "42"),
      )

      # Same WP post, title edited → new slug. Must replace, not duplicate.
      changed =
        described_class.upsert(
          record("2026-06-07-new-title", title: "New Title").merge(
            "wordpress_challenge_id" => "42",
          ),
        )

      expect(changed).to eq(true)
      expect(described_class.all.size).to eq(1)
      expect(described_class.all.first["title"]).to eq("New Title")
      expect(described_class.all.first["slug"]).to eq("2026-06-07-new-title")
    end

    it "keeps records with different WordPress ids separate" do
      described_class.upsert(record("week-1").merge("wordpress_challenge_id" => "1"))
      described_class.upsert(record("week-2").merge("wordpress_challenge_id" => "2"))
      expect(described_class.all.size).to eq(2)
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
