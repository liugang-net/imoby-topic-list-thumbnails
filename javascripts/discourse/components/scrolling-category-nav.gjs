import Component from "@glimmer/component";
import { service } from "@ember/service";

export default class ScrollingCategoryNav extends Component {
  @service site;

  constructor() {
    super(...arguments);
    console.log("ScrollingCategoryNav component initialized");
    
    // 在构造函数中直接设置选中状态
    this.setupActiveState();
  }

  setupActiveState() {
    // 使用更长的延迟确保DOM完全渲染
    setTimeout(() => {
      this.updateActiveState();
    }, 500);
    
    // 只使用URL变化检测，移除其他监听器避免重复
    this.setupUrlWatcher();
  }

  get shouldShowNav() {
    return settings.show_scrolling_category_nav;
  }

  get allowedCategories() {
    if (!settings.scrolling_nav_categories) return [];
    return settings.scrolling_nav_categories.split('|').map(id => parseInt(id));
  }

  get showCounts() {
    return settings.scrolling_nav_show_counts;
  }

  get showOnMobile() {
    return settings.scrolling_nav_show_on_mobile;
  }

  setupUrlWatcher() {
    let lastUrl = window.location.pathname;
    
    setInterval(() => {
      const currentUrl = window.location.pathname;
      if (currentUrl !== lastUrl) {
        console.log('URL changed from', lastUrl, 'to', currentUrl);
        lastUrl = currentUrl;
        // 使用防抖，避免重复执行
        this.debouncedUpdateActiveState();
      }
    }, 500);
  }

  debouncedUpdateActiveState() {
    // 清除之前的定时器
    if (this.updateTimer) {
      clearTimeout(this.updateTimer);
    }
    
    // 设置新的定时器
    this.updateTimer = setTimeout(() => {
      this.updateActiveState();
    }, 100);
  }


  get categories() {
    if (!this.site?.categories) {
      return [];
    }
    
    const allCategories = this.site.categories;
    const allowedIds = this.allowedCategories;
    
    // 过滤分类：公开、顶级分类，并且如果在设置中指定了分类ID，则只显示指定的分类
    const filtered = allCategories.filter(category => {
      const isPublic = category.read_restricted === false;
      const isTopLevel = (category.parent_category_id === null || category.parent_category_id === undefined);
      const isAllowed = allowedIds.length === 0 || allowedIds.includes(category.id);
      
      return isPublic && isTopLevel && isAllowed;
    }).sort((a, b) => a.position - b.position);
    
    return filtered;
  }

  get categoryUrl() {
    return (category) => {
      const slug = category.slug || category.id.toString();
      return `/c/${slug}/${category.id}`;
    };
  }



  updateActiveState() {
    const currentPath = window.location.pathname;
    const navItems = document.querySelectorAll('.scrolling-category-nav .nav-item');
    
    navItems.forEach(item => {
      const href = item.getAttribute('href');
      let isActive = false;
      
      // 检查"最新"页面
      if (href === '/latest' && (currentPath === '/latest' || currentPath === '/' || currentPath.startsWith('/latest/'))) {
        isActive = true;
      }
      // 检查分类页面 - 使用更灵活的匹配
      else if (href && href.startsWith('/c/')) {
        // 提取分类ID进行匹配
        const hrefParts = href.split('/');
        const hrefCategoryId = hrefParts[hrefParts.length - 1];
        
        const currentParts = currentPath.split('/');
        const currentCategoryId = currentParts[currentParts.length - 1];
        
        if (hrefCategoryId === currentCategoryId) {
          isActive = true;
        }
      }
      
      if (isActive) {
        item.classList.add('active');
        console.log('Activated item:', href);
      } else {
        item.classList.remove('active');
      }
    });
  }

  <template>
    {{#if this.shouldShowNav}}
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
    {{/if}}
  </template>
}
