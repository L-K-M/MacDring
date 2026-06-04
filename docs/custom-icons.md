# Custom item icons

Any item in any drawer can be given a **custom icon** — useful when the default
icon is generic (a plain cloud/share, a folder of look-alike files) or you just want
a splash of color. There are two kinds of custom icon:

1. **A generated icon** — a colored **folder** or **rounded tile** with an optional
   SF Symbol "burned in". No file needed; pick a color and a symbol.
2. **An image file** — choose any image as the icon (items tabs only).

## Using it

**Right-click an item in its drawer → Customize Icon…** to open the editor:

- **Base** — *Folder* (a macOS-style colored folder with the glyph on the body) or
  *Rounded tile* (a solid color tile with the glyph centered, app-icon-like).
- **Color** — any color.
- **Symbol** — pick an SF Symbol (or leave it empty for a plain colored base; the
  ✕ clears a chosen symbol).

A live **preview** updates as you go. **Save** applies it; **Use Default** removes
the custom icon and restores the item's normal icon.

> The editor opens in its own small window, so the drawer closes while you edit and
> re-opens when you're done.

## How it's stored

The generated icon is an `IconStyle` (`base` + `colorHex` + optional `symbol`), and
it's rendered to an image by `IconRenderer` — the same renderer drives the editor's
preview and the drawer icon, so they always match.

Where the override lives depends on the item:

- **Persistent items** (an **Items** tab) store the `IconStyle` on the item itself
  (`DrawerItem.iconStyle`), so it travels with the item and is included in layout
  export/import.
- **Live items** (the **Folder**, **Disks**, **Network**, and **Cloud** tabs, whose
  contents are re-listed every time the drawer opens) can't carry the override on the
  transient item, so it's stored on the **tab**, keyed by the item's path
  (`Tab.iconStyles`), and re-applied to the freshly-listed item each open. So a
  custom icon for a specific network share or cloud provider sticks across re-lists,
  restarts, and reconnects.

## Precedence

For a given item the icon is chosen in this order:

1. a chosen **image file** (`customIconBookmark`),
2. a **generated** icon (`iconStyle`),
3. the item's **default** (app/file/folder icon, drive icon, the iCloud/cloud glyph,
   the Trash can, …).

Saving a generated icon on an Items-tab item clears any image override (and vice
versa), so an item has at most one custom source; **Reset Icon** / **Use Default**
clears it.
