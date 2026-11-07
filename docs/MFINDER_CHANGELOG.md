# MFinder → XFinder changelog

Newest first. “Merged” means the change is present on `main`; it does not mean the current installed app was updated or hand-tested.

| Task | What the user sees / where to go | Main commit(s) | Status |
|---|---|---|---|
| XF-MFGAP-01 | Hệ thống → Ổ đĩa → Phân tích thư mục: cached bounded tree, treemap/sunburst, selected-item inspector and folder drill-in; chart style and chart fraction persist. | `07257ae` | Builder branch only, awaiting Boss review. Build OK; storage/default tests 16/0; mutation 13/13 RED. Full gate RED: one known unrelated AgentCodex ancestor test failure. Not installed/live-tested. |
| XF-T35 | Hệ thống → Ổ đĩa → Phân tích thư mục: choose one folder, scan read-only with progress/cancel, view logical bytes and up to 50 largest files. | `1c92dc5`, `768dc83`, `ef669cb`, `74fb3c7`, `8cbfc2f` | Merged on main; installed/live behavior not verified by this Builder. |
| XF-T36 | Notch → Cách mở: choose fixed page, last used page, or current activity when clicking the notch. | `3ea38e4`, `0709dc9` | Merged on main; live behavior not verified by this Builder. |
| XF-T36B | Notch → Hiển thị khi toàn màn hình: configure notch visibility over fullscreen apps/media. | `7d79dfa`, `9e31196`, `022ee0d` | Merged on main; live behavior not verified by this Builder. |
| XF-MFGAP audit | Per-feature option crosswalk first (38 rows), 12 feature audit sections, global privacy audit, current Settings key/page inventory, and ordered follow-up plan. No settings are moved. | `d166af4` | Docs committed on `agent/codex-XF-SETTINGS`. Chart code is held at the new spec's hierarchy-retention stop condition (Q-MFGAP-11). No build/install/live claim. |

## Scope notes

- `docs/reference/MFINDER_PROMPT_SYSTEM.md` is the feature requirements source; `MFINDER_PROMPT_TEACHING.md` is educational context and is not treated as a build request.
- No MFinder branding, account, paid service, or provider infrastructure is included by this changelog.
- Any future Settings work stays with the feature that owns the option unless the owner approves an exact page/control move list.
