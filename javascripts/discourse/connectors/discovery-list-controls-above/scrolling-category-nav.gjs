import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import DropdownMenu from "discourse/components/dropdown-menu";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import DMenu from "discourse/float-kit/components/d-menu";
import { bind } from "discourse/lib/decorators";
import getURL, { withoutPrefix } from "discourse/lib/get-url";
import NavItem from "discourse/models/nav-item";
import { i18n } from "discourse-i18n";

const FILTER_TYPES = ["latest", "hot", "categories"];

// 仅允许在触发器上/下翻转，禁止 flip 到左侧或右侧（否则会在「最新」右边弹出）
const FILTER_MENU_FALLBACK_PLACEMENTS = [
  "bottom-start",
  "bottom",
  "bottom-end",
  "top-start",
  "top",
  "top-end",
];

export default class ScrollingCategoryNav extends Component {
  @service site;
  @service router;

  @tracked urlVersion = 0;

  constructor() {
    super(...arguments);
    this.setupActiveState();
    this.router?.on?.("routeDidChange", this, this.bumpUrlVersion);
  }

  willDestroy() {
    super.willDestroy();

    this.router?.off?.("routeDidChange", this, this.bumpUrlVersion);

    if (this.urlWatcher) {
      window.removeEventListener("popstate", this.urlWatcher);
    }

    if (this._originalPushState) {
      history.pushState = this._originalPushState;
      history.replaceState = this._originalReplaceState;
    }

    if (this.navItems) {
      this.navItems.forEach((item) => {
        if (item.clickHandler) {
          item.removeEventListener("click", item.clickHandler);
          item.clickHandler = null;
        }
      });
    }

    this.navItems = null;
  }

  get shouldRender() {
    return settings.show_scrolling_category_nav;
  }

  get allowedCategories() {
    if (!settings.scrolling_nav_categories) {
      return [];
    }
    return settings.scrolling_nav_categories.split("|").map((id) => parseInt(id, 10));
  }

  get backgroundColor() {
    return settings.scrolling_nav_background_color;
  }

  get navStyle() {
    return `background-color: ${this.backgroundColor};`;
  }

  get pathContext() {
    return {
      category: this.args.category,
      tag: this.args.tag,
      noSubcategories: false,
    };
  }

  get filterMenuItems() {
    this.urlVersion;
    this.router?.currentURL;
    const current = this.currentFilter;
    return FILTER_TYPES.map((name) => ({
      name,
      href: NavItem.pathFor(name, this.pathContext),
      label: i18n(`filters.${name}.title`),
      isActive: current === name,
    }));
  }

  get filterTriggerLabel() {
    this.urlVersion;
    this.router?.currentURL;
    const f = this.currentFilter;
    return i18n(`filters.${f}.title`);
  }

  get currentFilter() {
    this.urlVersion;
    this.router?.currentURL;
    return this._filterFromPath(this.applicationPathname);
  }

  get applicationPathname() {
    try {
      return withoutPrefix(window.location.pathname) || "/";
    } catch {
      return window.location.pathname || "/";
    }
  }

  _filterFromPath(pathname) {
    const p = pathname || "/";
    if (p === "/categories") {
      return "categories";
    }
    const lMatch = p.match(/\/l\/([^/]+)/);
    if (lMatch) {
      const seg = lMatch[1];
      if (seg === "hot") {
        return "hot";
      }
      if (seg === "categories") {
        return "categories";
      }
      if (seg === "latest") {
        return "latest";
      }
      return "latest";
    }
    if (p === "/hot" || p.startsWith("/hot/")) {
      return "hot";
    }
    return "latest";
  }

  @bind
  bumpUrlVersion() {
    this.urlVersion++;
  }

  @action
  onRegisterFilterMenuApi(api) {
    this.filterMenuApi = api;
  }

  @action
  closeFilterMenu() {
    this.filterMenuApi?.close?.();
  }

  setupActiveState() {
    requestAnimationFrame(() => {
      this.updateActiveState();
      this.setupClickHandlers();
    });

    this.setupUrlWatcher();
  }

  setupClickHandlers() {
    if (this.navItems && this.navItems.length > 0) {
      this.navItems.forEach((item) => {
        if (item.clickHandler) {
          item.removeEventListener("click", item.clickHandler);
        }

        item.clickHandler = () => {
          this.updateActiveStateOnClick(item);
        };

        item.addEventListener("click", item.clickHandler);
      });
    }
  }

  updateActiveStateOnClick(clickedItem) {
    if (this.navItems) {
      this.navItems.forEach((item) => {
        item.classList.remove("active");
      });
    }

    clickedItem.classList.add("active");
  }

