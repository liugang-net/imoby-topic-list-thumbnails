import Component from "@glimmer/component";
import { service } from "@ember/service";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import coldAgeClass from "discourse/helpers/cold-age-class";
import concatClass from "discourse/helpers/concat-class";
import dIcon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { getAbsoluteURL } from "discourse/lib/get-url";
import { nativeShare } from "discourse/lib/pwa-utils";
import ShareTopicModal from "discourse/components/modal/share-topic";
import { i18n } from "discourse-i18n";

export default class TopicListThumbnail extends Component {
  @service topicThumbnails;
  @service router;
  @service currentUser;
  @service modal;
  @service capabilities;

  @tracked _forceUpdate = 0;
  @tracked _isLiked = null;
  @tracked _likeCount = null;

  responsiveRatios = [1, 1.5, 2];

  // Make sure to update about.json thumbnail sizes if you change these variables
  get displayWidth() {
    return this.topicThumbnails.displayList
      ? settings.list_thumbnail_size
      : 400;
  }

  get topic() {
    return this.args.topic;
  }

  get hasThumbnail() {
    // 优先检查新的images数组
    if (this.topic.images && this.topic.images.length > 0) {
      return true;
    }
    // 回退到原来的thumbnails
    return !!this.topic.thumbnails;
  }

  get srcSet() {
    const srcSetArray = [];

    this.responsiveRatios.forEach((ratio) => {
      const target = ratio * this.displayWidth;
      const match = this.topic.thumbnails.find(
        (t) => t.url && t.max_width === target
      );
      if (match) {
        srcSetArray.push(`${match.url} ${ratio}x`);
      }
    });

    if (srcSetArray.length === 0) {
      srcSetArray.push(`${this.original.url} 1x`);
    }

    return srcSetArray.join(",");
  }

  get original() {
    return this.topic.thumbnails[0];
  }

  get width() {
    return this.original.width;
  }

  get isLandscape() {
    return this.original.width >= this.original.height;
  }

  get height() {
    return this.original.height;
  }

  get fallbackSrc() {
    const largeEnough = this.topic.thumbnails.filter((t) => {
      if (!t.url) {
        return false;
      }
      return t.max_width > this.displayWidth * this.responsiveRatios.lastObject;
    });

    if (largeEnough.lastObject) {
      return largeEnough.lastObject.url;
    }

    return this.original.url;
  }

  get url() {
    return this.topic.get("linked_post_number")
      ? this.topic.urlForPostNumber(this.topic.get("linked_post_number"))
      : this.topic.get("url");
  }

  get lastPostUrl() {
    return this.topic.get("lastPostUrl");
  }

  get user() {
    // 1) 明确给出的创建者对象
    if (this.topic.created_by) {
      return this.topic.created_by;
    }

    // 2) 尝试通过posters与users匹配
    const posters = this.topic.posters || [];
    const firstPoster = posters[0];
    const authorUserId = firstPoster?.user_id;

    if (authorUserId) {
      // 2.1 优先尝试 topic.users（若后端已将 users 嵌入到每个 topic 中）
      const embeddedUsers = this.topic.users || [];
      const fromEmbedded = embeddedUsers.find((u) => u?.id === authorUserId);
      if (fromEmbedded) {
        return fromEmbedded;
      }

      // 2.2 尝试从父级/外部传入的 users（若初始化器或外层传入）
      const argsUsers = this.args?.users || [];
      const fromArgs = argsUsers.find((u) => u?.id === authorUserId);
      if (fromArgs) {
        return fromArgs;
      }

      // 2.3 有些场景 Ember 会给 poster 附上 user 对象
      if (firstPoster.user) {
        return firstPoster.user;
      }
    }

    // 3) 回退方案：部分接口会给出最后回复用户（并不一定是原作者）
    return this.topic.user;
  }

  get userAvatar() {
    return this.user?.avatar_template;
  }

  get userName() {
    return this.user?.name || this.user?.username;
  }

  get authorUsername() {
    const u = this.user?.username;
    return typeof u === "string" ? u.trim() : "";
  }

  get authorHasIbomyProfile() {
    return this.authorUsername.length > 0;
  }

  get authorProfileWrapperClass() {
    return this.authorHasIbomyProfile
      ? "topic-user-header__profile"
      : "topic-user-header__profile topic-user-header__profile--static";
  }

