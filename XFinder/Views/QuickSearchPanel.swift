import SwiftUI
import AppKit

/// UI của bảng lệnh toàn cục — y như Spotlight/Raycast/TinyCast: ô tìm trên
/// cùng, danh sách kết quả phẳng bên dưới, dòng đang chọn nổi bật.
/// Dùng chung `QuickSearchEngine` với khối Tìm nhanh trong trang Tìm kiếm.
struct QuickSearchPanelView: View {
    @State private var controller = QuickSearchPanelController.shared
    @State private var engine = QuickSearchEngine.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Ô tìm
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary).font(.system(size: 16))

                TextField("Tìm ứng dụng, tập tin, quicklink, hoặc tính toán…",
                          text: Bindable(controller).query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onChange(of: controller.query) { _, newValue in
                        controller.queryChanged(newValue)
                    }
                    .onSubmit { controller.executeSelected() }

                if engine.isSearching {
                    ProgressView().scaleEffect(0.6).controlSize(.small)
                }
                if !controller.query.isEmpty {
                    Button {
                        controller.query = ""
                        controller.queryChanged("")
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            Divider()

            // Kết quả
            if engine.results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(engine.results.enumerated()), id: \.offset) { index, result in
                                QuickSearchPanelRow(result: result, isSelected: index == controller.selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        controller.selectedIndex = index
                                        controller.executeSelected()
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: controller.selectedIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 640, height: 460)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.12))
        )
        .onAppear {
            fieldFocused = true
            // Focus trong `.nonactivatingPanel` có thể trễ một nhịp; đặt lại
            // sau 0.15s để gõ ngay khi panel vừa mở.
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                fieldFocused = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "command.circle")
                .font(.system(size: 34)).foregroundColor(.secondary)
            Text("Gõ để tìm — ứng dụng, tập tin, quicklink, phép tính")
                .font(.system(size: 13)).foregroundColor(.secondary)
            Text("↵ thực thi dòng đầu · ↑/↓ di chuyển · Esc đóng")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Một dòng kết quả trong bảng lệnh: icon + tên + mô tả + nhãn loại,
/// nền xanh khi đang được chọn.
struct QuickSearchPanelRow: View {
    let result: QuickSearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon = result.icon {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: result.type.symbolName)
                    .font(.system(size: 15)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(result.subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(result.type.titleVI)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}