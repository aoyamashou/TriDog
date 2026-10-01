//
//  KeyEvent.swift
//  ⌘英かな
//
//  MIT License
//  Copyright (c) 2016 iMasanari
//

import Cocoa

var activeAppsList: [AppData] = []
var exclusionAppsList: [AppData] = []

var exclusionAppsDict: [String: String] = [:]

class KeyEvent: NSObject {
  /// 修飾キー単体押しの追跡
  var modifierTap = ModifierTapTracker()
  var isExclusionApp = false
  let bundleId = Bundle.main.infoDictionary?["CFBundleIdentifier"] as! String
  var eventTap: CFMachPort?

  /// 変換に使う設定表。既定はグローバルの shortcutList を読む。テストでは差し替える
  var shortcutTable: () -> [CGKeyCode: [KeyMapping]] = { shortcutList }
  /// 修飾キー単体押しの変換結果を OS に送る（keyDown と keyUp）。テストでは記録するだけの関数に差し替える
  var postShortcut: (KeyboardShortcut) -> Void = { $0.postEvent() }
  /// メディアキーの変換結果を OS に送る（keyDown のみ）。テストでは記録するだけの関数に差し替える
  var postKeyDown: (CGKeyCode, CGEventFlags) -> Void = { keyCode, flags in
    let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
    keyDownEvent.flags = flags
    keyDownEvent.post(tap: CGEventTapLocation.cghidEventTap)
  }

