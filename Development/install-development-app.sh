#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
SOURCE_APP=${PROJECT_ROOT}/DevelopmentBuild/Archivist.app
INSTALLED_APP=/Applications/Archivist.app
FORMER_APP=/Applications/ArchiveUtility.app
FORMER_BUNDLE_ID=com.keremgurevin.ArchiveUtility
EXTENSION_ID=com.keremgurevin.Archivist.FinderSync

[[ -d "${SOURCE_APP}" ]] || { print -u2 "error: build ${SOURCE_APP} first"; exit 66; }
killall Archivist 2>/dev/null || true
killall ArchiveUtility 2>/dev/null || true
killall ArchivistFinderSync 2>/dev/null || true
killall ArchiveFinderSync 2>/dev/null || true

if [[ -d "${FORMER_APP}" ]]; then
  OLD_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${FORMER_APP}/Contents/Info.plist" 2>/dev/null || true)
  if [[ "${OLD_ID}" == "${FORMER_BUNDLE_ID}" ]]; then rm -rf "${FORMER_APP}"; fi
fi
rm -rf "${INSTALLED_APP}"
ditto "${SOURCE_APP}" "${INSTALLED_APP}"
pluginkit -a "${INSTALLED_APP}/Contents/PlugIns/ArchivistFinderSync.appex"
pluginkit -e use -i "${EXTENSION_ID}"
killall Finder 2>/dev/null || true
print "Installed ${INSTALLED_APP}"
