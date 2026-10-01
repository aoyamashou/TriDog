//
//  StartupSettingsTests.swift
//  cmd-eikanaTests
//

import CoreGraphics
import Foundation
import Testing

@testable import _英かな

struct StartupSettingsTests {

  // MARK: - Helper

  func shortcutDictionary(keyCode: Int, flags: Int = 0) -> [AnyHashable: Any] {
    ["keyCode": keyCode, "flags": flags]
  }

  func mappingDictionary(input: Int, output: Int, enable: Bool = true) -> [AnyHashable: Any] {
    [
      "input": shortcutDictionary(keyCode: input),
      "output": shortcutDictionary(keyCode: output),
      "enable": enable,
    ]
  }

  func pairs(_ list: [KeyMapping]) -> [[UInt16]] {
    list.map { [$0.input.keyCode, $0.output.keyCode] }
  }

  // MARK: - 自動起動の保存値

  @Test func launchAtStartupWithoutSavedValueIsFirstLaunchAndEnabled() {
    let result = StartupSettings.launchAtStartup(saved: nil)
    #expect(result == StartupSettings.LaunchAtStartup(enabled: true, isFirstLaunch: true))
  }

  @Test(arguments: [(1, true), (0, false), (2, false), (-1, false)])
  func launchAtStartupReadsSavedInteger(saved: Int, enabled: Bool) {
    let result = StartupSettings.launchAtStartup(saved: saved)
    #expect(result == StartupSettings.LaunchAtStartup(enabled: enabled, isFirstLaunch: false))
  }

  @Test func launchAtStartupTreatsBoolAndNumericStringLikeInteger() {
    #expect(StartupSettings.launchAtStartup(saved: true).enabled == true)
    #expect(StartupSettings.launchAtStartup(saved: false).enabled == false)
    #expect(StartupSettings.launchAtStartup(saved: "1").enabled == true)
    #expect(StartupSettings.launchAtStartup(saved: "0").enabled == false)
  }

  @Test func launchAtStartupWithUnreadableValueIsOffButNotFirstLaunch() {
    let result = StartupSettings.launchAtStartup(saved: "foo")
    #expect(result == StartupSettings.LaunchAtStartup(enabled: false, isFirstLaunch: false))
  }

  @Test func launchAtStartupWithNonScalarValueIsOffButNotFirstLaunch() {
    // 数値でも文字列でもない保存値（配列や辞書）は、integer(forKey:) と同じく 0 扱い
    let result = StartupSettings.launchAtStartup(saved: [1])
    #expect(result == StartupSettings.LaunchAtStartup(enabled: false, isFirstLaunch: false))
  }

  // MARK: - 旧設定「起動時にアップデートを確認」

  @Test func legacyUpdateCheckIsNilWhenNotSaved() {
    #expect(StartupSettings.legacyAutomaticUpdateCheck(saved: nil) == nil)
  }

  @Test(arguments: [(1, true), (0, false), (2, false)])
  func legacyUpdateCheckIsTrueOnlyForOne(saved: Int, expected: Bool) {
    #expect(StartupSettings.legacyAutomaticUpdateCheck(saved: saved) == expected)
  }

  @Test func legacyUpdateCheckIgnoresNonIntegerValues() {
    #expect(StartupSettings.legacyAutomaticUpdateCheck(saved: "1") == nil)
    #expect(StartupSettings.legacyAutomaticUpdateCheck(saved: 1.0) == nil)
  }

  // MARK: - テストのホストとしての起動

