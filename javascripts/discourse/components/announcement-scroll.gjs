import Component from "@glimmer/component";
import { service } from "@ember/service";

export default class AnnouncementScroll extends Component {
  @service site;
  @service router;

  constructor() {
    super(...arguments);
    this.setupScrollAnimation();
    this.setupRouteWatcher();
  }

  setupRouteWatcher() {
    // 监听 Discourse 路由变化
    const router = this.router;
    if (router) {
      // 监听路由变化事件
      router.on('routeDidChange', () => {
        console.log('🔄 Discourse 路由变化检测');
        this.handleRouteChange();
      });
    }
    
    // 备用方案：监听浏览器路由变化
    this.setupBrowserRouteWatcher();
  }

  setupBrowserRouteWatcher() {
    let lastPath = window.location.pathname;
    
    const checkRouteChange = () => {
      const currentPath = window.location.pathname;
      if (currentPath !== lastPath) {
        console.log('🔄 浏览器路由变化检测:', lastPath, '->', currentPath);
        lastPath = currentPath;
        this.handleRouteChange();
      }
    };
    
    // 使用定时器检查路由变化
    this.routeCheckInterval = setInterval(checkRouteChange, 1000);
    
    // 监听浏览器前进后退
    window.addEventListener('popstate', checkRouteChange);
  }

  handleRouteChange() {
    // 强制重新计算 shouldShow
    this._forceUpdate = Date.now();
    console.log('🔄 强制更新组件:', this._forceUpdate);
    
    // 强制重新渲染组件
    this._forceRerender = Date.now();
    console.log('🔄 强制重新渲染:', this._forceRerender);
    
    // 直接操作DOM来显示/隐藏公告
    setTimeout(() => {
      this.updateAnnouncementVisibility();
    }, 100);
  }

  updateAnnouncementVisibility() {
    const currentPath = window.location.pathname;
    
    // 参考官方组件的显示逻辑
    // 1. 检查是否有公告数据
    if (!this.announcements || this.announcements.length === 0) {
      this.hideAnnouncement();
      return;
    }
    
    // 2. 检查移动设备显示设置
    const isMobile = window.innerWidth <= 768;
    if (isMobile && !this.showOnMobile) {
      this.hideAnnouncement();
      return;
    }
    
    // 排除的页面
    const excludedPaths = [
      '/login', '/admin', '/t/', '/u/', '/about', '/faq', '/tos', '/privacy',
      '/session', '/admin/', '/my/', '/preferences', '/notifications', '/messages',
      '/badges', '/groups', '/search', '/top', '/unread', '/new',
      '/bookmarks', '/activity', '/summary'
    ];
    
    // 允许的页面
    const allowedPaths = ['/', '/latest', '/c/', '/tags', '/tag/'];
    
    const isExcluded = excludedPaths.some(path => currentPath.startsWith(path));
    const isAllowed = allowedPaths.some(path => {
      if (path === '/') {
        return currentPath === '/' || currentPath === '';
      }
      return currentPath.startsWith(path);
    });
    
    const shouldShow = !isExcluded && isAllowed;
    
    // 查找公告元素并设置显示/隐藏
    const announcementElement = document.querySelector('.announcement-scroll');
    if (announcementElement) {
      if (shouldShow) {
        announcementElement.style.display = 'block';
      } else {
        this.hideAnnouncement();
      }
    }
  }

  hideAnnouncement() {
    const announcementElement = document.querySelector('.announcement-scroll');
    if (announcementElement) {
      announcementElement.style.display = 'none';
    }
  }

  willDestroy() {
    super.willDestroy();
    // 清理定时器
    if (this.routeCheckInterval) {
      clearInterval(this.routeCheckInterval);
    }
    if (this.scrollTimer) {
      clearInterval(this.scrollTimer);
    }
  }

