// App/ConfettiView.swift
import SwiftUI
import AppKit

/// Lightweight, non-interactive confetti burst layered over the main
/// window's content. Bind `trigger` to a monotonically-incrementing counter
/// (`AppEnvironment.confettiTrigger`); every change to that value fires a
/// fresh burst from the top of the view. Self-clears within ~1.5s.
///
/// `AppEnvironment` already gates *whether* `confettiTrigger` advances on
/// `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, so this view
/// doesn't need to check that itself — but it's harmless/idempotent if it's
/// ever driven from somewhere else that forgets to.
struct ConfettiView: NSViewRepresentable {
    var trigger: Int

    func makeNSView(context: Context) -> ConfettiHostView {
        ConfettiHostView()
    }

    func updateNSView(_ nsView: ConfettiHostView, context: Context) {
        guard context.coordinator.lastTrigger != trigger else { return }
        context.coordinator.lastTrigger = trigger
        nsView.burst()
    }

    func makeCoordinator() -> Coordinator { Coordinator(lastTrigger: trigger) }

    final class Coordinator {
        var lastTrigger: Int
        init(lastTrigger: Int) { self.lastTrigger = lastTrigger }
    }
}

/// Hosts a single `CAEmitterLayer` confetti burst. Never intercepts hit
/// testing so it can be layered over interactive content (the drop target,
/// file list, buttons) without stealing clicks or drags.
final class ConfettiHostView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()
        layer.masksToBounds = true
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func burst() {
        guard let hostLayer = layer, bounds.width > 0, bounds.height > 0 else { return }
        hostLayer.sublayers?.filter { $0.name == "confetti" }.forEach { $0.removeFromSuperlayer() }

        let emitter = CAEmitterLayer()
        emitter.name = "confetti"
        // AppKit views are y-up by default (no `isFlipped` override here),
        // so "top of the content" is the max-y edge; particles fall toward
        // -y via `yAcceleration` below.
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY)
        emitter.emitterSize = CGSize(width: bounds.width * 0.6, height: 1)
        emitter.emitterShape = .line
        emitter.renderMode = .unordered
        emitter.emitterCells = Self.colors.flatMap { color in
            [Self.makeCell(color: color, rounded: true), Self.makeCell(color: color, rounded: false)]
        }
        emitter.beginTime = CACurrentMediaTime()
        hostLayer.addSublayer(emitter)

        // Stop birthing new particles quickly (a "burst", not a fountain),
        // then remove the whole layer once the longest-lived particle from
        // that burst has finished falling — comfortably inside the ≤1.5s
        // budget from the brief.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak emitter] in
            emitter?.removeFromSuperlayer()
        }
    }

    // Teal/green (Theme.accent/success, dark-appearance values — legible on
    // both light and dark backdrops since these are additive confetti bits,
    // not text) plus a warm amber accent.
    private static let colors: [NSColor] = [
        NSColor(red: 0.114, green: 0.620, blue: 0.459, alpha: 1),
        NSColor(red: 0.592, green: 0.769, blue: 0.349, alpha: 1),
        NSColor(red: 0.937, green: 0.702, blue: 0.204, alpha: 1),
    ]

    private static func makeCell(color: NSColor, rounded: Bool) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = 9
        cell.lifetime = 1.1
        cell.lifetimeRange = 0.25
        cell.velocity = 260
        cell.velocityRange = 90
        // Emit in a downward-opening cone: straight down is -90° (-.pi/2)
        // from the positive-x axis in this y-up coordinate space.
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi / 3
        cell.yAcceleration = -420
        cell.spin = 3.5
        cell.spinRange = 5
        cell.scale = 0.5
        cell.scaleRange = 0.2
        cell.alphaSpeed = -0.6
        cell.color = color.cgColor
        cell.contents = Self.shapeImage(color: color, rounded: rounded)
        return cell
    }

    private static func shapeImage(color: NSColor, rounded: Bool) -> CGImage? {
        let side = 7
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(color.cgColor)
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        if rounded { ctx.fillEllipse(in: rect) } else { ctx.fill(rect) }
        return ctx.makeImage()
    }
}
