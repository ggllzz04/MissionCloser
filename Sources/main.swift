// MissionCloser — 在 macOS 调度中心（Mission Control）的窗口缩略图上加关闭按钮，
// 并支持悬停时 ⌘W 关闭窗口 / ⌘Q 退出应用 / ⌘H 隐藏应用。
//
// 应用在后台运行，不显示菜单栏图标和 Dock 图标：
// 手动打开（或已在运行时再次打开）会弹出设置窗口；作为登录项启动时静默运行。

import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        installMainMenu()

        let settings = Settings.shared
        settings.onTrusted = { Controller.shared.start() }

        if AXIsProcessTrusted() {
            Controller.shared.start()
        } else {
            // 弹出系统的授权提示；授权后由 Settings 的轮询回调启动
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        if !launchedAsLoginItem() || !AXIsProcessTrusted() {
            SettingsWindowController.shared.show()
        }
    }

    /// 应用已在运行时再次打开（双击图标、Spotlight、启动台）→ 显示设置窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// 关掉设置窗口后继续在后台运行
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// 不显示菜单栏，但需要主菜单来支持设置窗口里的 ⌘W / ⌘Q 等快捷键
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "退出 MissionCloser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
