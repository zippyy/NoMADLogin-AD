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
ADAUTH_SOURCE_DIR="${SOURCE_DIR}/NoMAD-ADAuth"
[[ -d "${PROJECT}" ]] || { echo "Expected Xcode project was not found: ${PROJECT}" >&2; exit 1; }
[[ -d "${ADAUTH_SOURCE_DIR}" ]] || { echo "Expected ADAuth source directory was not found: ${ADAUTH_SOURCE_DIR}" >&2; exit 1; }

# NoMAD-ADAuth 1.1.4 imports the old private NoMADPRIVATE Swift module. That
# module is not distributed with this project. The imported names actually come
# from ADAuth's own Objective-C DNS, GSS, and Kerberos headers, so expose those
# headers to the Swift target directly through a bridging header.
PRIVATE_IMPORTS="$(grep -RIl --include='*.swift' '^import NoMADPRIVATE$' "${ADAUTH_SOURCE_DIR}" || true)"
if [[ -n "${PRIVATE_IMPORTS}" ]]; then
  echo "Replacing NoMADPRIVATE imports with ADAuth's local Objective-C bridge"
  while IFS= read -r source_file; do
    sed -i '' '/^import NoMADPRIVATE$/d' "${source_file}"
  done <<< "${PRIVATE_IMPORTS}"
fi

BRIDGING_HEADER="${ADAUTH_SOURCE_DIR}/NoMAD-ADAuth-Bridging-Header.h"
cat > "${BRIDGING_HEADER}" <<'EOF'
#import <Foundation/Foundation.h>
#import <GSS/GSS.h>
#import <Kerberos/Kerberos.h>
#import "DNSResolver.h"
#import "GSSItem.h"
#import "KerbUtil.h"
#import "krb5.h"
EOF

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
  SWIFT_OBJC_BRIDGING_HEADER="${BRIDGING_HEADER}" \
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
