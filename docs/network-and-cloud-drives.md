# The Network and Cloud tabs

Two live, read-only tab types — siblings of the [Disks tab](../README.md) — for the
drives you reach *over the wire*:

- a **Network** tab lists your mounted **network shares**, and
- a **Cloud** tab lists your **cloud-storage drives**.

They're separate tab types so you can place and color them independently (a Network
tab on one edge, a Cloud tab on another). Create either from the menu bar → **New
Network Tab…** / **New Cloud Tab…**, or **Settings → Tabs → +**.

## Network tab

Lists every mounted **remote** volume — SMB, AFP, NFS, WebDAV, … — rebuilt each time
the drawer opens and refreshed live as shares mount/unmount.

| | |
|---|---|
| **Item kind** | `disk` (a real, ejectable volume) |
| **Default icon** | the volume's own icon (a network-drive glyph), via `NSWorkspace` |
| **Click** | open the share in Finder |
| **Menu** | **Eject** (disconnect the share) · Reveal in Finder |

A volume is kept only when it is **browsable** and **not local**
(`URLResourceKey.volumeIsLocalKey == false`). That "`!isLocal`" test is exactly what
separates a remote mount from a local disk, a USB stick, or a mounted disk image —
those report `isLocal == true` and belong to the **Disks** tab.

## Cloud tab

Lists your cloud-storage roots, rebuilt each time the drawer opens:

- **iCloud Drive** — `~/Library/Mobile Documents/com~apple~CloudDocs`
- **File-Provider providers** — every folder under `~/Library/CloudStorage`
  (Dropbox, Google Drive, OneDrive, Box, …), which is where macOS 12+ collects them.

| | |
|---|---|
| **Item kind** | `cloud` (an openable folder, not a volume) |
| **Default icon** | iCloud Drive → the system **iCloud** glyph; other providers → their own folder icon (most providers set one), falling back to a cloud glyph |
| **Click** | open the folder in Finder |
| **Menu** | Reveal in Finder |

Reading those two locations needs **no special permission** (they're in the user's
own Library), and the listing degrades to empty if a directory can't be read.

## How it works

Each tab is backed by a small pure lister in `MacDring/Store/`, mirroring
`DisksLister`/`FolderLister`:

- `NetworkLister` — enumerates `FileManager.mountedVolumeURLs(...)` and keeps the
  remote, browsable volumes as `.disk` items (reusing the existing open-in-Finder and
  **eject** plumbing: `DiskEjector`, `NSWorkspace.unmountAndEjectDevice`).
- `CloudLister` — reads the iCloud + `CloudStorage` roots as `.cloud` items.

Both produce **transient** items: nothing is written to `launcher.json`, and items
carry a plain `url` (no bookmark), so a closed tab costs nothing and an open one
always reflects the current state.

### Staying live

`TabController` observes `NSWorkspace`'s `didMount` / `didUnmount` /
`didRenameVolume` notifications and refreshes an open **Network** drawer (its shares
are volumes). Cloud providers change rarely — adding/removing one in its app — so a
**Cloud** drawer re-lists the next time it opens rather than live.

### Read-only

Like the Disks and Notes tabs, Network and Cloud tabs take **no drops** — they mirror
system state. Items are still draggable **out** to Finder or other apps, and
`⌘`-click reveals an item in Finder instead of opening it.

## Customizing an item's icon

If a default icon looks generic (some cloud providers don't publish a folder icon),
you can give any item your own icon — **right-click → Customize Icon…** — choosing a
color and an optional SF Symbol on a folder or rounded-tile base. For these live
tabs the override is remembered per share/provider (keyed by its path), so it sticks
across re-lists. See [custom item icons](custom-icons.md) for details.

## Network vs. Disks — which lists what?

| | Disks tab | Network tab | Cloud tab |
|---|---|---|---|
| Local disks / USB / SD | ✅ | — | — |
| Mounted disk images (`.dmg`) | ✅ | — | — |
| Network shares (SMB/AFP/NFS/WebDAV) | ✅ (as ejectable volumes) | ✅ (the focus) | — |
| Cloud drives (iCloud, Dropbox, …) | — | — | ✅ |

Network shares appear in **both** Disks and Network (they're ejectable volumes *and*
network drives); everything else is exclusive.

## Limitations

- **Cloud detection is path-based.** A provider must use a macOS File-Provider
  extension (so it appears under `~/Library/CloudStorage`) to be listed. A provider
  that only syncs a plain folder in your home directory won't show up — add it as a
  **Folder** tab or a folder item instead.
- **No live cloud refresh.** Adding/removing a cloud provider is reflected the next
  time the Cloud drawer opens, not instantly (there is no volume notification for it).
