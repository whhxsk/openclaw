# douyin-cdp

用 Chromium 远程调试法下载抖音视频（OpenClaw 专用技能）。

## 触发方式

用户发送抖音链接（`https://v.douyin.com/...` 或 `https://www.douyin.com/video/...`）时自动识别并执行。

## 核心流程

1. 杀掉现有 chromium 进程
2. 用 snap chromium 打开目标 URL（开启 `--remote-debugging-port=9222`）
3. 等待页面加载
4. 通过 CDP (Playwright) 从 `video.currentSrc` 提取真实直链
5. curl 下载到 `/home/xiwang/.openclaw/media/`
6. 用 feishu message 工具发送给用户

## 环境要求

- snap 版 chromium 已安装
- node + playwright 已安装
- 工作目录：`/home/xiwang/.openclaw/workspace`

## 使用限制

- 每次下载一个视频
- 不支持批量
- 不支持需要付费/独播登录的视频
