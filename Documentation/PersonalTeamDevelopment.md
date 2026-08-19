# Personal Team Finder development

Archivist's production Finder handoff remains:

`Finder Sync → App Group request file → opaque UUID activation → main app`

Free Personal Team provisioning does not provide a usable App Group shared by the sandboxed Finder Sync extension and the unsandboxed containing app. The local build therefore has an explicit, development-only transport selected at build time.

## Why the fallback is a custom URL

The alternatives were evaluated against the sandbox actually used by the extension:

- A Unix-domain socket still needs a filesystem location discoverable and writable by both processes. Without the provisioned App Group, the sandboxed extension cannot use the app's cache or Application Support directory.
- NSXPC requires a shared, provisioned Mach service or an endpoint that can first be transferred through another working channel.
- Distributed notifications do not safely deliver a request to an app that is not running and provide neither private payload transport nor reliable request delivery.
- A localhost listener adds port discovery, authentication, collision, and lifecycle problems; loopback is not inherently private to one process or user.

As the last-resort development mechanism permitted by the architecture, the extension opens a bounded `archivist://finder-dev-request/...` URL carrying the existing JSON request as base64url. Requests retain UUID, age, action cardinality, file-URL, maximum-count, maximum-size, and in-process replay validation.

This URL necessarily contains encoded filesystem paths. It contains no credentials, is not persisted by Archivist, and is limited to 32 URLs and 32 KiB. It is less private than the production App Group design and must not be treated as production-secure IPC.

> This transport is for local development only and is forbidden in Release builds.

## Build modes

Personal Team development:

```sh
Development/build-development-app.sh --personal-team
```

This signs the unsandboxed app without App Group entitlements and signs the sandboxed Finder extension with only its sandbox entitlement. The generated product advertises `personal-team-development` in both component Info plists.

Full-team development:

```sh
ARCHIVIST_APP_PROFILE=/path/to/app.provisionprofile \
ARCHIVIST_EXTENSION_PROFILE=/path/to/extension.provisionprofile \
Development/build-development-app.sh --full-team
```

This uses the production App Group transport and requires matching provisioning profiles. Release plus `personal-team-development` is rejected by both the project build phase and the transport build guard test.

## Install and test

1. Run `Development/install-development-app.sh`, then launch `/Applications/Archivist.app` once.
2. Enable `Archivist Finder Integration` in System Settings → General → Login Items & Extensions → Extensions → File Providers & Finder Extensions.
3. Confirm registration with `pluginkit -m -A -D -i com.keremgurevin.Archivist.FinderSync`.
4. If necessary, enable it with `pluginkit -e use -i com.keremgurevin.Archivist.FinderSync` and restart Finder with `killall Finder`.

## Development rename migration

Archivist was formerly named ArchiveUtility during development. Version 1 of the
preference migration copies only the known preference keys from the former bundle
domain, never arbitrary defaults. The old URL scheme is intentionally not retained;
stale development requests expire and Finder emits only `archivist://` requests.
5. On Desktop or Downloads, right-click a ZIP and test Open Archive and Extract Here. Select ordinary files and test Create ZIP. Repeat extraction and creation with multiple selections.
6. Launch the app normally and leave it idle; neither normal startup nor Settings should request SystemPolicyAppData or Full Disk Access.

Personal mode monitors Desktop and Downloads directly. Custom monitored roots remain a full-team/App Group feature because their configuration cannot be shared with the extension without reintroducing the provisioning problem.
