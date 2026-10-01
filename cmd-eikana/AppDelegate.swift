//
//  AppDelegate.swift
//  ⌘英かな
//
//  MIT License
//  Copyright (c) 2016 iMasanari
//

import Cocoa
import Sparkle

var statusItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
var loginItem = NSMenuItem()

@main
class AppDelegate: NSObject, NSApplicationDelegate {

  var windowController: NSWindowController?
  var preferenceWindowController: PreferenceWindowController!
  let keyEvent = KeyEvent()
  // Sparkle。開始は起動処理の中で行う（旧設定の引き継ぎを先に済ませるため）
  let updaterController = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Insert code here to initialize your application

    ////////////////////////////
    // 保存データの読み込み
    ////////////////////////////

    let userDefaults = UserDefaults.standard

    // 旧方式の登録は自動起動のオン・オフに関係なく残っていることがあるので、起動のたびに無効にする
    disableLegacyHelperLoginItem()

    // 「ログイン後にこのアプリを起動」。初回起動は既定でオンにして保存する
    let launchAtStartup = StartupSettings.launchAtStartup(
      saved: userDefaults.object(forKey: "lunchAtStartup"))
    if launchAtStartup.isFirstLaunch {
      setLaunchAtStartup(true)
      userDefaults.set(1, forKey: "lunchAtStartup")
    }

    // 旧方式（2.6.0 より前）からの更新時に、自動起動を新方式で登録し直す
    let lastVersion = userDefaults.string(forKey: "lastLaunchVersion")
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let reregistered = shouldReregisterLaunchAtStartup(
      lastVersion: lastVersion,
      currentVersion: currentVersion,
      launchAtStartupEnabled: launchAtStartup.enabled
    )
    if reregistered {
      setLaunchAtStartup(true)
    }
    // 登録に失敗していたら版を記録せず、次の起動で移行をやり直す
    if shouldRecordLaunchVersion(
      reregistered: reregistered, registeredAfterward: reregistered && launchAtStartupIsRegistered())
    {
      userDefaults.set(currentVersion, forKey: "lastLaunchVersion")
    }

    // 旧設定「起動時にアップデートを確認」を Sparkle の自動確認設定へ引き継ぐ（キーを消すので 1 度だけ走る）
    if let automaticallyChecks = StartupSettings.legacyAutomaticUpdateCheck(
      saved: userDefaults.object(forKey: "checkUpdateAtlaunch"))
    {
      updaterController.updater.automaticallyChecksForUpdates = automaticallyChecks
      userDefaults.removeObject(forKey: "checkUpdateAtlaunch")
    }
    updaterController.startUpdater()

    // 除外アプリ設定
    exclusionAppsList = StartupSettings.exclusionApps(
      from: userDefaults.object(forKey: "exclusionApps"))
    exclusionAppsDict = StartupSettings.exclusionAppsDict(exclusionAppsList)

    // ショートカット設定。保存が無いときは移行した設定か初期設定を保存しておく
    let mappings = StartupSettings.mappings(
      saved: userDefaults.object(forKey: "mappings"),
      oneShotModifiers: userDefaults.object(forKey: "oneShotModifiers"))
    keyMappingList = mappings.list

    switch mappings.source {
    case .saved:
      break
    case .migratedFromOneShotModifiers:
      userDefaults.removeObject(forKey: "oneShotModifiers")
      saveKeyMappings()
    case .defaults:
      saveKeyMappings()
    }

    keyMappingListToShortcutList()

    ////////////////////////////
    // UIの初期化
    ////////////////////////////

    preferenceWindowController = PreferenceWindowController.getInstance()

    let menu = NSMenu()
    statusItem.button?.title = "⌘"
    statusItem.menu = menu
    // 「メニューバーにアイコンを表示」の保存値を起動時に反映する（設定画面と同じく、未設定なら表示）
    statusItem.isVisible = (userDefaults.object(forKey: "showIcon") as? Int ?? 1) == 1

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    menu.addItem(
      withTitle: "About ⌘英かな \(version)", action: #selector(AppDelegate.open(_:)), keyEquivalent: ""
    )
    menu.addItem(
      withTitle: "Preferences...", action: #selector(AppDelegate.openPreferencesSerector(_:)),
      keyEquivalent: "")
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      withTitle: "Restart", action: #selector(AppDelegate.restart(_:)), keyEquivalent: "")
    menu.addItem(withTitle: "Quit", action: #selector(AppDelegate.quit(_:)), keyEquivalent: "")

    // テストのホストとして起動されたときは、権限の確認（ダイアログ）とキーの見張りを始めない。
    // テストのビルドは毎回別のアプリとして扱われ、起動のたびにアクセシビリティのダイアログが出てしまう。テストはキー処理を直接呼ぶので見張りは要らない
    if !StartupSettings.isRunningAsTestHost(environment: ProcessInfo.processInfo.environment) {
      keyEvent.start()
    }
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    // Insert code here to tear down your application
  }

  func applicationDidResignActive(_ notification: Notification) {
    activeKeyTextField?.blur()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    preferenceWindowController.showAndActivate(self)
    return false
  }

  // 保存されたUserDefaultを全削除する。
  func resetUserDefault() {
    guard let appDomain = Bundle.main.bundleIdentifier else { return }
    UserDefaults.standard.removePersistentDomain(forName: appDomain)
  }

  @IBAction func open(_ sender: NSButton) {
    if let checkURL = URL(string: "https://eikana.dominion525.com/") {
      if NSWorkspace.shared.open(checkURL) {
        print("url successfully opened")
      }
    } else {
      print("invalid url")
    }
  }
  @IBAction func openPreferencesSerector(_ sender: NSButton) {
    preferenceWindowController.showAndActivate(self)
  }

  @IBAction func restart(_ sender: NSButton) {
    let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
    let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
    let task = Process()
    task.launchPath = "/usr/bin/open"
    task.arguments = [path]
    task.launch()
    NSApplication.shared.terminate(self)
  }

  @IBAction func quit(_ sender: NSButton) {
    NSApplication.shared.terminate(self)
  }
}
