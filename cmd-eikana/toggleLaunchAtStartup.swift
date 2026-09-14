//
//  toggleLaunchAtStartup.swift
//  ⌘英かな
//
//  MIT License
//  Copyright (c) 2016 iMasanari
//

// ログイン項目に追加、またはそこから削除するための関数

import Cocoa
import ServiceManagement

/// バージョンアップ時に自動起動設定を再登録すべきか判定する
/// - Parameters:
///   - lastVersion: 前回起動時のバージョン（初回起動時はnil）
///   - currentVersion: 現在のバージョン
///   - launchAtStartupEnabled: 自動起動設定がオンか
/// - Returns: 再登録すべきならtrue
func shouldReregisterLaunchAtStartup(
  lastVersion: String?,
  currentVersion: String?,
  launchAtStartupEnabled: Bool
) -> Bool {
  guard lastVersion != currentVersion else { return false }
  return launchAtStartupEnabled
}

/// 本体自身をログイン項目に登録、または登録を解除する（macOS 13 以降の SMAppService.mainApp）
func setLaunchAtStartup(_ enabled: Bool) {
  do {
    if enabled {
      try SMAppService.mainApp.register()
      print("Successfully add login item.")
    } else {
      try SMAppService.mainApp.unregister()
      print("Successfully remove login item.")
    }
  } catch {
    print("Failed to \(enabled ? "add" : "remove") login item: \(error)")
  }
}
