# Valhalla Homebrew Tap Consolidation Design

Date: 2026-07-28

## Context

Artagon currently has two overlapping Homebrew taps:

- `artagon/homebrew-jdkvalhalla` distributes prebuilt OpenJDK Project Valhalla
  early-access binaries.
- `artagon/homebrew-jdk26ea` contains the legacy `jdk26ea` package and an open
  pull request that also adds Valhalla source-build formulas and bottle
  automation.

Maintaining two public entry points makes package discovery, version support,
workflow security, and release ownership unclear. The canonical repository
will be `artagon/homebrew-jdkvalhalla`. The legacy repository will retain only
the compatibility surface needed by existing `jdk26ea` users until it is
verified and archived.

This is a curated migration. It ports the useful behavior and tests from the
legacy pull request without merging unrelated repository histories or
overwriting the canonical repository.

## Goals

1. Provide one canonical tap for supported OpenJDK Valhalla releases.
2. Let users choose an official prebuilt binary or a source-built/bottled JDK.
3. Preserve the existing canonical package tokens.
4. Preserve the legacy `jdk26ea` token long enough to give existing users a
   working JDK 26 compatibility release and a clear migration path.
5. Make workflow permissions, artifact publication, and required checks
   fail-closed.
6. Leave the final consolidation pull request ready for the repository owner to
   merge.

## Non-goals

- Distributing general OpenJDK releases unrelated to Project Valhalla.
- Preserving the legacy repository as a second active Valhalla tap.
- Combining the two repositories with a Git history merge.
- Running a full Valhalla source build during the migration pull request.
- Automatically merging the consolidation or compatibility pull requests.

## Canonical Package Surface

| Installation mode | Token | Release line | Source |
| --- | --- | --- | --- |
| Prebuilt cask | `jdkvalhalla` | Current supported Valhalla EA | Official OpenJDK Valhalla binary |
| Prebuilt formula | `jdkvalhalla@26` | Valhalla JDK 26 EA | Official OpenJDK Valhalla binary |
| Prebuilt formula | `jdkvalhalla@27` | Valhalla JDK 27 EA | Official OpenJDK Valhalla binary |
| Source/bottle alias | `openjdk-valhalla` | Current source line | Alias to the current versioned source formula |
| Source/bottle formula | `openjdk-valhalla@27` | Valhalla JDK 27 | Pinned OpenJDK Valhalla source revision |
| Source/bottle formula | `openjdk-valhalla@28` | Valhalla JDK 28 | Pinned OpenJDK Valhalla source revision |

The canonical repository will document prebuilt packages as the fast default.
The source formulas are the explicit choice for users who need a locally built
or Homebrew-bottled JDK. Versioned tokens remain available so users and `jenv`
configurations can select a stable line without following the alias.

The `jdk26ea` token will not move into the canonical repository. It remains a
legacy compatibility token in `artagon/homebrew-jdk26ea`, updated to the
official OpenJDK 26.0.2 GA artifacts before that repository is archived.

## Repository Roles After Migration

### `artagon/homebrew-jdkvalhalla`

The canonical repository owns:

- all supported Valhalla prebuilt casks and formulas;
- all supported Valhalla source formulas and bottles;
- update, validation, and bottle release workflows;
- install instructions, version selection, and `jenv` integration;
- security tests for workflow permissions, action pinning, required-check
  aggregation, and release artifact validation.

### `artagon/homebrew-jdk26ea`

The legacy repository owns only:

- a working `jdk26ea` formula and cask pinned to OpenJDK 26.0.2 GA;
- a deprecation notice and migration link to the canonical Valhalla tap.

It will receive no new Valhalla release lines. After the compatibility package
and redirect are merged and verified, the repository will be archived.

## Migration Architecture

### Prebuilt distribution

The existing `jdkvalhalla` cask and versioned `jdkvalhalla@26` and
`jdkvalhalla@27` formulas remain backward compatible. Their update automation
continues to use official OpenJDK download metadata, validates all external
values, verifies downloaded archives against trusted checksums, and creates a
pull request instead of committing directly to `main`.

