#!/usr/bin/env python3
"""Export a mind map of every XFinder feature, generated from the source of truth in the code (2026-11-09, owner:
"xuất Mindmap toàn bộ chức năng của XFinder để tôi nghiên cứu và chỉnh sửa lại sau này").

Reads:  Models/SidebarDestination.swift (pages and their sidebar groups), Core/FeatureCatalog.swift (every feature with
        its key, default, permissions and idle cost, plus the bundles), Core/Browser/BrowserCommands.swift (commands and
        chords), Core/Browser/BrowserMenuLayout.swift (the browser menu bar), Core/Browser/BrowserToolbar.swift (toolbar
        items), Views/Browser/BrowserSettingsWindow.swift (browser settings sections), Core/Notch/NotchSurfaceMachine.swift
        (notch pages), App/XFinderApp.swift (xfinder:// deep links), Resources/L10n.strings.json (English titles).
Writes: docs/XFINDER_FEATURE_MINDMAP.md   — nested outline (Obsidian / Markmap / any outliner; edit this one)
        docs/XFINDER_FEATURE_MINDMAP.opml — the same tree as OPML (MindNode, XMind, iThoughts, Freeplane import it)
        docs/XFINDER_FEATURE_MINDMAP.html — the outline rendered as a mind map in the browser (Markmap from a CDN)
Run:    python3 scripts/export-feature-mindmap.py   (exit 1 if a feature or command has no title — the map would be short)
"""
from __future__ import annotations
import html, json, re, sys
from datetime import date
from pathlib import Path
from xml.sax.saxutils import quoteattr

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "XFinder"
L10N = json.loads((SRC / "Resources/L10n.strings.json").read_text(encoding="utf-8"))["entries"]


def en(key: str) -> str:
    return (L10N.get(key) or {}).get("en", "")


def bi(key: str) -> str:
    """'Tiêu đề (Title)' — Vietnamese key with its English, when the English differs."""
    e = en(key)
    return f"{key} ({e})" if e and e != key else key


def read(rel: str) -> str:
    return (SRC / rel).read_text(encoding="utf-8")


def cases_in(block: str) -> dict[str, str]:
    """`case .name: return "Title"` pairs inside one Swift switch/enum block."""
    return dict(re.findall(r'case \.(\w+):\s*return "([^"]+)"', block))


def block_after(text: str, marker: str, end_pattern: str = r"\n    (?:var|static|func|private|@)") -> str:
    start = text.index(marker)
    m = re.search(end_pattern, text[start + len(marker):])
    return text[start: start + len(marker) + (m.start() if m else len(text))]


class Node:
    def __init__(self, title: str, note: str = ""):
        self.title, self.note, self.children = title, note, []

    def add(self, title: str, note: str = "") -> "Node":
        child = Node(title, note)
        self.children.append(child)
        return child


# MARK: - Pages (sidebar)

def pages() -> Node:
    text = read("Models/SidebarDestination.swift")
    titles = cases_in(block_after(text, "var titleKey: String {"))
    groups_block = block_after(text, "static var groups:", r"\n    \}\n")
    node = Node("Trang trong cửa sổ chính (sidebar)", "Mỗi trang một việc; nhóm theo ý định người dùng")
    tabs = {"system": ["network", "storage", "pin"], "finderSearch": ["aiSearch"], "quickLookPage": ["mediaCompat"]}
    placed: set[str] = set()
    for header, items in re.findall(r'\("([^"]+)",\s*\[([^\]]+)\]\)', groups_block):
        group = node.add(header)
        for dest in re.findall(r"\.(\w+)", items):
            placed.add(dest)
            page = group.add(bi(titles.get(dest, dest)), f"SidebarDestination.{dest}")
            for tab in tabs.get(dest, []):
                placed.add(tab)
                page.add("Tab: " + bi(titles.get(tab, tab)), f"SidebarDestination.{tab}")
    others = node.add("Không nằm trong sidebar", "mở bằng liên kết hoặc footer")
    for dest, title in titles.items():
        if dest not in placed:
            others.add(bi(title), f"SidebarDestination.{dest}")
    return node


# MARK: - Feature catalog

