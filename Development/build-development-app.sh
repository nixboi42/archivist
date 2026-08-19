#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
DERIVED_DATA=${SCRIPT_DIR}/DerivedData
OUTPUT_APP=${PROJECT_ROOT}/DevelopmentBuild/Archivist.app
BUILT_APP=${DERIVED_DATA}/Build/Products/Debug/Archivist.app
SIGNING_IDENTITY=${ARCHIVIST_SIGNING_IDENTITY:-AE8481AD38CDE31B5ACBA2415395B939F6079F19}

case "${1:-}" in
  --personal-team)
    HANDOFF_MODE=personal-team-development
    APP_ENTITLEMENTS=Development/App/ArchivistPersonalTeam.entitlements
    EXTENSION_ENTITLEMENTS=Development/FinderSync/ArchivistFinderSyncPersonalTeam.entitlements
    ;;
  --full-team)
    HANDOFF_MODE=app-group
    APP_ENTITLEMENTS=Development/App/Archivist.entitlements
    EXTENSION_ENTITLEMENTS=Development/FinderSync/ArchivistFinderSync.entitlements
    if [[ -z "${ARCHIVIST_APP_PROFILE:-}" || -z "${ARCHIVIST_EXTENSION_PROFILE:-}" ]]; then
      print -u2 "error: --full-team requires ARCHIVIST_APP_PROFILE and ARCHIVIST_EXTENSION_PROFILE"
      exit 64
    fi
    ;;
  *)
    print -u2 "usage: $0 --personal-team | --full-team"
    exit 64
    ;;
esac

cd "${PROJECT_ROOT}"
xcodegen generate --spec Development/project.yml --project Development --project-root .
xcodebuild -quiet \
  -project Development/ArchivistDevelopment.xcodeproj \
  -scheme Archivist \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination 'platform=macOS,arch=arm64' \
  ARCHIVIST_FINDER_HANDOFF_MODE="${HANDOFF_MODE}" \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "${OUTPUT_APP}"
mkdir -p "${OUTPUT_APP:h}"
ditto "${BUILT_APP}" "${OUTPUT_APP}"

if [[ "${HANDOFF_MODE}" == "app-group" ]]; then
  cp "${ARCHIVIST_APP_PROFILE}" "${OUTPUT_APP}/Contents/embedded.provisionprofile"
  cp "${ARCHIVIST_EXTENSION_PROFILE}" "${OUTPUT_APP}/Contents/PlugIns/ArchivistFinderSync.appex/Contents/embedded.provisionprofile"
fi

codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${OUTPUT_APP}/Contents/Helpers/7zz"
for binary in \
  "${OUTPUT_APP}/Contents/PlugIns/ArchivistFinderSync.appex/Contents/MacOS/ArchivistFinderSync.debug.dylib" \
  "${OUTPUT_APP}/Contents/PlugIns/ArchivistFinderSync.appex/Contents/MacOS/__preview.dylib"; do
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${binary}"
done
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none \
  --entitlements "${EXTENSION_ENTITLEMENTS}" \
  "${OUTPUT_APP}/Contents/PlugIns/ArchivistFinderSync.appex"
for binary in \
  "${OUTPUT_APP}/Contents/MacOS/Archivist.debug.dylib" \
  "${OUTPUT_APP}/Contents/MacOS/__preview.dylib"; do
  codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none "${binary}"
done
codesign --force --sign "${SIGNING_IDENTITY}" --timestamp=none \
  --entitlements "${APP_ENTITLEMENTS}" \
  "${OUTPUT_APP}"
codesign --verify --deep --strict --verbose=2 "${OUTPUT_APP}"

MAIN_ENTITLEMENTS=$(codesign -d --entitlements - "${OUTPUT_APP}" 2>&1)
EXTENSION_PATH="${OUTPUT_APP}/Contents/PlugIns/ArchivistFinderSync.appex"
EXTENSION_ENTITLEMENTS_EFFECTIVE=$(codesign -d --entitlements - "${EXTENSION_PATH}" 2>&1)
if [[ "${MAIN_ENTITLEMENTS}" == *"com.apple.security.app-sandbox"* ]]; then
  print -u2 "error: the main application must remain unsandboxed"
  exit 1
fi
if [[ "${HANDOFF_MODE}" == "personal-team-development" ]]; then
  if [[ "${MAIN_ENTITLEMENTS}" == *"com.apple.security.application-groups"* ]]; then
    print -u2 "error: Personal Team build must not carry the production App Group"
    exit 1
  fi
  if [[ "${EXTENSION_ENTITLEMENTS_EFFECTIVE}" != *"com.apple.security.app-sandbox"* ||
        "${EXTENSION_ENTITLEMENTS_EFFECTIVE}" == *"com.apple.security.application-groups"* ]]; then
    print -u2 "error: Personal Team Finder extension must be sandboxed without an App Group"
    exit 1
  fi
else
  if [[ "${MAIN_ENTITLEMENTS}" != *"group.J6UMA79JLS.com.archivist.shared"* ]]; then
    print -u2 "error: full-team build is missing its Finder handoff App Group"
    exit 1
  fi
  if [[ "${EXTENSION_ENTITLEMENTS_EFFECTIVE}" != *"com.apple.security.app-sandbox"* ||
        "${EXTENSION_ENTITLEMENTS_EFFECTIVE}" != *"group.J6UMA79JLS.com.archivist.shared"* ]]; then
    print -u2 "error: full-team Finder extension entitlements are incomplete"
    exit 1
  fi
fi
MAIN_SIGNATURE=$(codesign -dv --verbose=4 "${OUTPUT_APP}" 2>&1)
if [[ "${MAIN_SIGNATURE}" != *"TeamIdentifier=J6UMA79JLS"* ]]; then
  print -u2 "error: local development signature lacks the App Group team identifier"
  exit 1
fi
PLIST_MODE=$(plutil -extract ArchivistFinderTransport raw "${OUTPUT_APP}/Contents/Info.plist")
EXTENSION_PLIST_MODE=$(plutil -extract ArchivistFinderTransport raw "${EXTENSION_PATH}/Contents/Info.plist")
if [[ "${PLIST_MODE}" != "${HANDOFF_MODE}" || "${EXTENSION_PLIST_MODE}" != "${HANDOFF_MODE}" ]]; then
  print -u2 "error: Finder transport mode does not match the requested build configuration"
  exit 1
fi
print "Built ${OUTPUT_APP}"
