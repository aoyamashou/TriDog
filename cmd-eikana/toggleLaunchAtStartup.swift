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

/// 自動起動を SMAppService.mainApp で登録するようになった最初のバージョン。これより前は旧方式（ヘルパー経由）
let firstMainAppLoginItemVersion = "2.6.0"

/// バージョンアップ時に自動起動設定を再登録すべきか判定する。
/// 旧方式から新方式へ移るときの 1 回だけ登録し、それ以降の更新では登録し直さない
/// （システム設定で外した利用者を、更新のたびに登録し直さないため）
/// - Parameters:
///   - lastVersion: 前回起動時のバージョン（記録が無いときはnil。2.4.0 以前からの更新か初回起動）
///   - currentVersion: 現在のバージョン
///   - launchAtStartupEnabled: 自動起動設定がオンか
/// - Returns: 再登録すべきならtrue
func shouldReregisterLaunchAtStartup(
  lastVersion: String?,
  currentVersion: String?,
  launchAtStartupEnabled: Bool
) -> Bool {
  guard lastVersion != currentVersion else { return false }
  if let lastVersion,
    lastVersion.compare(firstMainAppLoginItemVersion, options: .numeric) != .orderedAscending
  {
    return false
  }
  return launchAtStartupEnabled
}

/// 起動時に今回の版を「前回起動した版」として記録してよいか。
/// 移行の再登録をしたのに登録済みになっていなければ記録せず、次の起動でもう一度「移行」と判定させてやり直す
func shouldRecordLaunchVersion(reregistered: Bool, registeredAfterward: Bool) -> Bool {
  !reregistered || registeredAfterward
}

/// 自動起動が登録されているとみなす状態か。requiresApproval は登録済みで利用者の許可待ちなので、登録済みとして扱う
func isLaunchAtStartupRegistered(_ status: SMAppService.Status) -> Bool {
  status == .enabled || status == .requiresApproval
}

/// 本体自身がログイン項目に登録されているか（OS の登録状態を読む）
func launchAtStartupIsRegistered() -> Bool {
  isLaunchAtStartupRegistered(SMAppService.mainApp.status)
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