  navigateToIbomyProfile() {
    const username = this.authorUsername;
    if (!username) {
      return;
    }
    if (this.router?.transitionTo) {
      try {
        this.router.transitionTo("ibomy.u.index", username);
      } catch {
        window.location.href = `/ibomy/u/${encodeURIComponent(username)}`;
      }
    } else {
      window.location.href = `/ibomy/u/${encodeURIComponent(username)}`;
    }
  }

  @action
  handleAuthorProfileClick(event) {
    if (!this.authorHasIbomyProfile) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    this.navigateToIbomyProfile();
  }

  @action
  handleAuthorProfileKeydown(event) {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    if (!this.authorHasIbomyProfile) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    this.navigateToIbomyProfile();
  }

  get userTitle() {
    return this.user?.title;
  }

  get postTime() {
    // 使用主题创建时间，如果没有则使用最后回复时间
    return this.topic.created_at || this.topic.bumpedAt;
  }

  get postTimeFormatted() {
    return formatDate(this.postTime, { format: "tiny", noTitle: true });
  }

  get isVideo() {
    // 检查是否有视频URL
    return !!(this.topic.video_url && this.topic.video_url.trim());
  }

  get videoThumbnail() {
    // 获取视频缩略图
    return this.topic.video_thumbnail;
  }

  get images() {
    // 在信息流模式下，只使用新的images数组，不回退到thumbnails
    if (this.topicThumbnails.displayFeed) {
      // 如果是视频，返回视频缩略图
      if (this.isVideo && this.videoThumbnail) {
        return [this.videoThumbnail];
      }
      
      if (this.topic.images && this.topic.images.length > 0) {
        return this.topic.images
          .filter(img => img.url)
          .slice(0, 3)
          .map(img => this.getOptimizedImageUrl(img));
      }
      return [];
    }
    
    // 其他模式：优先使用新的images数组，如果没有则使用thumbnails
    if (this.topic.images && this.topic.images.length > 0) {
      return this.topic.images
        .filter(img => img.url)
        .slice(0, 3)
        .map(img => this.getOptimizedImageUrl(img));
    }
    
    // 回退到原来的thumbnails
    if (!this.hasThumbnail) return [];
    
    const imageUrls = this.topic.thumbnails
      .filter(t => t.url)
      .slice(0, 3)
      .map(t => t.url);
    
    return imageUrls;
  }

  getOptimizedImageUrl(imageData) {
    // 从thumbnails数组中找到第一个max_width >= 400的缩略图
    if (imageData.thumbnails && imageData.thumbnails.length > 0) {
      const optimizedThumbnail = imageData.thumbnails.find(thumb => 
        thumb.max_width !== null && thumb.max_width >= 399
      );
      
      if (optimizedThumbnail) {
        return optimizedThumbnail.url;
      }
    }
    
    // 如果没有找到合适的缩略图，使用原始URL
    return imageData.url;
  }

  get imageCount() {
    return this.images.length;
  }

  get totalImageCount() {
    // 在信息流模式下，只使用新的images数组
    if (this.topicThumbnails.displayFeed) {
      if (this.topic.images && this.topic.images.length > 0) {
        return this.topic.images.filter(img => img.url).length;
      }
      return 0;
    }
    
    // 其他模式：获取实际的总图片数量
    if (this.topic.images && this.topic.images.length > 0) {
      return this.topic.images.filter(img => img.url).length;
    }
    if (this.topic.thumbnails) {
      return this.topic.thumbnails.filter(t => t.url).length;
    }
    return 0;
  }

  get showImageCount() {
    return this.totalImageCount > 3;
  }

  get imageLayoutClass() {
    if (this.imageCount === 1) {
      // 单张图片时，根据宽高比例添加形状类型
      const imageShape = this.getImageShape();
      return `single-image ${imageShape}`;
    }
    if (this.imageCount === 2) return "multiple-images two-images";
    if (this.imageCount === 3) return "multiple-images three-images";
    return "";
  }

  getImageShape() {
    // 从topic.images数组中获取第一张图片的尺寸信息
    const firstImage = this.topic.images?.[0];
    if (!firstImage) return "normal";
    
    // 检查firstImage是否是对象
    if (typeof firstImage !== 'object' || firstImage === null) {
      return "normal";
    }
    
    // 从topic.images数组中获取图片尺寸信息
    const width = firstImage.width;
    const height = firstImage.height;
    
    // 当width和height都是null时，归为正常
    if (width === null && height === null) return "normal";
    
    // 当width或height为null时，归为正常
    if (width === null || height === null) return "normal";
    
    // 当宽度和高度都小于400px时，归为正常
    if (width < 400 && height < 400) return "normal";
    
    // 计算宽高比
    const ratio = width / height;
    
    // 以3:4和4:3为判断条件
    if (ratio > 4/3) {
      return "landscape"; // 横向：宽高比大于4:3
    } else if (ratio < 3/4) {
      return "portrait"; // 竖向：宽高比小于3:4
    } else {
      return "normal"; // 正常：宽高比在3:4到4:3之间
    }
  }

