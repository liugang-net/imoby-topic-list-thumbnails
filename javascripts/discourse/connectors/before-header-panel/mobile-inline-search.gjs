import Component from "@glimmer/component";
import { modifier } from "ember-modifier";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import SearchMenu from "discourse/components/search-menu";
import bodyClass from "discourse/helpers/body-class";

const MOBILE_INLINE_SEARCH_PLACEHOLDER = "啵咪·个性化定制";

export default class MobileInlineSearch extends Component {
  @service site;
  @service siteSettings;
  @service currentUser;
  @service router;

  advancedSearchButtonHref = "/search?expanded=true";

  syncRawPlaceholder = modifier((element) => {
    const text = MOBILE_INLINE_SEARCH_PLACEHOLDER;
    const apply = () => {
      const input =
        element.querySelector("#mobile-inline-search-input") ||
        document.getElementById("mobile-inline-search-input");
      if (!input) {
        return;
      }
      if (input.placeholder !== text) {
        input.placeholder = text;
      }
      if (input.getAttribute("aria-label") !== text) {
        input.setAttribute("aria-label", text);
      }
    };

    apply();

    const observer = new MutationObserver(apply);
    observer.observe(element, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ["placeholder", "aria-label", "id"],
    });

    return () => observer.disconnect();
  });

  get shouldDisplay() {
    if (!settings.mobile_inline_search_enabled) {
      return false;
    }
    if (!this.site.mobileView) {
      return false;
    }
    if (this.siteSettings.login_required && !this.currentUser) {
      return false;
    }
    if (this.args.topicInfoVisible) {
      return false;
    }
    const name = this.router.currentRouteName;
    if (name?.startsWith("admin")) {
      return false;
    }
    if (name === "full-page-search") {
      return false;
    }
    return true;
  }

  <template>
    {{#if this.shouldDisplay}}
      {{bodyClass "ibomy-mobile-inline-search--enabled"}}
      <div class="ibomy-mobile-inline-search" {{this.syncRawPlaceholder}}>
        <div class="ibomy-mobile-inline-search__pill">
          <DButton
            @icon="magnifying-glass"
            @title="search.open_advanced"
            class="btn search-icon ibomy-mobile-inline-search__icon-btn"
            @href={{this.advancedSearchButtonHref}}
          />
          <SearchMenu
            @location="header"
            @searchInputId="mobile-inline-search-input"
          />
        </div>
      </div>
    {{/if}}
  </template>
}