  setupUrlWatcher() {
    let lastUrl = this.applicationPathname;

    this.urlWatcher = () => {
      const currentUrl = this.applicationPathname;
      if (currentUrl !== lastUrl) {
        lastUrl = currentUrl;
        this.bumpUrlVersion();
        this.updateActiveState();
      }
    };

    window.addEventListener("popstate", this.urlWatcher);

    this._originalPushState = history.pushState;
    this._originalReplaceState = history.replaceState;

    history.pushState = (...args) => {
      this._originalPushState.apply(history, args);
      setTimeout(() => this.urlWatcher(), 0);
    };

    history.replaceState = (...args) => {
      this._originalReplaceState.apply(history, args);
      setTimeout(() => this.urlWatcher(), 0);
    };
  }

  get categories() {
    if (!this.site?.categories) {
      return [];
    }

    const allCategories = this.site.categories;
    const allowedIds = this.allowedCategories;

    const filtered = allCategories
      .filter((category) => {
        const isPublic = category.read_restricted === false;
        const isTopLevel =
          category.parent_category_id === null ||
          category.parent_category_id === undefined;
        const isAllowed =
          allowedIds.length === 0 || allowedIds.includes(category.id);

        return isPublic && isTopLevel && isAllowed;
      })
      .sort((a, b) => a.position - b.position);

    return filtered;
  }

  get categoryUrl() {
    return (category) => {
      const slug = category.slug || category.id.toString();
      return `/c/${slug}/${category.id}`;
    };
  }

  get homeUrl() {
    return getURL("/");
  }

  get homeLabel() {
    return i18n("js.home");
  }

  isHomeActivePath(pathname) {
    const p = pathname || "/";
    if (p === "/") {
      return true;
    }
    if (p === "/latest" || p.startsWith("/latest/")) {
      return true;
    }
    return false;
  }

  updateActiveState() {
    const currentPath = this.applicationPathname;

    this.navItems = document.querySelectorAll(
      ".scrolling-category-nav .nav-items-scroll .nav-item"
    );

    if (this.navItems.length === 0) {
      return;
    }

    const currentCategoryId = this.extractCategoryId(currentPath);

    this.navItems.forEach((item) => {
      const href = item.getAttribute("href");
      let isActive = false;

      if (item.classList.contains("nav-item--home")) {
        isActive = this.isHomeActivePath(currentPath);
      } else if (href && href.startsWith("/c/") && currentCategoryId) {
        const hrefCategoryId = this.extractCategoryId(href);
        if (hrefCategoryId === currentCategoryId) {
          isActive = true;
        }
      }

      item.classList.toggle("active", isActive);
    });
  }

  extractCategoryId(path) {
    const match = path.match(/^\/c\/[^/]+\/(\d+)/);
    return match ? match[1] : null;
  }

  <template>
    <div class="scrolling-category-nav" style={{this.navStyle}}>
      <div class="nav-container">
        <div class="nav-container__filter">
          <DMenu
            @modalForMobile={{false}}
            @placement="bottom-start"
            @visibilityOptimizer="none"
            @fallbackPlacements={{FILTER_MENU_FALLBACK_PLACEMENTS}}
            @identifier="ibomy-scrolling-category-nav-filter"
            @onRegisterApi={{this.onRegisterFilterMenuApi}}
            @triggerClass="scrolling-category-nav__filter-trigger"
            @contentClass="scrolling-category-nav__filter-panel"
          >
            <:trigger>
              <span class="scrolling-category-nav__filter-trigger-inner">
                <span
                  class="scrolling-category-nav__filter-trigger-label"
                >{{this.filterTriggerLabel}}</span>
                {{icon "angle-down"}}
              </span>
            </:trigger>
            <:content>
              <div class="scrolling-category-nav__filter-dropdown">
                <DropdownMenu
                  class="scrolling-category-nav__filter-menu"
                  {{on "click" this.closeFilterMenu}}
                  as |dropdown|
                >
                  {{#each this.filterMenuItems key="name" as |item|}}
                    <dropdown.item>
                      <a
                        href={{item.href}}
                        data-filter-active={{if item.isActive "true" "false"}}
                        class={{concatClass
                          "scrolling-category-nav__filter-link"
                          (if item.isActive "scrolling-category-nav__filter-link--active")
                        }}
                      >
                        <span
                          class="scrolling-category-nav__filter-link-label"
                        >{{item.label}}</span>
                        {{icon
                          "chevron-right"
                          class="scrolling-category-nav__filter-link-icon"
                        }}
                      </a>
                    </dropdown.item>
                  {{/each}}
                </DropdownMenu>
              </div>
            </:content>
          </DMenu>
        </div>

        <div class="nav-container__scroll">
          <div class="nav-items nav-items-scroll">
            <a href={{this.homeUrl}} class="nav-item nav-item--home">
              {{this.homeLabel}}
            </a>
            {{#each this.categories as |category|}}
              <a href={{this.categoryUrl category}} class="nav-item">
                {{category.name}}
              </a>
            {{/each}}
          </div>
        </div>
      </div>
    </div>
  </template>
}
