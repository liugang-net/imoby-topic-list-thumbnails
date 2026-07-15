import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import discourseLater from "discourse/lib/later";
import bodyClass from "discourse/helpers/body-class";
import dIcon from "discourse/helpers/d-icon";
import { bind } from "discourse/lib/decorators";
import getURL, { withoutPrefix } from "discourse/lib/get-url";
import { eq, gt } from "discourse/truth-helpers";

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

function parseSlides(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    return [];
  }
  return raw
    .map((row) => {
      if (!row || typeof row !== "object") {
        return null;
      }
      const background = row.background_image_url;
      if (background == null || String(background).trim() === "") {
        return null;
      }
      let href = row.link_url;
      if (typeof href !== "string" || !href.trim()) {
        href = "/";
      }
      const alt = typeof row.alt_text === "string" ? row.alt_text : "";
      const title =
        typeof row.panel_title === "string" ? row.panel_title.trim() : "";
      const character =
        typeof row.character_image_url === "string"
          ? row.character_image_url.trim()
          : "";
      const copy =
        typeof row.copy_image_url === "string"
          ? row.copy_image_url.trim()
          : "";
      return {
        background: String(background).trim(),
        character,
        copy,
        title,
        alt,
        href: href.trim(),
      };
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
  @service site;

  @tracked _routeEpoch = 0;
  @tracked activeIndex = 0;

  constructor() {
    super(...arguments);
    this.router?.on("routeDidChange", this, this.onHeroRouteDidChange);
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.router?.off("routeDidChange", this, this.onHeroRouteDidChange);
  }

  @bind
  onHeroRouteDidChange() {
    this._routeEpoch++;
  }

  get rawSlides() {
    return parseSlides(settings.hero_carousel_slides);
  }

  get slides() {
    return this.rawSlides.map((s, i) => ({
      ...s,
      resolvedHref: resolveHref(s.href),
      number: String(i + 1).padStart(2, "0"),
      __key: `${i}-${s.background}`,
    }));
  }

  get shouldShow() {
    this._routeEpoch;
    if (!settings.hero_carousel_enabled || this.slides.length === 0) {
      return false;
    }
    return isHeroCarouselPath(withoutPrefix(window.location.pathname) || "/");
  }

  get intervalSecForSwiper() {
    const n = parseInt(String(settings.hero_carousel_interval_seconds), 10);
    return Number.isFinite(n) && n >= 2 && n <= 60 ? n : 6;
  }

  get showPagination() {
    return this.slides.length > 1;
  }

  get activeSlide() {
    return this.slides[this.activeIndex] || this.slides[0] || null;
  }

  get announcements() {
    return this.site?.category_announcements || [];
  }

  get showNotice() {
    return this.announcements.length > 0;
  }

  get noticeUrl() {
    return (announcement) => getURL(`/t/${announcement.slug}/${announcement.id}`);
  }

  swiperInit = modifier((element, [epoch, slideCount, intervalSec]) => {
    void epoch;
    const n = Number(slideCount);
    if (!element || !Number.isFinite(n) || n < 1) {
      return;
    }

    let swiper = null;
    let destroyed = false;
    const intervalMs = Number(intervalSec) * 1000;

    const mount = (SwiperCtor) => {
      if (destroyed || !element.isConnected) {
        return;
      }
      swiper = new SwiperCtor(element, {
        loop: n > 1,
        speed: 700,
        effect: "fade",
        fadeEffect: { crossFade: true },
        parallax: true,
        allowTouchMove: n > 1,
        a11y: { enabled: true },
        autoplay:
          n > 1
            ? {
                delay: intervalMs,
                disableOnInteraction: false,
                pauseOnMouseEnter: true,
              }
            : false,
        on: {
          slideChange: (s) => {
            if (destroyed) {
              return;
            }
            this.activeIndex = s.realIndex ?? 0;
          },
        },
      });
      this._swiper = swiper;
      this.activeIndex = swiper.realIndex ?? 0;
    };

    waitForSwiper((SwiperCtor) => {
      if (destroyed) {
        return;
      }
      discourseLater(() => mount(SwiperCtor), 0);
    });

    return () => {
      destroyed = true;
      this._swiper = null;
      if (swiper) {
        swiper.destroy(true, true);
        swiper = null;
      }
    };
  });

  panelSwap = modifier((element, [key]) => {
    void key;
    element.classList.remove("ibomy-hero-carousel__panel-fade");
    void element.offsetWidth;
    element.classList.add("ibomy-hero-carousel__panel-fade");
  });

  // 通知条内容整行上下滚动切换；每 3s 滚动一条，到末尾无动画跳回开头，鼠标悬停暂停
  noticeScroll = modifier((element, [count]) => {
    const n = Number(count);
    const list = element?.querySelector(".ibomy-hero-carousel__notice-list");
    if (!element || !list || !Number.isFinite(n) || n <= 1) {
      return;
    }

    let index = 0;
    let timer = null;
    let destroyed = false;

    const scrollToNext = () => {
      index++;
      const itemHeight = element.getBoundingClientRect().height;
      list.style.transform = `translateY(${-index * itemHeight}px)`;

      if (index >= n) {
        discourseLater(() => {
          if (destroyed) {
            return;
          }
          index = 0;
          list.style.transition = "none";
          list.style.transform = "translateY(0)";
          requestAnimationFrame(() => {
            requestAnimationFrame(() => {
              if (!destroyed) {
                list.style.transition = "";
              }
            });
          });
        }, 500);
      }
    };

    const start = () => {
      if (!timer) {
        timer = setInterval(scrollToNext, 3000);
      }
    };
    const stop = () => {
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
    };

    start();
    element.addEventListener("mouseenter", stop);
    element.addEventListener("mouseleave", start);

    return () => {
      destroyed = true;
      stop();
      element.removeEventListener("mouseenter", stop);
      element.removeEventListener("mouseleave", start);
    };
  });

  goToSlide = (index) => {
    if (this._swiper) {
      this._swiper.slideToLoop(index);
    } else {
      this.activeIndex = index;
    }
  };

  <template>
    {{#if this.shouldShow}}
      {{bodyClass "has-ibomy-hero-carousel"}}
      <section
        class="ibomy-hero-carousel"
        aria-roledescription="carousel"
        aria-label="Hero"
      >
        <div class="ibomy-hero-carousel__box">
          {{#if this.showPagination}}
            <div class="ibomy-hero-carousel__pagination" role="tablist">
              {{#each this.slides as |slide index|}}
                <button
                  type="button"
                  class="ibomy-hero-carousel__pagination-mark
                    {{if
                      (eq index this.activeIndex)
                      'ibomy-hero-carousel__pagination-mark--active'
                    }}"
                  aria-label="{{slide.number}}"
                  {{on "click" (fn this.goToSlide index)}}
                ></button>
              {{/each}}
            </div>
          {{/if}}

          <div
            class="ibomy-hero-carousel__stage swiper ibomy-hero-swiper"
            {{this.swiperInit
              this._routeEpoch
              this.slides.length
              this.intervalSecForSwiper
            }}
          >
            <div class="ibomy-hero-carousel__side">
              <div
                class="ibomy-hero-carousel__panel"
                {{this.panelSwap this.activeIndex}}
              >
                <span
                  class="ibomy-hero-carousel__panel-title"
                >{{this.activeSlide.title}}</span>
                <span
                  class="ibomy-hero-carousel__panel-number"
                >{{this.activeSlide.number}}</span>
              </div>
            </div>

            <div class="swiper-wrapper">
              {{#each this.slides key="__key" as |slide|}}
                <a
                  class="swiper-slide ibomy-hero-carousel__slide"
                  href={{slide.resolvedHref}}
                  draggable="false"
                >
                  <span class="ibomy-hero-carousel__slide-bg">
                    <img
                      class="ibomy-hero-carousel__slide-bg-media"
                      src={{slide.background}}
                      alt={{slide.alt}}
                      loading="lazy"
                      draggable="false"
                      data-swiper-parallax="-8%"
                    />
                  </span>
                  <svg
                    class="ibomy-hero-carousel__slide-frame"
                    viewBox="0 0 1080 480"
                    preserveAspectRatio="none"
                    aria-hidden="true"
                  >
                    <polyline
                      points="1080,0.5 374,0.5 20,480"
                      fill="none"
                      stroke="#000000"
                      stroke-width="1"
                      vector-effect="non-scaling-stroke"
                    />
                  </svg>
                  <span class="ibomy-hero-carousel__slide-edge-bottom"></span>
                  {{#if slide.character}}
                    <span
                      class="ibomy-hero-carousel__layer ibomy-hero-carousel__layer--character"
                    >
                      <img
                        src={{slide.character}}
                        alt=""
                        loading="lazy"
                        draggable="false"
                        data-swiper-parallax="-18%"
                        data-swiper-parallax-opacity="0.2"
                      />
                    </span>
                  {{/if}}
                  {{#if slide.copy}}
                    <span
                      class="ibomy-hero-carousel__layer ibomy-hero-carousel__layer--copy"
                    >
                      <img
                        src={{slide.copy}}
                        alt=""
                        loading="lazy"
                        draggable="false"
                        data-swiper-parallax="-32%"
                        data-swiper-parallax-opacity="0.1"
                      />
                    </span>
                  {{/if}}
                </a>
              {{/each}}
            </div>
          </div>

          {{#if this.showNotice}}
            <div class="ibomy-hero-carousel__notice">
              <span class="ibomy-hero-carousel__notice-icon">
                {{dIcon "bell"}}
              </span>
              <div
                class="ibomy-hero-carousel__notice-viewport"
                {{this.noticeScroll this.announcements.length}}
              >
                <div class="ibomy-hero-carousel__notice-list">
                  {{#each this.announcements as |announcement|}}
                    <a
                      class="ibomy-hero-carousel__notice-item"
                      href={{this.noticeUrl announcement}}
                    >{{announcement.title}}</a>
                  {{/each}}
                  {{#if (gt this.announcements.length 1)}}
                    {{#each this.announcements as |announcement|}}
                      <a
                        class="ibomy-hero-carousel__notice-item"
                        href={{this.noticeUrl announcement}}
                        aria-hidden="true"
                        tabindex="-1"
                      >{{announcement.title}}</a>
                    {{/each}}
                  {{/if}}
                </div>
              </div>
              <a class="ibomy-hero-carousel__notice-more" href="/c/10/10">更多&gt;</a>
            </div>
          {{/if}}
        </div>
      </section>
    {{/if}}
  </template>
}
