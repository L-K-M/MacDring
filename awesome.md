# awesome.md — A Deep Review of MacDring

A full-codebase review (all ~10k lines of Swift, plus CI, docs, and tests): bugs,
general issues, missing features, and ideas. Every finding below was verified
against the source at review time; each carries a `file:line`, a severity, and —
where a fix is in flight — the PR that carries it.

**Legend:** 🔴 high · 🟡 medium · 🔵 low. "Fix: PR …" entries are implemented in
companion PRs opened alongside this document; everything else is documented here
for a future pass.

---

## 1. Bugs

### Data integrity & persistence

- **B1 🔴 Unknown enum values silently destroy tabs — permanently.**
  `Tab.swift:102/106/108`, `TabBehavior.swift:52`, `DrawerItem.swift:56`.
  `decodeIfPresent(TabKind.self, …) ?? .items` only defaults when the key is
  *missing*; an unknown raw value (e.g. a `"kind": "shelf"` written by a newer
  MacDring) **throws**, the `FailableTab` wrapper swallows the throw and drops the
  whole tab, and the next debounced save rewrites `launcher.json` without it. One
  more save and the `.bak` generation is gone too. Tab kinds have been added in
  nearly every release (`disks`, `network`, `cloud`, `recents`, `fresh`…), so
  downgrade/two-Macs scenarios hit this for real. Same pattern for `FolderSort`,
  `RecentsSource`, `TabConcealment` — and `ItemKind`, where **one** unknown item
  takes its entire tab down with it (`Tab.swift:96` decodes `[DrawerItem]`
  all-or-nothing). *Fix: PR "Lenient document decoding".*

- **B2 🔴 Backup rotation can clobber the only good copy.** `TabStore.swift:294-298`.
  `saveNow()` copies the current primary over `.bak` *before* knowing the new
  write succeeds. After recovering from `.bak` (primary corrupt), the very first
  save copies the **corrupt** primary over the good backup; if the subsequent
  write then fails (disk full — exactly when writes fail), both copies are bad
  and the recovered document exists only in memory. Relatedly, a document that
  exists but fails to decode is indistinguishable from "first run"
  (`TabStore.swift:42-54`): the app seeds a starter tab and overwrites the user's
  file 0.3 s later. A hand-recoverable JSON (truncated by a crash) is destroyed
  before the user notices. *Fix: PR "TabStore backup hardening" — rotate `.bak`
  only after a successful write, quarantine undecodable documents as
  `launcher.corrupt-<date>.json`.*

- **B3 🟡 `LauncherDocument.version` is decoded but never checked.**
  `LauncherDocument.swift:7-19`. "The `version` field drives forward migrations"
  is aspirational — nothing branches on it, and a document written by a newer
  schema gets lossily rewritten by an older build. *Fix (downgrade guard only):
  PR "TabStore backup hardening" — refuse to save when
  `document.version > currentVersion`.*

- **B4 🟡 Stale bookmarks are never refreshed.** `BookmarkResolver.swift:24-32`.
  The doc comment promises "the caller should re-create the bookmark … when
  stale", but `isStale` is consumed nowhere. Stale bookmarks are exactly the ones
  that eventually stop resolving; when they do, the `url` fallback points at the
  old path and the item breaks — defeating the bookmark's whole purpose.
  Recommended: a store sweep that re-mints stale bookmarks and refreshes
  `item.url`. (Not fixed here: wants on-device verification.)

- **B5 🔴 Stale Settings draft can wipe concurrent changes.** `TabsView.swift:152,326`.
  `TabEditor` holds a full `Tab` snapshot re-seeded only on selection change, and
  commits the *entire* draft on every keystroke (`.onChange(of: draft) →
  store.updateTab(draft)`). Drop a file onto the tab's pill (or edit its notes in
  the drawer) while its editor is open in Settings, then type one character in
  the Name field — the dropped item / notes edit is silently reverted. Needs a
  field-wise merge or external-change re-seeding; too design-sensitive to patch
  blind, so documented rather than fixed.

### Interaction

- **B6 🔴 Only the most recently registered per-tab hotkey works.**
  `CarbonHotkey.swift:34-53`. Each hotkey installs its own Carbon event handler
  on the application target, and the handler returns `noErr` unconditionally —
  even for hotkey IDs it doesn't own and even in its `guard` bail-out. Carbon
  stops the handler chain on `noErr`, so with ≥2 hotkeys the newest handler
  swallows every press and the others never fire. The handler also ignores
  `GetEventParameter`'s return status. *Fix: PR "Carbon hotkey chain".*

