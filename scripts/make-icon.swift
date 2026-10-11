// 生成应用图标：swift scripts/make-icon.swift <输出目录>
// 输出 AppIcon.iconset 与 1024px 预览 PNG，再由 build.sh 用 iconutil 转成 .icns
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    // 底板：macOS 图标网格（824×824，圆角 185），带投影
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.addPath(platePath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.13, green: 0.17, blue: 0.45, alpha: 1).cgColor,
        NSColor(srgbRed: 0.30, green: 0.42, blue: 0.95, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // 顶部柔光
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(white: 1, alpha: 0.18).cgColor, NSColor(white: 1, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 900), endRadius: 600, options: [])
    ctx.restoreGState()

    // 调度中心式的窗口缩略图
    func window(_ r: CGRect, alpha: CGFloat, accent: NSColor) {
        let path = CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor(white: 0, alpha: 0.3).cgColor)
        ctx.addPath(path); ctx.setFillColor(NSColor(white: 1, alpha: alpha).cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        // 标题栏
        ctx.setFillColor(accent.withAlphaComponent(alpha).cgColor)
        ctx.fill(CGRect(x: r.minX, y: r.maxY - 44, width: r.width, height: 44))
        // 内容行
        ctx.setFillColor(NSColor(white: 0.82, alpha: alpha).cgColor)
        var y = r.maxY - 84
        for w in [0.72, 0.55, 0.64] where y > r.minY + 24 {
            ctx.fill(CGRect(x: r.minX + 28, y: y, width: (r.width - 56) * w, height: 16)); y -= 34
        }
        ctx.restoreGState()
    }
    let gray = NSColor(white: 0.9, alpha: 1)
    window(CGRect(x: 548, y: 560, width: 290, height: 210), alpha: 0.55, accent: gray)
    window(CGRect(x: 186, y: 236, width: 290, height: 210), alpha: 0.55, accent: gray)
    window(CGRect(x: 548, y: 236, width: 290, height: 210), alpha: 0.55, accent: gray)
    // 主角窗口
    let hero = CGRect(x: 186, y: 520, width: 330, height: 250)
    window(hero, alpha: 1, accent: NSColor(srgbRed: 0.86, green: 0.89, blue: 0.97, alpha: 1))
    // 高亮描边（调度中心悬停效果）
    ctx.addPath(CGPath(roundedRect: hero.insetBy(dx: -10, dy: -10), cornerWidth: 34, cornerHeight: 34, transform: nil))
    ctx.setStrokeColor(NSColor(srgbRed: 0.55, green: 0.75, blue: 1, alpha: 1).cgColor)
    ctx.setLineWidth(10); ctx.strokePath()

    // 左上角红色关闭按钮
    let c = CGPoint(x: hero.minX + 8, y: hero.maxY - 8), radius: CGFloat = 78
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: NSColor(white: 0, alpha: 0.4).cgColor)
    ctx.addEllipse(in: CGRect(x: c.x - radius - 10, y: c.y - radius - 10, width: (radius + 10) * 2, height: (radius + 10) * 2))
    ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    let red = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 1, green: 0.42, blue: 0.38, alpha: 1).cgColor,
        NSColor(srgbRed: 0.88, green: 0.18, blue: 0.2, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)); ctx.clip()
    ctx.drawLinearGradient(red, start: CGPoint(x: c.x, y: c.y + radius), end: CGPoint(x: c.x, y: c.y - radius), options: [])
    ctx.restoreGState()
    let d: CGFloat = 30
    ctx.setStrokeColor(NSColor.white.cgColor); ctx.setLineWidth(18); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: c.x - d, y: c.y - d)); ctx.addLine(to: CGPoint(x: c.x + d, y: c.y + d))
    ctx.move(to: CGPoint(x: c.x - d, y: c.y + d)); ctx.addLine(to: CGPoint(x: c.x + d, y: c.y - d))
    ctx.strokePath()

    img.unlockFocus()
    return img
}

func writePNG(_ img: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = drawIcon(size: 1024)
for base in [16, 32, 128, 256, 512] {
    writePNG(master, pixels: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(master, pixels: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(master, pixels: 1024, to: out.appendingPathComponent("AppIcon-1024.png"))
