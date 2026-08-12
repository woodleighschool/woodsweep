#!/bin/sh

set -eu

project_root="$(pwd -P)"
readonly project_root

if [ ! -f "${project_root}/.mise/config.toml" ] || [ ! -d "${project_root}/WoodSweep.xcodeproj" ]; then
    echo "start-kopia-server.sh must run from the WoodSweep repository root" >&2
    exit 1
fi

readonly state_directory="${project_root}/.local/kopia"
readonly repository="${state_directory}/repository"
readonly bootstrap_user=bootstrap@woodsweep
readonly bootstrap_password=woodsweep-test-bootstrap
readonly tls_cert_file="${project_root}/.local/tls/kopia.pem"
readonly tls_key_file="${project_root}/.local/tls/kopia-key.pem"

readonly KOPIA_CONFIG_PATH="${state_directory}/config/repository.config"
readonly KOPIA_CACHE_DIRECTORY="${state_directory}/cache"
readonly KOPIA_LOG_DIR="${state_directory}/logs"
readonly KOPIA_PASSWORD=woodsweep-test-repository
export KOPIA_CONFIG_PATH KOPIA_CACHE_DIRECTORY KOPIA_LOG_DIR KOPIA_PASSWORD

if [ ! -r "${tls_cert_file}" ] || [ ! -r "${tls_key_file}" ]; then
    echo "local Kopia TLS certificate is missing; run 'mise run dev-tls'" >&2
    exit 1
fi

mkdir -p \
    "$(dirname "${KOPIA_CONFIG_PATH}")" \
    "${KOPIA_CACHE_DIRECTORY}" \
    "${KOPIA_LOG_DIR}" \
    "${repository}"

if [ ! -f "${KOPIA_CONFIG_PATH}" ]; then
    if [ -f "${repository}/kopia.repository.f" ]; then
        kopia repository connect filesystem --path "${repository}"
    else
        kopia repository create filesystem --path "${repository}"
    fi
fi

kopia server acl enable --reset

if kopia server users info "${bootstrap_user}" >/dev/null 2>&1; then
    kopia server users set "${bootstrap_user}" \
        --user-password "${bootstrap_password}"
else
    kopia server users add "${bootstrap_user}" \
        --user-password "${bootstrap_password}"
fi

kopia server acl add \
    --overwrite \
    --user "${bootstrap_user}" \
    --access FULL \
    --target type=user

exec kopia server start \
    --address 127.0.0.1:51515 \
    --tls-cert-file "${tls_cert_file}" \
    --tls-key-file "${tls_key_file}" \
    --server-control-username "${bootstrap_user}" \
    --server-control-password "${bootstrap_password}" \
    --no-check-for-updates \
    --no-ui
