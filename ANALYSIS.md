# MacDring — Code Review & Open Backlog

A living backlog for MacDring, refreshed by a full re-read of every source and test file
under `MacDring/` and `MacDringTests/` (plus `PLAN.md`, `README.md`, `AGENTS.md`, and the
CI workflows). This document is **forward-looking**: it lists what's still worth doing, with
a concrete action plan for each item. Finished work is not tracked here — see below.

> **What shipped already.** The original DragThing gap analysis (bugs **B1–B12**) and the
> high-value parity features it surfaced — **Trash**, **layout import/export**, **rename /
> change-icon**, **tab reorder + Move-to-Edge**, **auto-hide / auto-fade**, and the **Disks**
> tab — are all merged (PRs #1–#22). Those resolved items have been removed from this
> document; the detail lives in the git history and the merged PRs.

> **Review/build method.** Findings cite `file:line` against the code at review time. The
> review was done by reading the source, not by running the app. macOS CI (`ci.yml`, Xcode
> 16.2) is the source of truth for the build + the XCTest suite (currently **12 test files /
> ~97 test methods**); on-device GUI behavior still needs a real Mac (see §5).

Severity: **P0** correctness / data-loss · **P1** notable functional gap · **P2** robustness /
performance / UX · **P3** polish / cleanup.

---

## 1. Open findings from this review

Nothing P0/P1 surfaced — the code is clean and well-tested. The items below are robustness,
performance, and cleanup.

### Implementation issues

| # | Pri | Finding | Action plan |
|---|-----|---------|-------------|
| **I1** | P2 | **Folder tabs bookmark every entry on every refresh.** `FolderLister.contents` builds each transient item via `DrawerItem.fromFileURL` ([FolderLister.swift:36](MacDring/Store/FolderLister.swift)), which calls `BookmarkResolver.makeBookmark` per file ([DrawerItem.swift:108](MacDring/Model/DrawerItem.swift)). Folder items are never persisted, and every read path (`launch`, `reveal`, `isBroken`, drag-out) already falls back to `item.url` when there's no bookmark. So a folder drawer pointing at a 300-item directory does ~300 bookmark syscalls *and re-does them on every reconcile* (the 80 ms appearance-slider debounce, any display change, any store mutation all call `refreshOpenDrawer` while it's open). | Give `FolderLister` a lightweight item builder that sets `kind` (app/folder/file detection only) + `url` and **skips** `makeBookmark`. Keep `fromFileURL` (with the bookmark) for items that *are* persisted (drops, the Settings "Add Files…" picker). Optional follow-up: cache the listing and only re-list when the directory or sort actually changes. |
| **I2** | P2 | **Synchronous disk I/O in SwiftUI `body`.** `ItemView.isBroken` runs `BookmarkResolver.isBroken` (bookmark resolve + `fileExists`) inside the view body via `.opacity`/`.help` ([ItemView.swift:24,28,38](MacDring/Drawer/ItemView.swift)), and `iconImage` calls `resolveIcon` synchronously as the first-render fallback ([ItemView.swift:97](MacDring/Drawer/ItemView.swift)). On a slow/network volume or a large folder tab this is main-thread I/O per item per re-render. | Resolve broken-ness and the icon together in the existing `.task(id:)` and store both in `@State`; render from cached state in `body`. (The icon is already async there — fold `isBroken` in.) |
| **I4** | P3 | **Slot-drop edge cases.** In `handleFileDrop` for an items tab ([TabController.swift:471–478](MacDring/Tabs/TabController.swift)): dropping a **duplicate** URL onto an empty slot no-ops the placement (`addItem` dedups, then `placeItem(first.id…)` finds nothing); a **multi-file** drop only places `newItems.first` at the slot and scatters the rest; `loadDroppedURLs` returns URLs in **non-deterministic** order ([TabStripView.swift:227](MacDring/Tabs/TabStripView.swift)), so "first" is arbitrary. | Low stakes. If touched: for a duplicate, move the *existing* item to the target slot; for multi-file, fill consecutive free slots from the target; preserve provider order in `loadDroppedURLs` (index the results). |

