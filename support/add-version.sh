#!/usr/bin/env bash

# add-version.sh X.Y.Z: pin a gyrseek release in support/locks.
#
# Downloads the release, checks every archive against its SHA256SUMS and against
# its build attestation, and only then writes support/locks/gyrseek-X.Y.Z.txt.
# Review the new file in the pull request: it is what the action trusts.

set -euo pipefail

repo="gyrforge/gyrseek"
version="${1:-}"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "usage: $0 X.Y.Z" >&2
    exit 2
}

lock="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/locks/gyrseek-${version}.txt"
[[ ! -e "${lock}" ]] || {
    echo "${lock} already exists: a pinned version is never rewritten" >&2
    exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

gh release download "v${version}" --repo "${repo}" --dir "${work}"
(
    cd "${work}"
    if command -v sha256sum >/dev/null 2>&1; then sha256sum -c SHA256SUMS; else shasum -a 256 -c SHA256SUMS; fi
    for archive in gyrseek-v"${version}"-*.tar.gz; do
        gh attestation verify "${archive}" --repo "${repo}" \
            --signer-workflow "${repo}/.github/workflows/release.yml" >/dev/null
        echo "attested: ${archive}"
    done
)

cp "${work}/SHA256SUMS" "${lock}"
echo "wrote ${lock}"
