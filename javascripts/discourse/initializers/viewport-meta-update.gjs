export default {
  name: "viewport-meta-update",
  after: "viewport-setup",
  initialize(container) {
    // 在 viewport-setup.js 之后修改 viewport meta 标签
    // 覆盖 viewport-setup.js 可能添加的额外属性，设置为用户要求的值
    const viewport = document.querySelector("meta[name=viewport]");
    if (viewport) {
      // 将 viewport 设置为用户要求的值：width=device-width, initial-scale=1, viewport-fit=cover
      viewport.setAttribute("content", "width=device-width, initial-scale=1, viewport-fit=cover");
    }
  },
};

