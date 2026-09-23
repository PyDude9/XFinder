# Chuột & cử chỉ / Mouse & Gestures

> Có trong source hiện tại. **Không đồng nghĩa đã phát hành trên Releases.**
> Đây là bộ gửi phím tắt theo cử chỉ; không tự gọi API riêng của từng app.

## Bắt đầu

**Preset-first:** sau khi cấp quyền và bật công tắc, các app đã được hỗ trợ **có sẵn
mapping dùng được ngay**. Ghi nút / nhập bundle ID / ghi phím đều là tuỳ chỉnh
**không bắt buộc** — không phải bước onboarding.

1. Mở XFinder → sidebar **CỬA SỔ → Chuột & cử chỉ**.
2. Cấp **Trợ năng / Accessibility** cho đúng bản XFinder đang chạy.
3. Bật **Bật cử chỉ chuột**. Mặc định tính năng **tắt**, tilt **tắt**, debug **tắt**.
4. **Đọc mục "Kiểm tra nhanh" ở đầu trang.** Đây là bước trả lời hai câu hỏi duy nhất
   khiến cử chỉ không chạy — xem hai mục ngay bên dưới.
5. Giữ nút giữ của bạn, kéo lên/xuống/trái/phải, rồi thả: gửi đúng một hành động theo
   app đang ở trước.
6. Xong. Bảng bên dưới đã đúng — không cần cấu hình gì thêm.

### "Tôi làm đúng mà không có gì xảy ra" — đúng hai nguyên nhân
Cả hai đều **vô hình** trong bảng mapping, nên trang in chúng ra bằng số đo thật.

**1. Nút giữ sai — và mặc định cũ là nút không giữ được.**

Build cũ lấy `mouseButton(2)` (bấm con lăn) làm nút giữ mặc định. Giữ con lăn rồi kéo là
thao tác tay **không làm được**, nên tính năng đọc như đã chết. Config đã lưu của bạn có
thể vẫn mang giá trị đó, và **không có migration nào tự sửa**: `2` là giá trị *hợp lệ*, nên
sửa ngầm sẽ ghi đè lựa chọn có chủ ý của người thật sự muốn nó.

Trang giờ in **cảnh báo cam** đúng cho giá trị đó, kèm nút **Ghi lại nút giữ**. Bấm nút đó,
rồi **bấm nút hông bạn muốn giữ** — số hiện ra ngay khi bạn bấm.

**2. XFinder đang là ứng dụng phía trước.**

Engine tra bảng theo **bundle ID của app đang frontmost**. Khi bạn *đang thử* từ chính trang
này, XFinder frontmost — nên nhật ký hiện `com.xfinder.app` một cách **hợp lệ**, và cử chỉ
trông như hỏng trong khi nó chạy đúng cấu hình. Hãy chuyển sang Zed / Chrome / Excel… rồi
thử lại. Trang in rõ app sẽ nhận cử chỉ ở dòng **"Cử chỉ sẽ gửi tới"**.

Nếu vừa bấm một nút khác nút giữ hiện tại, trang hiện luôn gợi ý **"Đặt nút này làm nút
giữ?"** — một lần bấm để nhận. Gợi ý này **chỉ** hiện sau một lần bấm thật, không hiện trên
bản cài mới.

### Nút nào, động tác nào (phần người dùng hay hỏi nhất)

Mã CoreGraphics đếm `0 = trái, 1 = phải, 2 = giữa`, còn số **in trên vỏ chuột**
đếm từ 1. UI hiển thị **theo số người dùng đếm** — tức `mouseButton(n)` hiển thị
`Nút (n+1)` — và giữ mã thô trong ngoặc ở ba nút ai cũng có:

| Mã CoreGraphics | UI hiển thị | Ghi chú |
|---|---|---|
| `Button 0` | **Nút 1** (chuột trái) | Bị chặn — chiếm thao tác kéo/chọn |
| `Button 1` | **Nút 2** (chuột phải) | Dùng được nếu bạn muốn |
| `Button 2` | **Nút 3** (bấm con lăn xuống) | **Không dùng làm nút giữ** — xem mục "Kiểm tra nhanh" |
| `Button 3` | **Nút 4** | |
| `Button 4` | **Nút 5** | |
| từ `Button 5` | **Nút *n+1*** | Chuột nhiều nút |

> **Vì sao không đặt tên vật lý?** Bản trước gọi `Button 3` là “nút hông sau” và
> `Button 4` là “nút hông trước”. Sai theo hai cách: cùng một số là **nút khác nhau**
> trên Razer Basilisk và trên Magic Mouse, và không có API nào cho biết chuột bạn
> đang cắm có nút nào — macOS chỉ báo `mouseEventButtonNumber`, không có trường
> vendor/product nào trong `CGEventField`. Đặt tên vật lý là **khẳng định một layout
> chưa từng đo**. Số thì luôn đúng.

**Mỗi mũi tên trên sơ đồ in số nút ngay trên đầu mũi tên** (`Nút 3 ↑`), và
**tiêu đề trong bảng chi tiết cũng ghi số** (`Nút 3: kéo lên`). Đây là câu trả lời
cho câu hỏi nguyên văn *“tôi ko hiểu dùng nút nào của chuột với mũi tên”* — một
mũi tên trần không cho biết đang giữ nút nào.

### Giao diện kiểu Mac Mouse Fix / MOS (2026-09-21)

Trang này **không còn là một bảng sáu dòng chữ**. Bảng cũ là nguyên nhân thật của lỗi
"trang rỗng": mỗi dòng nhét hành động, câu động tác, nhãn nguồn và **hai nút** vào một
`HStack`, tất cả `.lineLimit(1)`. Với Global, `⌃↑` (ba ký tự) phải tranh chỗ với một câu
tiếng Việt đầy đủ trong khung ~240 pt — cả hai đều bị cắt tới mức không nhìn thấy.
**Dữ liệu chưa bao giờ rỗng; bố cục mới là thứ rỗng.**

