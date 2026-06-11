# frozen_string_literal: true

# One-off generator for config/weekly_challenge_seed.json. NOT loaded at runtime.
#
# Input (not committed — member-gated community content): the raw markdown source
# of the "Past and future challenges" topic, saved to RAW. Grab it logged in from
# /raw/<topic_id>. WP reconciliation reads a cached /wp-json/wp/v2/weekly-challenge
# dump at WP. Stdlib only (no Rails); US DST computed by rule. Prints a validation
# report; re-run and eyeball the report before committing a regenerated seed.
require "json"
require "date"

ROOT = File.expand_path("../../..", __dir__) # discourse repo root
RAW  = File.join(ROOT, "tmp/wc-403-raw.md")
WP   = "/tmp/wc-challenges.json"
OUT  = File.expand_path("../config/weekly_challenge_seed.json", __dir__)
COMMUNITY_BASE = "https://community.naturephotographers.network"

MONTHS = {
  "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4, "may" => 5, "jun" => 6,
  "jul" => 7, "aug" => 8, "sep" => 9, "oct" => 10, "nov" => 11, "dec" => 12
}

# 8:00 local America/Denver for the given Date, as UTC. MDT (UTC-6) from the 2nd
# Sunday of March to the 1st Sunday of November, otherwise MST (UTC-7).
def denver_8am_utc(date)
  y = date.year
  march = (1..31).map { |d| Date.new(y, 3, d) }.select(&:sunday?)[1]
  nov   = (1..30).map { |d| Date.new(y, 11, d) }.select(&:sunday?)[0]
  dst = date >= march && date < nov
  Time.utc(y, date.month, date.day, 8 + (dst ? 6 : 7), 0, 0)
end

def slugify(str)
  str.downcase.gsub("&", " and ").gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
end

# "12/14/25" -> Date. Two-digit year -> 2000s.
def parse_md_y(str)
  m, d, y = str.strip.split("/").map(&:to_i)
  y += 2000 if y < 100
  Date.new(y, m, d)
end

# "Jan 4" / "Apr 26" with an explicit year -> Date.
def parse_mon_day(str, year)
  mon, day = str.strip.split(/\s+/)
  Date.new(year, MONTHS.fetch(mon[0, 3].downcase), day.to_i)
end

entries = []
lines = File.readlines(RAW, chomp: true)

current_year = nil # nil = pre-details (2026 top table)
lines.each do |line|
  if (m = line.match(/\[details="(\d{4})"\]/))
    current_year = m[1].to_i
    next
  end

  if current_year.nil?
    # Format A: | Mon D–D | Title | Description |  (3 data columns, 2026)
    next unless line.start_with?("|")
    cells = line.split("|").map(&:strip).reject(&:empty?)
    next if cells.size != 3
    next if cells[0].downcase == "dates" || cells[0].start_with?("-")
    start_token = cells[0].split(/[–-]/).first
    entries << {
      number: nil, title: cells[1].strip,
      start_date: parse_mon_day(start_token, 2026), url: nil
    }
  elsif line.start_with?("|")
    # Format B: |Dates | Challenge | [num](/tag/..) | [desc](url)|  (4 columns)
    cells = line.split("|").map(&:strip).reject(&:empty?)
    next if cells.size < 4
    next if cells[0].downcase == "dates" || cells[0].start_with?("-")
    start_token = cells[0].split(/[–-]/).first
    num = cells[2][/\[(\d+)\]/, 1]
    url = cells[3][/\((https?:\/\/[^)]+|\/t\/[^)]+)\)/, 1]
    entries << {
      number: num&.to_i, title: cells[1].strip,
      start_date: parse_md_y(start_token), url: url
    }
  elsif line.start_with?("[#")
    # Format C: [# 1069 (12/11/22 - 12/31/22) Title](/tags/..) - [description](url)
    m = line.match(/\[#\s*(\d+)\s*\(([^)]+)\)\s*([^\]]*)\]/)
    next unless m
    num = m[1].to_i
    start_token = m[2].split(/[–-]/).first
    title = m[3].strip
    url = line[/-\s*\[[Dd]escription\]\((https?:\/\/[^)]+|\/t\/[^)]+)\)/, 1]
    entries << {
      number: num, title: title, start_date: parse_md_y(start_token), url: url
    }
  end
end

