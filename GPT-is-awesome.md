# GPT Audit Notes

Date: 2026-06-28

Scope: repository review of MacDring on `main`, with emphasis on bugs, performance/stutter risks, visual/layout issues, missing features, and improvement ideas. The untracked `.claude/` directory was present before this audit and was not touched.

## Legend

- Severity: High, Medium, Low, Idea.
- Confidence: High, Medium, Low.
- Disposition: `PR now` means I think the fix is small, independently valuable, and low-risk enough to implement immediately. `Design first` means the code issue is real but behavior or UX should be decided before changing it. `Backlog` means useful but not urgent, larger, or needing manual profiling.

## Findings

### 1. Future-version imports can bypass the newer-schema save protection

- Severity: Medium
- Confidence: High
- Disposition: PR now
- Evidence: `MacDring/Store/TabStore.swift` imports a decoded document with `replaceTabs(...)`, but leaves the in-memory `document.version` at the current app version. `saveNow()` correctly refuses to rewrite documents with `version > LauncherDocument.currentVersion`, but that guard no longer applies after import.
- Impact: Importing a layout exported by a newer MacDring can silently discard unknown future fields and then save the downgraded schema.
- Suggested fix: Reject imports whose document version is newer than this build, and test that the current tabs remain unchanged.

### 2. `replaceTabs(_:)` can persist invalid item slots

- Severity: Low
- Confidence: High
- Disposition: PR now
- Evidence: `MacDring/Store/TabStore.swift` normalizes item slots on load, `addTab`, `updateTab`, and import, but `replaceTabs(_:)` assigns the array directly.
- Impact: A reorder path or future caller can persist duplicate or negative slots even though the rest of the store tries to maintain valid grid positions.
- Suggested fix: Normalize item slots inside `replaceTabs(_:)` too.

### 3. Unknown future icon bases can discard icon styles

- Severity: Low/Medium
- Confidence: High
- Disposition: PR now
- Evidence: `MacDring/Model/IconStyle.swift` decodes `IconStyle.Base` strictly. A future `base` raw value throws. `DrawerItem.iconStyle` can then degrade to `nil`, while one bad entry in `Tab.iconStyles` can make the whole live-icon dictionary fall back to empty.
- Impact: Users running an older build after a newer one can lose custom icon presentation unnecessarily.
- Suggested fix: Decode `base` leniently with `.folder` as the fallback and add coverage for unknown raw values.

### 4. Update downloads use the remote asset name as a path component

- Severity: Low
- Confidence: Medium/High
- Disposition: PR now
- Evidence: `MacDring/Updates/UpdateDownloader.swift` passes `asset.name` directly into `appendingPathComponent`.
- Impact: GitHub release asset names are normally trusted, but path separators, empty names, `.`/`..`, or control-ish names are needless risk in reusable download code.
- Suggested fix: Sanitize to the last path component, reject pathlike placeholders, and preserve collision handling.

### 5. Settings file/link additions can duplicate existing targets

- Severity: Low
- Confidence: High
- Disposition: PR now
- Evidence: `MacDring/Settings/TabsView.swift` appends files and links directly to the local draft. The drag/drop path goes through `TabStore.addItem`, which deduplicates by resolved target.
- Impact: The same app/file/link can appear multiple times depending on whether the user added it from Settings or by dropping it.
- Suggested fix: Reuse equivalent target deduplication when appending to the Settings draft.

### 6. Fresh and Recents tabs default to grid even though their data is date-ranked

- Severity: Low
- Confidence: Medium/High
- Disposition: PR now
- Evidence: `MacDring/Model/Tab.swift` notes that date-ranked tabs read well as a list, but `MacDring/Settings/NewTabWindowController.swift` creates every tab with the default `.grid` layout.
- Impact: Newly-created Fresh/Recents tabs start in a less informative layout and hide the date-oriented design until the user discovers the per-tab setting.
- Suggested fix: Default Fresh and Recents to `.list`; keep other tab kinds unchanged.

### 7. Drawer level ignores the user's tab-window-level preference

- Severity: Medium
- Confidence: High
- Disposition: PR now, if mapped conservatively
- Evidence: `MacDring/Drawer/DrawerWindowController.swift` hard-codes the drawer panel level to `.popUpMenu`, while tab windows honor `Preferences.tabWindowLevel`.
- Impact: A user choosing normal-level tabs can still get a drawer floating at menu level above unrelated windows.
- Suggested fix: Let `DrawerWindowController` apply a level from preferences, likely keeping the drawer just above its tab but not hard-coded to popup-menu level in normal mode.

