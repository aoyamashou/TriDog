//
//  main.swift
//  ImeSwitch — 修飾キー単体押しで入力ソースを直接切り替える（自用）
//
//  Based on ⌘英かな (cmd-eikana)
//  MIT License
//  Copyright (c) 2016 iMasanari
//

import Carbon.HIToolbox
import Cocoa

// MARK: - 設定

let qinggID = "com.aodaren.inputmethod.Qingg"
let japaneseID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
let abcID = "com.apple.keylayout.ABC"

let leftShift: CGKeyCode = 56
let rightShift: CGKeyCode = 60

let defaults = UserDefaults.standard
/// 切り替え後にフォーカスを付け替えるか（CJKV 入力メソッドの不具合対策）。既定はオフ
let refocusKey = "refocusEnabled"
/// ABC に切り替える Shift の keyCode。既定は右 Shift
let abcShiftKey = "abcShift"

var abcShift: CGKeyCode {
  defaults.integer(forKey: abcShiftKey) == Int(leftShift) ? leftShift : rightShift
}

/// 単体押しした修飾キーの切り替え先と、フォーカス付け替えの対象か
func target(for keyCode: CGKeyCode) -> (id: String, cjkv: Bool)? {
  switch keyCode {
  case 55: return (qinggID, true)  // 左 ⌘ → 清歌
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
    NSLog("ImeSwitch: failed to create event tap")
    exit(1)
  }

  eventTap = tap
  CFRunLoopAddSource(
    CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
  CGEvent.tapEnable(tap: tap, enable: true)
}

// MARK: - メニュー

final class MenuHandler: NSObject {
  let refocusItem = NSMenuItem(
    title: "切换后刷新焦点（修复中日韩输入法不生效）", action: #selector(toggleRefocus), keyEquivalent: "")
  let leftShiftItem = NSMenuItem(title: "左 ⇧", action: #selector(chooseShift), keyEquivalent: "")
  let rightShiftItem = NSMenuItem(title: "右 ⇧", action: #selector(chooseShift), keyEquivalent: "")

  func makeMenu() -> NSMenu {
    let shiftMenu = NSMenu()
    leftShiftItem.tag = Int(leftShift)
    rightShiftItem.tag = Int(rightShift)
    for item in [refocusItem, leftShiftItem, rightShiftItem] { item.target = self }
    shiftMenu.addItem(leftShiftItem)
    shiftMenu.addItem(rightShiftItem)

    let shiftItem = NSMenuItem(title: "切换英文 (ABC) 的按键", action: nil, keyEquivalent: "")
    shiftItem.submenu = shiftMenu

    let menu = NSMenu()
    menu.addItem(refocusItem)
    menu.addItem(shiftItem)
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    updateStates()
    return menu
  }

  func updateStates() {
    refocusItem.state = defaults.bool(forKey: refocusKey) ? .on : .off
    leftShiftItem.state = abcShift == leftShift ? .on : .off
    rightShiftItem.state = abcShift == rightShift ? .on : .off
  }

  @objc func toggleRefocus() {
    defaults.set(!defaults.bool(forKey: refocusKey), forKey: refocusKey)
    updateStates()
  }

  @objc func chooseShift(_ sender: NSMenuItem) {
    defaults.set(sender.tag, forKey: abcShiftKey)
    updateStates()
  }
}

// MARK: - 起動

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let menuHandler = MenuHandler()
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "⌘"
statusItem.menu = menuHandler.makeMenu()

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