Bố cục mới:

```
┌─ Sơ đồ cử chỉ ──────────────────────────┐
│ [icon] Safari            [▾ chọn app]    │
│ Ứng dụng đang dùng: com.apple.Safari     │
│                                          │
│        ↑              │ ← Bấm vào một    │
│    ←  (🖱)  →         │   mũi tên để     │
│        ↓              │   xem chi tiết   │
│   ↺    ⇅    ↻         │                  │
│  [Nút 3 — bấm con lăn / Đổi nút]         │
└──────────────────────────────────────────┘
```

* **Sơ đồ chuột là bộ chọn.** Mỗi mũi tên là một `Button`; bấm vào là chọn hướng đó,
bấm lại là bỏ chọn (toggle, không phải radio). Không còn danh sách rời phải dò bằng mắt.
* **Bảng chi tiết bên phải** trả lời "mũi tên này gửi gì": Động tác → XFinder gửi →
nguồn gốc → hai nút phụ. Phím được in trong ô riêng nên đọc được ở mọi bề rộng.
* **Màu = nguồn gốc:** xanh lá = phím có sẵn, xanh dương = bạn tự đặt, viền đứt =
chưa gán. Cùng màu đó dùng cho cả mũi tên, viền bảng và nhãn nguồn.
* **Bấm lại mũi tên đang mở để đóng** — không cần nút X.
* **Đổi app là xoá mũi tên đang chọn** (`MouseDiagramSelection.afterProfileChange()`),
để bảng không hiển thị mapping của app trước đó.

Ba bước trên trang:

1. **Giữ** nút đã chọn (mặc định: **Nút 3**, bấm con lăn xuống — giữ nguyên, đừng nhả).
   Số nút được in ngay trên mỗi mũi tên của sơ đồ.
2. Vẫn giữ, **kéo** theo một hướng. Phải vượt ngưỡng (~12 đơn vị delta) mới tính là cử chỉ;
   ngắn hơn thì XFinder phát lại click bình thường.
3. **Thả** — XFinder gửi phím tắt của app đang ở trước.

Ví dụ: trong Safari, giữ **Nút 3** → kéo **SANG PHẢI** → thả ⇒ gửi `⌃Tab` (tab kế tiếp).

> **Tilt** chỉ dành cho chuột có con lăn **nghiêng được** trái/phải **và** driver gửi
> cuộn ngang dạng rời rạc. Mặc định công tắc này **tắt**, và hai mũi tên tilt **không
> được vẽ** cho tới khi bạn bật. Đo trên chính máy này: Razer Basilisk và Apple Magic
> Mouse đều báo **cuộn liên tục**, nên hai hướng đó không bao giờ chạy — vẽ ra sẽ là
> một control không làm được điều nhãn nó hứa. XFinder **không thể tự dò** phần cứng
> của bạn (macOS chỉ báo `mouseEventButtonNumber`, không có trường vendor/product),
> nên quyết định này thuộc về bạn.

**Banner trạng thái là số đo, không phải suy đoán.** Trang đọc `tapActive` — trạng thái
thật của Event Tap — chứ không suy ra từ chuỗi trạng thái:

| Banner | Ý nghĩa |
|---|---|
| *Sẵn sàng — …* | `tapActive == true`; mapping đã chạy được |
| *Chưa mở được Event Tap: chưa có quyền Trợ năng* | `tapCreate` trả nil và tiến trình chưa được tin |
| *Chưa mở được Event Tap: tapCreate trả nil dù đã có quyền Trợ năng* | Đã tin nhưng vẫn không mở được — nêu rõ để không đoán sai nguyên nhân |
| *Cử chỉ đang tắt…* | Công tắc đang tắt; không bao giờ hiện “Sẵn sàng” giả (test `testReadinessBadgeNeverClaimsReadyWithoutAnArmedTap` giữ tính chất này) |

**Cấp quyền xong không cần khởi động lại.** `GestureController` nghe
`NSApplication.didBecomeActiveNotification` và đọc lại `WindowManager.isTrusted`, nên
quay về XFinder sau khi cấp quyền là tap được arm ngay. Không cần bật/tắt công tắc.

**Không cần mở trang này mỗi lần khởi động.** `AppDelegate` gọi
`GestureController.shared.start()` trong `applicationDidFinishLaunching`, nên công tắc đã
bật thì Event Tap được arm ngay lúc mở app — trước đây tính năng chỉ sống khi trang còn
trên màn hình.

### Quyền Trợ năng bị reset mỗi lần build — và cách chặn hẳn

TCC gắn quyền vào **danh tính mã**, không phải đường dẫn. Bản ký **ad-hoc** có danh tính
là **cdhash**, mà cdhash **đổi mỗi lần build** — nên mỗi bản mới là một app khác với macOS
và quyền cũ không áp dụng. Đây là lý do hay gặp nhất của "đã cấp quyền mà vẫn báo chưa có".

Cách đo được (đã chạy trên máy này):

```sh
codesign -d -r- /Applications/XFinder.app    # xem Designated Requirement
```

| Ký bằng | Designated Requirement | Quyền sống qua rebuild? |
|---|---|---|
| ad-hoc (`--sign -`) | `cdhash H"a6cae0e2…"` | **Không** — mỗi build một danh tính mới |
| chứng chỉ ("XFinder Dev") | `identifier "com.xfinder.app" and certificate leaf = H"989e240c…"` | **Có** — danh tính ổn định |

