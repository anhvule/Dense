// App/DestinationDockView.swift
import SwiftUI
import DenseCore
import UniformTypeIdentifiers

struct DockPreset: Identifiable {
    let preset: Preset
    let symbol: String
    let title: String
    let subtitle: String
    var id: String { preset.rawValue }
}

struct DestinationDockView: View {
    @Binding var selected: Preset
    let onDropToPreset: (Preset, [NSItemProvider]) -> Void

    static let cards: [DockPreset] = [
        .init(preset: .discord, symbol: "bubble.left.and.bubble.right", title: "Discord", subtitle: "≤ 25 MB"),
        .init(preset: .email, symbol: "envelope", title: "Email", subtitle: "≤ 25 MB"),
        .init(preset: .youtube, symbol: "play.rectangle", title: "YouTube", subtitle: "Quality"),
        .init(preset: .webSocial, symbol: "globe", title: "Web / Social", subtitle: "1080p"),
        .init(preset: .balanced, symbol: "slider.horizontal.3", title: "Custom", subtitle: "Your rules"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Self.cards) { card in
                DockCard(card: card, isSelected: selected == card.preset)
                    .onTapGesture { selected = card.preset }
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        onDropToPreset(card.preset, providers)
                        return true
                    }
            }
        }
        .padding(.horizontal, 14)
    }
}

private struct DockCard: View {
    let card: DockPreset
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: card.symbol)
                .font(.system(size: 24, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(card.title).font(.system(size: 12, weight: .semibold))
            Text(card.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .fill(isSelected ? AnyShapeStyle(Theme.accent.opacity(0.16)) : AnyShapeStyle(.regularMaterial)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .strokeBorder(isSelected ? Theme.accent : Color.primary.opacity(0.08),
                          lineWidth: isSelected ? 1.5 : 1))
        .foregroundStyle(isSelected ? Theme.accent : Color.primary)
        .shadow(color: isSelected ? Theme.accent.opacity(0.30) : .black.opacity(hovering ? 0.18 : 0),
                radius: isSelected ? 10 : 8, y: 2)
        .scaleEffect(hovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(card.title) preset\(isSelected ? ", selected" : "")")
    }
}
