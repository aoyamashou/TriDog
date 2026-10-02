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
/// 左 ⌘ で切り替える入力ソースの ID。既定は清歌
let leftCommandTargetKey = "leftCommandTarget"

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

// MARK: - 入力ソース

func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
  guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
  return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue() as? T
}

/// id の入力ソースを選ぶ。既に選ばれていれば何もせず false
func selectInputSource(_ id: String) -> Bool {
  let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
  if property(current, kTISPropertyInputSourceID) as String? == id { return false }

  let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
  guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
    // 清歌などは同じ ID で入力メソッド本体と入力モードの 2 件が返るので、選択できる方を使う
    let source = list.first(where: {
      property($0, kTISPropertyInputSourceIsSelectCapable) as Bool? == true
    })
  else { return false }

  return TISSelectInputSource(source) == noErr
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

// MARK: - 修飾キー単体押しの検出

var eventTap: CFMachPort?
/// 押されたまま他の操作が無い修飾キー
var pressedKeyCode: CGKeyCode?

func handle(_ type: CGEventType, _ event: CGEvent) {
  switch type {
  case .tapDisabledByTimeout, .tapDisabledByUserInput:
    pressedKeyCode = nil
    if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }

  case .flagsChanged:
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard let mask = modifierMask(keyCode) else {
      pressedKeyCode = nil
      return
    }
    if event.flags.contains(mask) {
      // 別の修飾キーを押している最中なら組み合わせ操作とみなす
      pressedKeyCode = pressedKeyCode == nil ? keyCode : nil
      return
    }
    let isTap = pressedKeyCode == keyCode
    pressedKeyCode = nil
    guard isTap, let target = target(for: keyCode) else { return }
    // タップのコールバック中に TIS を呼ぶとタイムアウトしやすいので、次のループで行う
    DispatchQueue.main.async {
      if selectInputSource(target.id), target.cjkv, defaults.bool(forKey: refocusKey) {
        bounceFocus()
      }
    }

  default:
    pressedKeyCode = nil
  }
}

func watch() {
  let types: [CGEventType] = [
    .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
  ]
  let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

  guard
    let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
      eventsOfInterest: mask,
      callback: { _, type, event, _ in
        handle(type, event)
        return Unmanaged.passUnretained(event)
      }, userInfo: nil)
  else {
    NSLog("TriDog: failed to create event tap")
    exit(1)
  }

  eventTap = tap
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

    addItem(
      to: menu, text(
        zh: "切换后刷新焦点（修复中日韩输入法不生效）",
        en: "Refocus After Switching (fixes CJK input not applying)",
        ja: "切り替え後にフォーカスを更新（中日韓入力が反映されない問題の対策）"), #selector(toggleRefocus),
      on: defaults.bool(forKey: refocusKey))
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

  @objc func chooseLeftCommandTarget(_ sender: NSMenuItem) {
    defaults.set(sender.representedObject as? String, forKey: leftCommandTargetKey)
  }

  @objc func chooseShift(_ sender: NSMenuItem) {
    defaults.set(sender.tag, forKey: abcShiftKey)
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

if CGPreflightListenEventAccess() {
  watch()
} else {
  CGRequestListenEventAccess()
  Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
    if CGPreflightListenEventAccess() {
      timer.invalidate()
      watch()
    }
  }
}

app.run()