Tạo chứng chỉ tự ký **không cần GUI** (khác với ghi chú cũ trong `dev-install.sh`):

```sh
mkdir -p /tmp/xf-cert && cd /tmp/xf-cert
cat > cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = XFinder Dev
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf
# macOS từ chối PKCS#12 mặc định của OpenSSL -> phải dùng thuật toán cũ (-legacy).
openssl pkcs12 -export -out xf.p12 -inkey key.pem -in cert.pem \
  -passout pass:xfdev -name "XFinder Dev" \
  -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import xf.p12 -k ~/Library/Keychains/login.keychain-db -P xfdev -T /usr/bin/codesign -A
security add-trusted-cert -d -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
security find-identity -v -p codesigning     # phải thấy: 1 valid identities found
```

Sau đó ký theo thứ tự **appex trước, app sau** (ký app trước sẽ làm hỏng chữ ký con).

**Đừng ký appex bằng `codesign --force` trần, và đừng ký app ngoài bằng `--deep`** —
cả hai đều là bẫy đã gặp thật, và hậu quả không nhìn thấy được:

```sh
# ĐÚNG: appex ký kèm entitlements của chính nó
cat > /tmp/appex.entitlements <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
  <key>com.apple.security.get-task-allow</key><true/>
</dict></plist>
PLIST
codesign --force --sign "XFinder Dev" --identifier com.xfinder.app.XFinderSync \
  --entitlements /tmp/appex.entitlements \
  XFinder.app/Contents/PlugIns/XFinderSync.appex

# ĐÚNG: app ngoài KHÔNG dùng --deep
codesign --force --sign "XFinder Dev" --identifier com.xfinder.app XFinder.app
```

| Bẫy | Hậu quả | Phát hiện bằng |
|---|---|---|
| `codesign --force` trên appex **không kèm entitlements** | Xoá luôn `com.apple.security.app-sandbox` mà target build ra. `pkd` **từ chối** plug-in ⇒ `pluginkit` không liệt kê, Finder không có menu. Không có thông báo lỗi nào | `pluginkit -m -p com.apple.FinderSync -v` không thấy dòng XFinder, trong khi app khác vẫn có |
| `codesign --deep` trên app **ngoài** | Ký lại appex con bằng **identifier của app ngoài** ⇒ `com.xfinder.app.XFinderSync` bị gộp thành `com.xfinder.app`. Hai bundle trùng identifier ⇒ LaunchServices/pluginkit không phân giải được | `codesign -dv --verbose=2 <appex>/Contents/MacOS/XFinderSync` in ra `Identifier=com.xfinder.app` |
| `codesign --verify --deep --strict` khi kiểm tra | Chỉ kiểm bundle ngoài, **che** đúng cái lỗi trên | Phải verify từng appex theo tên (`codesign --verify --strict <appex>`) |

Ngoài ra, extension target phải khai `MACOSX_DEPLOYMENT_TARGET` **bằng** app chính
(14.0). Để 27.0 thì `GENERATE_INFOPLIST_FILE` ghi `LSMinimumSystemVersion = 27.0`
vào Info.plist của appex, và macOS **từ chối đăng ký** extension có minimum OS cao
hơn container của nó. `ENABLE_DEBUG_DYLIB = NO` cũng bắt buộc: mặc định Debug của
Xcode 16+ sinh stub + `.debug.dylib` + `__preview.dylib` thay vì một binary
extension thật.

**Cài vào `/Applications` để đường dẫn không đổi** — cùng danh tính *và* cùng path thì
mục trong System Settings không bị nhân đôi.

Một nguồn nhiễu riêng: **mọi thư mục build trung gian đều tự đăng ký cùng một
plugin identifier** (thư mục staging, `/tmp`, DerivedData, bản copy trên Desktop).
Đã đo được **16 đường dẫn chết** cùng khai `com.xfinder.app.XFinderSync`; khi đó
`pluginkit` không phân giải được gì cả. `scripts/install-mouse-rebuild.sh` gỡ đăng
ký các bản build/staging rồi `pluginkit -a` đúng bundle trong `/Applications`.

Sau khi cài, **người dùng vẫn phải tự bật extension** trong System Settings ▸
Login Items & Extensions ▸ Finder — không app nào làm hộ được. Script in ra trạng
thái đo được (`!` = đã đăng ký nhưng chưa bật, `+` = đang bật) thay vì ngụ ý là
đã chạy.

Hai cái bẫy khi ký lại mà build đang nằm trên Desktop (đã gặp thật):

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `resource fork, Finder information, or similar detritus not allowed` | Finder gắn xattr lên bundle, codesign từ chối ký | `xattr -cr XFinder.app`, hoặc copy bằng `ditto --norsrc --noextattr --noacl` |
| `spctl -a` trả `rejected` | Gatekeeper chỉ tin chứng chỉ Apple cấp | **Bình thường** với chứng chỉ tự ký; không cản việc mở app |

`spctl rejected` **không** phải lỗi cần sửa. Dấu hiệu đúng là
`codesign --verify --deep --strict` báo `satisfies its Designated Requirement`.

**Tuỳ chỉnh (không bắt buộc)**

- **Ghi phím** trên một dòng: chọn app, chọn hướng, nhấn tổ hợp mong muốn.
  **Esc**, **Hủy ghi**, rời trang hoặc hết 10 giây sẽ hủy ghi.
- **Ghi nút / modifier**: đổi trigger. **Nút 1** (chuột trái) được giữ riêng, không cho gán.
- **Khôi phục mapping mặc định của ứng dụng**: xoá override của app đang chọn.
- **Nâng cao — ứng dụng khác**: nhập bundle ID cho app không có trong danh sách.