Update automation receives only the permissions required to create its pull
request. Checkout credentials do not persist into later steps. Any action used
by the workflow is pinned to a full commit SHA.

### Source and bottle distribution

The `openjdk-valhalla@27` and `openjdk-valhalla@28` formulas are ported from the
legacy pull request and adapted to the canonical naming, documentation, and
workflow conventions. `openjdk-valhalla` points to the current supported source
line.

Bottle publication is split into two trust zones:

1. A read-only build job checks out the exact triggering commit, builds the
   formula, and emits bottle files plus metadata.
2. A publication job validates the exact artifact set and metadata before it
   receives write permission. It creates an atomic tag at `GITHUB_SHA`, verifies
   that tag, rejects an existing tag or release, and uploads without clobbering
   existing assets.

The validator rejects missing, extra, duplicate, ambiguously named, or
checksum-mismatched artifacts. Upload and download actions are pinned to full
commit SHAs.

## Validation and Workflow Security

The consolidation replaces the current manually posted aggregate commit status
with a normal GitHub Actions job named `Validation Status`. That job:

- runs with `if: always()`;
- declares every required validation and installation job in `needs`;
- checks every dependency result explicitly;
- fails if a dependency is skipped, cancelled, or unsuccessful;
- requires no write token and posts no synthetic status.

The workflow declares top-level `permissions: contents: read`. Jobs that need
additional permissions receive them locally. Checkout steps disable persisted
credentials unless a job has a documented need to perform a Git operation.

Repository settings after the consolidation merge will:

- default workflow tokens to read-only;
- prevent workflows from approving pull-request reviews;
- require full commit SHA action pinning;
- enable immutable releases;
- bind required checks to the GitHub Actions app;
- require the latest pushed commit to be approved;
- require conversation resolution;
- enforce branch protection for administrators;
- disallow force pushes and branch deletion.

Required check names will be rebuilt from the actual consolidated workflow job
names. Stale macOS 13/14 contexts and the manually posted `Validate` context
will be removed.

## Existing Pull Request Disposition

The consolidation branch incorporates relevant changes before closing any
canonical pull request:

| Pull request | Disposition |
| --- | --- |
| `homebrew-jdkvalhalla#5` | Reconcile the Valhalla 27 package update against current official metadata; close as superseded by the consolidation pull request. |
| `homebrew-jdkvalhalla#6` | Use the reviewed full-SHA CodeQL action update if still current; close as superseded. |
| `homebrew-jdkvalhalla#7` | Use the reviewed full-SHA pull-request action update if still current; close as superseded. |
| `homebrew-jdkvalhalla#8` | Use the reviewed full-SHA cache action update if still current; close as superseded. |
| `homebrew-jdkvalhalla#9` | Use the reviewed full-SHA release action update if still current; close as superseded. |
| `homebrew-jdkvalhalla#10` | Use the reviewed full-SHA checkout action update if still current; close as superseded. |
| `homebrew-jdk26ea#6` | Port the source formulas, validator, tests, documentation, and security improvements; then close without merging the mixed legacy/canonical change. |

No pull request is closed until its relevant content has either been included
in the consolidation branch or explicitly rejected with a recorded reason.

## Migration and Merge Sequence

1. Build the canonical consolidation branch.
2. Port source formulas, the current-version alias, artifact validator, bottle
   workflow, documentation, and security tests.
3. Reconcile and harden the prebuilt binary update workflow.
4. Replace aggregate validation and align required checks with actual jobs.
5. Run local syntax, policy, validator, and workflow-security tests.
6. Push one canonical consolidation pull request and confirm all required checks
   pass.
7. Close canonical pull requests `#5` through `#10` as superseded, with links to
   the consolidation pull request and the incorporated commit or decision.
8. Leave the canonical pull request ready for the repository owner to merge.
9. After the owner merges it, apply the final canonical repository security
   settings and verify package installs from the merged default branch.
10. Close legacy pull request `homebrew-jdk26ea#6` as superseded.
11. Create a minimal legacy cleanup pull request containing the OpenJDK 26.0.2
    compatibility update, deprecation notice, canonical migration link, and the
    fail-closed validation-status correction required by the repository's
    read-only workflow token policy.
