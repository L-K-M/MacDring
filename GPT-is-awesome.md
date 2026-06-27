# GPT-is-awesome.md

A current-state review of MacDring, written after reading the Swift/AppKit/SwiftUI
surface, tests, workflows, docs, and the existing backlog. The old `awesome.md`
was a useful fossil record, but many of its red flags are already fixed here:
lenient decoding, backup rotation, Carbon hotkey chaining, tab hover replay,
drawer drop highlighting, Settings miniaturization, SemVer prerelease ordering,
and release-test gating all have current code.

Legend: **High confidence** means I would implement it in a small branch. **Needs
design** means the bug or improvement is real, but the best behavior should be
chosen deliberately.

## Bugs and behavior issues

1. **Folder drawers accept web-link drops, then silently do nothing.**
   `DrawerHostingView.droppableModel` accepts `NSURL` objects with
   `.urlReadingFileURLsOnly: false` for both items and folder tabs
   ([DrawerWindowController.swift:45](MacDring/Drawer/DrawerWindowController.swift:45)).
   Later `handleFileDrop` filters folder-tab drops to `fileURLs`
   ([TabController.swift:630](MacDring/Tabs/TabController.swift:630)) and moves
   only those into the folder ([TabController.swift:653](MacDring/Tabs/TabController.swift:653)).
   Dragging a browser URL onto a folder drawer shows acceptance feedback but
   stores/moves nothing. **High confidence:** folder drawers should only advertise
   file URL drops; items drawers can keep accepting files and web URLs.

2. **A drag exit from one tab can cancel another tab's pending spring-open.**
   `pendingSpringOpen` is a single work item
   ([TabController.swift:26](MacDring/Tabs/TabController.swift:26)). When a drag
   exits any tab, `handleDragHover(... targeted: false)` cancels it without
   knowing which tab scheduled it ([TabController.swift:678](MacDring/Tabs/TabController.swift:678)).
   An enter-B / exit-A ordering can suppress B's spring-loaded drawer. **High
   confidence:** track the pending spring-open tab ID and cancel only matching exits.

3. **System-only Recents tabs show a clear button that cannot clear system recents.**
   The drawer header shows the trash/clear button for every `.recents` tab
   ([DrawerView.swift:171](MacDring/Drawer/DrawerView.swift:171)), but the action
   only clears `RecentsStore.shared`, MacDring's own history
   ([TabController.swift:758](MacDring/Tabs/TabController.swift:758)). For a
   `.system` source, and for a `.both` source with only Spotlight results, the
   button appears to do nothing. **High confidence:** expose whether the open
   recents drawer has clearable MacDring history and hide/disable the button otherwise.

4. **Type-to-find navigation can interfere with marked-text composition.**
   The local key monitor swallows Return, Enter, Up, and Down while searching
   ([TabController.swift:1048](MacDring/Tabs/TabController.swift:1048),
   [TabController.swift:1074](MacDring/Tabs/TabController.swift:1074)). That is
   fine for Latin text, but CJK/IME input uses marked text and often needs those
   keys to choose or confirm a composition. **High confidence:** if the current
   first responder is an `NSTextInputClient` with marked text, let the event pass.

5. **`RecentsStore.save` can erase history on an encoding failure.**
   It writes `defaults.set(try? JSONEncoder().encode(items), ...)`
   ([RecentsStore.swift:54](MacDring/Store/RecentsStore.swift:54)). `nil` removes
   the key, so a failed encode loses the last good persisted recents list. The
   model is simple enough that this is rare, but the failure mode is needless.
   **High confidence:** only update UserDefaults after a successful encode and log
   failures.