  get avatarUrl() {
    if (this.userAvatar) {
      return this.userAvatar.replace("{size}", "40");
    }
    return null;
  }

  get avatarInitials() {
    if (this.userName) {
      return this.userName.charAt(0).toUpperCase();
    }
    return "?";
  }

  /**
   * 支持两种后端返回格式：
   * - 旧：topic.tags = ["tag-a", "tag-b"]
   * - 新：topic.tags = [{ id, name, slug }, ...]
   */
  get normalizedTags() {
    const rawTags = this.topic?.tags || [];

    return rawTags
      .map((t) => {
        if (typeof t === "string") {
          return { id: null, name: t, slug: t };
        }

        const id = t?.id ?? null;
        const name = t?.name;
        const slug = t?.slug || name;

        if (!name && !slug) {
          return null;
        }

        return { id, name: name || slug, slug };
      })
      .filter(Boolean);
  }

  tagHref(tag) {
    if (!tag) {
      return "/tags";
    }

    // 新接口可能返回对象：{ id, name, slug }
    if (typeof tag === "object") {
      const slug = tag?.slug || tag?.name;
      const id = tag?.id;

      // 你当前站点的 tag 路由形如：/tag/<slug>/<id>
      if (slug && id) {
        return `/tag/${encodeURIComponent(slug)}/${encodeURIComponent(id)}`;
      }

      // 回退到只有 slug 的形式（不同站点/版本可能是 /tag/<slug>）
      if (slug) {
        return `/tag/${encodeURIComponent(slug)}`;
      }
    }

    // 旧格式：topic.tags = ["tag-a", "tag-b"]
    const tagName = typeof tag === "string" ? tag : null;
    if (tagName) {
      // 回退到 /tag/<name>（更接近新版路由）
      return `/tag/${encodeURIComponent(tagName)}`;
    }

    // 最终回退
    return "/tags";
  }

  @action
  handleTopicClick(event) {
    // 防止重复点击
    if (this._isNavigating) {
      return;
    }
    
    // 检查是否点击在可交互元素上（这些元素有自己的点击处理）
    const target = event.target;
    const interactiveElements = target.closest(
      ".user-link, .topic-user-header__profile, .discourse-tag, .stat, .action-button, .video-play-button, .title, .topic-excerpt, .topic-thumbnail-blog-data-share"
    );
    if (interactiveElements) {
      return; // 如果点击在可交互元素上，不处理
    }
    
    // 阻止默认行为并跳转到主题
    event.preventDefault();
    event.stopPropagation();
    
    // 设置导航标志，防止重复点击
    this._isNavigating = true;
    
    // 检测是否为移动端
    const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
    
    if (isMobile) {
      // 移动端直接跳转，避免SPA路由问题
      window.location.href = this.url;
    } else {
      // 桌面端使用SPA路由
      if (this.router && typeof this.router.transitionTo === 'function') {
        try {
          this.router.transitionTo('topic', this.topic.slug, this.topic.id);
          return;
        } catch (error) {
          console.warn('Router transitionTo failed:', error);
        }
      }
      
      // 回退到直接跳转
      window.location.href = this.url;
    }
    
    // 延迟重置导航标志
    setTimeout(() => {
      this._isNavigating = false;
    }, 1000);
  }

  get replyCount() {
    // 优先使用 posts_count - 1，因为这是Discourse的标准逻辑
    const posts = this.topic.posts_count;
    if (typeof posts === "number" && posts > 0) {
      return Math.max(0, posts - 1);
    }
    
    // 回退到 reply_count
    const direct = this.topic.reply_count;
    if (typeof direct === "number") {
      return direct;
    }
    
    return 0;
  }


  get likeCount() {
    // 如果_tracked属性有值，优先使用
    if (this._likeCount !== null) {
      return this._likeCount;
    }
    
    // 使用新的op_like_count字段
    return this.topic.op_like_count || 0;
  }

