# libarchive Provenance

## Component

libarchive static library

## Version

3.8.4

## Upstream

libarchive  
https://www.libarchive.org/

Release:  
https://github.com/libarchive/libarchive/releases/tag/v3.8.4

Source archive SHA-256:

`c7b847b57feacf5e182f4d14dd6cae545ac6843d55cb725f58e107cdf1c9ad73`

## Usage in Archivist

Archivist statically incorporates libarchive as an archive backend.

The bundled build targets:

- Apple Silicon (arm64)
- macOS 14 or later

Archivist uses libarchive for verified TAR-family formats, compression
streams, CPIO, and other operations explicitly enabled by Archivist's
authoritative capability policy.

A C interoperability layer contains direct libarchive API interaction and
provides deterministic cleanup of native archive resources.

Archive operations continue through Archivist's normal security and
filesystem boundaries.

## Vendored Artifact

The static library is stored at:

`Vendor/Libarchive/Libarchive.xcframework/macos-arm64/libarchive.a`

libarchive is statically linked into Archivist. There is therefore no
separate libarchive dynamic library or executable in the installed
application bundle.

## Verification

SHA-256 of the vendored `libarchive.a`:

`a3ff3898008dbf43d1930dc5e0c2f4aa7857a5b43ffd1bc6583e29311d3c5ec6`

The vendored static library and the corresponding build-output
`libarchive.a` were verified to have identical SHA-256 hashes.

Archivist has no Homebrew runtime dependency for libarchive.

The pinned build disables XML, crypto, LZ4, Zstandard, LZO, and
external-program filters. Stable compression libraries supplied by macOS,
including liblzma, remain system dependencies.

The source archive and upstream checksum manifest are retained beside the
artifact. `BuildHeaders/` contains the XZ Utils 5.8.3 public headers used to
produce it, with the corresponding license in `XZ-LICENSE`. The checked-in
headers avoid a build-time dependency on a local Homebrew installation.

Rebuild from `Vendor/Libarchive` with:

`./build-pinned.sh`

The script verifies the source archive SHA-256 before compiling.

## Capability Policy

Capabilities exposed by Archivist are based on the pinned and tested build,
not merely on formats theoretically supported by upstream libarchive.

Formats or filters that have not been verified with the bundled build remain
disabled.

## License

libarchive is third-party software and is not covered by Archivist's MIT
License.

The applicable upstream license is preserved in:

`Vendor/Libarchive/LICENSE`

Binary distributions of Archivist incorporating libarchive must preserve
the applicable license notices.

## Updating

When updating libarchive:

1. Obtain the source release from the official upstream project.
2. Verify the source artifact and checksum.
3. Review upstream licensing changes.
4. Build the static library for the supported macOS architecture(s).
5. Update the version and SHA-256 recorded here.
6. Update `LICENSE` and `XZ-LICENSE` if necessary.
7. Run Archivist's backend, format, corruption, Unicode, large-file,
   cancellation, security, and integration tests.
8. Enable new capabilities only after explicit verification.
