# 三语狗输入快切 TriDog

**中文** | [English](README.en.md) | [日本語](README.ja.md)

<img src="Resources/icon.png" width="128">

一个 macOS 菜单栏小工具：**单击修饰键，直接切换到指定输入法**。适合同时使用中文、日语、英语三种输入法的人，不用再反复按 ⌃Space 轮换。

| 单击 | 切换到 |
|---|---|
| 左 ⌘ | 你选的中文（或其他）输入法，默认清歌输入法 |
| 右 ⌘ | 日语（罗马字输入） |
| 右 ⇧（可改为左 ⇧） | 英语 ABC |

只有「按下后什么都没做就松开」才算单击。⌘C、⌘ 加鼠标点击、用 Shift 输入大写字母都不会触发切换。

## 下载与安装

1. 从 [Releases](https://github.com/aoyamashou/ime-switch/releases) 下载最新的 `TriDog-x.x.x.zip`，解压后把 `TriDog.app` 拖到「应用程序」文件夹。
2. 首次打开：这个 App 没有经过苹果公证，双击时可能会被系统拦截。请右键点击 → 打开。
3. 在「系统设置 → 隐私与安全性 → 输入监控」里允许 TriDog。

运行要求：Apple Silicon Mac，macOS 13 或更新。

## 菜单选项

点击菜单栏的 ♻ 图标：

- **切换后刷新焦点**（默认关闭）：macOS 有个老问题，切到中日韩输入法后，菜单栏已经变了，但当前应用有时还在用旧输入法。打开这个选项后，切换时焦点会离开当前窗口约 30ms 再回来，强制当前应用重新读取输入法。代价是焦点会闪一下，开着的菜单或弹出框可能被关掉。
- **左 ⌘ 切换到**：从已启用的输入法中选择。列表不包含 ABC 等英文键盘和苹果自带的日语输入法。
- **切换英文 (ABC) 的按键**：选择左 ⇧ 或右 ⇧。
- **关于 / Quit**

## 从源代码构建

只需要 Xcode Command Line Tools，不需要装 Xcode：

```bash
./build.sh
open build/TriDog.app
```

日语和 ABC 的输入法 ID 写在 `Sources/main.swift` 顶部。图标由 `Scripts/make-icon.swift` 生成。

## 致谢与许可

基于 iMasanari 的 [⌘英かな](https://github.com/iMasanari/cmd-eikana)（及 [dominion525 的 Apple Silicon 分支](https://github.com/dominion525/cmd-eikana)）改造。采用与上游一致的 [MIT License](LICENSE)。
