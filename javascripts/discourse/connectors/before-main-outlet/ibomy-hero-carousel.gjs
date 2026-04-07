import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { modifier } from "ember-modifier";
import bodyClass from "discourse/helpers/body-class";
import concatClass from "discourse/helpers/concat-class";
import dIcon from "discourse/helpers/d-icon";
import getURL from "discourse/lib/get-url";

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
  @tracked activeIndex = 0;
  _timer = null;

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
    return !!settings.hero_carousel_enabled && this.slides.length > 0;
  }

  get heightPx() {
    const raw = String(settings.hero_carousel_height || "220").replace(/px\s*$/i, "");
    const n = parseInt(raw, 10);
    return Number.isFinite(n) && n >= 120 && n <= 560 ? n : 220;
  }

  get intervalSec() {
    const n = parseInt(String(settings.hero_carousel_interval_seconds), 10);
    return Number.isFinite(n) && n >= 2 && n <= 60 ? n : 6;
  }

  get wrapperStyle() {
    return `--ibomy-hero-carousel-height:${this.heightPx}px;height:${this.heightPx}px`;
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
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
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
        style={{this.wrapperStyle}}
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
