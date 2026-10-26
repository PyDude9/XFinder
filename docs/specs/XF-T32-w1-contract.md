# XF-T32 W1 — contract: lớp dữ liệu (thuộc tính, ghim, nickname, emoji, quan hệ, Space)

Spec tổng `docs/specs/XF-T32-tilde-direction.md` §2–§4, Q-T32-2/3/4/12. Cơ chế đo từ DB của Tilde
(`~/Library/Application Support/FileExplorer/FileExplorer-v2.sqlite3`, chỉ đọc schema + hình dạng JSON, không đọc dòng
dữ liệu): định nghĩa thuộc tính JSON `[{id, name, kind, selectOptions:[{id, title, colorIndex}]}]`, lựa chọn theo
`(item_path, property_id) → option_id`, thuộc tính hiện ở thư mục nào `(folder_path, property_id, sort_order)`,
`file_nicknames(item_path, nickname)`, `folder_metadata(folder_path, emoji)`, `folder_relations(path_a, path_b, bookmark)`,
`sidebar_state.spaces_json [{id, name, groups:[{id, name, kind, isCollapsed, folders:[{path, name, bookmark}]}]}]`.
**Chép mô hình, không chép code.** Mọi file dưới đây là **thuần** (chỉ Foundation; `MetadataStore` thêm SQLite3), symlink
vào gói test, có test. Không UI, không chuỗi hiển thị (model trả **khoá L10n** khi cần nhãn — W2/W3 mới `L10n.t`).

Luật như W0 (Swift 6 strict, không `@unchecked Sendable`, chỉ sửa file của mình, scratch riêng, branch
`xf-t32-w1-<key>`, không push). Stub biên dịch được của mọi file đã có trên `main`.

## A. Thuộc tính + Live Groups — builder `properties`

**File**: `XFinder/Core/Browser/PropertySchema.swift` · `XFinder/Core/Browser/PropertyRules.swift` · test
`PropertySchemaTests.swift`, `PropertyRulesTests.swift`.

```swift
enum PropertyColor: Int, Codable, CaseIterable, Sendable { case gray, red, orange, yellow, green, blue, purple
    var titleKey: String     // "Xám" "Đỏ" "Cam" "Vàng" "Lục" "Lam" "Tím" — khoá L10n (W3 thêm vào store)
}
struct PropertyOption: Codable, Equatable, Identifiable, Sendable { var id: UUID; var title: String; var color: PropertyColor }
enum PropertyKind: String, Codable, Sendable { case select }        // Tilde 1.0.2 chỉ có select
struct PropertyDefinition: Codable, Equatable, Identifiable, Sendable {
    var id: UUID; var name: String; var kind: PropertyKind; var options: [PropertyOption]
}
struct PropertyCatalog: Codable, Equatable, Sendable {          // mọi định nghĩa, dùng chung giữa các thư mục
    static let currentSchemaVersion: Int = 1
    var schemaVersion: Int; var definitions: [PropertyDefinition]
    init()
    mutating func add(name: String) -> PropertyDefinition          // tên rỗng ⇒ "Thuộc tính"; trùng ⇒ thêm " 2", " 3"
    mutating func rename(_ id: UUID, to name: String) -> Bool      // rỗng/không có ⇒ false
    mutating func delete(_ id: UUID)
    mutating func addOption(_ property: UUID, title: String, color: PropertyColor) -> PropertyOption?   // title rỗng ⇒ nil
    mutating func updateOption(_ property: UUID, option: PropertyOption) -> Bool
    mutating func removeOption(_ property: UUID, option: UUID)
    mutating func moveOption(_ property: UUID, from: Int, to: Int)                   // ngoài khoảng ⇒ kẹp
    func definition(_ id: UUID) -> PropertyDefinition?
    func encoded() -> Data
    static func decode(_ data: Data?) -> PropertyCatalog            // hỏng/thiếu ⇒ PropertyCatalog(); mục hỏng bỏ riêng, phần còn lại giữ
}

enum PropertyRules {
    /// Nhóm theo thuộc tính (Tilde "Group by Status"): một section mỗi lựa chọn theo THỨ TỰ lựa chọn, bỏ section rỗng,
    /// "Chưa đặt" (khoá L10n "Chưa đặt") cuối cùng. Thứ tự entry trong section giữ nguyên thứ tự vào.
    struct Section: Equatable, Sendable { let option: PropertyOption?; let entries: [DirectoryEntry] }
    static func sections(_ entries: [DirectoryEntry], property: PropertyDefinition, selections: [String: UUID]) -> [Section]
    /// Lựa chọn mồ côi (option đã xoá) coi như chưa đặt.
    static func option(for path: String, property: PropertyDefinition, selections: [String: UUID]) -> PropertyOption?
    /// Live Group: (property, option) ⇒ đường dẫn, sắp theo tên hiển thị (nickname nếu có) bằng `EntryRules` so sánh tự nhiên.
    struct LiveGroup: Equatable, Sendable { let property: PropertyDefinition; let option: PropertyOption; let paths: [String] }
    static func liveGroups(catalog: PropertyCatalog, selections: [UUID: [String: UUID]], nicknames: [String: String],
                           wanted: [LiveGroupRef]) -> [LiveGroup]
}
struct LiveGroupRef: Codable, Equatable, Hashable, Sendable { var propertyID: UUID; var optionID: UUID }
```