def catalog() -> Node:
    # Comments between a literal's fields (the voice row carries a two-line one) would break the field pattern.
    text = re.sub(r"(?m)^\s*//[^\n]*\n", "", read("Core/FeatureCatalog.swift"))
    text = re.sub(r"(?m)[ \t]+//[^\n]*$", "", text)
    group_titles = cases_in(block_after(text, "enum FeatureGroup", r"\n}\n"))
    idle_titles = cases_in(block_after(text, "enum IdleCost", r"\n}\n"))
    permission_titles = cases_in(block_after(text, "var titleKey: String {", r"\n    \}\n")) if "enum AppPermission" in text else {}
    feature_ids = re.findall(r"^\s*case ([\w, ]+)\s*(?://.*)?$", block_after(text, "enum FeatureID", r"\n}\n"), re.M)
    all_ids = {i.strip() for line in feature_ids for i in line.split(",") if i.strip()}
    pattern = re.compile(
        r'FeatureDef\(id: \.(\w+),\s*titleKey: "([^"]+)",\s*subtitleKey: "([^"]+)",\s*symbol: "[^"]+",\s*group: \.(\w+),\s*'
        r'enabledKey: "([^"]+)",\s*defaultOn: (true|false),\s*permissions: \[([^\]]*)\],\s*idle: \.(\w+)\)', re.S)
    defs = pattern.findall(text)
    node = Node("Tính năng & Quyền (FeatureCatalog)", "Mỗi tính năng: khoá bật/tắt, mặc định, quyền macOS, chi phí khi nghỉ")
    by_group: dict[str, Node] = {}
    seen: set[str] = set()
    for fid, title, subtitle, group, key, default, perms, idle in defs:
        seen.add(fid)
        g = by_group.get(group) or by_group.setdefault(group, node.add(bi(group_titles.get(group, group))))
        perm_list = [p.strip(". ") for p in perms.split(",") if p.strip()]
        details = [
            f"khoá `{key}` · mặc định {'BẬT' if default == 'true' else 'tắt'}",
            "quyền: " + (", ".join(permission_titles.get(p, p) for p in perm_list) if perm_list else "không cần"),
            "khi nghỉ: " + idle_titles.get(idle, idle),
        ]
        f = g.add(bi(title), en(subtitle) and f"{subtitle} ({en(subtitle)})" or subtitle)
        for d in details:
            f.add(d)
    missing = sorted(all_ids - seen)
    if missing:
        print("FeatureID without a FeatureDef:", missing, file=sys.stderr)
        sys.exit(1)
    bundles = re.findall(r'FeatureBundle\(id: "([^"]+)", titleKey: "([^"]+)",\s*descriptionKey: "([^"]+)",[^)]*?turnOn: \[([^\]]*)\], turnOff: \[([^\]]*)\]\)', text, re.S)
    if bundles:
        b = node.add("Gói cài đặt nhanh (FeatureBundle)", "một chạm bật/tắt nhiều tính năng")
        for _, title, desc, on, off in bundles:
            x = b.add(bi(title), desc)
            x.add("bật: " + ", ".join(re.findall(r"\.(\w+)", on)) or "bật: —")
            x.add("tắt: " + (", ".join(re.findall(r"\.(\w+)", off)) or "—"))
    return node


# MARK: - File browser

GLYPHS = {"up": "↑", "down": "↓", "left": "←", "right": "→", "return": "↩", "delete": "⌫", "space": "␣", "tab": "⇥",
          "escape": "⎋", "f2": "F2"}


def chord_text(args: str) -> str:
    key = re.match(r'"([^"]+)"', args).group(1)
    mods = ("⌃" if "control: true" in args else "") + ("⌥" if "option: true" in args else "") + \
           ("⇧" if "shift: true" in args else "") + ("⌘" if "command: true" in args else "")
    return mods + GLYPHS.get(key, key.upper())


