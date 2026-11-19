# 使用原生 SwiftUI，不采用跨平台方案

技术栈选择 SwiftUI + Swift，仅支持 macOS 26+，不采用 Electron / Tauri / Web 等跨平台方案。

理由：
- **体积约束**：用户明确要求"体积小巧"。原生 SwiftUI 编译产物 < 5MB；Electron 起步 80MB，Tauri 也要捆绑 WebView（~10MB）且毛玻璃效果需要 CSS hack
- **原生体验约束**：用户要求"还原原生体验"。SwiftUI 直接使用 `NSVisualEffectView`、系统动画曲线、SF 字体，还原度远高于 Web 技术
- **平台约束**：仅 macOS 26+。老版本 macOS 自带 Launchpad，无需本应用；跨平台对单个 macOS 工具是无谓的复杂度

后果：
- 代码无法迁移到 Windows/Linux（用户已明确不需要）
- 需要 macOS 26 SDK 和 Xcode 16+ 才能构建
