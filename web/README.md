# MyShell Web 前端

`web/src/` 保存原生 HTML、CSS 和 JavaScript；`web/build.mjs` 将前端及固定
版本的浏览器依赖复制到 `web/dist/`，再由 Go 的 `embed` 打包。

```bash
npm ci
npm run build
```

依赖只有：

- `@xterm/xterm` 与 `@xterm/addon-fit`：终端渲染及尺寸适配
- `prismjs`：指定语言的代码高亮

不使用 CDN，生产容器不包含 Node.js 或 `node_modules`。

## 页面结构

- 登录/首次初始化页面
- 连接列表、搜索和加密凭据编辑
- 多标签终端、代码预览和状态栏
- 外观、定时检查与 Git 备份设置
- Git 备份列表及二次确认恢复

视觉基准为
[`docs/concepts/midnight-graphite-workspace.png`](docs/concepts/midnight-graphite-workspace.png)。
五套主题都使用相同布局和交互。桌面浏览器是主要目标，宽度小于 680px 时连接
栏变为抽屉。

修改 UI 后必须验证登录、连接编辑、主题切换、终端输入、窗口缩放、移动布局、
键盘焦点和浏览器控制台。
