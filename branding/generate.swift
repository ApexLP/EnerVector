// Regenerates the EnerVector icon/logo PNGs: swiftc -O -o /tmp/brand branding/generate.swift && /tmp/brand branding EnerVector/Assets.xcassets/AppIcon.appiconset/AppIcon.png EnerVector/Assets.xcassets/LogoMark.imageset/LogoMark.png
import AppKit

let blue = NSColor(srgbRed: 0.18, green: 0.37, blue: 0.66, alpha: 1)     // #2E5FA8
let blueDark = NSColor(srgbRed: 0.11, green: 0.26, blue: 0.51, alpha: 1)
let ink = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)

/// The "vector V": a V whose right arm ends in an arrowhead. Drawn in a 100×100 unit box, y-down.
func vectorV(in ctx: CGContext, rect: CGRect, color: NSColor) {
    let s = rect.width / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
    let a = (x: 22.0, y: 32.0), b = (x: 44.0, y: 76.0), c = (x: 64.0, y: 40.0)
    let dx = c.x - b.x, dy = c.y - b.y, len = (dx * dx + dy * dy).squareRoot()
    let d = (x: dx / len, y: dy / len), n = (x: -d.y, y: d.x)
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(11 * s)
    ctx.setLineJoin(.miter)
    ctx.setLineCap(.butt)
    ctx.move(to: p(a.x, a.y)); ctx.addLine(to: p(b.x, b.y)); ctx.addLine(to: p(c.x + d.x * 5, c.y + d.y * 5))
    ctx.strokePath()
    let tip = (x: c.x + d.x * 17, y: c.y + d.y * 17)
    ctx.setFillColor(color.cgColor)
    ctx.move(to: p(tip.x, tip.y))
    ctx.addLine(to: p(c.x + n.x * 13, c.y + n.y * 13))
    ctx.addLine(to: p(c.x - n.x * 13, c.y - n.y * 13))
    ctx.closePath(); ctx.fillPath()
}

import UniformTypeIdentifiers
func render(_ size: CGSize, alpha: Bool, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)   // y-down like the unit box
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

func drawText(_ s: String, font: NSFont, color: NSColor, kern: CGFloat, at pt: CGPoint, ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: pt.x, y: pt.y)
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: .zero)
    ctx.restoreGState()
}

let out = CommandLine.arguments[1], appIcon = CommandLine.arguments[2], markAsset = CommandLine.arguments[3]

// App icon: full-bleed blue gradient + white vector V (no alpha, as App Store requires).
let icon = render(CGSize(width: 1024, height: 1024), alpha: false) { ctx in
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [blue.cgColor, blueDark.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 1024, y: 1024), options: [])
    vectorV(in: ctx, rect: CGRect(x: 132, y: 150, width: 760, height: 760), color: .white)
}
save(icon, appIcon)
save(icon, out + "/EnerVector-AppIcon-1024.png")

// Mark: blue circle + white V, transparent background.
func mark(_ ctx: CGContext, _ r: CGRect) {
    ctx.setFillColor(blue.cgColor); ctx.fillEllipse(in: r)
    vectorV(in: ctx, rect: r, color: .white)
}
let markRep = render(CGSize(width: 1024, height: 1024), alpha: true) { mark($0, CGRect(x: 0, y: 0, width: 1024, height: 1024)) }
save(markRep, out + "/EnerVector-Mark.png")
save(render(CGSize(width: 300, height: 300), alpha: true) { mark($0, CGRect(x: 0, y: 0, width: 300, height: 300)) }, markAsset)

// Horizontal lockup: mark + ENERVECTOR / F I E L D  I N T E L L I G E N C E
let wordFont = NSFont.systemFont(ofSize: 250, weight: .heavy)
let tagFont = NSFont.systemFont(ofSize: 92, weight: .regular)
let word = "ENERVECTOR"
let wordW = NSAttributedString(string: word, attributes: [.font: wordFont, .kern: -4]).size().width
for (name, textColor, bg) in [("EnerVector-Logo", ink, NSColor.clear), ("EnerVector-Logo-White", NSColor.white, NSColor.clear)] {
    let h: CGFloat = 640, pad: CGFloat = 60, markD: CGFloat = 520
    let w = pad + markD + 70 + wordW + pad
    let rep = render(CGSize(width: w, height: h), alpha: true) { ctx in
        if bg != .clear { ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
        mark(ctx, CGRect(x: pad, y: (h - markD) / 2, width: markD, height: markD))
        let x = pad + markD + 70
        drawText(word, font: wordFont, color: textColor, kern: -4, at: CGPoint(x: x - 8, y: 70), ctx: ctx)
        // Spread the tagline to the wordmark's width.
        let tag = "FIELD INTELLIGENCE"
        let base = NSAttributedString(string: tag, attributes: [.font: tagFont]).size().width
        let kern = (wordW - base) / CGFloat(tag.count - 1)
        drawText(tag, font: tagFont, color: textColor, kern: kern, at: CGPoint(x: x, y: 395), ctx: ctx)
    }
    save(rep, out + "/\(name).png")
}
print("ok")