def browser() -> Node:
    commands = read("Core/Browser/BrowserCommands.swift")
    titles = cases_in(block_after(commands, "static func titleKey(_ command: BrowserCommand) -> String {", r"\n    \}\n"))
    chords = {c: chord_text(a) for c, a in re.findall(r"\.(\w+): KeyChord\(([^)]*)\)", block_after(commands, "private static let table", r"\n    \]"))}
    all_commands = {i.strip() for line in re.findall(r"^\s*case ([\w, ]+)\s*(?://.*)?$", block_after(commands, "enum BrowserCommand", r"\n}\n"), re.M)
                    for i in line.split(",") if i.strip()}
    untitled = sorted(all_commands - set(titles))
    if untitled:
        print("BrowserCommand without a title:", untitled, file=sys.stderr)
        sys.exit(1)

    def cmd(c: str) -> str:
        t = bi(titles.get(c, c))
        return f"{t} — {chords[c]}" if c in chords else t

    layout = read("Core/Browser/BrowserMenuLayout.swift")
    menu_titles = cases_in(block_after(layout, "static func titleKey(_ menu: Menu) -> String {", r"\n    \}\n"))
    sub_titles = cases_in(block_after(layout, "static func titleKey(_ submenu: Submenu) -> String {", r"\n    \}\n"))
    link_titles = cases_in(block_after(layout, "static func titleKey(_ link: Link) -> String {", r"\n    \}\n"))
    action_titles = cases_in(block_after(layout, "static func titleKey(_ action: Action) -> String {", r"\n    \}\n"))
    static_subs = block_after(layout, "static func entries(_ submenu: Submenu) -> [Entry]? {", r"\n    \}\n")
    top = block_after(layout, "static func entries(_ menu: Menu) -> [Entry] {", r"\n    \}\n")

    def entries(block: str, case_name: str) -> list[tuple[str, str]]:
        m = re.search(r"case \.%s:(.*?)(?=\n        case \.|\n        \}|$)" % case_name, block, re.S)
        return re.findall(r"\.(command|submenu|link|action)\(\.(\w+)\)", m.group(1)) if m else []

    node = Node("Trình duyệt tệp (XF-T28…T39)", "cửa sổ nhiều ngăn, tab từng ngăn, theo Tilde về giao diện, FileOctopus về tính năng")
    menubar = node.add("Thanh menu khi trình duyệt ở trước (XF-T38)", "Tệp/Đi là menu riêng; khối trong Edit/View/Window qua SwiftUI")
    listed: set[str] = set()
    for menu in ["app", "file", "edit", "view", "go", "window"]:
        m = menubar.add(bi(menu_titles.get(menu, menu)))
        for kind, name in entries(top, menu):
            if kind == "command":
                listed.add(name); m.add(cmd(name))
            elif kind == "submenu":
                s = m.add(bi(sub_titles.get(name, name)) + " ▸")
                for k2, n2 in entries(static_subs, name):
                    if k2 == "command":
                        listed.add(n2); s.add(cmd(n2))
            elif kind == "link":
                m.add(bi(link_titles.get(name, name)) + " → trang XFinder")
            else:
                m.add(bi(action_titles.get(name, name)))
    other = node.add("Lệnh khác (bảng lệnh ⌘K › `>`, chuột phải, phím)", "không nằm trong menu bar")
    for c in sorted(all_commands - listed, key=lambda c: titles.get(c, c)):
        other.add(cmd(c))

    toolbar = read("Core/Browser/BrowserToolbar.swift")
    labels: dict[str, str] = {}
    for chunk in re.split(r"\n    (?=(?:private )?func )", toolbar):   # one function per chunk, so a title never leaks
        m = re.match(r"(?:private )?func make(\w+)Item\(\)", chunk)
        t = re.search(r'let title = L10n\.t\("([^"]+)"\)', chunk)
        if m and t:
            labels[m.group(1)[0].lower() + m.group(1)[1:]] = t.group(1)
    fixed = {"sidebar": "Ẩn/hiện sidebar", "newFolder": "Thư mục mới", "quickLook": "Xem nhanh", "backForward": "Lùi / Tiến",
             "view": "Kiểu xem", "group": "Nhóm theo", "paneLayout": "Bố cục ngăn", "share": "Chia sẻ", "action": "Tác vụ (…)",
             "search": "Tìm", "downloads": "Khay Tải về", "tags": "Thẻ", "enclosingFolder": "Thư mục cha", "goToFolder": "Đến thư mục",
             "workspaces": "Workspace", "shelf": "Shelf", "operations": "Hàng đợi thao tác"}
    tb = node.add("Thanh công cụ (Navigation Bar)")
    default_ids = re.findall(r"ID\.(\w+)", block_after(toolbar, "func toolbarDefaultItemIdentifiers", r"\n    \}\n"))
    allowed_ids = [i for i in re.findall(r"ID\.(\w+)", block_after(toolbar, "func toolbarAllowedItemIdentifiers", r"\n    \}\n")) if i not in default_ids]
    d = tb.add("Mặc định")
    for i in default_ids:
        d.add(bi(fixed.get(i) or labels.get(i, i)))
    c = tb.add("Thêm được qua Tuỳ biến thanh công cụ")
    for i in allowed_ids:
        c.add(bi(fixed.get(i) or labels.get(i, i)))

    settings = read("Views/Browser/BrowserSettingsWindow.swift")
    st = node.add("Cài đặt trình duyệt (⌘, khi trình duyệt ở trước)")
    for title in re.findall(r'SettingsSection\(title: L10n\.t\("([^"]+)"\)', settings):
        st.add(bi(title))

    search = node.add("Tìm kiếm (ô tìm trên thanh công cụ)", "Spotlight + chỉ mục tên riêng + chỉ mục nội dung FTS5 (tuỳ chọn)")
    search.add("Phạm vi: Máy này (thư mục đã chỉ mục) · Thư mục hiện tại · Các ngăn đang mở")
    search.add("Câu tự nhiên VI/EN: \"ảnh tuần trước\", \"pdfs from last week\", \"lớn hơn 10 MB\", \"tải từ github\"")
    g = search.add("Bộ lọc `trường:giá trị` (thành chip)")
    for line in ["kind: pdf · image · video · audio · document · spreadsheet · presentation · archive · folder · app · screenshot · code · text",
                 "ext:pdf · tag:/tags:work · from:gmail (hiểu cả miền tệp đính kèm) · content:từ · in:/trong:thư-mục",
                 "size: >5MB · <=200KB · =0 (không đơn vị = byte)",
                 "modified:/created: today · yesterday · thisweek · lastweek · thismonth · lastmonth · thisyear · lastyear · <7d · >2w · <3m · <1y · 2026-10-01 · 2026-10-01..2026-10-10",
                 "cụm \"trong ngoặc\" · loại trừ -từ / !từ",
                 "Cảnh báo hiện dưới ô: bộ lọc lạ, ngày/cỡ/loại/đuôi sai, thiếu giá trị, thiếu ngoặc kép, quá 256 ký tự / 16 từ"]:
        g.add(line)
    search.add("Lưu tìm kiếm… → Tìm kiếm đã lưu (sidebar, menu Đi)")

    ws = node.add("Workspace & phiên (XF-T39)")
    for line in ["Lưu Workspace: mọi cửa sổ đang mở (tab, ngăn, thư mục, kiểu xem); trùng tên ⇒ hỏi Thay thế",
                 "Mở workspace: thêm cửa sổ, không thay cửa sổ đang mở (Window ▸ Mở workspace ▸, hoặc ⌘K gõ tên)",
                 "Đổi tên / Nhân bản / Xoá / Xem các workspace đã lưu… / Xuất các workspace… (tên, bố cục, thư mục)",
                 "Mở lại cửa sổ khi mở app (tab, ngăn, lịch sử Lùi/Tiến); giữ Shift khi mở để bỏ qua",
                 "Tệp lưu hỏng được chuyển sang bên, không bị ghi đè"]:
        ws.add(line)

    ops = node.add("Thao tác tệp an toàn")
    for line in ["Hàng đợi: tiến trình, tốc độ, Tạm dừng/Tiếp tục, Dừng, danh sách Sự cố + Thử lại",
                 "Hộp trùng tên: Thay thế (không áp cho thư mục/gói) · Giữ cả hai · Bỏ qua · Dừng · Gộp… (xem trước; Giữ bản mới hơn ≥ 1 s, ổ thô 2 s) · Áp dụng cho tất cả",
                 "Chép/chuyển cùng ổ = clone/rename; khác ổ = chép + kiểm hash + Thùng rác bản gốc",
                 "Hoàn tác bền ⌘Z / Làm lại ⇧⌘Z (20 bước, 24 h, kiểm lại trước khi chạy); nhật ký chống ngắt + Báo cáo khôi phục",
                 "Đổi tên: một luật tên (rỗng, ':' '/', '.', ký tự điều khiển, 255 đơn vị NFD); chỉ đổi hoa/thường được; renamex_np không bao giờ đè",
                 "Đổi tên hàng loạt ⌃⌘R: Thay chữ · Thêm chữ · Định dạng (Tên và chỉ số / bộ đếm / ngày); một lỗi chặn cả lô; hoán đổi tên được; một ⌘Z",
                 "Nén ZIP, Thêm vào Shelf, Chép/Chuyển sang ngăn kia, Cắt ⌘X kiểu Windows (tuỳ chọn), Thư mục mới chứa mục chọn, Tạo bí danh"]:
        ops.add(line)
    return node


