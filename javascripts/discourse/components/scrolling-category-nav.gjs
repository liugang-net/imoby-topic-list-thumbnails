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
  
  willDestroy() {
    super.willDestroy();
    
    // 清理事件监听器
    if (this.urlWatcher) {
      window.removeEventListener('popstate', this.urlWatcher);
    }
    
    // 清理点击事件监听器
    if (this.navItems) {
      this.navItems.forEach(item => {
        if (item.clickHandler) {
          item.removeEventListener('click', item.clickHandler);
          item.clickHandler = null;
        }
      });
    }
    
    // 清理缓存的DOM元素
    this.navItems = null;
  }

  setupActiveState() {
    // 使用requestAnimationFrame确保DOM完全渲染，但更高效
    requestAnimationFrame(() => {
      this.updateActiveState();
      // 设置点击事件监听器
      this.setupClickHandlers();
    });
    
    // 设置URL变化监听器
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

  get backgroundColor() {
    return settings.scrolling_nav_background_color;
  }

  get navStyle() {
    return `background-color: ${this.backgroundColor};`;
  }

  setupClickHandlers() {
    // 为每个导航项添加点击事件监听器
    if (this.navItems && this.navItems.length > 0) {
      this.navItems.forEach(item => {
        // 移除之前的事件监听器（如果存在）
        if (item.clickHandler) {
          item.removeEventListener('click', item.clickHandler);
        }
        
        // 创建新的点击处理器
        item.clickHandler = (event) => {
          // 立即更新选中状态，不等待URL变化
          this.updateActiveStateOnClick(item);
        };
        
        // 添加事件监听器
        item.addEventListener('click', item.clickHandler);
      });
    }
  }
  
  updateActiveStateOnClick(clickedItem) {
    // 立即清除所有active状态
    if (this.navItems) {
      this.navItems.forEach(item => {
        item.classList.remove('active');
      });
    }
    
    // 立即设置被点击项为active
    clickedItem.classList.add('active');
    console.log('Immediately activated item:', clickedItem.getAttribute('href'));
  }

  setupUrlWatcher() {
    let lastUrl = window.location.pathname;
    
    // 使用更高效的URL变化检测
    this.urlWatcher = () => {
      const currentUrl = window.location.pathname;
      if (currentUrl !== lastUrl) {
        console.log('URL changed from', lastUrl, 'to', currentUrl);
        lastUrl = currentUrl;
        // 立即更新，减少延迟
        this.updateActiveState();
      }
    };
    
    // 监听popstate事件（浏览器前进/后退）
    window.addEventListener('popstate', this.urlWatcher);
    
    // 监听pushstate/replacestate（SPA路由变化）
    const originalPushState = history.pushState;
    const originalReplaceState = history.replaceState;
    
    history.pushState = function(...args) {
      originalPushState.apply(history, args);
      setTimeout(() => this.urlWatcher(), 0);
    }.bind(this);
    
    history.replaceState = function(...args) {
      originalReplaceState.apply(history, args);
      setTimeout(() => this.urlWatcher(), 0);
    }.bind(this);
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
    
    // 缓存DOM查询结果
    if (!this.navItems) {
      this.navItems = document.querySelectorAll('.scrolling-category-nav .nav-item');
    }
    
    // 如果DOM元素不存在，尝试重新查询
    if (this.navItems.length === 0) {
      this.navItems = document.querySelectorAll('.scrolling-category-nav .nav-item');
      if (this.navItems.length === 0) {
        console.log('Nav items not found, skipping update');
        return;
      }
    }
    
    // 预计算当前路径的匹配规则
    const isLatestPage = currentPath === '/latest' || currentPath === '/' || currentPath.startsWith('/latest/');
    const currentCategoryId = this.extractCategoryId(currentPath);
    
    this.navItems.forEach(item => {
      const href = item.getAttribute('href');
      let isActive = false;
      
      // 检查"最新"页面
      if (href === '/latest' && isLatestPage) {
        isActive = true;
      }
      // 检查分类页面 - 使用预计算的分类ID
      else if (href && href.startsWith('/c/') && currentCategoryId) {
        const hrefCategoryId = this.extractCategoryId(href);
        if (hrefCategoryId === currentCategoryId) {
          isActive = true;
        }
      }
      
      // 使用classList.toggle优化DOM操作
      item.classList.toggle('active', isActive);
      
      if (isActive) {
        console.log('Activated item:', href);
      }
    });
  }
  
  extractCategoryId(path) {
    const parts = path.split('/');
    return parts[parts.length - 1];
  }

  <template>
    {{#if this.shouldShowNav}}
      <div class="scrolling-category-nav" style={{this.navStyle}}>
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
