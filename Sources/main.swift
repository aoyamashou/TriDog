//
//  main.swift
//  三语狗输入快切 TriDog — 修飾キー単体押しで入力ソースを直接切り替える
//
//  Based on ⌘英かな (cmd-eikana)
//  MIT License
//  Copyright (c) 2016 iMasanari
//

import Carbon.HIToolbox
import Cocoa
import ServiceManagement

// MARK: - 設定

let japaneseID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
let abcID = "com.apple.keylayout.ABC"

let leftShift: CGKeyCode = 56
let rightShift: CGKeyCode = 60

let homepage = "https://github.com/aoyamashou/TriDog"

let defaults = UserDefaults.standard
/// 切り替え後にフォーカスを付け替えるか（CJKV 入力メソッドの不具合対策）。既定はオフ
let refocusKey = "refocusEnabled"
/// ABC に切り替える Shift の keyCode。既定は右 Shift
let abcShiftKey = "abcShift"
/// メニューバーのアイコンを隠しているか
let hideIconKey = "hideStatusIcon"
/// 診断ログを書くか。既定はオフ
let loggingKey = "loggingEnabled"
/// 左 ⌘ で切り替える入力ソースの ID。既定は清歌
let leftCommandTargetKey = "leftCommandTarget"
/// F1〜F12 のカスタムキーマッピング設定
let fKeyMappingsKey = "fKeyMappings"

// MARK: - F1〜F12 キーマッピング設定

struct KeyCombo: Codable, Equatable {
  var keyCode: UInt16
  var modifiers: UInt64
  var enabled: Bool
}

let fKeys: [(name: String, keyCode: CGKeyCode)] = [
  ("F1", CGKeyCode(kVK_F1)),
  ("F2", CGKeyCode(kVK_F2)),
  ("F3", CGKeyCode(kVK_F3)),
  ("F4", CGKeyCode(kVK_F4)),
  ("F5", CGKeyCode(kVK_F5)),
  ("F6", CGKeyCode(kVK_F6)),
  ("F7", CGKeyCode(kVK_F7)),
  ("F8", CGKeyCode(kVK_F8)),
  ("F9", CGKeyCode(kVK_F9)),
  ("F10", CGKeyCode(kVK_F10)),
  ("F11", CGKeyCode(kVK_F11)),
  ("F12", CGKeyCode(kVK_F12)),
]

let fKeyNameByCode: [CGKeyCode: String] = Dictionary(uniqueKeysWithValues: fKeys.map { ($0.keyCode, $0.name) })

var fKeyMappings: [String: KeyCombo] = {
  guard let data = defaults.data(forKey: fKeyMappingsKey),
    let decoded = try? JSONDecoder().decode([String: KeyCombo].self, from: data)
  else { return [:] }
  return decoded
}()

func saveFKeyMappings() {
  if let data = try? JSONEncoder().encode(fKeyMappings) {
    defaults.set(data, forKey: fKeyMappingsKey)
  }
}

/// ショートカット録音中は F1〜F12 のリマップを一時停止する
var isRecordingShortcut = false

/// 左 ⌘ の切り替え先。保存値 → 清歌 → 選べる入力ソースの先頭 の順に、実際に有効なものを使う。
/// 清歌を入れていない環境や、選んでいた入力ソースを削除した場合でも動くようにする
var leftCommandTarget: String? {
  let methods = selectableInputMethods()
  let candidates = [defaults.string(forKey: leftCommandTargetKey), "com.aodaren.inputmethod.Qingg"]
  for case let id? in candidates where methods.contains(where: { $0.id == id }) {
    return id
  }
  return methods.first?.id
}

/// メニューの表示言語。システムの優先言語が中国語・日本語ならそれ、他は英語
let language: String = {
  let preferred = Locale.preferredLanguages.first ?? "en"
  if preferred.hasPrefix("zh") { return "zh" }
  if preferred.hasPrefix("ja") { return "ja" }
  return "en"
}()

func text(zh: String, en: String, ja: String) -> String {
  switch language {
  case "zh": return zh
  case "ja": return ja
  default: return en
  }
}

