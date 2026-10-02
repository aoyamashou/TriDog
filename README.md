# ImeSwitch（自用）

基于 [⌘英かな](https://github.com/iMasanari/cmd-eikana) 精简而来。单击修饰键直接切换到指定输入法：

| 单击 | 切换到 |
|---|---|
| 左 ⌘ | 清歌输入法 |
| 右 ⌘ | 日语（罗马字） |
| 右 ⇧ | ABC |

映射和切换方式都写在 `Sources/main.swift` 顶部的 `targets` 里。

## 构建与使用

```bash
./build.sh
open build/ImeSwitch.app
```

首次运行需要在「系统设置 → 隐私与安全性 → 输入监控」里允许 ImeSwitch。每次重新构建后可能要重新勾选。
退出：点菜单栏的「⌘」→ Quit。

## 中日韩输入法切换不生效的问题

用 TIS 接口切到中日韩输入法后，当前应用偶尔还在用旧的输入法。`Strategy` 提供了几种处理方式：

- `.refocus`：切换后让焦点离开一下再回来，强制当前应用重新读取输入法。只在菜单栏「⌘」→「切换后刷新焦点」打开时生效（默认关闭）；关闭时等同 `.plain`。
- `.reselect`：50ms 后再选一次。
- `.kanaKey`：仅用于日语，改为发送かな键（需要「辅助功能」权限）。
- `.plain`：只调用 TIS，适合 ABC 这类键盘布局。
