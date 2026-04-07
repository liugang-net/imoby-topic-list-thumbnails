import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { modifier } from "ember-modifier";
import { service } from "@ember/service";
import bodyClass from "discourse/helpers/body-class";
import concatClass from "discourse/helpers/concat-class";
import dIcon from "discourse/helpers/d-icon";
import { bind } from "discourse/lib/decorators";
import getURL, { withoutPrefix } from "discourse/lib/get-url";

// 与 before-main-outlet/announcement-scroll.gjs 一致：仅首页、最新、分类、标签相关页显示
const HERO_CAROUSEL_EXCLUDED_PREFIXES = [
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

const HERO_CAROUSEL_ALLOWED_PREFIXES = [
  "/",
  "/latest",
  "/c/",
  "/tags",
  "/tag/",
];

function isHeroCarouselPath(pathname) {
  const path = pathname || "";
  if (HERO_CAROUSEL_EXCLUDED_PREFIXES.some((p) => path.startsWith(p))) {
    return false;
  }
  return HERO_CAROUSEL_ALLOWED_PREFIXES.some((p) => {
    if (p === "/") {
      return path === "/" || path === "";
    }
    return path.startsWith(p);
  });
}

function parseObjectSlides(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    return [];
  }
  return raw
    .map((row) => {
      if (!row || typeof row !== "object") {
        return null;
      }
      const image = row.image_url ?? row.image ?? row.img ?? row.src;
      if (image == null || String(image).trim() === "") {
        return null;
      }
      let href = row.link_url ?? row.href ?? row.link ?? "/";
      if (typeof href !== "string") {
        href = "/";
      }
      const alt =
        typeof row.alt_text === "string"
          ? row.alt_text
          : typeof row.alt === "string"
            ? row.alt
            : "";
      return { image: String(image).trim(), href: href.trim(), alt };
    })
    .filter(Boolean);
}

function parseHeroItems(raw) {
  if (!raw || typeof raw !== "string" || !raw.trim()) {
    return [];
  }
  const t = raw.trim();
  try {
    const j = JSON.parse(t);
    if (Array.isArray(j)) {
      return j
        .map((row) => {
          if (!row || typeof row !== "object") {
            return null;
          }
          const image = row.image || row.img || row.src;
          if (!image || typeof image !== "string") {
            return null;
          }
          let href = row.href || row.link || "/";
          if (typeof href !== "string") {
            href = "/";
          }
          const alt = typeof row.alt === "string" ? row.alt : "";
          return { image: image.trim(), href: href.trim(), alt };
        })
        .filter(Boolean);
    }
  } catch {
    // fall through to line format
  }
  return t
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const parts = line.split("|").map((s) => s.trim());
      const image = parts[0];
      if (!image) {
        return null;
      }
      const href = parts[1] || "/";
      const alt = parts[2] || "";
      return { image, href, alt };
    })
    .filter(Boolean);
}

function resolveHref(href) {
  if (!href) {
    return getURL("/");
  }
  if (/^https?:\/\//i.test(href)) {
    return href;
  }
  const path = href.startsWith("/") ? href : `/${href}`;
  return getURL(path);
}

export default class IbomyHeroCarousel extends Component {
  @service router;

  @tracked activeIndex = 0;
  @tracked _routeEpoch = 0;
  _timer = null;

  constructor() {
    super(...arguments);
    this.router?.on("routeDidChange", this, this.onHeroRouteDidChange);
  }

  get rawItems() {
    const fromObjects = parseObjectSlides(settings.hero_carousel_slides);
    if (fromObjects.length > 0) {
      return fromObjects;
    }
    return parseHeroItems(settings.hero_carousel_items || "");
  }

  get slides() {
    return this.rawItems.map((s) => ({
      ...s,
      resolvedHref: resolveHref(s.href),
    }));
  }

  get shouldShow() {
    this._routeEpoch;
    if (!settings.hero_carousel_enabled || this.slides.length === 0) {
      return false;
    }
    return isHeroCarouselPath(withoutPrefix(window.location.pathname) || "/");
  }

  get intervalSec() {
    const n = parseInt(String(settings.hero_carousel_interval_seconds), 10);
    return Number.isFinite(n) && n >= 2 && n <= 60 ? n : 6;
  }

  get trackStyle() {
    return `transform:translateX(-${this.activeIndex * 100}%)`;
  }

  get showDots() {
    return this.slides.length > 1;
  }

  autoplay = modifier((_element) => {
    if (this.slides.length < 2) {
      return;
    }
    const tick = () => {
      if (this.isDestroying || this.isDestroyed) {
        return;
      }
      const n = this.slides.length;
      this.activeIndex = (this.activeIndex + 1) % n;
    };
    this._timer = setInterval(tick, this.intervalSec * 1000);
    return () => {
      if (this._timer) {
        clearInterval(this._timer);
        this._timer = null;
      }
    };
  });

  willDestroy() {
    super.willDestroy?.();
    this.router?.off("routeDidChange", this, this.onHeroRouteDidChange);
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
  }

  @bind
  onHeroRouteDidChange() {
    this._routeEpoch++;
  }

  @action
  goToSlide(index) {
    const n = this.slides.length;
    if (!n) {
      return;
    }
    this.activeIndex = ((index % n) + n) % n;
  }

  @action
  prevSlide() {
    this.goToSlide(this.activeIndex - 1);
  }

  @action
  nextSlide() {
    this.goToSlide(this.activeIndex + 1);
  }

  @action
  activeDotClass(i) {
    return this.activeIndex === i ? "is-active" : undefined;
  }

  @action
  dotAriaCurrent(i) {
    return this.activeIndex === i ? "true" : undefined;
  }

  <template>
    {{#if this.shouldShow}}
      {{bodyClass "has-ibomy-hero-carousel"}}
      <section
        class="ibomy-hero-carousel"
        aria-roledescription="carousel"
        aria-label="Hero"
        {{this.autoplay}}
      >
        <div class="ibomy-hero-carousel__viewport">
          <div class="ibomy-hero-carousel__track" style={{this.trackStyle}}>
            {{#each this.slides as |item|}}
              <a
                class="ibomy-hero-carousel__slide"
                href={{item.resolvedHref}}
                draggable="false"
              >
                <img
                  class="ibomy-hero-carousel__img"
                  src={{item.image}}
                  alt={{item.alt}}
                  loading="lazy"
                />
              </a>
            {{/each}}
          </div>
        </div>

        {{#if this.showDots}}
          <div class="ibomy-hero-carousel__dots" role="tablist">
            {{#each this.slides as |item i|}}
              <button
                type="button"
                class={{concatClass "ibomy-hero-carousel__dot" (this.activeDotClass i)}}
                aria-label="Go to slide {{i}}"
                aria-current={{this.dotAriaCurrent i}}
                {{on "click" (fn this.goToSlide i)}}
              ></button>
            {{/each}}
          </div>
        {{/if}}

        {{#if this.showDots}}
          <button
            type="button"
            class="ibomy-hero-carousel__nav ibomy-hero-carousel__nav--prev"
            aria-label="Previous slide"
            {{on "click" this.prevSlide}}
          >
            {{dIcon "chevron-left"}}
          </button>
          <button
            type="button"
            class="ibomy-hero-carousel__nav ibomy-hero-carousel__nav--next"
            aria-label="Next slide"
            {{on "click" this.nextSlide}}
          >
            {{dIcon "chevron-right"}}
          </button>
        {{/if}}
      </section>
    {{/if}}
  </template>
}
