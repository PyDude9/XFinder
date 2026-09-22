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
4. Giữ nút mặc định (**nút giữa, Button 2** theo mã CoreGraphics), kéo lên/xuống/trái/phải,
   rồi thả: gửi đúng một hành động theo app đang ở trước.
5. Xong. Bảng bên dưới đã đúng — không cần cấu hình gì thêm.

### Nút nào, động tác nào (phần người dùng hay hỏi nhất)

Mã CoreGraphics đếm `0 = trái, 1 = phải, 2 = giữa`. Con số trần **“Button 2” vô nghĩa
với người dùng**, và một số hãng in số *khác* trên chuột. Vì vậy UI luôn nói tên
nút thật, kèm mã trong ngoặc:

| Trigger | Nút thật | Ghi chú |
|---|---|---|
| `Button 0` | **Nút trái** | Bị chặn — chiếm thao tác kéo/chọn |
| `Button 1` | **Nút phải** | Dùng được nếu bạn muốn |
| `Button 2` | **Nút giữa / bấm con lăn xuống** | **Mặc định** |
| `Button 3` | **Nút hông sau (nút 4 in trên vỏ)** | Phổ biến trên chuột gaming/văn phòng |
| `Button 4` | **Nút hông trước (nút 5 in trên vỏ)** | |
| từ `Button 5` | “Nút chuột số *n+1*” | Chuột nhiều nút |

Mỗi dòng trong bảng mapping có **hai dòng chữ**: dòng trên là hành động + phím tắt,
dòng dưới là **động tác chuột cần làm** (`Giữ nút rồi kéo LÊN`, `Nghiêng con lăn sang
TRÁI (không giữ nút)`). Mũi tên trần không cho biết có đang giữ nút hay không, cũng
không cho biết đó là kéo hay cuộn.

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
│  [Nút giữa … / Đổi nút]                  │
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

1. **Giữ** nút đã chọn (mặc định: bấm con lăn xuống — giữ nguyên, đừng nhả).
2. Vẫn giữ, **kéo** theo một hướng. Phải vượt ngưỡng (~12 đơn vị delta) mới tính là cử chỉ;
   ngắn hơn thì XFinder phát lại click bình thường.
3. **Thả** — XFinder gửi phím tắt của app đang ở trước.

Ví dụ: trong Safari, giữ nút giữa → kéo **SANG PHẢI** → thả ⇒ gửi `⌃Tab` (tab kế tiếp).

> **Tilt** chỉ dành cho chuột có con lăn **nghiêng được** trái/phải. Chuột thường và
> Magic Mouse **không có** động tác này — bật công tắc tilt cũng không làm gì. Cuộn liên
> tục của trackpad không bị bắt.

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

Sau đó ký theo thứ tự **appex trước, app sau** (ký app trước sẽ làm hỏng chữ ký con):

```sh
codesign --force --sign "XFinder Dev" --identifier com.xfinder.app.XFinderSync \
  XFinder.app/Contents/PlugIns/XFinderSync.appex
codesign --force --deep --sign "XFinder Dev" --identifier com.xfinder.app XFinder.app
```

**Cài vào `/Applications` để đường dẫn không đổi** — cùng danh tính *và* cùng path thì
mục trong System Settings không bị nhân đôi.

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
- **Ghi nút / modifier**: đổi trigger. Nút trái được giữ riêng, không cho gán.
- **Khôi phục mapping mặc định của ứng dụng**: xoá override của app đang chọn.
- **Nâng cao — ứng dụng khác**: nhập bundle ID cho app không có trong danh sách.

**Đổi chuột:** binding không gắn vào hãng/serial. Nếu chuột mới phát cùng mã nút thì
binding dùng tiếp; nếu khác, ghi lại. Magic Mouse không được giả định có nút giữa:
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

