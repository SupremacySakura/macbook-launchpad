# 分发方式：GitHub Releases + 开发者 ID 签名 + 公证，不上 Mac App Store

V1 通过 GitHub Releases 分发公证过的 `.dmg` 文件。用户下载后拖入 `/Applications` 安装。

需要：
- Apple Developer Program 账号（$99/年）
- 开发者 ID 证书（Developer ID Application）
- 公证（Notarization）：`xcrun notarytool submit`

明确**不做**：
- ❌ Mac App Store（MAS 沙盒可能阻止扫描 `/Applications` 目录）
- ❌ Homebrew Cask（V2 再考虑）
- ❌ Sparkle 自动更新框架（V1 用户手动下载新版本）

理由：
- MAS 的沙盒限制可能要求用户手动授权"访问 /Applications"，体验差
- GitHub Releases 免费、无需审核、发布快
- 公证是 macOS 10.15+ 的强制要求，不做用户会看到"无法验证开发者"警告

后果：
- 需要每年续费 Apple Developer Program
- 用户更新需要手动下载（V2 可加 Sparkle）
