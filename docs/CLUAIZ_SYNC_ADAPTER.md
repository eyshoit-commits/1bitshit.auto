# Cluaiz ↔ 1BitShit Sync Adapter

This repository intentionally does **not** behave as a blind mirror of `cluaiz/cluaiz`.

The projects share code, but 1BitShit owns its product identity, installers, migration rules, registry metadata and CI policy. The adapter therefore separates reusable engine changes from project-specific files.

## Inbound: Cluaiz → 1BitShit

Workflow: `.github/workflows/sync-cluaiz-inbound.yml`

The workflow runs every six hours and can also be started manually.

It performs these steps:

1. Fetch the selected ref from `cluaiz/cluaiz`.
2. Skip when the upstream commit is already contained in 1BitShit.
3. Create a temporary `sync/cluaiz-*` branch.
4. Merge the upstream ref without committing immediately.
5. Restore every path listed in `.github/upstream-sync/owned-paths.txt` from 1BitShit.
6. Refuse unresolved conflicts outside protected paths.
7. Record the imported upstream commit in `.github/upstream-sync/last-import.json`.
8. Run branding, installer and Cargo metadata validation.
9. Push the branch and open a review pull request to `main`.

No inbound change is merged automatically. A successful adapter run means the change is technically importable, not automatically desirable.

## Protected 1BitShit paths

The current policy protects:

- Linux and Windows installers
- README and security policy
- GitHub workflows
- adapter and verification scripts
- BitShit migration documentation
- package registry metadata

Edit `.github/upstream-sync/owned-paths.txt` when ownership changes.

Directory entries must end in `/`. File entries are exact paths.

## Outbound: 1BitShit → Cluaiz

Workflow: `.github/workflows/propose-to-cluaiz.yml`

Outbound proposals are manual and commit-based. Supply one or more commit SHAs in oldest-first order. The adapter:

1. Checks out the current Cluaiz base branch.
2. Creates a clean proposal branch from that base.
3. Replays the selected 1BitShit commits with `git cherry-pick -x`.
4. Rejects changes touching 1BitShit-owned paths.
5. Runs Cluaiz-side Cargo metadata validation.
6. Pushes the proposal branch to a writable fork of `cluaiz/cluaiz`.
7. Opens a pull request against `cluaiz/cluaiz`.

This keeps upstream proposals focused on reusable fixes instead of exporting BitShit branding, installer choices or repository policy.

## Required outbound configuration

GitHub requires a writable fork because this repository has read-only access to `cluaiz/cluaiz`.

Create a fork such as:

```text
eyshoit-commits/cluaiz
```

Then configure the following in **Settings → Secrets and variables → Actions** for `1bitshit.auto`:

### Repository variable

```text
CLUAIZ_FORK_REPO=eyshoit-commits/cluaiz
```

### Repository secret

```text
CLUAIZ_UPSTREAM_TOKEN=<fine-grained token>
```

The token needs:

- read access to `cluaiz/cluaiz`
- write access to branches in the configured fork
- permission to create pull requests against `cluaiz/cluaiz`

Do not place the token in repository files, workflow inputs or logs.

## Selecting outbound commits

Prefer small, self-contained commits that modify reusable engine code.

Good candidates:

- build fixes
- runtime correctness fixes
- hardware detection fixes
- tests
- performance improvements
- generic API repairs

Bad candidates:

- BitShit naming
- BitShit installer behavior
- BitShit-specific paths or registry URLs
- migrations from `.cluaiz` to `.bitshit`
- repository-specific CI policy

Example workflow input:

```text
commits: 0123abc 4567def
title: Fix CPU backend detection and missing API manifest
body: Ports two generic build repairs discovered while validating 1BitShit.
upstream_base: main
```

## Conflict policy

Inbound conflicts in protected paths are resolved in favor of 1BitShit.

Inbound conflicts elsewhere stop the workflow. They require a human integration commit because silently choosing either side would risk dropping functional changes.

Outbound conflicts during cherry-pick stop the workflow. Rewrite or split the selected commit in 1BitShit, then run the proposal again.

## Security boundary

The scheduled inbound workflow uses the repository `GITHUB_TOKEN` only for branches and pull requests inside `1bitshit.auto`.

The outbound token is available only to the manually triggered outbound workflow. It is not used for scheduled imports or pull-request workflows.
