import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { modifier } from "ember-modifier";
import { scheduleOnce } from "@ember/runloop";
import { service } from "@ember/service";
import discourseLater from "discourse/lib/later";
import bodyClass from "discourse/helpers/body-class";
import concatClass from "discourse/helpers/concat-class";
import dIcon from "discourse/helpers/d-icon";
import { bind } from "discourse/lib/decorators";
import getURL, { withoutPrefix } from "discourse/lib/get-url";

const SLIDE_WIDTH_RATIO = 0.78;
const SLIDE_GAP_PX = 16;
const SWIPE_THRESHOLD_PX = 44;

// 与 before-main-outlet/ibomy-scroll-announcement.gjs 一致：仅首页、最新、分类、标签相关页显示
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

export default class IbomyHeroCarousel extends Component {
  @service router;

  @tracked _routeEpoch = 0;
  @tracked viewportWidth = 0;
  /**
   * 物理槽位下标：无克隆时 0..n-1；有克隆时为 [尾克隆, 真0..真n-1, 头克隆] 即 0..n+1，首屏应对齐真第一张 => 1
   */
  @tracked activePhysicalIndex = 1;
  /** 复位到等效真实位时瞬时关掉 transform 过渡，避免闪动 */
  @tracked suppressTrackTransition = false;
  _touchStartX = null;
  _touchStartY = null;
  _blockNavAfterSwipe = false;
  /** transitionend 与瞬时复位交错时忽略多余事件 */
  _repositioning = false;

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

  /** 轨道 DOM：[尾克隆] + 全部真实 + [头克隆]；单张不克隆 */
  get trackItems() {
    const slides = this.slides;
    const n = slides.length;
    if (n < 2) {
      return slides.map((slide, realIndex) => ({
        key: `only-${realIndex}`,
        slide,
        physicalIndex: realIndex,
        isClone: false,
      }));
    }
    return [
      {
        key: "clone-tail",
        slide: slides[n - 1],
        physicalIndex: 0,
        isClone: true,
      },
      ...slides.map((slide, i) => ({
        key: `real-${i}`,
        slide,
        physicalIndex: i + 1,
        isClone: false,
      })),
      {
        key: "clone-head",
        slide: slides[0],
        physicalIndex: n + 1,
        isClone: true,
      },
    ];
  }

  get physicalSlideCount() {
    const n = this.slides.length;
    if (n < 2) {
      return n;
    }
    return n + 2;
  }

