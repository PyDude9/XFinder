# Ghi chú trong Dynamic Island

Hiện ghi chú đang dùng từ NoteStore.shared. Ưu tiên mục ghim, ẩn mục đã lưu trữ và tìm theo nội dung không phân biệt hoa thường hoặc dấu. Tạo ghi chú hoặc mở ghi chú đã chọn trong trình chỉnh sửa XFinder hiện có. Dùng cùng dữ liệu với Settings và Edge Notes.

Worker sở hữu file mới `XFinder/Views/NotchNotesPage.swift`, phần lọc thuần nếu cần và test tương ứng. Không thay closure onChange của NoteStore. Xuất danh sách chuỗi VI/EN. Người tích hợp sở hữu router và catalog. Kiểm dữ liệu trống, tìm không khớp, ghi chú vừa lưu trữ/xóa, thay đổi từ editor, văn bản dài và điều hướng bàn phím.
