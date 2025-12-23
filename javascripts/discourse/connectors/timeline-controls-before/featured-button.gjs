import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import concatClass from "discourse/helpers/concat-class";
import dIcon from "discourse/helpers/d-icon";
import I18n from "I18n";

export default class FeaturedButton extends Component {
  @service currentUser;
  @service site;

  @tracked featuredLocal = null;
  @tracked isLoading = false;

  get canSetFeatured() {
    // 从 outletArgs.model 获取 topic
    const topic = this.args.outletArgs?.model;
    return topic?.can_set_featured || false;
  }

  // 使用 shouldRender 控制 connector 是否渲染
  get shouldRender() {
    return this.canSetFeatured;
  }

  get topic() {
    // 从 outletArgs.model 获取 topic
    return this.args.outletArgs?.model;
  }

  get isFeatured() {
    if (this.featuredLocal !== null) {
      return this.featuredLocal;
    }
    return !!this.topic?.featured;
  }

  get buttonText() {
    return this.isFeatured ? "取消精选" : "设为精选";
  }

  get buttonClass() {
    // 对齐旁边的管理按钮风格：btn btn-default btn-icon no-text
    // 精选时仅改变图标颜色，不改变按钮背景
    return this.isFeatured
      ? "btn-default btn-icon no-text is-featured"
      : "btn-default btn-icon no-text";
  }

  get buttonIcon() {
    // 使用统一的证书图标
    return "certificate";
  }

  @action
  async toggleFeatured() {
    if (!this.canSetFeatured) return;

    const topic = this.topic;
    const isCurrentlyFeatured = this.isFeatured;
    const endpoint = isCurrentlyFeatured ? "unset-featured" : "set-featured";

    try {
      this.isLoading = true;
      const response = await fetch(`/api/ibomy/t/${topic.id}/${endpoint}.json`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        credentials: 'include'
      });

      let result = {};
      try {
        result = await response.json();
      } catch (_) {}

      // 兼容 Discourse 官方错误结构
      const firstError = Array.isArray(result?.errors) && result.errors.length > 0 ? result.errors[0] : null;
      if (!response.ok || firstError) {
        throw new Error(firstError || result?.error || result?.message || '操作失败');
      }

      // 成功：根据返回值更新，若未提供则回退为取反
      const next = typeof result?.featured === 'boolean' ? result.featured : !isCurrentlyFeatured;
      // 本地优先，确保UI即时更新
      this.featuredLocal = next;
      // 同步到topic（若支持）
      if (typeof topic?.set === 'function') {
        topic.set("featured", next);
      } else if (topic) {
        topic.featured = next;
      }

      // 尝试触发一次父级 rerender（如果外层传入了回调）
      if (typeof this.args.onToggle === 'function') {
        try {
          this.args.onToggle(next);
        } catch (_) {}
      }
    } catch (error) {
      console.error('Error updating featured status:', error);
      popupAjaxError(error);
    }
    finally {
      this.isLoading = false;
    }
  }

  <template>
    <button 
      class={{concatClass "btn" this.buttonClass "featured-button"}}
      {{on "click" this.toggleFeatured}}
      title={{this.buttonText}}
      disabled={{this.isLoading}}
    >
      {{dIcon this.buttonIcon}}
    </button>
  </template>
}




