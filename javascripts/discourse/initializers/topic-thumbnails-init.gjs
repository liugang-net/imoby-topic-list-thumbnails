import { readOnly } from "@ember/object/computed";
import { service } from "@ember/service";
import { apiInitializer } from "discourse/lib/api";
import TopicListThumbnail from "../components/topic-list-thumbnail";
import ScrollingCategoryNav from "../components/scrolling-category-nav";

export default apiInitializer("0.8", (api) => {
  const ttService = api.container.lookup("service:topic-thumbnails");

  api.registerValueTransformer("topic-list-class", ({ value }) => {
    if (ttService.displayMinimalGrid) {
      value.push("topic-thumbnails-minimal");
    } else if (ttService.displayGrid) {
      value.push("topic-thumbnails-grid");
    } else if (ttService.displayList) {
      value.push("topic-thumbnails-list");
    } else if (ttService.displayMasonry) {
      value.push("topic-thumbnails-masonry");
    } else if (ttService.displayBlogStyle) {
      value.push("topic-thumbnails-blog-style-grid");
    } else if (ttService.displayFeed) {
      value.push("topic-thumbnails-feed");
    }
    return value;
  });

  api.registerValueTransformer("topic-list-columns", ({ value: columns }) => {
    if (ttService.enabledForRoute && !ttService.displayList) {
      columns.add(
        "thumbnail",
        { item: TopicListThumbnail },
        { before: "topic" }
      );
    }
    return columns;
  });

  api.renderInOutlet(
    "topic-list-before-link",
    <template>
      {{#if ttService.displayList}}
        <TopicListThumbnail @topic={{@outletArgs.topic}} />
      {{/if}}
    </template>
  );

  // 注册可滑动分类导航组件
  console.log("Navigation setting:", settings.show_scrolling_category_nav);
  if (settings.show_scrolling_category_nav) {
         // 使用 DOM 操作直接插入到页面
         let navigationInitialized = false;
         
         // 创建导航的函数
         function createNavigation() {
           const site = api.container.lookup('service:site');
           const categories = site.categories || [];
           
           // 过滤并排序分类
           const visibleCategories = categories
             .filter(cat => !cat.read_restricted && !cat.parent_category_id)
             .sort((a, b) => a.position - b.position);
           
           console.log("Available categories:", visibleCategories);
           
           // 构建导航HTML
           const currentPath = window.location.pathname;
           const isLatest = currentPath === '/latest' || currentPath === '/';
           
           let navItems = `<a href="/latest" class="nav-item ${isLatest ? 'active' : ''}">最新</a>`;
           visibleCategories.forEach(category => {
             // 处理空的slug，使用ID作为fallback
             const slug = category.slug || category.id.toString();
             const categoryPath = `/c/${slug}/${category.id}`;
             
             // 更灵活的匹配逻辑 - 专门处理Discourse的URL格式
             const isActive = currentPath === categoryPath || 
                             currentPath.startsWith(categoryPath + '/') ||
                             currentPath.includes(`/c/${category.id}`) ||
                             currentPath === `/c/${category.id}` ||
                             currentPath.match(new RegExp(`/c/[^/]*/${category.id}(/|$)`));
             
             navItems += `<a href="${categoryPath}" class="nav-item ${isActive ? 'active' : ''}">${category.name}</a>`;
           });
           
           return `
             <div class="scrolling-category-nav">
               <div class="nav-container">
                 <div class="nav-items">
                   ${navItems}
                 </div>
               </div>
             </div>
           `;
         }
         
         api.onPageChange(() => {
           const listControls = document.querySelector('.list-controls .container');
           const existingNav = document.querySelector('.scrolling-category-nav');
           
           // 如果导航已存在，只更新active状态
           if (existingNav) {
             updateActiveStates(existingNav);
             return;
           }
           
           // 如果导航不存在，创建它
           if (listControls) {
             const navHTML = createNavigation();
             const navContainer = document.createElement('div');
             navContainer.innerHTML = navHTML;
             listControls.insertBefore(navContainer.firstElementChild, listControls.firstChild);
             console.log("Navigation created");
           }
         });
         
         // 页面加载完成后也检查导航
         api.onPageChange(() => {
           // 延迟检查，确保DOM完全加载
           setTimeout(() => {
             const listControls = document.querySelector('.list-controls .container');
             const existingNav = document.querySelector('.scrolling-category-nav');
             
             if (listControls && !existingNav) {
               const navHTML = createNavigation();
               const navContainer = document.createElement('div');
               navContainer.innerHTML = navHTML;
               listControls.insertBefore(navContainer.firstElementChild, listControls.firstChild);
               console.log("Navigation created on delayed check");
             }
           }, 100);
         });
         
         // 更新active状态的辅助函数
         function updateActiveStates(navElement) {
           const currentPath = window.location.pathname;
           const navItems = navElement.querySelectorAll('.nav-item');
           
           navItems.forEach(item => {
             const href = item.getAttribute('href');
             const isLatest = href === '/latest' || href === '/';
             
             let isActive = false;
             if (isLatest) {
               isActive = currentPath === '/latest' || currentPath === '/';
             } else {
               // 解析分类路径
               const pathParts = href.split('/');
               const categoryId = pathParts[pathParts.length - 1];
               
               isActive = currentPath === href || 
                         currentPath.startsWith(href + '/') ||
                         currentPath.includes(`/c/${categoryId}`) ||
                         currentPath === `/c/${categoryId}` ||
                         currentPath.match(new RegExp(`/c/[^/]*/${categoryId}(/|$)`));
             }
             
             item.classList.toggle('active', isActive);
           });
         }
  }

  api.registerValueTransformer("topic-list-item-mobile-layout", ({ value }) => {
    if (ttService.enabledForRoute && !ttService.displayList) {
      // Force the desktop layout
      return false;
    }
    return value;
  });

  api.registerValueTransformer(
    "topic-list-item-class",
    ({ value, context: { index } }) => {
      if (ttService.displayMasonry) {
        value.push(`masonry-${index}`);
      }
      return value;
    }
  );

  const siteSettings = api.container.lookup("service:site-settings");
  if (settings.docs_thumbnail_mode !== "none" && siteSettings.docs_enabled) {
    api.modifyClass("component:docs-topic-list", {
      pluginId: "topic-thumbnails",
      topicThumbnailsService: service("topic-thumbnails"),
      classNameBindings: [
        "isMinimalGrid:topic-thumbnails-minimal",
        "isThumbnailGrid:topic-thumbnails-grid",
        "isThumbnailList:topic-thumbnails-list",
        "isMasonryList:topic-thumbnails-masonry",
        "isBlogStyleGrid:topic-thumbnails-blog-style-grid",
        "isFeedGrid:topic-thumbnails-feed",
      ],
      isMinimalGrid: readOnly("topicThumbnailsService.displayMinimalGrid"),
      isThumbnailGrid: readOnly("topicThumbnailsService.displayGrid"),
      isThumbnailList: readOnly("topicThumbnailsService.displayList"),
      isMasonryList: readOnly("topicThumbnailsService.displayMasonry"),
      isBlogStyleGrid: readOnly("topicThumbnailsService.displayBlogStyle"),
      isFeedGrid: readOnly("topicThumbnailsService.displayFeed"),
    });
  }
});
