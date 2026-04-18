import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { modifier } from "ember-modifier";
import { service } from "@ember/service";
import discourseLater from "discourse/lib/later";
import bodyClass from "discourse/helpers/body-class";
import { bind } from "discourse/lib/decorators";
import getURL, { withoutPrefix } from "discourse/lib/get-url";

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
  if (path.startsWith("/c/") && path.split("/").includes("edit")) {
    return false;
  }
  return HERO_CAROUSEL_ALLOWED_PREFIXES.some((p) => {
    if (p === "/") {
      return path === "/" || path === "";
    }
    return path.startsWith(p);
  });
}

function normalizeCaption(row) {
  if (!row || typeof row !== "object") {
    return "";
  }
  const c =
    row.caption ??
    row.title ??
    row.label ??
    row.heading ??
    row.subtitle;
  if (typeof c !== "string") {
    return "";
  }
  return c.trim();
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
      const caption = normalizeCaption(row);
      return {
        image: String(image).trim(),
        href: href.trim(),
        alt,
        caption,
      };
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
          const caption = normalizeCaption(row);
          return { image: image.trim(), href: href.trim(), alt, caption };
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
      const caption = parts[3] || "";
      return { image, href, alt, caption };
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

function waitForSwiper(onReady, attempt = 0) {
  if (typeof window === "undefined") {
    return;
  }
  if (window.Swiper) {
    onReady(window.Swiper);
    return;
  }
  if (attempt > 80) {
    return;
  }
  discourseLater(() => waitForSwiper(onReady, attempt + 1), 50);
}

export default class IbomyHeroCarousel extends Component {
  @service router;

  @tracked _routeEpoch = 0;

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

  get intervalSecForSwiper() {
    const n = Number(this.intervalSec);
    return Number.isFinite(n) && n >= 2 && n <= 60 ? n : 6;
  }

  /** 多页时在 DOM 上铺三段相同序列，配合 initialSlide=n 与无动画跳回，替代 Swiper loop（与 auto+centered 不兼容）。 */
  get deckSlides() {
    const s = this.slides;
    if (s.length === 0) {
      return [];
    }
    const tag = (it, i) => ({ ...it, __deckKey: `${i}-${it.image}-${it.resolvedHref}` });
    if (s.length === 1) {
      return [tag(s[0], 0)];
    }
    return [...s, ...s, ...s].map((it, i) => tag(it, i));
  }

  // _routeEpoch / 逻辑张数 / deck 张数 / 间隔：变化则 modifier teardown 并重建 Swiper。
  swiperInit = modifier((element, [epoch, logicalLen, deckLen, intervalSec]) => {
    void epoch;
    const n = Number(logicalLen);
    const total = Number(deckLen);
    if (!element || !Number.isFinite(n) || n < 1 || !Number.isFinite(total) || total < 1) {
      return;
    }

    let swiper = null;
    let destroyed = false;

    const intervalMs = Number(intervalSec) * 1000;
    const useTriple = n > 1 && total === n * 3;
    const initialSlide = useTriple ? n : 0;

    const mount = (SwiperCtor) => {
      if (destroyed || !element.isConnected) {
        return;
      }

      swiper = new SwiperCtor(element, {
        slidesPerView: "auto",
        centeredSlides: true,
        slidesPerGroup: 1,
        spaceBetween: 16,
        speed: 450,
        initialSlide,
        watchOverflow: n === 1,
        loop: false,
        rewind: false,
        slideToClickedSlide: n >= 2,
        preventClicks: false,
        preventClicksPropagation: false,
        autoplay:
          n >= 2
            ? {
                delay: intervalMs,
                disableOnInteraction: false,
                pauseOnMouseEnter: true,
              }
            : false,
        a11y: {
          enabled: true,
        },
        on: {
          slideChangeTransitionEnd(s) {
            if (destroyed || !useTriple || s.destroyed) {
              return;
            }
            const i = s.activeIndex;
            if (i >= n && i < 2 * n) {
              return;
            }
            // 无动画 jump：关 wrapper + 卡片过渡；slideTo 关回调避免连锁 transitionEnd；稍晚再恢复过渡以免首帧抖
            element.classList.add("ibomy-hero-swiper--deck-snap");
            if (i < n) {
              s.slideTo(i + n, 0, false);
            } else if (i >= 2 * n) {
              s.slideTo(i - n, 0, false);
            }
            s.update?.();
            requestAnimationFrame(() => {
              requestAnimationFrame(() => {
                if (destroyed || !element.isConnected) {
                  return;
                }
                discourseLater(() => {
                  if (!destroyed && element.isConnected) {
                    element.classList.remove("ibomy-hero-swiper--deck-snap");
                  }
                }, 48);
              });
            });
          },
        },
      });
    };

    waitForSwiper((SwiperCtor) => {
      if (destroyed) {
        return;
      }
      discourseLater(() => mount(SwiperCtor), 0);
    });

    return () => {
      destroyed = true;
      if (swiper) {
        swiper.destroy(true, true);
        swiper = null;
      }
    };
  });

  willDestroy() {
    super.willDestroy(...arguments);
    this.router?.off("routeDidChange", this, this.onHeroRouteDidChange);
  }

  @bind
  onHeroRouteDidChange() {
    this._routeEpoch++;
  }

  <template>
    {{#if this.shouldShow}}
      {{bodyClass "has-ibomy-hero-carousel"}}
      <section
        class="ibomy-hero-carousel"
        aria-roledescription="carousel"
        aria-label="Hero"
      >
        <div
          class="swiper ibomy-hero-carousel__viewport ibomy-hero-swiper"
          {{this.swiperInit
            this._routeEpoch
            this.slides.length
            this.deckSlides.length
            this.intervalSecForSwiper
          }}
        >
          <div class="swiper-wrapper">
            {{#each this.deckSlides key="__deckKey" as |item|}}
              <div class="swiper-slide ibomy-hero-swiper__slide">
                <a
                  class="ibomy-hero-carousel__slide-link"
                  href={{item.resolvedHref}}
                  draggable="false"
                >
                  <span class="ibomy-hero-carousel__card">
                    <span class="ibomy-hero-carousel__media">
                      <img
                        class="ibomy-hero-carousel__img"
                        src={{item.image}}
                        alt={{item.alt}}
                        loading="lazy"
                        draggable="false"
                      />
                    </span>
                    {{#if item.caption}}
                      <span class="ibomy-hero-carousel__caption">{{item.caption}}</span>
                    {{/if}}
                  </span>
                </a>
              </div>
            {{/each}}
          </div>
        </div>
      </section>
    {{/if}}
  </template>
}
