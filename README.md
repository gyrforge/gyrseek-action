# gyrseek-action

[![Self-test](https://github.com/gyrforge/gyrseek-action/actions/workflows/selftest.yml/badge.svg?branch=main)](https://github.com/gyrforge/gyrseek-action/actions/workflows/selftest.yml?query=branch%3Amain)

Installs [gyrseek](https://github.com/gyrforge/gyrseek) on a GitHub Actions runner, so that later steps can run `gyrseek npm ci`, `gyrseek uv sync` and the like. gyrseek installs a package and two older versions in a Docker sandbox, compares what each did, and only forwards your command when nothing new shows up.

This action only installs gyrseek. It does not run it: you decide which commands go through it.

## Usage

```yaml
permissions:
  contents: read

jobs:
  install:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<full commit sha> # v7
        with:
          persist-credentials: false

      - uses: gyrforge/gyrseek-action@<full commit sha> # v1
        with:
          version: "1.4.3"

      - run: gyrseek npm ci
```

Pin the action to a full commit SHA, as for any third-party action. The `gyrseek` step needs a running Docker daemon: GitHub-hosted `ubuntu-*` runners have one. GitHub-hosted macOS runners do not, so a scan cannot run there (the action still installs the binary, and warns when `docker` is missing).

## Inputs

| Input | Default | What it does |
|---|---|---|
| `version` | `latest` | An exact version such as `1.4.3`, or `latest`: the newest version this release of the action has a pinned hash for. Prefer an exact version. |
| `verify-attestation` | `true` | Also run `gh attestation verify`, which checks that the archive was built by gyrseek's own release workflow. Needs `gh` on the runner (GitHub-hosted runners have it); set to `false` on a runner without it. |
| `token` | `${{ github.token }}` | The token `gh` uses for the attestation lookup. It needs no permissions beyond reading the public repository. |

## Outputs

| Output | What it is |
|---|---|
| `version` | The gyrseek version that was installed |
| `path` | The directory that holds the binary (it is also added to `PATH`) |
| `target` | The release that was chosen, for example `x86_64-unknown-linux-gnu` |

## Runners

| Runner | Installed |
|---|---|
| Linux x86_64 and ARM64 | `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu` (Ubuntu 22.04 or newer: they link glibc and OpenSSL 3) |
| macOS Apple Silicon and Intel | `aarch64-apple-darwin`, `x86_64-apple-darwin` (macOS 13 or newer) |
| Windows | Not supported. Use WSL2. |

## How it protects you

The risk of installing a security tool from the network is that the download is not what you expected. Three checks, in order, and nothing is put on `PATH` unless all pass:

1. **A hash pinned in this repository.** For every supported version, `support/locks/gyrseek-X.Y.Z.txt` holds the SHA-256 of each release archive. The action downloads from `https://github.com/gyrforge/gyrseek/releases/download/…` and compares. The hashes come from the commit of the action you pinned, not from the download, so a changed release asset is refused. A version this release of the action does not know is refused too.
2. **The build attestation** (`verify-attestation`, on by default): the archive must carry a signed provenance statement from the `release.yml` workflow of `gyrforge/gyrseek`.
3. **A look inside the archive**: every path must sit under the one expected directory, and the binary must report exactly `gyrseek X.Y.Z`.

The `version` input is matched against a strict `X.Y.Z` pattern and passed to the script through the environment, never pasted into a shell command. The action needs no secrets. It unpacks under the runner's temporary directory and otherwise only adds that directory to `PATH` and sets its outputs.

### Keep secrets out of the job

gyrseek's scan is evidence, not a guarantee: after a clear scan the forwarded install runs on the runner itself, with the job's environment. Do not put cloud credentials, publish tokens or SSH keys in a job that installs through gyrseek. Run it in its own job with `contents: read` and pass results on as artifacts. See the [gyrseek README](https://github.com/gyrforge/gyrseek#2b-or-download-a-release-linux-and-macos).

## Adding a gyrseek version

After gyrseek publishes `vX.Y.Z`:

```bash
support/add-version.sh X.Y.Z
```

It downloads the release, checks every archive against `SHA256SUMS` and against its attestation, and only then writes `support/locks/gyrseek-X.Y.Z.txt`. Review the new file in the pull request: it is what the action trusts from then on. A pinned version's file is never rewritten, and `v1.4.2` is not pinned: it shipped under the wrong licence.

## Releasing the action

Users pin a tag or, better, its commit, so a tag fixes the set of hashes they trust. Version the action on its own, not after gyrseek:

- A new gyrseek version pinned: a minor release (`v1.1.0` adds gyrseek 1.4.4), because `version: latest` moves forward.
- A fix to the action's script or workflows: a patch release.
- A change to inputs or behavior that breaks users: a major release.

```bash
just check          # every pinned version is complete (CI runs this too)
just tag v1.1.0     # needs gh and just
```

`support/tag.sh` refuses unless `HEAD` is `origin/main`, the working tree is clean, every lock file is complete, and the self-test has passed on that commit (it waits for a run in progress). It never replaces a tag that exists. It then pushes the tag and creates the GitHub Release, whose notes list the pinned gyrseek versions and the commit to pin. Turn on immutable releases in the repository settings, so that a published release's tag cannot be moved.

## Development

- `.github/workflows/selftest.yml` installs on Linux x86_64, Linux ARM64 and macOS, installs an exact version, and checks that an unpinned version, a malformed version and a tampered hash are all refused.
- `.github/workflows/lint.yml` runs ShellCheck, yamllint, zizmor and `support/check-locks.sh`.
- Changes need a review from `@gyrforge/gyrseek-builders` (`.github/CODEOWNERS`).

## License

Copyright 2026 Gyrforge. Licensed under the [Apache License 2.0](LICENSE); the attribution is in [NOTICE](NOTICE).
