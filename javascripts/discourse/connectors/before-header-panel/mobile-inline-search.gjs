import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import DButton from "discourse/components/d-button";
import { ALL_PAGES_EXCLUDED_ROUTES } from "discourse/components/welcome-banner";
import bodyClass from "discourse/helpers/body-class";
import { isValidSearchTerm } from "discourse/lib/search";
import getURL from "discourse/lib/get-url";
import closeOnClickOutside from "discourse/modifiers/close-on-click-outside";
import { i18n } from "discourse-i18n";
import { themePrefix } from "virtual:theme";

const HISTORY_KEY = "ibomy_mobile_inline_search_history_v1";
const MAX_HISTORY = 10;

function parseHotItems(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    return [];
  }
  return raw
    .map((row) => {
      if (!row || typeof row !== "object") {
        return null;
      }
      const title = row.title != null ? String(row.title).trim() : "";
      const linkUrl = row.link_url ?? row.href ?? row.link;
      if (!title || linkUrl == null || String(linkUrl).trim() === "") {
        return null;
      }
      return { title, href: String(linkUrl).trim() };
    })
    .filter(Boolean);
}

function readHistory() {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    if (!raw) {
      return [];
    }
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed.filter((x) => typeof x === "string" && x.trim().length > 0);
  } catch {
    return [];
  }
}

function writeHistory(terms) {
  localStorage.setItem(HISTORY_KEY, JSON.stringify(terms.slice(0, MAX_HISTORY)));
}

function resolveNavHref(href) {
  if (!href) {
    return getURL("/");
  }
  const s = String(href).trim();
  if (/^https?:\/\//i.test(s)) {
    return s;
  }
  if (s.startsWith("//")) {
    return getURL("/");
  }
  if (/^[a-z][a-z0-9+.-]*:/i.test(s)) {
    return getURL("/");
  }
  const path = s.startsWith("/") ? s : `/${s}`;
  return getURL(path);
}

export default class MobileInlineSearch extends Component {
  @service site;
  @service siteSettings;
  @service currentUser;
  @service router;
  @service search;
  @service toasts;

  @tracked searchTerm = "";
  @tracked dropdownOpen = false;
  @tracked history = [];

  get coreHeaderSearchVisible() {
    if (this.site.mobileView || this.site.narrowDesktopView) {
      return false;
    }
    if (
      ALL_PAGES_EXCLUDED_ROUTES.some(
        (n) => n === this.router.currentRouteName
      ) ||
      this.search.welcomeBannerSearchInViewport ||
      this.router.currentRouteName?.startsWith("admin")
    ) {
      return false;
    }
    return (
      this.search.searchExperience === "search_field" &&
      !this.args.topicInfoVisible &&
      !this.search.welcomeBannerSearchInViewport
    );
  }

  get shouldDisplay() {
    if (!settings.mobile_inline_search_enabled) {
      return false;
    }
    if (this.coreHeaderSearchVisible) {
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

  get hotItems() {
    return parseHotItems(settings.mobile_inline_search_hot_items || []);
  }

  @action
  syncHistory() {
    this.history = readHistory();
  }

  @action
  openDropdown() {
    this.syncHistory();
    this.dropdownOpen = true;
  }

  @action
  closeDropdown() {
    this.dropdownOpen = false;
  }

  @action
  onInput(event) {
    this.searchTerm = event.target.value;
  }

  @action
  onInputKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.submitSearch();
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      this.closeDropdown();
    }
  }

  @action
  submitSearch() {
    const term = this.searchTerm.trim();
    if (!term) {
      return;
    }
    if (!isValidSearchTerm(term, this.siteSettings)) {
      this.toasts.error({
        duration: "short",
        data: { message: i18n("search.too_short") },
      });
      return;
    }

    const next = [term, ...readHistory().filter((t) => t !== term)];
    writeHistory(next);

    this.closeDropdown();
    this.router.transitionTo("full-page-search", {
      queryParams: { q: term },
    });
  }

