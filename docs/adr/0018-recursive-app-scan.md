# 递归扫描应用目录，包含 Utilities 子目录

扫描 `/Applications`、`~/Applications`、`/System/Applications` 时递归枚举子目录，并使用 `.skipsPackageDescendants` 避免进入 `.app` 包内部。同一应用按解析符号链接后的路径去重。

理由：
- 只扫描根目录会漏掉 `/System/Applications/Utilities`（终端、磁盘工具等）和 `/Applications/Utilities` 中的常用应用，违反"展示所有应用"
- 原生 Launchpad 也展示这些工具类应用
- 递归不会误入 `.app` 内部，符号链接去重避免同一应用重复出现

后果：
- 用户放在自定义子目录中的应用也会被发现（符合预期）
- 扫描耗时随目录深度增加，但仍在毫秒级
