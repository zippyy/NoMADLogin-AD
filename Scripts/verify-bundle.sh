#!/bin/bash
# Verify the built SecurityAgent plug-in before installing it at loginwindow.
set -euo pipefail

BUNDLE="${1:-}"
[[ -n "${BUNDLE}" && -d "${BUNDLE}" ]] || {
  echo "Usage: bash Scripts/verify-bundle.sh /path/to/NoMADLoginAD.bundle" >&2
  exit 64
}

PLUGIN_BINARY="${BUNDLE}/Contents/MacOS/NoMADLoginAD"
FRAMEWORK_BINARY="${BUNDLE}/Contents/Frameworks/NoMAD_ADAuth.framework/Versions/A/NoMAD_ADAuth"
if [[ ! -f "${FRAMEWORK_BINARY}" ]]; then
  FRAMEWORK_BINARY="${BUNDLE}/Contents/Frameworks/NoMAD_ADAuth.framework/NoMAD_ADAuth"
fi

[[ -f "${PLUGIN_BINARY}" ]] || { echo "Plug-in executable not found" >&2; exit 1; }
[[ -f "${FRAMEWORK_BINARY}" ]] || { echo "Embedded ADAuth binary not found" >&2; exit 1; }

for binary in "${PLUGIN_BINARY}" "${FRAMEWORK_BINARY}"; do
  ARCHS="$(lipo -archs "${binary}")"
  echo "${binary}: ${ARCHS}"
  [[ " ${ARCHS} " == *" arm64 "* && " ${ARCHS} " == *" x86_64 "* ]] || {
    echo "Expected universal arm64 + x86_64 binary: ${binary}" >&2
    exit 1
  }
done

codesign --verify --deep --strict --verbose=4 "${BUNDLE}"

# The current SecurityAgent process must resolve the embedded framework from
# the bundle. A system-wide Carthage path must never be present here.
otool -L "${PLUGIN_BINARY}"
otool -L "${FRAMEWORK_BINARY}"

echo "Verification passed: ${BUNDLE}"