Các tên tác vụ là **ý định sử dụng**, không phải đảm bảo mọi phiên bản ứng dụng
đều có cùng shortcut. Tùy chỉnh bàn phím macOS/app có thể đổi kết quả. Ưu tiên
phím hiển thị trong XFinder và shortcut thật của ứng dụng bạn dùng.

| Profile | Giữ + ↑ | Giữ + ↓ | Giữ + ← | Giữ + → | Tilt ← / → (opt-in) |
|---|---|---|---|---|---|
| Global, app không khớp profile | ⌃↑ — Mission Control* | ⌃↓ — App Exposé* | ⌃← — Space trái* | ⌃→ — Space phải* | ⌘[ / ⌘] — lịch sử nếu app hỗ trợ |
| Edge, Safari, Chrome | ⌘T — tab mới | ⌘W — đóng tab | ⌃⇧Tab — tab trước | ⌃Tab — tab sau | Cả hai gửi ⌘⇧T — mở lại tab vừa đóng |
| VS Code, Cursor, Zed, Antigravity, Claude | **Chưa gán** | **Chưa gán** | ⌃- | ⌃⇧- | Chưa gán |
| Photoshop, CapCut | ⌘0 | ⌘Z | [ | ] | **Chưa gán** |
| Discord, Zalo, AyuGram | **Chưa gán** | **Chưa gán** | ⌥↑ | ⌥↓ | Chưa gán |
| Excel, Word | **Chưa gán** | **Chưa gán** | **Chưa gán** | **Chưa gán** | Chưa gán |
| Obsidian, Notion | ⌘P | **Chưa gán** | ⌘⌥← | ⌘⌥→ | Chưa gán |

\* Global gửi shortcut, không dùng private API để ép Mission Control/Spaces.
Phải bật đúng các shortcut đó trong cài đặt bàn phím macOS. Không khẳng định kết
quả nếu bạn đã đổi hoặc tắt chúng.

### Những mục chủ động KHÔNG gán tự động

- Dev/AI ↑: `⌃\`` có thể là terminal nhưng không phải “chat UI” chung cho mọi app.
- Dev/AI ↓: AI refactor và format code là hai hành động khác nhau.
- Chat ↑/↓: unread, đầu trang và cuối trang không phải một hành động chung.
- Office ←/→: Word không có worksheet; không gán shortcut Excel cho Word.
- Notes ↓: tạo block/page khác nhau giữa Notion và Obsidian.
- Design tilt: không gọi cuộn ngang thông thường là “smooth timeline scrubbing”.
  Có thể chọn **Cuộn ngang nguyên bản** để chuyển tiếp sự kiện, không thêm smoothing.

Những ô này có **Ghi phím** riêng theo app. “Chưa gán” trên profile đã khớp **không
rơi về Global**; nó không gửi phím. Không cần tạo thêm tính năng AI hay quản lý tab.

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
| Notes | `co.elastic.obsidian`, `com.notion.Notion-App` |

Đây là các ID cấu hình theo yêu cầu, không phải kết quả kiểm kê app đã cài.
Nếu bản app của bạn dùng ID khác (beta, fork…), chọn **Dùng ứng dụng vừa hoạt động**
hoặc nhập bundle ID trong trang cấu hình. Profile tùy chỉnh kế thừa Global cho
những hướng chưa override; đặt **Chưa gán** để vô hiệu hóa riêng một hướng.
Nút **Khôi phục toàn bộ ứng dụng này về mặc định** xóa override của profile đang chọn,
không reset trigger, deadzone hay app khác.

### Đổi chuột sang nút khác

1. Ở cột phải sơ đồ, bấm **Đổi nút** (nằm ngay dưới hình chuột).
2. Bấm nút bạn muốn giữ. Modifier (⌃ ⌥ ⇧ ⌘) cũng nhận được, miễn là **giữ đúng một cái**.
3. XFinder ghi ngay; nhấn **Esc** để huỷ, hoặc chờ 10 giây tự dừng.

