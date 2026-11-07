# MFinder → XFinder changelog

Newest first. “Merged” means the change is present on `main`; it does not mean the current installed app was updated or hand-tested.

| Task | What the user sees / where to go | Commit(s) | Status |
|---|---|---|---|
| XF-MFGAP-03A | Nothing visible yet: pure archive safety rules (paths, links, duplicates, limits, capacity) + read-only system libarchive manifest reader. | `d092bae` `80522af` (+ docs), merge on main 2026-11-07 | **Merged, unrouted.** Built by OpenCode while GPT-Minion was out of quota. Gate green 3010/0 (Boss, outside builder); mutation 16/20 RED, 4 equivalent redundant guards. Spec approved with Boss decisions (Merge numbers colliding files, limits, Replace transaction, source-delete fix). Next: 03B shared staging, 03C page UX. |
| XF-MFGAP-02 | CÔNG CỤ → Tìm tệp trùng: chosen-folder exact duplicates, size grouping → streaming SHA-256 → byte comparison; explicit selection/keeper, fresh preflight and per-file revalidation before Trash, cancel and per-item outcomes. | `2d77c09`, merge `1ad19cb`, Boss `8092dd0` | **Merged 2026-11-07**; Boss read the Trash step line by line; Boss fix `8092dd0` (alias lookup only for same-size candidates). Gate green 2933/0, mutation duplicates 5/5 RED. **Installed 2026-11-07 14:33** (dylib 4c3dd76c == build, appex `+`, runtime L10n 0). Hand test T-MFGAP-02: CÔNG CỤ ▸ Tìm tệp trùng ▸ chọn thư mục có 2 bản sao ⇒ một nhóm; chọn bản sao ⇒ Chuyển vào Thùng rác ⇒ tệp nằm trong Thùng rác, bản giữ lại còn nguyên. Known strictness: any unreadable file makes the scan "incomplete" and disables Trash; 500 000-file memory not measured. |
| XF-MFGAP-01 | Hệ thống → Ổ đĩa → Phân tích thư mục: cached bounded tree, treemap/sunburst, selected-item inspector and folder drill-in; chart style and chart fraction persist. | `07257ae`, merge `430e261` | **Merged + installed 2026-11-07 14:03** (dylib 7995d81c == build, appex `+`, L10n 0). Boss gate green 2922/0; mutation storage 13/13 RED. Hand test: T-MFGAP-01 (scan a folder ⇒ chart; switch Bản đồ cây/Biểu đồ vòng without rescanning; click a folder ⇒ "Mở trong biểu đồ"; "Về thư mục gốc"; relaunch keeps style + slider). Follow-up: treemap is slice-and-dice (thin strips), not squarified; sunburst has no labels. |
| XF-T35 | Hệ thống → Ổ đĩa → Phân tích thư mục: choose one folder, scan read-only with progress/cancel, view logical bytes and up to 50 largest files. | `1c92dc5`, `768dc83`, `ef669cb`, `74fb3c7`, `8cbfc2f` | Merged on main; installed/live behavior not verified by this Builder. |
| XF-T36 | Notch → Cách mở: choose fixed page, last used page, or current activity when clicking the notch. | `3ea38e4`, `0709dc9` | Merged on main; live behavior not verified by this Builder. |
| XF-T36B | Notch → Hiển thị khi toàn màn hình: configure notch visibility over fullscreen apps/media. | `7d79dfa`, `9e31196`, `022ee0d` | Merged on main; live behavior not verified by this Builder. |
| XF-MFGAP audit | Per-feature option crosswalk first (38 rows), 12 feature audit sections, global privacy audit, current Settings key/page inventory, and ordered follow-up plan. No settings are moved. | `d166af4` | Docs committed on `agent/codex-XF-SETTINGS`. Chart code is held at the new spec's hierarchy-retention stop condition (Q-MFGAP-11). No build/install/live claim. |

## Scope notes

- `docs/reference/MFINDER_PROMPT_SYSTEM.md` is the feature requirements source; `MFINDER_PROMPT_TEACHING.md` is educational context and is not treated as a build request.
- No MFinder branding, account, paid service, or provider infrastructure is included by this changelog.
- Any future Settings work stays with the feature that owns the option unless the owner approves an exact page/control move list.
