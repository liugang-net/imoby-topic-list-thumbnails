import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";

export default class MaintenanceNotice extends Component {
  @service currentUser;
  @service router;

  @tracked _routeUpdate = 0;

  // 允许访问的路径（不需要显示维护通知）
  static ALLOWED_PATHS = ['/login', '/session', '/admin'];

  constructor() {
    super(...arguments);
    
    // 保存函数引用以便后续清理
    this.handleRouteChange = () => {
      this._routeUpdate = Date.now();
    };
    
    this.handlePopState = () => {
      this._routeUpdate = Date.now();
    };
    
    // 监听路由变化，确保 shouldShow 重新计算
    if (this.router) {
      this.router.on('routeDidChange', this.handleRouteChange);
    }
    
    // 监听浏览器前进/后退
    window.addEventListener('popstate', this.handlePopState);
    
    // 初始更新
    this._routeUpdate = Date.now();
  }

  willDestroy() {
    super.willDestroy?.();
    if (this.router?.off && this.handleRouteChange) {
      this.router.off('routeDidChange', this.handleRouteChange);
    }
    if (this.handlePopState) {
      window.removeEventListener('popstate', this.handlePopState);
    }
  }

  // 提取纯路径（移除查询参数和锚点）
  get currentPath() {
    const fullPath = this.router?.currentURL || window.location.pathname;
    return fullPath.split('?')[0].split('#')[0].toLowerCase();
  }

  // 检查路径是否允许访问
  get isPathAllowed() {
    const path = this.currentPath;
    return MaintenanceNotice.ALLOWED_PATHS.some(allowed => {
      return path === allowed || path.startsWith(`${allowed}/`);
    });
  }

  // 检查是否应该显示维护通知
  get shouldShow() {
    // 依赖路由更新，确保路径变化时重新计算
    this._routeUpdate;
    
    // 如果未启用维护模式，不显示
    if (!settings.maintenance_mode_enabled) {
      return false;
    }

    // 管理员可以访问所有页面
    if (this.currentUser?.admin) {
      return false;
    }

    // 检查路径是否允许访问
    if (this.isPathAllowed) {
      return false;
    }

    // 其他页面显示维护通知
    return true;
  }

  get maintenanceImage() {
    return settings.maintenance_mode_image || null;
  }

  get maintenanceTitle() {
    return settings.maintenance_mode_title || "敬请期待";
  }

  get maintenanceDescription() {
    return settings.maintenance_mode_description || "我们正在努力开发中，请稍后再来！";
  }

  <template>
    {{#if this.shouldShow}}
      <div class="maintenance-notice-overlay">
        <div class="maintenance-notice-content">
          {{#if this.maintenanceImage}}
            <div class="maintenance-notice-image">
              <img src={{this.maintenanceImage}} alt="维护中" />
            </div>
          {{/if}}
          <div class="maintenance-notice-text">
            <h1 class="maintenance-notice-title">{{this.maintenanceTitle}}</h1>
            <p class="maintenance-notice-description">{{this.maintenanceDescription}}</p>
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}