# MARK: - Notch, deep links, integrations

def notch() -> Node:
    machine = read("Core/Notch/NotchSurfaceMachine.swift")
    pages = re.findall(r"enum Page[^{]*\{ case ([\w, ]+) \}", machine)
    names = {"files": "Khay thả (tệp)", "clipboard": "Clipboard", "nowPlaying": "Đang phát", "agents": "Agent AI",
             "calendar": "Lịch & lời nhắc", "timer": "Hẹn giờ", "aiUsage": "Hạn mức AI"}
    node = Node("Notch (SurfacePanel 650×188)", "một panel cố định, máy trạng thái thuần NotchSurfaceMachine")
    p = node.add("Trang (chấm) và công cụ (thanh)")
    for name in [n.strip() for n in pages[0].split(",")] if pages else []:
        p.add(names.get(name, name))
    for line in ["Peek / mở rộng; bấm huy hiệu mở trang theo `notch.clickOpens` (cố định · lần cuối · theo hoạt động)",
                 "HUD âm lượng / độ sáng chen hàng đợi", "Ẩn trong ứng dụng toàn màn hình (`notch.fullscreenVisibility`)",
                 "Ghi chú mép (Edge notes): peek ở mép màn hình, ⌃⌥N, tự sao lưu hằng ngày",
                 "Hoạt động trực tiếp: Bluetooth, pin, SoC °C, GPU %, mạng…"]:
        node.add(line)
    return node


