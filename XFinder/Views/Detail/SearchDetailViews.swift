import SwiftUI
import AppKit

/// Shared result-row UI for the Tìm kiếm / Tìm kiếm AI pages.
struct FileResultRow: View {
    let item: FileSearchEngine.ResultItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: NSWorkspace.shared.icon(forFile: item.path).isTemplate ? "doc.fill" : "doc.fill")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(item.path).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Mở") { NSWorkspace.shared.open(URL(fileURLWithPath: item.path)) }
                .buttonStyle(.link).font(.system(size: 11))
            Button("Hiện trong Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            }
            .buttonStyle(.link).font(.system(size: 11))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }
}

/// Tìm kiếm — structured Spotlight search (name + kind + recency), optionally
/// scoped to chosen folders. Runs `mdfind` on a background task.
struct FinderSearchDetailView: View {
    @State private var criteria = FileSearchEngine.Criteria()
    @State private var scopes: [URL] = []
    @State private var results: [FileSearchEngine.ResultItem] = []
    @State private var isSearching = false
    @State private var searched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tìm kiếm")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                SettingsCard(title: "Tên tập tin") {
                    TextField("Ví dụ: báo cáo", text: $criteria.nameContains)
                        .textFieldStyle(.roundedBorder).font(.system(size: 12))
                        .onSubmit { run() }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Loại & thời gian") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Loại", selection: $criteria.kind) {
                            ForEach(FileSearchEngine.Criteria.KindFilter.allCases) { k in
                                Text(k.titleVI).tag(k)
                            }
                        }
                        .pickerStyle(.menu).frame(maxWidth: 220)
                        Picker("Sửa đổi", selection: Binding(
                            get: { criteria.modifiedWithinDays ?? 0 },
                            set: { criteria.modifiedWithinDays = $0 == 0 ? nil : $0 })) {
                                Text("Mọi lúc").tag(0)
                                Text("Hôm nay").tag(1)
                                Text("7 ngày qua").tag(7)
                                Text("30 ngày qua").tag(30)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal, 20)

                SettingsCard(title: "Phạm vi",
                             subtitle: scopes.isEmpty ? "Toàn máy" : "\(scopes.count) thư mục") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Thêm thư mục…") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.allowsMultipleSelection = true
                                if panel.runModal() == .OK { scopes = panel.urls }
                            }
                            if !scopes.isEmpty {
                                Button("Toàn máy") { scopes = [] }.font(.system(size: 12))
                            }
                        }
                        ForEach(scopes, id: \.self) { url in
                            HStack {
                                Text(url.path).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Button { scopes.removeAll { $0 == url } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    run()
                } label: {
                    HStack {
                        if isSearching { ProgressView().scaleEffect(0.7) }
                        Text(isSearching ? "Đang tìm…" : "Tìm kiếm")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSearching)
                .padding(.horizontal, 20)

                SettingsCard(title: searched
                             ? (results.isEmpty ? "Không tìm thấy gì" : "\(results.count) kết quả")
                             : "Kết quả") {
                    VStack(spacing: 6) {
                        ForEach(results.prefix(50)) { item in
                            FileResultRow(item: item)
                        }
                        if results.count > 50 {
                            Text("…và \(results.count - 50) kết quả nữa — hãy thu hẹp điều kiện.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func run() {
        let crit = criteria
        let sc = scopes
        isSearching = true
        Task.detached(priority: .userInitiated) {
            let found = FileSearchEngine.search(criteria: crit, scopes: sc)
            await MainActor.run {
                results = found
                searched = true
                isSearching = false
            }
        }
    }
}

/// Tìm kiếm AI — type a natural sentence (Vietnamese or English); the on-device
/// rule parser turns it into a Spotlight query and explains what it understood.
/// No network, no model download, no fabricated answers.
struct AiSearchDetailView: View {
    @State private var queryText = ""
    @State private var explanation: String? = nil
    @State private var results: [FileSearchEngine.ResultItem] = []
    @State private var isSearching = false
    @State private var searched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tìm kiếm AI")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.horizontal, 20).padding(.top, 16)

                SettingsCard(title: "Hỏi bằng câu tự nhiên",
                             subtitle: "100% trên máy — ví dụ: “ảnh sửa tuần này”") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Ví dụ: video mới tháng này, pdf báo cáo…", text: $queryText)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12))
                            .onSubmit { run() }
                        Text("Gợi ý: loại (ảnh, video, pdf, thư mục…) + thời gian (hôm nay, tuần này…) + tên trong “ngoặc kép”.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    run()
                } label: {
                    HStack {
                        if isSearching { ProgressView().scaleEffect(0.7) }
                        Text(isSearching ? "Đang tìm…" : "Tìm bằng AI")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                .padding(.horizontal, 20)

                if let expl = explanation {
                    SettingsCard(title: "AI hiểu") {
                        Text(expl).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                }

                SettingsCard(title: searched
                             ? (results.isEmpty ? "Không tìm thấy gì" : "\(results.count) kết quả")
                             : "Kết quả") {
                    VStack(spacing: 6) {
                        ForEach(results.prefix(50)) { item in
                            FileResultRow(item: item)
                        }
                        if results.count > 50 {
                            Text("…và \(results.count - 50) kết quả nữa.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func run() {
        let text = queryText
        isSearching = true
        Task.detached(priority: .userInitiated) {
            let (query, expl) = FileSearchEngine.parseNaturalLanguage(text)
            let found = FileSearchEngine.runMdfind(query: query)
            await MainActor.run {
                explanation = expl
                results = found
                searched = true
                isSearching = false
            }
        }
    }
}
