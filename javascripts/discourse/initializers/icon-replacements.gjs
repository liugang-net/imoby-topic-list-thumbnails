import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("0.8", (api) => {
  // 图标替换配置
  api.replaceIcon("d-topic-share", "ibomy-share");
  api.replaceIcon("d-post-share", "ibomy-share");
  api.replaceIcon("share", "ibomy-share");

  api.replaceIcon("reply", "ibomy-comment");
  // api.replaceIcon("far-pen-to-square", "plus");
  api.replaceIcon("bookmark", "ibomy-bookmark");
  api.replaceIcon("far-bookmark", "ibomy-bookmark");

  // api.replaceIcon("chevron-down", "far-file-lines");
});

