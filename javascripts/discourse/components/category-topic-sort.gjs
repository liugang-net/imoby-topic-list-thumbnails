import Component from "@glimmer/component";
import { service } from "@ember/service";
import { themePrefix } from "virtual:theme";
import getURL from "discourse/lib/get-url";
import { i18n } from "discourse-i18n";

export default class CategoryTopicSort extends Component {
  @service router;

  get currentPath() {
    return (this.router.currentURL || "").split(/[?#]/, 1)[0];
  }

  get categoryPath() {
    return this.currentPath.replace(/\/l\/[^/]+\/?$/, "").replace(/\/$/, "");
  }

  get shouldRender() {
    return this.categoryPath.startsWith("/c/");
  }

  get isHot() {
    return /\/l\/hot\/?$/.test(this.currentPath);
  }

  get latestHref() {
    return getURL(`${this.categoryPath}/l/latest`);
  }

  get hotHref() {
    return getURL(`${this.categoryPath}/l/hot`);
  }

  <template>
    {{#if this.shouldRender}}
      <nav
        class="category-topic-sort"
        aria-label={{i18n (themePrefix "topic_list_sort.label")}}
      >
        <span class="category-topic-sort__label">
          {{i18n (themePrefix "topic_list_sort.label")}}
        </span>
        <div class="category-topic-sort__options">
          <a
            href={{this.latestHref}}
            class={{if
              this.isHot
              "category-topic-sort__option"
              "category-topic-sort__option is-active"
            }}
            aria-current={{unless this.isHot "page"}}
          >
            {{i18n (themePrefix "topic_list_sort.latest")}}
          </a>
          <a
            href={{this.hotHref}}
            class={{if
              this.isHot
              "category-topic-sort__option is-active"
              "category-topic-sort__option"
            }}
            aria-current={{if this.isHot "page"}}
          >
            {{i18n (themePrefix "topic_list_sort.hot")}}
          </a>
        </div>
      </nav>
    {{/if}}
  </template>
}