### 8. Folder tab listing can block the main path on large or slow directories

- Severity: High
- Confidence: High
- Disposition: Backlog, larger PR
- Evidence: `MacDring/Store/FolderLister.swift` calls `contentsOfDirectory`, reads resource values for every entry, sorts everything, and only then applies the 300-item limit. The drawer applies folder contents synchronously when opening or refreshing.
- Impact: Huge folders, slow external disks, cloud-backed folders, or network volumes can stutter drawer opening and file-system refreshes.
- Suggested fix: Move listing off-main, keep previous content or show loading while listing, and discard stale results if another tab opens first. Consider preserving exact sort semantics even if early capping is introduced.

### 9. Settings can overwrite concurrent tab changes from a stale draft

- Severity: High
- Confidence: High
- Disposition: Backlog, needs careful store API work
- Evidence: `MacDring/Settings/TabsView.swift` stores a whole `Tab` as `@State draft` and calls `store.updateTab(draft)` on any draft change. `updateTab` replaces the entire tab.
- Impact: If the user edits Settings while a drawer drop, notes edit, icon customization, live-source style update, or another window updates the same tab, the next Settings field change can clobber those unrelated fields from the stale draft.
- Suggested fix: Prefer field-specific store mutations, or resync/merge the draft against the latest store value before committing.

### 10. Settings item rows synchronously resolve icons during view rendering

- Severity: Medium
- Confidence: High
- Disposition: Backlog or combine with a Settings refactor
- Evidence: `MacDring/Settings/TabsView.swift` calls `ItemView.resolveIcon(item)` directly inside the `ForEach` body.
- Impact: Large item lists, network paths, broken bookmarks, or custom icon files can make Settings scroll or load less smoothly.
- Suggested fix: Use a small async/cached row view, mirroring the drawer's attempt to keep icon work off the render path.

### 11. Drawer item icon/metadata tasks may still perform disk work on the main actor

- Severity: Medium
- Confidence: Medium
- Disposition: Backlog, profile first
- Evidence: `MacDring/Drawer/ItemView.swift` uses `.task` for icon and metadata resolution. That avoids doing work in `body`, but SwiftUI view tasks may still run on the main actor depending on isolation.
- Impact: Large drawers can still jank if bookmark resolution, `NSWorkspace` icon lookup, bundle reads, or resource-value reads are expensive.
- Suggested fix: Move filesystem/icon resolution into detached work and publish the result back on the main actor. Add a small cache keyed by resolved URL and icon style.

### 12. Launching applications explicitly activates the target app

- Severity: Medium/High
- Confidence: High
- Disposition: Design first
- Evidence: `MacDring/Launch/ItemLauncher.swift` sets `NSWorkspace.OpenConfiguration.activates = true` for app launch and open-with drops, while the project guidance says tab/drawer interactions should not steal focus.
- Impact: Clicking an app launcher or dropping onto an app can change the frontmost app immediately.
- Suggested fix: Decide whether MacDring should always launch in the background, expose a preference, or use modifier-click for background launch. This is behaviorally important enough to decide before changing.

### 13. Click-outside dismissal likely misses clicks inside MacDring's own windows

- Severity: Medium
- Confidence: Medium/High
- Disposition: Backlog, manual validation needed
- Evidence: `MacDring/Tabs/TabController.swift` uses a global mouse monitor for outside-app clicks and a local key monitor for Escape. Global mouse monitors do not report events delivered to the same app.
- Impact: Clicking Settings, the New Tab dialog, or other MacDring UI while a drawer is open may not consistently close the drawer.
- Suggested fix: Add a local mouse-down monitor that closes only for clicks outside drawer/tab panels.

### 14. Tab-pill URL drops are accepted for folder/live tabs but ignored

- Severity: Low
- Confidence: High
- Disposition: PR now or small backlog
- Evidence: `MacDring/Tabs/TabStripView.swift` accepts both file URLs and web URLs. Folder drop handling only processes file URLs, and the drawer-level AppKit drop path already restricts folder tabs to file URLs.
- Impact: Dropping a browser URL onto a folder tab can appear accepted but do nothing useful.
- Suggested fix: Make tab-pill drop acceptance kind-aware, or reject non-file URL drops for folder/live tabs before reporting success.

