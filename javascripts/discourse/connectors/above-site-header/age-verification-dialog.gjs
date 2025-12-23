import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { action } from "@ember/object";
import { on } from "@ember/modifier";

const STORAGE_KEYS = {
  AGE_VERIFIED: "age_verified",
  AGE_VERIFIED_TIMESTAMP: "age_verified_timestamp",
};

export default class AgeVerificationDialog extends Component {
  @service router;

  @tracked _routeUpdate = 0;
  @tracked isMounted = false;
  _previousBodyOverflow = null;
  _previousHtmlOverflow = null;

  constructor() {
    super(...arguments);

    // 标记组件已挂载
    this.isMounted = true;

    // 保存函数引用以便后续清理
    this.handleRouteChange = () => {
      this._routeUpdate = Date.now();
    };

    this.handlePopState = () => {
      this._routeUpdate = Date.now();
    };

    // 监听路由变化
    if (this.router) {
      this.router.on("routeDidChange", this.handleRouteChange);
    }

    // 监听浏览器前进/后退
    window.addEventListener("popstate", this.handlePopState);

    // 阻止 ESC 键关闭弹窗
    this.handleKeyDown = (event) => {
      if (event.key === "Escape") {
        // 检查 DOM 中是否存在弹窗
        const dialog = document.querySelector(".age-verification-overlay");
        if (dialog && dialog.offsetParent !== null) {
          event.preventDefault();
          event.stopPropagation();
        }
      }
    };
    window.addEventListener("keydown", this.handleKeyDown, true);

    // 初始更新
    this._routeUpdate = Date.now();
  }

  willDestroy() {
    super.willDestroy?.();
    // 恢复 body 滚动
    this.restoreBodyScroll();
    if (this.router?.off && this.handleRouteChange) {
      this.router.off("routeDidChange", this.handleRouteChange);
    }
    if (this.handlePopState) {
      window.removeEventListener("popstate", this.handlePopState);
    }
    if (this.handleKeyDown) {
      window.removeEventListener("keydown", this.handleKeyDown, true);
    }
  }

  // 阻止 body 和 html 滚动
  preventBodyScroll() {
    if (typeof document === "undefined") {
      return;
    }
    const body = document.body;
    const html = document.documentElement;

    // 处理 body
    if (body && this._previousBodyOverflow === null) {
      const currentBodyOverflow = body.style.overflow || "";
      if (currentBodyOverflow !== "hidden") {
        this._previousBodyOverflow = currentBodyOverflow || "";
        body.style.overflow = "hidden";
      } else {
        this._previousBodyOverflow = "";
      }
    }

    // 处理 html
    if (html && this._previousHtmlOverflow === null) {
      const currentHtmlOverflow = html.style.overflow || "";
      if (currentHtmlOverflow !== "hidden") {
        this._previousHtmlOverflow = currentHtmlOverflow || "";
        html.style.overflow = "hidden";
      } else {
        this._previousHtmlOverflow = "";
      }
    }
  }

  // 恢复 body 和 html 滚动
  restoreBodyScroll() {
    if (typeof document === "undefined") {
      return;
    }
    const body = document.body;
    const html = document.documentElement;

    // 恢复 body
    if (body && this._previousBodyOverflow !== null) {
      body.style.overflow = this._previousBodyOverflow;
      this._previousBodyOverflow = null;
    }

    // 恢复 html
    if (html && this._previousHtmlOverflow !== null) {
      html.style.overflow = this._previousHtmlOverflow;
      this._previousHtmlOverflow = null;
    }
  }

  // 获取当前路径
  get currentPath() {
    this._routeUpdate; // 依赖路由更新
    const fullPath = this.router?.currentURL || window.location.pathname;
    return fullPath.split("?")[0].split("#")[0];
  }

  // 获取完整 URL（包括查询参数）
  get fullUrl() {
    this._routeUpdate; // 依赖路由更新
    return typeof window !== "undefined" ? window.location.href : "";
  }

  // 检查是否为例外页面
  get isExcludedPage() {
    if (!settings.age_verification_excluded_paths) {
      return false;
    }

    const excludedPaths = settings.age_verification_excluded_paths
      .split("|")
      .filter((path) => path.trim());

    const pathname = this.currentPath;
    const fullUrl = this.fullUrl;

    return excludedPaths.some((path) => {
      // 检查 pathname 是否包含例外路径
      if (pathname?.includes(path)) {
        return true;
      }
      // 检查完整 URL（包括查询参数）是否包含例外路径
      if (fullUrl && fullUrl.includes(path)) {
        return true;
      }
      return false;
    });
  }

