#!/bin/bash
# Rebuild NoMAD_ADAuth locally. Do not use the framework committed by the
# historical Carthage checkout: it predates Apple Silicon and current SDKs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/build/ADAuth"
SOURCE_DIR="${WORK_DIR}/source"
DERIVED_DATA="${WORK_DIR}/DerivedData"
OUTPUT_DIR="${ROOT_DIR}/Carthage/Build/Mac"
REPO_URL="${ADAUTH_REPOSITORY:-https://github.com/jamf/NoMAD-ADAuth.git}"
REPO_REF="${ADAUTH_REF:-1.1.4}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"

command -v git >/dev/null || { echo "git is required" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "Xcode command-line tools are required" >&2; exit 1; }

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

git clone --depth 1 --branch "${REPO_REF}" "${REPO_URL}" "${SOURCE_DIR}"

PROJECT="${SOURCE_DIR}/NoMAD-ADAuth.xcodeproj"
[[ -d "${PROJECT}" ]] || { echo "Expected Xcode project was not found: ${PROJECT}" >&2; exit 1; }

# ADAuth 1.1.4 still imports NoMADPRIVATE from NoMADSession.swift even though
# the source target includes its Logger and UNIXUtilities implementations.
# Older Xcode builds silently left that private module reference in the emitted
# .swiftmodule. Current Swift dependency scanning correctly rejects consumers
# of the framework because NoMADPRIVATE is not shipped. Remove only that stale
# import before compiling the framework, leaving the actual helper sources in
# the same target.
PRIVATE_IMPORTS="$(grep -RIl --include='*.swift' '^import NoMADPRIVATE$' "${SOURCE_DIR}" || true)"
if [[ -n "${PRIVATE_IMPORTS}" ]]; then
  echo "Removing stale NoMADPRIVATE imports from ADAuth source"
  while IFS= read -r source_file; do
    sed -i '' '/^import NoMADPRIVATE$/d' "${source_file}"
  done <<< "${PRIVATE_IMPORTS}"
fi

# The archived dependency has changed scheme names over time. Resolve the
# framework-producing scheme from Xcode instead of hard-coding one.
SCHEME="$(xcodebuild -list -json -project "${PROJECT}" | plutil -extract project.schemes.0 raw -)"
[[ -n "${SCHEME}" ]] || { echo "Could not resolve an ADAuth Xcode scheme" >&2; exit 1; }

echo "Building ${SCHEME} (${REPO_REF}) for arm64 and x86_64"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "${DERIVED_DATA}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  SKIP_INSTALL=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

FRAMEWORK="$(find "${DERIVED_DATA}/Build/Products/Release" -maxdepth 1 -type d -name 'NoMAD_ADAuth.framework' -print -quit)"
[[ -n "${FRAMEWORK}" ]] || { echo "NoMAD_ADAuth.framework was not produced" >&2; exit 1; }

rm -rf "${OUTPUT_DIR}/NoMAD_ADAuth.framework" "${OUTPUT_DIR}/NoMAD_ADAuth.framework.dSYM"
ditto "${FRAMEWORK}" "${OUTPUT_DIR}/NoMAD_ADAuth.framework"

DSYM="$(find "${DERIVED_DATA}/Build/Products/Release" -maxdepth 1 -type d -name 'NoMAD_ADAuth.framework.dSYM' -print -quit || true)"
if [[ -n "${DSYM}" ]]; then
  ditto "${DSYM}" "${OUTPUT_DIR}/NoMAD_ADAuth.framework.dSYM"
fi

BINARY="${OUTPUT_DIR}/NoMAD_ADAuth.framework/Versions/A/NoMAD_ADAuth"
if [[ ! -f "${BINARY}" ]]; then
  BINARY="${OUTPUT_DIR}/NoMAD_ADAuth.framework/NoMAD_ADAuth"
fi
lipo -archs "${BINARY}"
echo "ADAuth framework rebuilt at ${OUTPUT_DIR}/NoMAD_ADAuth.framework"
