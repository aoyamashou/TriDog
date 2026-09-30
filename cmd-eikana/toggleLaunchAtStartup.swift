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

/// 2.5.x まで使っていた旧方式（ヘルパー経由の SMLoginItemSetEnabled）の登録を無効にする。
/// 旧方式の登録を無効にする手段はこの API しかないため、非推奨と承知で使っている（ビルド時に警告が出る）。
/// ヘルパーがバンドルに同梱されている間しか効かないので、ヘルパーを削除するときにこの関数も消す
func disableLegacyHelperLoginItem() {
  if !SMLoginItemSetEnabled("io.github.dominion525.cmd-eikana-helper" as CFString, false) {
    print("Failed to disable legacy helper login item.")
  }
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
