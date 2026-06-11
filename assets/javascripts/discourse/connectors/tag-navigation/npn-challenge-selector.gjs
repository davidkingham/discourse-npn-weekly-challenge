import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DSelect from "discourse/ui-kit/d-select";
import { i18n } from "discourse-i18n";
import challengeDateRange from "../../lib/challenge-date-range";

export default class NpnChallengeSelector extends Component {
  // Only on the plain tag page (tag.show and its /l/ filter variants) — not
  // tag intersections or category-scoped tag lists, which share this outlet.
  static shouldRender({ tag }, { siteSettings }, owner) {
    if (!siteSettings.npn_weekly_challenges_enabled || !tag) {
      return false;
    }

    const challengeTags = siteSettings.npn_weekly_challenge_tag_name
      .split("|")
      .map((name) => name.trim())
      .filter(Boolean);

    return (
      challengeTags.includes(tag.name) &&
      owner.lookup("service:router").currentRouteName?.startsWith("tag.show")
    );
  }

  @service router;

  @tracked challenges = [];

  constructor() {
    super(...arguments);
    this.loadChallenges();
  }

  async loadChallenges() {
    let challenges = [];
    try {
      const result = await ajax("/weekly-challenges.json");
      challenges = (result?.challenges || []).filter(
        (challenge) => challenge?.slug && challenge?.title
      );
    } catch {
      // A failed fetch just means no dropdown; the tag page works without it.
    }

    if (!this.isDestroying && !this.isDestroyed) {
      this.challenges = challenges;
    }
  }

  @action
  selectChallenge(slug) {
    if (slug) {
      this.router.transitionTo("weekly-challenges.show", slug);
    }
  }

  <template>
    {{#if this.challenges.length}}
      <div class="npn-challenge-selector">
        <label class="npn-challenge-selector__label" for="npn-challenge-select">
          {{i18n "npn_weekly_challenge.challenge_selector.label"}}
        </label>
        <DSelect
          id="npn-challenge-select"
          class="npn-challenge-selector__select"
          @onChange={{this.selectChallenge}}
          @nonePlaceholder={{i18n
            "npn_weekly_challenge.challenge_selector.placeholder"
          }}
          as |select|
        >
          {{#each this.challenges as |challenge|}}
            <select.Option @value={{challenge.slug}}>
              {{i18n
                "npn_weekly_challenge.challenge_selector.option"
                title=challenge.title
                range=(challengeDateRange challenge)
              }}
            </select.Option>
          {{/each}}
        </DSelect>
      </div>
    {{/if}}
  </template>
}
