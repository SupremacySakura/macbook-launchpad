# 应用排序：本地化字母序，不分目录

所有应用按应用名做本地化不区分大小写排序（`String.localizedCaseInsensitiveCompare`），混合显示，不按所在目录分组。

理由：
- 用户心智模型是"我要找 Safari"，而不是"Safari 装在哪个目录"
- macOS 15 原生 Launchpad 也是混合排序（虽然它默认按安装时间）
- 实现简单：`sorted(using:)` 一行搞定

后果：
- 用户可能期望"系统应用"和"第三方应用"分开。如果反馈强烈，V2 可以加"分组"开关
