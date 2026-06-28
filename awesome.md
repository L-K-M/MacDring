# awesome.md — Open Items Backlog

## 1. Open bugs

- **B5 / G9 🔴 Stale Settings draft can wipe concurrent changes.** `TabEditor` holds a
  whole-`Tab` `@State` draft re-seeded only on selection change and commits the
  entire draft on every keystroke, so a concurrent pill drop / notes edit / icon
  customization is reverted. _design_ — needs field-wise store mutations, or a
  merge/re-seed of the draft against the latest store value before committing; the
  binding model is too UX-sensitive to patch blind.

- **B10 🟡 Drag badge says "copy", folder-target drops move (incl. cross-volume).**
  _design_ — product decision: `.move` badge vs. copy-across-volumes vs.
  ⌥-modifier; the badge would also have to vary by hovered slot/tab kind.

- **B11 🟡 Direct `setFrame` during an in-flight pill animation** can finish at a
  stale target, leaving the riding pill misaligned until the next reconcile.
  _device_ — the cancel/re-assert fix and the misalignment it addresses need
  on-device animation observation.

- **B17a 🔵 Classic-style drag preview uses the modern sizing formula** (`dragFrame`
  has no `.classic` branch, unlike `place`), causing transient clipping. _device_ —
  needs visual verification of the classic pill preview mid-drag.

- **B17b 🔵 Links dropped on a folder _item_ are silently discarded** (the folder
  branch of `handleFileDrop` filters to file URLs; the app branch keeps links).
  _design_ — undecided what a link dropped on a folder should do (ignore vs. add
  elsewhere vs. write a `.webloc`).

- **B20 🟡 The hotkey recorder's key monitor can outlive its UI.** Teardown relies
  solely on `onDisappear`; a surviving monitor would swallow every `keyDown`.
  _device_ — confirming the leak, and a window-resign/timeout backstop, needs
  on-device SwiftUI lifecycle/focus behavior.

- **B28 🔵 Trash can read "full" when Finder shows it empty** — `ATTR_DIR_ENTRYCOUNT`
  counts `.DS_Store`. _device_ — a metadata-only count can't see entry names to
  exclude `.DS_Store`, so the fix needs a different approach validated on a real
  volume (and must not reintroduce a Trash-permission prompt).

- **G13 🟡 Click-outside dismissal misses clicks inside MacDring's own windows.** The
  global mouse monitor doesn't report same-app events, so clicking Settings or the
  New Tab dialog while a drawer is open may not close it. _device_ — a local
  mouse-down monitor is the fix, but it's interaction-sensitive (must not fire on
  clicks inside the drawer/tab panels) and needs on-device verification of the guard.

## 2. Open general & performance issues

