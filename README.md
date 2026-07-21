# discourse-npn-weekly-challenge

Weekly Challenge archive pages for Nature Photographers Network. Adds a
read-only archive at `/weekly-challenges` where members can browse past
Weekly Challenges and view the entries submitted for each one.

## What it does

- `/weekly-challenges` — lists all started challenges, newest first.
- `/weekly-challenges/upcoming` — the published schedule: the challenges that
  have not started yet, soonest first, with title, date range and description.
  Nothing on this page is a link — those challenges have no page yet.
- `/weekly-challenges/:slug` — one challenge: title, date range, link to the
  original prompt, entry count, a paginated topic list, and previous/next
  challenge navigation.
- `/weekly-challenges/announcements.rss` — RSS feed of the auto-published
  announcement topics only, built for external automations (the weekly
  announcement email). See [Announcements feed](#announcements-feed).

For each challenge, entry topics are found two ways and combined in a single
query (a topic matching both ways appears once):

1. **Modern submissions** — topics whose `npn_wordpress_challenge_id` topic
   custom field (written by [discourse-npn-submissions]) equals the
   challenge's `wordpress_challenge_id`.
2. **Legacy topics** — topics carrying the Weekly Challenge tag whose
   `created_at` falls inside the challenge's date window:
   `starts_at <= created_at < window end`, where the window end is the next
   challenge's `starts_at` when one exists, otherwise the challenge's
   `ends_at`, otherwise `starts_at + 7 days`.

All results go through Discourse's standard topic query security (secured
categories, unlisted and deleted topics), so users only ever see topics they
are allowed to see. The plugin has no migrations and never modifies existing
topics. The one thing it writes is the weekly announcement topic, and only when
`npn_weekly_challenge_auto_topic_enabled` is turned on (see
[Auto-published challenge topic](#auto-published-challenge-topic)).

## Settings

| Setting | Default | Purpose |
| --- | --- | --- |
| `npn_weekly_challenges_enabled` | off | Master switch; all routes 404 when off |
| `npn_weekly_challenge_tag_name` | `weekly-challenge` | Tag(s) identifying legacy challenge topics (topics with any of them match) |
| `npn_weekly_challenge_category_ids` | _(blank)_ | Optional category allowlist; blank = all categories |
| `npn_weekly_challenge_wordpress_api_url` | _(blank)_ | WordPress Weekly Challenge REST endpoint; blank disables the sync |
| `npn_weekly_challenge_wordpress_username` | _(blank)_ | WordPress user the sync authenticates as; needed to see scheduled challenges |
| `npn_weekly_challenge_wordpress_app_password` | _(blank)_ | Application password for that user; only ever sent over HTTPS |
| `npn_weekly_challenge_registry_json` | `[]` | Manual overrides merged on top of the seed and sync (see below) |
| `npn_weekly_challenge_page_size` | 30 | Entries per page on a challenge page |
| `npn_weekly_challenge_auto_topic_enabled` | off | Auto-create and pin the weekly challenge topic (see below) |
| `npn_weekly_challenge_auto_topic_category` | _(blank)_ | Category the topic is created in; required |
| `npn_weekly_challenge_auto_topic_author` | `system` | User the topic is posted as |
| `npn_weekly_challenge_auto_topic_tags` | _(blank)_ | Tags applied to the topic |
| `npn_weekly_challenge_auto_topic_title` | `Weekly Challenge: %{title}` | Title template |
| `npn_weekly_challenge_auto_topic_body` | _(see below)_ | Body template |

## Where challenge data comes from

`DiscourseNpnWeeklyChallenge::Registry` is the only code that knows where
challenges come from. It merges three layers, deduped by `slug` (a later layer
wins on a conflict):

1. **Shipped seed** — `config/weekly_challenge_seed.json`, the historical
   baseline (challenge #855 → mid-2026) backfilled from the community's "Past
   and future challenges" topic. Regenerate it with `scripts/generate_seed.rb`
   (see that file's header). This is the source of truth for everything that
   predates the WordPress feed.
2. **WordPress sync** — `DiscourseNpnWeeklyChallenge::ChallengeStore`, a durable
   `PluginStore` the daily job fills from WordPress (see below). The WordPress
   feed only exposes a rolling window of recent challenges, so the sync
   accumulates them: once a challenge is stored it stays in the archive even
   after WordPress drops it.
3. **Manual override** — the `npn_weekly_challenge_registry_json` setting, a JSON
   array for corrections and one-offs that wins over the other two.

Any layer that can't be read (missing seed, corrupt store, malformed JSON)
degrades to "contributes nothing", logs a warning, and never errors the site.

Challenges whose `starts_at` is in the future are hidden from the archive —
they don't appear in the list, 404 on direct access, and the current challenge
never links forward to them — until the week actually begins. They are listed,
unlinked, on `/weekly-challenges/upcoming` (`Registry.upcoming`, the exact
complement of the archive's published filter).

### WordPress sync

When `npn_weekly_challenge_wordpress_api_url` points at the Weekly Challenge
post type (e.g. `https://example.com/wp-json/wp/v2/weekly-challenge`), the
`Jobs::NpnWeeklyChallengeSync` scheduled job runs daily, fetches the collection
(SSRF-protected, short timeout, never raises), and upserts each challenge into
the store. Weeks already covered by the shipped seed are skipped, so the store
only holds genuine deltas. Each post maps as: `acf.wc_title` → title,
`acf.wc_dates` → start/end timestamps, `id` →
`wordpress_challenge_id` (which is what new submission topics carry, so modern
entries match by custom field), `link` → url.

**Scheduled challenges.** WordPress serves only published posts to anonymous
REST callers; scheduled posts have status `future` and asking for them without
credentials is rejected (`rest_forbidden_status`). So an unauthenticated sync
can never see the upcoming schedule. Set
`npn_weekly_challenge_wordpress_username` and
`npn_weekly_challenge_wordpress_app_password` (WordPress → Users → Profile →
Application Passwords) and the sync authenticates with basic auth and requests
`status=publish,future`, pulling scheduled challenges in so they appear on
`/weekly-challenges/upcoming`. Credentials are only sent over HTTPS — over plain
HTTP the sync logs a warning and falls back to published-only. A scheduled
post's `link` is withheld until it publishes (the permalink 404s until then);
the next sync after publication fills it in, matched on the WordPress post id.

### Auto-published challenge topic

With `npn_weekly_challenge_auto_topic_enabled` on, `Jobs::NpnWeeklyChallengePublish`
creates the week's announcement topic when a challenge starts, pins it in
`npn_weekly_challenge_auto_topic_category`, and unpins the previous week's. The
topic is rendered from the title/body templates; available placeholders are
`%{title}`, `%{description}`, `%{date_range}`, `%{challenge_url}` (this forum's
page for the challenge), `%{prompt_url}` (the WordPress prompt, may be blank)
and `%{slug}`. The weekly banner image is site-specific, so it isn't in the
default body — append the `![…](upload://…)` line to the body setting once.

The job polls every 5 minutes (`Jobs::Scheduled` has no cron, so it can't fire
"Sundays at midnight Pacific" directly) and does nothing on almost every run,
so the topic appears within about 5 minutes of the challenge starting.

Three behaviours are deliberate and worth knowing:

- **It never backfills.** Only the challenge that started within the last 24
  hours is ever published. The registry holds hundreds of past challenges; a
  publisher that asked "which of these lack a topic?" would post them all. A
  side effect is that **enabling the setting mid-week publishes nothing** — the
  first automatic topic appears when the next challenge begins, so it can't
  duplicate one a moderator already posted by hand.
- **Titles are disambiguated.** Challenge titles repeat over the years ("Fog"
  has run three times) and Discourse rejects a duplicate topic title even with
  validations skipped. When the rendered title is already taken, the date range
  is appended.
- **The announcement is not an entry.** It carries a
  `npn_weekly_challenge_slug` topic custom field, which marks it as published
  and keeps `TopicFinder` from listing it among its own challenge's entries.

One-time step when switching over: the previous-week unpin only finds topics the
plugin created, so the last hand-made topic stays pinned. Unpin it by hand once.

### Announcements feed

`/weekly-challenges/announcements.rss` exists so an external mailer (the Kit
RSS automation that sends the Sunday-morning announcement email) can watch for
new challenges without ever emailing members' entry posts. It deliberately does
**not** key off the `weekly-challenge` tag — entries carry that tag too — but
off the `npn_weekly_challenge_slug` custom field, so it contains exactly the
topics this plugin created and nothing a human can add by mis-tagging.

Feed items are shaped for an email template that supplies its own heading,
CTA button and branding:

- `<title>` is the **bare** challenge title ("Fog"), not the topic's prefixed
  one — the email adds its own "Weekly Challenge:" prefix, and Kit's Liquid
  filters can't strip one.
- `<description>` (Kit's `post.summary`) is built from the registry record: a
  date-range heading plus the prompt text. The forum post itself isn't used
  here because its submit/entries links and banner image would render twice in
  the email.
- `<content:encoded>` (Kit's `post.content`) carries the full first-post HTML,
  with links absolutized, for consumers that want fidelity.
- When an item's slug is no longer in the registry, title and description fall
  back to the topic itself.

The response is always secured as an anonymous viewer — it is publicly
cacheable (1 minute) and consumed by logged-out services, so it must never
widen to a signed-in viewer's visibility.

### Challenge timing

A challenge starts on its (Sunday) start date at **midnight
America/Los_Angeles** and runs until the next challenge begins.
`DiscourseNpnWeeklyChallenge::ChallengeTime` turns the WordPress display dates
into DST-aware UTC timestamps. Midnight Pacific is deliberate: the boundary is
both the entry deadline and the theme reveal, so it means no US timezone loses
any of its Saturday night (Eastern gets until 3am as grace) and the new theme
is live before Sunday sunrise everywhere in the US — when nature photographers
shoot. The WordPress posts are scheduled to publish at the same moment.

**The shipped seed predates this convention** and keeps its original
08:00 America/Denver anchors on purpose: legacy entries are matched purely by
stored date window, so regenerating the seed under the new convention would
shift every historical window and silently reassign old submissions across
weeks. Store records still present in the WordPress feed are rewritten to the
new convention by the next daily sync; older store records keep the timestamps
they were synced with.

### Override / entry format

Each object in `npn_weekly_challenge_registry_json` (and each seed record) uses:

```json
[
  {
    "wordpress_challenge_id": "123",
    "title": "Nature's Architecture",
    "slug": "2026-06-07-natures-architecture",
    "starts_at": "2026-06-07T07:00:00Z",
    "ends_at": "2026-06-14T07:00:00Z",
    "url": "https://example.com/weekly-challenge/natures-architecture"
  }
]
```

- `title`, `slug`, and `starts_at` are required; entries missing any of them
  are skipped (with a warning in the logs).
- `slug` must be lowercase letters, digits, and hyphens — it becomes the URL,
  and it's the key layers merge on (use the seed's `YYYY-MM-DD-title` slug to
  override a specific week).
- `wordpress_challenge_id` is the WordPress post id of the challenge. Omit it
  for old challenges that predate the submission plugin; those match by date
  only.
- `starts_at` / `ends_at` are ISO 8601 timestamps; use UTC (`Z`).
- `description` is the challenge prompt shown on the challenge page. The
  WordPress sync pulls it from `acf.wc_description`; the seed uses WordPress's
  text where available and the topic's one-liner otherwise (the oldest
  challenges have none).
- `url` links to the original WordPress prompt. It's only shown when a challenge
  has no `description` **and** has a `wordpress_challenge_id` (i.e. a real
  WordPress post) — challenges without a WordPress post never render a link.
- Malformed JSON disables only the override layer (it logs a warning); the seed
  and sync still render.

## Local testing

1. Enable `npn_weekly_challenges_enabled`. The shipped seed already populates
   `/weekly-challenges` with the full challenge history — no setup needed to see
   the list.
2. Ensure the `weekly-challenge` tag exists and matches
   `npn_weekly_challenge_tag_name` so legacy tagged topics match by date window.
3. To test the sync, set `npn_weekly_challenge_wordpress_api_url` and run the job
   from the rails console:
   `Jobs::NpnWeeklyChallengeSync.new.execute({})` (or
   `DiscourseNpnWeeklyChallenge::WordpressSync.refresh`).
4. For ad-hoc challenges, add an override to `npn_weekly_challenge_registry_json`.

To exercise the custom-field path without the submission plugin, attach the
field to a topic from the rails console:

```ruby
Topic.find(123).upsert_custom_fields("npn_wordpress_challenge_id" => "123")
```

Specs (plugin JS must be compiled once if no dev server/watcher is running:
`bin/rake assets:precompile:build_plugins`):

```bash
LOAD_PLUGINS=1 bin/rspec plugins/discourse-npn-weekly-challenge/spec
```

## Limitations (v1)

- **Date matching is heuristic.** A legacy topic tagged `weekly-challenge`
  but posted after the challenge's window (e.g. a late entry) won't appear
  under that challenge; a topic posted during the window for a *different*
  challenge will be misattributed. Old topics are not modified or backfilled
  in this version.
- **Gaps between challenges are absorbed by the earlier challenge.** The
  window of a challenge extends to the next challenge's `starts_at` even if
  its own `ends_at` is earlier, so no topic can fall between two challenges
  (or into two at once). Anything tagged during a hiatus attaches to the
  challenge before it.
- **The seed has a horizon.** It covers through its generation date; beyond that
  the archive depends on the WordPress sync (or manual overrides). Regenerate the
  seed periodically, or keep the sync configured.
- **Sync needs WordPress.** New challenges appear automatically only while
  `npn_weekly_challenge_wordpress_api_url` is set and reachable; otherwise add
  them via the manual override.
- **Entry counts are per-viewer.** The count reflects what the current user
  may see, so staff may see higher counts than anonymous visitors.

[discourse-npn-submissions]: https://github.com/davidkingham/discourse-npn-submissions
