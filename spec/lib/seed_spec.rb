# frozen_string_literal: true

require "rails_helper"

# Guards the shipped backfill (config/weekly_challenge_seed.json) against
# corruption or a bad regeneration. Legacy entries are matched purely by date
# window, so a malformed or out-of-order seed silently misattributes topics —
# these checks fail loudly instead.
describe "weekly challenge seed file" do # rubocop:disable RSpec/DescribeClass
  let(:raw) { JSON.parse(File.read(DiscourseNpnWeeklyChallenge::Registry::SEED_PATH)) }
  let(:challenges) { DiscourseNpnWeeklyChallenge::Registry.send(:build, raw) }

  it "is a non-empty JSON array" do
    expect(raw).to be_an(Array)
    expect(raw.size).to be > 300
  end

  it "every entry parses into a Challenge" do
    expect(challenges.size).to eq(raw.size)
  end

  it "has unique slugs" do
    slugs = challenges.map(&:slug)
    expect(slugs.uniq.size).to eq(slugs.size)
  end

  it "has a strictly increasing weekly timeline with no duplicate weeks" do
    starts = challenges.map(&:starts_at).sort
    expect(starts.uniq.size).to eq(starts.size)
    starts.each_cons(2) { |a, b| expect(b).to be > a }
  end

  it "anchors every start at 08:00 America/Denver" do
    zone = DiscourseNpnWeeklyChallenge::ChallengeTime.zone
    offenders =
      challenges.reject do |c|
        local = c.starts_at.in_time_zone(zone)
        local.hour == 8 && local.min.zero?
      end
    expect(offenders.map(&:slug)).to eq([])
  end
end
