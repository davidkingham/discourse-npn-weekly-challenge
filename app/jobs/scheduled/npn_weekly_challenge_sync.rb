# frozen_string_literal: true

module Jobs
  # Refreshes the challenge archive from WordPress once a day. The weekly cadence
  # of new challenges means daily is plenty fresh; WordpressSync no-ops when the
  # plugin is disabled or no API URL is configured, and never raises.
  class NpnWeeklyChallengeSync < ::Jobs::Scheduled
    every 1.day

    def execute(_args)
      DiscourseNpnWeeklyChallenge::WordpressSync.refresh
    end
  end
end
