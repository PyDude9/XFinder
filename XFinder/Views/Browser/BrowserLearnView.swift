import SwiftUI

/// Lessons never infer completion from clicks or change the person's files.
struct BrowserLearnView: View {
    @AppStorage(BrowserLearnProgress.key) private var progress = Data()

    private let lessons: [(id: String, title: String, body: String)] = [
        ("navigation", "Đi đến thư mục", "Chọn một thư mục ở thanh bên. Nhấp đúp thư mục để mở; dùng nút Quay lại và Tiến tới để đi qua lịch sử. Thanh đường dẫn ở đáy giúp quay về thư mục cha."),
        ("tabs", "Làm việc với tab", "Dùng nút cộng trên thanh tab để mở tab mới trong ngăn. Chọn tab để chuyển thư mục; nút đóng nằm trên tab đang chọn. Đóng tab Học sử dụng để trở lại công việc."),
        ("panes", "Đặt các thư mục cạnh nhau", "Dùng nút chia ngăn bên phải thanh tab để xem hai thư mục cùng lúc. Nhấp vào một ngăn để chọn ngăn nhận lệnh. Số ngăn có thể tạo phụ thuộc gói sử dụng."),
        ("metadata", "Sắp xếp bằng thông tin riêng", "Nhấp phải một mục để ghim trong thư mục, đặt biệt danh hoặc thêm thuộc tính. Với thư mục, bạn còn có thể đặt emoji. Biệt danh không đổi tên tệp trên đĩa."),
        ("spaces", "Tách công việc bằng Space", "Mở menu Space ở đầu thanh bên để tạo hoặc chuyển Space. Mỗi Space giữ danh sách mục ưa thích riêng. Dùng các chấm ở đáy thanh bên để chuyển nhanh giữa các Space."),
        ("preview", "Xem trước và dùng Shelf", "Chọn một tệp rồi nhấn ⇧⌘P để bật hoặc tắt ngăn xem trước. Dùng menu ngữ cảnh để thêm mục vào Shelf, nơi giữ các tệp bạn muốn dùng lại.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XFinderTokens.Space.section) {
                Label(L10n.t("Học sử dụng"), systemImage: "book.closed")
                    .font(XFinderTokens.Font.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.t("Sáu bài hướng dẫn ngắn. Tự đánh dấu khi bạn đã thực hành; tiến độ được lưu trên máy này."))
                    .font(XFinderTokens.Font.row)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(BrowserLearnProgress.count(in: progress)), total: 6)
                    .accessibilityLabel(L10n.t("Tiến độ học"))
                ForEach(lessons, id: \.id) { lesson in
                    VStack(alignment: .leading, spacing: XFinderTokens.Space.row) {
                        Text(L10n.t(lesson.title))
                            .font(XFinderTokens.Font.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text(L10n.t(lesson.body))
                            .font(XFinderTokens.Font.row)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle(L10n.t("Đã thực hành"), isOn: Binding(
                            get: { BrowserLearnProgress.completed(in: progress).contains(lesson.id) },
                            set: { complete in
                                // Read the latest shared value before merging a change from any window.
                                let latest = UserDefaults.standard.data(forKey: BrowserLearnProgress.key) ?? Data()
                                progress = BrowserLearnProgress.updating(latest, lesson: lesson.id, isComplete: complete)
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(L10n.t(lesson.title) + ": " + L10n.t("Đã thực hành"))
                    }
                    .padding(XFinderTokens.Space.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(XFinderTokens.Fill.surface, in: RoundedRectangle(cornerRadius: XFinderTokens.Radius.control))
                }
            }
            .padding(XFinderTokens.Space.section)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