12. Let the repository owner merge the legacy cleanup pull request.
13. Verify the legacy compatibility token and canonical installation paths.
14. Archive `artagon/homebrew-jdk26ea`.

## Branch Protection and Owner Merge Choreography

The canonical repository currently allows administrators to bypass branch
protection. The owner can therefore merge the consolidation pull request after
its checks pass without removing review requirements. Immediately after that
merge, administrator enforcement and the other final security settings are
enabled.

The legacy repository currently enforces branch protection for administrators
and has only one direct collaborator. For the final compatibility pull request:

1. keep required checks and the review rule configured;
2. temporarily disable administrator enforcement only after all required checks
   pass;
3. have the owner merge the exact approved head commit;
4. verify the merge commit and installation;
5. archive the repository immediately.

If the legacy merge cannot be completed in that narrow window, administrator
enforcement is restored and the repository remains unarchived. No checks,
force-push restrictions, or deletion restrictions are relaxed.

## Verification Matrix

| Area | Required evidence |
| --- | --- |
| Formula and cask syntax | `ruby -c` succeeds for every Ruby package file. |
| Homebrew policy | `brew style` and applicable `brew audit` checks succeed. |
| Prebuilt packages | CI installs each supported prebuilt token and executes `java -version`; representative jobs compile and run a small program. |
| Source formulas | Formula structure, pinned revisions, dependencies, resource checksums, and tests pass without forcing a full source build in migration CI. |
| Artifact validator | Positive fixture succeeds; missing, extra, duplicate, ambiguous, and checksum-mismatch fixtures fail. |
| Workflow security | Tests prove read-only defaults, least-privilege job grants, non-persisted checkout credentials, full-SHA action pins, exact artifact validation, and fail-closed aggregation. |
| Required checks | GitHub branch protection lists only live job contexts bound to the expected GitHub Actions app. |
| Canonical install | Fresh tap install succeeds for the current prebuilt cask/formula; token paths are usable by `jenv`. |
| Legacy compatibility | Fresh tap install of `jdk26ea` resolves OpenJDK 26.0.2 and executes `java -version`. |
| Archive | Legacy repository is archived only after both canonical and compatibility verification records exist. |

Long-running source builds and bottle production remain explicit manual
operations. A source release is not published until its full build and bottle
validation workflow succeeds.

## Rollback and Archive Gates

- The legacy repository remains active until the canonical consolidation is
  merged and canonical installs are verified.
- Failure of the canonical pull request leaves both repositories unchanged.
- Failure after canonical merge blocks legacy archival; the compatibility tap
  remains available while the canonical defect is fixed.
- Failure of the legacy compatibility pull request restores administrator
  enforcement and leaves the repository unarchived.
- Existing tags, releases, or bottle assets are never overwritten. A conflicting
  immutable release causes publication to fail for manual investigation.
- Archival is the final action. The archive gate requires the merged commit
  SHAs, successful install evidence, redirected documentation, and closed or
  transferred open work.

## Risks and Residual Limits

- Official Valhalla early-access URLs and page structure can change. Update
  automation must fail rather than guessing when metadata does not match its
  allowlist.
- Linux ARM64 and older macOS runner coverage may be constrained by available
  GitHub-hosted runners. Unsupported matrix entries must be documented rather
  than implied.
- Source builds are expensive. Migration CI validates definitions and controls,
  while release workflows supply the durable full-build evidence.
- A single-maintainer repository cannot satisfy a required independent approval
  without another reviewer. The owner merge choreography is therefore explicit,
  narrow, and followed by stronger final enforcement.

## Acceptance Criteria

The consolidation is complete when:

1. one canonical pull request contains the approved package surface and security
   controls;
2. its required checks pass and the owner merges it;
3. canonical repository protections are hardened and verified;
4. canonical prebuilt installation succeeds from `main`;
5. the minimal legacy compatibility pull request is merged and `jdk26ea`
   installation succeeds;
6. superseded pull requests are closed with traceable reasons; and
7. `artagon/homebrew-jdk26ea` is archived.
