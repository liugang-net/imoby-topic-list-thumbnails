import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { getOwner } from "@ember/owner";
import { htmlSafe } from "@ember/template";
import { cancel, schedule } from "@ember/runloop";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import DButton from "discourse/components/d-button";
import { ALL_PAGES_EXCLUDED_ROUTES } from "discourse/components/welcome-banner";
import bodyClass from "discourse/helpers/body-class";
import discourseDebounce from "discourse/lib/debounce";
import DiscourseURL from "discourse/lib/url";
import { isValidSearchTerm, searchForTerm } from "discourse/lib/search";
import getURL from "discourse/lib/get-url";
import { escapeExpression } from "discourse/lib/utilities";
import closeOnClickOutside from "discourse/modifiers/close-on-click-outside";

const HISTORY_KEY = "ibomy_mobile_inline_search_history_v1";
const MAX_HISTORY = 10;
const MAX_TOPIC_SUGGEST = 9;
const SUGGEST_DEBOUNCE_MS = 280;

function sanitizeCssColor(value) {
  if (value == null || typeof value !== "string") {
    return null;
  }
  const s = value.trim();
  if (s.length === 0 || s.length > 80) {
    return null;
  }
  if (
    /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(s)
  ) {
    return s;
  }
  if (/^rgba?\(\s*[\d\s.,%]+\s*\)$/.test(s)) {
    return s;
  }
  if (/^hsla?\(\s*[\d.\s,%]+\s*\)$/.test(s)) {
    return s;
  }
  return null;
}

function presetBadgeLabel(badge) {
  if (badge === "hot") {
    return "热";
  }
  if (badge === "new") {
    return "新";
  }
  if (badge === "exclusive") {
    return "独家";
  }
  return null;
}

function parsePresetBadge(rawBadge) {
  if (rawBadge == null) {
    return null;
  }
  const b = String(rawBadge).trim().toLowerCase();
  if (b === "hot" || b === "热") {
    return "hot";
  }
  if (b === "new" || b === "新") {
    return "new";
  }
  if (b === "exclusive" || b === "独家") {
    return "exclusive";
  }
  return null;
}

function buildBadgeStyle(textColor, bgColor) {
  const parts = [];
  if (bgColor) {
    parts.push(`background-color:${bgColor}`);
  }
  if (textColor) {
    parts.push(`color:${textColor}`);
  }
  if (parts.length === 0) {
    return null;
  }
  return htmlSafe(parts.join(";"));
}

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
      const badgeColor = sanitizeCssColor(row.badge_color);
      const badgeBgColor = sanitizeCssColor(row.badge_bg_color);

      const fromBadge = row.badge != null ? String(row.badge).trim() : "";
      const fromTag = row.tag != null ? String(row.tag).trim() : "";
      const fromLegacyBadgeText =
        row.badge_text != null ? String(row.badge_text).trim() : "";
      const rawBadgeStr = fromBadge || fromTag || fromLegacyBadgeText;

      if (rawBadgeStr.length === 0) {
        return { title, href: String(linkUrl).trim(), badge: null };
      }

      const preset = parsePresetBadge(rawBadgeStr);
      const badgeLabel = preset ? presetBadgeLabel(preset) : rawBadgeStr;
      const badgeKind = preset ?? "custom";

      return {
        title,
        href: String(linkUrl).trim(),
        badge: preset,
        badgeKind,
        badgeLabel,
        badgeStyle: buildBadgeStyle(badgeColor, badgeBgColor),
      };
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

function termRowHtml(term) {
  const e = escapeExpression(term);
  return `<span class="ibomy-mobile-inline-search__suggest-q">${e}</span>`;
}

