// App/Destination.swift
import DenseCore

/// A sidebar destination: presentation + the preset (and PDF budget) it maps to.
struct Destination: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let preset: Preset
    let pdfQuality: PDFQuality
    /// PDFs share the destination's byte budget with videos.
    var pdfTargetMB: Double? { preset.targetSizeMB }

    static let all: [Destination] = [
        .init(id: "discord", title: "Discord", subtitle: "≤ 25 MB",
              symbol: "bubble.left.and.bubble.right", preset: .discord, pdfQuality: .balanced),
        .init(id: "slack", title: "Slack", subtitle: "≤ 50 MB",
              symbol: "message", preset: .slack, pdfQuality: .balanced),
        .init(id: "email10", title: "Email — strict", subtitle: "≤ 10 MB",
              symbol: "envelope", preset: .emailSmall, pdfQuality: .small),
        .init(id: "email25", title: "Email", subtitle: "≤ 25 MB",
              symbol: "envelope.open", preset: .email, pdfQuality: .balanced),
        .init(id: "web", title: "Web / Social", subtitle: "1080p",
              symbol: "globe", preset: .webSocial, pdfQuality: .balanced),
        .init(id: "youtube", title: "YouTube", subtitle: "Quality-first",
              symbol: "play.rectangle", preset: .youtube, pdfQuality: .good),
        .init(id: "custom", title: "Custom", subtitle: "Your rules",
              symbol: "slider.horizontal.3", preset: .balanced, pdfQuality: .balanced),
    ]

    static func byID(_ id: String) -> Destination {
        all.first { $0.id == id } ?? all.first { $0.id == "email25" }!
    }
}
