import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class WeeklyChallengesIndexRoute extends DiscourseRoute {
  model() {
    return ajax("/weekly-challenges.json");
  }

  titleToken() {
    return i18n("npn_weekly_challenge.title");
  }
}
