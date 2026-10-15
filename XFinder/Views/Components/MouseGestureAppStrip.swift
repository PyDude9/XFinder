import SwiftUI
import AppKit

/// One chip of the app strip (variant B, block 3).
struct MouseGestureAppChip: Identifiable, Equatable {
    /// The bundle id, or `GestureProfiles.fallback` ("*") for the pinned Global chip.
    let id: String
    /// The short name drawn next to the icon.
    let title: String
    /// A built-in preset the user does not have installed — dashed border, the wireframe's `b-ghost-chip`.
    let isGhost: Bool
    /// The app in front, while the page shows a *different* app: draws the small top-right dot
    /// (the wireframe's `b-dot`). False when nothing is in front.
    let showsDot: Bool
}

/// Variant B, block 3 — the app chooser as ONE horizontal strip of chips.
///
/// Replaces the old 240-pt `profileSidebar` column (Lỗi #8: two sidebars for one question).
/// The Global chip is pinned first so the anchor every app-without-a-preset falls back to is
/// visible before any scrolling; every chip carries the app's real icon, its short name, and an
/// accent border while it is the profile being viewed. Overflow scrolls *inside* the strip —
/// per the contract this is the only place on the page where horizontal scroll is allowed.
struct MouseGestureAppStrip: View {
    let chips: [MouseGestureAppChip]
    /// The bundle id currently being viewed (`profile`).
    let selected: String
    /// The real icon for a bundle id, or `nil` (Global, or an app that is not installed).
    let icon: (String) -> NSImage?
    let onSelect: (String) -> Void
    /// The trailing "＋" chip: expands the "Nâng cao — ứng dụng khác" disclosure below.
    let onAdd: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: XFinderTokens.Space.tight) {
                    if let global = chips.first {
                        chipView(global).id(global.id)
                        // The wireframe separates the pinned Global chip from the app list.
                        if chips.count > 1 { separator }
                    }
                    ForEach(Array(chips.dropFirst())) { chip in
                        chipView(chip).id(chip.id)
                    }
                    addChip
                }
                // Headroom for the dot's -2 pt offset so a selected chip's dot is never clipped.
                .padding(.vertical, 3)
            }
            // The SwiftUI equivalent of the wireframe's `scrollIntoView`: on open, and whenever
            // the viewed app changes, bring its chip to the middle of the strip.
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, id in
                withAnimation(.easeOut(duration: XFinderTokens.Motion.overlayIn)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func chipView(_ chip: MouseGestureAppChip) -> some View {
        let isSelected = chip.id == selected
        return Button { onSelect(chip.id) } label: {
            HStack(spacing: XFinderTokens.Space.tight) {
                chipIcon(chip)
                Text(chip.title)
                    .font(XFinderTokens.Font.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(height: 28)
            .background(Capsule().fill(chip.isGhost ? XFinderTokens.Fill.inset : Color.clear))
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.accentColor : XFinderTokens.Fill.hairline,
                    style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1,
                                        dash: chip.isGhost && !isSelected ? [3, 3] : []))
            )
            .overlay(alignment: .topTrailing) {
                if chip.showsDot {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7).offset(x: 2, y: -2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(chip.isGhost ? L10n.t("Chưa cài — đang xem preset dựng sẵn") : chip.title)
        .accessibilityLabel(chip.showsDot
                            ? L10n.t("Ứng dụng đang dùng") + ": " + chip.title
                            : chip.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func chipIcon(_ chip: MouseGestureAppChip) -> some View {
        if chip.id == GestureProfiles.fallback {
            Image(systemName: "globe")
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .frame(width: 16, height: 16)
        } else if let image = icon(chip.id) {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: 16, height: 16).cornerRadius(3)
        } else {
            Image(systemName: "app")
                .font(XFinderTokens.Font.caption).foregroundColor(.secondary)
                .frame(width: 16, height: 16)
        }
    }

    /// The "＋" chip — same height and capsule as a chip so the strip reads as one row.
    private var addChip: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(XFinderTokens.Font.caption.weight(.semibold))
                .frame(height: 28)
                .padding(.horizontal, 10)
                .overlay(Capsule().strokeBorder(XFinderTokens.Fill.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(L10n.t("Thêm ứng dụng khác bằng Bundle ID"))
        .accessibilityLabel(L10n.t("Thêm ứng dụng khác bằng Bundle ID"))
    }

    private var separator: some View {
        Rectangle().fill(XFinderTokens.Fill.hairline).frame(width: 1, height: 20)
    }
}