6. **Move-to-main and first-run fallback use `NSScreen.main`, which is not stable
   "primary display" identity.** `reconcile` places disconnected tabs on
   `NSScreen.main` under the move-to-main policy
   ([TabController.swift:122](MacDring/Tabs/TabController.swift:122)), and
   `DisplayRegistry.mainScreenUUID()` prefers `NSScreen.main`
   ([DisplayRegistry.swift:44](MacDring/Screens/DisplayRegistry.swift:44)).
   AppKit's main screen follows keyboard/window focus. MacDring also makes its
   drawer panel key, so this fallback can drift toward the last active panel's
   display rather than the menu-bar/primary display. **High confidence:** prefer
   `NSScreen.screens.first` for deterministic primary-display fallback.

7. **Spotlight query start failure leaves async live tabs waiting forever.**
   `SpotlightQuery.start` configures the query and calls `query.start()` without
   checking the Boolean result ([SpotlightQuery.swift:58](MacDring/Store/SpotlightQuery.swift:58)).
   If the query cannot start, the completion never fires. Fresh has a direct-scan
   fallback, but system Recents can stay empty/stale with no clear failure path.
   **High confidence:** if `start()` returns false, tear down and complete with `[]`.

8. **Settings can still clobber concurrent tab changes.**
   `TabEditor` owns a full `Tab` draft and commits the whole value on every change
   ([TabsView.swift:163](MacDring/Settings/TabsView.swift:163),
   [TabsView.swift:346](MacDring/Settings/TabsView.swift:346)). If a file is
   dropped onto the tab, notes are edited in the drawer, or a live icon override is
   changed while Settings is open, the next Name/Color/Behavior edit can write an
   older snapshot back over those changes. **Needs design:** field-wise commits or
   a merge-against-baseline editor would fix this, but it touches the settings data
   flow and deserves a careful pass.

9. **The drawer drag operation badge says "copy" even when the action is move,
   open-with, trash, or add-a-reference.** `DrawerHostingView.updateDrag` always
   returns `.copy` ([DrawerWindowController.swift:58](MacDring/Drawer/DrawerWindowController.swift:58)).
   For folder-target drops, `FileMover.move` removes the original file
   ([FileMover.swift:8](MacDring/Launch/FileMover.swift:8)); for items tabs it adds
   a launcher reference; for app targets it opens with the app. **Needs design:**
   `.generic` would avoid the false green-plus promise, but Finder-style modifier
   behavior may be worth designing before changing the cursor globally.

10. **Drawer drop-highlight cleanup depends on AppKit sending a separate end/exit.**
    `performDragOperation` clears `fileDropSlot` but not `isDropTargeted`
    ([DrawerWindowController.swift:82](MacDring/Drawer/DrawerWindowController.swift:82)).
    `draggingEnded` normally clears both, but clearing both in `performDragOperation`
    is safer and avoids a stuck bright outline if AppKit skips the extra callback.
    **High confidence:** clear both fields on performed drops and empty drop failures.

## General issues

1. **A few UI paths still do synchronous filesystem work on the render path.**
   `ItemView` wisely moved drawer icon and metadata resolution into `.task`, but
   the Settings item list still calls `ItemView.resolveIcon(item)` directly in the
   form row ([TabsView.swift:259](MacDring/Settings/TabsView.swift:259)). The Trash
   context menu also checks every mounted trash synchronously while building the menu
   ([ItemView.swift:78](MacDring/Drawer/ItemView.swift:78)). This is mostly fine for
   tiny local layouts, but network volumes and large setups can make Settings feel
   sticky.

2. **Launch/file operation failures are mostly logged, not surfaced.**
   `FileMover.move`, `FileMover.trash`, `DiskEjector.eject`, and app open-with all
   return or log failure, but the drawer generally refreshes as if the action worked.
   A small transient failure badge/toast would make "file in use", "eject failed",
   or "couldn't move" understandable without Console.

3. **CI/CD docs are stale about release signing.**
   The workflow now runs tests before release and signs with
   `codesign --force --sign -` ([release.yml:87](.github/workflows/release.yml:87)),
   but the root `CICD.md` still says the app is signed with `--deep`
   ([CICD.md:56](CICD.md:56)). **High confidence:** update the prose so future
   release work starts from the truth.

