# frozen_string_literal: true

DiscourseNpnWeeklyChallenge::Engine.routes.draw do
  get "/weekly-challenges" => "challenges#index"
  # Declared before the :slug route, which would otherwise match "current" as a
  # slug. Real slugs are date-prefixed, so there is no collision.
  get "/weekly-challenges/current" => "challenges#current"
  get "/weekly-challenges/:slug" => "challenges#show", :constraints => { slug: /[a-z0-9\-]+/ }
end
