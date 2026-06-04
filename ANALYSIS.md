# MacDring — Open Backlog

A living, **forward-looking** backlog: what's still worth doing, each with a concrete
action. Finished work isn't tracked here — it lives in git history and the merged PRs.
Findings cite `file:line` against the code at review time. macOS CI (`ci.yml`, Xcode
16.2) is the source of truth for the build + the `MacDringTests/` suite; on-device GUI
behavior still needs a real Mac (§4).

> **Shipped so far.** The original DragThing gap analysis (B1–B12) and the parity
> features it surfaced are all merged: Trash, layout import/export, rename /
> change-icon, tab reorder + Move-to-Edge, auto-hide / auto-fade, the **Disks**,
> **Network**, and **Cloud** tabs, **per-tab behavior overrides**, **customizable item
> icons**, and a batch of robustness fixes (Trash-state accuracy, the activation-policy
> guard, folder-tab bookmark overhead, cached drawer-icon resolution, slot-drop edge
> cases). See the git history / PRs #1–#32.

Severity: **P0** data-loss · **P1** functional gap · **P2** robustness/perf/UX · **P3**
polish. **Nothing P0–P1 is open** — the code is clean and well-tested.

---

## 1. Code cleanup (P3)

- **C1 — Release-signing hygiene.** `release.yml` ad-hoc signs with
  `codesign --force --deep --sign -` ([release.yml:54](.github/workflows/release.yml)):
  `--deep` is Apple-deprecated, and the build (`CODE_SIGNING_ALLOWED=NO`) drops the
  target's Hardened Runtime + apple-events entitlement. Empty Trash still works (it
  falls back to the normal TCC prompt), so this is hygiene, not breakage.
  **Action:** drop `--deep` (sign the single bundle); note that the keyless release
  intentionally ships non-hardened; re-add `--options runtime` + `--entitlements` if
  Developer ID ever lands.
- **C3 — Small tidies.** Trailing whitespace at
  [DrawerItem.swift:162](MacDring/Model/DrawerItem.swift). `DrawerMetrics.notesSize`
  sizes the notes area from `iconSize` ([DrawerMetrics.swift:16–18](MacDring/Drawer/DrawerMetrics.swift))
  although notes have no icons — works, but a smell. `autoHide` (drawer dismissal, on
  `TabBehavior`/`Preferences`) collides in name with `TabConcealment`'s *pill* auto-hide.
  **Action:** trim the whitespace; optionally give `notesSize` its own constants;
  consider renaming `autoHide` → `closeOnClickOutside` next time that field is touched
  (migrate the Codable / `UserDefaults` key).

---

## 2. Features — DragThing parity & beyond

| Feature | Status | Approach |
|---|---|---|
| **Search / type-to-find + keyboard nav** in an open drawer | ❌ | The headline gap. A focusable field in the borderless key-but-non-activating drawer, arrow/return selection over the slot grid, and a filtered view. Touches the slot model + key focus — design on-device. |
| **Recents tab** (recent apps / documents) | ❌ | New `TabKind.recents` from `NSWorkspace` / `LSSharedFileList`-style recents, listed transiently like the other listers. Mostly additive. |
| **Spring-loaded folder _items_** (hierarchical pop-out) | ❌ | Folder *tabs* exist; a folder *item* still just opens in Finder. Hover-to-expand a nested drawer is a larger interaction — defer until search lands. |
| **Named layouts / sets** with in-app switching | ◑ | Import/export already covers backup; the remaining half is storing named snapshots + a Settings switcher (the document is already clean JSON). |
| **Separators / spacers / labels** in a dock | ❌ | A non-launchable item kind rendered as a divider/heading; fits the existing slot grid. Small. |
| **Running-app indicator** dot on app items | ❌ | Observe `NSWorkspace.runningApplications`; dot items whose bundle ID is active. Small, additive. |
| **iCloud sync · Quick Look · accessibility · localization** | ❌ | Each is its own project. Accessibility (labelling the SwiftUI controls) is the cheapest, most user-visible start. |
| Process dock · sound effects · AppleScript · free off-edge placement | — | Intentional non-goals (PLAN §1). |

---

## 3. Deferred / latent (low value or mild risk)

- **B13 — first-run seeding fallback + non-silent `.bak` restore.** Seeding runs only
  when the document was *never* loaded ([AppDelegate.swift:22](MacDring/AppDelegate.swift));
  a document that loaded but decoded to zero tabs shows nothing, and a `.bak` recovery
  is silent. **Action:** seed when `tabs.isEmpty` regardless of `loadedFromDisk`
  (guarded so it can't fight the "sacred" restore); surface a one-time "recovered from
  backup" notice. Deferred to avoid touching restore for a rare case.
- **B14 — schema-version migration hook.** `LauncherDocument.currentVersion == 1` but
  nothing branches on `version` ([LauncherDocument.swift:7](MacDring/Model/LauncherDocument.swift));
  all decoders are forward-compatible, so it's fine today. **Action:** add the
  `switch version { … }` hook **before** the next breaking schema change, not now.

---

## 4. On-device verification & distribution (Mac-only)

- **GUI verification on real hardware:** multi-monitor placement + the park-vs-move-to-main
  disconnect policy, Spaces, fullscreen, drag-to-reposition, auto-hide/fade reveal, all
  drag-and-drop (tab pill, per-slot drawer drops, folder drag-out, spring-loading), and
  the **generated-icon rendering + icon editor**. Unit tests cover only the pure logic
  (`EdgeLayout`, `DrawerMetrics`, `ScreenAnchor`, the listers, `IconStyle`).
- **Distribution:** Developer ID signing + notarization is intentionally **off**
  (`release.yml` ships an ad-hoc, unsigned, non-notarized build; Gatekeeper warns on
  first launch). Revisit only if prompt-free direct distribution becomes a goal — see
  `.github/CICD.md`.