  @Test func testHostIsDetectedFromTheXCTestEnvironment() {
    #expect(
      StartupSettings.isRunningAsTestHost(environment: ["XCTestConfigurationFilePath": "/tmp/x"]))
    #expect(StartupSettings.isRunningAsTestHost(environment: [:]) == false)
  }

  // このテスト自体がテストのホストの中で動いているので、本物の環境変数でも判定されることを確かめる。
  // 判定できていないと、テストのたびにアクセシビリティのダイアログが出る
  @Test func thisTestRunIsDetectedAsTestHost() {
    #expect(StartupSettings.isRunningAsTestHost(environment: ProcessInfo.processInfo.environment))
  }

  // MARK: - 除外アプリ

  @Test func exclusionAppsFromNilIsEmpty() {
    #expect(StartupSettings.exclusionApps(from: nil).isEmpty)
  }

  @Test func exclusionAppsFromNonArrayIsEmpty() {
    #expect(StartupSettings.exclusionApps(from: "foo").isEmpty)
    #expect(StartupSettings.exclusionApps(from: ["name": "A", "id": "a"]).isEmpty)
  }

  @Test func exclusionAppsRestoresNameAndIdInOrder() {
    let saved: [[AnyHashable: Any]] = [
      ["name": "A", "id": "com.example.a"],
      ["name": "B", "id": "com.example.b"],
    ]
    let list = StartupSettings.exclusionApps(from: saved)
    #expect(list.map { $0.id } == ["com.example.a", "com.example.b"])
    #expect(list.map { $0.name } == ["A", "B"])
  }

  @Test func exclusionAppsSkipsMalformedEntries() {
    let saved: [[AnyHashable: Any]] = [
      ["name": "A", "id": "com.example.a"],
      ["name": "no id"],
      ["id": 123, "name": "B"],
    ]
    let list = StartupSettings.exclusionApps(from: saved)
    #expect(list.map { $0.id } == ["com.example.a"])
  }

  @Test func exclusionAppsDictMapsIdToName() {
    let list = [AppData(name: "A", id: "com.example.a"), AppData(name: "B", id: "com.example.b")]
    let dict = StartupSettings.exclusionAppsDict(list)
    #expect(dict == ["com.example.a": "A", "com.example.b": "B"])
  }

  @Test func exclusionAppsDictLetsLaterDuplicateWin() {
    let list = [
      AppData(name: "old", id: "com.example.a"), AppData(name: "new", id: "com.example.a"),
    ]
    #expect(StartupSettings.exclusionAppsDict(list) == ["com.example.a": "new"])
  }

  // MARK: - キー設定: 保存値あり

  @Test func savedMappingsAreRestored() {
    let saved = [
      mappingDictionary(input: 55, output: 102),
      mappingDictionary(input: 54, output: 104, enable: false),
    ]
    let result = StartupSettings.mappings(saved: saved, oneShotModifiers: nil)
    #expect(result.source == .saved)
    #expect(pairs(result.list) == [[55, 102], [54, 104]])
    #expect(result.list.map { $0.enable } == [true, false])
  }

  @Test func savedMappingsTakePriorityOverOneShotModifiers() {
    let saved = [mappingDictionary(input: 55, output: 102)]
    let oneShot: [[AnyHashable: Any]] = [["input": 54, "output": shortcutDictionary(keyCode: 104)]]
    let result = StartupSettings.mappings(saved: saved, oneShotModifiers: oneShot)
    #expect(result.source == .saved)
    #expect(pairs(result.list) == [[55, 102]])
  }

  @Test func savedEmptyArrayStaysEmptyWithoutDefaults() {
    let result = StartupSettings.mappings(saved: [[AnyHashable: Any]](), oneShotModifiers: nil)
    #expect(result.source == .saved)
    #expect(result.list.isEmpty)
  }

  @Test func savedMappingsSkipMalformedEntries() {
    let saved: [[AnyHashable: Any]] = [
      mappingDictionary(input: 55, output: 102),
      ["input": shortcutDictionary(keyCode: 54)],
      [
        "input": shortcutDictionary(keyCode: -1), "output": shortcutDictionary(keyCode: 104),
        "enable": true,
      ],
    ]
    let result = StartupSettings.mappings(saved: saved, oneShotModifiers: nil)
    #expect(pairs(result.list) == [[55, 102]])
  }

  @Test func savedValueOfWrongTypeIsTreatedAsAbsent() {
    let result = StartupSettings.mappings(saved: "foo", oneShotModifiers: nil)
    #expect(result.source == .defaults)
  }

  // MARK: - キー設定: v2.0.x からの移行

  @Test func oneShotModifiersAreMigrated() {
    let oneShot: [[AnyHashable: Any]] = [
      ["input": 55, "output": shortcutDictionary(keyCode: 102)],
      ["input": 54, "output": shortcutDictionary(keyCode: 104, flags: 131072)],
    ]
    let result = StartupSettings.mappings(saved: nil, oneShotModifiers: oneShot)
    #expect(result.source == .migratedFromOneShotModifiers)
    #expect(pairs(result.list) == [[55, 102], [54, 104]])
    #expect(result.list.map { $0.input.flags.rawValue } == [0, 0])
    #expect(result.list.map { $0.output.flags.rawValue } == [0, 131072])
    #expect(result.list.map { $0.enable } == [true, true])
  }

  @Test(arguments: [
    ["input": "55", "output": ["keyCode": 102, "flags": 0]] as [AnyHashable: Any],
    ["input": -1, "output": ["keyCode": 102, "flags": 0]],
    ["input": 65536, "output": ["keyCode": 102, "flags": 0]],
    ["input": 55],
    ["input": 55, "output": ["keyCode": 102]],
  ])
  func malformedOneShotModifierIsSkipped(entry: [AnyHashable: Any]) {
    let result = StartupSettings.mappings(saved: nil, oneShotModifiers: [entry])
    #expect(result.source == .migratedFromOneShotModifiers)
    #expect(result.list.isEmpty)
  }

  @Test func nonDictionaryOneShotEntryIsSkippedButOthersSurvive() {
    let oneShot: [Any] = ["foo", ["input": 55, "output": shortcutDictionary(keyCode: 102)]]
    let result = StartupSettings.mappings(saved: nil, oneShotModifiers: oneShot)
    #expect(result.source == .migratedFromOneShotModifiers)
    #expect(pairs(result.list) == [[55, 102]])
  }

  @Test func oneShotModifiersOfWrongTypeFallBackToDefaults() {
    let result = StartupSettings.mappings(saved: nil, oneShotModifiers: "foo")
    #expect(result.source == .defaults)
  }

  // MARK: - キー設定: 初期設定

  @Test func defaultsAreLeftAndRightCommandToEisuAndKana() {
    let result = StartupSettings.mappings(saved: nil, oneShotModifiers: nil)
    #expect(result.source == .defaults)
    #expect(pairs(result.list) == [[55, 102], [54, 104]])
    #expect(
      result.list.allSatisfy {
        $0.enable && $0.input.flags.rawValue == 0 && $0.output.flags.rawValue == 0
      })
  }

  @Test func defaultMappingsAreFreshInstancesEachTime() {
    let first = StartupSettings.defaultMappings
    let second = StartupSettings.defaultMappings
    #expect(first[0] !== second[0])
  }
}
