# MacBook Launchpad

在 macOS 26+ 上恢复经典 Launchpad 体验的原生 SwiftUI 应用：全屏应用分页网格、实时搜索、点击或回车启动应用，并支持在访达中显示或安全地把应用移到废纸篓。

界面采用清透晨雾磨砂玻璃设计（默认“清透浅色”，支持通过右上角按钮切换“静谧深色”与“跟随系统”）：全屏桌面模糊叠加柔和大气晕染与轻盈悬浮玻璃翻页舞台，顶部悬浮胶囊搜索框实时展示匹配数量与一键清空按钮，底部胶囊分页器支持平滑形变指示，鼠标悬停应用项呈轻盈浮起与玻璃高光反馈；打开和关闭采用短促顺滑过渡，鼠标翻页实时跟手并以 `400ms` 无弹跳曲线落位，同时遵循系统“减弱动态效果”设置。

## 环境要求

- macOS 26 或更高版本
- Xcode 16+（需要 macOS 26 SDK）

## 构建与运行

```sh
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Launchpad.app
```

## 测试

```sh
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad -configuration Debug -derivedDataPath build build-for-testing
xcrun xctest build/Build/Products/Debug/LaunchpadTests.xctest
```

## 使用

- 启动后立即覆盖当前显示器并预热首屏图标，搜索框自动获得焦点；有应用清单缓存时首帧直接显示缓存内容
- 点击右上角外观按钮可在“清透浅色 / 静谧深色 / 跟随系统”间切换
- 使用触控板水平滑动、在翻页舞台按住鼠标拖动、空搜索时的 `←` / `→` 键或底部分页胶囊切换页面
- 普通页面按“从上到下、从左到右”的列优先顺序排列；搜索页保持居中，首个匹配项带有柔和强调边框
- 支持智能模糊搜索：包含前缀、子串、首字母缩写/驼峰（如 `vsc`、`gc`）、有序跳字（如 `sfr`）、轻微拼写容错（如 `chorme`）、中文拼音全拼/首字母（如 `wx`、`bilibili`），以及 `.app` 原文件名与本地化别名匹配；右侧显示匹配总数与一键清空按钮
- 完整扫描 `/Applications`、`~/Applications`、`/System/Applications` 与 `/System/Cryptexes/App/System/Applications`（包括 Safari 等带隐藏标志的符号链接、符号链接子目录及 Finder 替身）
- 点击应用项或按 `Enter` 启动第一个匹配应用
- 右键任意应用项可“在访达中显示”；对于可删除应用可进一步选择“移到废纸篓”（应用必须已退出）
- 按 `Esc` 清空搜索；搜索为空时再按 `Esc` 退出；点击四周退出带空白区域或按 `Cmd+Q` 也可随时退出

## 性能设计

- **按项独立观测（O(1) 重绘）**：`AppIconStore` 通过每应用独立的 `@Observable` `AppIconSlot` 驱动图标显示，单枚图标加载完成不会触发网格或外围视图重算
- **预光栅化磁盘缩略图缓存**：图标在后台按屏幕缩放比预光栅化为 Retina `CGImage`（`96pt × scale`）并缓存为 PNG（基于路径、像素尺寸与 Bundle 修改时间哈希校验），复用时零 LaunchServices XPC 与主线程解码开销
- **有界并发与启动预热**：图标加载池限制最大并发数为 6（当前页优先，相邻页后台预取），并在窗口创建阶段提前预热首屏缓存应用图标
- **并行扫描与局部状态隔离**：`FileSystemAppScanner` 并行解析应用包元数据；120Hz 横向拖拽状态隔离在分页网格视图内部，避免拖动期间触发背景与搜索栏重绘

## 分发

本地构建使用 "Sign to Run Locally"（ad-hoc 签名），Release 配置已开启 Hardened Runtime。发布到 GitHub Releases 前需要：

1. 使用 Apple Developer Program 的 Developer ID Application 证书签名，并设置 `DEVELOPMENT_TEAM`
2. 使用 `xcrun notarytool submit` 完成公证并 `xcrun stapler staple`
3. 将 `.app` 打包为 `.dmg` 上传到 GitHub Releases

## 文档

- 规格与任务：GitHub Issues
- 领域术语：`GLOSSARY.md`
- 架构决策：`docs/adr/`
