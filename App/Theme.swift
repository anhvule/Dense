// App/Theme.swift
import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.114, green: 0.620, blue: 0.459, alpha: 1)   // #1D9E75
            : NSColor(red: 0.059, green: 0.431, blue: 0.337, alpha: 1)   // #0F6E56
    })
    static let success = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.592, green: 0.769, blue: 0.349, alpha: 1)   // #97C459
            : NSColor(red: 0.231, green: 0.427, blue: 0.067, alpha: 1)   // #3B6D11
    })
    static let cardRadius: CGFloat = 12
    static let rowRadius: CGFloat = 10
}

/// Translucent desktop-tinted window backdrop (the "glass").
struct GlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

extension View {
    func glassCard(radius: CGFloat = Theme.cardRadius) -> some View { modifier(GlassCard(radius: radius)) }
}
