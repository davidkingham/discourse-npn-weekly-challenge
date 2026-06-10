# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # Prepended into TopicQuery (the pattern discourse-templates and
  # discourse-topic-voting use) so we can build on the protected
  # #default_results — the relation that already enforces secured categories,
  # unlisted/deleted visibility, ordering, and pagination. TopicFinder is the
  # public entry point; these methods are plumbing.
  module TopicQueryExtension
    def list_npn_weekly_challenge(challenge)
      results = TopicFinder.scope_to_challenge(default_results, challenge)
      create_list(:npn_weekly_challenge, {}, results)
    end

    def npn_weekly_challenge_count(challenge)
      TopicFinder
        .scope_to_challenge(default_results(skip_ordering: true), challenge)
        .reorder(nil)
        .count
    end
  end
end
