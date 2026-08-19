#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
DERIVED_DATA=${SCRIPT_DIR}/DerivedData
OUTPUT_APP=${PROJECT_ROOT}/DevelopmentBuild/Archivist.app
BUILT_APP=${DERIVED_DATA}/Build/Products/Debug/Archivist.app
SIGNING_IDENTITY=${ARCHIVIST_SIGNING_IDENTITY:-AE8481AD38CDE31B5ACBA2415395B939F6079F19}
SEVEN_ZIP_PATH=${ARCHIVIST_7ZZ_PATH:-}

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
    if [[ -z "${ARCHIVIST_APP_PROFILE:-}" || -z "${ARCHIVIST_EXTENSION_PROFILE:-}" ||
          -z "${ARCHIVIST_DEVELOPMENT_TEAM:-}" || -z "${ARCHIVIST_APP_GROUP_IDENTIFIER:-}" ]]; then
      print -u2 "error: --full-team requires ARCHIVIST_APP_PROFILE, ARCHIVIST_EXTENSION_PROFILE, ARCHIVIST_DEVELOPMENT_TEAM, and ARCHIVIST_APP_GROUP_IDENTIFIER"
      exit 64
    fi
    if [[ "${ARCHIVIST_APP_GROUP_IDENTIFIER}" != "group.${ARCHIVIST_DEVELOPMENT_TEAM}."* ]]; then
      print -u2 "error: ARCHIVIST_APP_GROUP_IDENTIFIER must use the ARCHIVIST_DEVELOPMENT_TEAM prefix"
      exit 64
    fi
    ;;
  *)
    print -u2 "usage: $0 --personal-team | --full-team"
    exit 64
    ;;
esac

if [[ -z "${SEVEN_ZIP_PATH}" || ! -f "${SEVEN_ZIP_PATH}" || ! -x "${SEVEN_ZIP_PATH}" ]]; then
  print -u2 "error: ARCHIVIST_7ZZ_PATH must point to an executable pinned 7-Zip 26.02 7zz binary"
  exit 64
fi
EXPECTED_7ZZ_SHA256=ecf1725c92260f5565d3c549a835407c6be7b8baf0d0dcc3e472599f81a4897a
ACTUAL_7ZZ_SHA256=$(shasum -a 256 "${SEVEN_ZIP_PATH}" | awk '{print $1}')
if [[ "${ACTUAL_7ZZ_SHA256}" != "${EXPECTED_7ZZ_SHA256}" ]]; then
  print -u2 "error: ARCHIVIST_7ZZ_PATH does not match the pinned 7-Zip 26.02 checksum"
  exit 64
fi

if [[ "${HANDOFF_MODE}" == "app-group" ]]; then
  GENERATED_ENTITLEMENTS_DIR="${DERIVED_DATA}/GeneratedEntitlements"
  mkdir -p "${GENERATED_ENTITLEMENTS_DIR}"
  APP_ENTITLEMENTS_GENERATED="${GENERATED_ENTITLEMENTS_DIR}/Archivist.entitlements"
  EXTENSION_ENTITLEMENTS_GENERATED="${GENERATED_ENTITLEMENTS_DIR}/ArchivistFinderSync.entitlements"
  cp "${APP_ENTITLEMENTS}" "${APP_ENTITLEMENTS_GENERATED}"
  cp "${EXTENSION_ENTITLEMENTS}" "${EXTENSION_ENTITLEMENTS_GENERATED}"
  plutil -replace com.apple.security.application-groups -xml "<array><string>${ARCHIVIST_APP_GROUP_IDENTIFIER}</string></array>" "${APP_ENTITLEMENTS_GENERATED}"
  plutil -replace com.apple.security.application-groups -xml "<array><string>${ARCHIVIST_APP_GROUP_IDENTIFIER}</string></array>" "${EXTENSION_ENTITLEMENTS_GENERATED}"
  APP_ENTITLEMENTS="${APP_ENTITLEMENTS_GENERATED}"
  EXTENSION_ENTITLEMENTS="${EXTENSION_ENTITLEMENTS_GENERATED}"
fi

cd "${PROJECT_ROOT}"
xcodegen generate --spec Development/project.yml --project Development --project-root .
xcodebuild -quiet \
  -project Development/ArchivistDevelopment.xcodeproj \
  -scheme Archivist \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination 'platform=macOS,arch=arm64' \
  ARCHIVIST_FINDER_HANDOFF_MODE="${HANDOFF_MODE}" \
  ARCHIVIST_APP_GROUP_IDENTIFIER="${ARCHIVIST_APP_GROUP_IDENTIFIER:-}" \
  ARCHIVIST_7ZZ_PATH="${SEVEN_ZIP_PATH}" \
  DEVELOPMENT_TEAM="${ARCHIVIST_DEVELOPMENT_TEAM:-}" \
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
  if [[ "${MAIN_ENTITLEMENTS}" != *"${ARCHIVIST_APP_GROUP_IDENTIFIER}"* ]]; then
    print -u2 "error: full-team build is missing its Finder handoff App Group"
    exit 1
  fi
  if [[ "${EXTENSION_ENTITLEMENTS_EFFECTIVE}" != *"com.apple.security.app-sandbox"* ||
        "${EXTENSION_ENTITLEMENTS_EFFECTIVE}" != *"${ARCHIVIST_APP_GROUP_IDENTIFIER}"* ]]; then
    print -u2 "error: full-team Finder extension entitlements are incomplete"
    exit 1
  fi
fi
MAIN_SIGNATURE=$(codesign -dv --verbose=4 "${OUTPUT_APP}" 2>&1)
if [[ "${HANDOFF_MODE}" == "app-group" && "${MAIN_SIGNATURE}" != *"TeamIdentifier=${ARCHIVIST_DEVELOPMENT_TEAM}"* ]]; then
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
