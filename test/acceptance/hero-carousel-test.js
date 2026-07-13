import { settled, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

acceptance("Ibomy hero carousel", function (needs) {
  let originalEnabled;
  let originalSlides;
  let originalItems;
  let originalSwiper;
  let swiper;

  needs.hooks.beforeEach(() => {
    originalEnabled = settings.hero_carousel_enabled;
    originalSlides = settings.hero_carousel_slides;
    originalItems = settings.hero_carousel_items;
    originalSwiper = window.Swiper;

    settings.hero_carousel_enabled = true;
    settings.hero_carousel_items = "";
    window.Swiper = class {
      constructor(element, options) {
        this.activeIndex = options.initialSlide;
        this.destroyed = false;
        this.element = element;
        this.options = options;
        swiper = this;
        options.on?.init?.(this);
      }

      slideTo(index) {
        this.activeIndex = index;
        this.lastSlide = index;
      }

      update() {}

      destroy() {
        this.destroyed = true;
      }
    };
  });

  needs.hooks.afterEach(() => {
    settings.hero_carousel_enabled = originalEnabled;
    settings.hero_carousel_slides = originalSlides;
    settings.hero_carousel_items = originalItems;
    window.Swiper = originalSwiper;
  });

  test("renders optional image layers and the side panel", async function (assert) {
    settings.hero_carousel_slides = [
      {
        image_url: "/images/base.jpg",
        background_image_url: "/images/background.jpg",
        character_image_url: "/images/character.png",
        copy_image_url: "/images/copy.png",
        panel_title: "私人定制",
        panel_subtitle: "オリジナルメイド",
        link_url: "/latest",
        alt_text: "Banner",
      },
      {
        image_url: "/images/second.jpg",
        link_url: "/categories",
        alt_text: "Second banner",
      },
    ];

    await visit("/");

    assert.dom(".ibomy-hero-carousel__layer--background img").exists();
    assert.dom(".ibomy-hero-carousel__layer--character img").exists();
    assert.dom(".ibomy-hero-carousel__layer--copy img").exists();
    assert.dom(".ibomy-hero-carousel__panel-number").hasText("01");
    assert.dom(".ibomy-hero-carousel__panel-title").hasText("私人定制");
    assert.dom(".ibomy-hero-carousel__pagination-mark").exists({ count: 2 });
    assert
      .dom(".ibomy-hero-carousel__pagination-mark--active")
      .exists({ count: 1 });
    assert.dom('.swiper-slide[aria-hidden="true"]').exists({ count: 4 });

    swiper.activeIndex = 3;
    swiper.options.on.slideChange(swiper);
    await settled();

    assert
      .dom(".ibomy-hero-carousel__pagination-mark:nth-child(2)")
      .hasClass("ibomy-hero-carousel__pagination-mark--active");

    swiper.activeIndex = 0;
    swiper.options.on.slideChangeTransitionEnd(swiper);

    assert.strictEqual(swiper.lastSlide, 2, "jumps back to the middle deck");
    assert.dom(".ibomy-hero-swiper").hasClass("ibomy-hero-swiper--deck-snap");

    swiper.options.on.beforeTransitionStart();
    swiper.activeIndex = 5;
    swiper.options.on.slideChangeTransitionEnd(swiper);

    assert.strictEqual(swiper.lastSlide, 3, "jumps back from the right deck");
  });

  test("keeps rendering the legacy text configuration", async function (assert) {
    settings.hero_carousel_slides = [];
    settings.hero_carousel_items =
      "/images/banner.jpg|/latest|Legacy banner|Campaign";

    await visit("/");

    assert.dom(".ibomy-hero-carousel__layer--background img").exists();
    assert.dom(".ibomy-hero-carousel__panel").exists();
    assert.dom(".ibomy-hero-carousel__panel-title").hasText("私人定制");
    assert.dom(".ibomy-hero-carousel__caption").hasText("Campaign");
  });
});
