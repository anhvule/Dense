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

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: card.symbol).font(.system(size: 22))
            Text(card.title).font(.system(size: 12, weight: .medium))
            Text(card.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1))
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        .accessibilityLabel("\(card.title) preset\(isSelected ? ", selected" : "")")
    }
}
