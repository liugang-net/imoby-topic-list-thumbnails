import { readOnly } from "@ember/object/computed";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import TopicListThumbnail from "../components/topic-list-thumbnail";
import ScrollingCategoryNav from "../components/scrolling-category-nav";
import AnnouncementScroll from "../components/announcement-scroll";
import FeaturedButton from "../components/featured-button";
import CategoryFeaturedCarousel from "../components/category-featured-carousel";

export default apiInitializer("0.8", (api) => {
  const ttService = api.container.lookup("service:topic-thumbnails");
  
  api.replaceIcon("d-topic-share", "share-nodes");
  api.replaceIcon("d-post-share", "share-nodes");
  api.replaceIcon("far-pen-to-square", "plus");
  api.replaceIcon("chevron-down", "far-file-lines");

  api.registerValueTransformer("topic-list-class", ({ value }) => {
    if (ttService.displayMinimalGrid) {
      value.push("topic-thumbnails-minimal");
    } else if (ttService.displayGrid) {
      value.push("topic-thumbnails-grid");
    } else if (ttService.displayList) {
      value.push("topic-thumbnails-list");
    } else if (ttService.displayMasonry) {
      value.push("topic-thumbnails-masonry");
    } else if (ttService.displayBlogStyle) {
      value.push("topic-thumbnails-blog-style-grid");
    } else if (ttService.displayFeed) {
      value.push("topic-thumbnails-feed");
    }
    return value;
  });

  api.registerValueTransformer("topic-list-columns", ({ value: columns }) => {
    if (ttService.enabledForRoute && !ttService.displayList) {
      columns.add(
        "thumbnail",
        { item: TopicListThumbnail },
        { before: "topic" }
      );
    }
    return columns;
  });

  api.renderInOutlet(
    "topic-list-before-link",
    <template>
      {{#if ttService.displayList}}
        <TopicListThumbnail @topic={{@outletArgs.topic}} />
      {{/if}}
    </template>
  );

  // 注册可滑动分类导航组件
  console.log("Navigation setting:", settings.show_scrolling_category_nav);
  if (settings.show_scrolling_category_nav) {
    api.renderInOutlet(
      "discovery-list-controls-above",
      <template>
        <ScrollingCategoryNav />
      </template>
    );
  }

  // 注册公告滚动组件到top-notices（在首页、最新页、话题列表页显示）
  api.renderInOutlet(
    "top-notices",
    <template>
      <AnnouncementScroll />
    </template>
  );

  // 注册精选按钮到timeline-controls-before
  api.renderInOutlet(
    "timeline-controls-before",
    <template>
      <FeaturedButton @topic={{@outletArgs.model}} />
    </template>
  );

  // 分类页推荐活动轮播，挂载在话题列表之前
  api.renderInOutlet(
    "before-topic-list",
    <template>
      {{#if @outletArgs.category}}
        <CategoryFeaturedCarousel @categoryId={{@outletArgs.category.id}} @category={{@outletArgs.category}} />
      {{/if}}
    </template>
  );

  api.registerValueTransformer("topic-list-item-mobile-layout", ({ value }) => {
    if (ttService.enabledForRoute && !ttService.displayList) {
      // Force the desktop layout
      return false;
    }
    return value;
  });

  api.registerValueTransformer(
    "topic-list-item-class",
    ({ value, context: { index } }) => {
      if (ttService.displayMasonry) {
        value.push(`masonry-${index}`);
      }
      return value;
    }
  );

  const siteSettings = api.container.lookup("service:site-settings");
  if (settings.docs_thumbnail_mode !== "none" && siteSettings.docs_enabled) {
    api.modifyClass("component:docs-topic-list", {
      pluginId: "topic-thumbnails",
      topicThumbnailsService: service("topic-thumbnails"),
      classNameBindings: [
        "isMinimalGrid:topic-thumbnails-minimal",
        "isThumbnailGrid:topic-thumbnails-grid",
        "isThumbnailList:topic-thumbnails-list",
        "isMasonryList:topic-thumbnails-masonry",
        "isBlogStyleGrid:topic-thumbnails-blog-style-grid",
        "isFeedGrid:topic-thumbnails-feed",
      ],
      isMinimalGrid: readOnly("topicThumbnailsService.displayMinimalGrid"),
      isThumbnailGrid: readOnly("topicThumbnailsService.displayGrid"),
      isThumbnailList: readOnly("topicThumbnailsService.displayList"),
      isMasonryList: readOnly("topicThumbnailsService.displayMasonry"),
      isBlogStyleGrid: readOnly("topicThumbnailsService.displayBlogStyle"),
      isFeedGrid: readOnly("topicThumbnailsService.displayFeed"),
    });
  }
});