Ca hỏng: option bị xoá còn lựa chọn; hai option cùng tên; tên tiếng Việt NFD/NFC so bằng nhau khi kiểm trùng; 0 entry;
`wanted` trỏ property/option không còn ⇒ bỏ; 10 000 entry `sections` < 20 ms (test thời gian rộng).

## B. Ghim, nickname, emoji, quan hệ — builder `pins`

**File**: `XFinder/Core/Browser/FolderAnnotations.swift` · test `FolderAnnotationsTests.swift`.

```swift
/// Ghim trong một thư mục (Tilde "Pin in 'Projects'"): đường dẫn ghim xuất hiện trong khối "Đã ghim" đầu thư mục cha.
/// "This folder" = ghim chính thư mục đó vào khối của nó (path == folder).
enum PinRules {
    static let maxPinsPerFolder: Int = 50
    /// Tách listing thành (ghim theo thứ tự ghim, phần còn lại theo thứ tự vào). Ghim mà không còn trong listing ⇒ bỏ khỏi
    /// kết quả và trả về trong `stale` (người tích hợp dọn DB). Ghim "This folder" luôn đứng đầu nếu có.
    static func split(_ entries: [DirectoryEntry], folder: String, pins: [String]) -> (pinned: [DirectoryEntry], rest: [DirectoryEntry], stale: [String], pinsFolderItself: Bool)
    static func toggled(_ pins: [String], path: String) -> [String]          // thêm cuối / bỏ; vượt max ⇒ không thêm
    static func moved(_ pins: [String], from: Int, to: Int) -> [String]
}
enum NicknameRules {
    static let maxLength: Int = 60
    /// Cắt khoảng trắng hai đầu, gộp xuống dòng thành khoảng trắng, cắt ở maxLength theo Character; rỗng ⇒ nil (xoá nickname).
    static func normalized(_ raw: String) -> String?
    /// Chuỗi tìm kiếm của một mục cho ⌘K/lọc: tên + nickname, gập dấu (EntryRules.foldBytes).
    static func searchKey(name: String, nickname: String?) -> [UInt8]
}
enum EmojiRules {
    /// Một grapheme emoji (kể cả ZWJ, cờ, tông da); khác ⇒ nil.
    static func normalized(_ raw: String) -> String?
}
/// Đổi tên/chuyển một mục ⇒ mọi khoá đường dẫn có tiền tố `from` (chính nó hoặc con cháu) đổi sang `to`.
enum PathRewrite {
    static func rewritten(_ path: String, from: String, to: String) -> String?   // không liên quan ⇒ nil; "/a/bc" không khớp "/a/b"
}
struct FolderRelation: Codable, Equatable, Identifiable, Sendable { var id: UUID; var a: String; var b: String }
enum RelationRules {
    /// Quan hệ hai chiều, không tự trỏ, không trùng (a,b) ~ (b,a).
    static func adding(_ relations: [FolderRelation], a: String, b: String) -> [FolderRelation]
    static func related(to folder: String, in relations: [FolderRelation]) -> [String]
}
```

Ca hỏng: tên thư mục có tiền tố giống nhau (`/a/b` vs `/a/bc`); đường dẫn kết thúc `/`; ghim trùng; nickname toàn khoảng
trắng; emoji "👍🏽", "🇻🇳", "👨‍👩‍👧"; chữ thường không phải emoji ⇒ nil.

## C. Kho SQLite — builder `store`

**File**: `XFinder/Core/Browser/MetadataStore.swift` (actor, `import SQLite3`, destructor transient riêng tư như W0
`ListingDiskCache`) · test `MetadataStoreTests.swift` (DB tạm).

