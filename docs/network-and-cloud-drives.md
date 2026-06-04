# The Network & Cloud tab

A **Network & Cloud** tab is a live, read-only drawer that lists the drives you
reach *over the wire* — your mounted **network shares** and your **cloud-storage
drives** — in one place. It is the sibling of the [Disks tab](../README.md): same
idea (a live listing you don't have to curate), pointed at remote and cloud
storage instead of local volumes.

Create one from the menu bar → **New Network & Cloud Tab…**, or **Settings →
Tabs → +** and pick the *Network & Cloud* type.

## What it shows

The drawer is rebuilt every time it opens (and refreshes live while open as
shares mount/unmount), from two sources:

| Source | What it is | Item kind | Click | Menu |
|---|---|---|---|---|
| **Network shares** | Mounted **remote** volumes — SMB, AFP, NFS, WebDAV, … | `disk` | Opens the share in Finder | **Eject** (disconnects the share) |
| **Cloud drives** | iCloud Drive, plus every File-Provider provider under `~/Library/CloudStorage` (Dropbox, Google Drive, OneDrive, Box, …) | `folder` | Opens the folder in Finder | Reveal in Finder |

Network shares come first (sorted by name), then cloud drives (sorted by name).

## How it works

The listing is produced by `NetworkLister` (in `MacDring/Store/`), mirroring
`DisksLister` and `FolderLister`:

- **Network shares.** `FileManager.mountedVolumeURLs(...)` enumerates every mounted
  volume; each is kept only when it is **browsable** and **not local**
  (`URLResourceKey.volumeIsLocalKey == false`). That "`!isLocal`" test is exactly
  what separates a remote mount from a local disk, a USB stick, or a mounted disk
  image — those report `isLocal == true` and belong to the **Disks** tab, not here.
  A kept share becomes a `.disk` `DrawerItem` carrying the volume URL, so it reuses
  the existing open-in-Finder and **eject** plumbing (`DiskEjector`,
  `NSWorkspace.unmountAndEjectDevice`). No extra permission is needed.
- **Cloud drives.** macOS 12+ collects third-party cloud providers as folders under
  `~/Library/CloudStorage`, and iCloud Drive lives at
  `~/Library/Mobile Documents/com~apple~CloudDocs`. `NetworkLister.cloudRoots`
  reads those two locations (the user's own Library — no special permission) and
  turns each provider folder into a `.folder` `DrawerItem`. Cloud roots are plain
  folders, not volumes, so they can be opened but **not** ejected.

Both sources produce **transient** items: nothing is written to
`launcher.json`, and the items carry a plain `url` (no bookmark), so a closed tab
costs nothing and an open one always reflects the current state.

### Staying live

`TabController` already observes `NSWorkspace`'s
`didMount` / `didUnmount` / `didRenameVolume` notifications to refresh an open
**Disks** drawer; the same observer now refreshes an open **Network & Cloud**
drawer (its network shares are `.disk` items too). Connecting or disconnecting a
share, or ejecting one from the drawer, updates the list immediately. Cloud
providers change rarely (you add one in its app); those are picked up the next
time the drawer opens.

### Read-only

Like the Disks and Notes tabs, a Network & Cloud tab takes **no drops** — it is a
mirror of system state, not a place to file things. Its items are still draggable
**out** to Finder or other apps (drag a share or a cloud folder onto a window),
and `⌘`-click reveals an item in Finder instead of opening it.

## Network vs. Disks — which lists what?

| | Disks tab | Network & Cloud tab |
|---|---|---|
| Local disks / USB / SD | ✅ | — |
| Mounted disk images (`.dmg`) | ✅ | — |
| Network shares (SMB/AFP/NFS/WebDAV) | ✅ (as ejectable volumes) | ✅ (the focus) |
| Cloud drives (iCloud, Dropbox, …) | — | ✅ |

Network shares appear in **both** (they are ejectable volumes *and* network
drives); everything else is exclusive to one tab. Use the Disks tab for "what
can I eject?" and the Network & Cloud tab for "where's my remote/cloud storage?".

## Limitations

- **Cloud detection is path-based.** A provider must use a macOS File-Provider
  extension (so it appears under `~/Library/CloudStorage`) to be listed. A
  provider that only syncs a folder in your home directory won't show up — add it
  as a **Folder** tab or a folder item instead.
- **No live cloud refresh.** Adding/removing a cloud provider is reflected the next
  time the drawer opens, not instantly (there is no volume notification for it).
