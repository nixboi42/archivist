# Local Finder integration testing

The generated development product is `DevelopmentBuild/Archivist.app`. It is locally signed with the installed Apple Development identity for team `J6UMA79JLS`; no Developer ID, notarization, stapling, or release packaging is involved.

1. For a free Personal Team, rebuild with `Development/build-development-app.sh --personal-team`. For a provisioned full team, see `Documentation/PersonalTeamDevelopment.md` and use `--full-team` with both provisioning-profile paths.
2. Run `Development/install-development-app.sh`. It removes the former development app only when its bundle identifier is the known former identifier, installs the new bundle, registers its extension, and restarts Finder.
3. Launch `/Applications/Archivist.app` once. Personal mode uses the explicitly marked development URL fallback and has no App Group entitlement. Full-team mode uses App Group `group.J6UMA79JLS.com.archivist.shared`.
4. Enable **Archivist Finder Integration** in **System Settings → General → Login Items & Extensions → Extensions → File Providers & Finder Extensions**. On older macOS releases, use **Privacy & Security → Extensions → Finder Extensions**. The command-line equivalent for this local build is `pluginkit -e use -i com.keremgurevin.Archivist.FinderSync`.
5. Desktop and Downloads are the Personal Team defaults. Full-team mode also supports the monitored-root settings stored in the App Group. Coverage is never global.
6. Confirm registration with `pluginkit -m -A -D -i com.keremgurevin.Archivist.FinderSync`.
7. If Finder has cached an old extension state, run `killall Finder` once, then reopen the monitored folder.

Smoke test: put a ZIP in Desktop or Downloads, right-click it, choose **Archivist → Open Archive**, then try **Extract Here** and **Extract to “Archive Name”**. Right-click ordinary files and verify the create actions. A folder not listed in Settings should not show the menu.

If the identity differs on another development Mac, set `ARCHIVIST_SIGNING_IDENTITY` to the SHA-1 identifier of the appropriate Apple Development certificate. Do not replace full-team signing with ad-hoc signing: an ad-hoc signature has no team identifier and cannot use the provisioned App Group correctly.