Nút trái (`Button 0`) **bị từ chối** — nó chiếm thao tác kéo/chọn thông thường.
Trigger dùng chung cho mọi thiết bị theo **mã nút của event**, không theo HID identity
của từng con chuột; đổi sang con khác có số nút khác thì ghi lại.

### Tuỳ chỉnh một hướng, rồi trả về mặc định

1. Bấm mũi tên trên sơ đồ (bấm lại để bỏ chọn).
2. Trong bảng bên phải: **Đổi phím tắt** để ghi phím mới, **Chưa gán** để cố ý không gửi gì,
   hoặc **Cuộn ngang** (chỉ hiện với hai mũi tên tilt) để trả lại cuộn ngang nguyên bản.
3. Nhãn viên màu đổi thành **Bạn tự đặt** — đây là dấu hiệu hướng đó giờ do bạn quyết định,
   không còn lấy từ preset.
4. **Về mặc định** trả hướng đó về preset. Nút **Khôi phục toàn bộ ứng dụng này về mặc định**
   ở cuối trang xoá mọi override của app đang chọn cùng một lúc.

Cảnh báo như trên: nút **Về mặc định** trong bảng chi tiết hiện xoá cả app (gọi
`resetProfile`) chứ không chỉ một hướng — nhãn và hành vi đang lệch nhau, cần sửa.

### Bundle ID khớp thế nào, và khi nào rơi về Global

1. XFinder lấy bundle ID của **app đang ở trước** (`NSWorkspace`), rồi tra theo thứ tự:
   override riêng của bundle ID → override họ profile (khoá cũ) → preset của bundle ID.
2. **Không khớp bundle ID nào** → dùng bảng **Mặc định toàn cục**. Đây là Global đang
   thật sự có tác dụng, và dòng *Ứng dụng đang dùng:* trên trang nói rõ điều đó thay vì
   giả vờ app có preset riêng.
3. **App có preset nhưng hướng đó Chưa gán** → **không** rơi về Global. Đây là chủ ý:
   Dev/AI ↑↓ không được phép biến thành Mission Control chỉ vì bảng Global có ⌃↑.

Bảng Global mặc định (áp cho app không có profile riêng):

| Hướng | Gửi |
|---|---|
| Giữ + ↑ | ⌃↑ — Mission Control* |
| Giữ + ↓ | ⌃↓ — App Exposé* |
| Giữ + ← | ⌃← — Space trái* |
| Giữ + → | ⌃→ — Space phải* |
| Tilt ← / → | ⌘[ / ⌘] — lịch sử nếu app hỗ trợ |

\* Global gửi **phím tắt**, không gọi API riêng để ép Mission Control/Spaces.
macOS phải đang gán các phím đó (Cài đặt → Bàn phím → Phím tắt → Sứ mệnh điều khiển).
Nếu bạn đã đổi hoặc tắt chúng, XFinder vẫn gửi đúng ⌃↑ — chỉ là macOS không làm gì.

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
  XFinder/Core/MouseGestures/GestureEngine.swift \
  Tests/Runtime/MouseGesturesProbe.swift -o /tmp/xfinder-gesture-probe
/tmp/xfinder-gesture-probe
# Riêng lần này sẽ thử mở event tap thật trong 2 giây, trigger là Button 31:
/tmp/xfinder-gesture-probe --live-tap
```

Harness mặc định dùng callback production nhưng thu event đầu ra trong bộ nhớ,
**không gửi click/phím vào ứng dụng khác**. Test package dùng symlink tới model
production để tránh bản sao logic bị lệch. Mutation test phải chạy trên scratch
copy, không sửa nguồn thật trong lúc app đang build.

## Tham khảo

- [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix): trải nghiệm giữ nút + kéo.
- [Mos](https://github.com/Caldis/Mos): trải nghiệm cấu hình chuột/cuộn theo ứng dụng.

Chỉ tham khảo README và ý tưởng tương tác; module này viết riêng, không sao chép
source, không nhúng thư viện của hai dự án và không tuyên bố tương đương mọi tính năng.
