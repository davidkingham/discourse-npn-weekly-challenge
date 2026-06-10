import { shortDate } from "discourse/lib/formatter";
import { i18n } from "discourse-i18n";

// Human-readable date range for a serialized challenge. Falls back to just
// the start date when no end date was provided in the registry.
export default function challengeDateRange(challenge) {
  const start = shortDate(challenge.starts_at);

  if (!challenge.ends_at) {
    return start;
  }

  return i18n("npn_weekly_challenge.date_range", {
    start,
    end: shortDate(challenge.ends_at),
  });
}