var abcShift: CGKeyCode {
  defaults.integer(forKey: abcShiftKey) == Int(leftShift) ? leftShift : rightShift
}

/// 単体押しした修飾キーの切り替え先と、フォーカス付け替えの対象か
func target(for keyCode: CGKeyCode) -> (id: String, cjkv: Bool)? {
  switch keyCode {
  case 55: return leftCommandTarget.map { ($0, true) }  // 左 ⌘ → 選んだ入力ソース（既定は清歌）
  case 54: return (japaneseID, true)  // 右 ⌘ → 日本語
  case abcShift: return (abcID, false)  // 左 or 右 ⇧ → ABC
  default: return nil
  }
}

/// flagsChanged の keyCode に対応する修飾フラグ。修飾キーでなければ nil
func modifierMask(_ keyCode: CGKeyCode) -> CGEventFlags? {
  switch keyCode {
  case 54, 55: return .maskCommand
  case 56, 60: return .maskShift
  case 59, 62: return .maskControl
  case 58, 61: return .maskAlternate
  case 63: return .maskSecondaryFn
  case 57: return .maskAlphaShift
  default: return nil
  }
}

// MARK: - 診断ログ

let logURL = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Logs/TriDog.log")
let logFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
  return f
}()

/// ~/Library/Logs/TriDog.log に 1 行追記する。オフのときは何もしない（force は印を付けるとき用）。
/// 1 MB を超えたら TriDog.log.old に退避して作り直す
func log(_ message: @autoclosure () -> String, force: Bool = false) {
  guard force || defaults.bool(forKey: loggingKey) else { return }
  let fm = FileManager.default
  if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > 1_000_000 {
    let old = logURL.appendingPathExtension("old")
    try? fm.removeItem(at: old)
    try? fm.moveItem(at: logURL, to: old)
  }
  let line = "\(logFormatter.string(from: Date())) \(message())\n"
  guard let data = line.data(using: .utf8) else { return }
  if let handle = try? FileHandle(forWritingTo: logURL) {
    handle.seekToEndOfFile()
    handle.write(data)
    try? handle.close()
  } else {
    try? data.write(to: logURL)
  }
}

/// 入力ソース 1 件の要約（ID・種別・モード・選択可否）
func describe(_ source: TISInputSource) -> String {
  let id = property(source, kTISPropertyInputSourceID) as String? ?? "?"
  let type = (property(source, kTISPropertyInputSourceType) as String? ?? "?")
    .replacingOccurrences(of: "TISType", with: "")
  let mode = property(source, kTISPropertyInputModeID) as String? ?? "-"
  let capable = property(source, kTISPropertyInputSourceIsSelectCapable) as Bool? == true
  return "{id=\(id) type=\(type) mode=\(mode) selectable=\(capable)}"
}

func currentSourceDescription() -> String {
  describe(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
}

func frontmostDescription() -> String {
  NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
}

/// 切り替えの後、入力ソースが維持されているかを少し遅れて 2 回記録する
func logSettled(expecting id: String) {
  guard defaults.bool(forKey: loggingKey) else { return }
  for ms in [100, 500] {
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
      log("  +\(ms)ms current=\(currentSourceDescription()) expected=\(id) frontmost=\(frontmostDescription())")
    }
  }
}

// MARK: - 入力ソース

func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
  guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
  return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? T
}

/// id の入力ソースを選ぶ。既に選ばれていれば何もせず false
func selectInputSource(_ id: String) -> Bool {
  let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
  if property(current, kTISPropertyInputSourceID) as String? == id {
    log("select \(id): already current \(describe(current)) -> skipped")
    return false
  }

  let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
  guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
    // 清歌などは同じ ID で入力メソッド本体と入力モードの 2 件が返るので、選択できる方を使う
    let source = list.first(where: {
      property($0, kTISPropertyInputSourceIsSelectCapable) as Bool? == true
    })
  else {
    log("select \(id): no selectable source found")
    return false
  }

  let status = TISSelectInputSource(source)
  log(
    "select \(id): from=\(describe(current)) candidates=\(list.map(describe)) picked=\(describe(source)) status=\(status) now=\(currentSourceDescription())"
  )
  return status == noErr
}