4. **There are still small hygiene nits.**
   `GitHubReleaseClient.fetch` force-unwraps a constructed URL
   ([GitHubReleaseClient.swift:42](MacDring/Updates/GitHubReleaseClient.swift:42)),
   `DrawerItem.swift` has trailing whitespace before the Trash factory
   ([DrawerItem.swift:176](MacDring/Model/DrawerItem.swift:176)), and
   `DrawerMetrics.notesSize` sizes notes from icon dimensions
   ([DrawerMetrics.swift:28](MacDring/Drawer/DrawerMetrics.swift:28)). None are
   urgent, but they are easy cleanups when those files are touched.

## Missing features worth considering

1. **2-D keyboard navigation when not filtering.** Type-to-find is great, but arrow
   movement through the visible grid/list would make drawers usable without search,
   especially for small, muscle-memory layouts.

2. **Quick Look for file/folder items.** Spacebar preview, or a context-menu
   "Quick Look", would feel native and would make Fresh/Recents tabs much more useful.

3. **Separators, spacers, and labels.** A non-launchable drawer item kind would let
   users make little sections inside an items tab without needing fake folders.

4. **Named layouts/profiles.** Import/export is already there. Keeping named
   snapshots inside the app would support "work", "travel", "presentation", or
   "minimal mode" setups with very little new model complexity.

5. **Accessibility labels and VoiceOver pass.** The icon-only header controls have
   `.help`, but not a complete accessibility story. A focused pass would improve
   keyboard/screen-reader confidence without threatening the no-permission promise.

6. **Optional folder-item popouts.** Folder tabs exist, but a folder item still opens
   in Finder. A spring-open nested drawer would be delightfully DragThing-adjacent,
   though it should be opt-in so the app stays calm.

## Visual and layout notes

1. **The current screenshot looks polished.** The pill/drawer join, edge-sharp
   corners, and tab color accents read well. The earlier "tab does not attach to
   drawer" class of issue appears addressed by `minExtent` and inner-corner squaring
   in `DrawerWindowController.computeOpenFrame`
   ([DrawerWindowController.swift:332](MacDring/Drawer/DrawerWindowController.swift:332)).

2. **The drop cursor and highlights need semantic tightening.** The slot rings are
   useful, but the copy badge conflicts with move/trash/open-with behavior. This is
   the most visible remaining interaction ambiguity.

3. **Settings item rows can stutter on icon-heavy tabs.** This is the same render-path
   icon issue from General issue 1, but it is also visual: a Settings form should
   scroll like paper, not like it is touching every network bookmark on the way by.

4. **Notes sizing feels tied to launcher icon settings.** The behavior is documented,
   but "icon size changes my note page size" is conceptually odd. A future notes
   width/height preset, or fixed text-area sizing constants, would make that pane
   feel more intentional.

## Delightful or quirky ideas

1. **Drop receipts.** After a successful drop, briefly show a tiny "Added", "Moved",
   "Opened with", or "Trashed" pulse in the drawer header. It would also solve the
   silent-failure gap by having a natural place for "Could not eject" or "Move failed".

2. **Recent drop stack.** A temporary "last dropped" mini row at the top of a drawer
   could make bulk filing feel satisfying and give users a quick undo/remove target.

3. **Edge weather.** Not actual weather: a subtle per-edge "busy" shimmer while a
   folder/Fresh/Recents live listing is refreshing, so async updates feel alive.

4. **Icon recipe presets.** The generated icon editor could offer a few named styles
   ("Project", "Archive", "Server", "Scratch") built from the existing `IconStyle`
   primitives. No heavy assets required.

5. **A tiny command palette.** From the menu-bar item: fuzzy search all tabs/items,
   jump to a tab, add a link, toggle idle hiding, check updates. MacDring is spatial
   first, but a keyboard command layer would be a nice power-user secret door.
