#!/usr/bin/env bash

# action.sh: install gyrseek from a release archive whose SHA-256 is pinned in
# this action's own tree (support/locks), then check where the archive was built.
#
# Nothing in the environment can change what is installed except the `version`
# input, which only selects among the hashes committed here.

set -euo pipefail

repo="gyrforge/gyrseek"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
locks="${here}/support/locks"

die() {
    echo "::error::${*}"
    exit 1
}

warn() {
    echo "::warning::${*}"
}

output() {
    echo "${1}=${2}" >> "${GITHUB_OUTPUT}"
}

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${1}" | cut -d' ' -f1
    else
        shasum -a 256 "${1}" | cut -d' ' -f1
    fi
}

# --- which version -----------------------------------------------------------

version_regex='^v?[0-9]+\.[0-9]+\.[0-9]+$'

case "${GHA_GYRSEEK_VERSION:-latest}" in
    latest | "")
        # The newest version this action has hashes for.
        version="$(find "${locks}" -name 'gyrseek-*.txt' -print \
            | sed -n 's#.*/gyrseek-\(.*\)\.txt$#\1#p' | sort -V | tail -n 1)"
        [[ -n "${version}" ]] || die "this action has no gyrseek versions pinned"
        ;;
    *)
        [[ "${GHA_GYRSEEK_VERSION}" =~ ${version_regex} ]] \
            || die "'version' must be 'latest' or an exact X.Y.Z version"
        version="${GHA_GYRSEEK_VERSION#v}"
        ;;
esac

lock="${locks}/gyrseek-${version}.txt"
[[ -f "${lock}" ]] \
    || die "gyrseek ${version} is not pinned by this version of the action: use a newer release of the action, or one of: $(find "${locks}" -name 'gyrseek-*.txt' -print | sed -n 's#.*/gyrseek-\(.*\)\.txt$#\1#p' | sort -V | tr '\n' ' ')"

# --- which archive -----------------------------------------------------------

case "${RUNNER_OS:-}/${RUNNER_ARCH:-}" in
    Linux/X64) target="x86_64-unknown-linux-gnu" ;;
    Linux/ARM64) target="aarch64-unknown-linux-gnu" ;;
    macOS/X64) target="x86_64-apple-darwin" ;;
    macOS/ARM64) target="aarch64-apple-darwin" ;;
    *) die "unsupported runner: ${RUNNER_OS:-unknown} ${RUNNER_ARCH:-unknown} (gyrseek has Linux and macOS builds; on Windows use WSL2)" ;;
esac

name="gyrseek-v${version}-${target}"
archive="${name}.tar.gz"

expected="$(awk -v f="${archive}" '$2 == f { print $1 }' "${lock}")"
[[ "${expected}" =~ ^[0-9a-f]{64}$ ]] \
    || die "no valid SHA-256 for ${archive} in ${lock#"${here}"/}"

# --- download and check ------------------------------------------------------

work="$(mktemp -d "${RUNNER_TEMP:?RUNNER_TEMP is not set}/gyrseek.XXXXXX")"
curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error \
    --location --retry 3 --output "${work}/${archive}" \
    "https://github.com/${repo}/releases/download/v${version}/${archive}"

actual="$(sha256 "${work}/${archive}")"
[[ "${actual}" == "${expected}" ]] \
    || die "${archive} does not match the SHA-256 pinned by this action (expected ${expected}, got ${actual}); nothing was installed"

if [[ "${GHA_GYRSEEK_VERIFY_ATTESTATION:-true}" == "true" ]]; then
    command -v gh >/dev/null 2>&1 \
        || die "'verify-attestation' needs the GitHub CLI (gh) on the runner; install it or set verify-attestation: false"
    GH_TOKEN="${GHA_GYRSEEK_TOKEN:-}" gh attestation verify "${work}/${archive}" \
        --repo "${repo}" \
        --signer-workflow "${repo}/.github/workflows/release.yml" \
        >/dev/null \
        || die "the build attestation of ${archive} did not verify; nothing was installed"
fi

# --- unpack ------------------------------------------------------------------

# Only the one directory this archive is named for, nothing absolute or upward.
while IFS= read -r entry; do
    [[ "${entry}" == "${name}/"* && "${entry}" != *..* ]] \
        || die "${archive} holds an unexpected path: ${entry}"
done < <(tar -tzf "${work}/${archive}")

dest="${work}/unpacked"
mkdir -p "${dest}"
tar -xzf "${work}/${archive}" -C "${dest}"

bin="${dest}/${name}"
reported="$("${bin}/gyrseek" --version)"
[[ "${reported}" == "gyrseek ${version}" ]] \
    || die "the installed binary reports '${reported}', expected 'gyrseek ${version}'"

echo "${bin}" >> "${GITHUB_PATH}"
output "version" "${version}"
output "target" "${target}"
output "path" "${bin}"

command -v docker >/dev/null 2>&1 \
    || warn "docker was not found: every gyrseek scan needs a running Docker daemon (GitHub-hosted macOS runners have none)"

echo "Installed gyrseek ${version} (${target})"
