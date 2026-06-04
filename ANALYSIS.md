# MacDring — Review, Gap Analysis & Backlog

A full review of the MacDring codebase as of branch `claude/dragthing-review-analysis-uNwgJ`,
a gap analysis against the original **DragThing**, and a prioritized backlog of fixes
and features. Each prioritized item is intended to ship as its own PR (see
[§4 Prioritized backlog](#4-prioritized-backlog)).

> **Review method.** Every source file under `MacDring/` and `MacDringTests/` was read,
> along with `PLAN.md`, `README.md`, and `AGENTS.md`. Findings below cite `file:line`.
>
> **Build caveat.** This review was performed in a Linux container with no macOS Swift
> toolchain, so the project could not be compiled or its XCTest suite run here. Pure-logic
> findings are reasoned from the code and the existing tests; on-screen/window behavior is
> inferred from the code and the GUI notes in `PLAN.md §12`. All code changes that follow
> from this analysis should be built and tested on macOS (Xcode 16+) before merge.

---

## 1. Bugs & Issues

Severity key: **P0** correctness / data-loss / core-usability · **P1** notable functional gap ·
**P2** polish / robustness · **P3** minor / cosmetic.

### B1 — One malformed tab discards the *entire* launcher document (P0, data-loss)
`Tab.init(from:)` decodes `anchor` with a non-optional `try c.decode(ScreenAnchor.self, …)`
(`MacDring/Model/Tab.swift:73`). If a single tab is missing/has a corrupt `anchor`, the
whole `[Tab]` decode throws, `TabStore.decode` returns `nil`
(`MacDring/Store/TabStore.swift:78`), and the store falls back to the `.bak` — which, if it
shares the defect, leaves the user with **zero tabs**. A launcher people have arranged is
exactly the thing the design calls "sacred" (PLAN §2/§6), so a single bad record should not
nuke everything. **Fix:** decode tabs leniently (decode element-by-element, skipping
unreadable ones) so one bad tab is dropped, not the whole document.

### B2 — Tabs sharing an edge overlap; `order` is never used for layout (P0, usability)
`ScreenAnchor.order` is persisted and preserved on drag (`TabController.swift:206`) but
**`EdgeLayout` never consumes it** — there is no de-overlap pass. Two tabs anchored to the
same edge at the same fractional position render exactly on top of each other. PLAN §5
explicitly promises "Tabs sharing an edge on a screen are spaced by `order` + `position`,
de-overlapped by a layout pass." `NewTabWindowController` only papers over this by staggering
the *initial* position (`NewTabWindowController.swift:49-50`); dragging two tabs together, or
seeding + adding, still collides. **Fix:** add a layout pass in `TabController.reconcile` that
groups tabs by (display, edge) and offsets stacked tabs along the edge by `order`.

### B3 — A per-tab hotkey can open a drawer onto a disconnected/stale screen (P1)
When a tab's display is unplugged under the default **park** policy, `reconcile` calls
`wc.hide()` (`TabController.swift:78`) but never clears `TabWindowController.currentScreen`,
which keeps pointing at the now-detached `NSScreen`. `openDrawer` guards only on
`wc.currentScreen != nil` (`TabController.swift:120-122`), so firing that tab's Carbon hotkey
will still try to slide a drawer out on a stale screen. **Fix:** in `openDrawer`, require the
tab's `anchor.displayUUID` to currently resolve via the registry (or clear `currentScreen` in
`hide()` / on park).

### B4 — Web links / URLs can't be dropped onto tabs or drawers (P1, DragThing parity)
The pill registers only `UTType.fileURL` for `.onDrop` (`TabStripView.swift:33`) and the
drawer's AppKit destination registers only `.fileURL`
(`DrawerWindowController.swift:109`, `droppableModel` checks `urlReadingFileURLsOnly`
`:46`). Dragging a URL out of Safari/Chrome's address bar (a `public.url` / text payload)
does nothing. The app *can* hold `.url` items (`DrawerItem.fromLink`), but the only way to
create one is the **Add Link…** sheet in Settings. DragThing let you drop a link straight
onto a dock. **Fix:** accept `public.url`/`public.utf8-plain-text`, build `.url` items.

### B5 — `customIconBookmark` is dead; "Change Icon…" and "Rename" are unimplemented (P1)
PLAN §7 and the README advertise an item context menu with **Rename** and **Change Icon…**,
and the model carries `customIconBookmark` (`DrawerItem.swift:23`). But `ItemView.resolveIcon`
never reads it (`ItemView.swift:69-82`) and the item context menu only offers
Open / Reveal / Remove (`ItemView.swift:24-33`). So a documented capability and a persisted
field are both inert. **Fix:** add Rename + Change Icon… actions, honor `customIconBookmark`
in `resolveIcon`, and wire the callbacks through `DrawerModel`/`TabController`/`TabStore`.

### B6 — Every appearance-preference change triggers a full window reconcile (P2, perf)
`TabController` subscribes to `preferences.objectWillChange` and calls `reconcile()` on *any*
change (`TabController.swift:43-45`). Dragging the Icon-size, Corner-radius, Tab-thickness, or
Animation sliders in Settings fires this continuously; each `reconcile` re-measures and
repositions **every** tab window (`place` → `layoutSubtreeIfNeeded` + `fittingSize`, then
`applyFrame`) and **re-lists every folder tab's directory** (`apply` → `FolderLister.contents`).
That's a lot of work per slider tick, and it churns disk I/O for folder tabs. **Fix:** debounce
the preference-driven reconcile, and/or only reconcile on settings that actually change layout.

### B7 — Notes text can be reset mid-edit by an unrelated reconcile (P2)
Typing in a notes drawer is intentionally decoupled (`TabStore.setNotes` skips `onChange`,
`TabStore.swift:179-185`). But if a reconcile is triggered for *any other* reason while a notes
drawer is open — a screen-parameters change, a preference change, or a mutation to a different
tab — `refreshOpenDrawer` → `DrawerWindowController.apply` resets `model.notes = tab.notes`
(`DrawerWindowController.swift:236-238`), disrupting the `TextEditor` (selection/scroll, and any
in-flight IME composition). **Fix:** when refreshing an open notes drawer, don't overwrite
`model.notes` from the store (the model is already the live source while editing).

### B8 — Frame-defender vs. overlapping pill animations race (P2)
`animate(to:)` sets `isAdjustingFrame = true` and clears it in the completion handler
(`TabWindowController.swift:171-183`). If a second animation starts before the first finishes
(rapid open/close/switch), the *first* completion clears the flag while the *second* is still
running, so `defendFrame` (`:101-110`) can wrongly fire and snap the pill to a half-animated
`intendedFrame`. **Fix:** track a generation/counter or suppress the defender via a depth count
rather than a single bool.

### B9 — Esc and click-outside monitors are app-global while a drawer is open (P2)
`startMonitoring` installs an app-wide local key monitor that consumes **Esc** and returns
`nil` (`TabController.swift:379-385`). If a drawer is open and the user presses Esc while
interacting with the **Settings** window (e.g. to dismiss a sheet/popover), the drawer eats the
Esc instead. Similarly the global mouse monitor closes the drawer on the click that the user
meant for Settings. Low-frequency, but surprising. **Fix:** ignore Esc when the key window
belongs to the app's own ordinary windows (Settings/New Tab).

### B10 — List layout has no drop feedback for empty space (P3)
In `.list` layout, only occupied rows highlight on file-drag
(`DrawerView.swift:151-153`); there's no "drop here / append" affordance for the empty area, and
no per-row "into folder / open-with" ring like the grid has (`:174-179`). Cosmetic
inconsistency. **Fix:** render a list-tail drop indicator and the into/open-with ring in list
mode too.

### B11 — Adding the same app/file twice silently duplicates it (P3)
`handleFileDrop` and the Settings "Add Files…" path append unconditionally
(`TabController.swift:269-272`, `TabsView.swift:286-288`). Dropping an app that's already in the
tab makes a second copy. DragThing de-duplicated optionally. **Fix:** skip (or offer to skip)
adding an item whose resolved URL already exists in the tab.

### B12 — `DrawerMetrics` list width is a hardcoded 300 pt (P3)
List-layout drawers are always 300 pt wide regardless of icon size or label length
(`DrawerMetrics.swift:56`), so long names truncate hard. **Fix:** derive list width from icon
size + a label allowance, clamped to the screen.

### B13 — Seeding silently no-ops if no display UUID resolves (P3)
`seedStarterTab` returns silently when `mainScreenUUID()` is `nil`
(`AppDelegate.swift:132`), so a first-run user on an odd display setup gets an empty menu-bar
app with no tab and no hint. Rare, but there's no fallback or message. **Fix:** fall back to a
best-effort anchor and/or surface a first-run hint.

### B14 — Minor robustness / cleanups (P3)
- `LauncherDocument.version` exists but no migration switch is keyed off it
  (`LauncherDocument.swift`); only slot-normalization migrates. Fine today, but document the
  intent or wire a version switch before the schema changes.
- The `.bak` recovery is silent (PLAN §9 envisioned "offer to restore"); there's no user-facing
  indication the primary file was corrupt. Consider a one-line notification.
- `BookmarkResolver.makeBookmark` uses non-security-scoped options — correct for the v1
  Developer-ID build, but the App Store path (PLAN §10) is still entirely TODO.

---

## 2. Gaps to DragThing

DragThing (TLA Systems, 1995–2019) did more than edge-tabs-into-drawers. Against its feature
set, MacDring is missing:

| DragThing feature | Status in MacDring | Notes |
|---|---|---|
| Edge tabs that collapse to a drawer | ✅ Core feature | The thing people miss most. |
| Hold apps / files / folders / URLs | ✅ (URL add via Settings only) | See **B4** — no URL *drop*. |
| Multiple docks, color-coded, per-monitor | ✅ tabs | But stacking on one edge is broken — see **B2**. |
| **Disks dock** (mounted volumes, **eject**) | ❌ Missing | A staple DragThing dock. |
| **Trash** (show, drag-to-trash to delete, **empty**) | ❌ Missing | No delete-by-drag, no Trash item. |
| **Recent applications / recent documents** dock | ❌ Missing | Auto-populating "recents." |
| **Spring-loaded folder _items_** (hierarchical pop-out) | ❌ Partial | Only whole-folder *tabs*; a folder *item* just opens in Finder. |
| **Process dock** (running apps / switcher) | ❌ By design | Explicit non-goal (PLAN §1). |
| **Clippings / clipboard store** | ❌ Post-v1 | Noted as a future extra. |
| **Multiple named layouts / sets** | ❌ Missing | DragThing had switchable layouts. |
| **Separators / spacers / labels** within a dock | ❌ Missing | Only freeform grid gaps. |
| Customizable icon size, name display, label position | ✅ Mostly | Global, not per-item. |
| Per-dock / per-item **hot keys** | ✅ Per-tab | Carbon, no Accessibility. |
| Auto-updating aliases (survive move/rename) | ✅ Bookmarks | |
| **Auto-hide / reveal-on-edge-hover** docks | ❌ Post-v1 | PLAN §13 candidate. |
| Launch at login | ✅ | `SMAppService`. |
| Sound effects, AppleScript dictionary | ❌ Non-goals | Intentionally dropped. |
| Drag a dock anywhere (not just edges) | ❌ By design | Edge-anchored only. |
| Running-app indicator / badges | ❌ Missing | No "app is running" dot. |

The high-value parity gaps are **Disks & Trash**, **Recent apps/documents**, **spring-loaded
folder items**, and **multiple layouts** — each captures something DragThing users relied on.

---

## 3. Missing Features & Ideas

Beyond DragThing parity, ideas that would make MacDring more versatile / complete:

1. **Search / type-to-find in an open drawer.** A filter field (and type-select) for tabs with
   many items. Pairs with #2.
2. **Keyboard navigation in a drawer** (arrows + Return, type-select) — PLAN §13 candidate.
3. **Reorder tabs in the Settings → Tabs list** (drag to reorder; `replaceTabs` already exists,
   the UI just doesn't expose reordering).
4. **Tab context-menu quick actions**: "Move to edge ▸", "Move to display ▸", "Duplicate",
   "Lock" — today the pill menu only has Configure / Remove (`TabStripView.swift:37-41`).
5. **Quick Look** an item with the space bar.
6. **Per-item launch options**: open-with override, command-line args / open in Terminal,
   "open at login," "reveal vs open."
7. **Layout import / export** (the document is already clean JSON) and optional **iCloud sync**
   — PLAN §13.
8. **Auto-hide / reveal-on-edge-hover** tabs so they never obstruct fullscreen content.
9. **Onboarding / welcome** on first run, and a non-silent **backup-restore** UI for a corrupt
   document (ties to **B1/B14**).
10. **Accessibility**: VoiceOver labels on pills and items; Dynamic-Type-aware drawer text.
11. **Localization** scaffolding (strings are currently inline literals).
12. **Folder-tab niceties**: sort options, show-hidden toggle, live refresh via `FSEvents`
    (today a folder tab only re-lists on open/refresh, `FolderLister`), file-count badge.
13. **Drop a text selection / image as a clipping** (the clippings store, modernized).
14. **Running-app indicator** dot on application items (cheap via `NSWorkspace.runningApplications`).
15. **"Add current Finder selection / frontmost app"** menu-bar command for fast capture.

---

## 4. Prioritized Backlog

Ordered by priority. Each row is intended to land as **its own PR**. Items are sequenced so the
cheap, high-confidence correctness fixes (pure logic, unit-testable) go first.

| # | Pri | Item | Type | Refs |
|---|-----|------|------|------|
| 1 | P0 | Resilient document decode — never lose all tabs to one bad record | bug | B1 |
| 2 | P0 | De-overlap tabs sharing an edge (use `order`) | bug | B2 |
| 3 | P1 | Guard drawer-open against a parked/stale screen | bug | B3 |
| 4 | P1 | Accept URL / link drops on tabs & drawers | feature/parity | B4 |
| 5 | P1 | Item **Rename** + **Change Icon…** (wire `customIconBookmark`) | feature | B5 |
| 6 | P2 | Debounce / scope the appearance-preference reconcile | perf | B6 |
| 7 | P2 | Don't reset notes text on unrelated reconcile | bug | B7 |
| 8 | P2 | Fix frame-defender vs. overlapping-animation race | bug | B8 |
| 9 | P2 | Reorder tabs in Settings; "Move to edge/display" pill submenu | feature | §3.3/3.4 |
| 10 | P2 | List-layout drop feedback + into/open-with ring | bug | B10 |
| 11 | P1 | **Disks & Trash** special items (eject / empty / drag-to-trash) | parity | §2 |
| 12 | P1 | Search / type-to-find + keyboard nav in a drawer | feature | §3.1/3.2 |
| 13 | P2 | De-dupe on add (skip an item already in the tab) | bug | B11 |
| 14 | P2 | List drawer width from icon size + labels | bug | B12 |
| 15 | P3 | Esc/click monitor ignores app's own windows | bug | B9 |
| 16 | P3 | First-run seeding fallback + non-silent .bak restore | bug | B13/B14 |
| 17 | P2 | **Recent applications / documents** tab kind | parity | §2 |
| 18 | P3 | Spring-loaded folder *items* (hierarchical pop-out) | parity | §2 |
| 19 | P3 | Multiple named layouts / sets | parity | §2 |
| 20 | P3 | Auto-hide / reveal-on-edge-hover tabs | feature | §3.8 |
| 21 | P3 | Import/export + iCloud sync; Quick Look; a11y; localization | feature | §3 |

**Execution note:** items 1–8 are self-contained and low-risk and are tackled first as
individual PRs. Larger parity features (11, 12, 17–21) are scoped here and follow once the
correctness backlog is clear. Because this environment can't run the macOS build, each PR keeps
its blast radius small and adds unit tests for any pure-logic change.

---

## 5. Status (PRs raised)

Each item below shipped as its own PR against `main`. They were authored in a Linux
container with **no macOS toolchain**, so none were compiled here — every PR notes this
and asks CI (Xcode) to confirm the build/tests. Several touch `TabController.swift` /
`handleFileDrop` and will need ordinary merge-conflict resolution if merged together.

| Backlog | Item | PR |
|---|---|---|
| — | This document | #1 |
| 1 | Resilient document decode (P0 data-loss) | #2 |
| 2 | De-overlap tabs sharing an edge (P0) | #3 |
| 3 | Guard drawer-open against a parked screen (P1) | #4 |
| 4 | Accept URL / link drops (P1) | #5 |
| 5 | Item Rename + Change Icon (P1) | #6 |
| 6 | Debounce appearance-preference reconcile (P2) | #7 |
| 7 | Don't reset notes on unrelated reconcile (P2) | #8 |
| 8 | Frame-defender vs. overlapping-animation race (P2) | #9 |
| 13 | De-duplicate items on add (P2) | #11 |
| 15 | Esc no longer swallowed from app's own windows (P3) | #12 |
| 10 | List-layout drop ring (P3) | #13 |
| 9 | Reorder tabs in Settings + "Move to Edge" submenu (P2) | #14 |
| 14 | List drawer width from icon size (P3) | #10 |
| 11 | **Trash item** — open Trash + drop-to-delete (P1 parity) | #15 |
| 21a | Layout import / export (JSON backup + migration) | #16 |

### Deliberately deferred (need design + on-device testing, not done blind)

- **B13** first-run seeding fallback / non-silent `.bak` restore — low value; the seeding
  fallback risks the "sacred" restore logic, so left alone.
- **B14** `LauncherDocument.version` migration switch — no schema change yet; revisit before one.
- **#12** drawer search / type-to-find + keyboard navigation — interacts with the grid/slot
  model and key focus in a borderless panel; needs care.
- **#17** Recent applications / documents tab kind — new data source + kind.
- **#18** spring-loaded folder *items* (hierarchical pop-out).
- **#19** multiple named layouts / sets (import/export in #16 covers the backup half).
- **#20** auto-hide / reveal-on-edge-hover tabs (Dock-style windowing).
- **Disks** (eject-able volumes) — the Trash half of the parity gap shipped in #15.
- **#21 remainder** — iCloud sync, Quick Look, accessibility, localization.

These are the right next tranche once the PRs above are merged and green on macOS CI.
