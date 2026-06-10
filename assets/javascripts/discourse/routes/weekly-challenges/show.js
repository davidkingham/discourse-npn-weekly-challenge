import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import TopicList from "discourse/models/topic-list";
import DiscourseRoute from "discourse/routes/discourse";

export default class WeeklyChallengesShowRoute extends DiscourseRoute {
  @service store;

  async model(params) {
    const result = await ajax(`/weekly-challenges/${params.slug}.json`);

    return {
      slug: params.slug,
      challenge: result.challenge,
      previousChallenge: result.previous_challenge,
      nextChallenge: result.next_challenge,
      entryCount: result.entry_count,
      // Wraps the raw payload in real Topic models so the core topic list
      // component renders them natively.
      topics: TopicList.topicsFrom(this.store, result),
    };
  }

  titleToken() {
    return this.currentModel?.challenge?.title;
  }
}
