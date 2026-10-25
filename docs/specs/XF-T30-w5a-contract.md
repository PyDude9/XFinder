# XF-T30 W5a — contract (bộ máy tìm kiếm: chỉ mục tên, chỉ mục nội dung, khớp theo tầng, ghép nguồn, tìm đã lưu)

Spec tổng §2 hàng W5. Hành vi: `scratchpad/claude/t30/spec-search.md` (§1 phạm vi, §4 cú pháp, §5 chỉ mục + giới hạn, §7 tìm
đã lưu). Cơ chế đo từ binary FileOctopus: `docs/FILEOCTOPUS_MECHANISMS_2026-10-25.md` §4. W5a = **chỉ bộ máy** (file mới +
VisionChild); nối vào thanh tìm / tab Cài đặt Tìm kiếm / sidebar là W5b (sau W1–W4).

## 1. Nguyên tắc (đo được, không đoán)

- **Không chỉ mục nào khi người dùng chưa duyệt thư mục** (FileOctopus R29): mặc định không quét gì ⇒ chi phí nghỉ = 0.
- Chỉ mục chạy **khi có ít nhất một cửa sổ trình duyệt mở** (giữ `IdleCost.onlyWhileOpen` trung thực); đóng hết ⇒ dừng
  FSEvents, lưu con trỏ `last_event_id`; mở lại ⇒ `FSEventStreamCreate(sinceWhen: cursor)` bắt kịp thay vì quét lại
  (cơ chế FileOctopus đo được). Con trỏ quá cũ / `kFSEventStreamEventFlagHistoryDone` báo mất ⇒ quét lại gốc đó.
- Dữ liệu trên **đĩa** (SQLite WAL, `synchronous=NORMAL`), không mảng tên trong RAM: chuỗi con qua FTS5 `tokenize='trigram'`,
  tiền tố/chính xác qua chỉ mục B-tree trên `name_key` gập. Đo bộ nhớ trước/sau một lần quét 100 000 tệp (`footprint` của
  tiến trình test) — mục tiêu tăng ≤ 15 MB và trả về sau khi xong.
- Dựng lại = **generation mới** ghi song song, `active_generation` chỉ đổi khi xong (không bao giờ chỉ mục nửa vời).
- Liệt kê bằng `DirectoryReader` (getattrlistbulk, giữ `._*`); loại `~/Library`, `node_modules`, `.git`, `DerivedData`,
  `.build`, `build`, `Pods`, `.Trash` (FileOctopus 0.9.2 loại `~/Library` và thư mục build).
- Trích chữ / OCR **chỉ trong tiến trình con** `XFinder --vision <job>` (luật Vision giữ bộ nhớ; PDFKit cũng chạy ở con):
  job mới `text-pdf` (≤ 50 trang, tệp ≤ 64 MiB), `text-rich` (rtf/rtfd/doc/docx/odt/html qua `NSAttributedString`),
  `ocr-index` (ảnh ≤ 50 MiB, PDF quét ≤ 10 trang render rồi OCR `.accurate`); byte tệp qua stdin (không đường dẫn qua argv —
  luật 9 NFD), ra UTF-8, cắt 200 000 ký tự. Văn bản thường đọc ở cha, ≤ 2 MiB.
- FTS5 nội dung: `fts5(body, alt, tokenize='unicode61 remove_diacritics 2')` (alt = chữ OCR), `bm25`, `snippet(…, 24)`,
  `PRAGMA secure_delete=ON` + `'secure-delete'` (bỏ khỏi chỉ mục là xoá thật trên đĩa), `optimize` sau lô lớn.

## 2. Thuần (builder P5 — `NameMatcher.swift`, `SearchIndexRules.swift`, `SavedSearch.swift`, test)

- `NameMatcher` (stub có doc-comment): tầng `exact < prefix < wordPrefix < substring < fuzzy`; gập bằng
  `EntryRules.foldBytes` (cùng khoá với lọc); fuzzy = dãy con đúng thứ tự, điểm thưởng đầu từ + liền mạch, phạt khoảng
  cách; `rank(candidates:query:limit:fuzzyBudget:)` dừng tầng fuzzy khi hết ngân sách (số ứng viên thử), trả `tierEnded`.