**Đổi chuột:** binding không gắn vào hãng/serial. Nếu chuột mới phát cùng mã nút thì
binding dùng tiếp; nếu khác, ghi lại. Magic Mouse không được giả định có nút 3:
có thể chọn modifier + di chuyển chuột. Không nhận diện riêng từng thiết bị bằng HID.

## Phân biệt click và gesture

- Deadzone mặc định **12 đơn vị delta CoreGraphics**, chỉnh bằng slider. Không phải
  12 point màn hình, không phải khoảng cách vật lý; DPI/driver có thể đổi cảm giác.
- Tổng quãng đường **nhỏ hơn** ngưỡng: phát lại cặp down/up tại vị trí click ban đầu,
  giữ button, modifiers và click count. Click vì thế xảy ra **khi thả nút**, không
  ngay lúc nhấn. Không dùng nút này cho native hold/drag/orbit trong app 3D.
- Đi đủ xa rồi quay về gần điểm bắt đầu: **không click**, không gửi phím.
- Chọn hướng theo tổng delta cuối; đường chéo bằng nhau ưu tiên trục dọc.
- Modifier vẫn được chuyển cho hệ thống để không làm hỏng các shortcut thông thường.
  Gõ phím hoặc nhấn nút khác trong khi giữ sẽ hủy stroke; không giả lập “click modifier”.
- Đổi app, sleep/chuyển phiên, đổi cấu hình hoặc Event Tap bị tắt sẽ hủy stroke.
  Không phát click bù vào app vừa được chuyển tới.
- Hold quá 15 giây sẽ hủy; có drain tạm thời cho release đã bị chặn. Khi tắt trong
  lúc đang giữ, tap có thể còn tối đa 15 giây để thu hồi release, sau đó được gỡ.

## Mapping mặc định — đây chính xác là phím XFinder gửi