- **B7 🔴 Dropping a file into its own folder silently renames it ("name 2").**
  `FileMover.swift:12-14`. `uniqueDestination` only ever returns a path that
  doesn't exist; when the dropped file already lives in the target directory the
  candidate path *is the source* (which exists), so it advances to "name 2" and
  the self-move guard on line 14 can never fire — it's dead code. Dragging an
  item a few pixels inside its own folder drawer and releasing routes through
  exactly this path and renames the user's file. *Fix: PR "FileMover self-drop".*

- **B8 🔴 Hovering the riding pill of an open hover-tab replays the entire drawer
  open.** `TabController.swift:291-295` → `:214-244`. `handleHover(inside: true)`
  calls `openDrawer(id)` with no `openTabID == id` guard (compare
  `handleDragHover`, which has one). Once a hover tab's drawer is open, the pill
  rides the drawer's inner face; every cursor crossing from drawer content back
  onto the pill re-runs `openDrawer` — wiping an active type-to-find filter
  (`clearSearch()`), flipping a notes tab out of edit mode, re-listing folder
  contents synchronously, and replaying the open animation from `alpha 0`.
  *Fix: PR "Interaction fixes".*

- **B9 🟡 The drawer's drop-highlight is dead code.** `DrawerModel.swift:16`,
  consumed at `DrawerView.swift:62-65`. `DrawerView` brightens the drawer outline
  when `model.isDropTargeted` — but nothing ever sets it
  (`DrawerHostingView.draggingEntered/Exited` only update `fileDropSlot`). When a
  file drag hovers the drawer background/header there is zero feedback that
  releasing will add the file. *Fix: PR "Interaction fixes".*

- **B10 🟡 Drag badge says "copy", operation is a move — including cross-volume.**
  `DrawerWindowController.swift:58-62` + `FileMover.swift`. `updateDrag` returns
  `.copy` (green ⊕) for every accepted drag, but folder-target drops **move**;
  `FileManager.moveItem` across volumes is copy+delete, so dragging from a USB
  stick onto a folder tab removes it from the stick — the opposite of the badge
  and of Finder's convention. Needs a product decision (`.move` badge vs.
  copy-across-volumes vs. ⌥-modifier support), so documented rather than fixed.

- **B11 🟡 Direct `setFrame` while a pill animation is in flight.**
  `TabWindowController.swift:319-335` vs `:205-209`. An `animator()` frame
  animation isn't cancelled by a direct `setFrame`; during drag-while-open and
  Spotlight-resize (`TabController.swift:845-851`) the in-flight animation can
  finish at a stale target, leaving the riding pill misaligned until the next
  reconcile. Needs on-device verification of the fix (cancel/re-assert).

- **B12 🔵 `handleDragHover(false)` can cancel *another* tab's pending
  spring-open.** `TabController.swift:528-535`. `pendingSpringOpen` is a single
  shared work item, cancelled without checking which tab scheduled it; an
  enter-B/exit-A interleaving kills B's spring-open.

- **B13 🔵 Local key monitor breaks IME composition in type-to-find.**
  `TabController.swift:912-931`. Return/↑/↓ are consumed while searching even
  when a CJK input source has marked text, so composition can't be confirmed.
  Guard on `firstResponder.hasMarkedText()`.

- **B14 🔵 Failed hotkey registration retries (and logs) on every reconcile.**
  `TabController.swift:539-554`. Nothing caches a failed spec, so every store
  mutation re-creates the `CarbonHotkey`, re-fails, and re-logs.

- **B15 🔵 `endDrag` with no resolvable display UUID strands the pill** at its
  preview position until an unrelated reconcile (`TabController.swift:430-437`);
  the failure path should call `reconcile()`.

- **B16 🔵 Drag-reposition among stacked tabs can silently "not stick"** —
  `deOverlapStackedTabs` sorts by `(order, position)` with `order` dominant, but
  a drag updates only `position`, so a tab dragged past its neighbor can snap
  back behind it on release.

- **B17 🔵 Classic-style drag preview uses the modern sizing formula**
  (`TabWindowController.swift:340-350` vs `:183-197`) — transient clipping during
  drags. **Links dropped on folder items are silently discarded**
  (`TabController.swift:480,494-498`). **Middle-clicks don't dismiss the drawer**
  (monitor matches left/right only, `TabController.swift:885`).

### Settings, lifecycle & app

