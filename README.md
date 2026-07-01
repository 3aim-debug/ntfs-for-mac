# NTFS For Mac

Mount NTFS drives read/write on macOS using [ntfs-3g](https://github.com/tuxera/ntfs-3g) and [macFUSE](https://macfuse.github.io/). SwiftUI front-end over DiskArbitration — no custom filesystem driver.

## Requirements

- macOS 14+
- [macFUSE](https://macfuse.github.io/) 5.2+ (5.3.1+ dev on macOS 27)
- [ntfs-3g-mac](https://github.com/gromgit/fuse) via Homebrew

## Build

```bash
git clone https://github.com/3aim-debug/ntfs-for-mac.git
cd ntfs-for-mac
make app
open "build/NTFS For Mac.app"
```

First launch: right-click the app → **Open** (ad-hoc signed local build).

## Driver install

**macOS 27+**

```bash
brew uninstall --cask macfuse 2>/dev/null || true
brew install --cask macfuse@dev
brew tap gromgit/fuse
brew trust --formula gromgit/fuse/ntfs-3g-mac
brew install gromgit/fuse/ntfs-3g-mac
```

**Earlier macOS**

```bash
brew install --cask macfuse
brew tap gromgit/fuse
brew install gromgit/fuse/ntfs-3g-mac
```

Allow the macFUSE extension in **System Settings → Privacy & Security** if prompted.

## Usage

Select an NTFS volume → **Mount Read/Write** → enter your password. The volume shows up at `/Volumes/<name>`.

Mount uses ntfs-3g with async I/O. The app writes `user_allow_other` to `/etc/fuse.conf` on first mount so Finder can see the volume.

## Layout

```
Sources/NTFSAccessCore/   Drive list, NTFS detection, mount logic
Sources/NTFSAccessApp/    SwiftUI
Scripts/build_app.sh      Builds NTFS For Mac.app
```

## Troubleshooting

| Issue | What to try |
|-------|-------------|
| Mount OK but invisible in Finder | Quit app (Cmd+Q), reopen, remount |
| Unclean filesystem | Remount (runs `ntfsfix`); or shut down Windows with Fast Startup off |
| Hibernation / hiberfil.sys | Full Windows shutdown, not Restart |
| Dirty NTFS from Windows | `chkdsk` from Windows if `ntfsfix` isn't enough |

## License

MIT
