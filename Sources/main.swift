//
//  main.swift
//  ImeSwitch — 修飾キー単体押しで入力ソースを直接切り替える（自用）
//
//  Based on ⌘英かな (cmd-eikana)
//  MIT License
//  Copyright (c) 2016 iMasanari
//

import Carbon
import Cocoa

// MARK: - 設定（ここだけ変えればよい）

/// 切り替え後に入力欄へ反映させる方法
enum Strategy {
  /// TISSelectInputSource のみ（キーボードレイアウト向け）
  case plain
  /// 選択後にフォーカスを一瞬自アプリへ移して戻す（CJKV 入力メソッドの不具合対策）
  case refocus
  /// 選択後 50ms でもう一度 TISSelectInputSource
  case reselect
  /// TIS を使わず かな キー(104) を送る（日本語専用、アクセシビリティ権限が必要）
  case kanaKey
}

struct Target {
  let id: String
  let strategy: Strategy
}

/// 単体押しした修飾キーの keyCode → 切り替え先
let targets: [CGKeyCode: Target] = [
  55: Target(id: "com.aodaren.inputmethod.Qingg", strategy: .refocus),  // 左 ⌘ → 清歌
  54: Target(id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", strategy: .refocus),  // 右 ⌘ → 日本語
  60: Target(id: "com.apple.keylayout.ABC", strategy: .plain),  // 右 ⇧ → ABC
]

// MARK: - 入力ソース

enum InputSource {
  static func find(_ id: String) -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource]
    else { return nil }
    // 清歌などは同じ ID で入力メソッド本体と入力モードの 2 件が返るので、選択できる方を使う
    return list.first { isSelectCapable($0) } ?? list.first
  }

  static func isSelectCapable(_ source: TISInputSource) -> Bool {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable)
    else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
  }

  static func currentID() -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
  }

  static func select(_ id: String) -> Bool {
    guard let source = find(id) else {
      NSLog("ImeSwitch: input source not found: \(id)")
      return false
    }
    return TISSelectInputSource(source) == noErr
  }
}

// MARK: - フォーカスの付け替え（CJKV 対策）

/// key になれる 1×1 の透明ウィンドウ
final class FocusWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

final class Refocuser {
  private lazy var window: FocusWindow = {
    let window = FocusWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.alphaValue = 0.01
    window.level = .floating
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    return window
  }()

  /// 最前面のアプリからフォーカスを一瞬奪い、すぐに返す。入力欄が戻ってきた時点で現在の入力ソースを読み直す
  func bounce() {
    guard let previous = NSWorkspace.shared.frontmostApplication,
      previous.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return }

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
      self.window.orderOut(nil)
      previous.activate()
    }
  }
}

// MARK: - 修飾キー単体押しの検出

let modifierMasks: [CGKeyCode: CGEventFlags] = [
  54: .maskCommand, 55: .maskCommand,
  56: .maskShift, 60: .maskShift,
  59: .maskControl, 62: .maskControl,
  58: .maskAlternate, 61: .maskAlternate,
  63: .maskSecondaryFn, 57: .maskAlphaShift,
]

final class Switcher {
  private var eventTap: CFMachPort?
  /// 押されたまま他の操作が無い修飾キー
  private var pressedKeyCode: CGKeyCode?
  private let refocuser = Refocuser()

  func start() {
    if CGPreflightListenEventAccess() {
      watch()
      return
    }
    CGRequestListenEventAccess()
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
      if CGPreflightListenEventAccess() {
        timer.invalidate()
        self.watch()
      }
    }
  }

  private func watch() {
    let types: [CGEventType] = [
      .flagsChanged, .keyDown,
      .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
    ]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, type, event, refcon in
          let switcher = Unmanaged<Switcher>.fromOpaque(refcon!).takeUnretainedValue()
          switcher.handle(type: type, event: event)
          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      NSLog("ImeSwitch: failed to create event tap")
      NSApp.terminate(nil)
      return
    }

    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func handle(type: CGEventType, event: CGEvent) {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      pressedKeyCode = nil
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }

    case .flagsChanged:
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
      guard let mask = modifierMasks[keyCode] else {
        pressedKeyCode = nil
        return
      }
      if event.flags.contains(mask) {
        // 別の修飾キーを押している最中なら組み合わせ操作とみなす
        pressedKeyCode = pressedKeyCode == nil ? keyCode : nil
      } else {
        let isTap = pressedKeyCode == keyCode
        pressedKeyCode = nil
        if isTap, let target = targets[keyCode] {
          // タップ処理の中で TIS を呼ぶとタップがタイムアウトしやすいので、次のループで行う
          DispatchQueue.main.async { self.switchTo(target) }
        }
      }

    default:
      pressedKeyCode = nil
    }
  }

  private func switchTo(_ target: Target) {
    if target.strategy == .kanaKey {
      postKey(104)
      return
    }
    if InputSource.currentID() == target.id { return }
    guard InputSource.select(target.id) else { return }

    switch target.strategy {
    case .plain, .kanaKey:
      break
    case .refocus:
      refocuser.bounce()
    case .reselect:
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
        _ = InputSource.select(target.id)
      }
    }
  }

  private func postKey(_ keyCode: CGKeyCode) {
    if !CGPreflightPostEventAccess() {
      CGRequestPostEventAccess()
      return
    }
    CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)?.post(tap: .cghidEventTap)
  }
}

// MARK: - アプリ

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let switcher = Switcher()

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem.button?.title = "⌘"
    let menu = NSMenu()
    menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem.menu = menu

    switcher.start()
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
