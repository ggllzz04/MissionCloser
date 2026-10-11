// 检测调度中心的进入/退出，摆放关闭按钮，处理点击与悬停快捷键。

import Cocoa
import ApplicationServices

final class Controller {
    static let shared = Controller()

    private let settings = Settings.shared
    private let debug = ProcessInfo.processInfo.environment["MISSIONCLOSER_DEBUG"] != nil

    private(set) var active = false
    private var started = false
    private var timer: Timer?
    private var panels: [CloseButtonPanel] = []
    private var thumbs: [Thumbnail] = []
    private var mapping: [Int: RealWindow] = [:]
    private var windowsCache: [RealWindow] = []
    private var windowsCacheTime = Date.distantPast
    private var buttonRects: [Int: CGRect] = [:]   // 当前可见的关闭按钮区域（AX/CG 全局坐标）
    private var hoveredThumb: Int?
    private var pressedIndex: Int?
    private var eventTap: CFMachPort?
    private var dockObserver: AXObserver?
    private var lastDebug: [String] = []

    /// 需要辅助功能权限，获得后调用
    func start() {
        guard !started else { return }
        started = true
        installEventTap()
        installDockObserver()
        schedule(interval: 0.4)
    }

    private func schedule(interval: TimeInterval) {
        if let t = timer, abs(t.timeInterval - interval) < 0.001 { return }
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Dock 在进入/退出调度中心时会发出这些通知，用来加快响应；轮询作为兜底
    private func installDockObserver() {
        guard let dock = MissionControl.dockApp, let dockAX = MissionControl.dockElement else { return }
        var obs: AXObserver?
        let cb: AXObserverCallback = { _, _, _, _ in
            DispatchQueue.main.async { Controller.shared.tick() }
        }
        guard AXObserverCreate(dock.processIdentifier, cb, &obs) == .success, let obs else { return }
        for n in ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop", "AXExposeExit"] {
            AXObserverAddNotification(obs, dockAX, n as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        dockObserver = obs
    }

    // MARK: 主循环

    func tick() {
        guard settings.enabled, let t = MissionControl.thumbnails(), !t.isEmpty else {
            if active { deactivate() }
            return
        }
        if !active {
            active = true
            windowsCacheTime = .distantPast
            schedule(interval: 0.1)   // 调度中心激活期间高频刷新，跟上动画和布局变化
        }
        if Date().timeIntervalSince(windowsCacheTime) > 1.0 {
            windowsCache = MissionControl.realWindows()
            windowsCacheTime = Date()
        }
        thumbs = t
        mapping = MissionControl.match(t, windowsCache)
        if debug {
            let desc = t.indices.map { "\(t[$0].title) → \(mapping[$0].map { "\($0.appName) / \($0.title)" } ?? "（未匹配）")" }
            if desc != lastDebug { lastDebug = desc; desc.forEach { log($0) } }
        }
        updateHover(at: axPoint(fromCocoa: NSEvent.mouseLocation))
    }

    private func deactivate() {
        active = false
        thumbs = []; mapping = [:]; windowsCache = []; buttonRects = [:]
        hoveredThumb = nil; pressedIndex = nil
        panels.forEach { $0.orderOut(nil) }
        schedule(interval: 0.4)
    }

    // MARK: 按钮摆放与悬停

    private var buttonSize: CGFloat { settings.size.points }

    /// 根据鼠标位置更新悬停状态，并重新摆放按钮
    private func updateHover(at p: CGPoint) {
        let pad = buttonSize * 0.5
        hoveredThumb = thumbs.indices.first { thumbs[$0].frame.insetBy(dx: -pad, dy: -pad).contains(p) }
        layoutPanels()
        let hit = buttonIndex(at: p)
        for (i, panel) in panels.enumerated() { panel.button.hovered = (i == hit) }
    }

    private func layoutPanels() {
        while panels.count < thumbs.count { panels.append(CloseButtonPanel()) }
        let s = buttonSize
        buttonRects = [:]
        for (i, panel) in panels.enumerated() {
            let visible = i < thumbs.count && mapping[i] != nil
                && (settings.visibility == .always || i == hoveredThumb)
            guard visible else { if panel.isVisible { panel.orderOut(nil) }; continue }
            // 左上角，略向外偏移，和系统窗口关闭按钮的位置感觉一致
            let t = thumbs[i].frame
            let rect = CGRect(x: t.minX - s * 0.35, y: t.minY - s * 0.35, width: s, height: s)
            buttonRects[i] = rect
            let frame = cocoaRect(fromAX: rect)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func buttonIndex(at p: CGPoint) -> Int? {
        buttonRects.first { $0.value.insetBy(dx: -2, dy: -2).contains(p) }?.key
    }

    // MARK: 操作

    enum Action { case closeWindow, quitApp, hideApp }

    func perform(_ action: Action, thumbIndex: Int) {
        guard let w = mapping[thumbIndex] else { NSSound.beep(); return }
        switch action {
        case .closeWindow:
            log("关闭窗口：\(w.appName) / \(w.title)")
            if w.pressCloseButton() {
                after(0.6) { [weak self] in
                    guard let self else { return }
                    if !w.exists { return self.windowsChanged() }
                    if w.needsUserAttention { return self.exitForPrompt() }
                    self.log("关闭按钮无效，改用 ⌘W")
                    self.closeWithCommandW(w)
                }
            } else {
                log("没有可用的关闭按钮，改用 ⌘W")
                closeWithCommandW(w)
            }
        case .quitApp:
            log("退出应用：\(w.appName)")
            w.app.terminate()
            waitForQuit(w.app, deadline: Date().addingTimeInterval(1.5))
        case .hideApp:
            log("隐藏应用：\(w.appName)")
            w.app.hide()
            after(0.2) { [weak self] in self?.windowsChanged() }
        }
    }

    /// 后台应用不会响应发给它的 ⌘W（菜单项也处于禁用状态），
    /// 所以先临时激活目标应用（不会退出调度中心），发完 ⌘W 再切回原来的前台应用。
    private func closeWithCommandW(_ w: RealWindow) {
        guard w.exists else { return windowsChanged() }
        let previous = NSWorkspace.shared.frontmostApplication
        let restore = { if let p = previous, p != w.app, !p.isTerminated { p.activate() } }
        w.app.activate()
        after(0.15) { [weak self] in
            guard let self else { return }
            guard w.sendCommandW() else {
                self.log("无法聚焦目标窗口，放弃")
                restore()
                return NSSound.beep()
            }
            self.after(0.6) {
                if !w.exists { restore(); self.windowsChanged() }
                else if w.needsUserAttention { self.exitForPrompt() }  // 提示属于目标应用，保持它在前台
                else { restore(); self.log("窗口仍未关闭"); NSSound.beep() }
            }
        }
    }

    private func waitForQuit(_ app: NSRunningApplication, deadline: Date) {
        if app.isTerminated { return windowsChanged() }
        // 超时还没退出，多半是弹出了保存提示
        if Date() > deadline { return exitForPrompt() }
        after(0.15) { [weak self] in self?.waitForQuit(app, deadline: deadline) }
    }

    /// 窗口集合变化后刷新匹配缓存（调度中心里留下的空占位框是系统行为，退出后自然消失）
    private func windowsChanged() {
        windowsCacheTime = .distantPast
        tick()
    }

    /// 弹出保存提示等需要用户处理的情况：按设置退出调度中心，让用户能看到
    private func exitForPrompt() {
        if active && settings.exitOnPrompt { MissionControl.toggle() }
    }

    private func after(_ seconds: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }

    private func log(_ msg: String) {
        if debug { NSLog("MissionCloser: %@", msg) }
    }

    // MARK: 事件监听：关闭按钮点击 + 悬停快捷键

    /// 返回 true 表示吞掉该鼠标事件
    fileprivate func handleMouse(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let p = event.location
        switch type {
        case .mouseMoved, .leftMouseDragged:
            updateHover(at: p)
            return false
        case .leftMouseDown:
            pressedIndex = buttonIndex(at: p)
            return pressedIndex != nil
        case .leftMouseUp:
            guard let idx = pressedIndex else { return false }
            pressedIndex = nil
            if buttonIndex(at: p) == idx {
                DispatchQueue.main.async { self.perform(.closeWindow, thumbIndex: idx) }
            }
            return true
        default:
            return false
        }
    }

    /// 返回 true 表示吞掉该按键
    fileprivate func handleKey(_ event: CGEvent) -> Bool {
        let flags = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        guard flags == .maskCommand else { return false }
        let action: Action
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 13 where settings.shortcutClose: action = .closeWindow   // W
        case 12 where settings.shortcutQuit:  action = .quitApp       // Q
        case 4 where settings.shortcutHide:   action = .hideApp       // H
        default: return false
        }
        let pad = buttonSize * 0.5
        let p = event.location
        guard let idx = thumbs.indices.first(where: { thumbs[$0].frame.insetBy(dx: -pad, dy: -pad).contains(p) }),
              mapping[idx] != nil else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { self.perform(action, thumbIndex: idx) }
        }
        return true  // 吞掉按键，避免传给前台应用
    }

    private func installEventTap() {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let cb: CGEventTapCallBack = { _, type, event, _ in
            let c = Controller.shared
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = c.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard c.active else { return Unmanaged.passUnretained(event) }
            let swallow = type == .keyDown ? c.handleKey(event) : c.handleMouse(type, event)
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: cb, userInfo: nil) else {
            NSLog("MissionCloser: 无法创建事件监听（需要辅助功能权限）")
            return
        }
        eventTap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
