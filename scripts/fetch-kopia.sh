#!/bin/bash

set -euo pipefail

# renovate: datasource=github-releases depName=kopia/kopia
readonly KOPIA_VERSION="0.23.1"
readonly KOPIA_ARCHIVE="kopia-${KOPIA_VERSION}-macOS-universal.tar.gz"
readonly KOPIA_URL="https://github.com/kopia/kopia/releases/download/v${KOPIA_VERSION}/${KOPIA_ARCHIVE}"
readonly CACHE_DIR="${DERIVED_FILE_DIR}/Kopia-${KOPIA_VERSION}"
readonly SOURCE_DIR="${CACHE_DIR}/kopia-${KOPIA_VERSION}-macOS-universal"
readonly SOURCE_BINARY="${SOURCE_DIR}/kopia"
readonly SOURCE_LICENSE="${SOURCE_DIR}/LICENSE"
readonly BUNDLE_BINARY="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/kopia"
readonly BUNDLE_LICENSE="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Kopia-LICENSE.txt"

if [[ ! -x "${SOURCE_BINARY}" || ! -f "${SOURCE_LICENSE}" ]]; then
    TEMP_DIR="$(mktemp -d "${DERIVED_FILE_DIR}/KopiaDownload.XXXXXX")"
    readonly TEMP_DIR
    trap 'rm -rf "${TEMP_DIR}"' EXIT
    /usr/bin/curl --fail --location --retry 3 \
        --output "${TEMP_DIR}/${KOPIA_ARCHIVE}" \
        "${KOPIA_URL}"
    /usr/bin/tar -xzf "${TEMP_DIR}/${KOPIA_ARCHIVE}" -C "${TEMP_DIR}"
    /bin/rm -rf "${CACHE_DIR}"
    /bin/mkdir -p "${CACHE_DIR}"
    /bin/mv "${TEMP_DIR}/kopia-${KOPIA_VERSION}-macOS-universal" "${SOURCE_DIR}"
fi

if /usr/bin/codesign --display "${SOURCE_BINARY}" >/dev/null 2>&1; then
    /usr/bin/codesign --verify --strict --verbose=2 "${SOURCE_BINARY}"
fi

/bin/mkdir -p "$(dirname "${BUNDLE_BINARY}")" "$(dirname "${BUNDLE_LICENSE}")"
/usr/bin/install -m 0755 "${SOURCE_BINARY}" "${BUNDLE_BINARY}"
/usr/bin/install -m 0644 "${SOURCE_LICENSE}" "${BUNDLE_LICENSE}"

if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" ]]; then
    identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
    options=(--force --sign "${identity}" --options runtime)
    if [[ "${identity}" != "-" && "${CONFIGURATION}" == "Release" ]]; then
        options+=(--timestamp)
    fi
    /usr/bin/codesign "${options[@]}" "${BUNDLE_BINARY}"
fi
