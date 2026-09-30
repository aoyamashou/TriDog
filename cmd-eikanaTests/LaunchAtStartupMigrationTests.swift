//
//  LaunchAtStartupMigrationTests.swift
//  cmd-eikanaTests
//
//  Copyright © 2025 eikana. All rights reserved.
//

import Testing

@testable import _英かな

struct LaunchAtStartupMigrationTests {

  // バージョンが同じ場合は再登録しない
  @Test func sameVersionShouldNotReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: "2.4.0",
      currentVersion: "2.4.0",
      launchAtStartupEnabled: true
    )
    #expect(result == false)
  }

  // バージョンが異なり、自動起動オンなら再登録する
  @Test func differentVersionWithEnabledShouldReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: "2.4.0",
      currentVersion: "2.4.1",
      launchAtStartupEnabled: true
    )
    #expect(result == true)
  }

  // バージョンが異なっても、自動起動オフなら再登録しない
  @Test func differentVersionWithDisabledShouldNotReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: "2.4.0",
      currentVersion: "2.4.1",
      launchAtStartupEnabled: false
    )
    #expect(result == false)
  }

  // 初回起動（lastVersion == nil）で自動起動オンなら再登録する
  @Test func firstLaunchWithEnabledShouldReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: nil,
      currentVersion: "2.4.1",
      launchAtStartupEnabled: true
    )
    #expect(result == true)
  }

  // 初回起動（lastVersion == nil）で自動起動オフなら再登録しない
  @Test func firstLaunchWithDisabledShouldNotReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: nil,
      currentVersion: "2.4.1",
      launchAtStartupEnabled: false
    )
    #expect(result == false)
  }

  // 旧方式の 2.5.x から新方式の 2.6.0 に上げたとき、自動起動オンなら再登録する
  @Test func upgradeFromLegacyVersionWithEnabledShouldReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: "2.5.2",
      currentVersion: "2.6.0",
      launchAtStartupEnabled: true
    )
    #expect(result == true)
  }

  // 新方式に移った後の更新では、自動起動オンでも再登録しない（システム設定で外した人を登録し直さない）
  @Test func upgradeWithinMainAppVersionsShouldNotReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: "2.6.0",
      currentVersion: "2.6.1",
      launchAtStartupEnabled: true
    )
    #expect(result == false)
  }

  // 版は数字として比べる（文字列の比較だと 2.10.0 が 2.6.0 より前になる）
  @Test func versionsAreComparedNumerically() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: "2.10.0",
      currentVersion: "2.10.1",
      launchAtStartupEnabled: true
    )
    #expect(result == false)
  }

  // 両方nilの場合（エッジケース）は再登録しない
  @Test func bothNilShouldNotReregister() {
    let result = shouldReregisterLaunchAtStartup(
      lastVersion: nil,
      currentVersion: nil,
      launchAtStartupEnabled: true
    )
    #expect(result == false)
  }
}