  get isLiked() {
    // 如果_tracked属性有值，优先使用
    if (this._isLiked !== null) {
      return this._isLiked;
    }
    
    // 使用新的op_liked字段
    return !!this.topic.op_liked;
  }

  get canLike() {
    // 使用新的op_can_like字段
    return !!this.topic.op_can_like;
  }

  get isBookmarked() {
    this._forceUpdate;
    return !!this.topic.bookmarked;
  }

  get cannotBookmark() {
    return !this.currentUser || !this.topic.first_post_id;
  }

  get allowInvitesForShare() {
    return (
      !!this.currentUser?.can_invite_to_forum &&
      !!this.topic.details?.can_invite_to_topic
    );
  }

  @action
  async handleShareClick(event) {
    event.preventDefault();
    event.stopPropagation();

    const topic = this.topic;
    const shareUrl = topic.shareUrl;
    if (!shareUrl) {
      return;
    }

    try {
      await nativeShare(this.capabilities, {
        url: getAbsoluteURL(shareUrl),
      });
    } catch {
      this.modal.show(ShareTopicModal, {
        model: {
          category: topic.category,
          topic,
          allowInvites: this.allowInvitesForShare,
        },
      });
    }
  }

  @action
  async handleBookmarkClick(event) {
    event.preventDefault();
    event.stopPropagation();

    if (this.cannotBookmark) {
      return;
    }

    const postId = this.topic.first_post_id;

    try {
      if (this.isBookmarked) {
        const data = await ajax(`/posts/${postId}/bookmark.json`, {
          type: "DELETE",
        });
        const bookmarked = data.topic_bookmarked === true;
        this.topic.set("bookmarked", bookmarked);
        this.topic.notifyPropertyChange("bookmarked");
        this._forceUpdate++;
      } else {
        await ajax("/bookmarks.json", {
          type: "POST",
          data: {
            bookmarkable_type: "Post",
            bookmarkable_id: postId,
          },
        });
        this.topic.set("bookmarked", true);
        this.topic.notifyPropertyChange("bookmarked");
        this._forceUpdate++;
      }
    } catch (error) {
      popupAjaxError.call(this, error);
    }
  }

