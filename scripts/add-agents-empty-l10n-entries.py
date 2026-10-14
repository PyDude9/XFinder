#!/usr/bin/env python3
"""2026-10-14 — why an empty notch Agents page is empty (AgentSessionRules.emptyReasonKeys). ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
ENTRIES = {
    "Chờ bạn: ": ("Waiting for you: ", "fragment"),
    "Phiên: ": ("Sessions: ", "fragment"),
    "Agent AI đang tắt — bật ở trang Agent AI.": ("AI agents are off — turn them on in AI agents settings.", "sentence"),
    "Đã bật OpenCode nhưng không tìm thấy lệnh opencode.": ("OpenCode is on, but the opencode command was not found.", "sentence"),
    "Chưa nối agent nào — cài hook cho Claude Code / Codex hoặc bật OpenCode ở trang Agent AI.": ("No agent connected yet — install the hook for Claude Code / Codex or turn on OpenCode in AI agents settings.", "sentence"),
}
def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8")); e = data["entries"]
    bad = [k for k, (en, _) in ENTRIES.items() if k in e and e[k].get("en") != en]
    for k in bad: print(f"CONFLICT: {k!r} = {e[k].get('en')!r}")
    if bad: return 1
    added = sum(1 for k in ENTRIES if k not in e)
    for k, (en, sc) in ENTRIES.items(): e.setdefault(k, {"en": en, "scope": sc})
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}"); return 0
if __name__ == "__main__": sys.exit(main())
