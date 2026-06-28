# GPT Audit Notes — Open Items

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

## Delightful or Quirky Ideas

- Spring-load countdown glow: while a dragged item hovers over a tab and the spring-open timer is pending, animate a subtle charging outline around the tab.
- URL favicons: replace the generic globe for web links with cached favicons when feasible.
- Fresh sparkle: briefly sparkle newly-arrived Fresh items, matching the Fresh tab's `sparkles` glyph.
- Folder truncation badge: show `300+` or similar when `FolderLister.limit` truncates a large directory.
- Recents time buckets: group list layout sections as Today, Yesterday, This Week, and Older.
- Cloud-provider personality: give iCloud, Dropbox, Google Drive, OneDrive, and Box default colors/glyph treatments in cloud tabs.
- DragThing nostalgia mode: in classic tab style, add a tiny bevel/highlight animation when a drawer opens.
- Search aliases: let short terms like `dl`, `icloud`, `trash`, and provider names match common drawer items.
- Dock-edge warning: when a tab is placed on the Dock edge, show a gentle hint explaining that `visibleFrame` may shift available space.
- Peek mode: modifier-hover a Notes, Fresh, or Recents tab to preview the drawer without keying search or editing.
