// 读取调度中心（Mission Control）的缩略图，并把它们匹配回真实窗口。
//
// 调度中心由 Dock 进程绘制，激活时 Dock 的辅助功能树中会出现
//   AXGroup(id=mc) → AXGroup(id=mc.display) → AXGroup(id=mc.windows) → AXButton(缩略图)
// 每个缩略图只有标题和屏幕坐标，没有所属进程，因此用「标题 + 宽高比 + 相对位置」匹配。

import Cocoa
import ApplicationServices

// MARK: - AX 工具

func axAttr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}

func axString(_ e: AXUIElement, _ name: String) -> String? { axAttr(e, name) as? String }

func axChildren(_ e: AXUIElement) -> [AXUIElement] { (axAttr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

func axFrame(_ e: AXUIElement) -> CGRect? {
    if let v = axAttr(e, "AXFrame"), CFGetTypeID(v) == AXValueGetTypeID() {
        var r = CGRect.zero
        if AXValueGetValue(v as! AXValue, .cgRect, &r) { return r }
    }
    var pos = CGPoint.zero, size = CGSize.zero
    guard let p = axAttr(e, kAXPositionAttribute), let s = axAttr(e, kAXSizeAttribute),
          AXValueGetValue(p as! AXValue, .cgPoint, &pos),
          AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: pos, size: size)
}

/// 主屏高度，用于在 AX/CG 坐标（左上角原点）与 Cocoa 坐标（左下角原点）之间转换
var primaryScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

func cocoaRect(fromAX r: CGRect) -> CGRect {
    CGRect(x: r.minX, y: primaryScreenHeight - r.maxY, width: r.width, height: r.height)
}

func axPoint(fromCocoa p: NSPoint) -> CGPoint {
    CGPoint(x: p.x, y: primaryScreenHeight - p.y)
}

// MARK: - 数据模型

struct Thumbnail {
    let title: String
    let frame: CGRect        // AX 坐标
    let container: CGRect    // 所在 mc.windows 区域（AX 坐标）
}

final class RealWindow {
    let element: AXUIElement
    let app: NSRunningApplication
    let title: String
    let frame: CGRect        // AX 坐标

    init(element: AXUIElement, app: NSRunningApplication, title: String, frame: CGRect) {
        self.element = element; self.app = app; self.title = title; self.frame = frame
    }

    var appName: String { app.localizedName ?? "" }

    private var appElement: AXUIElement { AXUIElementCreateApplication(app.processIdentifier) }

    /// 窗口是否还存在
    var exists: Bool {
        if app.isTerminated { return false }
        var v: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &v) == .invalidUIElement { return false }
        let windows = (axAttr(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.contains { CFEqual($0, element) }
    }

    /// 窗口上挂着「是否保存」之类的表单，或应用弹出了对话框
    var needsUserAttention: Bool {
        if axChildren(element).contains(where: { axString($0, kAXRoleAttribute) == kAXSheetRole }) { return true }
        let windows = (axAttr(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.contains {
            let sub = axString($0, kAXSubroleAttribute)
            return sub == kAXDialogSubrole || sub == kAXSystemDialogSubrole
        }
    }

    /// 按窗口自带的关闭按钮
    func pressCloseButton() -> Bool {
        guard let btn = axAttr(element, kAXCloseButtonAttribute) else { return false }
        let b = btn as! AXUIElement
        if (axAttr(b, kAXEnabledAttribute) as? Bool) == false { return false }
        return AXUIElementPerformAction(b, kAXPressAction as CFString) == .success
    }

    /// 兜底：把窗口设为该应用的焦点窗口，再直接给该应用发送 ⌘W（应用需处于前台才会响应）。
    /// 只有确认焦点确实落在目标窗口上才发送，避免误关同一应用的其他窗口。
    @discardableResult
    func sendCommandW() -> Bool {
        guard exists else { return false }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, element)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        guard let focused = axAttr(appElement, kAXFocusedWindowAttribute), CFEqual(focused, element) else { return false }
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 13, keyDown: down) else { continue }
            e.flags = .maskCommand
            e.postToPid(app.processIdentifier)
        }
        return true
    }
}

// MARK: - 调度中心读取

enum MissionControl {
    static var dockApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
    }

    static var dockElement: AXUIElement? {
        dockApp.map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    /// 调度中心未激活时返回 nil
    static func thumbnails() -> [Thumbnail]? {
        guard let dock = dockElement,
              let mc = axChildren(dock).first(where: { axString($0, kAXIdentifierAttribute) == "mc" })
        else { return nil }
        var result: [Thumbnail] = []
        for display in axChildren(mc) where axString(display, kAXIdentifierAttribute) == "mc.display" {
            for group in axChildren(display) where axString(group, kAXIdentifierAttribute) == "mc.windows" {
                let container = axFrame(group) ?? .zero
                for item in axChildren(group) where axString(item, kAXRoleAttribute) == kAXButtonRole {
                    guard let f = axFrame(item), f.width > 20, f.height > 20 else { continue }
                    result.append(Thumbnail(title: axString(item, kAXTitleAttribute) ?? "",
                                            frame: f, container: container))
                }
            }
        }
        return result
    }

    /// 退出 / 进入调度中心
    static func toggle() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
    }

    /// 枚举所有普通应用的窗口（已隐藏应用的窗口同样会出现在调度中心里，不能跳过）
    static func realWindows() -> [RealWindow] {
        var list: [RealWindow] = []
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != me {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25)
            for w in (axAttr(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
                if axString(w, kAXRoleAttribute) != kAXWindowRole { continue }
                if (axAttr(w, kAXMinimizedAttribute) as? Bool) == true { continue }
                guard let f = axFrame(w), f.width > 40, f.height > 40 else { continue }
                list.append(RealWindow(element: w, app: app, title: axString(w, kAXTitleAttribute) ?? "", frame: f))
            }
        }
        return list
    }

    /// 缩略图 ↔ 真实窗口 的贪心匹配，返回 [缩略图下标: 窗口]
    static func match(_ thumbs: [Thumbnail], _ windows: [RealWindow]) -> [Int: RealWindow] {
        let screens = NSScreen.screens.map { cocoaRect(fromAX: $0.frame) }  // 对称变换，同样可用于 Cocoa → AX
        func screenOf(_ r: CGRect) -> CGRect {
            screens.first(where: { $0.contains(CGPoint(x: r.midX, y: r.midY)) }) ?? screens.first ?? r
        }
        var pairs: [(cost: Double, t: Int, w: Int)] = []
        for (ti, t) in thumbs.enumerated() {
            let tAspect = t.frame.width / max(t.frame.height, 1)
            let tc = t.container.width > 0 ? t.container : screenOf(t.frame)
            let tx = (t.frame.midX - tc.minX) / max(tc.width, 1), ty = (t.frame.midY - tc.minY) / max(tc.height, 1)
            for (wi, w) in windows.enumerated() {
                var cost: Double
                if t.title == w.title && !w.title.isEmpty { cost = 0 }
                else if w.title.isEmpty && t.title == w.appName { cost = 0.3 }
                else if !w.title.isEmpty && !t.title.isEmpty && (t.title.contains(w.title) || w.title.contains(t.title)) { cost = 0.8 }
                else if t.title == w.appName { cost = 1.2 }
                else { continue }
                let wAspect = w.frame.width / max(w.frame.height, 1)
                cost += Double(abs(log(tAspect / wAspect))) * 2
                let sc = screenOf(w.frame)
                let wx = (w.frame.midX - sc.minX) / max(sc.width, 1), wy = (w.frame.midY - sc.minY) / max(sc.height, 1)
                cost += Double(hypot(tx - wx, ty - wy)) * 0.4
                pairs.append((cost, ti, wi))
            }
        }
        pairs.sort { $0.cost < $1.cost }
        var usedT = Set<Int>(), usedW = Set<Int>(), result: [Int: RealWindow] = [:]
        for p in pairs where !usedT.contains(p.t) && !usedW.contains(p.w) {
            usedT.insert(p.t); usedW.insert(p.w); result[p.t] = windows[p.w]
        }
        return result
    }
}
