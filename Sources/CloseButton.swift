// 盖在缩略图左上角（或右上角）的关闭按钮。
// 调度中心激活时 Dock 会截走鼠标事件，所以面板本身不接收鼠标，
// 点击与悬停都由 Controller 里的 CGEventTap 处理，这里只负责绘制。

import Cocoa

final class CloseButtonView: NSView {
    var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        let circle = NSBezierPath(ovalIn: r)
        (hovered ? NSColor(calibratedRed: 1, green: 0.37, blue: 0.34, alpha: 1)
                 : NSColor(calibratedWhite: 0.15, alpha: 0.85)).setFill()
        circle.fill()
        NSColor(calibratedWhite: 1, alpha: 0.9).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let c = NSPoint(x: bounds.midX, y: bounds.midY), d = r.width * 0.2
        let x = NSBezierPath()
        x.move(to: NSPoint(x: c.x - d, y: c.y - d)); x.line(to: NSPoint(x: c.x + d, y: c.y + d))
        x.move(to: NSPoint(x: c.x - d, y: c.y + d)); x.line(to: NSPoint(x: c.x + d, y: c.y - d))
        x.lineWidth = max(1.5, r.width * 0.08)
        x.lineCapStyle = .round
        NSColor.white.setStroke()
        x.stroke()
    }
}

final class CloseButtonPanel: NSPanel {
    let button = CloseButtonView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))

    init() {
        super.init(contentRect: button.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        button.autoresizingMask = [.width, .height]
        contentView = button
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 需要高于调度中心本身的层级
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
