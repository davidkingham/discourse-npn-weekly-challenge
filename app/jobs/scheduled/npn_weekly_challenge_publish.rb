# frozen_string_literal: true

module Jobs
  # Publishes the weekly challenge topic shortly after its challenge starts.
  #
  # Jobs::Scheduled has no cron expression, so it cannot fire "Sundays at 08:00"
  # directly. The established pattern is to poll often and return early: the
  # publisher is a no-op except in the window right after a challenge begins, so
  # nearly every run does nothing but a registry read.
  class NpnWeeklyChallengePublish < ::Jobs::Scheduled
    every 15.minutes

    def execute(_args)
      DiscourseNpnWeeklyChallenge::TopicPublisher.publish_due
    end
  end
end
