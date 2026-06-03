# MacDring

Screen-edge tabs that open drawers of your apps, files, folders, and links — a
fast, modern reimagining of the classic **[DragThing](https://www.dragthing.com/)**.

Slim colored tabs sit flush against the edges of your screens. Click one and a
drawer slides out with whatever you put there. Drag files onto a tab to add them.
Works across multiple monitors, and your tabs return to exactly where you left
them after a restart.

## Features

- **Edge tabs → drawers.** Colored tabs anchored to any screen edge; click (or
  hover) to open a drawer.
- **Three tab types** — an **items** tab (apps, files, folders, links arranged
  freely in a grid with gaps), a **notes** tab (a quick text scratchpad), and a
  **folder** tab (a live, read-only view of a directory's contents).
- **Holds anything launchable** — applications, files, folders, and URLs. One
  click opens them.
- **Drag-and-drop to add.** Drop files or apps from Finder onto a tab or its open
  drawer.
- **Per-tab color, name, and glyph** (SF Symbol or letters) — DragThing-style
  customization, modernized.
- **Multi-monitor from the start.** Tabs live on a specific display + edge and
  react live to displays connecting, disconnecting, and changing resolution.
- **Stable restore.** Tabs return to the same display and spot after a restart,
  resolution change, or reconnection — anchored by a durable display identity and
  a fractional edge position, never raw pixels.
- **Optional per-tab hotkey** to toggle a drawer from anywhere — and it needs
  **no Accessibility permission**.
- **Modern, native look** — translucent materials, rounded corners, a quick
  open/close animation; light/dark adaptive.
- **Menu-bar agent** — no Dock icon. Launch at login via `SMAppService`.

## Build & Run

Requires **Xcode 16+** and **macOS 13+**.

```bash
# Build
xcodebuild -project MacDring.xcodeproj -scheme MacDring -configuration Debug build

# Release build
xcodebuild -project MacDring.xcodeproj -scheme MacDring -configuration Release build

# Run unit tests
xcodebuild -project MacDring.xcodeproj -scheme MacDring -destination 'platform=macOS' test
```

For day-to-day development, open `MacDring.xcodeproj` in Xcode and run.

## Usage

1. Launch MacDring — it appears as a sidebar icon in the menu bar, and a starter
   **Apps** tab appears on the right edge of your main display.
2. **Click the tab** to open its drawer; click an item to launch it.
3. **Drag files or apps** from Finder onto a tab to add them.
4. **Right-click a tab** → *Configure Tab…* to rename it, change its color/glyph,
   move it to another edge or display, set behavior, or assign a hotkey.
5. Use the menu bar → **New Items / Notes / Folder Tab…** to add more (a small
   dialog sets the name, color, type, and folder), or **MacDring Settings…** to
   manage everything.

### Customizing

- **Per tab** (right-click → *Configure Tab…*, or **Settings → Tabs**): name,
  color, glyph, edge, display, position, open-on-hover/auto-hide/keep-open, and an
  optional hotkey.
- **Global** (**Settings → Appearance / General**): drawer material, grid vs. list
  layout, icon size, corner radius, tab thickness, labels, single vs. double-click
  to open, animation speed, the multi-display disconnect policy, and launch at
  login.

## Permissions & Distribution

MacDring needs **no special permissions** for its core features — launching uses
`NSWorkspace`, and optional hotkeys use Carbon (no Accessibility grant). It ships
as a menu-bar agent (`LSUIElement`) and is intended for direct distribution with
**Developer ID signing + notarization**. (A future App Store build would enable
the sandbox and switch file items to security-scoped bookmarks.)

## Status

v1 is implemented and unit-tested (layout math, anchors, persistence, bookmarks,
preferences). On-screen window behavior — multi-monitor placement, Spaces,
fullscreen, drag-to-reposition, and drag-and-drop — is exercised in a real GUI
session. See `PLAN.md` for the full design and milestone status.