# Dedup by week (start_date); first occurrence wins. Reports dups.
seen = {}
dups = []
deduped = entries.reject do |e|
  key = e[:start_date]
  if seen[key]
    dups << e
    true
  else
    seen[key] = e
    false
  end
end

deduped.sort_by! { |e| e[:start_date] }

# Backfill numbers for the unnumbered 2026 rows by continuing the sequence.
# (Source lists them in the top table without numbers; cadence is weekly and
# ordering is clean, so number = previous + 1.)
assigned = []
deduped.each_with_index do |e, i|
  next unless e[:number].nil?
  prev = deduped[i - 1]
  e[:number] = prev[:number] + 1 if prev && prev[:number]
  e[:number_assigned] = true
  assigned << e[:number]
end

# Reconcile WordPress post ids by matching start_date.
wp_by_date = {}
if File.exist?(WP)
  JSON.parse(File.read(WP)).each do |post|
    dates = post.dig("acf", "wc_dates").to_s
    start_token = dates.split(/[–-]/).first
    next if start_token.to_s.strip.empty?
    begin
      wp_by_date[parse_md_y(start_token)] = { id: post["id"], link: post["link"] }
    rescue StandardError
      next
    end
  end
end

# Build final records: starts_at, ends_at (= next week's start, exclusive), slug,
# wordpress_challenge_id where known.
seed = []
deduped.each_with_index do |e, i|
  starts = denver_8am_utc(e[:start_date])
  nxt = deduped[i + 1]
  ends = nxt ? denver_8am_utc(nxt[:start_date]) : denver_8am_utc(e[:start_date] + 7)
  wp = wp_by_date[e[:start_date]]
  url = e[:url] || wp&.dig(:link)
  # Older rows link with site-relative paths (/t/.., /tags/..); absolutize them
  # to the community host so they survive Challenge.normalize_url (which drops
  # non-HTTP URLs). The seed is NPN-specific, so hardcoding the host is fine.
  url = "#{COMMUNITY_BASE}#{url}" if url&.start_with?("/")
  rec = {
    "wordpress_challenge_id" => wp ? wp[:id].to_s : nil,
    "number" => e[:number],
    "title" => e[:title],
    "slug" => "#{e[:start_date].strftime('%Y-%m-%d')}-#{slugify(e[:title])}",
    "starts_at" => starts.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "ends_at" => ends.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "url" => url
  }
  seed << rec
end

File.write(OUT, JSON.pretty_generate(seed) + "\n")

# ---- Validation report -----------------------------------------------------
warn "== parse summary =="
warn "parsed entries:     #{entries.size}"
warn "duplicate weeks:    #{dups.size}"
dups.each { |d| warn "  dup week #{d[:start_date]} -> ##{d[:number]} #{d[:title]}" }
warn "final records:      #{seed.size}"
warn "date range:         #{deduped.first[:start_date]} .. #{deduped.last[:start_date]}"
warn "with WP post id:    #{seed.count { |r| r['wordpress_challenge_id'] }}"
warn "missing number:     #{seed.count { |r| r['number'].nil? }}"
warn "numbers assigned:   #{assigned.size}#{assigned.empty? ? '' : " (#{assigned.min}..#{assigned.max})"}"

nums = deduped.map { |e| e[:number] }.compact
warn "\n== number sequence =="
warn "numbered range:     #{nums.min} .. #{nums.max}  (#{nums.size} numbered)"
full = (nums.min..nums.max).to_a
missing = full - nums
warn "missing numbers:    #{missing.empty? ? 'none' : missing.join(', ')}"
dupe_nums = nums.tally.select { |_, c| c > 1 }.keys
warn "duplicate numbers:  #{dupe_nums.empty? ? 'none' : dupe_nums.join(', ')}"

warn "\n== weekly cadence (gaps != 7 days) =="
deduped.each_cons(2) do |a, b|
  gap = (b[:start_date] - a[:start_date]).to_i
  next if gap == 7
  warn "  #{a[:start_date]} -> #{b[:start_date]} = #{gap}d  (##{a[:number]} #{a[:title]})"
end

warn "\n== number vs date-order disagreements =="
prev = nil
deduped.each do |e|
  if e[:number] && prev && e[:number] <= prev[:number].to_i
    warn "  ##{e[:number]} #{e[:start_date]} not increasing after ##{prev[:number]} #{prev[:start_date]}"
  end
  prev = e if e[:number]
end
warn "\nwrote tmp/wc-seed.json"