```swift
actor MetadataStore {
    static let shared: MetadataStore     // ~/Library/Application Support/XFinder/Browser/metadata.sqlite
    init(databaseURL: URL)
    // thuộc tính
    func catalog() -> PropertyCatalog
    func saveCatalog(_ catalog: PropertyCatalog)                // xoá property/option ⇒ xoá lựa chọn mồ côi trong cùng transaction
    func selections(property: UUID) -> [String: UUID]          // item_path → option
    func selections(in folder: String) -> [UUID: [String: UUID]]   // chỉ con trực tiếp của folder (parent_path = folder)
    func allSelections() -> [UUID: [String: UUID]]              // cho Live Groups
    func select(path: String, property: UUID, option: UUID?)   // nil = xoá
    func folderProperties(_ folder: String) -> [(property: UUID, showInView: Bool)]   // theo sort_order
    func setFolderProperties(_ folder: String, _ list: [(property: UUID, showInView: Bool)])
    // ghim / nickname / emoji / quan hệ
    func pins(in folder: String) -> [String]
    func setPins(_ pins: [String], in folder: String)
    func nickname(for path: String) -> String?
    func nicknames(in folder: String) -> [String: String]
    func allNicknames() -> [String: String]
    func setNickname(_ nickname: String?, for path: String)
    func emoji(for folder: String) -> String?
    func setEmoji(_ emoji: String?, for folder: String)
    func relations() -> [FolderRelation]
    func setRelations(_ relations: [FolderRelation])
    // đổi tên / chuyển / xoá trên đĩa
    func itemMoved(from: String, to: String)                   // PathRewrite trên MỌI bảng, một transaction
    func itemRemoved(_ path: String)                           // xoá dòng của nó + con cháu (đã vào Thùng rác)
    func changeToken() -> Int                                  // tăng sau mỗi ghi — UI dùng để biết cần đọc lại
}
```

Bảng (WAL, `user_version` = 1): `catalog(id=0, json)`, `selections(item_path, parent_path, property_id, option_id,
PK(item_path, property_id))` + index `(property_id)` + `(parent_path)`, `folder_properties(folder_path, property_id,
show_in_view, sort_order)`, `pins(folder_path, item_path, sort_order)`, `nicknames(item_path PK, parent_path, nickname)`,
`emoji(folder_path PK, emoji)`, `relations(id PK, a, b)`. Ca hỏng: DB hỏng ⇒ đổi tên file thành `.corrupt-<ts>` (không xoá) và
tạo mới; `itemMoved` cho thư mục có 1 000 con cháu < 50 ms; đường dẫn có `'`, `%`, `_` (LIKE escape — dùng so sánh tiền tố
bằng `substr`/khoảng, không LIKE); ghi đồng thời từ hai Task.

## D. Space — builder `spaces`

**File**: `XFinder/Core/Browser/SpaceModel.swift` · test `SpaceModelTests.swift`.

```swift
/// Một Space = một sidebar riêng (Tilde: tiêu đề sidebar đổi Space, chấm phân trang ở đáy) + các Live Group + các
/// workspace đã lưu của nó. Thư mục/ổ hệ thống (Locations) dùng chung mọi Space.
struct Space: Codable, Equatable, Identifiable, Sendable {
    var id: UUID; var name: String; var symbol: String?          // SF Symbol hoặc nil
    var sidebar: SidebarLayout                                    // favorites + nhóm tuỳ biến (đã có, schema 2)
    var liveGroups: [LiveGroupRef]
    var workspaceIDs: [UUID]                                      // trỏ vào WorkspaceStore đã có
}
struct SpaceStore: Codable, Equatable, Sendable {
    static let currentSchemaVersion: Int = 1
    var schemaVersion: Int; var spaces: [Space]; var activeID: UUID
    /// Lần đầu: một Space "Cá nhân" (khoá L10n "Cá nhân") bọc SidebarLayout hiện có — không mất gì của người dùng.
    static func migrated(from layout: SidebarLayout) -> SpaceStore
    var active: Space { get }
    mutating func add(name: String, cloningSidebarFrom: UUID?) -> Space     // tên rỗng ⇒ "Space"; trùng ⇒ " 2"
    mutating func rename(_ id: UUID, to name: String) -> Bool
    mutating func delete(_ id: UUID) -> Bool                     // không xoá Space cuối; xoá active ⇒ active = kế bên
    mutating func activate(_ id: UUID) -> Bool
    mutating func activateNext() ; mutating func activatePrevious()      // vòng
    mutating func move(from: Int, to: Int)
    mutating func updateActiveSidebar(_ transform: (inout SidebarLayout) -> Void)
    mutating func toggleLiveGroup(_ ref: LiveGroupRef)                    // trên Space active
    func encoded() -> Data
    static func decode(_ data: Data?, fallbackLayout: SidebarLayout) -> SpaceStore   // hỏng ⇒ migrated(fallback); activeID mồ côi ⇒ spaces[0]
}
```

Ca hỏng: decode JSON tương lai (trường lạ) giữ phần đọc được; 0 Space trong JSON ⇒ migrated; xoá Space đang active khi chỉ
còn 2; `move` ngoài khoảng.

## Nghiệm thu W1
Test thuần cho mọi API; ≥ 3 mutant mỗi file vào harness browser (người tích hợp); `MetadataStore` đo: 10 000 lựa chọn
`allSelections` < 30 ms, `itemMoved` 1 000 con cháu < 50 ms (in số trong báo cáo).
