import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class VocabularyWorkspaceController: NSObject, NSWindowDelegate {
    static let shared = VocabularyWorkspaceController()
    private var window: NSWindow?
    let assistant = TranslateAssistant()
    func show(text: String? = nil, meaning: String = "") {
        if let text { assistant.receive(text: text, meaning: meaning) }
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = L10n.t("Dịch & Sổ từ vựng")
            window.minSize = NSSize(width: 980, height: 620)
            window.isReleasedWhenClosed = false; window.delegate = self
            window.contentView = NSHostingView(rootView: VocabularyWorkspaceView(assistant: assistant))
            window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { assistant.stop() }
}

struct VocabularyWorkspaceView: View {
    @Bindable var assistant: TranslateAssistant
    @State private var store = VocabularyStore.shared
    @State private var page = 0
    @State private var book = VocabularyLibrary.defaultWordbookID
    @State private var search = ""
    @State private var selected: UUID?
    @State private var editing: VocabularyCard?
    @State private var deleting: VocabularyCard?
    @State private var newBook = ""
    @State private var flipped = false
    @State private var reviewID: UUID?
    @State private var module = TranslationBlueprintModule.definition
    @State private var prompt = ""
    @State private var template = ""
    @State private var ioMessage: String?
    private let languages = ["und", "en", "vi", "zh", "ja", "ko"]
    private var cards: [VocabularyCard] {
        store.library.cards.filter { $0.wordbookID == book && (search.isEmpty || $0.term.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    private var currentCard: VocabularyCard? { store.library.cards.first { $0.id == selected } }
    private var due: [VocabularyCard] { store.library.dueCards(at: Date()).filter { $0.wordbookID == book } }
    private var reviewCard: VocabularyCard? { due.first { $0.id == reviewID } ?? due.first }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Text(L10n.t("Dịch & Sổ từ vựng")).font(.headline)
                Picker(L10n.t("Không gian"), selection: $page) {
                    Text(L10n.t("Tra từ")).tag(0)
                    Text(L10n.t("Ôn tập")).tag(1)
                    Text(L10n.t("Bản thiết kế prompt")).tag(2)
                }.pickerStyle(.segmented).frame(maxWidth: 430)
                Spacer()
                if store.isSaving { ProgressView().controlSize(.small) }
                Text(L10n.t(store.hasPersistedData ? "Đã lưu trên máy" : "Lưu trên máy")).font(.caption).foregroundStyle(.secondary)
                Menu(L10n.t("Nhập / Xuất")) {
                    Button(L10n.t("Nhập bản sao lưu JSON")) { importLibrary() }
                    Button(L10n.t("Xuất bản sao lưu JSON")) { exportFile(kind: "json") }
                    Button(L10n.t("Xuất thẻ Anki TSV")) { exportFile(kind: "tsv") }
                    Button(L10n.t("Xuất Prompt Markdown")) { exportFile(kind: "md") }
                    Button(L10n.t("Xuất Prompt JSON")) { exportFile(kind: "blueprints") }
                }.disabled(!store.isLoaded || store.isSaving)
            }.padding(16)
            Divider()
            if let issue = store.issue {
                Text(L10n.t(issueKey(issue))).foregroundStyle(.orange).padding(8).textSelection(.enabled)
            }
            if store.recoveredBackup { Text(L10n.t("Đã phục hồi bản sao lưu. File chính chỉ được thay khi bạn lưu thay đổi.")).foregroundStyle(.orange).padding(8) }
            if let ioMessage { Text(L10n.t(ioMessage)).foregroundStyle(.secondary).padding(6) }
            HStack(spacing: 0) {
                sidebar.frame(width: 210)
                Divider()
                Group {
                    if page == 0 { words }
                    else if page == 1 { review }
                    else { blueprints }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Text(L10n.t("Dữ liệu nằm trên máy. JSON giữ lịch ôn; TSV chỉ nhập nội dung thẻ vào Anki. Chưa cấu hình đồng bộ đám mây."))
                .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .sheet(item: $editing) { card in
            VocabularyCardEditor(card: card, store: store)
        }
        .alert(L10n.t("Xóa từ này?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(L10n.t("Hủy"), role: .cancel) { deleting = nil }
            Button(L10n.t("Xóa từ"), role: .destructive) {
                guard let card = deleting else { return }
                Task { if await store.removeCard(id: card.id) { selected = nil }; deleting = nil }
            }
        }
        .task { await store.load(); loadPrompt() }
        .onChange(of: prompt) { _, value in persistPrompt(value, user: false) }
        .onChange(of: template) { _, value in persistPrompt(value, user: true) }
        .onChange(of: module) { _, _ in assistant.invalidate(); loadPrompt() }
        .onChange(of: assistant.text) { _, _ in assistant.invalidate(); selected = nil }
        .onChange(of: assistant.context) { _, _ in assistant.invalidate() }
        .onChange(of: assistant.source) { _, _ in assistant.invalidate() }
        .onChange(of: assistant.target) { _, _ in assistant.invalidate() }
        .onChange(of: book) { _, _ in flipped = false; reviewID = nil; selected = nil }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("Sổ từ vựng")).font(.headline)
            List(selection: $book) {
                ForEach(store.library.wordbooks, id: \.id) { item in
                    Text(item.id == VocabularyLibrary.defaultWordbookID ? L10n.t("Từ đã lưu") : item.name).tag(item.id)
                }
            }.listStyle(.sidebar)
            TextField(L10n.t("Tên sổ mới"), text: $newBook).onSubmit { addBook() }
            Button(L10n.t("Tạo sổ")) { addBook() }.disabled(newBook.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isReadOnly || !store.isLoaded)
            Button(L10n.t("Cấu hình AI")) { AppState.shared.navigate(to: .voiceTyping); AppState.shared.bringMainWindowFront() }
            Text(L10n.t("Chỉ gửi văn bản và ngữ cảnh bạn nhập khi bấm Phân tích AI. Dùng nhà cung cấp ở trang Giọng nói."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(12)
    }

    private var words: some View {
        HStack(spacing: 0) {
            VStack {
                TextField(L10n.t("Tìm từ đã lưu"), text: $search).textFieldStyle(.roundedBorder).padding(12)
                List(selection: $selected) {
                    ForEach(cards, id: \.id) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.term).font(.headline)
                            Text(card.meaning).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(card.language.uppercased() + " · " + card.review.nextReviewAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4).tag(card.id)
                    }
                }
                if cards.isEmpty { Text(L10n.t("Chưa có từ trong sổ này.")).foregroundStyle(.secondary).padding() }
            }.frame(minWidth: 220, maxWidth: 300)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let card = currentCard { savedDetail(card) }
                    else { lookup }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbar { Button(L10n.t("Tra từ mới")) { selected = nil; assistant.receive(text: "", meaning: "") } }
    }

    private var lookup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("Tra từ theo ngữ cảnh")).font(.title2.bold())
            TextField(L10n.t("Từ hoặc cụm từ"), text: $assistant.text).textFieldStyle(.roundedBorder)
            HStack {
                Picker(L10n.t("Nguồn"), selection: $assistant.source) { ForEach(languages, id: \.self) { Text($0.uppercased()).tag($0) } }
                Picker(L10n.t("Đích"), selection: $assistant.target) { ForEach(Array(languages.dropFirst()), id: \.self) { Text($0.uppercased()).tag($0) } }
            }
            Text(L10n.t("Ngữ cảnh (không bắt buộc)")).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $assistant.context).frame(height: 70).border(Color.secondary.opacity(0.25))
            HStack {
                Button(L10n.t("Phân tích AI")) { assistant.analyze(module: .definition, overrides: store.library.blueprints) }
                    .disabled(assistant.busy || assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L10n.t("Từ điển trên máy")) { DictionaryLookup.open(assistant.text) }.disabled(assistant.text.isEmpty)
                Button { assistant.speak(assistant.text, language: assistant.source) } label: { Image(systemName: "speaker.wave.2") }.help(L10n.t("Phát âm")).disabled(assistant.text.isEmpty)
                if assistant.busy { ProgressView().controlSize(.small); Button(L10n.t("Hủy")) { assistant.invalidate() } }
            }
            if let key = assistant.messageKey { Text(L10n.t(key)).foregroundStyle(.orange) }
            Text(L10n.t("Nghĩa / bản dịch")).font(.caption)
            TextEditor(text: $assistant.meaning).frame(minHeight: 90).border(Color.secondary.opacity(0.25))
            if let result = assistant.definition {
                lexical(syllables: result.syllables, us: result.phoneticUS, uk: result.phoneticUK,
                    senses: result.definitions, synonyms: result.synonyms, etymology: result.etymology)
            }
            Button(L10n.t("Lưu vào sổ từ")) {
                let card = assistant.card(wordbook: book)
                Task { if let saved = await store.saveCard(card) { selected = saved.id } }
            }.buttonStyle(.borderedProminent).disabled(store.isReadOnly || !store.isLoaded || assistant.busy || assistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func savedDetail(_ card: VocabularyCard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(card.term).font(.largeTitle.bold()).textSelection(.enabled)
                Button { assistant.speak(card.term, language: card.language) } label: { Image(systemName: "speaker.wave.2") }.help(L10n.t("Phát âm"))
                Spacer()
                Button(L10n.t("Tra từ mới")) { selected = nil; assistant.receive(text: "", meaning: "") }
            }
            Text(card.meaning).font(.title3).textSelection(.enabled)
            Text(card.context).foregroundStyle(.secondary).textSelection(.enabled)
            lexical(syllables: card.syllables, us: card.phoneticUS, uk: card.phoneticUK, senses: card.definitions, synonyms: card.synonyms, etymology: card.etymology)
            if let provenance = card.provenance { Text(provenance).font(.caption).foregroundStyle(.secondary) }
            Text(L10n.t("Lần ôn tiếp theo")).font(.caption)
            Text(card.review.nextReviewAt.formatted(date: .long, time: .shortened)).monospacedDigit()
            HStack {
                Button(L10n.t("Chỉnh sửa từ")) { editing = card }.disabled(store.isReadOnly)
                Button(L10n.t("Xóa từ"), role: .destructive) { deleting = card }.disabled(store.isReadOnly)
            }
        }
    }
    private func lexical(syllables: String?, us: String?, uk: String?, senses: [VocabularyDefinition], synonyms: [String], etymology: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text([syllables, us, uk].compactMap { $0 }.joined(separator: " · ")).font(.system(.body, design: .monospaced))
            ForEach(Array(senses.enumerated()), id: \.offset) { _, sense in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sense.pos + " · " + sense.meaningVi).bold()
                    Text(sense.meaningEn)
                    Text(sense.exampleEn).italic()
                    Text(sense.exampleVi).foregroundStyle(.secondary)
                }.textSelection(.enabled)
            }
            if !synonyms.isEmpty { Text(synonyms.joined(separator: " · ")).textSelection(.enabled) }
            if let etymology { Text(etymology).foregroundStyle(.secondary).textSelection(.enabled) }
        }
    }

    private var review: some View {
        VStack(spacing: 22) {
            HStack { Text(L10n.t("Đến hạn ôn")).font(.title2.bold()); Text("\(due.count)").monospacedDigit() }
            if let card = reviewCard {
                Text(card.term).font(.largeTitle.bold()).textSelection(.enabled)
                Button(L10n.t("Phát âm")) { assistant.speak(card.term, language: card.language) }
                if flipped {
                    Text(card.meaning).font(.title2).textSelection(.enabled)
                    Text(card.context).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ratingButton(.again, key: "Lại · 10 phút", card: card)
                        ratingButton(.hard, key: "Khó", card: card)
                        ratingButton(.good, key: "Nhớ", card: card)
                        ratingButton(.easy, key: "Dễ", card: card)
                    }
                } else { Button(L10n.t("Hiện đáp án")) { flipped = true }.keyboardShortcut(.space, modifiers: []) }
            } else { Text(L10n.t("Không có thẻ đến hạn trong sổ này.")).foregroundStyle(.secondary) }
            Text(L10n.t("SM-2 với Lại sau 10 phút. Lịch này độc lập với bộ lập lịch của Anki.")).font(.caption).foregroundStyle(.secondary)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func ratingButton(_ rating: VocabularyRating, key: String, card: VocabularyCard) -> some View {
        let next = VocabularyReviewRules.reviewed(card.review, rating: rating, now: Date())
        return Button {
            Task { if await store.reviewCard(id: card.id, rating: rating) { flipped = false; reviewID = nil } }
        } label: {
            VStack { Text(L10n.t(key)); Text(next.nextReviewAt.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
        }.disabled(store.isSaving || store.isReadOnly)
    }

    private var blueprints: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(L10n.t("Mô-đun"), selection: $module) {
                        ForEach(TranslationBlueprintModule.allCases) { Text(L10n.t($0.titleKey)).tag($0) }
                    }
                    Text(L10n.t("Chỉ dẫn hệ thống")).font(.headline)
                    TextEditor(text: $prompt).font(.system(.body, design: .monospaced)).frame(height: 230)
                    Text(L10n.t("Mẫu đầu vào")).font(.headline)
                    TextEditor(text: $template).font(.system(.body, design: .monospaced)).frame(height: 100)
                    HStack {
                        Button(L10n.t("Lưu prompt")) {
                            let id = module.rawValue, system = prompt, user = template
                            Task {
                                let a = await store.saveBlueprint(id: id, text: system)
                                let b = await store.saveBlueprint(id: id + ".user", text: user)
                                ioMessage = a && b ? "Đã lưu prompt trên máy." : "Không lưu được dữ liệu. Hãy xuất bản sao lưu và thử lại."
                            }
                        }.disabled(store.isReadOnly || store.isSaving)
                        Button(L10n.t("Khôi phục prompt gốc")) {
                            let id = module.rawValue
                            Task { _ = await store.saveBlueprint(id: id, text: nil); _ = await store.saveBlueprint(id: id + ".user", text: nil); loadPrompt() }
                        }.disabled(store.isReadOnly || store.isSaving)
                    }
                    DisclosureGroup(L10n.t("Lược đồ JSON")) { Text(module.schemaJSON).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }.padding(18)
            }.frame(minWidth: 350)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("Thử prompt với dữ liệu thật")).font(.headline)
                    TextField(L10n.t("Từ hoặc cụm từ"), text: $assistant.text)
                    TextEditor(text: $assistant.context).frame(height: 80)
                    Button(L10n.t("Chạy bản nháp")) {
                        var overrides = store.library.blueprints
                        overrides[module.rawValue] = prompt; overrides[module.rawValue + ".user"] = template
                        assistant.analyze(module: module, overrides: overrides)
                    }.disabled(assistant.busy || assistant.text.isEmpty)
                    if assistant.busy { ProgressView(); Button(L10n.t("Hủy")) { assistant.invalidate() } }
                    if let key = assistant.messageKey { Text(L10n.t(key)).foregroundStyle(.orange) }
                    Text(assistant.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text(L10n.t("Prompt tự lưu trên máy. Làm sạch lời nói xử lý văn bản, không tự bật micro.")).font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.frame(minWidth: 300)
        }
    }
    private func persistPrompt(_ value: String, user: Bool) {
        guard store.isLoaded, !store.isReadOnly else { return }
        let id = module.rawValue + (user ? ".user" : "")
        let existing = store.library.blueprints[id] ?? (user ? module.userTemplate : module.systemInstruction)
        guard value != existing else { return }
        Task { _ = await store.saveBlueprint(id: id, text: value) }
    }
    private func loadPrompt() {
        prompt = store.library.blueprints[module.rawValue] ?? module.systemInstruction
        template = store.library.blueprints[module.rawValue + ".user"] ?? module.userTemplate
    }
    private func addBook() {
        let name = newBook
        Task { if let id = await store.addWordbook(name: name) { book = id; newBook = "" } }
    }
    private func importLibrary() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= VocabularyLibrary.maximumImportBytes else { throw VocabularyStore.Issue.invalidImport }
                    let data = try Data(contentsOf: url)
                    let ok = await store.importJSON(data)
                    ioMessage = ok ? "Đã nhập dữ liệu; giữ nguyên từ và lịch ôn đã có." : "File nhập không hợp lệ. Dữ liệu hiện tại được giữ nguyên."
                    if ok { loadPrompt() }
                } catch { ioMessage = "File nhập không hợp lệ. Dữ liệu hiện tại được giữ nguyên." }
            }
        }
    }
    private func exportFile(kind: String) {
        Task {
            do {
                let data: Data
                let extensionName: String
                switch kind {
                case "tsv": data = Data(store.library.ankiTSV().utf8); extensionName = "tsv"
                case "md": data = Data(TranslationBlueprintExport(customizations: store.library.blueprints).markdown().utf8); extensionName = "md"
                case "blueprints": data = try TranslationBlueprintExport(customizations: store.library.blueprints).json(); extensionName = "json"
                default: data = try await store.exportJSON(); extensionName = "json"
                }
                let panel = NSSavePanel(); panel.nameFieldStringValue = "XFinder-\(kind).\(extensionName)"
                panel.allowedContentTypes = [UTType(filenameExtension: extensionName) ?? .data]
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    do { try data.write(to: url, options: .atomic) } catch { ioMessage = "Không xuất được file. Hãy chọn vị trí có quyền ghi." }
                }
            } catch { ioMessage = "Không xuất được file. Hãy chọn vị trí có quyền ghi." }
        }
    }
    private func issueKey(_ issue: VocabularyStore.Issue) -> String {
        switch issue {
        case .corrupt, .unreadable: return "Không đọc được sổ từ. File gốc được giữ nguyên; hãy kiểm tra thư mục Wordbook."
        case .unsupportedVersion: return "Dữ liệu được tạo bởi phiên bản mới hơn. Không ghi đè file này."
        case .backupFailed: return "Đã lưu file chính nhưng chưa tạo được bản sao lưu. Hãy xuất JSON."
        case .invalidImport: return "Dữ liệu không hợp lệ. Chưa lưu thay đổi."
        case .writeFailed: return "Không lưu được dữ liệu. Hãy xuất bản sao lưu và thử lại."
        }
    }
}

private struct VocabularyCardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var card: VocabularyCard
    var store: VocabularyStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Chỉnh sửa từ")).font(.title2.bold())
            TextField(L10n.t("Từ hoặc cụm từ"), text: $card.term)
            Text(L10n.t("Nghĩa / bản dịch"))
            TextEditor(text: $card.meaning).frame(height: 120)
            Text(L10n.t("Ngữ cảnh (không bắt buộc)"))
            TextEditor(text: $card.context).frame(height: 80)
            if store.issue != nil { Text(L10n.t("Không lưu được dữ liệu. Hãy xuất bản sao lưu và thử lại.")).foregroundStyle(.orange) }
            HStack {
                Button(L10n.t("Hủy")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.t("Lưu")) {
                    let snapshot = card
                    Task { if await store.saveCard(snapshot) != nil { dismiss() } }
                }.keyboardShortcut(.defaultAction).disabled(store.isSaving || card.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || card.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 500)
    }
}
