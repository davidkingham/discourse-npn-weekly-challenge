import { LinkTo } from "@ember/routing";
import { i18n } from "discourse-i18n";
import challengeDateRange from "../../lib/challenge-date-range";

export default <template>
  <section class="npn-weekly-challenges">
    <header class="npn-weekly-challenges__header">
      <h1 class="npn-weekly-challenges__title">
        {{i18n "npn_weekly_challenge.title"}}
      </h1>
      <p class="npn-weekly-challenges__description">
        {{i18n "npn_weekly_challenge.list_description"}}
      </p>
    </header>

    {{#if @controller.model.challenges.length}}
      <ul class="npn-weekly-challenges__list">
        {{#each @controller.model.challenges as |challenge|}}
          <li class="npn-weekly-challenges__item">
            <LinkTo
              @route="weekly-challenges.show"
              @model={{challenge.slug}}
              class="npn-weekly-challenges__link"
            >
              <span class="npn-weekly-challenges__item-title">
                {{challenge.title}}
              </span>
              <span class="npn-weekly-challenges__item-dates">
                {{challengeDateRange challenge}}
              </span>
            </LinkTo>
          </li>
        {{/each}}
      </ul>
    {{else}}
      <p class="npn-weekly-challenges__empty">
        {{i18n "npn_weekly_challenge.no_challenges"}}
      </p>
    {{/if}}
  </section>
</template>