- **B18 🟡 A miniaturized Settings window defeats the activation-policy guard and
  can become unrestorable.** `ActivationPolicy.swift:16`,
  `SettingsWindowController.swift:36,51-56`. The guard counts
  `isVisible && canBecomeMain`, but `isVisible` is false for miniaturized
  windows — so closing the New Tab dialog while Settings is minimized drops the
  app to `.accessory`, vanishing the Dock thumbnail; re-showing never
  `deminiaturize`s. *Fix: PR "Settings & lifecycle fixes".*

- **B19 🟡 Test runs rewrite the developer's real `launcher.json`.**
  `AppDelegate.swift:35-37`. `applicationDidFinishLaunching` is test-guarded but
  `applicationWillTerminate` is not — at test-host exit it instantiates the lazy
  `TabController` and calls `saveNow()` against the real store, re-encoding the
  live document and clobbering its `.bak`. *Fix: PR "Settings & lifecycle fixes".*

- **B20 🟡 The hotkey recorder's key monitor can outlive its UI.**
  `HotkeyRecorderView.swift:23,38-49`. Teardown relies solely on `onDisappear`,
  which isn't guaranteed on window-close for a cached, never-released window;
  a surviving monitor consumes every `keyDown` in the app (`return nil`).
  Documented — wants a `windowWillClose` / resign-key backstop verified on-device.

- **B21 🔵 `SettingsRouter.tabToSelect` is never cleared** (`TabsView.swift:36-42`)
  — after "Configure Tab…", switching panes and returning snaps the selection
  back to the routed tab. *Fix: PR "Settings & lifecycle fixes".*

- **B22 🔵 Duplicate `"headphones"` entry breaks `ForEach(id: \.self)`
  uniqueness** in the symbol picker (`SymbolPickerView.swift:89,127`).
  *Fix: PR "Settings & lifecycle fixes".*

- **B23 🔵 Stepper ranges disagree with `Preferences` clamps**
  (`GeneralView.swift:61-62` allows 1…10/1…12; `Preferences.swift:170-171` clamps
  to 1…12/1…16). *Fix: PR "Settings & lifecycle fixes".*

- **B24 🔵 `NSColor(hex:)` accepts `+`-prefixed garbage** (`ColorHex.swift:12-19`)
  — `UInt64("+84FF0", radix: 16)` parses (the sign counts as a "digit" for the
  length check), yielding a wrong color instead of `nil` and defeating
  `Preferences.validColor`. *Fix: PR "Settings & lifecycle fixes".*

- **B25 🔵 `NSScreen.main` is "screen with keyboard focus", not "primary
  display"** (`TabController.swift:122,268`, `DisplayRegistry.swift:44-47`) — and
  MacDring's drawer panel `makeKey()`s, so move-to-main and first-run seeding can
  pick a surprising display. `NSScreen.screens.first` is the deterministic choice.

### Stores, listers & updates

- **B26 🟡 SemVer pre-release comparison is lexical, not semver.**
  `SemanticVersion.swift:57`. `"beta.10" < "beta.9"` lexically, so a user on
  `1.4.0-beta.9` is never offered `beta.10`, and `latestRelease(includePrereleases:)`
  can pick the wrong "newest". *Fix: PR "Updates fixes" — SemVer §11
  identifier-by-identifier comparison.*

- **B27 🔵 The daily update check can systematically skip a day.**
  `UpdateChecker.swift:94-107`. `lastCheckDate` is stamped at request
  *completion*, so a punctual +24 h timer finds `elapsed < interval` and defers
  to +48 h. *Fix: PR "Updates fixes" — throttle against `interval * 0.9`.*

- **B28 🔵 Trash can read "full" when Finder shows it empty** —
  `ATTR_DIR_ENTRYCOUNT` counts `.DS_Store` (`TrashInspector.swift:50-79`).
  Needs an on-device-verified fallback for small counts.

- **B29 🔵 `RecentsStore.save` failure erases history** —
  `defaults.set(try? encode(…))` stores `nil`, removing the key
  (`RecentsStore.swift:55`). **`GitHubReleaseClient.fetch` force-unwraps its
  URL** (`GitHubReleaseClient.swift:42`), violating the repo's own no-force-unwrap
  rule. **`checkNow()` silently no-ops while a check is in flight**
  (`UpdateChecker.swift:124-126`).

### CI / release

- **B30 🟡 A `v*` tag on any commit publishes a release without tests.**
  `.github/workflows/release.yml:3-5`. No test job, no on-main check — and the
  in-app `UpdateChecker` then offers that build to every user. The re-sign step
  also uses deprecated `--deep` and drops the declared entitlements + hardened
  runtime (`release.yml:45,54` vs `project.pbxproj`), a trap for the future
  Developer-ID path (ANALYSIS.md C1 tracks the signing half).
  *Fix (tests + `--deep`): PR "Release workflow hardening".*

