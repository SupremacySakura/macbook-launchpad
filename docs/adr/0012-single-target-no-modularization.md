# V1 单 target 项目结构，不做模块化拆分

V1 使用单个 Xcode 项目、单个 SwiftUI App target，不拆分 Swift Package、不引入 MVVM 框架、不做依赖注入。

```
Launchpad/
├── LaunchpadApp.swift       # @main 入口
├── ContentView.swift        # 根视图
├── AppScanner.swift         # 扫描 .app
├── App.swift                # 数据模型
└── Assets.xcassets
```

理由：
- V1 预估总代码量 < 500 行，拆模块是过度设计
- 单一 target 编译快（< 5 秒），迭代效率高
- 如果 V2 加拖拽/文件夹导致代码膨胀，届时再拆

后果：
- 如果代码超过 2000 行还不拆，会导致编译时间变长、导航困难。届时重新评估
