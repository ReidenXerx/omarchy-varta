// Draws Varta's app icon at every size macOS asks for.
//   swift tools/make-icon.swift Resources/Assets.xcassets/AppIcon.appiconset
// A shield, half lit: Varta's menu bar mark at the size of an icon. Blue
// ground, amber shield, the colours of the Mac Ports Plan's concept art.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func shield(in r: CGRect) -> CGPath {
    // Flat top with softened corners, straight sides, a point at the bottom.
    let p = CGMutablePath()
    let w = r.width, h = r.height, x = r.minX, top = r.maxY, bottom = r.minY
    let shoulder = top - h * 0.12
    p.move(to: CGPoint(x: x + w / 2, y: top))
    p.addCurve(to: CGPoint(x: x + w, y: shoulder),
               control1: CGPoint(x: x + w * 0.70, y: top), control2: CGPoint(x: x + w * 0.88, y: top - h * 0.02))
    p.addLine(to: CGPoint(x: x + w, y: top - h * 0.45))
    p.addCurve(to: CGPoint(x: x + w / 2, y: bottom),
               control1: CGPoint(x: x + w, y: top - h * 0.75), control2: CGPoint(x: x + w * 0.72, y: bottom + h * 0.08))
    p.addCurve(to: CGPoint(x: x, y: top - h * 0.45),
               control1: CGPoint(x: x + w * 0.28, y: bottom + h * 0.08), control2: CGPoint(x: x, y: top - h * 0.75))
    p.addLine(to: CGPoint(x: x, y: shoulder))
    p.addCurve(to: CGPoint(x: x + w / 2, y: top),
               control1: CGPoint(x: x + w * 0.12, y: top - h * 0.02), control2: CGPoint(x: x + w * 0.30, y: top))
    p.closeSubpath()
    return p
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // Apple's macOS grid: an 824 pt rounded square centred in 1024, with room
    // for the shadow underneath.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(squircle); ctx.setFillColor(color(0x1b3a80)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let ground = CGGradient(colorsSpace: cs, colors: [color(0x3a74dc), color(0x16306e)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ground, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let sr = CGRect(x: 512 - 250, y: 200, width: 500, height: 600)
    let sp = shield(in: sr)
    // Shadow, then the amber shield.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x0a1638, 0.55))
    ctx.addPath(sp); ctx.setFillColor(color(0xe39a1c)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(sp); ctx.clip()
    let amber = CGGradient(colorsSpace: cs, colors: [color(0xf6c050), color(0xd9850f)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(amber, start: CGPoint(x: 512, y: 800), end: CGPoint(x: 512, y: 200), options: [])
    // The lit left half: "watching" at a glance, like shield.lefthalf.filled.
    ctx.setFillColor(color(0xffffff, 0.22))
    ctx.fill(CGRect(x: sr.minX, y: sr.minY, width: sr.width / 2, height: sr.height))
    ctx.restoreGState()
    // A fine light rim so the shield reads on the blue at 16 px.
    ctx.addPath(sp); ctx.setStrokeColor(color(0xffe2a0, 0.9)); ctx.setLineWidth(10); ctx.strokePath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try draw(px).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) sizes to \(out.path)")
