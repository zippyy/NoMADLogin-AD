#!/bin/bash
# Build NoMAD Login AD with a current macOS SDK after rebuilding its dependency.
# Usage:
#   CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
#   DEVELOPMENT_TEAM=TEAMID bash Scripts/build-macos27.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/Config/ModernMacOS.xcconfig"
PROJECT="${ROOT_DIR}/NoMADLogin-AD.xcodeproj"
SCHEME="NoMADLoginAD"
DERIVED_DATA="${ROOT_DIR}/build/NoMADLoginAD-DerivedData"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
TEAM_ID="${DEVELOPMENT_TEAM:-}"

[[ -f "${CONFIG_FILE}" ]] || { echo "Missing ${CONFIG_FILE}" >&2; exit 1; }
[[ -d "${PROJECT}" ]] || { echo "Missing ${PROJECT}" >&2; exit 1; }

MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}" \
  bash "${ROOT_DIR}/Scripts/bootstrap-adauth.sh"

# Swift 5 removed String.characters. The old DEPNotify tracker code only uses
# it to create NSRegularExpression ranges, where UTF-16 length is the correct
# NSString-compatible value.
if grep -R "\.characters\.count" "${ROOT_DIR}/Notify/Tracker.swift" >/dev/null; then
  echo "Patching Swift 5 String.characters.count compatibility"
  sed -i '' 's/\.characters\.count/.utf16.count/g' "${ROOT_DIR}/Notify/Tracker.swift"
fi

rm -rf "${DERIVED_DATA}"
BUILD_ARGS=(
  -project "${PROJECT}"
  -scheme "${SCHEME}"
  -configuration Release
  -sdk macosx
  -xcconfig "${CONFIG_FILE}"
  -derivedDataPath "${DERIVED_DATA}"
  ARCHS="arm64 x86_64"
  ONLY_ACTIVE_ARCH=NO
  "MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-15.0}"
  CODE_SIGN_STYLE=Manual
  "CODE_SIGN_IDENTITY=${IDENTITY}"
  "DEVELOPMENT_TEAM=${TEAM_ID}"
  build
)

xcodebuild "${BUILD_ARGS[@]}"

BUNDLE="${DERIVED_DATA}/Build/Products/Release/NoMADLoginAD.bundle"
[[ -d "${BUNDLE}" ]] || { echo "NoMADLoginAD.bundle was not produced" >&2; exit 1; }

FRAMEWORK="${BUNDLE}/Contents/Frameworks/NoMAD_ADAuth.framework"
[[ -d "${FRAMEWORK}" ]] || { echo "Embedded NoMAD_ADAuth.framework is missing" >&2; exit 1; }

SIGN_ARGS=(--force --options runtime --sign "${IDENTITY}")
if [[ "${IDENTITY}" != "-" ]]; then
  SIGN_ARGS+=(--timestamp)
fi

# Sign nested code first; do not use codesign --deep to sign.
codesign "${SIGN_ARGS[@]}" "${FRAMEWORK}"
codesign "${SIGN_ARGS[@]}" "${BUNDLE}"

bash "${ROOT_DIR}/Scripts/verify-bundle.sh" "${BUNDLE}"
echo "Built bundle: ${BUNDLE}"
