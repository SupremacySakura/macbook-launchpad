# 实现点击启动应用

## Parent

#1

## What to build

点击网格中的任意应用图标，对应应用启动，启动台退出。

## Acceptance criteria

- [ ] 点击应用项使用 `NSWorkspace.open(url)` 启动应用
- [ ] 启动成功后启动台立即退出
- [ ] 启动失败静默处理（不显示错误提示）

## Blocked by

- #6
