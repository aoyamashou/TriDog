//
//  StartupSettings.swift
//  ⌘英かな
//
//  MIT License
//  Copyright (c) 2016 iMasanari
//

import CoreGraphics
import Foundation

/// 起動時に UserDefaults から読んだ値の解釈。UserDefaults 自体やグローバル状態には依存しない
enum StartupSettings {
  /// 初期設定（左右のコマンドキー単体で英数/かな）
  static var defaultMappings: [KeyMapping] {
    [
      KeyMapping(input: KeyboardShortcut(keyCode: 55), output: KeyboardShortcut(keyCode: 102)),
      KeyMapping(input: KeyboardShortcut(keyCode: 54), output: KeyboardShortcut(keyCode: 104)),
    ]
  }

  /// キー設定をどこから得たか
  enum MappingsSource: Equatable {
    /// 保存されている "mappings" を復元した
    case saved
    /// v2.0.x の "oneShotModifiers" から移行した
    case migratedFromOneShotModifiers
    /// 保存が無く、初期設定を使った
    case defaults
  }

  /// キー設定の読み込み結果
  struct Mappings {
    let list: [KeyMapping]
    let source: MappingsSource
  }

  /// 「ログイン後にこのアプリを起動」の保存値の解釈
  struct LaunchAtStartup: Equatable {
    /// 自動起動がオンか
    let enabled: Bool
    /// 保存値が無い初回起動か。初回は既定でオンにして保存する
    let isFirstLaunch: Bool
  }

  /// "lunchAtStartup" の保存値を解釈する。未保存なら初回起動としてオン、保存値は 1 ならオン
  static func launchAtStartup(saved: Any?) -> LaunchAtStartup {
    guard let saved = saved else {
      return LaunchAtStartup(enabled: true, isFirstLaunch: true)
    }

    let value: Int
    if let number = saved as? NSNumber {
      value = number.intValue
    } else if let text = saved as? String {
      value = Int(text) ?? 0
    } else {
      value = 0
    }

    return LaunchAtStartup(enabled: value == 1, isFirstLaunch: false)
  }

  /// 旧設定「起動時にアップデートを確認」（"checkUpdateAtlaunch"）を Sparkle の自動確認設定へ引き継ぐ値。
  /// 保存値が整数でなければ nil（引き継ぐものが無い）
  static func legacyAutomaticUpdateCheck(saved: Any?) -> Bool? {
    guard let value = saved as? Int else {
      return nil
    }

    return value == 1
  }

  /// テストのホストとして起動されたか。Xcode はテストを走らせるアプリに XCTestConfigurationFilePath を渡す
  static func isRunningAsTestHost(environment: [String: String]) -> Bool {
    environment["XCTestConfigurationFilePath"] != nil
  }

  /// "exclusionApps" の保存値から除外アプリの一覧を復元する。形式が合わない項目は捨て、配列でなければ空
  static func exclusionApps(from saved: Any?) -> [AppData] {
    guard let entries = saved as? [[AnyHashable: Any]] else {
      return []
    }

    return entries.compactMap { AppData(dictionary: $0) }
  }

  /// 除外アプリの一覧から、bundle ID で名前を引く辞書を作る
  static func exclusionAppsDict(_ list: [AppData]) -> [String: String] {
    var dict: [String: String] = [:]

    for app in list {
      dict[app.id] = app.name
    }

    return dict
  }

  /// "mappings" の保存値があればそれを復元する。無ければ v2.0.x の "oneShotModifiers" から移行し、
  /// どちらも無ければ初期設定を使う。形式が合わない項目は捨てる
  static func mappings(saved: Any?, oneShotModifiers: Any?) -> Mappings {
    if let entries = saved as? [[AnyHashable: Any]] {
      return Mappings(list: entries.compactMap { KeyMapping(dictionary: $0) }, source: .saved)
    }

    if let entries = oneShotModifiers as? [Any] {
      let list = entries.compactMap { entry -> KeyMapping? in
        guard let dictionary = entry as? [AnyHashable: Any],
          let inputKeyCodeInt = dictionary["input"] as? Int,
          let inputKeyCode = CGKeyCode(exactly: inputKeyCodeInt),
          let outputDictionary = dictionary["output"] as? [AnyHashable: Any],
          let output = KeyboardShortcut(dictionary: outputDictionary)
        else {
          return nil
        }

        return KeyMapping(input: KeyboardShortcut(keyCode: inputKeyCode), output: output)
      }
      return Mappings(list: list, source: .migratedFromOneShotModifiers)
    }

    return Mappings(list: defaultMappings, source: .defaults)
  }
}
