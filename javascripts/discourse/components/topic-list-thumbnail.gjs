import Component from "@glimmer/component";
import { service } from "@ember/service";
import coldAgeClass from "discourse/helpers/cold-age-class";
import concatClass from "discourse/helpers/concat-class";
import dIcon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";

export default class TopicListThumbnail extends Component {
  @service topicThumbnails;

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
      : this.topic.get("lastUnreadUrl");
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

  get images() {
    // 优先使用新的images数组，如果没有则使用thumbnails
    if (this.topic.images && this.topic.images.length > 0) {
      return this.topic.images
        .filter(img => img.url)
        .slice(0, 3)
        .map(img => img.url);
    }
    
    // 回退到原来的thumbnails
    if (!this.hasThumbnail) return [];
    
    const imageUrls = this.topic.thumbnails
      .filter(t => t.url)
      .slice(0, 3)
      .map(t => t.url);
    
    return imageUrls;
  }

  get imageCount() {
    return this.images.length;
  }

  get totalImageCount() {
    // 获取实际的总图片数量
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
    if (this.imageCount === 1) return "single-image";
    if (this.imageCount === 2) return "multiple-images two-images";
    if (this.imageCount === 3) return "multiple-images three-images";
    return "";
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

  tagHref(tag) {
    if (!tag) {
      return "/tags";
    }
    // Discourse 标签列表标准路径为 /tags/<tag>
    return `/tags/${encodeURIComponent(tag)}`;
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

  <template>
    {{#if this.topicThumbnails.displayFeed}}
      {{! 信息流模式 - 完整的社交媒体风格布局 }}
      <div class="topic-feed-item">
        {{! 用户信息头部 }}
        <div class="topic-user-header">
          <div class="user-avatar">
            <a href={{this.url}} aria-label={{this.topic.title}}>
              {{#if this.avatarUrl}}
                <img src={{this.avatarUrl}} alt={{this.userName}} />
              {{else}}
                <div class="avatar-placeholder">
                  {{this.avatarInitials}}
                </div>
              {{/if}}
            </a>
          </div>
          <div class="user-info">
            <div class="user-name">
              <a href={{this.url}} class="user-link">{{this.userName}}</a>
            </div>
            <div class="post-time">{{this.postTimeFormatted}}</div>
            {{#if this.userTitle}}
              <div class="user-title">{{this.userTitle}}</div>
            {{/if}}
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
            <a href={{this.url}} class="title">{{this.topic.title}}</a>
          </div>
          {{#if this.topic.excerpt}}
            <a href={{this.url}} class="topic-excerpt">{{this.topic.excerpt}}</a>
          {{/if}}
          {{! 图片展示 }}
          {{#if this.images.length}}
            <a href={{this.url}} class={{concatClass "topic-images" this.imageLayoutClass}} aria-label={{this.topic.title}}>
              {{#each this.images as |imageUrl index|}}
                <div class="image-container">
                  <img src={{imageUrl}} alt="主题图片" loading="lazy" />
                </div>
              {{/each}}
              {{#if this.showImageCount}}
                <div class="images-total-badge">
                  {{this.totalImageCount}}张
                </div>
              {{/if}}
            </a>
          {{/if}}
        </div>

        {{! 底部统计信息 }}
        <div class="topic-footer">
          <div class="topic-tags">
            {{#each this.topic.tags as |tag|}}
              <a href={{this.tagHref tag}} class="discourse-tag">{{tag}}</a>
            {{/each}}
          </div>
          <div class="topic-stats">
            <a href={{this.url}} class="stat" aria-label="查看回复">
              {{dIcon "comment"}}
              <span class="number">{{this.replyCount}}</span>
            </a>
            <a href={{this.url}} class="stat" aria-label="查看浏览">
              {{dIcon "eye"}}
              <span class="number">{{this.topic.views}}</span>
            </a>
          </div>
        </div>
      </div>
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