def links() -> Node:
    app = read("App/XFinderApp.swift")
    handler = block_after(app, "private func handleFinderURL(_ url: URL) {", r"\n    \}\n")
    desc = {"browser": "mở trình duyệt tệp tại ?path=", "droptray-add": "thêm ?path= vào Khay thả và hiện notch",
            "settings": "mở trang ?page=<SidebarDestination>", "translate": "dịch ?text= hoặc vùng đang chọn",
            "clipboard": "mở Thư viện Clipboard", "capture": "chụp & chú thích", "notch": "mở notch ?page=",
            "n": "trang Ghi chú", "l": "trang Ghi chú", "p": "ghim ghi chú đang mở"}
    node = Node("Liên kết sâu xfinder://", "dùng từ Shortcuts, Alfred, Raycast, agent…")
    for host in re.findall(r'case "([a-z-]+)"', handler):
        node.add(f"xfinder://{host} — {desc.get(host, '')}".rstrip(" —"))
    return node


def integrations() -> Node:
    node = Node("Tích hợp & tiến trình phụ")
    for line in ["`XFinder --mcp`: máy chủ MCP cho Clipboard (agent đọc/ghi clipboard)",
                 "`XFinder --vision <ocr-fast|ocr-accurate|cutout|stitch>`: Vision chạy ở tiến trình con (giữ bộ nhớ app chính 26 MB)",
                 "`XFinder --crew-guard`: hook quyền cho crew agent (ask/deny lệnh đổi trạng thái, chặn ghi ngoài worktree)",
                 "XFinderSync.appex: Finder Sync (menu Thao tác Finder trong Finder)",
                 "XFinderNowPlaying.dylib qua perl host: Đang phát (MediaRemote)",
                 "Agent AI: hook Claude Code / Codex, OpenCode qua CLI, Gemini; crew ký HMAC, handoff, thống kê hạn mức",
                 "Trợ năng + Ghi màn hình: ⌘-Tab, Xem trước Dock, Vùng bắt dính, Giữ ⌘Q, HUD",
                 "Thống kê ẩn danh tắt được (`analytics.optOut`); không tự cập nhật"]:
        node.add(line)
    return node


# MARK: - Output