### 15. List layout lacks empty-slot drop targets

- Severity: Low
- Confidence: High
- Disposition: Backlog
- Evidence: `MacDring/Drawer/DrawerView.swift` reports row frames for existing list items only, while grid layout reports every slot.
- Impact: In list layout, dropping into blank space falls back to generic append behavior instead of a precise target.
- Suggested fix: Add synthetic slot frames for empty rows or a dedicated append target below the last visible row.

### 16. Hotkey registration failures are only logged

- Severity: Low/Medium
- Confidence: Medium
- Disposition: Backlog
- Evidence: `MacDring/Tabs/TabController.swift` logs registration failures from `MacDring/Hotkeys/CarbonHotkey.swift`, but Settings still shows the hotkey as configured.
- Impact: A user can believe a hotkey works when macOS rejected it or another tab already owns it.
- Suggested fix: Surface registration status in Settings, and preflight duplicate hotkeys before saving.

### 17. Broken items are dimmed but have no clear relink action

- Severity: Low
- Confidence: Medium/High
- Disposition: Backlog
- Evidence: `MacDring/Drawer/ItemView.swift` dims broken targets and provides help text, but the planned relink affordance is not visible in the context menu.
- Impact: Users can see that an item is broken but have no direct repair path.
- Suggested fix: Add `Relink...` for broken file/app/folder items and update the bookmark/URL after the user selects a replacement.

### 18. Fresh and system Recents have no loading or timeout state

- Severity: Medium
- Confidence: Medium
- Disposition: Backlog
- Evidence: `MacDring/Store/SpotlightQuery.swift` gathers asynchronously, while `MacDring/Drawer/DrawerView.swift` can show an empty-state message before query completion.
- Impact: A live tab can look empty or broken while Spotlight is still gathering, unavailable, or slow.
- Suggested fix: Add a live-items loading/error state and source-specific empty copy.

### 19. Fresh tabs do a direct filesystem scan twice on open

- Severity: Low
- Confidence: High
- Disposition: Backlog
- Evidence: Fresh content is seeded in `DrawerWindowController.apply(tab:)`, then `TabController.startFreshQuery` performs another `FreshLister.contents()` call before starting Spotlight.
- Impact: Small but avoidable repeated I/O on drawer open.
- Suggested fix: Pass through the already-seeded items or cache the scan briefly.

### 20. Cloud tabs do not appear to refresh live when providers appear or disappear

- Severity: Low
- Confidence: Medium
- Disposition: Backlog
- Evidence: Disks/network tabs observe workspace volume notifications, and folders have a dispatch source watcher. Cloud tabs are listed on open but do not appear to watch `~/Library/CloudStorage` or the iCloud container parent.
- Impact: New or removed cloud providers may not show until reopening or refreshing the drawer.
- Suggested fix: Watch the relevant cloud roots, or periodically refresh only while a cloud drawer is open.

### 21. The Settings `+` button only creates a generic Items tab

- Severity: Medium
- Confidence: High
- Disposition: Design first
- Evidence: `MacDring/Settings/TabsView.swift` creates a hard-coded Items tab, while the menu/New Tab dialog supports Items, Notes, Folder, Disks, Network, Cloud, Recents, and Fresh.
- Impact: Settings makes the most interesting tab types less discoverable.
- Suggested fix: Reuse the New Tab dialog or attach a menu to the `+` button.

### 22. New Tab dialog uses a fixed compact size

- Severity: Low
- Confidence: Medium
- Disposition: Backlog
- Evidence: `MacDring/Settings/NewTabView.swift` uses a fixed frame around a grouped form.
- Impact: Localization, larger text, or future controls can clip.
- Suggested fix: Use a minimum size and fit the content height naturally.

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

## Immediate PR Queue

I will implement the following entries because they are small, high-confidence, and can be isolated into separate branches:

- Entry 1: reject future-version layout imports.
- Entry 2: normalize slots in `replaceTabs(_:)`.
- Entry 3: leniently decode future `IconStyle.Base` values.
- Entry 4: sanitize update-download asset filenames.
- Entry 5: deduplicate Settings-added items.
- Entry 6: default new Fresh/Recents tabs to list layout.
- Entry 7: make drawer level follow the tab-window-level preference if the existing API supports a minimal mapping.
- Entry 14: reject URL drops that folder/live tab pills cannot handle.
