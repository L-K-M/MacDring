# MacDring — Review, DragThing Gap Analysis & Status

A full review of the MacDring codebase against the original **DragThing**, the bugs and
gaps it surfaced, and the work shipped in response. This document is now a **status
record**: §1 lists what was found and fixed, §2–§3 are the (updated) gap analysis, and
**§4 is the succinct "what remains."**

> **Review method.** Every source and test file under `MacDring/` and `MacDringTests/`
> was read, along with `PLAN.md`, `README.md`, and `AGENTS.md`. Findings cite `file:line`
> against the code at review time.
>
> **Build/verification note.** The review and all fixes were authored in a Linux container
> with **no macOS Swift toolchain**, so nothing was compiled or unit-tested locally. Every
> change shipped as its own small PR (all since merged to `main`); macOS CI (Xcode 16+) is
> the source of truth for build + the XCTest suite. Pure-logic changes added unit tests.

---

## 1. Bugs & Issues — all fixed

Severity: **P0** correctness / data-loss / core-usability · **P1** notable functional gap ·
**P2** polish / robustness · **P3** minor / cosmetic. Every item below is **merged**.

| # | Pri | Issue | Fix | PR |
|---|-----|-------|-----|----|
| **B1** | P0 | One malformed tab discarded the *entire* launcher (`Tab.init` decoded `anchor` non-optionally → whole `[Tab]` decode threw → store fell back to empty). | Decode tabs leniently via a non-throwing `FailableTab` wrapper; a bad record is dropped, the rest survive. | #2 |
| **B2** | P0 | Tabs sharing an edge overlapped exactly — `anchor.order` was persisted but `EdgeLayout` never used it (no de-overlap pass, contra PLAN §5). | Pure `EdgeLayout.packAlongEdge` + a `TabController` pass grouping visible tabs by (display, edge) and packing by `order`/`position`. | #3 |
| **B3** | P1 | A per-tab hotkey could slide a drawer onto a parked/disconnected display (`currentScreen` went stale). | `openDrawer` resolves the screen live via `resolvedScreen(for:)`, mirroring `reconcile`'s placement. | #4 |
| **B4** | P1 | Web links couldn't be dropped — only `UTType.fileURL` was registered. | Register `.url`/`.URL`, load via `NSItemProvider`'s URL loader, route links to `.url` items (or open-with). `DrawerItem.fromDroppedURL`. | #5 |
| **B5** | P1 | `customIconBookmark` was dead; "Rename" / "Change Icon…" (PLAN §7) were unimplemented. | `resolveIcon` honors the override; item menu gains Rename / Change Icon / Reset Icon, wired through `TabController`. | #6 |
| **B6** | P2 | Every appearance-preference change ran a full window reconcile (slider drags re-listed folder tabs per tick). | Debounce the preference-driven reconcile (80 ms). | #7 |
| **B7** | P2 | An unrelated reconcile while a notes drawer was open reset the live text. | `apply(tab:preserveLiveNotes:)` keeps an open notes drawer's text. | #8 |
| **B8** | P2 | Frame-defender vs. overlapping pill animations could snap a half-animated tab. | Replace the bool guard with an animation depth count. | #9 |
| **B9** | P3 | An open drawer swallowed Esc from the app's own Settings/New-Tab windows. | Pass Esc through when a `.titled` app window is key. | #12 |
| **B10** | P3 | List layout lacked the grid's file-into / open-with drop ring. | Add the ring to list rows. | #13 |
| **B11** | P2 | Dropping/adding the same app/file/link twice created a duplicate. | De-dup in `TabStore.addItem` by standardized URL (+ tests). | #11 |
| **B12** | P3 | List drawers were a fixed 300 pt wide regardless of icon size. | Width tracks icon size + label allowance (+ tests). | #10 |

---

## 2. DragThing parity — updated

