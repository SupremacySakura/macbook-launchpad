# 实现 AppScanner 协议和 FileSystemAppScanner

## Parent

#1

## What to build

`AppScanner` 协议 + `FileSystemAppScanner` 实现，能扫描 `/Applications` 并返回 `[App]` 数组（包含 name, icon, url）。命令行测试能打印找到的应用列表。

## Acceptance criteria

- [ ] `AppScanner` 协议定义 `scan() -> [App]` 方法
- [ ] `FileSystemAppScanner` 实现扫描 `/Applications`、`~/Applications`、`/System/Applications`
- [ ] 返回的 `App` 包含 name（应用名）、icon（NSImage）、url（应用路径）
- [ ] 临时测试代码能在控制台打印找到的应用数量

## Blocked by

- #2
