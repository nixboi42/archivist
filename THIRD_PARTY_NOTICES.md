# Third-Party Notices

Archivist incorporates and/or distributes third-party software that is
licensed separately from Archivist.

Archivist itself is licensed under the MIT License. See [LICENSE](LICENSE).

## 7-Zip

Archivist distributes the 7-Zip command-line executable (`7zz`) as an archive
backend.

- Version: 26.02
- Project: 7-Zip
- Author: Igor Pavlov
- Website: https://www.7-zip.org/

7-Zip and its components are distributed under their respective upstream
licenses. See [Vendor/SevenZip/LICENSE](Vendor/SevenZip/LICENSE) for
the licensing information distributed with the version of 7-Zip used by
Archivist.

Additional provenance and version information is available in
[Vendor/SevenZip/PROVENANCE.md](Vendor/SevenZip/PROVENANCE.md).

## libarchive

Archivist incorporates libarchive as an archive backend.

- Version: 3.8.4
- Project: libarchive
- Website: https://www.libarchive.org/

libarchive is distributed under its upstream license. See
[Vendor/Libarchive/LICENSE](Vendor/Libarchive/LICENSE).

Additional provenance and version information is available in
[Vendor/Libarchive/PROVENANCE.md](Vendor/Libarchive/PROVENANCE.md).

## XZ Utils headers

Archivist distributes a small set of XZ Utils headers with its pinned
libarchive build inputs. They are covered by the upstream 0BSD license; see
[Vendor/Libarchive/XZ-LICENSE](Vendor/Libarchive/XZ-LICENSE).

## Apple System Frameworks and Tools

Archivist uses APIs and system components supplied by macOS, including Apple
frameworks used for native application integration and supported Apple archive
formats.

These components are supplied by Apple as part of macOS and are not
redistributed by Archivist as third-party open-source components.

---

Third-party software remains subject to its respective license terms.
Archivist's MIT License does not replace or modify those terms.