  get shouldShow() {
    // 依赖强制更新属性，确保路由变化时重新计算
    this._forceUpdate;
    this._forceRerender;
    
    const currentPath = window.location.pathname;
    
    // 参考Discourse官方banner组件的显示逻辑
    // 1. 首先检查是否有公告数据
    if (!this.announcements || this.announcements.length === 0) {
      return false;
    }
    
    // 2. 检查移动设备显示设置（参考官方组件）
    const isMobile = window.innerWidth <= 768;
    if (isMobile && !this.showOnMobile) {
      return false;
    }
    
    // 排除的页面 - 这些页面不显示公告
    const excludedPaths = [
      '/login',
      '/admin',
      '/t/',      // 话题详情页
      '/u/',      // 用户页面
      '/about',
      '/faq',
      '/tos',
      '/privacy',
      '/session', // 登录相关页面
      '/admin/',  // 管理页面
      '/my/',     // 个人设置页面
      '/preferences', // 偏好设置
      '/notifications', // 通知页面
      '/messages', // 消息页面
      '/badges',  // 徽章页面
      '/groups',  // 群组页面
      '/search',  // 搜索页面
      '/top',     // 热门页面（如果需要排除的话）
      '/unread',  // 未读页面
      '/new',     // 新话题页面
      '/bookmarks', // 书签页面
      '/activity', // 活动页面
      '/summary'  // 摘要页面
    ];
    
    // 检查是否在排除的路径中
    const isExcluded = excludedPaths.some(path => currentPath.startsWith(path));
    if (isExcluded) {
      return false;
    }
    
    // 只允许在以下页面显示：
    // - 首页 (/)
    // - 最新页 (/latest)
    // - 分类页面 (/c/)
    // - 标签页面 (/tags 和 /tag/)
    const allowedPaths = [
      '/',        // 首页
      '/latest',  // 最新页
      '/c/',      // 分类页面
      '/tags',    // 标签列表页
      '/tag/'     // 具体标签页
    ];
    
    // 检查是否在允许的路径中
    const isAllowed = allowedPaths.some(path => {
      if (path === '/') {
        return currentPath === '/' || currentPath === '';
      }
      return currentPath.startsWith(path);
    });
    
    // 只有在允许的页面且有公告数据时才显示
    const hasAnnouncements = this.announcements && this.announcements.length > 0;
    return isAllowed && hasAnnouncements;
  }

  get announcements() {
    // 从site服务中获取分类公告数据
    return this.site?.category_announcements || [];
  }

  get showOnMobile() {
    // 移动设备显示设置（参考官方组件）
    // 可以通过设置控制，这里默认允许移动设备显示
    return true;
  }


  get topicUrl() {
    return (announcement) => {
      return `/t/${announcement.slug}/${announcement.id}`;
    };
  }

  get announcementStyle() {
    // 依赖强制更新属性，确保路由变化时重新计算
    this._forceUpdate;
    this._forceRerender;
    
    const shouldShow = this.shouldShow;
    
    if (shouldShow) {
      return 'display: block;';
    } else {
      return 'display: none;';
    }
  }

  setupScrollAnimation() {
    // 延迟执行，确保DOM已渲染
    setTimeout(() => {
      this.startScrollAnimation();
    }, 1000);
  }

  startScrollAnimation() {
    const container = document.querySelector('.announcement-scroll-container');
    if (!container) return;

    const content = container.querySelector('.announcement-content');
    if (!content) return;

    // 如果公告数量少于等于1，不需要滚动
    if (this.announcements.length <= 1) {
      return;
    }

    // 设置无限向上滚动
    const scrollInterval = 3000; // 每3秒滚动一次
    let currentIndex = 0;
    const isMobile = window.innerWidth <= 768;
    const itemHeight = isMobile ? 36 : 40; // 根据设备类型设置行高

    const scrollToNext = () => {
      // 无限向上滚动
      currentIndex++;
      const translateY = -currentIndex * itemHeight;
      content.style.transform = `translateY(${translateY}px)`;
      
      // 当滚动到第二组公告开始时，重置位置实现无缝循环
      if (currentIndex >= this.announcements.length) {
        setTimeout(() => {
          currentIndex = 0;
          content.style.transition = 'none';
          content.style.transform = 'translateY(0)';
          setTimeout(() => {
            content.style.transition = 'transform 0.5s ease';
          }, 50);
        }, 500);
      }
    };

    // 设置定时器
    this.scrollTimer = setInterval(scrollToNext, scrollInterval);

    // 添加鼠标悬停暂停功能
    const announcementElement = document.querySelector('.announcement-scroll');
    if (announcementElement) {
      announcementElement.addEventListener('mouseenter', () => {
        if (this.scrollTimer) {
          clearInterval(this.scrollTimer);
          this.scrollTimer = null;
        }
      });

      announcementElement.addEventListener('mouseleave', () => {
        if (!this.scrollTimer) {
          this.scrollTimer = setInterval(scrollToNext, scrollInterval);
        }
      });
    }
  }

  easeInOutQuad(t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  <template>
    <div class="announcement-scroll" style={{this.announcementStyle}}>
      <div class="announcement-scroll-container">
        <div class="announcement-content">
          {{#each this.announcements as |announcement|}}
            <a href={{this.topicUrl announcement}} class="announcement-item">
              <span class="announcement-badge">公告</span>
              <span class="announcement-title">{{announcement.title}}</span>
            </a>
          {{/each}}
          {{#each this.announcements as |announcement|}}
            <a href={{this.topicUrl announcement}} class="announcement-item">
              <span class="announcement-badge">公告</span>
              <span class="announcement-title">{{announcement.title}}</span>
            </a>
          {{/each}}
        </div>
      </div>
      <div class="announcement-more">
        <a href="/c/10/10" class="more-link">更多</a>
      </div>
    </div>
  </template>
}