  @action
  selectHistoryTerm(term) {
    this.searchTerm = term;
    this.submitSearch();
  }

  @action
  onHistoryRowClick(event) {
    const term = event.currentTarget?.getAttribute?.("data-term");
    if (term == null) {
      return;
    }
    this.selectHistoryTerm(term);
  }

  @action
  clearHistory(event) {
    event?.preventDefault?.();
    localStorage.removeItem(HISTORY_KEY);
    this.syncHistory();
  }

  @action
  onHotRowClick(event) {
    const href = event.currentTarget?.getAttribute?.("data-href");
    if (href == null) {
      return;
    }
    event.preventDefault();
    window.location.assign(resolveNavHref(href));
  }

  @action
  clearSearchTerm(event) {
    event.preventDefault();
    this.searchTerm = "";
  }

  <template>
    {{#if this.shouldDisplay}}
      {{bodyClass "ibomy-mobile-inline-search--enabled"}}
      <div
        class="ibomy-mobile-inline-search"
        {{closeOnClickOutside this.closeDropdown}}
      >
        <div class="ibomy-mobile-inline-search__pill">
          <DButton
            @icon="magnifying-glass"
            @title={{i18n "search.search_button"}}
            class="btn search-icon ibomy-mobile-inline-search__icon-btn"
            @action={{this.submitSearch}}
          />
          <div class="ibomy-mobile-inline-search__field">
            <input
              id="mobile-inline-search-input"
              type="search"
              autocomplete="off"
              class="ibomy-mobile-inline-search__input"
              placeholder={{i18n (themePrefix "inline_search.placeholder")}}
              aria-label={{i18n (themePrefix "inline_search.placeholder")}}
              value={{this.searchTerm}}
              {{on "input" this.onInput}}
              {{on "keydown" this.onInputKeydown}}
              {{on "focus" this.openDropdown}}
            />
            {{#if this.searchTerm}}
              <button
                type="button"
                class="btn-flat ibomy-mobile-inline-search__clear-input"
                title={{i18n "search.clear_search"}}
                {{on "click" this.clearSearchTerm}}
              >×</button>
            {{/if}}
            {{#if this.dropdownOpen}}
              <div class="ibomy-mobile-inline-search__dropdown">
                {{#if this.history.length}}
                  <div class="ibomy-mobile-inline-search__section">
                    <div class="ibomy-mobile-inline-search__section-head">
                      <span class="ibomy-mobile-inline-search__section-title">{{i18n
                          (themePrefix "inline_search.history_heading")
                        }}</span>
                      <button
                        type="button"
                        class="btn-flat ibomy-mobile-inline-search__section-action"
                        {{on "click" this.clearHistory}}
                      >{{i18n (themePrefix "inline_search.clear_history")}}</button>
                    </div>
                    <ul class="ibomy-mobile-inline-search__list">
                      {{#each this.history as |term|}}
                        <li>
                          <button
                            type="button"
                            class="ibomy-mobile-inline-search__list-item"
                            data-term={{term}}
                            {{on "click" this.onHistoryRowClick}}
                          >{{term}}</button>
                        </li>
                      {{/each}}
                    </ul>
                  </div>
                {{/if}}
                {{#if this.hotItems.length}}
                  <div class="ibomy-mobile-inline-search__section">
                    <div class="ibomy-mobile-inline-search__section-head">
                      <span class="ibomy-mobile-inline-search__section-title">{{i18n
                          (themePrefix "inline_search.hot_heading")
                        }}</span>
                    </div>
                    <ul class="ibomy-mobile-inline-search__list">
                      {{#each this.hotItems as |item|}}
                        <li>
                          <button
                            type="button"
                            class="ibomy-mobile-inline-search__list-link"
                            data-href={{item.href}}
                            {{on "click" this.onHotRowClick}}
                          >{{item.title}}</button>
                        </li>
                      {{/each}}
                    </ul>
                  </div>
                {{/if}}
              </div>
            {{/if}}
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}
