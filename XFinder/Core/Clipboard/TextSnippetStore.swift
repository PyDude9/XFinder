import AppKit
import Foundation

/// Local JSON-backed store for Text Snippets (`~/Library/Application Support/XFinder/snippets.json`).
@MainActor
@Observable
final class TextSnippetStore {
    static let shared = TextSnippetStore()

    private(set) var snippets: [TextSnippet] = []
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("XFinder", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("snippets.json")
        load()
    }

    @discardableResult
    func add(trigger: String, expansion: String) -> TextSnippetRules.ValidationError? {
        if let err = TextSnippetRules.validate(trigger: trigger, expansion: expansion, existing: snippets) {
            return err
        }
        let item = TextSnippet(
            trigger: TextSnippetRules.normalizedTrigger(trigger),
            expansion: expansion,
            isEnabled: true
        )
        snippets.append(item)
        save()
        TextSnippetExpander.shared.applySettings()
        return nil
    }

    func toggle(id: UUID) {
        guard let idx = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[idx].isEnabled.toggle()
        save()
        TextSnippetExpander.shared.applySettings()
    }

    func delete(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
        TextSnippetExpander.shared.applySettings()
    }

    func copyExpanded(_ snippet: TextSnippet) {
        let pb = NSPasteboard.general
        let currentClip = pb.string(forType: .string)
        let expanded = TextSnippetRules.expand(snippet.expansion, now: Date(), clipboardText: currentClip)
        pb.clearContents()
        pb.setString(expanded, forType: .string)
    }

    func quickSearchResults(query: String) -> [QuickSearchResult] {
        TextSnippetRules.search(query: query, snippets: snippets).map { item in
            QuickSearchResult(
                type: .snippet,
                title: item.trigger,
                subtitle: item.expansion,
                icon: nil,
                action: { [weak self] in
                    Task { @MainActor in self?.copyExpanded(item) }
                }
            )
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TextSnippet].self, from: data) else {
            return
        }
        snippets = decoded
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snippets) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
