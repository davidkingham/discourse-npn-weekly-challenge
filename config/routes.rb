# frozen_string_literal: true

DiscourseNpnWeeklyChallenge::Engine.routes.draw do
  get "/weekly-challenges" => "challenges#index"
  # Declared before the :slug route, which would otherwise match "current" and
  # "upcoming" as slugs. Real slugs are date-prefixed, so there is no collision.
  get "/weekly-challenges/current" => "challenges#current"
  get "/weekly-challenges/upcoming" => "challenges#upcoming"
  get "/weekly-challenges/announcements.rss" => "challenges#announcements", :format => :rss
  get "/weekly-challenges/:slug" => "challenges#show", :constraints => { slug: /[a-z0-9\-]+/ }
end
