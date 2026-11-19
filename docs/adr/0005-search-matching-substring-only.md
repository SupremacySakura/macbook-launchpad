# V1 搜索匹配规则：仅大小写不敏感的子串匹配

搜索仅匹配应用名（`CFBundleDisplayName` 或 `CFBundleName`），规则是大小写不敏感的子串匹配（`contains`，忽略大小写）。

明确**不做**：
- ❌ 拼音匹配（输入 "wx" 匹配"微信"）
- ❌ 模糊匹配（输入 "sfar" 匹配 "Safari"）
- ❌ 匹配应用别名、关键词、`.app` 文件名、`CFBundleExecutable`

理由：
- 子串匹配实现只需一行 `localizedCaseInsensitiveContains`，覆盖 90% 实际场景
- 拼音匹配需要引入中文分词 / 拼音库，二进制体积和复杂度都显著增加
- 模糊匹配（fuzzy matching）需要评分算法，且结果排序对用户不直观

后果：
- 中文用户搜索英文应用（如输入"浏览器"找不到 Safari）会觉得搜索"不好用"。V2 可以考虑加入"应用别名表"作为轻量替代，而不是直接上拼音
