# 7-Zip Provenance

## Component

7-Zip command-line executable (`7zz`)

## Version

26.02

## Upstream Project

7-Zip  
https://www.7-zip.org/

Copyright © Igor Pavlov and contributors.

## Usage in Archivist

Archivist bundles the macOS `7zz` executable and invokes it as a managed
subprocess for archive operations supported by the 7-Zip backend.

Archivist does not execute archive commands through a shell.

The bundled executable is used for formats and operations assigned to the
7-Zip backend by Archivist's authoritative capability policy.

## Password Transport

For password-protected operations, Archivist communicates with `7zz` through
a managed pseudo-terminal (PTY).

Passwords are not supplied through:

- command-line arguments containing the password
- environment variables
- temporary password files

The PTY has terminal echo disabled before the child process is spawned.

## Bundling

The `7zz` executable is bundled with the Archivist application and is expected
to be available from the application's helper resources at runtime.

Archivist may also support an explicitly configured external `7zz` executable
for development or user-selected configurations.

## Verification

The bundled executable is pinned to the version documented above.

Release/build tooling should verify the expected executable and version before
packaging.

If a SHA-256 checksum is maintained for the downloaded upstream artifact or
bundled executable, it should be recorded here and verified by the build
process.

## License

7-Zip is third-party software and is not covered by Archivist's MIT License.

The licensing information distributed with the bundled 7-Zip version is
preserved verbatim in:

`Vendor/SevenZip/LICENSE.txt`

That notice includes the applicable GNU LGPL terms and notices concerning
BSD-licensed components and the unRAR license restriction.

Binary distributions of Archivist that contain `7zz` must also include the
applicable 7-Zip licensing information.

## Updating

When updating 7-Zip:

1. Obtain the new release from the official upstream project.
2. Verify the downloaded artifact.
3. Update the bundled executable.
4. Update the version recorded in this file.
5. Update any recorded cryptographic hashes.
6. Replace `LICENSE.txt` with the licensing information distributed with the
   new version if it has changed.
7. Run Archivist's backend, password-transport, security, and integration
   tests before accepting the update.
