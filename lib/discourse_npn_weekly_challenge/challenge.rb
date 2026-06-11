# frozen_string_literal: true

module DiscourseNpnWeeklyChallenge
  # Immutable record describing one Weekly Challenge. Instances are built by
  # Registry from the npn_weekly_challenge_registry_json site setting; nothing
  # in the plugin mutates them after construction.
  class Challenge
    SLUG_PATTERN = /\A[a-z0-9][a-z0-9\-]*\z/
    DEFAULT_DURATION = 7.days
    MAX_DESCRIPTION = 2000

    attr_reader :wordpress_challenge_id, :title, :slug, :starts_at, :ends_at, :url, :description

    # Build a Challenge from one parsed registry entry, or return nil when the
    # entry is unusable (missing/invalid title, slug, or starts_at). Optional
    # fields that fail to parse are dropped individually rather than rejecting
    # the whole entry.
    def self.from_hash(hash)
      return nil unless hash.is_a?(Hash)

      title = hash["title"].to_s.strip
      slug = hash["slug"].to_s.strip.downcase
      starts_at = parse_time(hash["starts_at"])
      return nil if title.blank? || !slug.match?(SLUG_PATTERN) || starts_at.nil?

      new(
        wordpress_challenge_id: normalize_wordpress_id(hash["wordpress_challenge_id"]),
        title: title,
        slug: slug,
        starts_at: starts_at,
        ends_at: parse_time(hash["ends_at"]),
        url: normalize_url(hash["url"]),
        description: normalize_description(hash["description"]),
      )
    end

    def self.normalize_description(value)
      text = value.to_s.strip
      return nil if text.blank?
      text.length > MAX_DESCRIPTION ? "#{text[0, MAX_DESCRIPTION].rstrip}…" : text
    end

    def self.parse_time(value)
      return nil if value.blank?
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    # The submissions plugin stores the WordPress post id as an integer-typed
    # custom field, so the topic_custom_fields value is its canonical integer
    # string (e.g. "123"). Normalize digit strings through Integer so "0123"
    # in the registry still matches.
    def self.normalize_wordpress_id(value)
      s = value.to_s.strip
      return nil if s.blank?
      s.match?(/\A\d+\z/) ? s.to_i.to_s : s
    end

    def self.normalize_url(value)
      url = value.to_s.strip
      return nil if url.blank?
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) && uri.host.present? ? url : nil
    rescue URI::InvalidURIError
      nil
    end

    def initialize(wordpress_challenge_id:, title:, slug:, starts_at:, ends_at:, url:, description:)
      @wordpress_challenge_id = wordpress_challenge_id
      @title = title
      @slug = slug
      @starts_at = starts_at
      @ends_at = ends_at
      @url = url
      @description = description
      freeze
    end

    # Exclusive end of the legacy date-matching window. The next challenge's
    # start always wins (so a topic can never fall in two windows), then the
    # explicit end date, then a one-week default.
    def window_end(next_challenge_starts_at)
      next_challenge_starts_at || ends_at || starts_at + DEFAULT_DURATION
    end

    # Lets ChallengeSerializer (ActiveModel::Serializer) read attributes from
    # this plain Ruby object.
    def read_attribute_for_serialization(attribute)
      public_send(attribute)
    end

    # Value equality on slug (the registry's unique key), so adjacency
    # lookups don't depend on object identity across registry re-parses.
    def ==(other)
      other.is_a?(Challenge) && other.slug == slug
    end
    alias eql? ==

    def hash
      slug.hash
    end
  end
end
