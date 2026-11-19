# 创建 Xcode 项目骨架

## Parent

#1

## What to build

一个可编译运行的空 SwiftUI 应用，包含 `LaunchpadApp` 入口、`ContentView` 占位视图、`App` 数据模型。用户双击 `.app` 能看到一个空白窗口。

## Acceptance criteria

- [ ] 存在 Xcode 项目文件，scheme 名为 `Launchpad`
- [ ] `LaunchpadApp.swift` 包含 `@main` 入口
- [ ] `ContentView.swift` 显示占位文本（如 "Hello Launchpad"）
- [ ] `App.swift` 定义 `App` 结构体（name, icon, url）
- [ ] `xcodebuild -scheme Launchpad -configuration Debug build` 成功
- [ ] 运行 `.app` 显示空白窗口

## Blocked by

None (can start immediately)
