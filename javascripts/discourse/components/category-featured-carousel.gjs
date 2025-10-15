import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import dIcon from "discourse/helpers/d-icon";
import concatClass from "discourse/helpers/concat-class";
import { on } from "@ember/modifier";
import { fn } from "@ember/helper";
// 不使用模板修饰符，改为监听路由变化

export default class CategoryFeaturedCarousel extends Component {
  @service router;

  @tracked items = [];
  @tracked loading = true;
  @tracked lastKey = null;

  get categoryId() {
    return this.args?.categoryId;
  }

  get category() {
    return this.args?.category || null;
  }

  get hasItems() {
    return Array.isArray(this.items) && this.items.length > 0;
  }

  constructor() {
    super(...arguments);
    this.maybeReload();
    // 监听路由变化，切换分类时刷新
    if (this.router && this.onRouteChanged) {
      this.router.on('routeDidChange', this.onRouteChanged);
    }
  }

  async load() {
    if (!this.categoryId && !this.category) {
      this.loading = false;
      return;
    }

    try {
      // 1) 优先从已有的分类对象中读取（后端已在 Category 上添加 featured_topics）
      const local = this.category?.featured_topics || this.category?.featuredTopics;
      if (Array.isArray(local) && local.length) {
        this.items = local;
        this.loading = false;
        return;
      }

      // 2) 回退到官方分类接口：/c/:id.json（或 /c/:slug/:id.json）
      const id = this.categoryId || this.category?.id;
      const res = await fetch(`/c/${id}/show.json`, { headers: { Accept: "application/json" } });
      const data = await res.json();
      const cat = data?.category || {};
      const featured = cat.featured_topics || cat.featuredTopics || [];
      this.items = featured;
    } catch (e) {
      // 静默失败
      this.items = [];
    } finally {
      this.loading = false;
      // 渲染后绑定track
      requestAnimationFrame(() => {
        this.bindTrack();
      });
    }
  }

  willDestroy() {
    super.willDestroy?.();
    if (this.router && this.onRouteChanged) {
      try { this.router.off('routeDidChange', this.onRouteChanged); } catch(e) {}
    }
  }

  get argsKey() {
    const id = this.categoryId || this.category?.id;
    return id ? String(id) : "";
  }

  @action maybeReload() {
    const currentKey = this.argsKey;
    if (currentKey && currentKey !== this.lastKey) {
      this.lastKey = currentKey;
      this.loading = true;
      this.items = [];
      this.load();
    }
  }

  @action onRouteChanged() {
    // 路由变化时尝试刷新（分类切换等）
    this.maybeReload();
  }

  get showComponent() {
    // 只有在有数据时才显示组件
    return !this.loading && this.hasItems;
  }

  get showLoading() {
    // 显示加载状态：正在加载且有分类ID
    return this.loading && (this.categoryId || this.category);
  }

  bindTrack() {
    if (this.carouselTrack) { return; }
    const root = document.querySelector('.category-featured-carousel .cfc-viewport');
    if (root) {
      this.carouselTrack = root;
    }
  }

  get trackStyle() {
    // 高度自适应，卡片宽度在CSS里控制
    return "";
  }

  topicUrl(topic) {
    if (topic?.slug && topic?.id) {
      return `/t/${topic.slug}/${topic.id}`;
    }
    return topic?.url || "#";
  }

  thumbUrl(topic) {
    if (!topic) { return null; }
    if (topic.image_url) { return topic.image_url; }
    if (topic.thumbnail) { return topic.thumbnail; }
    return null;
  }

  get displayItems() {
    // 显示所有数据，让用户可以通过滚动查看
    return this.items;
  }

  @action scrollByAmount(dir) {
    const el = this.carouselTrack;
    if (!el) return;
    
    const card = el.querySelector('.cfc-card');
    if (!card) return;
    
    const cardWidth = card.offsetWidth;
    const gap = 12; // 卡片间距
    const step = cardWidth + gap;
    
    // 移动端优化：使用更快的滚动
    const isMobile = window.innerWidth <= 768;
    const behavior = isMobile ? 'auto' : 'smooth';
    
    el.scrollBy({ 
      left: dir * step, 
      behavior: behavior
    });
  }

  @action registerTrack(el) {
    this.carouselTrack = el;
  }

  <template>
    {{#if this.showLoading}}
      <div class="category-featured-carousel">
        <div class="cfc-loading">
          <div class="cfc-loading-spinner"></div>
          <div class="cfc-loading-text">加载中...</div>
        </div>
      </div>
    {{else if this.showComponent}}
      <div class="category-featured-carousel">
        <button class="cfc-nav prev" type="button" {{on "click" (fn this.scrollByAmount -1)}} {{on "touchend" (fn this.scrollByAmount -1)}} aria-label="上一页">
          {{dIcon "chevron-left"}}
        </button>

        <div class="cfc-viewport" {{on "did-insert" this.registerTrack}}>
          <div class="cfc-track" style={{this.trackStyle}}>
            {{#each this.displayItems as |topic|}}
              <a class="cfc-card" href={{this.topicUrl topic}}>
                <div class="cfc-thumb-container">
                  {{#if (this.thumbUrl topic)}}
                    <img class="cfc-thumb" src={{this.thumbUrl topic}} alt={{topic.title}} loading="lazy" />
                  {{else}}
                    <div class="cfc-thumb-placeholder">
                      <div class="cfc-placeholder-icon">{{dIcon "file-text"}}</div>
                      <div class="cfc-placeholder-text">无图片</div>
                    </div>
                  {{/if}}
                  {{#if topic.bumped_at_short}}
                    <span class="cfc-date">{{topic.bumped_at_short}}</span>
                  {{/if}}
                </div>
                <div class="cfc-content">
                  <div class="cfc-title">{{topic.title}}</div>
                </div>
              </a>
            {{/each}}
          </div>
        </div>

        <button class="cfc-nav next" type="button" {{on "click" (fn this.scrollByAmount 1)}} {{on "touchend" (fn this.scrollByAmount 1)}} aria-label="下一页">
          {{dIcon "chevron-right"}}
        </button>
      </div>
    {{/if}}
  </template>
}


