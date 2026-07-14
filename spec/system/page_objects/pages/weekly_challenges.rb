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

      def visit_upcoming
        page.visit("/weekly-challenges/upcoming")
        self
      end

      def go_to_upcoming
        page.find(".npn-weekly-challenges__header-link").click
        self
      end

      def has_upcoming_heading?
        page.has_css?(
          ".npn-weekly-challenges__title",
          text: I18n.t("js.npn_weekly_challenge.upcoming.title"),
        )
      end

      def has_challenge_description?(text)
        page.has_css?(".npn-weekly-challenges__item-description", text: text)
      end

      # The upcoming challenges have no page to link to yet.
      def has_no_challenge_links?
        page.has_no_css?(".npn-weekly-challenges__list a")
      end

      def visit_tag(name)
        page.visit("/tag/#{name}")
        self
      end

      def visit_tag_intersection(name, additional_name)
        page.visit("/tags/intersection/#{name}/#{additional_name}")
        self
      end

      def select_challenge(title)
        page.find(".npn-challenge-selector select").select(title)
        self
      end

      # The first option is the placeholder; the rest are challenges.
      def challenge_selector_options
        page.all(".npn-challenge-selector option").drop(1).map(&:text)
      end

      def has_tag_page?
        page.has_css?("body.tags-page")
      end

      def has_challenge_selector?
        page.has_css?(".npn-challenge-selector")
      end

      def has_no_challenge_selector?
        page.has_no_css?(".npn-challenge-selector")
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

      def has_current_badge_on?(title)
        page.has_css?(
          ".npn-weekly-challenges__item-title:has(.npn-weekly-challenges__current-badge)",
          text: title,
        )
      end

      def current_badge_count
        page.all(".npn-weekly-challenges__current-badge").size
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
