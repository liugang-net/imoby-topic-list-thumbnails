import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("0.8", (api) => {
  // 图标替换配置
  api.replaceIcon("d-topic-share", "share-nodes");
  api.replaceIcon("d-post-share", "share-nodes");
  api.replaceIcon("far-pen-to-square", "plus");
  // api.replaceIcon("chevron-down", "far-file-lines");
});

