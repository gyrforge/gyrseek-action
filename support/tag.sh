#!/usr/bin/env bash

# tag.sh vX.Y.Z: tag origin/main and publish the release.
#
# The tag is what users pin, and the lock files it points at are what they
# trust, so a tag is only made on the commit that is on main, whose lock files
# are complete and whose self-test has passed. A tag that exists is never moved
# or replaced: to change a release, make a new version.

set -euo pipefail

tag="${1:-}"
[[ "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "usage: $0 vX.Y.Z" >&2
    exit 2
}

cd "$(dirname "${BASH_SOURCE[0]}")/.."

die() {
    echo "${*}" >&2
    exit 1
}

git fetch --quiet origin main || die "cannot fetch origin/main, so nothing was tagged"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || die "HEAD is not origin/main: check out main and pull first, so the tag is on the commit that passed CI"
[[ -z "$(git status --porcelain)" ]] || die "the working tree is not clean"

support/check-locks.sh

sha="$(git rev-parse HEAD)"
id="$(gh run list --workflow selftest.yml --commit "${sha}" --limit 1 --json databaseId --jq '.[0].databaseId // empty')" \
    || die "cannot read the self-test runs with gh, so nothing was tagged"
[[ -n "${id}" ]] || die "no self-test run found for ${sha} yet: wait for it to start, then run again"
echo "waiting for self-test run ${id} on ${sha}"
gh run watch "${id}" --exit-status >/dev/null || die "the self-test did not pass on ${sha}, so nothing was tagged"

rc=0
git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1 || rc=$?
if [[ "${rc}" -eq 0 ]]; then
    die "${tag} is already on origin. A released version is never replaced: use a new version."
elif [[ "${rc}" -ne 2 ]]; then
    die "cannot read the tags of origin (git ls-remote exited ${rc}), so nothing was tagged"
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    [[ "$(git rev-parse "${tag}^{commit}")" == "${sha}" ]] \
        || die "the local tag ${tag} points at another commit than HEAD: delete it (git tag -d ${tag}) or check out that commit"
    echo "the local tag ${tag} already points at HEAD (an earlier push did not finish); pushing it"
else
    git tag "${tag}"
fi
git push origin "${tag}"

pinned="$(find support/locks -name 'gyrseek-*.txt' -print | sed -n 's#.*/gyrseek-\(.*\)\.txt$#\1#p' | sort -V)"
newest="$(tail -n 1 <<<"${pinned}")"
notes="$(mktemp)"
trap 'rm -f "${notes}"' EXIT
{
    echo "Pins gyrseek: $(tr '\n' ' ' <<<"${pinned}" | sed 's/ $//; s/ /, /g'). \`version: latest\` installs ${newest}."
    echo
    echo "Pin this release by its commit:"
    echo
    echo '```yaml'
    echo "- uses: gyrforge/gyrseek-action@${sha} # ${tag}"
    echo '```'
} > "${notes}"

gh release create "${tag}" --verify-tag --title "${tag}" --notes-file "${notes}" \
    || die "the tag ${tag} is pushed but its release was not created: run 'gh release create ${tag} --verify-tag' (an immutable release protects the tag only once it exists)"
echo "released ${tag} (${sha})"
