# MacBook Launchpad

在 macOS 26+ 上恢复经典 Launchpad 体验的原生 SwiftUI 应用：全屏应用分页网格、实时搜索、点击或回车启动应用，并支持安全地把应用移到废纸篓。

界面使用带桌面模糊的深色玻璃背景；打开、关闭和程序化翻页采用短促的 ease-out 过渡，并遵循系统“减弱动态效果”设置。

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
xcodebuild -project Launchpad.xcodeproj -scheme Launchpad -configuration Debug -derivedDataPath build test
```

## 使用

- 启动后立即覆盖当前显示器，搜索框已获得焦点
- 使用触控板水平滑动、在应用区按住鼠标拖动、空搜索时的 `←` / `→` 键或底部分页圆点切换页面
- 普通页面按“从上到下、从左到右”的列优先顺序排列；搜索页保持居中
- 输入应用名的一部分即可实时过滤（大小写不敏感的子串匹配）
- 点击应用项或按 `Enter` 启动第一个匹配应用
- 右键可删除的应用项并选择“移到废纸篓”；应用必须已退出
- 按 `Esc` 清空搜索；搜索为空时再按 `Esc` 退出
- 点击顶部搜索区（输入框之外）的空白处，或按 `Cmd+Q` 退出
- 点击下方应用区的空白处不会退出，可继续拖动翻页

应用图标按当前页异步加载；启动台不会缓存应用清单或图标，每次唤起都会重新扫描。

## 分发

本地构建使用 "Sign to Run Locally"（ad-hoc 签名），Release 配置已开启 Hardened Runtime。发布到 GitHub Releases 前需要：

1. 使用 Apple Developer Program 的 Developer ID Application 证书签名，并设置 `DEVELOPMENT_TEAM`
2. 使用 `xcrun notarytool submit` 完成公证并 `xcrun stapler staple`
3. 将 `.app` 打包为 `.dmg` 上传到 GitHub Releases

## 文档

- 规格与任务：GitHub Issues
- 领域术语：`GLOSSARY.md`
- 架构决策：`docs/adr/`
