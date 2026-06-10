# frozen_string_literal: true

module PageObjects
  module Pages
    class WeeklyChallenges < PageObjects::Pages::Base
      def visit_index
        page.visit("/weekly-challenges")
        self
      end

      def visit_challenge(slug)
        page.visit("/weekly-challenges/#{slug}")
        self
      end

      def open_challenge(title)
        page.find(".npn-weekly-challenges__link", text: title).click
        self
      end

      def go_to_previous_challenge
        page.find(".npn-weekly-challenge__nav-link.--previous").click
        self
      end

      def has_challenge_listed?(title)
        page.has_css?(".npn-weekly-challenges__item-title", text: title)
      end

      def has_challenge_title?(title)
        page.has_css?(".npn-weekly-challenge__title", text: title)
      end

      def has_entry_topic?(title)
        page.has_css?(".npn-challenge-entries .raw-topic-link", text: title)
      end

      def has_no_entry_topic?(title)
        page.has_no_css?(".npn-challenge-entries .raw-topic-link", text: title)
      end

      def has_empty_state?
        page.has_css?(".npn-challenge-entries__empty")
      end
    end
  end
end
