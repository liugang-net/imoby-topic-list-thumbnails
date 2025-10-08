import Component from "@glimmer/component";
import { service } from "@ember/service";

export default class ScrollingCategoryNav extends Component {
  @service site;

  constructor() {
    super(...arguments);
    console.log("ScrollingCategoryNav component initialized");
  }

  get categories() {
    if (!this.site?.categories) {
      console.log("No site categories found");
      return [];
    }
    
    console.log("Raw site categories:", this.site.categories);
    
    const allCategories = this.site.categories;
    console.log("All categories count:", allCategories.length);
    
    // 过滤掉未读分类和隐藏分类
    const filtered = allCategories.filter(category => {
      return category.read_restricted === false && 
             (category.parent_category_id === null || category.parent_category_id === undefined);
    }).sort((a, b) => a.position - b.position);
    
    console.log("Filtered categories:", filtered);
    return filtered;
  }

  get categoryUrl() {
    return (category) => {
      const slug = category.slug || category.id.toString();
      return `/c/${slug}/${category.id}`;
    };
  }

  <template>
    <div class="scrolling-category-nav">
      <div class="nav-container">
        <div class="nav-items">
          <a href="/latest" class="nav-item">最新</a>
          {{#each this.categories as |category|}}
            <a href={{this.categoryUrl category}} class="nav-item">
              {{category.name}}
            </a>
          {{/each}}
        </div>
      </div>
    </div>
  </template>
}