- **Main-thread blocking I/O** (the codebase's one systemic weakness). `ItemView`
  icon resolution is now off the render path (G11), but these remain:
  - `TrashInspector` stats every mounted volume while building a context menu.
  - `FileMover.emptyTrash` (synchronous `NSAppleScript`).
  - `DiskEjector` (synchronous unmount).
  - `FolderLister.contents` (**G8**) enumerates + stats + sorts the whole directory
    before the 300-cap, applied synchronously on open/refresh.
  - `TabStore.addItem`'s dedup resolves every existing bookmark per drop.
  - `BookmarkResolver.resolve` runs without `.withoutUI`/`.withoutMounting`.
  - **G10** — Settings item rows call `ItemView.resolveIcon` synchronously inside the
    `ForEach` body, so large/networked/broken icons jank Settings scrolling.

  _device_ for most (validating no UI/perf/permission regression needs a real
  multi-volume / offline-server Mac); _design_ for `FolderLister` (a cap-before-sort
  needs a top-N strategy preserving "folders first + chosen sort") and for **G10**
  (an async/cached Settings row mirrors the drawer's `ItemView`, but the Settings
  layout differs — the visual result wants on-device verification).

- **G19 🔵 Fresh tabs scan the filesystem twice on open** — the drawer seeds via
  `FreshScanner`, then `updateSpotlightWatch` scans again as the Spotlight-merge base,
  in two different classes. _design_ — de-duping crosses the drawer/controller open
  sequence; both scans are bounded and cheap, so the value doesn't justify a blind
  cross-class change whose runtime behavior can't be verified here.

- **Silent Launch/ failures.** `FileMover.move/trash`, `DiskEjector.eject`, and
  `ItemLauncher.open(_:withApp:)` return values every caller ignores, so a failed
  eject is indistinguishable from success. _design_ — surfacing failures needs a
  chosen UI (alert/toast).

- **No mutation batching.** A 10-file drop = 10 `addItem` calls = 10 reconciles;
  `TabEditor` commits a full `updateTab` per keystroke. _design_ — a coalescing
  primitive on `TabStore` touches the reconcile contract.

## 3. Open UX & behavior (needs a product decision)

- **⌘W doesn't close Settings** — no File→Close in the main menu. _design_ — the menu
  item is easy, but adding a File menu to an `LSUIElement` agent is a minor product
  choice. (The related `applicationSupportsSecureRestorableState` warning is fixed.)

- **G15 List layout lacks empty-slot drop targets** (grid reports every slot; the list
  reports only existing rows, so blank-space drops fall back to generic append).
  _design_ — where insertion targets sit (between-row vs. a trailing append zone) is
  a layout decision.

- **G16 Hotkey registration failures aren't surfaced in Settings** — the recorder
  shows the spec as configured even when macOS rejected it. _design_ — threading
  registration status back to the UI and choosing its presentation is a product
  decision. (The retry/log-spam half is fixed via B14.)

- **G18 Fresh/Recents have no loading or timeout state** — a live tab can look empty
  while Spotlight is still gathering. _design_ — distinguishing "loading" from
  "empty," plus a timeout policy and its UI, spans model and view.

- **G20 Cloud tabs don't refresh live** when providers appear/disappear (no watcher on
  `~/Library/CloudStorage`). _design / large_ — a new `DispatchSource` watch wired
  into open/close/refresh, mirroring the folder watcher.

- **G21 Settings "+" only creates a generic Items tab** while the New Tab dialog
  supports every kind. _design_ — route "+" into that dialog or attach a kind menu.

- **G22 New Tab dialog uses a fixed compact size** (could clip with localization /
  larger Dynamic Type). Relaxing the frame is small, but whether the looser layout
  reads well across locales wants on-device visual verification.

## 4. Missing features (backlog — each a project)

Feature work, not patches; each needs design + on-device iteration:

- **Drag items _out_ of an items tab** — only live listings get `.onDrag` today.
- **Relink for broken items (G17)** — broken items dim but the only remedy is
  delete + re-add. Needs a `Relink…` context action wiring an `NSOpenPanel` through
  DrawerModel→TabController to re-mint the bookmark/URL.
- **Full-grid keyboard navigation** — type-to-find ships; arrowing the unfiltered grid doesn't.
- **Hover-open dwell delay** — hover tabs open instantly; brushing an edge pops drawers.
- **Quick Look + multi-select** — natural for a file launcher.
- **Bare-function-key hotkeys** — `hasModifier` rejects plain F12.
- **"Move to Display"** in the pill context menu (only Move to Edge today).
- **Live-update Fresh / system-Recents while open** — the Spotlight query is stopped
  after the first gather, so new arrivals don't appear (folder tabs do live-update).
- **Per-tab Fresh scopes** — scopes are hardcoded under `$HOME` today.
- **Undo for destructive actions** — tab deletion, item removal, file moves.

