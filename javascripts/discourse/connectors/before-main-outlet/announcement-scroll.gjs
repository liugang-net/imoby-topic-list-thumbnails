import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { bind } from "discourse/lib/decorators";
import { withoutPrefix } from "discourse/lib/get-url";
import { and } from "discourse/truth-helpers";

// 与 ibomy-hero-carousel.gjs 相同范围：仅首页、最新、分类、标签相关页（并排除话题/用户/后台等）
const ANNOUNCEMENT_EXCLUDED_PREFIXES = [
  "/login",
  "/admin",
  "/t/",
  "/u/",
  "/about",
  "/faq",
  "/tos",
  "/privacy",
  "/session",
  "/admin/",
  "/my/",
  "/preferences",
  "/notifications",
  "/messages",
  "/badges",
  "/groups",
  "/search",
  "/top",
  "/unread",
  "/new",
  "/bookmarks",
  "/activity",
  "/summary",
];

const ANNOUNCEMENT_ALLOWED_PREFIXES = [
  "/",
  "/latest",
  "/c/",
  "/tags",
  "/tag/",
];

function applicationPathFromWindow() {
  if (typeof window === "undefined") {
    return "/";
  }
  try {
    return withoutPrefix(window.location.pathname) || "/";
  } catch {
    return window.location.pathname || "/";
  }
}

function isAnnouncementEligiblePath(path) {
  const p = path || "";
  if (ANNOUNCEMENT_EXCLUDED_PREFIXES.some((x) => p.startsWith(x))) {
    return false;
  }
  return ANNOUNCEMENT_ALLOWED_PREFIXES.some((x) => {
    if (x === "/") {
      return p === "/" || p === "";
    }
    return p.startsWith(x);
  });
}

export default class AnnouncementScroll extends Component {
  @service site;
  @service router;

  @tracked _routeEpoch = 0;

  constructor() {
    super(...arguments);
    this.router?.on("routeDidChange", this, this.onRouteDidChange);
    this.setupScrollAnimation();
  }

  willDestroy() {
    super.willDestroy();
    this.router?.off("routeDidChange", this, this.onRouteDidChange);
    if (this.scrollTimer) {
      clearInterval(this.scrollTimer);
      this.scrollTimer = null;
    }
  }

  @bind
  onRouteDidChange() {
    this._routeEpoch++;
  }

  get applicationPath() {
    this._routeEpoch;
    return applicationPathFromWindow();
  }

  get announcements() {
    return this.site?.category_announcements || [];
  }

  get showOnMobile() {
    return true;
  }

  get shouldShow() {
    this._routeEpoch;
    if (!this.announcements.length) {
      return false;
    }
    if (!isAnnouncementEligiblePath(this.applicationPath)) {
      return false;
    }
    const isMobile = window.innerWidth <= 768;
    if (isMobile && !this.showOnMobile) {
      return false;
    }
    return true;
  }

  get backgroundColor() {
    return settings.announcement_background_color;
  }

  get announcementStyle() {
    this._routeEpoch;
    if (!this.shouldShow) {
      return "display: none;";
    }
    return `display: block; background-color: ${this.backgroundColor};`;
  }

  get topicUrl() {
    return (announcement) => {
      return `/t/${announcement.slug}/${announcement.id}`;
    };
  }

  setupScrollAnimation() {
    setTimeout(() => {
      this.startScrollAnimation();
    }, 1000);
  }

  startScrollAnimation() {
    if (!isAnnouncementEligiblePath(applicationPathFromWindow())) {
      return;
    }
    const container = document.querySelector(".announcement-scroll-container");
    if (!container) {
      return;
    }

    const content = container.querySelector(".announcement-content");
    if (!content) {
      return;
    }

    if (this.announcements.length <= 1) {
      return;
    }

    const scrollInterval = 3000;
    let currentIndex = 0;
    const isMobile = window.innerWidth <= 768;
    const itemHeight = isMobile ? 36 : 40;

    const scrollToNext = () => {
      currentIndex++;
      const translateY = -currentIndex * itemHeight;
      content.style.transform = `translateY(${translateY}px)`;

      if (currentIndex >= this.announcements.length) {
        setTimeout(() => {
          currentIndex = 0;
          content.style.transition = "none";
          content.style.transform = "translateY(0)";
          setTimeout(() => {
            content.style.transition = "transform 0.5s ease";
          }, 50);
        }, 500);
      }
    };

    this.scrollTimer = setInterval(scrollToNext, scrollInterval);

    const announcementElement = document.querySelector(".announcement-scroll");
    if (announcementElement) {
      announcementElement.addEventListener("mouseenter", () => {
        if (this.scrollTimer) {
          clearInterval(this.scrollTimer);
          this.scrollTimer = null;
        }
      });

      announcementElement.addEventListener("mouseleave", () => {
        if (!this.scrollTimer) {
          this.scrollTimer = setInterval(scrollToNext, scrollInterval);
        }
      });
    }
  }

  <template>
    {{#if (and this.announcements.length this.shouldShow)}}
      <div class="announcement-scroll">
        <div class="announcement-scroll-container">
          <div class="announcement-content">
            {{#each this.announcements as |announcement|}}
              <a href={{this.topicUrl announcement}} class="announcement-item">
                <span class="announcement-badge">公告</span>
                <span class="announcement-title">{{announcement.title}}</span>
              </a>
            {{/each}}
            {{#each this.announcements as |announcement|}}
              <a href={{this.topicUrl announcement}} class="announcement-item">
                <span class="announcement-badge">公告</span>
                <span class="announcement-title">{{announcement.title}}</span>
              </a>
            {{/each}}
          </div>
        </div>
        <div class="announcement-more">
          <a href="/c/10/10" class="more-link">更多</a>
        </div>
      </div>
    {{/if}}
  </template>
}
