//
//  KeyEventTests.swift
//  cmd-eikanaTests
//

import Cocoa
import CoreGraphics
import Testing

@testable import _英かな

/// KeyEvent.handle にタップを通さず CGEvent を渡し、返るイベントと OS へ送られるキーを検証する。
/// 設定表と送信処理はインスタンスに差し替えるので、グローバル状態には触らない
struct KeyEventTests {

  // MARK: - Helper

  static let command = CGEventFlags.maskCommand
  static let shift = CGEventFlags.maskShift

  /// 送信処理を記録に置き換えた KeyEvent
  final class Harness {
    let keyEvent = KeyEvent()
    var postedShortcuts: [KeyboardShortcut] = []
    var postedKeyDowns: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []

    init(mappings: [KeyMapping]) {
      let table = KeyMappingListEditor.shortcutTable(from: mappings)
      keyEvent.shortcutTable = { table }
      keyEvent.postShortcut = { [unowned self] in self.postedShortcuts.append($0) }
      keyEvent.postKeyDown = { [unowned self] in self.postedKeyDowns.append(($0, $1)) }
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
      keyEvent.handle(type: type, event: event)?.takeUnretainedValue()
    }
  }

  func mapping(
    input: (keyCode: UInt16, flags: CGEventFlags), output: (keyCode: UInt16, flags: CGEventFlags)
  ) -> KeyMapping {
    KeyMapping(
      input: KeyboardShortcut(keyCode: CGKeyCode(input.keyCode), flags: input.flags),
      output: KeyboardShortcut(keyCode: CGKeyCode(output.keyCode), flags: output.flags))
  }

  func mapping(input: UInt16, output: UInt16) -> KeyMapping {
    mapping(input: (input, []), output: (output, []))
  }

