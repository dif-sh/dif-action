# dif build and validate

A GitHub Action that installs the [dif](https://github.com/dif-sh/dif) CLI and runs `dif build` on your repo. The job fails when a flag file is invalid, including when two active experiments clash on one surface.

dif keeps each feature flag and A/B test as one Markdown file under `dif/experiments/`. `dif build` validates those files and compiles the active ones into `dif/generated/client.ts`. This action runs that step in CI, so a pull request that introduces a clash cannot merge green.

## Usage

```yaml
name: flags

on:
  pull_request:
  push:
    branches: [main]

jobs:
  dif:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: dif-sh/dif-action@v1
```

That is the whole setup. There is no key, no account and no secret to configure.

### Check only, write nothing

`dif validate` runs the same checks as `dif build` and writes no files.

```yaml
      - uses: dif-sh/dif-action@v1
        with:
          command: validate
```

### Build the flags, then build the app

`dif/generated/` is gitignored by the `dif/.gitignore` that `dif init` writes, so CI has to run `dif build` before the app build. The action leaves the generated files in the workspace for later steps.

```yaml
    steps:
      - uses: actions/checkout@v5
      - uses: dif-sh/dif-action@v1
        with:
          version: "0.6.3"
      - uses: actions/setup-node@v5
        with:
          node-version: 22
      - run: npm ci
      - run: npm run build
```

### Monorepo

Point `working-directory` at the folder that contains `dif/`.

```yaml
      - uses: dif-sh/dif-action@v1
        with:
          working-directory: apps/web
```

### Install dif and run your own commands

```yaml
      - uses: dif-sh/dif-action@v1
        with:
          install-only: "true"
      - run: dif validate --json > dif-report.json
```

## Inputs

| Input | Default | What it does |
| --- | --- | --- |
| `version` | `latest` | dif release to install. `latest`, or a version such as `0.6.3` or `v0.6.3`. Pin it if you want a new dif release to reach CI only when you choose. |
| `command` | `build` | dif verb to run. `build` validates, then writes `dif/generated/` and `dif/context.json`. `validate` checks only. |
| `args` | empty | Extra arguments for the verb, split on whitespace. Example: `--out src/generated`. Arguments that contain spaces are not supported. |
| `working-directory` | `.` | Directory that contains the `dif/` folder, relative to the repository root. |
| `annotations` | `true` | Turn each dif error and warning into a GitHub annotation on the file it names. Set to `false` to print the log only. |
| `install-only` | `false` | Install dif and add it to `PATH` without running a verb. |

## Outputs

| Output | Value |
| --- | --- |
| `version` | The installed dif version, for example `0.6.3`. |
| `exit-code` | Exit code of the dif verb: `0` when every check passed, `1` on any validation error. |

## What a clash looks like

Two files, both `status: active`, both on `surface: home`, neither with an `exclusion_group`:

```md
---
id: new-checkout
status: active
owner: dev@example.com
surface: home
hypothesis: >
  Inlining the address form lifts completed checkouts.
variants:
  - id: "off"
    weight: 90
  - id: "on"
    weight: 10
metrics:
  primary: completed_checkout
created: 2026-10-07
---
```

```md
---
id: home-hero-cta
status: active
owner: dev@example.com
surface: home
hypothesis: >
  A shorter hero CTA lifts signups.
variants:
  - id: "off"
    weight: 90
  - id: "on"
    weight: 10
metrics:
  primary: signup
created: 2026-10-08
---
```

The step log, from dif 0.6.3 run against `tests/fixtures/clash` in this repo:

```console
$ dif build
error E007 dif/experiments/active/home-hero-cta.md:1:1: experiments `home-hero-cta` and `new-checkout` both target surface `home` without a shared exclusion_group, and their audiences are not provably disjoint
  help: Add the same `exclusion_group:` value to both, narrow one of the audiences so they're provably disjoint, or change one of their `surface:` fields.

✗ build refused: 1 error(s)
  fix the above and re-run, or run `dif validate` to recheck.
```

`dif build` exits 1, the step fails, and nothing is written to `dif/generated/`. The action also prints one workflow command per diagnostic, which GitHub shows as an annotation on `home-hero-cta.md` line 1 with the title `dif E007`:

```text
::error file=tests/fixtures/clash/dif/experiments/active/home-hero-cta.md,line=1,col=1,title=dif E007::experiments `home-hero-cta` and `new-checkout` both target surface `home` without a shared exclusion_group, and their audiences are not provably disjoint
```

Add `exclusion_group: home` to both files and the same step passes:

```console
$ dif build
✓ validated 2 active experiment(s)
✓ typed client → dif/generated/client.ts
✓ audiences   → dif/generated/audiences.ts
✓ events      → dif/generated/events.ts
✓ context     → dif/context.json
```

### The rule

Two experiments with `status: active` and the same `surface:` are a conflict, error `E007`, unless one of these holds:

1. Both declare the same `exclusion_group:` value. A user is then in at most one experiment in that group.
2. Both have an `include` constraint on the same audience attribute and the value sets do not intersect, for example `device_type: mobile` next to `device_type: [tablet, desktop]`.

Files with `status: draft` are skipped. The check is per surface: two experiments on different surfaces are never flagged.

### Everything that fails the step

`dif build` and `dif validate` exit 1 on any of these errors:

| Code | Meaning |
| --- | --- |
| `E001` | Invalid frontmatter |
| `E003` | `owner` is not an email |
| `E004` | `surface` does not exist |
| `E005` | Variant weights do not sum to 100 |
| `E006` | Audience attribute not declared in `dif/config.yaml` |
| `E007` | Exclusion conflict, as above |
| `E008` | Declared attribute has no `dif/audiences/<name>.ts` |
| `E009` | Duplicate experiment id across `active/` and `concluded/` |
| `E010` | Duplicate variant id |

Warnings `W001` to `W004` are annotated and exit 0. For example, a `dif("id", ...)` call in a `.ts`, `.tsx`, `.js` or `.jsx` file that names no active experiment is `W001`, and the step still passes.

## How it installs dif

`scripts/install.sh` downloads the prebuilt binary for the runner from the [dif-sh/dif release](https://github.com/dif-sh/dif/releases), compares its SHA-256 with the `.sha256` file published next to it, and refuses to install on a mismatch. It then adds the binary to `PATH` for the rest of the job. It uses `bash`, `curl` and `tar`, which GitHub-hosted runners include. It does not need Node or npm.

| Runner | Binary |
| --- | --- |
| Linux x64 | `dif-x86_64-unknown-linux-musl.tar.gz` (static) |
| Linux arm64 | `dif-aarch64-unknown-linux-musl.tar.gz` (static) |
| macOS arm64 | `dif-aarch64-apple-darwin.tar.gz` |
| macOS x64 | `dif-x86_64-apple-darwin.tar.gz` |
| Windows x64 | `dif-x86_64-pc-windows-msvc.zip` |

There is no Windows arm64 binary. The action stops with an error on that runner.

`version: latest` reads the redirect from `github.com/dif-sh/dif/releases/latest`, so it needs no token and makes no API call.

## What this action does not do

- It does not change a rollout. Weights and variants are compiled into the client by `dif build`; changing them means editing the `.md` file and merging it.
- It does not commit `dif/generated/` or open a pull request.
- It does not send anything to Dif Cloud and reads no key.
- It does not run your tests or build your app.

## Development

`.github/workflows/test.yml` runs the action on Linux x64, Linux arm64, macOS and Windows against two fixtures: `tests/fixtures/pass` must exit 0 and write `dif/generated/client.ts`, and `tests/fixtures/clash` must fail the step and write nothing.

To run the same scripts locally with `dif` already on your `PATH`:

```sh
DIF_WORKING_DIRECTORY=tests/fixtures/pass  bash scripts/run.sh; echo $?   # 0
DIF_WORKING_DIRECTORY=tests/fixtures/clash bash scripts/run.sh; echo $?   # 1
```

## License

MIT. See [LICENSE](LICENSE).