  /** 圆点 / 对外逻辑下标 0..n-1 */
  get logicalActiveIndex() {
    const n = this.slides.length;
    if (n < 2) {
      return this.activePhysicalIndex;
    }
    const p = this.activePhysicalIndex;
    if (p === 0) {
      return n - 1;
    }
    if (p === n + 1) {
      return 0;
    }
    return p - 1;
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

  // 仅用已提交的 viewportWidth，避免在 getter 里读 DOM；首帧为 0 时用保守占位，等异步测量后再更新
  get layoutWidthPx() {
    const w = this.viewportWidth;
    return w > 1 ? w : 360;
  }

  get slideWidthPx() {
    const v = this.layoutWidthPx;
    if (!v) {
      return 0;
    }
    return Math.max(120, Math.round(v * SLIDE_WIDTH_RATIO));
  }

  get trackTranslatePx() {
    const v = this.layoutWidthPx;
    const n = this.slides.length;
    const count = this.physicalSlideCount;
    const W = this.slideWidthPx;
    if (!v || !count || !W) {
      return 0;
    }
    let i = this.activePhysicalIndex;
    if (n < 2) {
      i = Math.min(Math.max(i, 0), Math.max(n - 1, 0));
    }
    const gap = SLIDE_GAP_PX;
    return Math.round(v / 2 - i * (W + gap) - W / 2);
  }

  get trackMinWidthPx() {
    const count = this.physicalSlideCount;
    const W = this.slideWidthPx;
    if (!count || !W) {
      return 0;
    }
    const gap = SLIDE_GAP_PX;
    return Math.round(count * W + Math.max(0, count - 1) * gap);
  }

  get trackStyle() {
    const tx = this.trackTranslatePx;
    const minW = this.trackMinWidthPx;
    if (!minW) {
      return "transform:translateX(0);min-width:100%";
    }
    return `transform:translate3d(${tx}px,0,0);min-width:${minW}px`;
  }

  get slideWidthStyle() {
    const w = this.slideWidthPx;
    if (!w) {
      return "";
    }
    return `width:${w}px;flex:0 0 ${w}px`;
  }

  get showDots() {
    return this.slides.length > 1;
  }

  viewportMeasure = modifier((element) => {
    const readWidth = () => {
      let w = Math.round(
        element.getBoundingClientRect().width ||
          element.clientWidth ||
          element.offsetWidth ||
          0
      );
      if (w < 2) {
        const p = element.parentElement;
        w = Math.round(p?.getBoundingClientRect?.().width || p?.clientWidth || 0);
      }
      if (w < 2 && typeof window !== "undefined") {
        const inner = Math.round(
          document.documentElement?.clientWidth || window.innerWidth
        );
        w = Math.max(280, Math.min(inner, 520));
      }
      return w;
    };

    const commit = () => {
      const w = readWidth();
      if (w > 0 && w !== this.viewportWidth) {
        this.viewportWidth = w;
      }
    };

    // 禁止在 modifier 同步阶段写 @tracked（会与当次渲染里已读的 viewportWidth 冲突）
    queueMicrotask(commit);
    requestAnimationFrame(commit);
    requestAnimationFrame(() => requestAnimationFrame(commit));
    scheduleOnce("afterRender", null, commit);
    discourseLater(commit, 120);
    discourseLater(commit, 400);

    const ro = new ResizeObserver(() => {
      requestAnimationFrame(commit);
    });
    ro.observe(element);
    return () => ro.disconnect();
  });

  get intervalSecForAutoplay() {
    const n = Number(this.intervalSec);
    return Number.isFinite(n) && n >= 2 && n <= 60 ? n : 6;
  }

  // 传入 slideCount、interval（秒，数字）作为位置参数，保证条数或间隔变化时重建定时器
  autoplay = modifier((_element, [slideCount, intervalSec]) => {
    const n = Number(slideCount);
    const secRaw = Number(intervalSec);
    const sec =
      Number.isFinite(secRaw) && secRaw >= 2 && secRaw <= 60 ? secRaw : 6;
    if (!Number.isFinite(n) || n < 2) {
      return;
    }
    queueMicrotask(() => {
      if (this.activePhysicalIndex < 1 || this.activePhysicalIndex > n + 1) {
        this.activePhysicalIndex = 1;
      }
    });
    const ms = sec * 1000;
    const tick = () => {
      const total = this.rawItems.length;
      if (total < 2) {
        return;
      }
      if (this.activePhysicalIndex >= total + 1) {
        return;
      }
      this.activePhysicalIndex = this.activePhysicalIndex + 1;
    };
    const id = setInterval(tick, ms);
    return () => clearInterval(id);
  });

  /** 条数变化时把物理指针夹到合法区间（依赖 rawItems.length） */
  carouselStateSync = modifier((_element, [slideCount]) => {
    const n = Number(slideCount);
    queueMicrotask(() => {
      if (!Number.isFinite(n) || n < 1) {
        return;
      }
      if (n < 2) {
        if (this.activePhysicalIndex !== 0) {
          this.activePhysicalIndex = 0;
        }
        return;
      }
      if (this.activePhysicalIndex < 1 || this.activePhysicalIndex > n + 1) {
        this.activePhysicalIndex = 1;
      }
    });
  });

  willDestroy() {
    super.willDestroy?.();
    this.router?.off("routeDidChange", this, this.onHeroRouteDidChange);
  }

  @bind
  onHeroRouteDidChange() {
    this._routeEpoch++;
    const n = this.slides.length;
    queueMicrotask(() => {
      if (n < 2) {
        this.activePhysicalIndex = 0;
      } else {
        this.activePhysicalIndex = 1;
      }
    });
  }

  repositionPhysical(targetP) {
    this._repositioning = true;
    this.suppressTrackTransition = true;
    this.activePhysicalIndex = targetP;
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.suppressTrackTransition = false;
        requestAnimationFrame(() => {
          this._repositioning = false;
        });
      });
    });
  }

  @action
  onTrackTransitionEnd(ev) {
    if (this._repositioning) {
      return;
    }
    if (ev.target !== ev.currentTarget) {
      return;
    }
    if (ev.propertyName !== "transform") {
      return;
    }
    const n = this.slides.length;
    if (n < 2) {
      return;
    }
    const p = this.activePhysicalIndex;
    if (p === n + 1) {
      this.repositionPhysical(1);
    } else if (p === 0) {
      this.repositionPhysical(n);
    }
  }

  @action
  goToSlide(index) {
    const n = this.slides.length;
    if (!n) {
      return;
    }
    const target = ((index % n) + n) % n;
    if (n < 2) {
      this.activePhysicalIndex = target;
      return;
    }
    this.activePhysicalIndex = target + 1;
  }

  @action
  prevSlide() {
    const n = this.slides.length;
    if (!n || n < 2) {
      return;
    }
    if (this.activePhysicalIndex > 0) {
      this.activePhysicalIndex = this.activePhysicalIndex - 1;
    }
  }

  @action
  nextSlide() {
    const n = this.slides.length;
    if (!n || n < 2) {
      return;
    }
    if (this.activePhysicalIndex < n + 1) {
      this.activePhysicalIndex = this.activePhysicalIndex + 1;
    }
  }

  @action
  activeDotClass(i) {
    return this.logicalActiveIndex === i ? "is-active" : undefined;
  }

  @action
  dotAriaCurrent(i) {
    return this.logicalActiveIndex === i ? "true" : undefined;
  }

  @action
  slideRowActiveClass(row) {
    return row.physicalIndex === this.activePhysicalIndex ? "is-active" : undefined;
  }

  @action
  onTouchStart(event) {
    const t = event.touches?.[0];
    if (!t) {
      return;
    }
    this._touchStartX = t.clientX;
    this._touchStartY = t.clientY;
  }

  @action
  onTouchEnd(event) {
    if (this._touchStartX == null) {
      return;
    }
    const t = event.changedTouches?.[0];
    const endX = t?.clientX ?? this._touchStartX;
    const endY = t?.clientY ?? this._touchStartY;
    const dx = endX - this._touchStartX;
    const dy = endY - this._touchStartY;
    this._touchStartX = null;
    this._touchStartY = null;

    if (this.slides.length < 2) {
      return;
    }
    if (
      Math.abs(dx) < SWIPE_THRESHOLD_PX ||
      Math.abs(dx) < Math.abs(dy)
    ) {
      return;
    }

    if (dx < 0) {
      this.nextSlide();
    } else {
      this.prevSlide();
    }

    this._blockNavAfterSwipe = true;
    discourseLater(() => {
      this._blockNavAfterSwipe = false;
    }, 400);
  }

  @action
  onTouchCancel() {
    this._touchStartX = null;
    this._touchStartY = null;
  }

  @action
  handleSlideClick(event) {
    if (this._blockNavAfterSwipe) {
      event.preventDefault();
      event.stopPropagation();
    }
  }

  <template>
    {{#if this.shouldShow}}
      {{bodyClass "has-ibomy-hero-carousel"}}
      <section
        class="ibomy-hero-carousel"
        aria-roledescription="carousel"
        aria-label="Hero"
        {{this.carouselStateSync this.rawItems.length}}
        {{this.autoplay this.rawItems.length this.intervalSecForAutoplay}}
      >
        <div
          class="ibomy-hero-carousel__viewport"
          {{this.viewportMeasure}}
          {{on "touchstart" this.onTouchStart passive=true}}
          {{on "touchend" this.onTouchEnd passive=true}}
          {{on "touchcancel" this.onTouchCancel passive=true}}
        >
          <div
            class={{concatClass
              "ibomy-hero-carousel__track"
              (if this.suppressTrackTransition "ibomy-hero-carousel__track--instant")
            }}
            style={{this.trackStyle}}
            {{on "transitionend" this.onTrackTransitionEnd}}
          >
            {{#each this.trackItems key="key" as |row|}}
              <a
                class={{concatClass
                  "ibomy-hero-carousel__slide"
                  (if row.isClone "ibomy-hero-carousel__slide--clone")
                  (this.slideRowActiveClass row)
                }}
                href={{row.slide.resolvedHref}}
                draggable="false"
                style={{this.slideWidthStyle}}
                tabindex={{if row.isClone "-1"}}
                aria-hidden={{if row.isClone "true"}}
                {{on "click" this.handleSlideClick}}
              >
                <span class="ibomy-hero-carousel__card">
                  <span class="ibomy-hero-carousel__media">
                    <img
                      class="ibomy-hero-carousel__img"
                      src={{row.slide.image}}
                      alt={{row.slide.alt}}
                      loading="lazy"
                      draggable="false"
                    />
                  </span>
                  {{#if row.slide.caption}}
                    <span class="ibomy-hero-carousel__caption">{{row.slide.caption}}</span>
                  {{/if}}
                </span>
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
