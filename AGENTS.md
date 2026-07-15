# 仓库开发指南

## 项目定位

本仓库是一个 Discourse 主题组件，用于扩展主题列表缩略图、轮播、移动端导航及相关界面。修改时应优先使用 Discourse 官方主题 API、组件和插件出口，避免覆盖核心模板或依赖不稳定的 DOM 结构。

## 目录结构

- `javascripts/discourse/components/`：可复用的 Glimmer 组件。
- `javascripts/discourse/connectors/`：注入 Discourse 插件出口的界面功能。
- `javascripts/discourse/initializers/`：主题初始化逻辑。
- `javascripts/discourse/services/`：跨组件共享的状态与行为。
- `javascripts/discourse/lib/`：无界面依赖的工具逻辑。
- `common/common.scss`：桌面端与移动端共用样式。
- `mobile/mobile.scss`：仅移动端加载的样式。
- `locales/`：主题设置和界面文本的多语言翻译。
- `settings.yml`：可在 Discourse 后台配置的主题选项。
- `about.json`：主题组件元数据、兼容版本及序列化配置。

## 编码与命名规范

遵循 `@discourse/lint-configs`、Prettier 和 Stylelint 配置，使用两个空格缩进，单行尽量不超过 100 个字符。文件使用 kebab-case，例如 `topic-list-thumbnail.gjs`；JavaScript 变量使用 camelCase；SCSS 类名应表达功能，避免绑定易变化的页面层级。

新增用户可见文本或设置项时，先在 `locales/en.yml` 定义基准键，再同步维护 `locales/zh_CN.yml` 等相关语言文件。不要在组件中硬编码可翻译文本。

## 本地测试

修改完成后，使用 `discourse_theme upload .` 将当前主题组件上传到本地 Discourse 测试环境，再检查相关页面及移动端显示效果。

## 提交与合并请求

提交信息保持简短、聚焦，推荐使用 `feat:`、`fix:`、`style:` 等前缀，例如 `fix: 修复移动端轮播位置`。一个提交只处理一类变更。

合并请求需说明修改目的、影响页面及验证方式。涉及界面变化时提供桌面端和移动端截图；涉及主题设置时说明默认值及升级影响。避免混入无关格式化或大范围翻译变更。
