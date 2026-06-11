# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # The Weekly Challenge calendar convention. A challenge starts on its (Sunday)
  # start date at 08:00 in the club's local timezone and runs until the next
  # challenge begins. WordPress publishes only a display date string
  # (acf.wc_dates, e.g. "6/7/26 - 6/13/26"); this turns that into the canonical
  # UTC timestamps the rest of the plugin uses, matching how the shipped seed
  # (config/weekly_challenge_seed.json) was generated.
  #
  # The timezone matters: legacy entries are matched purely by date window, so an
  # 8am-local start is what keeps a Sunday-morning submission inside its own week
  # rather than the previous one. ActiveSupport handles DST (MST/MDT) for us.
  module ChallengeTime
    ZONE = "America/Denver"
    START_HOUR = 8
    DEFAULT_DURATION = 7.days

    module_function

    def zone
      @zone ||= ActiveSupport::TimeZone[ZONE]
    end

    # 08:00 local on the given date, as a UTC Time. Accepts a Date or anything
    # Date.parse handles; returns nil when unparseable.
    def start_of_day(date)
      date = to_date(date)
      return nil if date.nil?
      zone.local(date.year, date.month, date.day, START_HOUR).utc
    end

    # Parse the *start* of a WordPress wc_dates string ("6/7/26 - 6/13/26" or
    # "6/7/26") into the canonical UTC start timestamp. Returns nil on failure.
    def parse_start(wc_dates)
      token = wc_dates.to_s.split(/[–-]/).first.to_s.strip
      return nil if token.blank?
      start_of_day(parse_mdy(token))
    end

    # The exclusive end of a one-week window from the given start (next Sunday at
    # 08:00 local), DST-aware. Used as the fallback window end / display end for
    # the most recent challenge, before a following challenge exists to bound it.
    def default_end(starts_at_utc)
      return nil if starts_at_utc.nil?
      start_of_day(starts_at_utc.in_time_zone(zone).to_date + 7)
    end

    def to_date(value)
      return value if value.is_a?(Date)
      return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)
      parse_mdy(value)
    end

    # "M/D/YY" or "M/D/YYYY" -> Date; two-digit years map to the 2000s. Falls
    # back to Date.parse for ISO-ish strings. Returns nil when unrecognized.
    def parse_mdy(value)
      str = value.to_s.strip
      if (m = str.match(%r{\A(\d{1,2})/(\d{1,2})/(\d{2,4})\z}))
        month, day, year = m.captures.map(&:to_i)
        year += 2000 if year < 100
        return Date.new(year, month, day)
      end
      Date.parse(str)
    rescue ArgumentError, Date::Error
      nil
    end
  end
end
