import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import CoreTopicList from "discourse/components/topic-list/list";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import TopicList from "discourse/models/topic-list";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

// Pagination state for one challenge. Kept in a separate object keyed on the
// slug because prev/next navigation transitions to the same route with a new
// model — Glimmer reuses this component instance, so per-challenge state
// can't live in once-initialized component fields.
class EntriesState {
  @tracked topics;
  // Set when a fetched page comes back empty, so the button can't loop on
  // empty pages if entries disappear between the count and a later fetch.
  @tracked exhausted = false;

  page = 0;

  constructor(slug, topics) {
    this.slug = slug;
    this.topics = topics;
  }
}

export default class NpnChallengeEntries extends Component {
  @service store;

  @tracked loading = false;

  // Recomputed only when the args change (i.e. when navigating to another
  // challenge); paging mutates the cached object's tracked fields without
  // invalidating it.
  @cached
  get state() {
    return new EntriesState(this.args.slug, [...this.args.initialTopics]);
  }

  get hasMore() {
    const state = this.state;
    return !state.exhausted && state.topics.length < this.args.entryCount;
  }

  @action
  async loadMore() {
    if (this.loading) {
      return;
    }

    this.loading = true;
    // Captured before the await: if the user navigates to another challenge
    // mid-fetch, the result is appended to this (now orphaned) state instead
    // of leaking into the new challenge's list.
    const state = this.state;
    const nextPage = state.page + 1;

    try {
      const result = await ajax(
        `/weekly-challenges/${encodeURIComponent(state.slug)}.json?page=${nextPage}`
      );
      const fetched = TopicList.topicsFrom(this.store, result);
      state.page = nextPage;
      if (fetched.length === 0) {
        state.exhausted = true;
      } else {
        state.topics = [...state.topics, ...fetched];
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  <template>
    <div class="npn-challenge-entries">
      {{#if this.state.topics.length}}
        <CoreTopicList @topics={{this.state.topics}} @showPosters={{true}} />

        {{#if this.hasMore}}
          <DButton
            @action={{this.loadMore}}
            @label="npn_weekly_challenge.load_more"
            @isLoading={{this.loading}}
            class="btn-default npn-challenge-entries__load-more"
          />
        {{/if}}
      {{else}}
        <p class="npn-challenge-entries__empty">
          {{i18n "npn_weekly_challenge.no_entries"}}
        </p>
      {{/if}}
    </div>
  </template>
}