  /// システムに無効化されたイベントタップを再有効化する。テストではタップを持たないので、記録するだけの関数に差し替える
  var reenableTap: (CFMachPort?) -> Void = { eventTap in
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }
  }

  override init() {
    super.init()
  }

  func start() {
    // 起動時点の最前面アプリで除外状態を決める。切り替え通知が来るまで判定されないと、除外アプリ上でも変換してしまう
    if let frontmostApp = NSWorkspace.shared.frontmostApplication {
      updateActiveApp(frontmostApp)
    }

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(KeyEvent.setActiveApp(_:)),
      name: NSWorkspace.didActivateApplicationNotification,
      object: nil)

    // Input Monitoring権限のチェック (macOS 10.15+)
    if #available(macOS 10.15, *) {
      if !CGPreflightListenEventAccess() {
        CGRequestListenEventAccess()
      }
    }

    // Accessibility権限のチェック
    let checkOptionPrompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
    let options: CFDictionary = [checkOptionPrompt: true] as NSDictionary

    if !AXIsProcessTrustedWithOptions(options) {
      // アクセシビリティに設定されていない場合、設定されるまでループで待つ
      Timer.scheduledTimer(
        timeInterval: 1.0,
        target: self,
        selector: #selector(KeyEvent.watchAXIsProcess(_:)),
        userInfo: nil,
        repeats: true)
    } else {
      self.watch()
    }
  }

  @objc func watchAXIsProcess(_ timer: Timer) {
    // macOS 10.15+ではInput Monitoring権限も確認
    if #available(macOS 10.15, *) {
      if AXIsProcessTrusted() && CGPreflightListenEventAccess() {
        timer.invalidate()
        self.watch()
      }
    } else {
      if AXIsProcessTrusted() {
        timer.invalidate()
        self.watch()
      }
    }
  }

  @objc func setActiveApp(_ notification: NSNotification) {
    let app = notification.userInfo!["NSWorkspaceApplicationKey"] as! NSRunningApplication

    updateActiveApp(app)
  }

  /// 最前面になったアプリに合わせて、除外状態と最近使ったアプリの一覧を更新する
  private func updateActiveApp(_ app: NSRunningApplication) {
    if let name = app.localizedName, let id = app.bundleIdentifier {
      let update = ActiveAppTracker.update(
        recentApps: activeAppsList, activatedName: name, activatedId: id,
        selfBundleId: bundleId, exclusionAppsDict: exclusionAppsDict)

      isExclusionApp = update.isExclusion
      activeAppsList = update.recentApps
    }
  }

  func watch() {
    // マウスのドラッグバグ回避のため、NSEventとCGEventを併用
    // CGEventのみでやる方法を捜索中
    let nsEventMaskList: NSEvent.EventTypeMask = [
      .leftMouseDown,
      .leftMouseUp,
      .rightMouseDown,
      .rightMouseUp,
      .otherMouseDown,
      .otherMouseUp,
      .scrollWheel,
    ]

    NSEvent.addGlobalMonitorForEvents(matching: nsEventMaskList) { _ in
      self.modifierTap.cancel()
    }

    NSEvent.addLocalMonitorForEvents(matching: nsEventMaskList) { (event: NSEvent) -> NSEvent? in
      self.modifierTap.cancel()
      return event
    }

    let eventMaskList = [
      CGEventType.keyDown.rawValue,
      CGEventType.keyUp.rawValue,
      CGEventType.flagsChanged.rawValue,
      UInt32(NX_SYSDEFINED),  // Media key Event
    ]
    var eventMask: UInt32 = 0

    for mask in eventMaskList {
      eventMask |= (1 << mask)
    }

    let observer = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: {
          (
            proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
            refcon: UnsafeMutableRawPointer?
          ) -> Unmanaged<CGEvent>? in
          if let observer = refcon {
            let mySelf = Unmanaged<KeyEvent>.fromOpaque(observer).takeUnretainedValue()
            return mySelf.eventCallback(proxy: proxy, type: type, event: event)
          }
          return Unmanaged.passUnretained(event)
        },
        userInfo: observer
      )
    else {
      print("failed to create event tap")
      exit(1)
    }

    self.eventTap = eventTap

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<
    CGEvent
  >? {
    return handle(type: type, event: event)
  }

  /// タップから受け取ったイベントを処理する。返したイベントが OS に渡り、nil なら捨てられる
  func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    // タイムアウト等でシステムに無効化されたイベントタップを再有効化する
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      // 無効化されている間の操作（⌘+C など）は届かないので、修飾キー単体押しの追跡を取り消す
      modifierTap.cancel()
      reenableTap(eventTap)
      return nil
    }

    if isExclusionApp {
      // 除外アプリでの操作も、修飾キー単体押しの追跡を取り消す対象
      modifierTap.cancel()
      return Unmanaged.passUnretained(event)
    }

    if let mediaKeyEvent = MediaKeyEvent(event) {
      return mediaKeyEvent.keyDown ? mediaKeyDown(mediaKeyEvent) : mediaKeyUp(mediaKeyEvent)
    }

    switch type {
    case .flagsChanged:
      let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

      guard let isDown = KeyConverter.modifierKeyState(keyCode: keyCode, flags: event.flags) else {
        // 修飾キーとして扱わないキー（Globe キーなど）の flagsChanged も、他の操作として追跡を取り消す
        modifierTap.cancel()
        return Unmanaged.passUnretained(event)
      }
      return isDown ? modifierKeyDown(event) : modifierKeyUp(event)

    case .keyDown:
      return keyDown(event)

    case .keyUp:
      return keyUp(event)

    default:
      modifierTap.cancel()

      return Unmanaged.passUnretained(event)
    }
  }

  func keyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    #if DEBUG
      print(KeyboardShortcut(event).toString())
    #endif

    modifierTap.cancel()

    if let keyTextField = activeKeyTextField {
      keyTextField.shortcut = KeyboardShortcut(event)
      keyTextField.stringValue = keyTextField.shortcut!.toString()

      return nil
    }

    return convertIfMapped(event)
  }

  func keyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    modifierTap.cancel()

    return convertIfMapped(event)
  }

  /// 設定に一致すればイベントの keyCode と flags を変換先に書き換えて返す（Disable なら nil）。
  /// 一致しなければ元のイベントをそのまま返す
  private func convertIfMapped(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let shortcut = KeyboardShortcut(event)

    switch KeyConverter.resolve(
      shortcut: shortcut, lookupKeyCode: shortcut.keyCode, in: shortcutTable())
    {
    case .passThrough:
      return Unmanaged.passUnretained(event)
    case .disable:
      return nil
    case .convert(let keyCode, let flags):
      event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
      event.flags = flags
      return Unmanaged.passUnretained(event)
    }
  }

  func modifierKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    #if DEBUG
      print(KeyboardShortcut(event).toString())
    #endif

    modifierTap.modifierDown(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))

    if let keyTextField = activeKeyTextField, keyTextField.isAllowModifierOnly {
      let shortcut = KeyboardShortcut(event)

      keyTextField.shortcut = shortcut
      keyTextField.stringValue = shortcut.toString()
    }

    return Unmanaged.passUnretained(event)
  }

  /// 修飾キーが単体で押されて離されたら、その設定に従ってキーを送る。元の flagsChanged イベントはそのまま通す
  func modifierKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let isTap = modifierTap.modifierUp(CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))

    if activeKeyTextField == nil, isTap {
      let shortcut = KeyboardShortcut(event)

      if case .convert(let keyCode, let flags) = KeyConverter.resolve(
        shortcut: shortcut, lookupKeyCode: shortcut.keyCode, in: shortcutTable())
      {
        postShortcut(KeyboardShortcut(keyCode: keyCode, flags: flags))
      }
    }

    return Unmanaged.passUnretained(event)
  }

  func mediaKeyDown(_ mediaKeyEvent: MediaKeyEvent) -> Unmanaged<CGEvent>? {
    modifierTap.cancel()

    // オフセットを足した keyCode が型に収まらないメディアキーは、設定の対象外としてそのまま通す
    guard let mappingKeyCode = KeyConverter.mediaKeyMappingKeyCode(keyType: mediaKeyEvent.keyCode)
    else {
      return Unmanaged.passUnretained(mediaKeyEvent.event)
    }

    #if DEBUG
      print(KeyboardShortcut(keyCode: mappingKeyCode, flags: mediaKeyEvent.flags).toString())
    #endif

    if let keyTextField = activeKeyTextField {
      // 出力欄はメディアキーを受け付けない（出力として送れないため）。記録しない操作は OS にそのまま通す
      guard keyTextField.isAllowModifierOnly else {
        return Unmanaged.passUnretained(mediaKeyEvent.event)
      }

      keyTextField.shortcut = KeyboardShortcut(keyCode: mappingKeyCode, flags: mediaKeyEvent.flags)
      keyTextField.stringValue = keyTextField.shortcut!.toString()

      return nil
    }

    // メディアキーは keyCode を持たないので、修飾フラグだけを照合に使い、設定表はオフセット付きのキーコードで引く
    let shortcut = KeyboardShortcut(keyCode: 0, flags: mediaKeyEvent.flags)

    switch KeyConverter.resolve(
      shortcut: shortcut, lookupKeyCode: mappingKeyCode, in: shortcutTable())
    {
    case .passThrough:
      return Unmanaged.passUnretained(mediaKeyEvent.event)
    case .disable:
      return nil
    case .convert(let keyCode, let flags):
      postKeyDown(keyCode, flags)
      return nil
    }
  }

  func mediaKeyUp(_ mediaKeyEvent: MediaKeyEvent) -> Unmanaged<CGEvent>? {
    modifierTap.cancel()

    return Unmanaged.passUnretained(mediaKeyEvent.event)
  }
}

/// 出力側にこの keyCode を設定した項目は、入力キーを無効化する（何も送らない）
let disableKeyCode: CGKeyCode = 999

/// メディアキーは NX_KEYTYPE_* にこの値を足した keyCode で設定表と keyCodeDictionary を引く
let mediaKeyCodeOffset = 1000

let modifierMasks: [CGKeyCode: CGEventFlags] = [
  54: CGEventFlags.maskCommand,
  55: CGEventFlags.maskCommand,
  56: CGEventFlags.maskShift,
  60: CGEventFlags.maskShift,
  59: CGEventFlags.maskControl,
  62: CGEventFlags.maskControl,
  58: CGEventFlags.maskAlternate,
  61: CGEventFlags.maskAlternate,
  63: CGEventFlags.maskSecondaryFn,
  57: CGEventFlags.maskAlphaShift,
]