/// 左 ⌘ の切り替え先に選べる入力ソース（ID と名前）。
/// 有効で選択できるキーボード入力ソースのうち、キーボードレイアウト（ABC など英語系）と
/// Apple の日本語入力を除く。清歌のように同じ ID が 2 件返るものは 1 件にまとめる
func selectableInputMethods() -> [(id: String, name: String)] {
  guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
  else { return [] }

  var result: [(id: String, name: String)] = []
  for source in list {
    guard property(source, kTISPropertyInputSourceCategory) as String?
      == kTISCategoryKeyboardInputSource as String,
      property(source, kTISPropertyInputSourceType) as String?
        != kTISTypeKeyboardLayout as String,
      property(source, kTISPropertyInputSourceIsSelectCapable) as Bool? == true,
      let id = property(source, kTISPropertyInputSourceID) as String?,
      !id.hasPrefix("com.apple.inputmethod.Kotoeri"),
      !result.contains(where: { $0.id == id })
    else { continue }
    result.append((id, property(source, kTISPropertyLocalizedName) as String? ?? id))
  }
  return result
}

/// 入力ソースを ABC に退避してから選び直し、入力メソッドを最前面アプリに対して再度有効化させる
func reactivate(_ id: String) {
  _ = selectInputSource(abcID)
  DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
    _ = selectInputSource(id)
    if defaults.bool(forKey: refocusKey) { bounceFocus() }
  }
}

// MARK: - フォーカスの付け替え（CJKV 対策）

/// key になれる 1×1 の透明ウィンドウ
final class FocusWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

/// 最前面のアプリからフォーカスを一瞬奪い、すぐに返す。入力欄が戻ってきた時点で現在の入力ソースを読み直す。
/// ウィンドウは初回だけ作る
var focusWindow: FocusWindow?

func bounceFocus() {
  guard let previous = NSWorkspace.shared.frontmostApplication, previous != .current else { return }

  let window =
    focusWindow
    ?? {
      let window = FocusWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: .borderless, backing: .buffered, defer: true)
      window.isOpaque = false
      window.backgroundColor = .clear
      window.alphaValue = 0.01
      window.level = .floating
      window.ignoresMouseEvents = true
      window.isReleasedWhenClosed = false
      window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
      focusWindow = window
      return window
    }()

  window.makeKeyAndOrderFront(nil)
  NSApp.activate(ignoringOtherApps: true)

  DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
    window.orderOut(nil)
    previous.activate()
  }
}

// MARK: - 修飾キー単体押し・F1〜F12 リマップの検出

var eventTap: CFMachPort?
/// 押されたまま他の操作が無い修飾キー
var pressedKeyCode: CGKeyCode?
/// 現在押し下げ中でリマップ済みの F キー（keyUp を確実にペアで送るため、押下時のターゲットを保持する）
var activeRemappedKeys: [CGKeyCode: KeyCombo] = [:]
/// 自前で送出した合成イベントを識別し、eventTap の無限ループを防ぐタグ
let syntheticEventTag: Int64 = 0x5452_4447
let relevantModifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

func postSyntheticKey(_ combo: KeyCombo, keyDown: Bool) {
  let source = CGEventSource(stateID: .hidSystemState)
  guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(combo.keyCode), keyDown: keyDown)
  else { return }
  event.flags = CGEventFlags(rawValue: combo.modifiers)
  event.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
  event.post(tap: .cghidEventTap)
}

