# 实现背景模糊效果

## Parent

#1

## What to build

全屏窗口背景从纯色改为 `NSVisualEffectView` 模糊背景，视觉效果接近原生 Launchpad。

## Acceptance criteria

- [ ] 使用 `NSVisualEffectView`，material = `.fullScreenUI`
- [ ] blendingMode = `.behindWindow`
- [ ] state = `.active`
- [ ] 能看到桌面壁纸透过模糊背景

## Blocked by

- #3
