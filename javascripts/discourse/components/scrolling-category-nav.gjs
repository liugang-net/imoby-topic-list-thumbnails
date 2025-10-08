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
    
    // 监听页面导航事件
    this.setupNavigationListener();
    
    // 定期检查URL变化（作为备用方案）
    this.setupUrlWatcher();
  }

  setupUrlWatcher() {
    let lastUrl = window.location.pathname;
    
    setInterval(() => {
      const currentUrl = window.location.pathname;
      if (currentUrl !== lastUrl) {
        console.log('URL changed from', lastUrl, 'to', currentUrl);
        lastUrl = currentUrl;
        this.updateActiveState();
      }
    }, 500);
  }

  setupNavigationListener() {
    // 监听popstate事件（浏览器前进后退）
    window.addEventListener('popstate', () => {
      setTimeout(() => {
        this.updateActiveState();
      }, 100);
    });
    
    // 监听所有导航链接的点击事件
    document.addEventListener('click', (event) => {
      const target = event.target.closest('a');
      if (target && target.classList.contains('nav-item')) {
        // 延迟更新，等待页面导航完成
        setTimeout(() => {
          this.updateActiveState();
        }, 200);
      }
    });
    
    // 监听Discourse的路由变化
    if (typeof Discourse !== 'undefined' && Discourse.__container__) {
      const router = Discourse.__container__.lookup('router:main');
      if (router) {
        router.on('routeDidChange', () => {
          setTimeout(() => {
            this.updateActiveState();
          }, 100);
        });
      }
    }
  }

  get categories() {
    if (!this.site?.categories) {
      return [];
    }
    
    const allCategories = this.site.categories;
    
    // 过滤掉未读分类和隐藏分类
    const filtered = allCategories.filter(category => {
      return category.read_restricted === false && 
             (category.parent_category_id === null || category.parent_category_id === undefined);
    }).sort((a, b) => a.position - b.position);
    
    return filtered;
  }

  get categoryUrl() {
    return (category) => {
      const slug = category.slug || category.id.toString();
      return `/c/${slug}/${category.id}`;
    };
  }

  getItemClass(itemType, category = null) {
    return 'nav-item';
  }


  updateActiveState() {
    const currentPath = window.location.pathname;
    console.log('Current path:', currentPath);
    const navItems = document.querySelectorAll('.scrolling-category-nav .nav-item');
    console.log('Found nav items:', navItems.length);
    
    navItems.forEach(item => {
      const href = item.getAttribute('href');
      console.log('Checking item:', href, 'against path:', currentPath);
      
      let isActive = false;
      
      // 检查"最新"页面
      if (href === '/latest' && (currentPath === '/latest' || currentPath === '/' || currentPath.startsWith('/latest/'))) {
        isActive = true;
      }
      // 检查分类页面 - 使用更灵活的匹配
      else if (href && href.startsWith('/c/')) {
        // 提取分类ID进行匹配
        const hrefParts = href.split('/');
        const hrefCategoryId = hrefParts[hrefParts.length - 1]; // 获取最后一个部分作为ID
        
        const currentParts = currentPath.split('/');
        const currentCategoryId = currentParts[currentParts.length - 1]; // 获取当前路径的最后一个部分作为ID
        
        console.log('Comparing category IDs:', hrefCategoryId, 'vs', currentCategoryId);
        
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
    <div class="scrolling-category-nav">
      <div class="nav-container">
        <div class="nav-items">
          <a href="/latest" class={{this.getItemClass "latest"}}>最新</a>
          {{#each this.categories as |category|}}
            <a href={{this.categoryUrl category}} class={{this.getItemClass "category" category}}>
              {{category.name}}
            </a>
          {{/each}}
        </div>
      </div>
    </div>
  </template>
}
