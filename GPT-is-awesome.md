# GPT Audit Notes — Open Items

Original audit dated 2026-06-28, reconciled against `main` the same day. Findings
that shipped or were implemented during this pass are cleared out; what remains is
**open**, each tagged with why it isn't being implemented now.

**Disposition:** _device_ = needs on-device verification · _design_ = needs a
product/UX decision · _large_ = multi-file refactor / feature.

## Resolved

Findings **1–7** and **14** shipped as PRs #53–#60: reject future-version imports ·
normalize `replaceTabs` slots · lenient `IconStyle.Base` decoding · sanitize
update-download filenames · deduplicate Settings-added items · default Fresh/Recents
to list layout · drawer level follows the tab-window-level preference · kind-aware
tab-pill URL drops. Finding **11** was already satisfied — the drawer's `ItemView`
resolves icon/metadata in a `.task` off the render path. The retry/log-spam half of
**16** is fixed (TabController now caches failed hotkey specs; see awesome.md B14).

## Open — needs a design / product decision

- **8. Folder listing blocks the main path on large/slow dirs.** `FolderLister.contents`
  enumerates + stats + sorts the whole directory before the 300-cap, applied
  synchronously on open. _design_ — async listing needs a drawer loading-state
  contract (placeholder, ordering, cancellation when the tab closes). Overlaps
  awesome.md §2.

- **9. Settings overwrites concurrent tab changes from a stale draft.** (= awesome.md
  B5.) _design_ — per-field store mutations, or merge/resync the draft against the
  latest store value before committing.

- **12. App launch explicitly activates the target app** while project guidance says
  drawer interactions shouldn't steal focus. _design_ — always-background vs. a
  preference vs. modifier-click is a product call (Dock-like launch usually activates).

- **15. List layout lacks empty-slot drop targets.** _design_ — where insertion
  targets sit in a top-to-bottom list (between-row vs. a trailing append zone) is a
  layout decision.

- **16. Hotkey registration failures aren't surfaced in Settings.** _design_ — threading
  registration status back to the recorder UI and choosing its presentation is a
  product decision. (The retry/log-spam half is done.)

- **17. Broken items have no relink action.** _design / large_ — needs a new callback
  through DrawerModel→TabController, an `NSOpenPanel` re-bookmark flow, and a scope
  decision (per-item vs. bulk).

- **18. Fresh/Recents have no loading or timeout state.** _design_ — distinguishing
  "loading" from "empty," plus a timeout policy and its UI, spans model and view.

- **20. Cloud tabs don't refresh live** when providers appear/disappear (no watcher on
  `~/Library/CloudStorage`). _design / large_ — a new `DispatchSource` watch wired
  into open/close/refresh, mirroring the folder watcher.

- **21. Settings "+" only creates a generic Items tab** while the New Tab dialog
  supports every kind. _design_ — route "+" into that dialog or attach a kind menu.

## Open — small but deferred (can't verify blind)

- **10. Settings item rows resolve icons synchronously during render.** Moving to
  async/cached rows mirrors the drawer's `ItemView`, but the Settings list layout
  differs — the visual result (flicker / row-height shift) wants on-device
  verification before changing the render path.

- **13. Click-outside dismissal misses clicks inside MacDring's own windows** (a global
  mouse monitor doesn't report same-app events). A local mouse-down monitor is the
  fix, but it's interaction-sensitive (must not fire on clicks inside the drawer/tab
  panels) and needs on-device verification of the guard.

- **19. Fresh tabs scan the filesystem twice on open** — the drawer seeds via
  `FreshScanner`, then `updateSpotlightWatch` scans again as the Spotlight-merge base,
  in two different classes. De-duping crosses the drawer/controller open sequence;
  both scans are bounded and cheap, so the value doesn't justify a blind cross-class
  change whose runtime behavior can't be verified here.

- **22. New Tab dialog uses a fixed compact size.** Relaxing the frame is small, but
  whether the looser layout reads well across locales / Dynamic Type wants on-device
  visual verification.

## Delightful or quirky ideas (backlog)

Future-pass idea list — each needs design + visual iteration: spring-load countdown
glow · URL favicons · Fresh sparkle on new arrivals · folder truncation badge (`300+`) ·
Recents time buckets (Today / Yesterday / This Week / Older) · cloud-provider
personality · DragThing nostalgia mode · search aliases (`dl`, `icloud`, `trash`) ·
Dock-edge placement warning · peek mode.
