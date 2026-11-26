default:
    @just --list

# Check that every pinned version is complete
check:
    support/check-locks.sh

# Tag origin/main and publish the release: just tag v1.0.0
tag version:
    support/tag.sh {{version}}