**Bảng này là toàn bộ preset dựng sẵn.** Mỗi dòng ghi **ý định** ("Lùi", "Tab kế
 tiếp") và **phím chính xác** sẽ được gửi. Hai thứ đó tách rời vì cùng một ý định là
phím khác nhau ở mỗi app — và vì một phím tắt trần (`⌘⇧]`) không cho người dùng biết
nó làm gì.

Ký hiệu: **⬤** = quy ước chung của macOS (mọi app có khái niệm đó đều hiểu);
**▪** = phím tắt riêng của app đó, kiểm chứng được trong chính app;
**—** = cố ý để trống. **⌨︎** = hành động **hệ thống**: XFinder đọc phím tắt **bạn đã gán**
trong Hệ thống → Bàn phím → Phím tắt và gửi **đúng phím đó**; máy chưa gán thì **không gửi gì**
(trang nói rõ). Đây **không** phải `NSEvent.systemDefined` — cơ chế đó đã bị gỡ (Round 8).

| Profile | Giữ + ↑ | Giữ + ↓ | Giữ + ← | Giữ + → | Nghiêng ← / → (opt-in) |
|---|---|---|---|---|---|
| Global (app không khớp profile nào) | ⌨︎ Mission Control | ⌨︎ App Exposé | ⌨︎ Space trước | ⌨︎ Space kế tiếp | — không gửi phím (chuyển tiếp cuộn ngang) |
| Edge, Safari, Chrome | ⬤ `⌘T` — Tab mới | ⬤ `⌘W` — Đóng tab | ⬤ `⌘[` — Lùi | ⬤ `⌘]` — Tiến | ⬤ `⌃⇥` — Tab kế tiếp |
| VS Code, Cursor, Zed, Antigravity, Claude | — | — | ⬤ `⌘[` — Lùi | ⬤ `⌘]` — Tiến | — |
| Kitty, Terminal, iTerm2 | — | — | ⬤ `⌥←` — Lùi một từ | ⬤ `⌥→` — Tới một từ | — |
| Photoshop, CapCut | ▪ `⌘0` — Vừa khung | ▪ `⌘Z` — Hoàn tác | ▪ `[` — Thu nhỏ cọ | ▪ `]` — Phóng to cọ | — |
| **Excel** | ▪ `⌘+` — Phóng to | ▪ `⌘-` — Thu nhỏ | ⬤ `⌃⇧⇥` — Trang tính trước | ⬤ `⌃⇥` — Trang tính kế tiếp | — |
| **Word** | ▪ `⌘+` — Phóng to | ▪ `⌘-` — Thu nhỏ | — | — | — |
| Discord, Zalo, AyuGram | — | — | ⬤ `⌥↑` — Mục trước | ⬤ `⌥↓` — Mục kế tiếp | — |
| Obsidian, Notion | ▪ `⌘P` — Mục kế tiếp | — | ⬤ `⌘⌥←` — Lùi | ⬤ `⌘⌥→` — Tiến | — |

> **Word và Excel là HAI bảng riêng, không phải một bảng dùng chung.** Bản trước gộp
> cả hai vào một profile rỗng. Word **không có worksheet**, nên `⌃⇧⇥` không có nghĩa
> gì trong Word; Excel thì có tài liệu riêng cho cặp đó. Test
> `testWordAndExcelDoNotShareOneTable` giữ hai dictionary tách rời.
>
> **Global đã đổi lần thứ TƯ (2026-09-23), và lần này là để sửa một cơ chế không tồn tại.**
>
> * Bảng 3 (2026-09-22) gửi `⌃↑`/`⌃↓` cho Mission Control, `⌃←`/`⌃→` cho Spaces — người dùng
>   báo gesture **được nhận nhưng không làm gì**. Đo ra là **đúng**: máy này
>   `com.apple.symbolichotkeys` ids 79–82 bật mà **không gán phím nào**, và plist factory
>   của macOS 27 **không có** binding mũi tên nào cho chúng.
> * Bảng 3b thay up/down bằng **keytype hệ thống số 32** (`NSEvent.systemDefined`, tiền thân
>   của ký hiệu `⚙︎`). Cũng sai: **`NX_KEYTYPE_MISSION_CONTROL` không tồn tại** —
>   `ev_keymap.h` chỉ định nghĩa tới `NX_KEYTYPE_MENU = 25`. Post một sự kiện không định nghĩa
>   ⇒ không ai nghe.
> * Bảng 4 (hiện tại) không ship **phím** nào cho bốn hành động này, mà ship **ý định**.
>   `SpaceBinding` đọc `com.apple.symbolichotkeys` **của chính máy bạn** (ids 32/33/79–82,
>   kèm fallback 80/82) và post **đúng chord máy đó khai** — đo trên máy này:
>   `⌃↑`, `⌃↓`, `⌃←`, `⌃→`, mask `0x840000` = `control | maskSecondaryFn`.
>
> **Bit `fn` là bắt buộc.** Apple mã hoá các arrow này kèm `maskSecondaryFn`; mask bỏ bit đó
> là post một chord hệ thống không khớp. `GestureShortcut.label` **bỏ** bit fn khi *hiển thị*
> (nên hàng đọc `⌃↑`, giống System Settings) nhưng **post nguyên mask** — hiển thị và dispatch
> là hai việc, và chỉ phần dispatch mới cần đúng bit.
>
> **Một resolver, hai người dùng.** `GestureMap.row(...)` trả `systemShortcut` +
> `isUnboundSystemAction`; UI hiển thị đúng giá trị đó và engine post đúng giá trị đó. Máy
> **chưa gán** phím cho hành động nào thì hàng ghi **“chưa gán trong macOS”** và cử chỉ
> **không gửi gì** — không có nhánh nào bịa ra một phím dự phòng.
>
> **Chưa kiểm chứng được:** macOS có **thực sự** mở Mission Control / đổi Space khi post chord
> đó hay không. Bằng chứng hiện có: engine post đúng chord máy khai, tap đang mở, AX tree
> hiển thị đúng phím. Việc cuối cần mắt người — xem `docs/GESTURE_VERIFICATION.md`, Round 8.
>
> Test `testShownEqualsSentForEveryBundleAndDirection` giữ UI và engine dùng **cùng** resolver;
> `testNoPresetShipsASpaceConstant` chặn hằng số `⌃←`/`⌃→` quay lại preset.

\* Global gửi **hành động hệ thống** cho cả bốn hướng, nhưng bằng **phím tắt do máy bạn khai**
(§ `⌨︎`), không bằng sự kiện `NSEvent.systemDefined`. `⌘[` / `⌘]` là quy ước lịch sử của macOS
và được hầu hết app tôn trọng; app nào không có lịch sử thì phím đó vô hại.

**Hai nhánh nghiêng của Global:** preset để **trống**, và điều đó là chủ ý — engine
nhánh tilt coi `.unassigned` là "để sự kiện cuộn ngang đi thẳng", nên thao tác nghiêng
vẫn là cuộn ngang bình thường. Không có phím nào được gửi và không có gì bị giả vờ.

### Những mục chủ động KHÔNG gán tự động

Đây là danh sách **đầy đủ** các ô cố ý để trống, kèm lý do. Không ô nào bị bỏ trống vì
"chưa làm" — mỗi ô là một hành động **không có phím chung đáng tin** giữa các app trong
nhóm đó.

- **Dev/AI ↑/↓**: "toggle terminal" là ``⌃` `` trong VS Code, `⌃\`` trong Cursor, và
  khác nữa trong Zed; "AI refactor" là `⌘I` trong Cursor và `⌘K` trong Claude. Gửi một
  trong hai như preset chung là **đoán** mà trông như đã kiểm chứng. Ghi phím riêng cho
  từng app nếu bạn muốn.
- **Chat ↑/↓**: "unread", "đầu trang" và "cuối trang" là ba hành động khác nhau, không
  app nào dùng chung một phím.
- **Word ←/→**: Word **không có worksheet**. Không mượn phím Excel cho Word.
- **Notes ↓**: "thêm block" (Notion `/`) và "thêm trang" (`⌘N`) là hai hành động khác
  nhau, hậu quả khác nhau.
- **Terminal ↑/↓**: không có phím chung cho "cuộn một dòng" trên cả Kitty, Terminal và
  iTerm2 — và `⌘W` trong Terminal có thể **giết tiến trình đang chạy**. Sai một phím
  trong terminal là mất việc, nên ở đây Chưa gán mới là câu trả lời trung thực.
- **Design tilt**: không gọi cuộn ngang thông thường là "smooth timeline scrubbing".

Những ô này có **Ghi phím** riêng theo app. “Chưa gán” trên profile đã khớp **không
rơi về Global**; nó không gửi phím.

### Năm hành động hệ thống

`Mission Control`, `App Exposé`, `Hiện màn hình nền`, `Space trước` và `Space kế tiếp` đều nằm
trong **danh sách chọn hành động**. **Bốn hành động đầu-cuối được Global dùng làm preset** —
chúng chính là lý do bảng Global tồn tại. Chúng hoạt động bằng cách đọc binding **của chính
bạn**, nên không có chuyện “gửi một phím bạn chưa gán”:

- Máy bạn **đã** đặt phím tắt cho Mission Control (mặc định: `⌃↑`) → XFinder gửi đúng phím đó.
- Máy bạn **chưa** đặt → hàng trên trang ghi **“chưa gán trong macOS”**, tô cam, và cử chỉ
  **không gửi gì** — kèm nút mở thẳng Hệ thống → Bàn phím → Phím tắt để bạn gán.

Không nằm trong preset nào:

- **`Hiện màn hình nền`**: là `F11` trên bàn phím Apple đầy đủ — máy không có F11 thì phím đó
  vô nghĩa, nên XFinder không áp nó lên mọi máy.
- **`Chụp màn hình`**: `⌘⇧3` đã là phím hệ thống, và gán nó vào một cử chỉ đặt **ảnh chụp** khắp
  nơi chỉ vì một cái vuốt tay là hậu quả không ai xin.

Chọn chúng trong menu là hành động **chủ ý** của bạn, không phải preset áp lên.

### Nguồn của từng dòng

Mỗi dòng hiện một nhãn cho biết giá trị đến từ đâu — đây là thứ phân biệt
“preset cố ý để trống” với “preset bị thiếu”. Từ 2026-09-21 nhãn này là một **viên màu**
trong `GestureDetailPanel`, và cùng màu đó tễ viền bảng lẫn mũi tên trên sơ đồ:

| Nhãn | Màu | Nghĩa |
|---|---|---|
| **Mặc định** | xanh lá | Preset dựng sẵn của app đó |
| **Toàn cục** | xanh lá | App không có profile riêng → dùng bảng Global |
| **Tự đặt** | xanh dương | Bạn đã ghi phím / đổi / đặt Chưa gán cho hướng này |
| **Chưa gán** | xám, viền đứt | Preset cố ý không gán (hành động mơ hồ, không có phím chung đáng tin) |

Viên màu còn kèm **một câu giải thích** ngay dưới, vì "Mặc định" và "Toàn cục" khác
nhau về ý nghĩa: một bên là "app này được thiết kế riêng", bên kia là "không có gì riêng
nên đây là bảng dự phòng".

Cách giải (một resolver duy nhất, dùng chung cho cả UI và lúc chạy):

1. override riêng của đúng bundle ID đó
2. override dùng chung cho họ profile (khoá cũ, giữ để nâng cấp)
3. preset dựng sẵn của bundle ID, hoặc Global nếu app không có profile
4. `.unassigned`

**Override `.unassigned` không bao giờ rơi xuống bước sau.** Đặt Chưa gán cho một
hướng của Safari sẽ giữ đúng Chưa gán, không quay về ⌘T.

### Bundle IDs được nhận diện

| Nhóm | Bundle IDs |
|---|---|
| Browser | `com.microsoft.edgemac`, `com.apple.Safari`, `com.google.Chrome` |
| Dev/AI | `com.visualstudio.code`, `com.cursor.ide`, `dev.zed.Zed`, `com.antigravity.ide`, `com.anthropic.claude` |
| Design | `com.adobe.Photoshop`, `com.lemon.CapCutMac` |
| Chat | `com.hnc.Discord`, `com.vng.zalo`, `org.telegram.ayugram` |
| Office | `com.microsoft.Excel`, `com.microsoft.Word` |
| Terminal | `net.kovidgoyal.kitty`, `com.apple.Terminal`, `com.googlecode.iterm2` |
| Notes | `co.elastic.obsidian`, `com.notion.Notion-App` |

Đây là các ID cấu hình theo yêu cầu, không phải kết quả kiểm kê app đã cài.
Nếu bản app của bạn dùng ID khác (beta, fork…), chọn **Dùng ứng dụng vừa hoạt động**
hoặc nhập bundle ID trong trang cấu hình. Profile tùy chỉnh kế thừa Global cho
những hướng chưa override; đặt **Chưa gán** để vô hiệu hóa riêng một hướng.
Nút **Khôi phục toàn bộ ứng dụng này về mặc định** xóa override của profile đang chọn,
không reset trigger, deadzone hay app khác.

### Đổi nút giữ (nút nào của chuột?)

Đây là câu hỏi đầu tiên của mọi người dùng, và XFinder trả lời bằng **số đo trên máy
bạn**, không bằng lời khuyên:

1. Mở trang → mục **XFinder đã nhận gì**. Bấm **Bật ghi nhật ký**.
2. Bấm thử nút bạn định dùng. Trang hiện **“Nút bạn vừa bấm: 4”** — đó là con số
   XFinder nhận được từ chuột bạn, không phải suy đoán.
3. Bấm **Ghi nút** trong mục **Nút giữ và cuộn**, rồi bấm đúng nút đó. Hoặc bấm vào
   **bảng số trên thân chuột** trong sơ đồ (nút đó cũng ghi lại).
4. Nhấn **Esc** để huỷ, hoặc chờ 10 giây tự dừng.

**Nút 1** (`Button 0`, chuột trái) **bị từ chối** — nó chiếm thao tác kéo/chọn thông
thường. Modifier (⌃ ⌥ ⇧ ⌘) cũng nhận được, miễn là **giữ đúng một cái**.

> **Vì sao không nói thẳng “nút hông trên”?** Vì không API nào trả lời được câu đó.
> `CGEventField` chỉ có năm trường chuột và trường cao nhất là `3`
> (`mouseEventButtonNumber`) — **không có trường vendor/product/device nào**, nên không
> code path nào biết con số nào ứng với nút vật lý nào. Số thì luôn đúng. Trang có
> **Ghi nút** để bạn tự xác nhận, và mục *XFinder đã nhận gì* để bạn **đọc được số của
> chính mình** thay vì phải tin.

Trigger dùng chung cho mọi thiết bị theo **mã nút của event**, không theo HID identity
của từng con chuột; đổi sang con khác có số nút khác thì ghi lại.

### Giữ nút cuộn rồi kéo để cuộn (tuỳ chọn, mặc định tắt)

Mục **Nút giữ và cuộn** có thêm một công tắc riêng: giữ **nút cuộn** rồi kéo là cuộn,
không cần nhấc tay khỏi chuột. Dành cho app phải cuộn nhiều như Photoshop hay CapCut.

- Nút đó **vẫn bấm bình thường** khi bạn không kéo. Chỉ khi kéo quá ngưỡng thì `↕`/`↔`
  được chuyển thành sự kiện wheel có tiết chế (~60 Hz) — chuột 8 kHz không bắn hàng nghìn
  sự kiện/giây.
- **Mặc định tắt**, và đây không phải sự nhút nhát: nút hông thường đã được driver gán
  sẵn (back/forward), nên chiếm nó là đánh nhau với driver. Đó là lựa chọn của bạn.
- Nút cuộn **không bao giờ trùng nút giữ**: `validate()` tự sửa nếu bạn ghi trùng, vì
  một nút không thể vừa "bắt đầu cử chỉ" vừa "cuộn".

### Tuỳ chỉnh một hướng, rồi trả về mặc định

1. Bấm mũi tên trên sơ đồ (bấm lại để bỏ chọn).
2. Trong bảng bên phải: **Đổi phím tắt** để ghi phím mới, **Chưa gán** để cố ý không gửi gì,
   hoặc **Cuộn ngang** (chỉ hiện với hai mũi tên tilt) để trả lại cuộn ngang nguyên bản.
3. Nhãn viên màu đổi thành **Bạn tự đặt** — đây là dấu hiệu hướng đó giờ do bạn quyết định,
   không còn lấy từ preset.
4. **Về mặc định** trả hướng đó về preset. Nút **Khôi phục toàn bộ ứng dụng này về mặc định**
   ở cuối trang xoá mọi override của app đang chọn cùng một lúc.

Nút **Về mặc định** trong bảng chi tiết gọi `resetDirection(bundle:direction:)` nên
**chỉ** xoá hướng đang mở — các hướng khác của app đó giữ nguyên. Nút ở cuối trang mới
là nút xoá cả app. (Trước đây nút trong bảng gọi `resetProfile`, tức xoá cả app trong khi
nhãn chỉ hứa một hướng; đã sửa.) Nếu bạn muốn **cố ý** để một hướng không gửi gì, hãy
dùng **Chưa gán** — nó lưu một override thật và không bị nhầm với “chưa cấu hình”.

### Bundle ID khớp thế nào, và khi nào rơi về Global

1. XFinder lấy bundle ID của **app đang ở trước** (`NSWorkspace`), rồi tra theo thứ tự:
   override riêng của bundle ID → override họ profile (khoá cũ) → preset của bundle ID.
2. **Không khớp bundle ID nào** → dùng bảng **Mặc định toàn cục**. Đây là Global đang
   thật sự có tác dụng, và dòng *Ứng dụng đang dùng:* trên trang nói rõ điều đó thay vì
   giả vờ app có preset riêng.
3. **App có preset nhưng hướng đó Chưa gán** → **không** rơi về Global. Đây là chủ ý:
   Dev/AI ↑↓ không được phép biến thành điều hướng mục chỉ vì bảng Global có giá trị.

Bảng Global mặc định (áp cho app không có profile riêng):

| Hướng | Gửi |
|---|---|
| Giữ + ↑ | ⌨︎ **Mission Control** — đúng phím bạn đã gán |
| Giữ + ↓ | ⌨︎ **App Exposé** |
| Giữ + ← | ⌨︎ **Space trước** |
| Giữ + → | ⌨︎ **Space kế tiếp** |
| Tilt ← / → | để trống — chuyển tiếp cuộn ngang nguyên bản |

\* Bốn hàng đầu là **ý định**, không phải hằng số: `SpaceBinding` giải chúng từ
`com.apple.symbolichotkeys` của chính máy bạn (đo trên máy này: `⌃↑`, `⌃↓`, `⌃←`, `⌃→`) và
**không gửi gì** nếu máy đó chưa gán. Mỗi hướng vẫn đổi được bằng **Đổi phím tắt**, hoặc
**Chưa gán** để tắt hẳn. (Bảng Global cũ quảng cáo `⌘[`/`⌘]` cho Lùi/Tiến — đã bỏ: bốn hành
động hệ thống mới là thứ người dùng thực sự cần ở bảng dự phòng.)

## Tilt, driver và tránh xung đột

- Tilt độc lập với trigger, chỉ bật khi công tắc chính và công tắc tilt đều bật.
- Chỉ nhận scroll ngang **rời rạc**, axis dọc bằng 0. Cuộn liên tục/momentum của
  trackpad và Magic Mouse được giữ nguyên. Không thể coi mọi ngang scroll là
  thao tác nghiêng bánh xe thật: Event Tap không cung cấp nhận diện vật lý ở đây.
- Giới hạn một shortcut tilt mỗi **350 ms**, chống đóng/mở tab hàng loạt khi giữ tilt.
- Nếu driver biến tilt thành nút phụ thay vì scroll ngang, ánh xạ tilt này không nhận;
  có thể ghi nút đó làm trigger, hoặc chỉnh driver. XFinder không tự đoán VID/PID.
- Tắt mapping trùng trong Mac Mouse Fix, Mos, Logitech Options, Razer hoặc app khác.
  Thứ tự event tap giữa các app không được bảo đảm.
- Không thay thế Snap Zones, Dock Preview, Clipboard hoặc Finder Keyboard.
  Trigger trái bị cấm để tránh chiếm thao tác kéo/chọn thông thường.

## Hiệu năng và kiến trúc

- `GestureEngine`: queue serial `.userInteractive` riêng + CFRunLoop nhận Mach port;
  callback không ở main thread. Main actor chỉ quản lý UI, UserDefaults và nhận
  thông báo đổi ứng dụng từ NSWorkspace.
- Motion path O(1), không dispatch task cho từng sample, không polling con trỏ.
  Worker ngủ trên run loop khi không có event/command. Tắt tính năng thì gỡ tap;
  không tạo worker ở lần chạy đầu nếu chưa bật hoặc ghi binding.
- Chỉ timer một lần cho ghi binding và hold timeout. Không có timer toàn app.
- Event tổng hợp có marker để tránh tự bắt lại click/phím do engine phát.
- Khi timeout làm tap bị disable: hủy stroke và re-enable **port còn hợp lệ**.
  Không invalidate rồi enable chính port đã hủy. Đây không phải bảo đảm không bao
  giờ timeout trên mọi phần cứng hoặc trong Secure Input.
- Debug mặc định tắt; tối đa 4 bản ghi/giây trên utility queue. Log chỉ gồm bundle ID
  và tổng delta/quãng đường, không ghi nội dung phím hoặc văn bản, không gửi mạng.
- Cấu hình lưu cục bộ trong `mouseGestures.configuration.v1` (UserDefaults JSON).
  Phím được ghi bằng virtual key code: đổi keyboard layout có thể đổi ký tự.
- **Chỉ lưu thay đổi của bạn.** `overrides` khởi tạo là `{}` và **không** được nhồi
  sẵn preset. Preset nằm trong source như lớp factory bất biến, nên bản cập nhật sau
  vẫn đổi được preset cho người dùng cũ. Kiểm chứng trên máy: bản cài mới ghi
  `{"enabled": true, …, "overrides": {}}` — đúng rỗng.
- Bản cũ từng lưu **cả** dictionary mặc định. `GestureController.migrateIfNeeded()`
  chạy một lần (cờ `mouseGestures.migrated.v1`) và chỉ xoá những dòng còn y hệt
  factory — sửa đổi thật và lựa chọn **Chưa gán** có chủ ý được giữ lại.
  Bundle ID lạ được coi là dữ liệu thật và giữ nguyên.
  Hàm này được gọi từ **cả** `init` **và** `start()`: controller là singleton tạo
  muộn, nên `init` có thể chạy sau khi một bản build khác đã ghi preferences.
  Đo trên máy với payload 18 bundle: còn lại đúng `com.apple.Safari` (một sửa đổi
  thật + một Chưa gán có chủ ý) và `my.custom.app`.
- **Lỗi giải mã không được xoá dữ liệu của bạn.** `init` đọc bằng
  `GestureController.recover(from:)`: nếu đối tượng lưu thiếu một khoá (bản cũ/mới
  lệch field), các field đọc được vẫn được giữ thay vì nuốt cả cấu hình. Đo được:
  chỉ cần thiếu một khoá là `JSONDecoder` ném `keyNotFound`, và `try?` sẽ làm mất
  toàn bộ override.
- **Thứ tự encode của override là mảng xen kẽ.** `[GestureDirection: GestureAction]`
  mã hoá thành `["up", {…}, "down", {…}]`, không phải object. Khi viết fixture cũ
  để thử migration, hãy sinh bằng `JSONEncoder` trên model thật — JSON viết tay dạng
  object sẽ không giải mã được và trông y hệt “migration không chạy”.
- Trạng thái Event Tap thật được phản chiếu vào `mouseGestures.lastTapState`
  (`active` / `failure` / `trusted`). Đây là kênh để đo từ bên ngoài: AppleScript
  không đọc được app (shell không có quyền Trợ năng), nên chuỗi trạng thái không
  phải bằng chứng — key này mới là.

## Kiểm chứng và giới hạn

Build/logic test không chứng minh chuột Razer 8 kHz đã được kiểm thử. Xem
[GESTURE_VERIFICATION.md](GESTURE_VERIFICATION.md) để biết chính xác các phép đo,
những gì đã pass và phần cần thao tác bằng phần cứng thật.

Chạy kiểm tra:

```sh
swift test --package-path Tests
swiftc -swift-version 6 \
  XFinder/Core/MouseGestures/GestureModel.swift \
  XFinder/Core/MouseGestures/GestureMap.swift \
  XFinder/Core/MouseGestures/SpaceBinding.swift \
  XFinder/Core/MouseGestures/GestureEngine.swift \
  Tests/Runtime/MouseGesturesProbe.swift -o /tmp/xfinder-gesture-probe
/tmp/xfinder-gesture-probe
# Riêng lần này sẽ thử mở event tap thật trong 2 giây, trigger là Button 31:
/tmp/xfinder-gesture-probe --live-tap
```

`GestureMap.swift` và `SpaceBinding.swift` phải có trong danh sách biên dịch: engine
đọc `GestureMap.row(...)` để lấy *ý định* của hàng, và `SpaceBinding` để giải phóng
phím cho hành động hệ thống. Harness cũng khẳng định hành động hệ thống gửi **đúng
chord của máy** (kèm bit fn) và khi máy không gán phím thì **không gửi gì cả**.

Harness mặc định dùng callback production nhưng thu event đầu ra trong bộ nhớ,
**không gửi click/phím vào ứng dụng khác**. Test package dùng symlink tới model
production để tránh bản sao logic bị lệch. Mutation test phải chạy trên scratch
copy, không sửa nguồn thật trong lúc app đang build.

## Tham khảo

- [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix): trải nghiệm giữ nút + kéo.
- [Mos](https://github.com/Caldis/Mos): trải nghiệm cấu hình chuột/cuộn theo ứng dụng.

Chỉ tham khảo README và ý tưởng tương tác; module này viết riêng, không sao chép
source, không nhúng thư viện của hai dự án và không tuyên bố tương đương mọi tính năng.
