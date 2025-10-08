import Component from "@glimmer/component";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { dIcon } from "discourse-common/lib/icon-library";

export default class ScrollingCategoryNav extends Component {
  @service router;
  @service site;
  @tracked scrollPosition = 0;

  constructor() {
    super(...arguments);
    console.log("ScrollingCategoryNav component initialized");
  }

  get categories() {
    if (!this.site.categories) return [];
    
    // 过滤掉未读分类和隐藏分类
    return this.site.categories.filter(category => 
      category.read_restricted === false && 
      category.parent_category_id === null
    ).sort((a, b) => a.position - b.position);
  }

  get currentCategoryId() {
    const route = this.router.currentRoute;
    if (route?.params?.category_slug_path_with_id) {
      const match = route.params.category_slug_path_with_id.match(/(\d+)$/);
      return match ? parseInt(match[1], 10) : null;
    }
    return null;
  }

  get isAllActive() {
    return this.currentCategoryId === null;
  }

  get isActive() {
    return (categoryId) => {
      return this.currentCategoryId === categoryId;
    };
  }

  get categoryUrl() {
    return (category) => {
      return `/c/${category.slug}/${category.id}`;
    };
  }

  @action
  scrollLeft() {
    const container = document.querySelector('.scrolling-category-nav .nav-container');
    if (container) {
      container.scrollBy({ left: -200, behavior: 'smooth' });
    }
  }

  @action
  scrollRight() {
    const container = document.querySelector('.scrolling-category-nav .nav-container');
    if (container) {
      container.scrollBy({ left: 200, behavior: 'smooth' });
    }
  }

  @action
  onScroll(event) {
    this.scrollPosition = event.target.scrollLeft;
  }

  get showScrollButtons() {
    return this.categories.length > 4; // 超过4个分类时显示滚动按钮
  }

  get canScrollLeft() {
    return this.scrollPosition > 0;
  }

  get canScrollRight() {
    const container = document.querySelector('.scrolling-category-nav .nav-container');
    if (!container) return false;
    return this.scrollPosition < (container.scrollWidth - container.clientWidth);
  }

  <template>
    {{#if this.categories.length}}
      <div class="scrolling-category-nav">
        {{#if this.showScrollButtons}}
          <button 
            class="scroll-button scroll-left {{if this.canScrollLeft '' 'disabled'}}"
            {{on "click" this.scrollLeft}}
            aria-label="向左滚动"
            disabled={{if this.canScrollLeft false true}}
          >
            {{dIcon "chevron-left"}}
          </button>
        {{/if}}

        <div class="nav-container" {{on "scroll" this.onScroll}}>
          <div class="nav-items">
            <a 
              href="/latest" 
              class="nav-item {{if this.isAllActive 'active'}}"
            >
              全部
            </a>
            {{#each this.categories as |category|}}
              <a 
                href={{this.categoryUrl category}}
                class="nav-item {{if (this.isActive category.id) 'active'}}"
              >
                {{category.name}}
                {{#if category.topic_count}}
                  <span class="count">({{category.topic_count}})</span>
                {{/if}}
              </a>
            {{/each}}
          </div>
        </div>

        {{#if this.showScrollButtons}}
          <button 
            class="scroll-button scroll-right {{if this.canScrollRight '' 'disabled'}}"
            {{on "click" this.scrollRight}}
            aria-label="向右滚动"
            disabled={{if this.canScrollRight false true}}
          >
            {{dIcon "chevron-right"}}
          </button>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
