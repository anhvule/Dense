# Visual Polish: Adaptive Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Checkbox steps.

**Goal:** Take the approved dock + shrink-meter layout from stock-SwiftUI to a sleek, professional "adaptive glass" finish: translucent full-bleed window, layered material cards with hover/selection depth, one violet brand accent, disciplined typography, and spring motion. Layout and behavior unchanged.

**Architecture:** A small `Theme` (tokens + reusable card/glass modifiers + NSVisualEffectView wrapper) consumed by restyled views. No engine changes; no new behavior; all gates are build/launch (styling has no unit-test surface).

**Tech Stack:** SwiftUI materials, NSVisualEffectView, SF Symbols hierarchical rendering.

## Global Constraints

- Behavior is untouched: same views, same actions, same copy (rejection banner string byte-identical), same accessibility labels from R3/R4 fixes.
- Both appearances supported (adaptive); every custom color has light+dark variants.
- Accent: violet — light mode #5B4FD6, dark mode #7F77DD. System blue must no longer appear as selection/progress color anywhere in the main window.
- All numerals displaying sizes/percentages use `.monospacedDigit()`.
- Gates per task: `xcodegen generate && xcodebuild -project Dense.xcodeproj -scheme Dense -configuration Debug build` BUILD SUCCEEDED with zero new source warnings; app launches/quits cleanly; `cd DenseCore && swift test` still 46/46 (should be untouched).

---

### Task P1: Theme, window chrome, dock restyle

**Files:**
- Create: `App/Theme.swift`
- Modify: `App/DenseApp.swift` (window style), `App/MainView.swift` (background + header placement), `App/DestinationDockView.swift` (card restyle)

**Step 1 — Theme.swift (complete):**

```swift
// App/Theme.swift
import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.498, green: 0.467, blue: 0.867, alpha: 1)   // #7F77DD
            : NSColor(red: 0.357, green: 0.310, blue: 0.839, alpha: 1)   // #5B4FD6
    })
    static let success = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.365, green: 0.792, blue: 0.647, alpha: 1)   // #5DCAA5
            : NSColor(red: 0.059, green: 0.431, blue: 0.337, alpha: 1)   // #0F6E56
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
```

**Step 2 — Window chrome:** in `DenseApp.swift`, add `.windowStyle(.hiddenTitleBar)` to the WindowGroup. In `MainView`, set `.background(GlassBackground().ignoresSafeArea())` on the outermost VStack; give the content `.padding(.top, 6)` so the header clears the traffic lights; header keeps "Dense" (13pt, `.semibold`, `.secondary`) + batch stats (`.monospacedDigit()`), buttons `.buttonStyle(.borderless)` tinted `Theme.accent` for the advanced-toggle icon only.

**Step 3 — Dock cards (`DockCard` in DestinationDockView.swift):** replace the flat fill/stroke with:

```swift
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
```

Keep tap/drop handlers and the card list identical.

**Step 4 — Gates + commit** `feat: adaptive-glass theme, window chrome, dock card polish`.

---

### Task P2: Rows, empty state, advanced panel, motion

**Files:**
- Modify: `App/FileRowView.swift`, `App/MainView.swift`, `App/AdvancedPanelView.swift`

**Step 1 — Rows:** replace `List(queue.jobs)` in MainView with:

```swift
ScrollView {
    LazyVStack(spacing: 8) {
        ForEach(queue.jobs) { FileRowView(job: $0) }
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: queue.jobs.count)
}
```

In FileRowView: wrap the HStack content in `.padding(10).glassCard(radius: Theme.rowRadius)`; thumbnail 56×38 radius 6, with a small `play.fill` overlay glyph bottom-left on the thumbnail when present; add `.transition(.move(edge: .top).combined(with: .opacity))` on the row. SizeBar: track `Color.primary.opacity(0.08)`; fill `Theme.accent` while running and `Theme.success` when done; animation becomes `.spring(response: 0.5, dampingFraction: 0.75)`; on `.done` also overlay a `checkmark.circle.fill` (Theme.success, 13pt) appearing next to the savings % with `.transition(.scale.combined(with: .opacity))`. All byte/percent Texts get `.monospacedDigit()`. Replace `.green`/`.red` foregrounds: success → `Theme.success`, failure text stays `.red` (system red is correct for errors). Keep every accessibility label from the R3 fixes verbatim.

**Step 2 — Empty state:** dashed drop target instead of bare icon:

```swift
VStack(spacing: 10) {
    Image(systemName: "arrow.down.doc").font(.system(size: 40, weight: .light))
        .symbolRenderingMode(.hierarchical).foregroundStyle(Theme.accent)
    Text("Drop videos anywhere — or onto a destination")
        .font(.callout).foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.background(RoundedRectangle(cornerRadius: Theme.cardRadius)
    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    .foregroundStyle(Color.primary.opacity(0.15)))
.padding(.horizontal, 14).padding(.bottom, 12)
```

**Step 3 — Advanced panel:** `.padding(14).glassCard()` instead of the flat controlBackgroundColor fill; each `label()` gains a leading 14pt hierarchical SF Symbol (Format→`shippingbox`, Resolution→`aspectratio`, Target size→`scalemass`, Audio→`speaker.wave.2`, Output→`folder`, Suffix→`textformat`, Folder→`folder.badge.gearshape`, Originals→`trash`, GIF mode→`photo.stack`); panel appears/disappears with `.transition(.move(edge: .top).combined(with: .opacity))` (MainView already animates the toggle). Pickers/steppers keep bindings identical; `.tint(Theme.accent)` on the panel container so toggles/steppers pick up the brand color.

**Step 4 — Rejection banner:** same string, restyled: `.font(.caption.weight(.medium))`, `.padding(.vertical, 6).padding(.horizontal, 12)`, `.background(Capsule().fill(.orange.opacity(0.15)))`, `.foregroundStyle(.orange)`.

**Step 5 — Gates + commit** `feat: glass rows, empty state, advanced panel polish and motion`.

## Self-Review (at write time)

- Constraints traced: accent replaces system blue (dock selection P1, SizeBar fill + panel tint P2); monospaced digits (P2 step 1, P1 header); copy/labels preserved (explicit in P2 step 1); both appearances (Theme dynamic NSColor providers). Placeholder scan: none. Type consistency: `Theme.accent`/`glassCard()` defined P1, consumed P2; `AnyShapeStyle` needed for the material/color ternary — included.
