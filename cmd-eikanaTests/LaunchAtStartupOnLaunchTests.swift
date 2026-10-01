//
//  LaunchAtStartupOnLaunchTests.swift
//  cmd-eikanaTests
//

import Foundation
import Testing

@testable import _英かな

/// 起動時の自動起動の処理（prepareLaunchAtStartupOnLaunch）を、場面ごとに、呼ばれる処理の順番と保存される値で確かめる。
/// 保存先はメモリの中だけで済ませ、OS に触る処理は記録するだけのものに差し替えるので、テストのホストの実設定には触らない
struct LaunchAtStartupOnLaunchTests {

  /// 読み書きをメモリの中だけで済ませる UserDefaults
  final class InMemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? {
      values[defaultName]
    }

    override func string(forKey defaultName: String) -> String? {
      values[defaultName] as? String
    }

    override func set(_ value: Any?, forKey defaultName: String) {
      values[defaultName] = value
    }

    override func set(_ value: Int, forKey defaultName: String) {
      values[defaultName] = value
    }

    override func removeObject(forKey defaultName: String) {
      values[defaultName] = nil
    }
  }

  /// 保存値を与えて起動時の処理を 1 回走らせ、呼ばれた処理を順に記録する
  final class Launch {
    let defaults = InMemoryDefaults(suiteName: nil)!
    var calls: [String] = []

    init(saved: [String: Any]) {
      defaults.values = saved
    }

    func run(version: String, registrationSucceeds: Bool) {
      prepareLaunchAtStartupOnLaunch(
        defaults: defaults,
        currentVersion: version,
        disableLegacyHelper: { self.calls.append("disableLegacyHelper") },
        register: { self.calls.append("register(\($0))") },
        isRegistered: { registrationSucceeds })
    }

    var lunchAtStartup: Int? { defaults.values["lunchAtStartup"] as? Int }
    var lastLaunchVersion: String? { defaults.values["lastLaunchVersion"] as? String }
  }

  // 新しく入れた人の初回起動: 既定でオンにして登録し、登録できたら版を記録する
  @Test func firstLaunchTurnsLaunchAtStartupOnAndRecordsTheVersion() {
    let launch = Launch(saved: [:])
    launch.run(version: "2.6.0", registrationSucceeds: true)

    #expect(launch.calls.first == "disableLegacyHelper")
    #expect(launch.calls.contains("register(true)"))
    #expect(launch.lunchAtStartup == 1)
    #expect(launch.lastLaunchVersion == "2.6.0")
  }

  // 2.5.2 から 2.6.0（自動起動オン）: 新方式で登録し直し、版を 2.6.0 として記録する
  @Test func upgradeFromLegacyVersionReregistersAndRecordsTheVersion() {
    let launch = Launch(saved: ["lunchAtStartup": 1, "lastLaunchVersion": "2.5.2"])
    launch.run(version: "2.6.0", registrationSucceeds: true)

    #expect(launch.calls == ["disableLegacyHelper", "register(true)"])
    #expect(launch.lastLaunchVersion == "2.6.0")
  }

  // 2.5.2 から 2.6.0（自動起動オン、登録に失敗）: 版を記録せず、次の起動で移行をやり直す
  @Test func failedReregistrationKeepsTheLegacyVersionForRetry() {
    let launch = Launch(saved: ["lunchAtStartup": 1, "lastLaunchVersion": "2.5.2"])
    launch.run(version: "2.6.0", registrationSucceeds: false)

    #expect(launch.calls == ["disableLegacyHelper", "register(true)"])
    #expect(launch.lastLaunchVersion == "2.5.2")
  }

  // 2.5.2 から 2.6.0（自動起動オフ）: 登録せず、版は記録する
  @Test func upgradeFromLegacyVersionWithLaunchAtStartupOffDoesNotRegister() {
    let launch = Launch(saved: ["lunchAtStartup": 0, "lastLaunchVersion": "2.5.2"])
    launch.run(version: "2.6.0", registrationSucceeds: false)

    #expect(launch.calls == ["disableLegacyHelper"])
    #expect(launch.lastLaunchVersion == "2.6.0")
  }

  // 2.6.0 から 2.6.1（保存値はオンだが、システム設定で外した人）: 登録し直さず、版は記録する
  @Test func upgradeWithinMainAppVersionsDoesNotRegisterAgain() {
    let launch = Launch(saved: ["lunchAtStartup": 1, "lastLaunchVersion": "2.6.0"])
    launch.run(version: "2.6.1", registrationSucceeds: false)

    #expect(launch.calls == ["disableLegacyHelper"])
    #expect(launch.lastLaunchVersion == "2.6.1")
  }

  // 同じ版での起動: 旧方式の無効化だけを行う
  @Test func launchWithTheSameVersionOnlyDisablesTheLegacyHelper() {
    let launch = Launch(saved: ["lunchAtStartup": 1, "lastLaunchVersion": "2.6.0"])
    launch.run(version: "2.6.0", registrationSucceeds: true)

    #expect(launch.calls == ["disableLegacyHelper"])
    #expect(launch.lastLaunchVersion == "2.6.0")
  }
}