| DragThing feature | Status | Notes |
|---|---|---|
| Edge tabs → drawer | ✅ Core | The marquee feature. |
| Apps / files / folders / URLs, **drop a link** | ✅ | URL drop shipped in **#5**. |
| Multiple docks, color-coded, per-monitor, **non-overlapping** | ✅ | De-overlap shipped in **#3**. |
| Per-item **rename** / **custom icon** | ✅ | Shipped in **#6**. |
| **Trash** (open, drop-to-delete) | ✅ | Shipped in **#15** (recoverable `trashItem`). |
| Per-dock hotkeys, launch at login, stable multi-monitor restore | ✅ | Pre-existing. |
| **Layout backup / migration** | ✅ | JSON import/export shipped in **#16**. |
| **Tab reordering** + quick "Move to Edge" | ✅ | Shipped in **#14**. |
| **Disks** (mounted volumes, **eject**) | ❌ | The Trash half is done; eject-able disks remain. |
| **Recent applications / documents** dock | ❌ | Auto-populating recents. |
| **Spring-loaded folder _items_** (hierarchical pop-out) | ❌ | Folder *tabs* exist; a folder *item* still just opens in Finder. |
| **Multiple named layouts / sets** | ◑ | Import/export covers backup; in-app switching is still TODO. |
| Separators / spacers / labels within a dock | ❌ | Only freeform grid gaps. |
| Auto-hide / reveal-on-edge-hover docks | ✅ | Per-tab **Auto-hide** (slide off the edge, leaving a sliver) or **Auto-fade** (dim in place); both reveal on edge-hover. PLAN §13. |
| Process dock, sound effects, AppleScript, free placement off-edge | ❌ | Intentional non-goals. |

---

## 3. Other ideas surfaced (status)

Done: drawer-search's sibling — **tab reorder** (#14); **import/export** (#16);
**rename / change-icon** (#6). Still open:

1. **Search / type-to-find + keyboard nav** in an open drawer.
2. **Per-item launch options** (open-with override, args / open in Terminal).
3. **iCloud sync** of the layout (the document is already clean JSON).
4. **Quick Look** an item with the space bar.
5. **Accessibility** (VoiceOver labels, Dynamic Type) and **localization** scaffolding.
6. **Folder-tab niceties**: sort options, show-hidden toggle, live `FSEvents` refresh.
7. **Running-app indicator** dot on application items.
8. Non-silent **`.bak` restore** notification when a corrupt document is recovered.

---

## 4. What remains to do

Everything from §1 (bugs) and the §2 parity items marked ✅ is **merged**. What's left,
in rough priority order:

**Deliberately deferred during this pass** (small, but low value / mild risk):
- **B13** — first-run seeding fallback + non-silent `.bak` restore. Skipped because the
  seeding fallback risks the "sacred" restore logic for a very rare case.
- **B14** — wire a `LauncherDocument.version` migration switch before the schema next changes.

**Larger features** (each needs real design + an on-device GUI session, so they were not
attempted blind):
- **Drawer search / type-to-find + keyboard navigation** — interacts with the grid/slot
  model and key focus in a borderless panel.
- **Recent applications / documents** as a new tab kind.
- **Spring-loaded folder _items_** (hierarchical pop-out from a folder item).
- **Multiple named layouts / sets** with in-app switching (import/export already covers
  the backup half).
- **Eject-able Disks** items (the Trash half shipped in #15).
- **iCloud sync**, **Quick Look**, **accessibility**, **localization**.

**Outstanding from the original plan (PLAN §12, phase 10) — not code I can do here:**
- **Real-hardware GUI verification**: multi-monitor placement, Spaces, fullscreen,
  drag-to-reposition, and all drag-and-drop behaviors (including the merged changes) on an
  actual Mac.
- **Developer ID signing + notarization** for distribution.

> Net: the correctness backlog is clear and several high-value DragThing-parity features
> shipped. The remaining work is larger, design-led features plus the on-device verification
> and signing that can only happen on a Mac.
