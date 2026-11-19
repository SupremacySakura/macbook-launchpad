# 实现单元测试

## Parent

#1

## What to build

`AppScanner` 和搜索过滤逻辑有单元测试覆盖，使用 `MockAppScanner` 接缝，测试能独立运行。

## Acceptance criteria

- [ ] 存在 `MockAppScanner` 实现，返回硬编码的 `[App]` 数据
- [ ] 搜索过滤测试：输入 "saf" 匹配 "Safari"，不匹配 "Chrome"
- [ ] 搜索过滤测试：大小写不敏感，输入 "SAFARI" 匹配 "Safari"
- [ ] 搜索过滤测试：空搜索返回所有应用
- [ ] `xcodebuild test -scheme Launchpad` 通过

## Blocked by

- #4
- #7
