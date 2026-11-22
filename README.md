# MacBook Launchpad

在 macOS 26+ 上恢复经典 Launchpad 体验的原生 SwiftUI 应用：全屏应用分页网格、实时搜索、点击或回车启动应用，并支持安全地把应用移到废纸篓。

界面使用带桌面模糊的深墨蓝背景、冷青翻页舞台和深钴蓝退出带，仅以薄荷青点亮当前页与输入光标；打开和关闭采用短促过渡，鼠标翻页实时跟手并以 `400ms` 无弹跳曲线落位，同时遵循系统“减弱动态效果”设置。

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

- 启动后立即覆盖当前显示器，搜索框已获得焦点；有应用清单缓存时首帧直接显示缓存内容
- 使用触控板水平滑动、在应用区按住鼠标拖动、空搜索时的 `←` / `→` 键或底部分页圆点切换页面
- 普通页面按“从上到下、从左到右”的列优先顺序排列；搜索页保持居中
- 输入应用名的一部分即可实时过滤（大小写不敏感的子串匹配）
- 点击应用项或按 `Enter` 启动第一个匹配应用
- 右键可删除的应用项并选择“移到废纸篓”；应用必须已退出
- 按 `Esc` 清空搜索；搜索为空时再按 `Esc` 退出
- 窗口四周的深钴蓝玻璃区域是退出带；点击其中的空白处可退出。搜索为空时按 `Esc`，或随时按 `Cmd+Q` 退出。搜索框、应用项和分页圆点仍正常响应
- 在中央翻页舞台内按住鼠标左右拖动；页面会跟随指针，越过第一页或最后一页时有轻微阻尼回弹

应用图标按当前页异步加载；应用清单会缓存在本地，启动时先展示上次扫描结果，再在后台扫描并按差异更新。图标仍不缓存。

## 分发

本地构建使用 "Sign to Run Locally"（ad-hoc 签名），Release 配置已开启 Hardened Runtime。发布到 GitHub Releases 前需要：

1. 使用 Apple Developer Program 的 Developer ID Application 证书签名，并设置 `DEVELOPMENT_TEAM`
2. 使用 `xcrun notarytool submit` 完成公证并 `xcrun stapler staple`
3. 将 `.app` 打包为 `.dmg` 上传到 GitHub Releases

## 文档

- 规格与任务：GitHub Issues
- 领域术语：`GLOSSARY.md`
- 架构决策：`docs/adr/`
