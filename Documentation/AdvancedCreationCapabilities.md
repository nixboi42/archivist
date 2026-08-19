# Advanced creation capability verification

This matrix is evidence for the single authoritative policy implemented by
`AuthoritativeCapabilities`; it is not a second runtime capability table.

## Verified backend builds

- Bundled 7-Zip: `7zz 26.02` (arm64), verified with `7zz i`, targeted help, and
  create/list/test/extract probes using the exact bundled executable.
- Libarchive: `3.8.4`, pinned by the package and verified through its public C API.

## Exposed policy

| Format | Backend | Verified creation controls |
| --- | --- | --- |
| 7z | 7zz | semantic level, Copy/LZMA2/LZMA/PPMd/BZip2, dictionary, word size, solid mode, threads, AES password/header encryption, volume splitting |
| ZIP | 7zz | semantic level, Copy/Deflate/Deflate64/BZip2/LZMA/PPMd, applicable dictionary/word presets, threads, password, volume splitting |
| TAR, CPIO | libarchive | container creation only |
| TAR.GZ, GZip | libarchive | compression level |
| TAR.BZ2, BZip2 | libarchive | compression levels 1–9 (no store) |
| TAR.XZ, XZ | libarchive | compression level and thread count |

TAR.ZST remains disabled for the bundled libarchive configuration. Unknown or
unverified controls remain unavailable. Standalone stream formats retain the
existing one-input restriction.

## Translation notes

7zz options are emitted deterministically as `-mx`, `-m0`, `-md`, `-mfb`,
`-ms`, `-mmt`, `-mhe`, and `-v`. Passwords continue through the existing PTY
transport and never appear in process arguments. Libarchive levels and XZ
threads are applied with `archive_write_set_filter_option`; unsupported options
are rejected before filesystem or backend work rather than silently ignored.

Multipart output is committed as one crash-safe archive set. The public names
are `Base.ext.001`, `.002`, and so on. Only `.001` is an entry point; selecting
a later volume yields a structured first-volume diagnostic. A numbered gap is
reported as `MISSING_ARCHIVE_VOLUME` before invoking 7zz where possible.

## Primary references

- Exact bundled executable: `Archivist.app/Contents/Helpers/7zz i`
- Libarchive API: <https://github.com/libarchive/libarchive/blob/master/libarchive/archive.h>
- Libarchive write options: <https://manpages.debian.org/unstable/libarchive-dev/archive_write_set_options.3.en.html>
