# 三语狗输入快切 TriDog

**中文** | [English](README.en.md) | [日本語](README.ja.md)

<img src="Resources/banner.png" alt="TriDog banner">

<img src="Resources/TriDog-promo.gif" alt="TriDog demo" width="420">

一个 macOS 菜单栏小工具：**单击修饰键，直接切换到指定输入法**。适合同时使用中文、日语、英语三种输入法的人，不用再反复按 ⌃Space 轮换。

> **适用范围：本项目仅适用于 US 配列（美式布局）键盘。** JIS 配列（日式布局）键盘自带「英数」「かな」键，系统本身就能直接切换，不需要本项目。

| 单击 | 切换到 |
|---|---|
| 左 ⌘ | 中文输入法，**可在菜单中自己选择**（默认清歌输入法；没装清歌时自动用列表里的第一个） |
| 右 ⌘ | 日语（罗马字输入） |
| 右 ⇧ 或 左 ⇧ | 英语 ABC，**可在菜单中自己选择用左 ⇧ 还是右 ⇧**（默认右 ⇧） |

只有「按下后什么都没做就松开」才算单击。⌘C、⌘ 加鼠标点击、用 Shift 输入大写字母都不会触发切换。

## 下载与安装

1. 从 [Releases](https://github.com/aoyamashou/TriDog/releases) 下载最新的 `TriDog-x.x.x.zip`，解压后把 `TriDog.app` 拖到「应用程序」文件夹。
2. 首次打开：这是个人业余小项目，没有付费做苹果公证，双击时可能会被系统拦截。请右键点击 → 打开。
3. 在「系统设置 → 隐私与安全性 → 输入监控」里允许 TriDog。

运行要求：Apple Silicon Mac，macOS 13 或更新。

## 菜单选项

点击菜单栏的 ♻ 图标：

- **切换后刷新焦点**（默认关闭）：macOS 有个老问题，切到中日韩输入法后，菜单栏已经变了，但当前应用有时还在用旧输入法。打开这个选项后，切换时焦点会离开当前窗口约 30ms 再回来，强制当前应用重新读取输入法。代价是焦点会闪一下，开着的菜单或弹出框可能被关掉。
- **左 ⌘ 切换到**：从已启用的输入法中选择。列表不包含 ABC 等英文键盘和苹果自带的日语输入法。
- **切换英文 (ABC) 的按键**：选择左 ⇧ 或右 ⇧。
- **关于 / 退出**

## 键位不合习惯？

如果这套键位不符合你的习惯（比如想用别的键，或者想切到别的输入法），请自行克隆本仓库，让你的 AI agent（如 Claude Code）去改。所有逻辑都在一个文件 `Sources/main.swift` 里，改起来很简单：

```bash
git clone https://github.com/aoyamashou/TriDog.git
```

## 从源代码构建

只需要 Xcode Command Line Tools，不需要装 Xcode：

```bash
./build.sh
open build/TriDog.app
```

日语和 ABC 的输入法 ID 写在 `Sources/main.swift` 顶部。图标由 `Scripts/make-icon.swift` 生成。

## 友情项目

这两个项目的作者在输入法和 Claude 模型使用方面给了我非常多的指导，大家有兴趣也可以看看他们的项目：

- [水杉输入法 MSIME](https://github.com/metasequoiaime/msime)：开源的多平台中文输入法，支持 Android、iOS、macOS、Linux、Windows 和 HarmonyOS，各平台共用同一套 Rust 输入引擎。
- [QDuo](https://github.com/XueshiQiao/qduo)：macOS 划词工具，在任意 App 里选中文字，光标旁就会弹出你自定义的操作（翻译、润色、搜索、朗读、问 AI 等），结果直接写回原处。

## 致谢与许可

基于 iMasanari 的 [⌘英かな](https://github.com/iMasanari/cmd-eikana)（及 [dominion525 的 Apple Silicon 分支](https://github.com/dominion525/cmd-eikana)）改造。采用与上游一致的 [MIT License](LICENSE)。
