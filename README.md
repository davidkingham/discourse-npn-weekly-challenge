# discourse-npn-weekly-challenge

Weekly Challenge archive pages for Nature Photographers Network. Adds a
read-only archive at `/weekly-challenges` where members can browse past
Weekly Challenges and view the entries submitted for each one.

## What it does

- `/weekly-challenges` — lists all configured challenges, newest first.
- `/weekly-challenges/:slug` — one challenge: title, date range, link to the
  original prompt, entry count, a paginated topic list, and previous/next
  challenge navigation.

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
are allowed to see. The plugin writes nothing — no migrations, no backfills,
no changes to existing topics.

## Settings

| Setting | Default | Purpose |
| --- | --- | --- |
| `npn_weekly_challenges_enabled` | off | Master switch; all routes 404 when off |
| `npn_weekly_challenge_tag_name` | `weekly-challenge` | Tag(s) identifying legacy challenge topics (topics with any of them match) |
| `npn_weekly_challenge_category_ids` | _(blank)_ | Optional category allowlist; blank = all categories |
| `npn_weekly_challenge_registry_json` | `[]` | The challenge registry (see below) |
| `npn_weekly_challenge_page_size` | 30 | Entries per page on a challenge page |

## Challenge registry

v1 sources challenge data from the `npn_weekly_challenge_registry_json` site
setting — a JSON array, one object per challenge:

```json
[
  {
    "wordpress_challenge_id": "123",
    "title": "Nature's Architecture",
    "slug": "2026-06-09-natures-architecture",
    "starts_at": "2026-06-09T00:00:00Z",
    "ends_at": "2026-06-16T00:00:00Z",
    "url": "https://example.com/weekly-challenge/natures-architecture"
  }
]
```

Field notes:

- `title`, `slug`, and `starts_at` are required; entries missing any of them
  are skipped (with a warning in the logs).
- `slug` must be lowercase letters, digits, and hyphens — it becomes the URL.
- `wordpress_challenge_id` is the WordPress post id of the challenge (the
  same id discourse-npn-submissions stores on new submission topics). Omit it
  for old challenges that predate the submission plugin; those match by date
  only.
- `starts_at` / `ends_at` are ISO 8601 timestamps; use UTC (`Z`) unless the
  challenge genuinely rolls over in another timezone.
- `url` links to the original challenge prompt; omit if there isn't one.
- Malformed JSON disables the archive list (it renders empty) and logs a
  warning — it never errors the site.

The registry is parsed and cached per-process and re-parsed whenever the
setting changes.

`DiscourseNpnWeeklyChallenge::Registry` is the only code that knows where
challenge data comes from. A future WordPress sync replaces the inside of
`Registry.all` (e.g. with a cached HTTP fetch like the one in
discourse-npn-submissions' `WeeklyChallengeInfo`) without touching the
controller, query, or frontend.

## Local testing

1. Enable `npn_weekly_challenges_enabled`.
2. Paste a registry array into `npn_weekly_challenge_registry_json` (the
   example above works — adjust dates to bracket some existing tagged topics).
3. Ensure the `weekly-challenge` tag exists and matches
   `npn_weekly_challenge_tag_name`.
4. Visit `/weekly-challenges`.

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
- **The registry is manual.** Challenges appear only after being added to the
  setting. The structure is designed to be replaced by a WordPress sync.
- **Entry counts are per-viewer.** The count reflects what the current user
  may see, so staff may see higher counts than anonymous visitors.

[discourse-npn-submissions]: https://github.com/davidkingham/discourse-npn-submissions
