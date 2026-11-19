# 接受 macOS 26 兼容性风险：必要时可引入私有 API

macOS 26 (Tahoe) 是新系统，SwiftUI 的 `.fullScreen`、`NSVisualEffectView` 等公开 API 在新系统上的行为可能异常。如果公开 API 无法实现原生 Launchpad 效果，接受引入私有 API 的方案。

理由：
- 项目目标是"还原原生体验"，如果公开 API 做不到，就必须用私有 API
- 项目不上 Mac App Store（ADR-0014），私有 API 不会导致审核问题
- 私有 API 的风险是"未来 macOS 版本可能失效"，但这是一个个人项目，失效时再修

后果：
- 需要在代码中明确标记哪些是私有 API 调用，以便未来维护
- 每次 macOS 大版本更新后需要验证功能是否正常