- `SearchIndexRules`: loại trừ, giới hạn (§1), `contentKind(forExtension:)`, `rootStatus(…)`, `action(path:flags:)` cho cờ
  FSEvents (`MustScanSubDirs`/`UserDropped`/`KernelDropped` ⇒ quét lại cây con; `RootChanged` ⇒ gốc bị dời/thay; `ItemRemoved`
  ⇒ xoá; còn lại ⇒ cập nhật một đường dẫn), `validateNewRoot` (đã nằm trong gốc khác / nằm trong vùng loại / không phải thư
  mục), mô tả trạng thái → khoá L10n.
- `SavedSearch` + `SavedSearchStore` (tên duy nhất, đổi tên, xoá, bật/tắt sidebar, giải mã bỏ phần hỏng; lưu **câu tìm + phạm vi**,
  không lưu kết quả; ngày tương đối tính lại mỗi lần chạy).

## 3. Bộ máy (builder N5 — `FilenameIndex.swift`; C5 — `ContentIndex.swift` + `Core/Image/VisionChild.swift`; S5 — `SearchCoordinator.swift`)

- `FilenameIndex` (actor): bảng `search_roots`, `index_generation(state building|active, counts)`, `names(root, generation,
  path, name, name_key, parent, size, mtime, ctime, kind, inode)` + FTS5 trigram trên `name_key`, `event_cursors`; quét theo
  lô (giao dịch 5 000 hàng), ưu tiên tiện ích nền (`Task(priority: .utility)`), FSEvents mỗi gốc
  (`kFSEventStreamCreateFlagFileEvents|UseCFTypes|WatchRoot`, latency 1 s), `search(_:within:limit:)` theo tầng (chính xác +
  tiền tố bằng B-tree, chuỗi con bằng trigram, fuzzy trên tập nhỏ có ngân sách), trạng thái từng gốc, tạm dừng, dựng lại,
  xoá chỉ mục (dữ liệu suy ra; gốc vẫn được duyệt), `suspend()`/`resume()`. Đo và ghi vào báo cáo: quét 100 000 tệp
  (`scratchpad/claude/testdata/d100000`), cỡ DB, độ trễ truy vấn mỗi tầng, bộ nhớ.
- `ContentIndex` (actor): `documents(doc_id, root, path, inode, fingerprint=size+mtime, status, skip_reason, truncated,
  indexed_at)` + FTS5; chỉ gốc bật Contents / Text in Images; hàng đợi một-lần-một, ưu tiên nền, bỏ qua tệp quá giới hạn
  (ghi `skip_reason`), dữ liệu iCloud chưa tải **không bao giờ** bị ép tải (bỏ qua, `dataless`); `search(_:within:limit:)` trả
  đường dẫn + đoạn trích + hạng.
- `SearchCoordinator` (`@MainActor`): nhận `ParsedSearch` + phạm vi (`folder` / `mac` / `panes`), chạy song song ba nguồn —
  chỉ mục tên (gốc nằm trong phạm vi), Spotlight (`FileSearchEngine.runMdfind` + `SearchQuery.mdfindExpression`, dừng sớm), chỉ
  mục nội dung (khi có từ ngữ và gốc bật) — gộp theo đường dẫn (tầng tốt nhất thắng, nguồn ghi lại), áp chip (loại/ngày/cỡ/
  in:/tag:) lên kết quả chỉ mục, gửi cập nhật dần (`onUpdate`), huỷ được, "This Mac" khi chưa có gốc ⇒ hành vi cũ (Spotlight
  toàn máy) — FileOctopus lùi về thư mục hiện tại, XFinder giữ Spotlight vì đã có (ghi Q-T30-14).

## 4. Khoá

`fileBrowser.search.roots` (Data JSON `[IndexRoot]`, ONE reader/writer `BrowserSettings.indexRoots`),
`fileBrowser.search.defaultScope` (String `mac|folder|previous`, mặc định `mac`), `fileBrowser.savedSearches` (Data JSON).
Control: W4 (tab Tìm kiếm + Nâng cao).

## 5. Nghiệm thu W5a

Test thuần (tầng + fuzzy + ngân sách + chữ Việt không dấu khớp có dấu; loại trừ; cờ FSEvents; validateNewRoot; SavedSearch),
probe đo trong scratchpad của builder (quét/truy vấn/bộ nhớ/FTS5 có sẵn trên máy: `sqlite_compileoption_used('ENABLE_FTS5')`
= 1 đã đo), harness `mutation-check-search.sh` thêm mutant cho NameMatcher/Rules. Không có UI ở W5a.
