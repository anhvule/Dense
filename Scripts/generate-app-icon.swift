import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Dense app icon — "Squeeze": teal squircle + two inward white chevrons.
// Rendered natively so output is pixel-perfect at every size.

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

func rounded(_ v: CGFloat) -> CGFloat { v }

func drawIcon(size N: CGFloat) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: Int(N), height: Int(N),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // macOS Big Sur icon grid: body inset ~100/1024 of canvas, corner ~22.37% of body.
    let inset = N * (100.0 / 1024.0)
    let body = CGRect(x: inset, y: inset, width: N - 2 * inset, height: N - 2 * inset)
    let side = body.width
    let corner = side * 0.2237

    // Rounded-rect squircle path (clip so the gradient fills it).
    let path = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    // Vertical teal gradient: #20A97E (top) -> #0C5F49 (bottom).
    // CoreGraphics origin is bottom-left, so stop 0 is the bottom.
    let top = CGColor(srgbRed: 0x20/255.0, green: 0xA9/255.0, blue: 0x7E/255.0, alpha: 1)
    let bot = CGColor(srgbRed: 0x0C/255.0, green: 0x5F/255.0, blue: 0x49/255.0, alpha: 1)
    let grad = CGGradient(colorsSpace: space, colors: [bot, top] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad,
                           start: CGPoint(x: body.midX, y: body.minY),
                           end: CGPoint(x: body.midX, y: body.maxY),
                           options: [])
    ctx.restoreGState()

    // Two inward chevrons (normalized within the body). Y is flipped to
    // bottom-left origin: the "top" chevron (points down) sits at higher y.
    func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
        CGPoint(x: body.minX + nx * side, y: body.minY + (1 - ny) * side)
    }
    let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    ctx.setStrokeColor(white)
    ctx.setFillColor(white)
    ctx.setLineWidth(side * 0.072)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // "Compress" glyph: two chevrons squeezing toward a centre bar.
    // Top chevron sits in the upper half and points DOWN toward the bar.
    ctx.beginPath()
    ctx.move(to: p(0.30, 0.72)); ctx.addLine(to: p(0.50, 0.585)); ctx.addLine(to: p(0.70, 0.72))
    ctx.strokePath()
    // Bottom chevron sits in the lower half and points UP toward the bar.
    ctx.beginPath()
    ctx.move(to: p(0.30, 0.28)); ctx.addLine(to: p(0.50, 0.415)); ctx.addLine(to: p(0.70, 0.28))
    ctx.strokePath()

    // Centre bar — the thing being compressed. Rounded pill.
    let barW = side * 0.40, barH = side * 0.052
    let barRect = CGRect(x: body.midX - barW / 2, y: body.midY - barH / 2, width: barW, height: barH)
    ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
    ctx.fillPath()

    return ctx.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write("failed to create \(url.lastPathComponent)\n".data(using: .utf8)!); return
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes {
    guard let img = drawIcon(size: CGFloat(s)) else { print("draw failed \(s)"); continue }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(s).png")
    write(img, to: url)
    print("wrote icon_\(s).png")
}
