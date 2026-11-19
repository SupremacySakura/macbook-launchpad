# V1 不支持全局快捷键唤起

V1 中启动台是一个普通 macOS 应用，用户从 Dock / Spotlight / `/Applications` 双击打开。不支持 `F4`、自定义热键等全局唤起方式，也不做后台驻留。

理由：
- 全局热键需要 `Carbon RegisterEventHotKey` 或 `MASShortcut` 框架，涉及辅助功能权限申请，复杂度高
- 全局热键的价值在"高频唤起"，但 V1 还没有验证用户是否真的会高频使用
- 用户已有替代方案：把应用固定在 Dock、用 Spotlight 搜索"Launchpad"

后果：
- 如果 V1 用户反馈"打开太慢"，V2 优先做全局热键
- 如果做全局热键，需要解决与系统 `F4` Launchpad 快捷键的冲突（macOS 26 上 `F4` 默认打开 App Library）
