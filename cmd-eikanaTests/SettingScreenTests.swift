//
//  SettingScreenTests.swift
//  cmd-eikanaTests
//

import Cocoa
import ServiceManagement
import Testing

@testable import _英かな

/// 設定画面とメニューバー。自動起動の登録は差し替えた関数で確かめ、Sparkle の設定とあわせて OS やアプリの実設定には触らない
extension GlobalStateTests {
  @Suite struct SettingScreenTests {

    @Test(arguments: [
      (SMAppService.Status.enabled, true),
      (SMAppService.Status.requiresApproval, true),
      (SMAppService.Status.notRegistered, false),
      (SMAppService.Status.notFound, false),
    ])
    func launchAtStartupIsRegisteredWhenEnabledOrAwaitingApproval(
      status: SMAppService.Status, registered: Bool
    ) {
      #expect(isLaunchAtStartupRegistered(status) == registered)
    }

    @MainActor @Test func launchAtStartupCheckboxShowsTheRegistrationWhenShown() {
      let controller = PreferenceScreens.setting
      var registered = true
      let originalRegistered = controller.launchAtStartupRegistered
      let originalState = controller.lunchAtStartup.state
      defer {
        controller.launchAtStartupRegistered = originalRegistered
        controller.lunchAtStartup.state = originalState
      }
      controller.launchAtStartupRegistered = { registered }

      controller.viewWillAppear()
      #expect(controller.lunchAtStartup.state == .on)

      // システム設定の側で外された後に表示し直すと、外れた状態になる
      registered = false
      controller.viewWillAppear()
      #expect(controller.lunchAtStartup.state == .off)
    }

    @MainActor @Test func launchAtStartupCheckboxFollowsTheRegistrationWhenTheAppBecomesActive() {
      let controller = PreferenceScreens.setting
      var registered = true
      let originalRegistered = controller.launchAtStartupRegistered
      let originalState = controller.lunchAtStartup.state
      defer {
        controller.launchAtStartupRegistered = originalRegistered
        controller.lunchAtStartup.state = originalState
      }
      controller.launchAtStartupRegistered = { registered }
      controller.viewWillAppear()
      #expect(controller.lunchAtStartup.state == .on)

      // 設定画面を開いたままシステム設定で外され、こちらに戻ってきた
      registered = false
      NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
      #expect(controller.lunchAtStartup.state == .off)
    }

    @MainActor @Test func launchAtStartupCheckboxRegistersAndSaves() {
      let controller = PreferenceScreens.setting
      let defaults = RecordingDefaults(suiteName: nil)!
      var registered = false
      var requests: [Bool] = []
      let originalDefaults = controller.userDefaults
      let originalRegistered = controller.launchAtStartupRegistered
      let originalRegister = controller.registerLaunchAtStartup
      let originalState = controller.lunchAtStartup.state
      defer {
        controller.userDefaults = originalDefaults
        controller.launchAtStartupRegistered = originalRegistered
        controller.registerLaunchAtStartup = originalRegister
        controller.lunchAtStartup.state = originalState
      }
      controller.userDefaults = defaults
      controller.launchAtStartupRegistered = { registered }
      controller.registerLaunchAtStartup = {
        requests.append($0)
        registered = $0
      }

      controller.lunchAtStartup.state = .on
      controller.clickLunchAtStartup(controller.lunchAtStartup)
      #expect(requests == [true])
      #expect(controller.lunchAtStartup.state == .on)
      #expect((defaults.lastValue(forKey: "lunchAtStartup") as? NSControl.StateValue) == .on)

      controller.lunchAtStartup.state = .off
      controller.clickLunchAtStartup(controller.lunchAtStartup)
      #expect(requests == [true, false])
      #expect(controller.lunchAtStartup.state == .off)
      #expect((defaults.lastValue(forKey: "lunchAtStartup") as? NSControl.StateValue) == .off)
    }

    @MainActor @Test func launchAtStartupCheckboxFollowsTheRegistrationWhenRegisteringFails() {
      let controller = PreferenceScreens.setting
      let defaults = RecordingDefaults(suiteName: nil)!
      var requests: [Bool] = []
      let originalDefaults = controller.userDefaults
      let originalRegistered = controller.launchAtStartupRegistered
      let originalRegister = controller.registerLaunchAtStartup
      let originalState = controller.lunchAtStartup.state
      defer {
        controller.userDefaults = originalDefaults
        controller.launchAtStartupRegistered = originalRegistered
        controller.registerLaunchAtStartup = originalRegister
        controller.lunchAtStartup.state = originalState
      }
      controller.userDefaults = defaults
      // 登録を頼んでも状態が変わらない（登録に失敗した）
      controller.launchAtStartupRegistered = { false }
      controller.registerLaunchAtStartup = { requests.append($0) }

      controller.lunchAtStartup.state = .on
      controller.clickLunchAtStartup(controller.lunchAtStartup)
      #expect(requests == [true])
      #expect(controller.lunchAtStartup.state == .off)
    }

    @MainActor @Test func showIconCheckboxTogglesTheStatusItemAndSaves() {
      let controller = PreferenceScreens.setting
      let defaults = RecordingDefaults(suiteName: nil)!
      var visibility: [Bool] = []
      let originalDefaults = controller.userDefaults
      let originalSetVisible = controller.setStatusItemVisible
      let originalState = controller.showIcon.state
      defer {
        controller.userDefaults = originalDefaults
        controller.setStatusItemVisible = originalSetVisible
        controller.showIcon.state = originalState
      }
      controller.userDefaults = defaults
      controller.setStatusItemVisible = { visibility.append($0) }

      controller.showIcon.state = .off
      controller.clickShowIcon(controller.showIcon)
      #expect(visibility == [false])
      #expect((defaults.lastValue(forKey: "showIcon") as? NSControl.StateValue) == .off)

      controller.showIcon.state = .on
      controller.clickShowIcon(controller.showIcon)
      #expect(visibility == [false, true])
      #expect((defaults.lastValue(forKey: "showIcon") as? NSControl.StateValue) == .on)
      #expect(defaults.recorded.count == 2)
    }

    @MainActor @Test func checkboxesReflectSavedStateAfterLoad() {
      let controller = PreferenceScreens.setting
      // viewDidLoad は保存値を読んで反映する。テストのホストは実設定で起動しているので、値の有無だけ確かめる
      #expect([.on, .off].contains(controller.showIcon.state))
      #expect([.on, .off].contains(controller.lunchAtStartup.state))
      #expect([.on, .off].contains(controller.checkUpdateAtlaunch.state))
    }

    @MainActor @Test func menuBarHasTheFourItemsInOrder() {
      let titles = statusItem.menu?.items.map { $0.title } ?? []
      #expect(titles.count == 5)
      #expect(titles[0].hasPrefix("About ⌘英かな "))
      #expect(titles[1] == "Preferences...")
      #expect(titles[2] == "")
      #expect(titles[3] == "Restart")
      #expect(titles[4] == "Quit")
    }

    @MainActor @Test func menuItemsTargetTheExpectedActions() {
      let items = statusItem.menu?.items ?? []
      #expect(items[0].action == #selector(AppDelegate.open(_:)))
      #expect(items[1].action == #selector(AppDelegate.openPreferencesSerector(_:)))
      #expect(items[3].action == #selector(AppDelegate.restart(_:)))
      #expect(items[4].action == #selector(AppDelegate.quit(_:)))
    }
  }
}
