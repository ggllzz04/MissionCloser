// 设置项（UserDefaults）与设置窗口。
// 应用不在菜单栏和 Dock 中常驻，首次打开或再次打开应用时弹出此窗口。

import Cocoa
import SwiftUI
import ServiceManagement
import ApplicationServices

enum ButtonVisibility: String, CaseIterable, Identifiable {
    case always, hover
    var id: String { rawValue }
    var label: String { self == .always ? "始终显示" : "悬停时显示" }
}

enum ButtonSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String { ["small": "小", "medium": "中", "large": "大"][rawValue]! }
    var points: CGFloat { ["small": 20, "medium": 26, "large": 32][rawValue]! }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { save(enabled, "enabled") } }
    @Published var visibility: ButtonVisibility { didSet { save(visibility.rawValue, "visibility") } }
    @Published var size: ButtonSize { didSet { save(size.rawValue, "size") } }
    @Published var shortcutClose: Bool { didSet { save(shortcutClose, "shortcutClose") } }
    @Published var shortcutQuit: Bool { didSet { save(shortcutQuit, "shortcutQuit") } }
    @Published var shortcutHide: Bool { didSet { save(shortcutHide, "shortcutHide") } }
    @Published var exitOnPrompt: Bool { didSet { save(exitOnPrompt, "exitOnPrompt") } }

    /// 以下两项来自系统，定时刷新
    @Published private(set) var trusted = AXIsProcessTrusted()
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published var loginError: String?

    /// 辅助功能权限从无到有时回调（用于启动事件监听）
    var onTrusted: (() -> Void)?
    private var pollTimer: Timer?

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String, _ def: Bool) -> Bool { d.object(forKey: key) as? Bool ?? def }
        enabled = bool("enabled", true)
        visibility = ButtonVisibility(rawValue: d.string(forKey: "visibility") ?? "") ?? .always
        size = ButtonSize(rawValue: d.string(forKey: "size") ?? "") ?? .medium
        shortcutClose = bool("shortcutClose", true)
        shortcutQuit = bool("shortcutQuit", true)
        shortcutHide = bool("shortcutHide", true)
        exitOnPrompt = bool("exitOnPrompt", true)

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshSystemState() }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    func refreshSystemState() {
        let t = AXIsProcessTrusted()
        if t != trusted {
            trusted = t
            if t { onTrusted?() }
        }
        let s = SMAppService.mainApp.status
        if s != loginStatus { loginStatus = s }
    }

    var launchAtLogin: Bool {
        get { loginStatus == .enabled || loginStatus == .requiresApproval }
        set {
            loginError = nil
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                loginError = "\(error.localizedDescription)（建议把 MissionCloser 放到「应用程序」文件夹后再试）"
            }
            loginStatus = SMAppService.mainApp.status
        }
    }
}

// MARK: - 设置界面

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MissionCloser").font(.title2.bold())
                    Text("在调度中心里直接关闭窗口").foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(version)").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 4)

            Form {
                Section("权限") {
                    HStack {
                        Circle().fill(settings.trusted ? Color.green : Color.orange).frame(width: 9, height: 9)
                        Text(settings.trusted ? "已获得辅助功能权限" : "需要辅助功能权限才能工作")
                        Spacer()
                        if !settings.trusted {
                            Button("打开系统设置") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                        }
                    }
                }

                Section("通用") {
                    Toggle("启用", isOn: $settings.enabled)
                    Toggle("登录时自动启动", isOn: Binding(get: { settings.launchAtLogin },
                                                      set: { settings.launchAtLogin = $0 }))
                    if settings.loginStatus == .requiresApproval {
                        Text("需要在「系统设置 › 通用 › 登录项」中允许 MissionCloser")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let err = settings.loginError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("关闭按钮") {
                    Picker("显示方式", selection: $settings.visibility) {
                        ForEach(ButtonVisibility.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("大小", selection: $settings.size) {
                        ForEach(ButtonSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("⌘W  关闭窗口", isOn: $settings.shortcutClose)
                    Toggle("⌘Q  退出应用", isOn: $settings.shortcutQuit)
                    Toggle("⌘H  隐藏应用", isOn: $settings.shortcutHide)
                } header: {
                    Text("悬停快捷键")
                } footer: {
                    Text("在调度中心里把鼠标停在窗口缩略图上时生效").font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("关闭时弹出「是否保存」等提示，自动退出调度中心", isOn: $settings.exitOnPrompt)
                } header: {
                    Text("其他")
                } footer: {
                    Text("否则提示会被调度中心挡住，需要手动退出后才能看到").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("菜单栏和 Dock 中不显示图标，再次打开 MissionCloser 即可回到此窗口。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出 MissionCloser") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 4)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "MissionCloser"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        Settings.shared.refreshSystemState()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
