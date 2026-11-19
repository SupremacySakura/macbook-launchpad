# MacBook Launchpad

在 macOS 26+ 上恢复经典 Launchpad 体验的原生 SwiftUI 应用：全屏应用网格、实时搜索、点击或回车启动应用。

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

- 启动后自动进入全屏，搜索框已获得焦点
- 输入应用名的一部分即可实时过滤（大小写不敏感的子串匹配）
- 点击应用项或按 `Enter` 启动第一个匹配应用
- 按 `Esc` 清空搜索；搜索为空时再按 `Esc` 退出
- 点击搜索框与应用项之外的空白区域，或按 `Cmd+Q` 退出

## 分发

本地构建使用 "Sign to Run Locally"（ad-hoc 签名），Release 配置已开启 Hardened Runtime。发布到 GitHub Releases 前需要：

1. 使用 Apple Developer Program 的 Developer ID Application 证书签名，并设置 `DEVELOPMENT_TEAM`
2. 使用 `xcrun notarytool submit` 完成公证并 `xcrun stapler staple`
3. 将 `.app` 打包为 `.dmg` 上传到 GitHub Releases

## 文档

- 规格与任务：GitHub Issues
- 领域术语：`GLOSSARY.md`
- 架构决策：`docs/adr/`