  @action
  async handleLikeClick(event) {
    event.preventDefault();
    event.stopPropagation();
    
    // 检查是否可以点赞
    if (!this.canLike) {
      return;
    }
    
    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
      const postId = this.topic.first_post_id;
      
      if (!postId) {
        return;
      }
      
      if (this.isLiked) {
        // 取消点赞
        const response = await fetch(`/post_actions/${postId}`, {
          method: 'DELETE',
          headers: {
            'accept': '*/*',
            'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'x-csrf-token': csrfToken,
            'x-requested-with': 'XMLHttpRequest'
          },
          body: 'post_action_type_id=2',
          mode: 'cors',
          credentials: 'include'
        });
        
        if (response.ok) {
          const data = await response.json();
          this.updateLikeStateFromResponse(data);
        }
      } else {
        // 点赞
        const response = await fetch('/post_actions', {
          method: 'POST',
          headers: {
            'accept': '*/*',
            'content-type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'x-csrf-token': csrfToken,
            'x-requested-with': 'XMLHttpRequest'
          },
          body: `id=${postId}&post_action_type_id=2&flag_topic=false`,
          mode: 'cors',
          credentials: 'include'
        });
        
        if (response.ok) {
          const data = await response.json();
          this.updateLikeStateFromResponse(data);
        }
      }
    } catch (error) {
      console.error('点赞操作失败:', error);
    }
  }

  updateLikeStateFromResponse(responseData) {
    // 从API响应中获取最新的点赞状态
    const likeAction = responseData.actions_summary?.find(action => action.id === 2);
    
    if (likeAction) {
      // 判断是否已点赞：如果有acted字段且为true，说明已点赞；否则未点赞
      const isLiked = likeAction.acted === true;
      const likeCount = likeAction.count || 0;
      
      // 更新新的字段
      this.topic.set('op_liked', isLiked);
      this.topic.set('op_like_count', likeCount);
      
      // 强制触发重新计算
      this.topic.notifyPropertyChange('op_liked');
      this.topic.notifyPropertyChange('op_like_count');
      
      // 更新tracked属性
      this._isLiked = isLiked;
      this._likeCount = likeCount;
      
      // 强制重新渲染组件
      this._forceUpdate++;
    }
  }

  updateLikeState(liked) {
    // 更新新的字段
    this.topic.set('op_liked', liked);
    this.topic.set('op_like_count', Math.max(0, (this.topic.op_like_count || 0) + (liked ? 1 : -1)));
    
    // 强制触发重新计算
    this.topic.notifyPropertyChange('op_liked');
    this.topic.notifyPropertyChange('op_like_count');
    
    // 更新tracked属性
    this._isLiked = liked;
    this._likeCount = this.topic.op_like_count;
    
    // 强制重新渲染组件
    this._forceUpdate++;
  }

  <template>
    {{#if this.topicThumbnails.displayFeed}}
      {{! 信息流模式 - 完整的社交媒体风格布局 }}
      <a href={{this.url}} class="topic-feed-item">
        {{! 用户信息头部；头像+用户名跳转 /ibomy/u/:username（不可嵌套 a，故用 role=link + 点击） }}
        <div class="topic-user-header">
          <div class="topic-user-header__left">
            <div
              class={{this.authorProfileWrapperClass}}
              role={{if this.authorHasIbomyProfile "link"}}
              tabindex={{if this.authorHasIbomyProfile "0"}}
              {{on "click" this.handleAuthorProfileClick}}
              {{on "keydown" this.handleAuthorProfileKeydown}}
            >
              <div class="user-avatar">
                {{#if this.avatarUrl}}
                  <img src={{this.avatarUrl}} alt={{this.userName}} />
                {{else}}
                  <div class="avatar-placeholder">
                    {{this.avatarInitials}}
                  </div>
                {{/if}}
              </div>
              <div class="user-info">
                <div class="user-name">
                  <span class="user-link">{{this.userName}}</span>
                </div>
                <div class="post-time">{{this.postTimeFormatted}}</div>
                {{#if this.userTitle}}
                  <div class="user-title">{{this.userTitle}}</div>
                {{/if}}
              </div>
            </div>
          </div>
          <div class="post-actions">
            <button class="action-button" title="更多选项">
              {{dIcon "ellipsis-h"}}
            </button>
          </div>
        </div>

        {{! 主题内容 }}
        <div class="topic-content">
          <div class="topic-title">
            <span class="title">{{this.topic.title}}</span>
          </div>
          {{#if this.topic.excerpt}}
            <span class="topic-excerpt">{{this.topic.excerpt}}</span>
          {{/if}}
          {{! 图片/视频展示 }}
          {{#if this.images.length}}
            <div class={{concatClass "topic-images" this.imageLayoutClass}} aria-label={{this.topic.title}}>
              {{#each this.images as |imageUrl index|}}
                <div class="image-container">
                  <img src={{imageUrl}} alt="主题图片" loading="lazy" />
                  {{#if this.isVideo}}
                    <div class="video-placeholder-overlay">
                      <svg class="fa d-icon d-icon-play svg-icon svg-string" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">
                        <use href="#play"></use>
                      </svg>
                    </div>
                  {{/if}}
                </div>
              {{/each}}
              {{#if this.showImageCount}}
                <div class="images-total-badge">
                  {{this.totalImageCount}}张
                </div>
              {{/if}}
            </div>
          {{/if}}
        </div>
        
        {{! 底部统计信息 }}
        <div class="topic-footer">
          <div class="topic-tags">
            {{#each this.normalizedTags as |tag|}}
              <a
                href={{this.tagHref tag}}
                data-tag-name="{{tag.name}}"
                class="discourse-tag"
              >{{tag.name}}</a>
            {{/each}}
          </div>
          <div class="topic-stats">
            <a href={{this.lastPostUrl}} class="stat" aria-label="查看回复">
              {{dIcon "comment"}}
              <span class="number">{{this.replyCount}}</span>
            </a>
            {{#if this.canLike}}
              <button 
                class="stat stat-like {{if this.isLiked 'liked'}}" 
                {{on "click" this.handleLikeClick}} 
                aria-label="{{if this.isLiked '取消点赞' '点赞'}}"
                title="{{if this.isLiked '点击取消点赞' '点击点赞'}}"
              >
                {{dIcon "heart"}}
                <span class="number">{{this.likeCount}}</span>
              </button>
            {{else}}
              <div class="stat stat-like disabled {{if this.isLiked 'liked'}}"
               {{on "click" this.handleLikeClick}} 
                aria-label="无法操作" title="无法进行点赞操作">
                {{dIcon "heart"}}
                <span class="number">{{this.likeCount}}</span>
              </div>
            {{/if}}
            <button
              type="button"
              class={{concatClass "stat" "stat-bookmark" (if this.isBookmarked "is-bookmarked")}}
              disabled={{this.cannotBookmark}}
              aria-label={{if this.isBookmarked "取消收藏" "加入收藏"}}
              title={{if
                this.cannotBookmark
                "登录后可收藏"
                (if this.isBookmarked "点击取消收藏" "点击加入收藏")
              }}
              {{on "click" this.handleBookmarkClick}}
            >
              {{dIcon "star"}}
            </button>
            <button
              type="button"
              class="stat stat-share"
              title={{i18n "topic.share.help"}}
              aria-label={{i18n "topic.share.help"}}
              {{on "click" this.handleShareClick}}
            >
              {{dIcon "d-topic-share"}}
            </button>
            <a href={{this.url}} class="stat stat-views" aria-label="查看浏览">
              {{dIcon "eye"}}
              <span class="number">{{this.topic.views}}</span>
            </a>
          </div>
        </div>
      </a>
    {{else}}
      {{! List模式的简化布局 }}
      {{#if this.topicThumbnails.displayList}}
        <div class="topic-list-simple">
          <div class="topic-content">
            <div class="topic-title">
              <a href={{this.url}} class="title-link">{{this.topic.title}}</a>
            </div>
            <div class="topic-meta">
              <span class="post-time">{{this.postTimeFormatted}}</span>
            </div>
          </div>
          {{#if this.hasThumbnail}}
            <div class="topic-thumbnail">
              <a href={{this.url}} aria-label={{this.topic.title}}>
                <img
                  src={{this.fallbackSrc}}
                  srcset={{this.srcSet}}
                  width={{this.width}}
                  height={{this.height}}
                  loading="lazy"
                  alt="主题缩略图"
                />
              </a>
            </div>
          {{/if}}
        </div>
      {{else}}
        {{! 其他模式的原有布局 }}
        <div
          class={{concatClass
            "topic-list-thumbnail"
            (if this.hasThumbnail "has-thumbnail" "no-thumbnail")
          }}
        >
          <a href={{this.url}} aria-label={{this.topic.title}}>
            {{#if this.hasThumbnail}}
              <img
                class="background-thumbnail"
                src={{this.fallbackSrc}}
                srcset={{this.srcSet}}
                width={{this.width}}
                height={{this.height}}
                loading="lazy"
              />
              <img
                class="main-thumbnail"
                src={{this.fallbackSrc}}
                srcset={{this.srcSet}}
                width={{this.width}}
                height={{this.height}}
                loading="lazy"
              />
            {{else}}
              <div class="thumbnail-placeholder">
                {{dIcon settings.placeholder_icon}}
              </div>
            {{/if}}
          </a>
        </div>
      {{/if}}

      {{#if this.topicThumbnails.showLikes}}
        <div class="topic-thumbnail-likes">
          {{dIcon "heart"}}
          <span class="number">
            {{this.topic.like_count}}
          </span>
        </div>
      {{/if}}

      {{#if this.topicThumbnails.displayBlogStyle}}
        <div class="topic-thumbnail-blog-data">
          <div class="topic-thumbnail-blog-data-views">
            {{dIcon "eye"}}
            <span class="number">
              {{this.topic.views}}
            </span>
          </div>
          <div class="topic-thumbnail-blog-data-likes">
            {{dIcon "heart"}}
            <span class="number">
              {{this.topic.like_count}}
            </span>
          </div>
          <div class="topic-thumbnail-blog-data-comments">
            {{dIcon "comment"}}
            <span class="number">
              {{this.topic.reply_count}}
            </span>
          </div>
          <button
            type="button"
            class="topic-thumbnail-blog-data-share"
            title={{i18n "topic.share.help"}}
            aria-label={{i18n "topic.share.help"}}
            {{on "click" this.handleShareClick}}
          >
            {{dIcon "d-topic-share"}}
          </button>
          <div
            class={{concatClass
              "topic-thumbnail-blog-data-activity"
              "activity"
              (coldAgeClass
                this.topic.createdAt startDate=this.topic.bumpedAt class=""
              )
            }}
            title={{this.topic.bumpedAtTitle}}
          >
            <a class="post-activity" href={{this.topic.lastPostUrl}}>
              {{~formatDate this.topic.bumpedAt format="tiny" noTitle="true"~}}
            </a>
          </div>
        </div>
      {{/if}}
    {{/if}}
  </template>
}