func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
  if event.getIntegerValueField(.eventSourceUserData) == syntheticEventTag {
    return Unmanaged.passUnretained(event)
  }

  switch type {
  case .tapDisabledByTimeout, .tapDisabledByUserInput:
    pressedKeyCode = nil
    activeRemappedKeys.removeAll()
    log("event tap disabled (\(type.rawValue)), re-enabling")
    if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }

  case .keyDown:
    pressedKeyCode = nil
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard !isRecordingShortcut, let fName = fKeyNameByCode[keyCode] else { break }

    let activeMods = event.flags.intersection(relevantModifierMask)
    if let combo = fKeyMappings[fName], combo.enabled, activeMods.isEmpty {
      let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
      if !isRepeat {
        activeRemappedKeys[keyCode] = combo
        log("remap \(fName) -> \(formatKeyCombo(combo))")
      }
      postSyntheticKey(combo, keyDown: true)
      return nil
    }

  case .keyUp:
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if let combo = activeRemappedKeys.removeValue(forKey: keyCode) {
      postSyntheticKey(combo, keyDown: false)
      return nil
    }

  case .flagsChanged:
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard let mask = modifierMask(keyCode) else {
      pressedKeyCode = nil
      return Unmanaged.passUnretained(event)
    }
    if event.flags.contains(mask) {
      // 別の修飾キーを押している最中なら組み合わせ操作とみなす
      pressedKeyCode = pressedKeyCode == nil ? keyCode : nil
      return Unmanaged.passUnretained(event)
    }
    let isTap = pressedKeyCode == keyCode
    pressedKeyCode = nil
    guard isTap, let target = target(for: keyCode) else { return Unmanaged.passUnretained(event) }
    // タップのコールバック中に TIS を呼ぶとタイムアウトしやすいので、次のループで行う
    DispatchQueue.main.async {
      log(
        "key=\(keyCode) target=\(target.id) cjkv=\(target.cjkv) refocus=\(defaults.bool(forKey: refocusKey)) frontmost=\(frontmostDescription()) current=\(currentSourceDescription())"
      )
      let switched = selectInputSource(target.id)
      logSettled(expecting: target.id)
      guard target.cjkv else { return }
      if switched {
        log("  path=switched")
        if defaults.bool(forKey: refocusKey) { bounceFocus() }
      } else {
        // 既に目標の入力ソースになっている。システム上は切り替わっているのに
        // アプリ側が英字のまま（macOS の不具合）という状態から、もう一度押して復帰できるようにする
        log("  path=reactivate")
        reactivate(target.id)
      }
    }

  default:
    pressedKeyCode = nil
  }

  return Unmanaged.passUnretained(event)
}

func watch() {
  let types: [CGEventType] = [
    .flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
  ]
  let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

  guard
    let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
      eventsOfInterest: mask,
      callback: { _, type, event, _ in
        handle(type, event)
      }, userInfo: nil)
  else {
    NSLog("TriDog: failed to create event tap")
    return
  }

  eventTap = tap
  log("event tap started")
  CFRunLoopAddSource(
    CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
  CGEvent.tapEnable(tap: tap, enable: true)
}

// MARK: - メニュー