---

## 2. General issues

- **Main-thread blocking I/O** is the codebase's one systemic weakness:
  `ItemView`'s icon resolution, `TrashInspector.trashIsEmpty()` (stats
  `.Trashes` on *every mounted volume* while building a context menu),
  `FileMover.emptyTrash()` (synchronous `NSAppleScript`), `DiskEjector`
  (synchronous unmount), `FolderLister.contents` (enumerates and sorts the whole
  directory before applying the 300-item cap), `TabStore.addItem`'s dedup scan
  (resolves every existing bookmark per drop), and `BookmarkResolver`'s
  resolution without `.withoutUI`/`.withoutMounting` (can block on — or attempt
  to mount — an offline server). Each deserves a background hop.
- **Silent failures throughout Launch/**: `FileMover.move/trash`,
  `DiskEjector.eject`, and `ItemLauncher.open(_:withApp:)` return Bools every
  caller ignores. A failed eject (file in use) is indistinguishable from success.
- **No mutation batching**: a 10-file drop = 10 `store.addItem` calls = 10+ full
  reconciles (each re-measuring every pill); a `performBatch {}` that coalesces
  `onChange` would fix the class. Similarly, `TabEditor` commits a full
  `updateTab` per keystroke.
- **Unconditional `@Published` writes** (`TabWindowController.update/previewSnap`)
  fire `objectWillChange` on every reconcile/mouse-move even when nothing changed.
- **Global `.mouseMoved` monitor does per-tab work on every system-wide mouse
  move** while any concealable tab is visible; a precomputed reveal-zone union
  with an early-exit would gate it.
- **`clean-build.sh:24`** kills every `clang`/`swift-frontend` on the machine.
- **Docs drift**: ANALYSIS.md's feature table marks type-to-find, the running-app
  dot, and folder sort/hidden/live-refresh as ❌ though all three shipped, and
  duplicates its "Spring-loaded folder items" row *(fixed in this PR)*; README
  never mentions the import/export feature that exists in Settings → Tabs
  *(fixed in this PR)*; `/CICD.md` and `/.github/CICD.md` diverge; AGENTS.md
  says "assume Developer ID + notarization" while both CI docs declare signing
  intentionally off.
- **Test gaps with teeth**: nothing tests unknown enum raw values (B1), the
  `.bak` rotation-after-recovery path (B2), two-pre-release ordering (B26), or
  `FileMover` self-drops (B7) — the companion PRs add all four. Bonus:
  `TrashInspectorTests.testIsEmptyTrueForSubdirectoryOnly` asserts *false*.
- **No `applicationSupportsSecureRestorableState`** (macOS 14+ logs a warning);
  no File→Close in the main menu, so **⌘W doesn't close Settings**.

---

## 3. Missing features

What a user would expect that isn't there (README promises themselves check out
— everything advertised is implemented):

1. **Drag items *out* of an items tab** — only live listings get `.onDrag`;
   items-tab entries can't be dragged to Finder or another tab (DragThing did both).
2. **Relink for broken items** — broken items render dimmed (as promised) but
   the only remedy is delete + re-add, losing the custom icon and name.
3. **Full-grid keyboard navigation** — type-to-find ships, but arrowing the
   unfiltered slot grid doesn't (acknowledged in ANALYSIS §2).
4. **Hover-open dwell delay** — hover tabs open instantly; brushing an edge pops
   drawers accidentally. The Dock uses ~200 ms of dwell.
5. **Quick Look** (Space on a selected/hovered item) and **multi-select** —
   natural for a file launcher.
6. **Bare-function-key hotkeys** — `hasModifier` rejects plain F12 (a classic
   DragThing binding) while accepting Shift+A, which eats capital-A system-wide.
7. **"Move to Display"** in the pill context menu (only Move to Edge today).
8. **Accessibility & localization** — one `.accessibilityLabel` in the whole
   app; zero localized strings despite the project enabling string catalogs.
9. **In-place updates** — the checker only downloads to `~/Downloads`; no
   install/relaunch.
10. **Fresh/system-Recents tabs don't live-update while open** — the
    `NSMetadataQuery` is stopped after first gather; a download finishing while
    the Fresh drawer is open never appears (folder tabs *do* live-update).
11. **Per-tab Fresh scopes** — hardcoded `Downloads/Desktop/Documents` under
    `$HOME`; a relocated Downloads folder is missed. System Recents search only
    `$HOME`, so recently-used apps in `/Applications` never appear.
12. **No undo anywhere** — tab deletion (a tiny "−" button, no confirmation),
    item removal, file moves.

---

## 4. Ideas — novel, cool, delightful, quirky

- **"Just landed" live Fresh tab** 🌟 — keep the Spotlight query live while the
  Fresh drawer is open, shimmer new arrivals in, and badge the closed Fresh
  *pill* with a dot when something lands. A DragThing-flavored downloads shelf
  nobody else has.
- **Reconnect "wave"** — when a display returns and its parked tabs reappear,
  stagger each pill's slide-in by 40 ms so the user *sees* everything come home.
  All the machinery (`hiddenTabFrame` → `animate`) exists.
- **Snap guides + haptics during tab drag** — magnetize `position` to
  0/¼/½/¾/1 and to neighboring tabs, with an `NSHapticFeedbackManager`
  `.alignment` tick on snap.
- **Undo toast for file moves** — drops *move* files; keep the reverse list and
  show "Moved 3 items to Projects — Undo" in the drawer header. Turns
  B7/B10-class surprises into recoverable ones.
- **Trash delight** — a count badge via `TrashInspector.entryCount`, and the
  classic poof on drop-to-trash. Plus a `DispatchSource` watch on `~/.Trash` so
  the icon flips the instant Finder empties it.
- **Self-healing bookmarks** — a launch-time sweep that re-mints stale bookmarks
  (B4) turns the bookmark system from "decays silently" into "heals silently".
- **Read-only "time traveler" mode** — when `document.version > currentVersion`,
  load best-effort, disable saving (the companion PR does this), and show a
  one-line banner in Settings explaining why.
- **Frecency Recents** — `RecentItem` already has dates; add a launch counter
  and a "Frequent" sort. Recents that learn what you actually reopen.
- **Checklist notes** — teach `MarkdownText.classify` a `- [ ]` / `- [x]` case
  and render tappable checkboxes in the notes preview. Small, pure, testable.
- **Live preview in Appearance** — a miniature screen mock (edge + pill +
  drawer) re-rendering as you drag the thickness/radius/material sliders, which
  today are invisible until you close Settings.
- **Drag-over "peek"** — while a file drag nears a concealed tab's edge zone,
  pre-reveal the sliver to a full pill so spring-loading targets aren't 3 pt wide.
- **Shift-drag to duplicate a tab** onto another edge/display — DragThing power
  users cloned docks constantly; the store supports it in two calls.
- **Search upgrades** — initials/fuzzy matching ("xc" → Xcode) with matched-range
  bolding, ⌘1–9 to launch the Nth result, ⇧Return to reveal.
- **Running-app powers** — Quit/Hide in a running app item's context menu;
  ⌥-click to hide others (Dock parity).
- **Eject All** header button on the Disks tab, async ejects with per-item
  spinners, and "which app is holding this volume" on failure.
- **Display picker as a map** — replace the edge-position slider + display
  dropdown with a tiny drag-on-a-diagram widget mirroring System Settings →
  Displays.
- **Versioned export envelope** — wrap `exportData()` in
  `{"app":"MacDring","formatVersion":…,"document":…}` so import errors can say
  "made by a newer version" instead of "doesn't look valid".

---

## 5. Companion PRs

Opened alongside this document (each scoped to disjoint files to keep merges
clean; PR numbers filled in after creation):

| PR | Fixes | Files |
|---|---|---|
| Carbon hotkey chain | B6 | `Hotkeys/CarbonHotkey.swift` |
| FileMover self-drop | B7 | `Launch/FileMover.swift` + tests |
| Lenient document decoding | B1 | `Model/Tab.swift`, `Model/DrawerItem.swift`, new `Model/LenientDecoding.swift` + tests |
| TabStore backup hardening | B2, B3 | `Store/TabStore.swift` + tests |
| Interaction fixes | B8, B9 | `Tabs/TabController.swift`, `Drawer/DrawerWindowController.swift` |
| Settings & lifecycle fixes | B18, B19, B21–B24 | `Common/ActivationPolicy.swift`, `Settings/*`, `AppDelegate.swift`, `Model/ColorHex.swift` + tests |
| Updates fixes | B26, B27 | `Updates/SemanticVersion.swift`, `Updates/UpdateChecker.swift` + tests |
| Release workflow hardening | B30 (tests + `--deep`) | `.github/workflows/release.yml`, `.github/workflows/ci.yml` |

Everything not in that table is intentionally left as documentation: either it
needs on-device GUI verification (B5, B11, B20, B28), a product decision (B10),
or it's a feature project in its own right (§3, §4).
