# Microfiche

Microfiche is a native macOS image library for browsing folders in place. It links to local folders, iCloud Drive, and external volumes without copying the source files.

## Features

- Responsive Grid and List views
- Adjustable thumbnail sizing
- Multiple linked folders and remembered external drives
- iCloud Drive naming, placeholder status, and download recovery
- Contact sheets with drag and drop
- Search by filename, path, tags, labels, comments, and source
- File-type and tag filters
- Local tags, labels, comments, and source metadata
- EXIF/ImageIO camera and exposure details
- Quick preview and focused detail view
- Rename, Reveal in Finder, Open, Copy Path, Share, and Move to Trash
- Keyboard navigation and macOS accessibility support

## Development

Open `Microfiche.xcodeproj` in Xcode and run the **Microfiche** scheme on macOS.

Before changing user-visible behavior, read [TESTING.md](TESTING.md). A successful build verifies compilation only; interaction changes must also cover every affected state and transition, including repeated use without relaunching. Repository-wide contributor rules are in [AGENTS.md](AGENTS.md).

Command-line verification with the Xcode beta toolchain used by this repository:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Microfiche.xcodeproj \
  -scheme Microfiche \
  -configuration Debug \
  -destination 'platform=macOS' test
```

The Debug configuration uses local ad-hoc signing so revoked or unavailable development certificates do not prevent local builds. Configure a valid Apple Development team for distribution builds.