  func keyEvent(_ keyCode: UInt16, down: Bool, flags: CGEventFlags = []) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down)!
    event.flags = flags
    return event
  }

  /// 修飾キーの flagsChanged。flags は変化後の状態
  func flagsChanged(_ keyCode: UInt16, flags: CGEventFlags) -> CGEvent {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
    event.type = .flagsChanged
    event.flags = flags
    return event
  }

  /// メディアキーの NX_SYSDEFINED イベント
  func mediaKeyEvent(keyType: Int32, down: Bool) -> CGEvent {
    let data1 = (Int(keyType) << 16) | ((down ? 0x0a : 0x0b) << 8)
    let nsEvent = NSEvent.otherEvent(
      with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
      context: nil, subtype: 8, data1: data1, data2: -1)!
    return nsEvent.cgEvent!
  }

  func keyCode(of event: CGEvent?) -> Int64? {
    event?.getIntegerValueField(.keyboardEventKeycode)
  }

  // MARK: - keyDown / keyUp の変換

  @Test func mappedKeyDownIsRewrittenInPlace() {
    let harness = Harness(mappings: [mapping(input: 0, output: 11)])
    let event = keyEvent(0, down: true)

    let result = harness.handle(.keyDown, event)

    #expect(result === event)
    #expect(keyCode(of: result) == 11)
  }

  @Test func mappedKeyUpIsRewrittenInPlace() {
    let harness = Harness(mappings: [mapping(input: 0, output: 11)])
    let result = harness.handle(.keyUp, keyEvent(0, down: false))
    #expect(keyCode(of: result) == 11)
  }

  @Test func unmappedKeyDownPassesThroughUnchanged() {
    let harness = Harness(mappings: [mapping(input: 0, output: 11)])
    let event = keyEvent(1, down: true)

    let result = harness.handle(.keyDown, event)

    #expect(result === event)
    #expect(keyCode(of: result) == 1)
    #expect(harness.postedShortcuts.isEmpty)
  }

  @Test func keyMappedToDisableIsDropped() {
    let harness = Harness(mappings: [mapping(input: 0, output: UInt16(disableKeyCode))])
    #expect(harness.handle(.keyDown, keyEvent(0, down: true)) == nil)
    #expect(harness.handle(.keyUp, keyEvent(0, down: false)) == nil)
  }

  @Test func conversionReplacesInputModifiersWithOutputModifiers() {
    let harness = Harness(
      mappings: [mapping(input: (0, Self.command), output: (11, Self.shift))])
    let result = harness.handle(.keyDown, keyEvent(0, down: true, flags: Self.command))

    #expect(keyCode(of: result) == 11)
    #expect(result?.flags.contains(Self.command) == false)
    #expect(result?.flags.contains(Self.shift) == true)
  }

  @Test func keyWithoutRequiredModifierIsNotConverted() {
    let harness = Harness(
      mappings: [mapping(input: (0, Self.command), output: (11, []))])
    let result = harness.handle(.keyDown, keyEvent(0, down: true))
    #expect(keyCode(of: result) == 0)
  }

  // MARK: - 修飾キー単体押し

  @Test func commandTapPostsMappedKey() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])

    let down = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    let up = harness.handle(.flagsChanged, flagsChanged(55, flags: []))

    #expect(down != nil && up != nil)
    #expect(harness.postedShortcuts.count == 1)
    #expect(harness.postedShortcuts.first?.keyCode == 102)
    #expect(harness.postedShortcuts.first?.flags.contains(Self.command) == false)
  }

  @Test func flagsChangedEventsPassThroughUnchanged() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    let down = flagsChanged(55, flags: Self.command)

    let result = harness.handle(.flagsChanged, down)

    #expect(result === down)
    #expect(keyCode(of: result) == 55)
  }

  @Test func unmappedModifierTapPostsNothing() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    _ = harness.handle(.flagsChanged, flagsChanged(54, flags: Self.command))
    _ = harness.handle(.flagsChanged, flagsChanged(54, flags: []))
    #expect(harness.postedShortcuts.isEmpty)
  }

  @Test func keyPressedWhileModifierHeldCancelsTap() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    _ = harness.handle(.keyDown, keyEvent(0, down: true, flags: Self.command))
    _ = harness.handle(.keyUp, keyEvent(0, down: false, flags: Self.command))
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: []))
    #expect(harness.postedShortcuts.isEmpty)
  }

  @Test func otherEventWhileModifierHeldCancelsTap() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    _ = harness.handle(.leftMouseDown, keyEvent(0, down: true))
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: []))
    #expect(harness.postedShortcuts.isEmpty)
  }

  @Test func flagsChangedOfNonModifierKeyPassesThroughAndCancelsTap() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    let globe = flagsChanged(179, flags: Self.command)

    let result = harness.handle(.flagsChanged, globe)
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: []))

    #expect(result === globe)
    #expect(harness.postedShortcuts.isEmpty)
  }

  // MARK: - 除外アプリ

  @Test func exclusionAppPassesEverythingThroughUnchanged() {
    let harness = Harness(mappings: [
      mapping(input: 0, output: 11), mapping(input: 55, output: 102),
    ])
    harness.keyEvent.isExclusionApp = true

    let keyResult = harness.handle(.keyDown, keyEvent(0, down: true))
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: []))

    #expect(keyCode(of: keyResult) == 0)
    #expect(harness.postedShortcuts.isEmpty)
  }

  @Test func exclusionAppEventCancelsPendingTap() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    harness.keyEvent.isExclusionApp = true
    _ = harness.handle(.keyDown, keyEvent(0, down: true))
    harness.keyEvent.isExclusionApp = false
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: []))
    #expect(harness.postedShortcuts.isEmpty)
  }

  // MARK: - メディアキー

  @Test func mappedMediaKeyDownPostsKeyAndIsDropped() {
    let soundUp = UInt16(mediaKeyCodeOffset + Int(NX_KEYTYPE_SOUND_UP))
    let harness = Harness(mappings: [mapping(input: soundUp, output: 102)])

    let result = harness.handle(.null, mediaKeyEvent(keyType: NX_KEYTYPE_SOUND_UP, down: true))

    #expect(result == nil)
    #expect(harness.postedKeyDowns.count == 1)
    #expect(harness.postedKeyDowns.first?.keyCode == 102)
  }

  @Test func mediaKeyUpPassesThrough() {
    let soundUp = UInt16(mediaKeyCodeOffset + Int(NX_KEYTYPE_SOUND_UP))
    let harness = Harness(mappings: [mapping(input: soundUp, output: 102)])
    let event = mediaKeyEvent(keyType: NX_KEYTYPE_SOUND_UP, down: false)

    let result = harness.handle(.null, event)

    #expect(result === event)
    #expect(harness.postedKeyDowns.isEmpty)
  }

  @Test func unmappedMediaKeyPassesThrough() {
    let harness = Harness(mappings: [mapping(input: 0, output: 11)])
    let event = mediaKeyEvent(keyType: NX_KEYTYPE_PLAY, down: true)

    let result = harness.handle(.null, event)

    #expect(result === event)
    #expect(harness.postedKeyDowns.isEmpty)
  }

  @Test func mediaKeyMappedToDisableIsDropped() {
    let play = UInt16(mediaKeyCodeOffset + Int(NX_KEYTYPE_PLAY))
    let harness = Harness(mappings: [mapping(input: play, output: UInt16(disableKeyCode))])
    #expect(harness.handle(.null, mediaKeyEvent(keyType: NX_KEYTYPE_PLAY, down: true)) == nil)
    #expect(harness.postedKeyDowns.isEmpty)
  }

  @Test func mediaKeyCancelsPendingTap() {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    _ = harness.handle(.null, mediaKeyEvent(keyType: NX_KEYTYPE_PLAY, down: true))
    _ = harness.handle(.null, mediaKeyEvent(keyType: NX_KEYTYPE_PLAY, down: false))
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: []))
    #expect(harness.postedShortcuts.isEmpty)
  }

  // MARK: - タップの無効化通知

  @Test(arguments: [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput])
  func tapDisabledNotificationIsSwallowed(type: CGEventType) {
    let harness = Harness(mappings: [])
    #expect(harness.handle(type, keyEvent(0, down: true)) == nil)
  }

  // 無効化されている間の操作（⌘+C など）はタップに届かない。無効化の知らせを「間に操作があったかもしれない」合図として扱い、
  // 修飾キーを離しても単体押しにしない
  @Test(arguments: [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput])
  func tapDisabledWhileModifierHeldCancelsTap(type: CGEventType) {
    let harness = Harness(mappings: [mapping(input: 55, output: 102)])
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: Self.command))
    _ = harness.handle(type, keyEvent(0, down: true))
    _ = harness.handle(.flagsChanged, flagsChanged(55, flags: []))
    #expect(harness.postedShortcuts.isEmpty)
  }
}
