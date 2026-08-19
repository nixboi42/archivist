# 7-Zip Provenance

## Component

7-Zip command-line executable (`7zz`)

## Version

26.02

## Upstream

7-Zip  
https://www.7-zip.org/

Copyright © Igor Pavlov and contributors.

## Usage in Archivist

Archivist bundles the macOS `7zz` executable and invokes it as a managed
subprocess for supported archive operations.

The bundled executable is used primarily for 7z and ZIP-family operations,
as well as supported extraction operations for formats such as RAR, CAB,
and ARJ.

Archivist executes `7zz` directly without a shell.

For password-protected operations, Archivist uses a managed pseudo-terminal
(PTY) with terminal echo disabled. Passwords are not passed in process
arguments, environment variables, or temporary files.

## Bundling

The installed executable is located at:

`/Applications/Archivist.app/Contents/Helpers/7zz`

The bundled executable reports 7-Zip version 26.02.

## Verification

SHA-256 of the bundled `7zz` executable:

`ecf1725c92260f5565d3c549a835407c6be7b8baf0d0dcc3e472599f81a4897a`

This checksum identifies the exact `7zz` executable bundled with the
verified Archivist development build.

## License

7-Zip is third-party software and is not covered by Archivist's MIT License.

The licensing information accompanying the bundled version is preserved in:

`Vendor/SevenZip/LICENSE`

Binary distributions of Archivist containing `7zz` must reproduce the
applicable 7-Zip licensing information.

## Updating

When updating 7-Zip:

1. Obtain the release from the official upstream project.
2. Verify the downloaded artifact.
3. Replace the bundled executable.
4. Update the version and SHA-256 recorded here.
5. Update `LICENSE` if the upstream licensing information changed.
6. Run Archivist's backend, PTY/password, security, and integration tests.
