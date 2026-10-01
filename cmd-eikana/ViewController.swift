//
//  ViewController.swift
//  ⌘英かな
//
//  MIT License
//  Copyright (c) 2016 iMasanari
//

import Cocoa
import ServiceManagement
import Sparkle

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  /// 設定の保存先。テストでは記録するだけの UserDefaults に差し替える
  var userDefaults = UserDefaults.standard
  /// メニューバー項目の表示を切り替える。AppKit がその状態をアプリの設定に保存するので、テストでは記録するだけの関数に差し替える
  var setStatusItemVisible: (Bool) -> Void = { statusItem.isVisible = $0 }
  /// 自動起動が OS に登録されているか。登録状態は OS が持っているので、テストでは決まった値を返す関数に差し替える
  var launchAtStartupRegistered: () -> Bool = {
    isLaunchAtStartupRegistered(SMAppService.mainApp.status)
  }
  /// 自動起動を OS に登録・解除する。OS のログイン項目を変えるので、テストでは記録するだけの関数に差し替える
  var registerLaunchAtStartup: (Bool) -> Void = { setLaunchAtStartup($0) }

  @IBOutlet weak var showIcon: NSButton!
  @IBOutlet weak var lunchAtStartup: NSButton!
  @IBOutlet weak var checkUpdateAtlaunch: NSButton!

  // Sparkle の updater は AppDelegate が保持している
  private var updater: SPUUpdater {
    (NSApp.delegate as! AppDelegate).updaterController.updater
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.

    reflectSavedShowIcon()

    checkUpdateAtlaunch.state = updater.automaticallyChecksForUpdates ? .on : .off

    // 設定画面を開いたままシステム設定で変えられた場合も、こちらに戻ってきたときに読み直す
    NotificationCenter.default.addObserver(
      self, selector: #selector(applicationDidBecomeActive(_:)),
      name: NSApplication.didBecomeActiveNotification, object: nil)
  }

  /// 「メニューバーにアイコンを表示」の保存値をチェックに反映する。保存値が無ければ表示（オン）
  func reflectSavedShowIcon() {
    let showIconState = userDefaults.object(forKey: "showIcon") as? Int ?? 1
    showIcon.state = NSControl.StateValue(rawValue: showIconState)
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    // システム設定の側で外されることもあるので、表示のたびに OS の登録状態を読む
    reflectLaunchAtStartup()
  }

  @objc private func applicationDidBecomeActive(_ notification: Notification) {
    reflectLaunchAtStartup()
  }

  private func reflectLaunchAtStartup() {
    lunchAtStartup.state = launchAtStartupRegistered() ? .on : .off
  }

  @IBAction func clickShowIcon(_ sender: AnyObject) {
    setStatusItemVisible(showIcon.state == NSControl.StateValue.on)
    userDefaults.set(showIcon.state, forKey: "showIcon")
  }
  @IBAction func clickLunchAtStartup(_ sender: AnyObject) {
    registerLaunchAtStartup(lunchAtStartup.state == NSControl.StateValue.on)
    userDefaults.set(lunchAtStartup.state, forKey: "lunchAtStartup")
    // 登録に失敗したときにチェックだけが残らないよう、実際の登録状態を表示し直す
    reflectLaunchAtStartup()
  }
  @IBAction func clickCheckUpdateAtlaunch(_ sender: AnyObject) {
    updater.automaticallyChecksForUpdates = (checkUpdateAtlaunch.state == .on)
  }
  // 結果（最新である・失敗した・更新がある）の表示は Sparkle の標準 UI が行う
  @IBAction func checkUpdateButton(_ sender: AnyObject) {
    updater.checkForUpdates()
  }
}