  // 检查是否已经验证过
  get isAgeVerified() {
    if (typeof window === "undefined") {
      return false;
    }

    // 获取时间间隔配置（默认 86400 秒 = 1天）
    const intervalSeconds =
      settings.age_verification_interval_seconds || 86400;

    // 如果时间间隔为 0 或负数，每次都需要验证
    if (intervalSeconds <= 0) {
      return false;
    }

    // 检查时间戳
    const verifiedTimestamp = localStorage.getItem(
      STORAGE_KEYS.AGE_VERIFIED_TIMESTAMP
    );

    // 如果没有时间戳，检查是否有旧的验证状态（向后兼容）
    if (!verifiedTimestamp) {
      const oldVerified = localStorage.getItem(STORAGE_KEYS.AGE_VERIFIED);
      // 如果有旧的验证状态但没有时间戳，视为需要重新验证
      return false;
    }

    // 计算时间差
    const now = Date.now();
    const timestamp = parseInt(verifiedTimestamp, 10);

    // 如果时间戳无效，需要重新验证
    if (isNaN(timestamp)) {
      return false;
    }

    // 计算距离验证的时间（秒）
    const timeSinceVerification = (now - timestamp) / 1000;

    // 如果还在时间间隔内，返回 true
    return timeSinceVerification < intervalSeconds;
  }

  // 检查是否应该显示弹窗
  get shouldShow() {
    // 依赖路由更新，确保路径变化时重新计算
    this._routeUpdate;

    // 如果未启用年龄验证，不显示
    if (!settings.age_verification_enabled) {
      this.restoreBodyScroll();
      return false;
    }

    // 如果组件未挂载，不显示
    if (!this.isMounted || typeof window === "undefined") {
      this.restoreBodyScroll();
      return false;
    }

    // 如果当前页面为例外页面，不显示
    if (this.isExcludedPage) {
      this.restoreBodyScroll();
      return false;
    }

    // 如果已经验证过，不显示
    if (this.isAgeVerified) {
      this.restoreBodyScroll();
      return false;
    }

    // 其他情况显示弹窗，并阻止背景滚动
    this.preventBodyScroll();
    return true;
  }

  // 确认处理
  @action
  handleConfirm() {
    if (typeof window !== "undefined") {
      // 存储当前时间戳（毫秒）
      const timestamp = Date.now();
      localStorage.setItem(
        STORAGE_KEYS.AGE_VERIFIED_TIMESTAMP,
        timestamp.toString()
      );
      // 同时存储验证状态（保持兼容性）
      localStorage.setItem(STORAGE_KEYS.AGE_VERIFIED, "true");
    }
    // 触发重新计算 shouldShow
    this._routeUpdate = Date.now();
  }

  // 拒绝处理
  @action
  handleReject() {
    if (typeof window !== "undefined") {
      const rejectUrl =
        settings.age_verification_reject_url ||
        "https://cdn.ibomy.com/forum/images/age_verify/r18.html";

      // 尝试关闭窗口（如果窗口是通过脚本打开的）
      try {
        window.close();
      } catch (error) {
        // 忽略错误
      }

      // 重定向到拒绝页面
      setTimeout(() => {
        window.location.href = rejectUrl;
      }, 50);
    }
  }


  // CDN 图片地址
  get imageUrls() {
    return {
      character:
        "https://cdn.ibomy.com/forum/images/age_verify/character1.png",
      r18: "https://cdn.ibomy.com/forum/images/age_verify/r18.png",
      bg: "https://cdn.ibomy.com/forum/images/age_verify/bg.png",
      title: "https://cdn.ibomy.com/forum/images/age_verify/title.png",
      accept: "https://cdn.ibomy.com/forum/images/age_verify/accept.png",
      reject: "https://cdn.ibomy.com/forum/images/age_verify/reject.png",
    };
  }

  <template>
    {{#if this.shouldShow}}
      <div class="age-verification-overlay">
        <div class="age-verification-dialog">
          {{! 角色图片 }}
          <img
            src={{this.imageUrls.character}}
            alt=""
            class="age-verify-character"
          />

          {{! R18 标签 }}
          <img
            src={{this.imageUrls.r18}}
            alt="R18"
            class="age-verify-r18"
          />

          {{! 背景图 }}
          <img
            src={{this.imageUrls.bg}}
            alt=""
            class="age-verify-bg"
          />

          {{! 内容区域 }}
          <div class="age-verification-content">
            {{! 标题 }}
            <img
              src={{this.imageUrls.title}}
              alt=""
              class="age-verify-title"
            />

            {{! 说明文字 }}
            <div class="age-verify-text">
              该网站包含有年龄限制的内容，包括仿照人体器官的建模素材。登录或者进入网站即表示您确认您已年满
              18 岁，或在您访问本网站时所在的司法管辖区已是成年人。
            </div>

            {{! 按钮区域 }}
            <div class="age-verify-buttons">
              <div
                class="age-verify-button age-verify-accept"
                role="button"
                {{on "click" this.handleConfirm}}
              >
                <img
                  src={{this.imageUrls.accept}}
                  alt="确认"
                  class="age-verify-button-img"
                />
              </div>
              <div
                class="age-verify-button age-verify-reject"
                role="button"
                {{on "click" this.handleReject}}
              >
                <img
                  src={{this.imageUrls.reject}}
                  alt="拒绝"
                  class="age-verify-button-img"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}