### Cleanup

| # | Pri | Finding | Action plan |
|---|-----|---------|-------------|
| **C1** | P3 | **Release workflow drops the signing config the project sets.** The target enables Hardened Runtime + `CODE_SIGN_ENTITLEMENTS` (apple-events) in `project.pbxproj`, but `release.yml` builds `CODE_SIGNING_ALLOWED=NO` then `codesign --force --deep --sign -` **without** `--entitlements` or `--options runtime` ([release.yml:54](.github/workflows/release.yml)). The shipped app is ad-hoc, non-hardened, no embedded entitlement. Empty Trash still works (it falls back to the normal TCC "control Finder" prompt), so this is hygiene, not breakage. `--deep` is also Apple-deprecated. | Drop `--deep` (sign the single bundle). If/when Developer ID lands, re-add `--options runtime` + `--entitlements`. Document that the keyless release intentionally ships non-hardened. |
| **C2** | P3 | **Activation-policy revert can fire with another window open.** `SettingsWindowController.windowWillClose` unconditionally resets to `.accessory` ([SettingsWindowController.swift:57–59](MacDring/Settings/SettingsWindowController.swift)); `NewTabWindowController` guards on "any other ordinary window still open" ([NewTabWindowController.swift:75–80](MacDring/Settings/NewTabWindowController.swift)). With both open, closing Settings first drops the New Tab window's Dock presence. | Mirror the `NewTabWindowController` guard in `SettingsWindowController` (only revert to `.accessory` when no other titled window is visible). |
| **C3** | P3 | **Small tidies.** Trailing whitespace at [DrawerItem.swift:122](MacDring/Model/DrawerItem.swift). `DrawerMetrics.notesSize` sizes the notes area from `iconSize` ([DrawerMetrics.swift:16–21](MacDring/Drawer/DrawerMetrics.swift)) even though notes have no icons — works, but the coupling is a smell. The name `autoHide` means *drawer dismissal* on `TabBehavior`/`Preferences` while `TabConcealment` is the *pill* auto-hide — two "auto-hide"s; the comments disambiguate, but a rename (e.g. `closeOnClickOutside`) would remove the footgun. | Trim the whitespace; optionally give `notesSize` its own constants; consider the `autoHide` → `closeOnClickOutside` rename when next touching that field (it's a stored `UserDefaults`/Codable key, so migrate the key). |

---

## 2. Documentation sync (docs vs. code)

The code moved ahead of the prose in a few places. Each is a one-line fix.

| Doc | Says | Reality | Fix |
|---|---|---|---|
| **README.md §Permissions** | "needs **no special permissions**" ([README.md:84](README.md)) | True for core launching, but the app **requests `com.apple.security.automation.apple-events`** and prompts to control Finder the first time you **Empty Trash**. | Add a sentence: Empty Trash asks once to control Finder (Apple Events); declining just leaves the Trash as-is. |
| **PLAN.md §4** | `enum ItemKind { case application, file, folder, url }` ([PLAN.md:169](PLAN.md)) | Six cases — adds `.trash`, `.disk`. | Update the enum and the `DrawerItem`/`TabKind` notes to include trash + disks. |
| **PLAN.md §11–§12** | "**61 unit tests passing**" ([PLAN.md:516](PLAN.md)); file tree omits some files | ~97 tests across 12 files. Tree lacks `TabConcealment.swift`, `MacDringTests/DrawerItemTests.swift`, `MacDringTests/DisksListerTests.swift`. | Refresh the count and add the missing files (or soften to "the test suite," since exact counts drift). |

---

## 3. DragThing parity & missing features (what's left)

| Feature | Status | Action / approach |
|---|---|---|
| **Search / type-to-find + keyboard nav** in an open drawer | ❌ | The headline gap. Needs a focusable field in the borderless key-but-non-activating drawer panel, arrow/return selection over the slot grid, and a filtered view. Interacts with the slot model and key focus — design on-device. |
| **Recent applications / documents** tab kind | ❌ | New `TabKind.recents` backed by `NSWorkspace`/`LSSharedFileList`-style recents, listed transiently like `FolderLister`/`DisksLister`. Mostly additive. |
| **Spring-loaded folder _items_** (hierarchical pop-out) | ❌ | A folder *item* still just opens in Finder; folder *tabs* exist. Hover-to-expand a nested drawer is a larger interaction; defer until search lands. |
| **Multiple named layouts / sets** with in-app switching | ◑ | Import/export already covers backup. Remaining half: store named snapshots and switch between them in Settings. Document is already clean JSON, so this is a store + UI feature. |
| **Separators / spacers / labels** within a dock | ❌ | A non-launchable `ItemKind` rendered as a divider/heading; fits the existing slot grid. Small. |
| **Running-app indicator** dot on application items | ❌ | Observe `NSWorkspace.runningApplications` and dot items whose bundle ID is active. Small, additive. |
| **Folder-tab niceties** — sort options, show-hidden toggle, live `FSEvents` refresh | ❌ | Per-tab sort/hidden flags on the `.folder` tab; `FSEvents`/`DispatchSource` to refresh the open drawer on directory change instead of only on open. Pairs well with **I1**. |
| **iCloud sync**, **Quick Look** (space bar), **accessibility** (VoiceOver/Dynamic Type), **localization** | ❌ | Each is its own project; all deferred. Accessibility is the most user-visible and the cheapest to start (label the SwiftUI controls). |
| Process dock, sound effects, AppleScript, free off-edge placement | ❌ | Intentional non-goals (PLAN §1). |

---

## 4. Deferred / latent (small, low value or mild risk)

- **B13 — first-run seeding fallback + non-silent `.bak` restore.** Seeding only runs when the
  document was *never* loaded ([AppDelegate.swift:22](MacDring/AppDelegate.swift)); a doc that
  loaded but decoded to zero tabs (every record corrupt) shows no tabs and no starter, and a
  successful `.bak` recovery is silent. *Action:* seed when `tabs.isEmpty` regardless of
  `loadedFromDisk`, guarded so it can't fight the "sacred" restore; surface a one-time notice
  when a `.bak` was used. Skipped so far to avoid touching restore for a rare case.
- **B14 — schema-version migration switch.** `LauncherDocument.currentVersion == 1` but nothing
  branches on `version` ([LauncherDocument.swift:8](MacDring/Model/LauncherDocument.swift)); all
  decoders are lenient/forward-compatible, so it's fine *today*. *Action:* add the `switch
  version { … }` migration hook **before** the next breaking schema change, not now.

---

## 5. On-device verification & distribution (Mac-only, can't be done from review)

- **Real-hardware GUI verification:** multi-monitor placement & the park-vs-move-to-main
  disconnect policy, Spaces, fullscreen, drag-to-reposition, auto-hide/fade reveal, and all
  drag-and-drop (tab pill, per-slot drawer drops, folder drag-out, spring-loading) on an actual
  Mac. These paths are unit-tested only where they're pure geometry (`EdgeLayout`, `DrawerMetrics`,
  `ScreenAnchor`, `DisksLister`).
- **Distribution:** Developer ID signing + notarization is intentionally **off** (`release.yml`
  ships an ad-hoc, unsigned, non-notarized build; Gatekeeper warns on first launch). Revisit only
  if direct distribution without the Gatekeeper prompt becomes a goal — see `.github/CICD.md`.

---

> **Net:** the correctness/parity backlog from the original review is fully shipped. What
> remains is a short list of performance/UX refinements (§1), quick doc fixes (§2), and the
> larger, design-led features plus on-device verification that only a Mac session can carry
> (§3, §5).
