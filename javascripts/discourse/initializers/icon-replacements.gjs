import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("0.8", (api) => {
  // 图标替换配置
  api.replaceIcon("d-topic-share", "share");
  api.replaceIcon("d-post-share", "share");
  // api.replaceIcon("far-pen-to-square", "plus");
  api.replaceIcon("bookmark", "star");
  api.replaceIcon("far-bookmark", "far-star");

  // api.replaceIcon("chevron-down", "far-file-lines");
});

