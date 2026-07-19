# frozen_string_literal: true

require "rails_helper"

describe DiscourseNpnWeeklyChallenge::WordpressSync do
  let(:store) { DiscourseNpnWeeklyChallenge::ChallengeStore }

  def wp_post(
    id: 21_426,
    title: "Silhouettes with Color",
    dates: "6/7/26 - 6/13/26",
    description: nil,
    **over
  )
    acf = { "wc_title" => title, "wc_dates" => dates }
    acf["wc_description"] = description if description
    { "id" => id, "link" => "https://example.com/weekly-challenge/1243/", "acf" => acf }.merge(
      over.transform_keys(&:to_s),
    )
  end

  before do
    SiteSetting.npn_weekly_challenges_enabled = true
    SiteSetting.npn_weekly_challenge_wordpress_api_url =
      "https://example.com/wp-json/wp/v2/weekly-challenge"
    # Isolate from the shipped seed unless a spec opts in.
    allow(DiscourseNpnWeeklyChallenge::Registry).to receive(:seed_challenges).and_return([])
  end

  after { store.clear }

  describe ".normalize" do
    it "maps a WordPress post to a seed-shaped record" do
      expect(described_class.normalize(wp_post)).to eq(
        "wordpress_challenge_id" => "21426",
        "title" => "Silhouettes with Color",
        "slug" => "2026-06-07-silhouettes-with-color",
        "starts_at" => "2026-06-07T07:00:00Z",
        "ends_at" => "2026-06-14T07:00:00Z",
        "url" => "https://example.com/weekly-challenge/1243/",
        "description" => nil,
      )
    end

    it "cleans the description to plain text" do
      record =
        described_class.normalize(
          wp_post(description: "<p>Create bold silhouettes &amp; shapes.</p>"),
        )
      expect(record["description"]).to eq("Create bold silhouettes & shapes.")
    end

    it "decodes entities and builds a matching slug" do
      record = described_class.normalize(wp_post(title: "Light Beams &amp; Crepuscular Rays"))
      expect(record["title"]).to eq("Light Beams & Crepuscular Rays")
      expect(record["slug"]).to eq("2026-06-07-light-beams-and-crepuscular-rays")
    end

    it "returns nil without a usable title" do
      expect(described_class.normalize(wp_post(title: ""))).to be_nil
      expect(described_class.normalize("id" => 1, "acf" => {})).to be_nil
    end

    it "returns nil when the dates are unparseable" do
      expect(described_class.normalize(wp_post(dates: "soon"))).to be_nil
    end

    it "drops a non-positive post id" do
      expect(described_class.normalize(wp_post(id: 0))["wordpress_challenge_id"]).to be_nil
    end

    it "keeps the url for a published post" do
      expect(described_class.normalize(wp_post(status: "publish"))["url"]).to eq(
        "https://example.com/weekly-challenge/1243/",
      )
    end

    it "omits the url of a scheduled post, whose permalink 404s until it publishes" do
      record = described_class.normalize(wp_post(status: "future"))

      expect(record["url"]).to be_nil
      expect(record["title"]).to eq("Silhouettes with Color")
    end
  end

  describe "authentication" do
    let(:endpoint) { "https://example.com/wp-json/wp/v2/weekly-challenge" }

    def set_credentials
      SiteSetting.npn_weekly_challenge_wordpress_username = "sync-bot"
      SiteSetting.npn_weekly_challenge_wordpress_app_password = "abcd efgh ijkl"
    end

    describe ".collection_uri" do
      it "asks for scheduled challenges when credentials are configured" do
        set_credentials

        expect(described_class.collection_uri(endpoint).query).to eq(
          "per_page=100&status=publish%2Cfuture",
        )
      end

      it "stays anonymous without credentials" do
        expect(described_class.collection_uri(endpoint).query).to eq("per_page=100")
      end

      it "stays anonymous when only one half of the credential is set" do
        SiteSetting.npn_weekly_challenge_wordpress_username = "sync-bot"

        expect(described_class.collection_uri(endpoint).query).to eq("per_page=100")
      end

      it "does not request scheduled posts over plain HTTP, where the password would leak" do
        set_credentials

        uri = described_class.collection_uri("http://example.com/wp-json/wp/v2/weekly-challenge")

        expect(uri.query).to eq("per_page=100")
      end

      it "preserves a status the admin already set" do
        set_credentials

        expect(described_class.collection_uri("#{endpoint}?status=draft").query).to eq(
          "status=draft&per_page=100",
        )
      end
    end

    describe ".fetch_remote" do
      it "sends the application password as basic auth over HTTPS" do
        set_credentials
        stub =
          stub_request(:get, "#{endpoint}?per_page=100&status=publish,future").with(
            basic_auth: %w[sync-bot abcd\ efgh\ ijkl],
          ).to_return(status: 200, body: "[]")

        described_class.fetch_remote(described_class.collection_uri(endpoint))

        expect(stub).to have_been_requested
      end

      it "sends no credentials when none are configured" do
        stub = stub_request(:get, "#{endpoint}?per_page=100").to_return(status: 200, body: "[]")

        described_class.fetch_remote(described_class.collection_uri(endpoint))

        expect(stub).to have_been_requested
        expect(WebMock).to have_requested(:get, /weekly-challenge/).with { |req|
          req.headers["Authorization"].nil?
        }
      end

      it "never sends credentials over plain HTTP" do
        set_credentials
        http_endpoint = "http://example.com/wp-json/wp/v2/weekly-challenge"
        stub_request(:get, "#{http_endpoint}?per_page=100").to_return(status: 200, body: "[]")

        described_class.fetch_remote(described_class.collection_uri(http_endpoint))

        expect(WebMock).to have_requested(:get, /weekly-challenge/).with { |req|
          req.headers["Authorization"].nil?
        }
      end
    end
  end

  describe ".refresh" do
    it "stores fetched challenges and reports the change" do
      allow(described_class).to receive(:fetch_collection).and_return([wp_post])

      expect(described_class.refresh).to eq(true)
      expect(store.all.map { |r| r["slug"] }).to eq(["2026-06-07-silhouettes-with-color"])
    end

    it "skips weeks the shipped seed already covers" do
      seed_week =
        DiscourseNpnWeeklyChallenge::Challenge.from_hash(
          "title" => "Silhouettes with Color",
          "slug" => "2026-06-07-silhouettes-with-color",
          "starts_at" => "2026-06-07T07:00:00Z",
        )
      allow(DiscourseNpnWeeklyChallenge::Registry).to receive(:seed_challenges).and_return(
        [seed_week],
      )
      allow(described_class).to receive(:fetch_collection).and_return([wp_post])

      expect(described_class.refresh).to eq(false)
      expect(store.all).to eq([])
    end

    it "is a no-op when disabled" do
      SiteSetting.npn_weekly_challenges_enabled = false
      allow(described_class).to receive(:fetch_collection)
      expect(described_class.refresh).to eq(false)
      expect(described_class).not_to have_received(:fetch_collection)
    end

    it "is a no-op when no API URL is configured" do
      SiteSetting.npn_weekly_challenge_wordpress_api_url = ""
      allow(described_class).to receive(:fetch_collection)
      expect(described_class.refresh).to eq(false)
      expect(described_class).not_to have_received(:fetch_collection)
    end

    it "does nothing when the fetch fails" do
      allow(described_class).to receive(:fetch_collection).and_return(nil)
      expect(described_class.refresh).to eq(false)
      expect(store.all).to eq([])
    end

    it "refreshes the Registry cache after a change" do
      allow(described_class).to receive(:fetch_collection).and_return([wp_post])
      allow(DiscourseNpnWeeklyChallenge::Registry).to receive(:clear_cache).and_call_original
      described_class.refresh
      expect(DiscourseNpnWeeklyChallenge::Registry).to have_received(:clear_cache)
    end
  end

  describe ".collection_uri" do
    it "adds a bounded per_page when absent" do
      uri = described_class.collection_uri("https://example.com/wp-json/wp/v2/weekly-challenge")
      expect(uri.query).to eq("per_page=100")
    end

    it "preserves an existing per_page" do
      uri =
        described_class.collection_uri(
          "https://example.com/wp-json/wp/v2/weekly-challenge?per_page=5&order=desc",
        )
      expect(uri.query).to eq("per_page=5&order=desc")
    end
  end
end