function buildPlainTitleHighlight(title, term) {
  if (!title) {
    return "";
  }
  const t = term.trim();
  if (!t) {
    return escapeExpression(title);
  }
  const lower = title.toLowerCase();
  const idx = lower.indexOf(t.toLowerCase());
  if (idx === -1) {
    return escapeExpression(title);
  }
  const before = escapeExpression(title.slice(0, idx));
  const mid = escapeExpression(title.slice(idx, idx + t.length));
  const after = escapeExpression(title.slice(idx + t.length));
  return `${before}<span class="ibomy-mobile-inline-search__suggest-q">${mid}</span>${after}`;
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
  @service appEvents;

  @tracked searchTerm = "";
  @tracked dropdownOpen = false;
  @tracked history = [];
  @tracked historyExpanded = true;
  @tracked suggestRows = [];
  @tracked suggestLoading = false;

  _suggestRequest = null;
  _suggestDebounceTimer = null;

  constructor() {
    super(...arguments);
    this.router.on(
      "routeDidChange",
      this,
      this.syncInlineSearchFromFullPageController
    );
    this.appEvents.on(
      "full-page-search:trigger-search",
      this,
      this.syncInlineSearchFromFullPageController
    );
    schedule("afterRender", () => {
      this.syncInlineSearchFromFullPageController();
    });
  }

  get portalSearchUiEnabled() {
    return (
      this.siteSettings.ibomy_portal_enabled &&
      this.siteSettings.ibomy_portal_search_ui
    );
  }

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
      return this.portalSearchUiEnabled;
    }
    return true;
  }

  get hotItems() {
    return parseHotItems(settings.mobile_inline_search_hot_items || []);
  }

  get hasTypedQuery() {
    return this.searchTerm.trim().length > 0;
  }

  get showIdlePanel() {
    return !this.hasTypedQuery;
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.router.off(
      "routeDidChange",
      this,
      this.syncInlineSearchFromFullPageController
    );
    this.appEvents.off(
      "full-page-search:trigger-search",
      this,
      this.syncInlineSearchFromFullPageController
    );
    this._suggestRequest?.abort?.();
    if (this._suggestDebounceTimer != null) {
      cancel(this._suggestDebounceTimer);
      this._suggestDebounceTimer = null;
    }
  }

  @action
  syncInlineSearchFromFullPageController() {
    if (!this.portalSearchUiEnabled) {
      return;
    }
    if (this.router.currentRouteName !== "full-page-search") {
      return;
    }
    const c = getOwner(this).lookup("controller:full-page-search");
    const st = c?.searchTerm;
    if (st != null && this.searchTerm !== st) {
      this.searchTerm = st;
    }
  }

  @action
  syncHistory() {
    this.history = readHistory();
  }

  @action
  openDropdown() {
    this.syncHistory();
    this.dropdownOpen = true;
    const t = this.searchTerm.trim();
    if (
      t.length > 0 &&
      isValidSearchTerm(t, this.siteSettings)
    ) {
      if (this._suggestDebounceTimer != null) {
        cancel(this._suggestDebounceTimer);
      }
      this._suggestDebounceTimer = discourseDebounce(
        this,
        this.runTopicSuggest,
        SUGGEST_DEBOUNCE_MS
      );
    }
  }

  @action
  closeDropdown() {
    this.dropdownOpen = false;
  }

  @action
  onInput(event) {
    this.searchTerm = event.target.value;
    if (!this.hasTypedQuery) {
      if (this._suggestDebounceTimer != null) {
        cancel(this._suggestDebounceTimer);
        this._suggestDebounceTimer = null;
      }
      this.suggestRows = [];
      this.suggestLoading = false;
      this._suggestRequest?.abort?.();
      this._suggestRequest = null;
      return;
    }
    if (this._suggestDebounceTimer != null) {
      cancel(this._suggestDebounceTimer);
    }
    this._suggestDebounceTimer = discourseDebounce(
      this,
      this.runTopicSuggest,
      SUGGEST_DEBOUNCE_MS
    );
  }

  @action
  async runTopicSuggest() {
    const term = this.searchTerm.trim();
    if (!term) {
      this.suggestRows = [];
      this.suggestLoading = false;
      return;
    }
    if (!isValidSearchTerm(term, this.siteSettings)) {
      this.suggestRows = [];
      this.suggestLoading = false;
      return;
    }

    this._suggestRequest?.abort?.();
    this.suggestLoading = true;

    const req = searchForTerm(term, { typeFilter: "topic" });
    this._suggestRequest = req;

    try {
      const results = await req;
      if (this._suggestRequest !== req) {
        return;
      }

      const posts = results.posts || [];
      const slice = posts.slice(0, MAX_TOPIC_SUGGEST);
      const rows = [
        {
          kind: "term",
          term,
          titleSafe: htmlSafe(termRowHtml(term)),
        },
      ];

      for (const post of slice) {
        const topic = post.topic;
        if (!topic) {
          continue;
        }
        const titlePlain = topic.title;
        let titleHtmlStr;
        if (
          this.siteSettings.use_pg_headlines_for_excerpt &&
          post.topic_title_headline
        ) {
          titleHtmlStr = post.topic_title_headline;
        } else {
          titleHtmlStr = buildPlainTitleHighlight(titlePlain || "", term);
        }
        const url = topic.url || getURL("/");
        rows.push({
          kind: "topic",
          url,
          titleSafe: htmlSafe(titleHtmlStr),
        });
      }

      this.suggestRows = rows;
    } catch {
      if (this._suggestRequest === req) {
        this.suggestRows = [
          {
            kind: "term",
            term,
            titleSafe: htmlSafe(termRowHtml(term)),
          },
        ];
      }
    } finally {
      if (this._suggestRequest === req) {
        this.suggestLoading = false;
        this._suggestRequest = null;
      }
    }
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
        data: { message: "搜索词太短" },
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
  toggleHistoryExpanded(event) {
    event?.preventDefault?.();
    this.historyExpanded = !this.historyExpanded;
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
    this.suggestRows = [];
    this.suggestLoading = false;
  }

  @action
  onSuggestRowClick(row, event) {
    event?.preventDefault?.();
    if (row.kind === "term") {
      this.searchTerm = row.term;
      this.submitSearch();
      return;
    }
    const term = this.searchTerm.trim();
    if (term && isValidSearchTerm(term, this.siteSettings)) {
      const next = [term, ...readHistory().filter((t) => t !== term)];
      writeHistory(next);
      this.syncHistory();
    }
    this.closeDropdown();
    DiscourseURL.routeTo(row.url);
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
            @title="搜索"
            class="btn search-icon ibomy-mobile-inline-search__icon-btn"
            @action={{this.submitSearch}}
          />
          <div class="ibomy-mobile-inline-search__field">
            <input
              id="mobile-inline-search-input"
              type="search"
              autocomplete="off"
              class="ibomy-mobile-inline-search__input"
              placeholder="啵咪·个性化定制"
              aria-label="啵咪·个性化定制"
              value={{this.searchTerm}}
              {{on "input" this.onInput}}
              {{on "keydown" this.onInputKeydown}}
              {{on "focus" this.openDropdown}}
            />
            {{#if this.searchTerm}}
              <button
                type="button"
                class="btn-flat ibomy-mobile-inline-search__clear-input"
                title="清除搜索"
                {{on "click" this.clearSearchTerm}}
              >×</button>
            {{/if}}
            {{#if this.dropdownOpen}}
              <div class="ibomy-mobile-inline-search__dropdown">
                {{#if this.showIdlePanel}}
                  {{#if this.hotItems.length}}
                    <div class="ibomy-mobile-inline-search__section">
                      <div class="ibomy-mobile-inline-search__section-head">
                        <span class="ibomy-mobile-inline-search__section-title">bomi热搜</span>
                      </div>
                      <div class="ibomy-mobile-inline-search__hot-grid">
                        {{#each this.hotItems as |item|}}
                          <button
                            type="button"
                            class="ibomy-mobile-inline-search__hot-item"
                            data-href={{item.href}}
                            {{on "click" this.onHotRowClick}}
                          >
                            <span class="ibomy-mobile-inline-search__hot-title">{{item.title}}</span>
                            {{#if item.badgeLabel}}
                              <span
                                class="ibomy-mobile-inline-search__hot-badge ibomy-mobile-inline-search__hot-badge--{{item.badgeKind}}"
                                style={{item.badgeStyle}}
                              >{{item.badgeLabel}}</span>
                            {{/if}}
                          </button>
                        {{/each}}
                      </div>
                    </div>
                  {{/if}}
                  {{#if this.history.length}}
                    <div class="ibomy-mobile-inline-search__section ibomy-mobile-inline-search__section--history">
                      <div class="ibomy-mobile-inline-search__section-head">
                        <span class="ibomy-mobile-inline-search__section-title">搜索历史</span>
                        <div class="ibomy-mobile-inline-search__section-actions">
                          <DButton
                            @icon="trash-can"
                            @title="清空搜索历史"
                            class="btn-flat ibomy-mobile-inline-search__icon-action"
                            @action={{this.clearHistory}}
                          />
                          <DButton
                            @icon={{if this.historyExpanded "angle-down" "angle-right"}}
                            @title={{if this.historyExpanded "收起" "展开"}}
                            class="btn-flat ibomy-mobile-inline-search__icon-action"
                            @action={{this.toggleHistoryExpanded}}
                          />
                        </div>
                      </div>
                      {{#if this.historyExpanded}}
                        <div class="ibomy-mobile-inline-search__history-chips">
                          {{#each this.history as |term|}}
                            <button
                              type="button"
                              class="ibomy-mobile-inline-search__history-chip"
                              data-term={{term}}
                              {{on "click" this.onHistoryRowClick}}
                            >{{term}}</button>
                          {{/each}}
                        </div>
                      {{/if}}
                    </div>
                  {{/if}}
                {{else}}
                  <div class="ibomy-mobile-inline-search__suggest">
                    {{#if this.suggestLoading}}
                      <div class="ibomy-mobile-inline-search__suggest-loading">搜索中…</div>
                    {{else}}
                      <ul class="ibomy-mobile-inline-search__suggest-list">
                        {{#each this.suggestRows as |row|}}
                          <li class="ibomy-mobile-inline-search__suggest-li">
                            <button
                              type="button"
                              class="ibomy-mobile-inline-search__suggest-line"
                              {{on "click" (fn this.onSuggestRowClick row)}}
                            >
                              <span class="ibomy-mobile-inline-search__suggest-line-inner">{{row.titleSafe}}</span>
                            </button>
                          </li>
                        {{/each}}
                      </ul>
                    {{/if}}
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
