# awesome.md — Open Items from the Deep Review

The original full-codebase review, reconciled against `main` on 2026-06-28.
Findings that were fixed (companion PRs #42–#49 plus later commits) or implemented
during this reconciliation pass have been cleared out. What remains below is
**open**, each annotated with why it isn't being implemented yet.

**Legend:** 🔴 high · 🟡 medium · 🔵 low.
**Disposition:** _device_ = needs on-device GUI/animation/filesystem verification ·
_design_ = needs a product/UX decision · _large_ = multi-file refactor / feature project.

## Resolved since the review

Fixed on `main`: bugs **B1, B2, B3, B6, B7, B8, B9, B12, B13, B16, B18, B19,
B21–B27, B29a, B29c, B30** (companion PRs #42–#49 and follow-up commits), the
dead drop-highlight (B9), and the wrong `TrashInspector` test assertion.

Implemented during this pass:
- **B14** — cache failed hotkey specs so a reconcile no longer re-attempts (and
  re-logs) a spec macOS already rejected; the cache clears when the spec changes.
- **B15** — `endDrag`'s failure path now calls `reconcile()` instead of leaving the
  pill stranded at its preview position until an unrelated reconcile.
- **B17c** — middle-clicks now dismiss the drawer (`.otherMouseDown` added to the
  global click monitor).
- **B29b** — `GitHubReleaseClient.fetch` no longer force-unwraps its URL; it throws
  `ClientError.badURL`, honoring the repo's no-force-unwrap rule.
- **`applicationSupportsSecureRestorableState`** is now implemented (returns `true`),
  silencing the macOS 14+ warning.

---

## 1. Open bugs

- **B4 🟡 Stale bookmarks are never refreshed.** `BookmarkResolver.resolve` reports
  `isStale`, but no caller consumes it and no store sweep re-mints stale bookmarks.
  _device_ — re-minting and confirming items still resolve across real
  moves/renames/volume changes needs on-device filesystem verification.

- **B5 🔴 Stale Settings draft can wipe concurrent changes.** `TabEditor` holds a
  whole-`Tab` `@State` draft re-seeded only on selection change and commits the
  entire draft on every keystroke, so a concurrent pill drop / notes edit is
  reverted. (Same root as GPT audit #9.) _design_ — needs a field-wise merge or
  external-change re-seed; the binding model is too UX-sensitive to patch blind.

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

## 2. Open general issues

- **Main-thread blocking I/O** (the codebase's one systemic weakness). `ItemView`
  icon resolution is now off the render path, but these remain: `TrashInspector`
  stats every mounted volume while building a context menu; `FileMover.emptyTrash`
  (synchronous `NSAppleScript`); `DiskEjector` (synchronous unmount);
  `FolderLister.contents` enumerates + stats + sorts the whole directory before the
  300-cap; `TabStore.addItem`'s dedup resolves every existing bookmark per drop;
  `BookmarkResolver.resolve` runs without `.withoutUI`/`.withoutMounting`. _device_
  for most (validating no UI/perf/permission regression needs a real
  multi-volume / offline-server Mac); _design_ for `FolderLister` (a cap-before-sort
  needs a top-N strategy that preserves "folders first + chosen sort").

- **Silent Launch/ failures.** `FileMover.move/trash`, `DiskEjector.eject`, and
  `ItemLauncher.open(_:withApp:)` return values every caller ignores, so a failed
  eject is indistinguishable from success. _design_ — surfacing failures needs a
  chosen UI (alert/toast).

- **No mutation batching.** A 10-file drop = 10 `addItem` calls = 10 reconciles;
  `TabEditor` commits a full `updateTab` per keystroke. _design_ — a coalescing
  primitive on `TabStore` touches the reconcile contract.

- **⌘W doesn't close Settings** — no File→Close in the main menu. _design_ — the menu
  item is easy, but adding a File menu to an `LSUIElement` agent is a minor product
  choice. (The related `applicationSupportsSecureRestorableState` warning is fixed.)

## 3. Missing features (backlog — each a project)

Feature work, not patches; each needs design + on-device iteration:
drag items _out_ of an items tab · relink for broken items (see GPT audit #17) ·
full-grid keyboard navigation · hover-open dwell delay · Quick Look + multi-select ·
bare-function-key hotkeys · "Move to Display" · live-update for Fresh/system-Recents
while open · per-tab Fresh scopes · undo for destructive actions.

Intentionally **not** planned: accessibility/localization (English-only target) and
in-place updates (install stays the user's responsibility).

## 4. Ideas (delight backlog)

Future-pass idea list — none are bugs; each needs design + visual iteration:
"just landed" live Fresh tab · reconnect wave · snap guides + haptics during tab
drag · undo toast for file moves · trash poof + live count · self-healing bookmarks
(B4) · read-only "time traveler" banner when `version > currentVersion` · frecency
Recents · checklist notes · live Appearance preview · drag-over "peek" · shift-drag
to duplicate a tab · fuzzy/initials search + ⌘1–9 · running-app powers (Quit/Hide) ·
Eject All on the Disks tab · display picker as a map · versioned export envelope.
