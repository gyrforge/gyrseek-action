#!/usr/bin/env bash

# check-locks.sh: every pinned version must be complete and consistent.
#
# Each support/locks/gyrseek-X.Y.Z.txt must name exactly the four release
# archives of X.Y.Z, each with a 64-digit SHA-256, and nothing else. Run by CI
# and by tag.sh, so a half-written or hand-edited lock never reaches a tag.

set -euo pipefail

locks="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/locks"
targets=(
    aarch64-apple-darwin
    aarch64-unknown-linux-gnu
    x86_64-apple-darwin
    x86_64-unknown-linux-gnu
)

fail=0
count=0
for lock in "${locks}"/gyrseek-*.txt; do
    [[ -e "${lock}" ]] || { echo "no lock files in ${locks}" >&2; exit 1; }
    count=$((count + 1))
    version="$(basename "${lock}" .txt)"
    version="${version#gyrseek-}"
    if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "${lock}: the file name is not gyrseek-X.Y.Z.txt" >&2
        fail=1
        continue
    fi

    expected=()
    for target in "${targets[@]}"; do
        expected+=("gyrseek-v${version}-${target}.tar.gz")
    done

    actual="$(awk '{ print $2 }' "${lock}" | sort | tr '\n' ' ')"
    wanted="$(printf '%s\n' "${expected[@]}" | sort | tr '\n' ' ')"
    if [[ "${actual}" != "${wanted}" ]]; then
        echo "${lock}: expected exactly ${wanted}but found ${actual}" >&2
        fail=1
    fi

    if grep -qvE '^[0-9a-f]{64}  gyrseek-v[0-9.]+-[a-z0-9_-]+\.tar\.gz$' "${lock}"; then
        echo "${lock}: a line is not '<sha256>  <archive>'" >&2
        fail=1
    fi
done

[[ "${fail}" -eq 0 ]] || exit 1
echo "${count} pinned version(s) are complete"
