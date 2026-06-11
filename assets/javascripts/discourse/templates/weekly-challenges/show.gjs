import { LinkTo } from "@ember/routing";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import NpnChallengeEntries from "../../components/npn-challenge-entries";
import challengeDateRange from "../../lib/challenge-date-range";

export default <template>
  <section class="npn-weekly-challenge">
    <nav class="npn-weekly-challenge__breadcrumb">
      <LinkTo
        @route="weekly-challenges.index"
        class="npn-weekly-challenge__back-link"
      >
        {{dIcon "arrow-left"}}
        {{i18n "npn_weekly_challenge.back_to_list"}}
      </LinkTo>
    </nav>

    <header class="npn-weekly-challenge__header">
      <h1 class="npn-weekly-challenge__title">
        {{@controller.model.challenge.title}}
      </h1>
      <div class="npn-weekly-challenge__meta">
        <span class="npn-weekly-challenge__dates">
          {{challengeDateRange @controller.model.challenge}}
        </span>
        <span class="npn-weekly-challenge__count">
          {{i18n
            "npn_weekly_challenge.entry_count"
            count=@controller.model.entryCount
          }}
        </span>
      </div>

      {{#if @controller.model.challenge.description}}
        <p class="npn-weekly-challenge__description">
          {{@controller.model.challenge.description}}
        </p>
      {{else if @controller.model.challenge.wordpress_challenge_id}}
        {{#if @controller.model.challenge.url}}
          <a
            href={{@controller.model.challenge.url}}
            class="npn-weekly-challenge__prompt-link"
            target="_blank"
            rel="noopener noreferrer"
          >
            {{i18n "npn_weekly_challenge.view_prompt"}}
          </a>
        {{/if}}
      {{/if}}
    </header>

    <NpnChallengeEntries
      @slug={{@controller.model.slug}}
      @initialTopics={{@controller.model.topics}}
      @entryCount={{@controller.model.entryCount}}
    />

    <nav class="npn-weekly-challenge__nav">
      {{#if @controller.model.previousChallenge}}
        <LinkTo
          @route="weekly-challenges.show"
          @model={{@controller.model.previousChallenge.slug}}
          class="npn-weekly-challenge__nav-link --previous"
        >
          {{dIcon "chevron-left"}}
          <span class="npn-weekly-challenge__nav-title">
            {{@controller.model.previousChallenge.title}}
          </span>
        </LinkTo>
      {{/if}}
      {{#if @controller.model.nextChallenge}}
        <LinkTo
          @route="weekly-challenges.show"
          @model={{@controller.model.nextChallenge.slug}}
          class="npn-weekly-challenge__nav-link --next"
        >
          <span class="npn-weekly-challenge__nav-title">
            {{@controller.model.nextChallenge.title}}
          </span>
          {{dIcon "chevron-right"}}
        </LinkTo>
      {{/if}}
    </nav>
  </section>
</template>