Intentionally **not** planned: accessibility/localization (English-only target) and
in-place updates (install stays the user's responsibility).

## 5. Ideas (delight backlog)

### Implemented (now on main)

This batch of ideas shipped (plus the self-healing-bookmarks sweep, ex-B4).
**Caveat:** written against the codebase but not compiled here — run `xcodebuild`
on a Mac before release, and the interaction/visual ones especially want hands-on
checking (drag haptics, drag-over peek, the trash poof, the Fresh sparkle, the
Appearance preview, and favicon fetching).

- **Snap guides + haptics during tab drag** — `EdgeLayout.snappedPosition` magnetizes
  to 0/¼/½/¾/1 and neighbors; an `.alignment` haptic ticks on each new lock.
- **Undo toast for file moves** — "Moved N items to X — Undo" in the drawer header,
  reversible via `FileMover.undo`.
- **Trash delight** — red count badge + classic poof on drop-to-trash + a
  `DispatchSource` Trash watch that refreshes the icon when Finder empties it.
- **Self-healing bookmarks** — `TabStore.remintStaleBookmarks` sweeps stale bookmarks
  at launch (off-main resolve, main-thread write-back).
- **Checklist notes** — `MarkdownText` renders `- [ ]` / `- [x]` as tappable
  checkboxes that rewrite the note source.
- **Live preview in Appearance** — a mini edge+pill+drawer mock re-rendering as the
  thickness / radius / translucency / style / color controls change.
- **Drag-over "peek"** — a file drag nearing a concealed tab's edge reveals it from a
  wider peek zone (gated on an in-flight file drag).
- **Eject All** — a Disks-tab header button ejects every volume with a per-item spinner.
- **URL favicons** — `FaviconCache` swaps the globe for a cached `favicon.ico`.
- **Fresh sparkle** — items that landed within 5 min get a one-shot sparkle.
- **"Just landed" Fresh pill dot** — the closed Fresh tab pill shows a dot when its
  newest item arrived within ~20 min (a light 60 s re-scan keeps it current).
- **Folder truncation badge** — "300+" when `FolderLister.listing` reports a capped directory.
- **Recents time buckets** — the Recents and Fresh lists group into Today / Yesterday / This Week / Older.
- **Cloud-provider personality** — `CloudLister` brands iCloud / Dropbox / Google Drive /
  OneDrive / Box with per-provider colors and glyphs.

### Still on the backlog

Future-pass ideas — none are bugs; each needs design + visual iteration.

- **"Just landed" live Fresh tab** — keep the Spotlight query live while the drawer is
  open so arrivals stream in without reopening (the arrival sparkle and the closed-pill
  dot shipped; only the live-while-open query remains).
- **Reconnect "wave"** — stagger parked pills' slide-in by ~40 ms when a display returns.
- **Read-only "time traveler" banner** — when `document.version > currentVersion`, load best-effort and explain why saving is disabled.
- **Frecency Recents** — add a launch counter and a "Frequent" sort.
- **Shift-drag to duplicate a tab** onto another edge/display.
- **Search upgrades** — initials/fuzzy matching ("xc" → Xcode) with matched-range bolding, ⌘1–9 to launch the Nth result, ⇧Return to reveal.
- **Running-app powers** — Quit/Hide in a running app's context menu; ⌥-click to hide others.
- **Display picker as a map** — a drag-on-a-diagram widget mirroring System Settings → Displays.
- **Versioned export envelope** — wrap `exportData()` so import errors can say "made by a newer version".
- **Spring-load countdown glow** — while a dragged item hovers a tab with the spring-open timer pending, animate a charging outline around the tab.
- **DragThing nostalgia mode** — in classic tab style, a tiny bevel/highlight animation when a drawer opens.
- **Search aliases** — let short terms like `dl`, `icloud`, `trash`, and provider names match common items.
- **Dock-edge warning** — when a tab is placed on the Dock edge, hint that `visibleFrame` may shift.
- **Peek mode** — modifier-hover a Notes/Fresh/Recents tab to preview the drawer without keying search or editing.
