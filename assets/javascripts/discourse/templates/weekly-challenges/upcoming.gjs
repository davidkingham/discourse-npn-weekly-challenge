import { LinkTo } from "@ember/routing";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import challengeDateRange from "../../lib/challenge-date-range";

export default <template>
  <section class="npn-weekly-challenges">
    <nav class="npn-weekly-challenges__breadcrumb">
      <LinkTo
        @route="weekly-challenges.index"
        class="npn-weekly-challenges__back-link"
      >
        {{dIcon "arrow-left"}}
        {{i18n "npn_weekly_challenge.back_to_list"}}
      </LinkTo>
    </nav>

    <header class="npn-weekly-challenges__header">
      <h1 class="npn-weekly-challenges__title">
        {{i18n "npn_weekly_challenge.upcoming.title"}}
      </h1>
      <p class="npn-weekly-challenges__description">
        {{i18n "npn_weekly_challenge.upcoming.description"}}
      </p>
    </header>

    {{#if @controller.model.challenges.length}}
      {{! No links: these challenges have not started, so they have no page yet. }}
      <ul class="npn-weekly-challenges__list">
        {{#each @controller.model.challenges as |challenge|}}
          <li class="npn-weekly-challenges__item">
            <div class="npn-weekly-challenges__item-main">
              <span class="npn-weekly-challenges__item-title">
                {{challenge.title}}
              </span>
              <span class="npn-weekly-challenges__item-dates">
                {{challengeDateRange challenge}}
              </span>
            </div>
            {{#if challenge.description}}
              <p class="npn-weekly-challenges__item-description">
                {{challenge.description}}
              </p>
            {{/if}}
          </li>
        {{/each}}
      </ul>
    {{else}}
      <p class="npn-weekly-challenges__empty">
        {{i18n "npn_weekly_challenge.upcoming.none"}}
      </p>
    {{/if}}
  </section>
</template>
