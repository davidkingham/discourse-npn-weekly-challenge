# frozen_string_literal: true

DiscourseNpnWeeklyChallenge::Engine.routes.draw do
  get "/weekly-challenges" => "challenges#index"
  get "/weekly-challenges/:slug" => "challenges#show", :constraints => { slug: /[a-z0-9\-]+/ }
end
