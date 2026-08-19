# Archivist

A native archive manager for macOS, built to provide powerful archive management without sacrificing a clean, Mac-native experience.

Archivist combines broad format support with secure extraction, advanced compression controls, archive browsing, Finder integration, and native macOS workflows.

> **Status:** Archivist is under active development and is not yet a production release.

## Features

- Native macOS interface built with SwiftUI and AppKit
- Browse archives without extracting them first
- Drag files and folders directly from an open archive into Finder
- Finder context-menu integration
- Create, extract, list, and test archives
- Advanced compression options with a simple default interface
- Split/multipart archive creation and extraction
- Password-protected and encrypted archives
- 7z filename/header encryption
- Compression method, dictionary size, solid mode, thread count, and volume controls
- Quick Look integration for archive contents
- Background extraction and creation with a Jobs window
- Native conflict, password, and error dialogs
- Command-line interface
- Dedicated XIP/XAR/AppleArchive support

## Archive Backends

Archivist uses several backends rather than forcing every format through one implementation:

- **7-Zip (`7zz`)** — 7z, ZIP-family formats, RAR extraction, CAB, ARJ, and related formats
- **libarchive** — TAR, CPIO, GZip, BZip2, XZ, and Unix-oriented archive formats
- **Native Apple-format stack** — XIP, XAR, and AppleArchive

Backend selection is capability-driven and transparent to the user.

## Security

Archives are treated as untrusted input.

Archivist includes protections for:

- Path traversal
- Absolute and malformed archive paths
- Unicode filename collisions
- Unsafe symbolic and hard links
- Archive bombs and excessive expansion
- Disk-space exhaustion
- Partial or interrupted extraction
- Corrupted archives
- Unsafe destination replacement

Extraction is planned and validated before files are materialized.

Password handling for `7zz` uses a dedicated PTY transport. Passwords are not passed through command-line arguments, environment variables, or temporary files.

Archive creation and extraction use staged, crash-safe filesystem operations where appropriate.

## Advanced Compression

Archivist provides a simple creation interface by default, with additional controls available when supported by the selected format.

Advanced options include:

- Compression level
- Compression method
- Dictionary size
- Word size / fast bytes
- Solid compression
- Thread count
- Data encryption
- Filename/header encryption
- Split-volume size

Unsupported combinations are rejected before invoking the archive backend.

## Split Archives

Archivist supports creation and handling of multipart archives such as:

```text
Archive.7z.001
Archive.7z.002
Archive.7z.003
```

The first volume acts as the archive entry point. Missing volumes are detected and reported explicitly.

Multipart creation is staged and committed as a logical transaction to avoid leaving incomplete final archive sets after failures or cancellation.

## Finder Integration

Archivist provides Finder actions such as:

```text
Archivist ▸
    Open Archive
    Extract Here
    Extract to…
    Extract to "Archive Name"
```

For ordinary files and folders:

```text
Archivist ▸
    Create 7z Archive
    Create ZIP Archive
    Create Archive…
```

Finder Sync operates on configured monitored directories; macOS does not provide Finder Sync extensions with guaranteed global context-menu coverage.

Desktop and Downloads are used as development defaults.

## Drag and Drop

Files and folders can be dragged directly from an open archive into Finder.

Archivist uses native macOS file promises and lazily extracts only the requested archive contents into private temporary staging.

This supports:

- Individual files
- Multiple selections
- Folders
- Mixed file/folder selections
- Unicode filenames
- Encrypted archives
- Multipart archives

The final destination remains under Finder's control, including destination conflict handling.

## Command Line

Archivist includes the `archiveutil` command-line interface for listing, extracting, creating, and testing archives.

```bash
archiveutil list archive.7z
archiveutil extract archive.7z
archiveutil test archive.7z
```

Advanced creation settings are exposed through semantic CLI options rather than arbitrary backend command-line arguments.

Passwords are accepted through protected standard input rather than command-line arguments.

## Architecture

Archivist is divided into capability-driven layers:

```text
macOS GUI / Finder / CLI
          │
    Application Layer
          │
 ArchiveBackendRegistry
      ┌───┼──────────┐
      │   │          │
    7zz libarchive Apple formats
      │   │          │
      └───┼──────────┘
          │
 Security + Filesystem
```

The UI does not directly invoke archive backends.

Core components include:

- `ArchiveBackendRegistry`
- `SecureExtractionPlanner`
- `CrashSafeFilesystem`
- `FormatDetector`
- `JobQueue`
- Application-level browse, extract, create, test, preview, and drag-export use cases

## Requirements

- macOS 14 or later
- Apple Silicon

Archivist is currently developed and tested primarily as a local development application.

## Building

The repository contains the Swift packages, development configuration, vendored dependency metadata, and scripts required to build Archivist.

A Personal Team development build can be produced using the development build tooling in the repository.

Personal Team builds use a development-only Finder communication fallback because the full production Finder architecture relies on an App Group.

The production architecture remains:

```text
Finder Sync
    ↓
App Group request
    ↓
opaque request identifier
    ↓
Archivist
    ↓
Application layer
```

## Current Limitations

Archivist is still under development.

Notable intentionally deferred work includes:

- Editing/modifying existing archives
- Legacy pbzx XIP support
- External RAR creation
- Some additional archive formats
- Final Developer ID signing
- Notarization and stapling
- Release DMG packaging
- Production update infrastructure

RAR creation is not implemented in the bundled open-source backend.

## Development

The project has an extensive automated test suite covering the domain model, archive backends, security boundaries, filesystem behavior, Finder integration, CLI, and application layer.

When adding format support or backend functionality, capabilities should be added to the authoritative capability policy rather than duplicated in UI-specific tables.

Security-sensitive archive operations should continue to flow through the existing security and filesystem boundaries.

## License

See [`LICENSE`](LICENSE) for the project's license.

Third-party components retain their respective licenses and notices.
