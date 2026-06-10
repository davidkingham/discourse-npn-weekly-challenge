# frozen_string_literal: true

# name: discourse-npn-weekly-challenge
# about: Weekly Challenge archive and per-challenge entry browsing for Nature Photographers Network.
# version: 0.1.0
# authors: David Kingham
# url: https://github.com/davidkingham/discourse-npn-weekly-challenge
# license: MIT

enabled_site_setting :npn_weekly_challenges_enabled

register_asset "stylesheets/npn-weekly-challenge.scss"

module ::DiscourseNpnWeeklyChallenge
  PLUGIN_NAME = "discourse-npn-weekly-challenge"
end

require_relative "lib/discourse_npn_weekly_challenge/engine"

after_initialize do
  require_relative "lib/discourse_npn_weekly_challenge/challenge"
  require_relative "lib/discourse_npn_weekly_challenge/registry"
  require_relative "lib/discourse_npn_weekly_challenge/topic_finder"
  require_relative "lib/discourse_npn_weekly_challenge/topic_query_extension"
  require_relative "app/serializers/discourse_npn_weekly_challenge/challenge_serializer"
  require_relative "app/controllers/discourse_npn_weekly_challenge/challenges_controller"

  reloadable_patch { TopicQuery.prepend(DiscourseNpnWeeklyChallenge::TopicQueryExtension) }

  # The parsed registry is memoized keyed on the raw setting string, so this
  # hook is belt-and-suspenders — it keeps the per-process cache from holding
  # stale entries for old setting values indefinitely.
  on(:site_setting_changed) do |name, _old_value, _new_value|
    DiscourseNpnWeeklyChallenge::Registry.clear_cache if name == :npn_weekly_challenge_registry_json
  end

  Discourse::Application.routes.append { mount ::DiscourseNpnWeeklyChallenge::Engine, at: "/" }
end