def to_markdown(root: Node) -> str:
    lines = [f"# {root.title}", "", f"> {root.note}", "",
             "> Sinh bằng `python3 scripts/export-feature-mindmap.py` từ mã nguồn — phần sinh sẽ bị ghi đè lần sau; phần",
             "> **Ghi chú của chủ dự án** ở cuối tệp được giữ nguyên. Mở bằng Obsidian (plugin mindmap), Markmap, hoặc nhập",
             "> `XFINDER_FEATURE_MINDMAP.opml` vào MindNode / XMind / iThoughts; `XFINDER_FEATURE_MINDMAP.html` xem ngay trong trình duyệt.", ""]
    for branch in root.children:
        lines.append(f"## {branch.title}")
        if branch.note:
            lines.append(f"*{branch.note}*")
        lines.append("")

        def walk(node: Node, depth: int) -> None:
            for child in node.children:
                note = f" — {child.note}" if child.note else ""
                lines.append("    " * depth + f"- {child.title}{note}")
                walk(child, depth + 1)
        walk(branch, 0)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def to_opml(root: Node) -> str:
    def walk(node: Node, depth: int) -> list[str]:
        out = []
        for child in node.children:
            attrs = f"text={quoteattr(child.title)}" + (f" _note={quoteattr(child.note)}" if child.note else "")
            if child.children:
                out.append("  " * depth + f"<outline {attrs}>")
                out += walk(child, depth + 1)
                out.append("  " * depth + "</outline>")
            else:
                out.append("  " * depth + f"<outline {attrs}/>")
        return out
    body = [f"<outline text={quoteattr(root.title)} _note={quoteattr(root.note)}>"] + walk(root, 1) + ["</outline>"]
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<opml version="2.0">\n<head><title>XFinder — mind map chức năng</title>'
            f'<dateCreated>{date.today().isoformat()}</dateCreated></head>\n<body>\n' + "\n".join(body) + "\n</body>\n</opml>\n")


def to_html(markdown: str) -> str:
    return ("<!doctype html><html lang=\"vi\"><head><meta charset=\"utf-8\"><title>XFinder — mind map chức năng</title>"
            "<style>body,html{margin:0;height:100%}svg.markmap{width:100%;height:100vh}</style></head><body>"
            "<script src=\"https://cdn.jsdelivr.net/npm/markmap-autoloader@0.18\"></script>"
            "<div class=\"markmap\"><script type=\"text/template\">\n" + html.escape(markdown, quote=False) +
            "\n</script></div></body></html>\n")


OWNER_MARKER = "<!-- owner-notes: mọi thứ dưới dòng này được giữ nguyên khi sinh lại -->"


def owner_notes(existing: Path) -> str:
    """The owner's own section at the end of the outline survives every regeneration."""
    if existing.exists():
        text = existing.read_text(encoding="utf-8")
        if OWNER_MARKER in text:
            return text[text.index(OWNER_MARKER):].rstrip() + "\n"
    return OWNER_MARKER + "\n\n## Ghi chú của chủ dự án\n\n- (viết ở đây: tính năng cần bỏ, gộp, đổi tên, ý tưởng mới…)\n"


def main() -> int:
    plist = (SRC / "Info.plist").read_text(encoding="utf-8")
    version = re.search(r"CFBundleShortVersionString</key>\s*<string>([^<]+)", plist)
    root = Node(f"XFinder {version.group(1) if version else ''} — mind map chức năng ({date.today().isoformat()})",
                "macOS 14+ · Swift 6 · arm64 · mọi tính năng mở trong bản Debug cài trên máy")
    for branch in [pages(), catalog(), browser(), notch(), links(), integrations()]:
        root.children.append(branch)
    target = ROOT / "docs/XFINDER_FEATURE_MINDMAP.md"
    md = to_markdown(root) + "\n" + owner_notes(target)
    target.write_text(md, encoding="utf-8")
    (ROOT / "docs/XFINDER_FEATURE_MINDMAP.opml").write_text(to_opml(root), encoding="utf-8")
    (ROOT / "docs/XFINDER_FEATURE_MINDMAP.html").write_text(to_html(md), encoding="utf-8")

    def count(node: Node) -> int:
        return 1 + sum(count(c) for c in node.children)
    print("nodes:", count(root) - 1, "| branches:", [f"{b.title.split(' (')[0]}: {count(b) - 1}" for b in root.children])
    return 0


if __name__ == "__main__":
    sys.exit(main())
