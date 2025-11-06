import Component from "@glimmer/component";

export default class UserProfileStats extends Component {
  get totalFollowers() {
    return this.args.outletArgs?.model?.total_followers || 0;
  }

  get totalFollowing() {
    return this.args.outletArgs?.model?.total_following || 0;
  }

  get likesReceived() {
    return this.args.outletArgs?.model?.likes_received || 0;
  }

  get gamificationScore() {
    return this.args.outletArgs?.model?.gamification_score || 0;
  }

  <template>
    <div class="user-profile-stats">
      <div class="stat-item">
        <span class="stat-label">粉丝</span>
        <span class="stat-value">{{this.totalFollowers}}</span>
      </div>
      <div class="stat-item">
        <span class="stat-label">关注</span>
        <span class="stat-value">{{this.totalFollowing}}</span>
      </div>
      <div class="stat-item">
        <span class="stat-label">获赞</span>
        <span class="stat-value">{{this.likesReceived}}</span>
      </div>
      <div class="stat-item">
        <span class="stat-label">点数</span>
        <span class="stat-value">{{this.gamificationScore}}</span>
      </div>
    </div>
  </template>
}

