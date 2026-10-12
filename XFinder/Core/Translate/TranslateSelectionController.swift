import AppKit
import Carbon
import SwiftUI

/// N5a — the live half of "Dịch vùng chọn": a Carbon hotkey (⇧⌘G, the same mechanism as ⌘K), the Accessibility read
/// of the focused element's selection (the Voice module's helper), and a floating panel at the Spotlight position
/// hosting Apple's translation popover. ONE reader of `translate.hotkeyEnabled`. Off ⇒ no hotkey, no panel.
@MainActor
final class TranslateSelectionController {
    static let shared = TranslateSelectionController()

    private var hotKeyRef: EventHotKeyRef?
    private var carbonHandler: EventHandlerRef?
    private var panel: SurfacePanel?
    let model = TranslateSelectionModel()

    private init() {}

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "translate.hotkeyEnabled") as? Bool ?? false }

    func applySettings() {
        if isEnabled { registerHotkey() } else { unregisterHotkey(); panel?.hide() }
    }

    // MARK: Hotkey (Carbon, like QuickSearchPanelController)

    /// 'XFtr' — this feature's own signature, so its handler ignores ⌘K's events and vice versa.
    private static let signature: OSType = 0x58467472
    private static let hotKeyID: UInt32 = 2

    private func registerHotkey() {
        installCarbonHandlerIfNeeded()
        guard hotKeyRef == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(TranslateSelectionRules.keyCodeG, UInt32(cmdKey | shiftKey),
                                         EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr { hotKeyRef = ref }
    }

    private func unregisterHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installCarbonHandlerIfNeeded() {
        guard carbonHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == TranslateSelectionController.signature, id.id == TranslateSelectionController.hotKeyID
            else { return OSStatus(eventNotHandledErr) }
            let c = Unmanaged<TranslateSelectionController>.fromOpaque(userData).takeUnretainedValue()
            c.hotkeyFired()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &carbonHandler)
    }

    private nonisolated func hotkeyFired() {
        Task { @MainActor in self.translateSelection() }
    }

    // MARK: The action

    /// Read the selection NOW (before any panel takes focus), decide, show.
    func translateSelection() {
        let verdict = TranslateSelectionRules.verdict(for: VoiceScreenContext.selectedText())
        model.sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        model.translated = nil
        switch verdict {
        case .translate(let text):
            model.text = text
            model.messageKey = nil
            model.requestPresentation += 1
        default:
            model.text = ""
            model.messageKey = TranslateSelectionRules.messageKey(for: verdict)
        }
        if panel == nil {
            let p = SurfacePanel(kind: .interactive, size: CGSize(width: 520, height: 300))
            p.host(TranslateSelectionView(model: model))
            panel = p
        }
        panel?.show(anchor: .spotlight)
        panel?.installClickOutside { [weak self] in self?.panel?.hide() }
    }

    func dismiss() { panel?.hide() }

    func copyTranslation() {
        guard let t = model.translated, !t.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents(); pb.setString(t, forType: .string)
        ClipboardSounds.playCopy()
    }
}

/// What the panel shows. Mutated by the controller; `requestPresentation` ticks to re-open Apple's popover.
@MainActor
@Observable
final class TranslateSelectionModel {
    var text = ""
    var sourceApp: String?
    var messageKey: String?
    var translated: String?
    var requestPresentation = 0
}