/// メニューは開くたびに作り直す（入力ソースの追加・削除をその場で反映するため）。
/// 選択肢はサブメニューにせず、見出しの下にインデントして並べる
final class MenuHandler: NSObject, NSMenuDelegate {
  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    // 事件監視が始まっていない（補助機能・入力監視の許可が無効）と、キーの切り替え・リマップは動かない
    if eventTap == nil {
      addHeader(
        to: menu,
        text(
          zh: "⚠️ 未获得「辅助功能」权限，按键功能暂未生效",
          en: "⚠️ Accessibility not granted — key features are inactive",
          ja: "⚠️ 「アクセシビリティ」が未許可のため、キー機能は無効です"))
      addItem(
        to: menu,
        text(zh: "打开「辅助功能」设置…", en: "Open Accessibility Settings…", ja: "「アクセシビリティ」設定を開く…"),
        #selector(openAccessibility), on: false)
      addItem(
        to: menu,
        text(zh: "打开「输入监控」设置…", en: "Open Input Monitoring Settings…", ja: "「入力監視」の設定を開く…"),
        #selector(openInputMonitoring), on: false)
      menu.addItem(.separator())
    }

    addItem(
      to: menu,
      text(
        zh: "F1–F12 按键映射设置…",
        en: "F1–F12 Key Mapping Settings…",
        ja: "F1〜F12 キーマッピング設定…"),
      #selector(openKeyMappingSettings), on: false)
    menu.addItem(.separator())

    addItem(
      to: menu, text(
        zh: "切换后刷新焦点（修复中日韩输入法不生效）",
        en: "Refocus After Switching (fixes CJK input not applying)",
        ja: "切り替え後にフォーカスを更新（中日韓入力が反映されない問題の対策）"), #selector(toggleRefocus),
      on: defaults.bool(forKey: refocusKey))
    // 状態は SMAppService が持つので UserDefaults には保存しない。未登録（既定）ならオフ
    addItem(
      to: menu, text(zh: "开机自动启动", en: "Launch at Login", ja: "ログイン時に起動"),
      #selector(toggleLaunchAtLogin), on: SMAppService.mainApp.status == .enabled)
    addItem(
      to: menu,
      text(
        zh: "隐藏菜单栏图标（再次启动本程序即可恢复）",
        en: "Hide Menu Bar Icon (launch the app again to restore)",
        ja: "メニューバーのアイコンを隠す（もう一度起動すると再表示）"),
      #selector(hideStatusIcon), on: false)
    addItem(
      to: menu,
      text(zh: "记录诊断日志", en: "Write Diagnostic Log", ja: "診断ログを記録"),
      #selector(toggleLogging), on: defaults.bool(forKey: loggingKey))
    if defaults.bool(forKey: loggingKey) {
      addItem(
        to: menu,
        text(zh: "标记：刚才输入异常", en: "Mark: Input Just Went Wrong", ja: "印を付ける：今、入力がおかしい"),
        #selector(markProblem), on: false, indented: true)
      addItem(
        to: menu, text(zh: "在访达中显示日志", en: "Show Log in Finder", ja: "ログを Finder で表示"),
        #selector(revealLog), on: false, indented: true)
    }
    menu.addItem(.separator())

    addHeader(to: menu, text(zh: "左 ⌘ 切换到", en: "Left ⌘ Switches To", ja: "左 ⌘ の切り替え先"))
    let methods = selectableInputMethods()
    if methods.isEmpty {
      addHeader(
        to: menu,
        text(zh: "（没有可选的输入法）", en: "(No input methods available)", ja: "（選べる入力ソースがありません）"),
        indented: true)
    }
    let current = leftCommandTarget
    for method in methods {
      addItem(
        to: menu, method.name, #selector(chooseLeftCommandTarget), on: method.id == current,
        indented: true
      ).representedObject = method.id
    }
    menu.addItem(.separator())

    addHeader(
      to: menu,
      text(zh: "切换英文 (ABC) 的按键", en: "Key for English (ABC)", ja: "英語 (ABC) に切り替えるキー"))
    let shifts = [
      (text(zh: "左 ⇧", en: "Left ⇧", ja: "左 ⇧"), leftShift),
      (text(zh: "右 ⇧", en: "Right ⇧", ja: "右 ⇧"), rightShift),
    ]
    for (title, keyCode) in shifts {
      addItem(to: menu, title, #selector(chooseShift), on: abcShift == keyCode, indented: true).tag =
        Int(keyCode)
    }
    menu.addItem(.separator())

    addItem(
      to: menu, text(zh: "关于 三语狗输入快切", en: "About TriDog", ja: "TriDog について"),
      #selector(showAbout), on: false)
    menu.addItem(
      withTitle: text(zh: "退出", en: "Quit", ja: "終了"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
  }

  @objc func showAbout() {
    let credits = NSMutableAttributedString(
      string: "\(homepage)\n\nBased on ⌘英かな by iMasanari · MIT License",
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.secondaryLabelColor,
      ])
    credits.addAttribute(.link, value: homepage, range: NSRange(location: 0, length: homepage.count))
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))

    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: "三语狗输入快切 TriDog",
      .credits: credits,
    ])
  }

  @discardableResult
  private func addItem(
    to menu: NSMenu, _ title: String, _ action: Selector, on: Bool, indented: Bool = false
  ) -> NSMenuItem {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
    item.target = self
    item.state = on ? .on : .off
    item.indentationLevel = indented ? 1 : 0
    return item
  }

  private func addHeader(to menu: NSMenu, _ title: String, indented: Bool = false) {
    let item = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    item.indentationLevel = indented ? 1 : 0
  }

  @objc func toggleRefocus() {
    defaults.set(!defaults.bool(forKey: refocusKey), forKey: refocusKey)
  }

  @objc func openAccessibility() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  @objc func openInputMonitoring() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    {
      NSWorkspace.shared.open(url)
    }
  }

  @objc func openKeyMappingSettings() {
    KeyMappingWindowController.shared.show()
  }

  @objc func toggleLogging() {
    let enabled = !defaults.bool(forKey: loggingKey)
    if enabled {
      defaults.set(true, forKey: loggingKey)
      let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
      log("=== logging on, TriDog \(v), macOS \(ProcessInfo.processInfo.operatingSystemVersionString) ===")
    } else {
      log("=== logging off ===")
      defaults.set(false, forKey: loggingKey)
    }
  }

  /// 異常に気付いた瞬間に押す。直前のログと照らし合わせるための目印
  @objc func markProblem() {
    log("!!! MARK: input wrong. current=\(currentSourceDescription()) frontmost=\(frontmostDescription())", force: true)
  }

  @objc func revealLog() {
    NSWorkspace.shared.activateFileViewerSelecting([logURL])
  }

  @objc func hideStatusIcon() {
    defaults.set(true, forKey: hideIconKey)
    statusItem.isVisible = false
  }

  @objc func toggleLaunchAtLogin() {
    let service = SMAppService.mainApp
    do {
      if service.status == .enabled {
        try service.unregister()
      } else {
        try service.register()
      }
    } catch {
      NSLog("TriDog: launch at login: \(error)")
    }
    // ユーザーの承認待ちになったときは「ログイン項目」の設定画面を開く
    if service.status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
  }

  @objc func chooseLeftCommandTarget(_ sender: NSMenuItem) {
    defaults.set(sender.representedObject as? String, forKey: leftCommandTargetKey)
  }

  @objc func chooseShift(_ sender: NSMenuItem) {
    defaults.set(sender.tag, forKey: abcShiftKey)
  }
}

// MARK: - キー表記・設定ウィンドウ

let specialKeyNames: [UInt16: String] = [
  UInt16(kVK_Return): "↩",
  UInt16(kVK_Tab): "⇥",
  UInt16(kVK_Space): "Space",
  UInt16(kVK_Delete): "⌫",
  UInt16(kVK_Escape): "⎋",
  UInt16(kVK_ForwardDelete): "⌦",
  UInt16(kVK_UpArrow): "↑",
  UInt16(kVK_DownArrow): "↓",
  UInt16(kVK_LeftArrow): "←",
  UInt16(kVK_RightArrow): "→",
  UInt16(kVK_Home): "↖",
  UInt16(kVK_End): "↘",
  UInt16(kVK_PageUp): "⇞",
  UInt16(kVK_PageDown): "⇟",
  UInt16(kVK_F1): "F1",
  UInt16(kVK_F2): "F2",
  UInt16(kVK_F3): "F3",
  UInt16(kVK_F4): "F4",
  UInt16(kVK_F5): "F5",
  UInt16(kVK_F6): "F6",
  UInt16(kVK_F7): "F7",
  UInt16(kVK_F8): "F8",
  UInt16(kVK_F9): "F9",
  UInt16(kVK_F10): "F10",
  UInt16(kVK_F11): "F11",
  UInt16(kVK_F12): "F12",
  UInt16(kVK_F13): "F13",
  UInt16(kVK_F14): "F14",
  UInt16(kVK_F15): "F15",
  UInt16(kVK_F16): "F16",
  UInt16(kVK_F17): "F17",
  UInt16(kVK_F18): "F18",
  UInt16(kVK_F19): "F19",
  UInt16(kVK_F20): "F20",
]

func keyName(for keyCode: UInt16) -> String {
  if let special = specialKeyNames[keyCode] { return special }
  if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
    let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
  {
    let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = data.withUnsafeBytes { rawPtr -> OSStatus in
      guard let layout = rawPtr.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
        return OSStatus(paramErr)
      }
      return UCKeyTranslate(
        layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
    }
    if status == noErr, length > 0 {
      let str = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
      if !str.isEmpty { return str.uppercased() }
    }
  }
  return "Key(\(keyCode))"
}

func formatKeyCombo(_ combo: KeyCombo) -> String {
  let flags = CGEventFlags(rawValue: combo.modifiers)
  var prefix = ""
  if flags.contains(.maskControl) { prefix += "⌃" }
  if flags.contains(.maskAlternate) { prefix += "⌥" }
  if flags.contains(.maskShift) { prefix += "⇧" }
  if flags.contains(.maskCommand) { prefix += "⌘" }
  return prefix + keyName(for: combo.keyCode)
}

func cgFlags(from modifierFlags: NSEvent.ModifierFlags) -> CGEventFlags {
  var result = CGEventFlags()
  if modifierFlags.contains(.control) { result.insert(.maskControl) }
  if modifierFlags.contains(.option) { result.insert(.maskAlternate) }
  if modifierFlags.contains(.shift) { result.insert(.maskShift) }
  if modifierFlags.contains(.command) { result.insert(.maskCommand) }
  return result
}

final class KeyMappingWindowController: NSObject, NSWindowDelegate {
  static let shared = KeyMappingWindowController()

  private var window: NSWindow?
  private var checkboxes: [String: NSButton] = [:]
  private var recorderButtons: [String: NSButton] = [:]
  private var clearButtons: [String: NSButton] = [:]
  private var recordingFName: String?
  private var localMonitor: Any?

  func show() {
    if window == nil {
      buildWindow()
    }
    refreshRows()
    NSApp.activate(ignoringOtherApps: true)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
  }

  private func buildWindow() {
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    win.title = text(
      zh: "F1–F12 按键映射设置",
      en: "F1–F12 Key Mapping Settings",
      ja: "F1〜F12 キーマッピング設定")
    win.isReleasedWhenClosed = false
    win.delegate = self

    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 10
    root.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
    root.translatesAutoresizingMaskIntoConstraints = false

    let hint = NSTextField(
      wrappingLabelWithString: text(
        zh: "仅单独按下 F1–F12（含 Fn+F1–F12）时触发映射；按住 ⌘ / ⌥ / ⌃ / ⇧ 时保留原按键。",
        en: "Triggers only when F1–F12 (or Fn+F1–F12) is pressed alone. Holding ⌘ / ⌥ / ⌃ / ⇧ passes through.",
        ja: "F1〜F12 単体押し（Fn+F1〜F12 を含む）のみ変換します。⌘ / ⌥ / ⌃ / ⇧ 併用時はそのまま送信します。"))
    hint.font = .systemFont(ofSize: 12)
    hint.textColor = .secondaryLabelColor
    root.addArrangedSubview(hint)

    for (fName, _) in fKeys {
      let row = NSStackView()
      row.orientation = .horizontal
      row.alignment = .centerY
      row.spacing = 10

      let toggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleMapping(_:)))
      toggle.identifier = NSUserInterfaceItemIdentifier(fName)
      toggle.widthAnchor.constraint(equalToConstant: 20).isActive = true

      let label = NSTextField(labelWithString: fName)
      label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
      label.widthAnchor.constraint(equalToConstant: 36).isActive = true

      let recorder = NSButton(title: "", target: self, action: #selector(toggleRecord(_:)))
      recorder.bezelStyle = .rounded
      recorder.identifier = NSUserInterfaceItemIdentifier(fName)
      recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true

      let clear = NSButton(
        title: text(zh: "清除", en: "Clear", ja: "消去"),
        target: self,
        action: #selector(clearMapping(_:)))
      clear.bezelStyle = .rounded
      clear.identifier = NSUserInterfaceItemIdentifier(fName)
      clear.widthAnchor.constraint(equalToConstant: 64).isActive = true

      row.addArrangedSubview(toggle)
      row.addArrangedSubview(label)
      row.addArrangedSubview(recorder)
      row.addArrangedSubview(clear)

      checkboxes[fName] = toggle
      recorderButtons[fName] = recorder
      clearButtons[fName] = clear
      root.addArrangedSubview(row)
    }

    win.contentView = root
    window = win
  }

  private func refreshRows() {
    for (fName, _) in fKeys {
      let combo = fKeyMappings[fName]
      let toggle = checkboxes[fName]
      let recorder = recorderButtons[fName]
      let clear = clearButtons[fName]

      if recordingFName == fName {
        recorder?.title = text(
          zh: "请按下快捷键…（再次点击取消）",
          en: "Press shortcut… (click to cancel)",
          ja: "ショートカットを入力…（再クリックで取消）")
      } else if let combo {
        recorder?.title = formatKeyCombo(combo)
      } else {
        recorder?.title = text(zh: "点击设置快捷键", en: "Click to set shortcut", ja: "クリックして設定")
      }

      toggle?.isEnabled = combo != nil
      toggle?.state = (combo?.enabled == true) ? .on : .off
      clear?.isEnabled = combo != nil
    }
  }

  @objc private func toggleMapping(_ sender: NSButton) {
    guard let fName = sender.identifier?.rawValue, var combo = fKeyMappings[fName] else { return }
    combo.enabled = sender.state == .on
    fKeyMappings[fName] = combo
    saveFKeyMappings()
    refreshRows()
  }

  @objc private func clearMapping(_ sender: NSButton) {
    guard let fName = sender.identifier?.rawValue else { return }
    if recordingFName == fName { stopRecording() }
    fKeyMappings.removeValue(forKey: fName)
    saveFKeyMappings()
    refreshRows()
  }

  @objc private func toggleRecord(_ sender: NSButton) {
    guard let fName = sender.identifier?.rawValue else { return }
    if recordingFName == fName {
      stopRecording()
      refreshRows()
      return
    }
    startRecording(for: fName)
  }

  private func startRecording(for fName: String) {
    stopRecording()
    recordingFName = fName
    isRecordingShortcut = true
    refreshRows()

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let targetFName = self.recordingFName else { return event }
      let flags = cgFlags(from: event.modifierFlags)
      let combo = KeyCombo(keyCode: event.keyCode, modifiers: flags.rawValue, enabled: true)
      fKeyMappings[targetFName] = combo
      saveFKeyMappings()
      self.stopRecording()
      self.refreshRows()
      return nil
    }
  }

  private func stopRecording() {
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
      localMonitor = nil
    }
    recordingFName = nil
    isRecordingShortcut = false
  }

  func windowWillClose(_ notification: Notification) {
    stopRecording()
  }
}

// MARK: - 起動

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let menuHandler = MenuHandler()
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
// アプリアイコンと同じリサイクルマーク。テンプレート画像にしてメニューバーの明暗に合わせる
let statusImage = NSImage(systemSymbolName: "arrow.3.trianglepath", accessibilityDescription: "TriDog")
statusImage?.isTemplate = true
statusItem.button?.image = statusImage
let menu = NSMenu()
menu.autoenablesItems = false
menu.delegate = menuHandler
statusItem.menu = menu

/// 隠している間にもう一度起動（Finder・Launchpad・`open`）されると、実行中のプロセスに reopen が届くので、アイコンを戻す
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    defaults.set(false, forKey: hideIconKey)
    statusItem.isVisible = true
    return false
  }
}
let appDelegate = AppDelegate()
app.delegate = appDelegate

/// 隠した状態を保つのは、ログイン時の自動起動のときだけ。手動で起動したときは必ず表示する
let launchedAsLoginItem =
  NSAppleEventManager.shared().currentAppleEvent?
  .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
if defaults.bool(forKey: hideIconKey), launchedAsLoginItem {
  statusItem.isVisible = false
} else {
  defaults.set(false, forKey: hideIconKey)
  statusItem.isVisible = true
}

if AXIsProcessTrusted() {
  watch()
} else {
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(options)
  Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
    if AXIsProcessTrusted() {
      timer.invalidate()
      watch()
    }
  }
}

app.run()
