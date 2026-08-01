# Security Policy

## Report a vulnerability

Report suspected vulnerabilities privately through
[GitHub Security Advisories](https://github.com/artagon/homebrew-jdkvalhalla/security/advisories/new).
Do not open a public issue for a vulnerability or include credentials,
private keys, exploit data, or other sensitive material in public logs.

For non-sensitive package defects, use the public issue tracker.

## Trusted upstreams

Prebuilt package automation accepts release metadata only from:

- `https://jdk.java.net/valhalla/`
- `https://download.java.net/java/early_access/valhalla/`

Constructed archive URLs must use HTTPS, the exact `download.java.net` host,
and the Valhalla early-access path. The update workflow validates each
published SHA-256 checksum and independently hashes the downloaded archive
before generating a formula or cask.

Source formulas use commit-specific `openjdk/valhalla` archive URLs with
reviewed SHA-256 values. Their version strings include the pinned revision.
Boot JDK resources are also HTTPS URLs with fixed checksums.

## Workflow trust boundaries

Pull-request validation is read-only. Its aggregate `Validation Status` job
checks every required dependency result and fails if any job was skipped,
cancelled, or unsuccessful. It does not post a synthetic commit status or
hold a write token.

The prebuilt update workflow separates preparation from publication:

1. A read-only job parses official metadata, downloads and hashes archives,
   renders packages, and uploads an artifact containing exactly one versioned
   formula and the cask.
2. A narrowly write-scoped job checks out the same triggering commit,
   validates the artifact's exact path allowlist, reruns Ruby syntax, and opens
   a pull request containing only those files.

Source bottle publication has the same split trust model. A read-only job
builds and smoke-tests the pinned formula. The write-scoped job rejects extra
files, symlinks, version or revision drift, root URL changes, filename
ambiguity, and checksum mismatch before publication.

## Bottle packages

Versioned source bottles are published with Homebrew's GHCR client. A rerun
does not mutate an existing OCI package version. Before a bottle-block pull
request is opened, a token-free registry request must prove the package is
public and contains exactly one ARM64 macOS descriptor with the validated
bottle digest.

GitHub creates a new container package as private. On the first publication,
the workflow stops after upload until an owner makes that package public; the
rerun then verifies anonymous access and exact content. Homebrew records the
bottle SHA-256 in the formula, so later blob drift fails installation.

Repository settings should enable GitHub's immutable release option as
defense in depth, although current bottle distribution uses GHCR rather than
release assets.

## GitHub Actions controls

- Every workflow declares explicit least-privilege permissions.
- Repository checkout credentials are not persisted.
- Third-party actions are pinned to a full commit SHA.
- Write tokens are scoped to the individual publication job or step.
- Pull-request code never runs in a write-scoped update or bottle build job.
- Required checks should be bound to the GitHub Actions app, apply to
  administrators, require the latest approved commit, and reject force pushes
  or branch deletion.

Dependency updates and workflow changes require review. A moving action tag,
best-effort checksum validation, broad write permission, or unvalidated
artifact glob is not accepted.

## User verification

Inspect package metadata before installation:

```bash
brew info artagon/jdkvalhalla/jdkvalhalla@27
brew info artagon/jdkvalhalla/openjdk-valhalla@28
brew cat artagon/jdkvalhalla/openjdk-valhalla@28
```

Homebrew verifies formula, cask, resource, and bottle checksums automatically.
After installation, confirm the selected runtime:

```bash
java -version
```

Valhalla early-access builds are experimental and are not supported as
production JDKs.

## Incident response

If package or workflow integrity is in doubt, maintainers should disable the
affected workflow, stop publication, revoke exposed credentials, preserve
audit evidence, identify impacted revisions and artifacts, and notify users
through a security advisory. A repaired package must use a new reviewed
version or bottle revision rather than overwrite an existing published
artifact.
