# Canonical Valhalla Tap Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `artagon/homebrew-jdkvalhalla` the secure canonical tap for prebuilt and source-built OpenJDK Project Valhalla releases while preserving its existing package tokens.

**Architecture:** Keep the existing prebuilt cask and formulas as the fast installation path, and add versioned source formulas plus a rolling alias. Separate read-only build/update work from narrowly scoped publication jobs, validate exact artifacts before any write, and use one fail-closed GitHub Actions check for branch protection.

**Tech Stack:** Homebrew Ruby DSL, Ruby 3 and Minitest, Bats, Bash, GitHub Actions YAML, `actionlint`, `shellcheck`, GitHub CLI.

## Global Constraints

- The canonical repository is `artagon/homebrew-jdkvalhalla`.
- Preserve `jdkvalhalla`, `jdkvalhalla@26`, and `jdkvalhalla@27`.
- Add `openjdk-valhalla`, `openjdk-valhalla@27`, and `openjdk-valhalla@28`.
- Do not add `jdk26ea` to the canonical repository.
- Do not add general OpenJDK releases unrelated to Project Valhalla.
- Do not run a full Valhalla source build in migration CI.
- Every GitHub Action reference is a full 40-character commit SHA.
- Pull-request validation defaults to `permissions: contents: read`.
- Checkout credentials use `persist-credentials: false`.
- Publication rejects missing, extra, duplicate, ambiguous, or checksum-mismatched artifacts.
- Existing tags, releases, and bottle assets are immutable and are never overwritten.
- The repository owner merges the consolidation pull request.
- Use Conventional Commit messages.

---

## File Map

### Package surface

- Create `Formula/openjdk-valhalla@27.rb`: pinned source build for the JEP 401
  EA3 milestone.
- Create `Formula/openjdk-valhalla@28.rb`: pinned source build for the reviewed
  Valhalla `lworld` snapshot.
- Create `Aliases/openjdk-valhalla`: relative symlink to
  `../Formula/openjdk-valhalla@28.rb`.
- Preserve `Formula/jdkvalhalla@26.rb`, `Formula/jdkvalhalla@27.rb`, and
  `Casks/jdkvalhalla.rb`: official prebuilt packages.

### Validation and automation

- Create `scripts/validate-bottle-artifact.rb`: exact bottle/JSON validator.
- Create `scripts/parse-valhalla-release.rb`: strict parser for the official
  Valhalla release page.
- Create `tests/formula_contract.bats`: package-token and source-formula
  contracts.
- Create `tests/bottle_artifact_validator_test.rb`: validator unit tests.
- Create `tests/parse_valhalla_release_test.rb`: release parser unit tests.
- Create `tests/workflow_security_test.rb`: workflow permissions, action pins,
  artifact binding, and aggregation tests.
- Create `.github/workflows/bottles.yml`: manual source build and immutable
  GHCR bottle publication.
- Modify `.github/workflows/validate.yml`: read-only, fail-closed validation and
  prebuilt installation matrix.
- Modify `.github/workflows/update.yml`: read-only preparation followed by a
  narrowly scoped pull-request job.
- Modify `.github/workflows/audit.yml`: current immutable checkout action and
  read-only checkout.
- Modify `.github/workflows/codeql.yml`: current immutable checkout and CodeQL
  actions.
- Delete `.github/workflows/release.yml`: remove the unused prebuilt GitHub
  release workflow; bottle packages are owned by `bottles.yml`.
- Modify `scripts/test.sh`: include all static tests and all supported package
  files without forcing source builds.

### Documentation

- Modify `README.md`: describe prebuilt versus source installations, all tokens,
  build-time warning, and `jenv` registration.
- Modify `SECURITY.md`: document the trust zones, immutable releases, checksum
  handling, and reporting path.

## Exact Reviewed Action Revisions

Use these full revisions:

| Action | Revision |
| --- | --- |
| `actions/checkout` v6.0.2 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| `actions/cache` v5.0.5 | `27d5ce7f107fe9357f9df03efb73ab90386fccae` |
| `actions/upload-artifact` v4 | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| `actions/download-artifact` v4 | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |
| `github/codeql-action/init` v3.31.0 | `d198d2fabf39a7f36b5ce57ce70d4942944f006e` |
| `github/codeql-action/analyze` v3.31.0 | `d198d2fabf39a7f36b5ce57ce70d4942944f006e` |
| `peter-evans/create-pull-request` v8.1.1 | `5f6978faf089d4d20b00c7766989d076bb2fc7f1` |
| `Homebrew/actions/setup-homebrew` | `b2a302b9a642580cae998e6ba2076ffd28e61317` |

### Task 1: Add the versioned source formulas and rolling alias

**Files:**
- Create: `tests/formula_contract.bats`
- Create: `Formula/openjdk-valhalla@27.rb`
- Create: `Formula/openjdk-valhalla@28.rb`
- Create: `Aliases/openjdk-valhalla`

**Interfaces:**
- Consumes: reviewed source formula content from
  `artagon/homebrew-jdk26ea` commit
  `bc34b97a7daa54f29e0f06b3a0d44fb521ead1d3`.
- Produces: Homebrew tokens `openjdk-valhalla@27`,
  `openjdk-valhalla@28`, and `openjdk-valhalla`.

- [ ] **Step 1: Write the package contract**

Create `tests/formula_contract.bats` with tests that:

```bash
setup() {
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/.." && pwd -P)"
}

@test "all supported package definitions are valid Ruby" {
  local package
  for package in \
    Formula/jdkvalhalla@26.rb \
    Formula/jdkvalhalla@27.rb \
    Formula/openjdk-valhalla@27.rb \
    Formula/openjdk-valhalla@28.rb \
    Casks/jdkvalhalla.rb; do
    run ruby -c "${REPO_ROOT}/${package}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "Syntax OK" ]
  done
}

@test "rolling source token resolves to JDK 28" {
  run readlink "${REPO_ROOT}/Aliases/openjdk-valhalla"
  [ "${status}" -eq 0 ]
  [ "${output}" = "../Formula/openjdk-valhalla@28.rb" ]
}
```

Add assertions that the JDK 27 source URL contains
`f9799f4c1a35694951413fda0986cdebe49f85d0`, the JDK 28 source URL contains
`f181286389fad995be1e71de60f30d14eb1c9122`, both formulas require ARM64,
macOS Sonoma, Xcode 15.4, and the boot JDK resource, and neither source formula
contains a mutable branch URL.

- [ ] **Step 2: Run the contract and verify it fails**

Run:

```bash
rtk bats tests/formula_contract.bats
```

Expected: FAIL because the source formulas and alias do not exist.

- [ ] **Step 3: Port the reviewed source formulas**

Port the two formula files exactly from commit
`bc34b97a7daa54f29e0f06b3a0d44fb521ead1d3`. Preserve these immutable
coordinates:

```ruby
# openjdk-valhalla@27
url "https://github.com/openjdk/valhalla/archive/f9799f4c1a35694951413fda0986cdebe49f85d0.tar.gz"
version "27-ea-20260310-f9799f4c1a35"
sha256 "eb44694f4525aa7e57a6304d4c01f17ffaf78824ec76016e512742b643664367"

# openjdk-valhalla@28
url "https://github.com/openjdk/valhalla/archive/f181286389fad995be1e71de60f30d14eb1c9122.tar.gz"
version "28-ea-20260727-f181286389fa"
sha256 "d44923f1e68651f85080e53a27afd23fcc3ac23e0022bde7ba1309ca0d5bcf25"
```

Both formulas keep these build constraints:

```ruby
depends_on "autoconf" => :build
depends_on "make" => :build
depends_on "pkgconf" => :build
depends_on xcode: ["15.4", :build]
depends_on arch: :arm64
depends_on macos: :sonoma
```

Keep the four-job cap, version-specific preview smoke test, pinned OpenJDK 26
boot JDK, `keg_only :versioned_formula`, and system library dependencies.

- [ ] **Step 4: Create the rolling alias**

Run from the repository root:

```bash
mkdir -p Aliases
ln -s ../Formula/openjdk-valhalla@28.rb Aliases/openjdk-valhalla
```

- [ ] **Step 5: Run focused validation**

Run:

```bash
rtk bats tests/formula_contract.bats
rtk brew style Formula/openjdk-valhalla@27.rb Formula/openjdk-valhalla@28.rb
rtk brew audit --formula artagon/jdkvalhalla/openjdk-valhalla@27
rtk brew audit --formula artagon/jdkvalhalla/openjdk-valhalla@28
```

Expected: all checks PASS. Do not run `brew install` for either source formula.

- [ ] **Step 6: Commit**

```bash
rtk git add Aliases/openjdk-valhalla Formula/openjdk-valhalla@27.rb Formula/openjdk-valhalla@28.rb tests/formula_contract.bats
rtk git commit -m "feat(formula): add versioned Valhalla source builds"
```

### Task 2: Add exact bottle artifact validation

**Files:**
- Create: `tests/bottle_artifact_validator_test.rb`
- Create: `scripts/validate-bottle-artifact.rb`

**Interfaces:**
- Consumes: a directory containing one `*.bottle.tar.gz` and one
  `*.bottle.json`.
- Produces: `bottle_path` and `json_path` entries in the file passed to
  `--github-output`.

- [ ] **Step 1: Write validator tests**

Port the reviewed tests from commit `bc34b97a7daa54f29e0f06b3a0d44fb521ead1d3`,
then set:

```ruby
TAP = "artagon/jdkvalhalla"
ROOT_URL = "https://ghcr.io/v2/artagon/jdkvalhalla"
```

Keep the valid-artifact, extra-bottle, wrong-revision, and checksum-mismatch
tests. Add:

```ruby
def test_rejects_additional_json_files
  Dir.mktmpdir do |directory|
    write_valid_artifact(directory)
    File.write(File.join(directory, "unexpected.bottle.json"), "{}")
    _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))
    refute status.success?
    assert_includes stderr, "expected exactly one bottle JSON"
  end
end

def test_rejects_remote_filename_with_encoded_path_separator
  Dir.mktmpdir do |directory|
    _bottle_path, json_path = write_valid_artifact(directory)
    payload = JSON.parse(File.read(json_path))
    metadata = payload.fetch("#{TAP}/#{FORMULA}").fetch("bottle").fetch("tags").values.first
    metadata["filename"] = "nested%2F#{BOTTLE}"
    File.write(json_path, JSON.pretty_generate(payload))
    _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))
    refute status.success?
    assert_includes stderr, "remote bottle filename does not match"
  end
end
```

Add a symlink test for both archive and JSON paths.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
rtk ruby tests/bottle_artifact_validator_test.rb
```

Expected: FAIL because the validator does not exist.

- [ ] **Step 3: Port and adapt the validator**

Port `scripts/validate-bottle-artifact.rb` from the reviewed legacy commit.
Retain these validations:

```ruby
fail_validation("invalid formula token") unless formula.match?(/\Aopenjdk-valhalla@\d+\z/)
fail_validation("invalid git revision") unless git_revision.match?(/\A[0-9a-f]{40}\z/)
fail_validation("expected exactly one bottle archive, found #{bottle_paths.length}") unless bottle_paths.one?
fail_validation("expected exactly one bottle JSON, found #{json_paths.length}") unless json_paths.one?
```

Require the exact canonical GHCR root URL derived from the tap name.
Require exact tap/formula name, version, formula path, Git revision, root URL,
single ARM64 tag, Homebrew-derived local and encoded remote filenames, and
SHA-256.
Reject symlinks. Write only real paths to the GitHub output file with mode
`0600`.

- [ ] **Step 4: Run validator tests**

Run:

```bash
rtk ruby tests/bottle_artifact_validator_test.rb
rtk ruby -c scripts/validate-bottle-artifact.rb
```

Expected: all tests PASS and syntax is valid.

- [ ] **Step 5: Commit**

```bash
rtk git add scripts/validate-bottle-artifact.rb tests/bottle_artifact_validator_test.rb
rtk git commit -m "feat(scripts): validate exact bottle artifacts"
```

### Task 3: Add the split-trust bottle workflow

**Files:**
- Create: `tests/workflow_security_test.rb`
- Create: `.github/workflows/bottles.yml`

**Interfaces:**
- Consumes: workflow input `formula`, restricted to
  `openjdk-valhalla@27` or `openjdk-valhalla@28`.
- Produces: an immutable GHCR bottle package plus a pull request containing only
  `Formula/<formula>.rb`. The temporary workflow artifact is named
  `bottle-<formula>-<version>-<12-char-main-SHA>`.

- [ ] **Step 1: Write workflow security tests**

Create tests that load every `.github/workflows/*.yml` with `YAML.load_file`.
For `bottles.yml`, assert:

```ruby
assert_equal({}, document["permissions"])
assert_equal({ "contents" => "read" }, build["permissions"])
assert_equal(
  { "contents" => "write", "packages" => "write", "pull-requests" => "write" },
  publish["permissions"],
)
assert checkout_steps(document).all? {
  |step| step.dig("with", "persist-credentials") == false
}
```

Also assert that:

- build verifies `refs/heads/main`;
- artifact text contains `${GITHUB_SHA::12}`;
- publication runs only for `refs/heads/main`;
- publication uses `brew pr-upload --upload-only`;
- no command enables `--keep-old`;
- a retry may tolerate an existing upload only before a token-free `skopeo`
  inspection verifies the exact ARM64 macOS bottle digest;
- upload paths come only from validator outputs;
- package and merge steps use validator outputs, not globs or `find`;
- all action references match `\A[^@\s]+@[0-9a-f]{40}\z`.

- [ ] **Step 2: Run the workflow test and verify it fails**

Run:

```bash
rtk ruby tests/workflow_security_test.rb
```

Expected: FAIL because `bottles.yml` does not exist.

- [ ] **Step 3: Port and adapt the bottle workflow**

Port `.github/workflows/bottles.yml` from the reviewed legacy commit. Change
both tap values to:

```yaml
env:
  TAP: artagon/jdkvalhalla
```

Use the exact action revisions from this plan. Keep `permissions: {}` at the
workflow level, `contents: read` on `build`, and `contents: write` plus
`packages: write` and `pull-requests: write` only on `publish`. Scope
`HOMEBREW_GITHUB_PACKAGES_TOKEN` to the package step. Keep the exact validator
call in both trust zones. Since new GHCR packages default to private, require an
anonymous exact-digest inspection after upload and before the bottle-block pull
request. On a first publication, the owner makes the new package public and
reruns the workflow; the rerun may skip the existing upload only because the
anonymous inspection remains mandatory.

- [ ] **Step 4: Validate the workflow**

Run:

```bash
rtk ruby tests/workflow_security_test.rb
rtk actionlint .github/workflows/bottles.yml
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add .github/workflows/bottles.yml tests/workflow_security_test.rb
rtk git commit -m "ci(workflow): publish immutable Valhalla bottle packages"
```

### Task 4: Make pull-request validation read-only and fail-closed

**Files:**
- Modify: `tests/workflow_security_test.rb`
- Modify: `.github/workflows/validate.yml`
- Modify: `scripts/test.sh`

**Interfaces:**
- Consumes: results from `validate-static`, `test-cask-macos`, and
  `test-prebuilt-formula`.
- Produces: one required check named `Validation Status`.

- [ ] **Step 1: Add failing validation-policy tests**

Add assertions:

```ruby
document = workflow("validate.yml")
assert_equal({ "contents" => "read" }, document["permissions"])
status = document.fetch("jobs").fetch("validation-status")
assert_equal "${{ always() }}", status["if"]
assert_equal %w[validate-static test-cask-macos test-prebuilt-formula].sort,
             status["needs"].sort
```

Assert the `Confirm completion` step has these exact environment keys:

```ruby
{
  "VALIDATE_STATIC_RESULT" => "${{ needs.validate-static.result }}",
  "TEST_CASK_MACOS_RESULT" => "${{ needs.test-cask-macos.result }}",
  "TEST_PREBUILT_FORMULA_RESULT" => "${{ needs.test-prebuilt-formula.result }}",
}
```

Assert its shell loops over every value, requires `success`, and exits `1` on
any other result. Assert no step posts a commit status and no step exposes
`GH_TOKEN`.

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
rtk ruby tests/workflow_security_test.rb
```

Expected: FAIL against the current synthetic `Validate` status workflow.

- [ ] **Step 3: Replace the validation workflow**

Use these jobs:

1. `validate-static` on `macos-14`: Ruby syntax for every formula/cask,
   Homebrew style/audit, Bats contracts, Ruby unit tests, `actionlint`, and
   `shellcheck`.
2. `test-cask-macos`: matrix `macos-14` and `macos-15`, install
   `artagon/jdkvalhalla/jdkvalhalla`, run its absolute `java -version`, and
   uninstall under `if: always()`.
3. `test-prebuilt-formula`: matrix of `jdkvalhalla@26` and
   `jdkvalhalla@27` on Ubuntu 24.04, install, run `java -version`, compile and
   run `HelloWorld.java`, and uninstall under `if: always()`.
4. `validation-status` named `Validation Status`, `if: ${{ always() }}`, with
   explicit dependency-result verification and no token.

Every checkout uses:

```yaml
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
  with:
    persist-credentials: false
```

The source formulas receive syntax, policy, dependency, resource, and test
contract validation only. No CI step installs them.

- [ ] **Step 4: Update the local validation script**

Make `scripts/test.sh` run:

```bash
rtk bats tests/formula_contract.bats
rtk ruby tests/bottle_artifact_validator_test.rb
rtk ruby tests/workflow_security_test.rb
rtk ruby tests/parse_valhalla_release_test.rb
```

The shell script itself must call the underlying executables without `rtk`
because RTK is an agent-side wrapper, not a repository runtime dependency.
Keep local install behavior limited to prebuilt `jdkvalhalla@27` and the cask.
Add style/audit loops for every Ruby package file.

- [ ] **Step 5: Run focused validation**

Run:

```bash
rtk ruby tests/workflow_security_test.rb
rtk bats tests/formula_contract.bats
rtk actionlint .github/workflows/validate.yml
rtk shellcheck scripts/test.sh tests/formula_contract.bats
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add .github/workflows/validate.yml scripts/test.sh tests/workflow_security_test.rb
rtk git commit -m "ci(workflow): make validation fail closed"
```

### Task 5: Harden prebuilt update automation

**Files:**
- Create: `scripts/parse-valhalla-release.rb`
- Create: `tests/parse_valhalla_release_test.rb`
- Modify: `tests/workflow_security_test.rb`
- Modify: `.github/workflows/update.yml`

**Interfaces:**
- `parse-valhalla-release.rb PAGE OUTPUT` consumes saved official HTML and
  appends `full_version`, `jdk_version`, `ea_tag`, and `build` to `OUTPUT`.
- `prepare` produces an artifact containing exactly one versioned prebuilt
  formula and `Casks/jdkvalhalla.rb`.
- `create-pr` consumes that exact artifact and opens a pull request.

- [ ] **Step 1: Write release-parser tests**

Create tests for one valid release, no release, two different releases, and a
value containing a newline. The valid fixture contains:

```html
<a href="/java/early_access/valhalla/27/1/">27-jep401ea3+1-1</a>
```

The success assertion is exactly:

```ruby
assert_equal(
  "full_version=27-jep401ea3+1-1\n" \
  "jdk_version=27\n" \
  "ea_tag=jep401ea3\n" \
  "build=1\n",
  File.read(output),
)
```

Ambiguous pages must fail with `expected exactly one Valhalla version`.

- [ ] **Step 2: Run parser tests and verify they fail**

Run:

```bash
rtk ruby tests/parse_valhalla_release_test.rb
```

Expected: FAIL because the parser does not exist.

- [ ] **Step 3: Implement the strict parser**

Use:

```ruby
pattern = /\b(?<full>(?<jdk>\d{2})-(?<tag>jep401ea\d+)\+(?<build>\d+)-\d+)\b/
matches = File.read(ARGV.fetch(0), encoding: "UTF-8").scan(pattern)
versions = matches.map(&:first).uniq
abort "expected exactly one Valhalla version" unless versions.one?
match = pattern.match(versions.fetch(0))
abort "invalid JDK line" unless (26..99).cover?(Integer(match[:jdk], 10))
abort "invalid build" unless (1..999).cover?(Integer(match[:build], 10))
```

Reject carriage returns and newlines in every output value. Append the four
keys to `ARGV.fetch(1)` with mode `0600`.

- [ ] **Step 4: Add update-workflow security assertions**

Assert:

- workflow-level `permissions: {}`;
- `prepare.permissions == { "contents" => "read" }`;
- `create-pr.permissions == { "contents" => "write", "pull-requests" => "write" }`;
- every checkout disables persisted credentials;
- only `create-pr` uses `peter-evans/create-pull-request`;
- `prepare` calls `scripts/parse-valhalla-release.rb`;
- checksums match `^[0-9a-f]{64}$` and downloaded archives are hashed;
- the upload artifact contains only
  `Casks/jdkvalhalla.rb` and `Formula/jdkvalhalla@${JDK_VERSION}.rb`;
- `create-pr` validates those exact two paths before copying them;
- the pull-request action uses revision
  `5f6978faf089d4d20b00c7766989d076bb2fc7f1`.

- [ ] **Step 5: Split and harden `.github/workflows/update.yml`**

Use `prepare` for page download, strict parse, URL construction, remote
checksum fetch, independent archive download/hash verification, deterministic
file updates, Ruby syntax, and artifact upload. Use `create-pr` only to check
out the triggering main SHA, download the generated package files, verify the
exact two-file allowlist, rerun Ruby syntax, copy them into place, and invoke
the pull-request action.

Use the checkout, cache, upload, download, and pull-request revisions in this
plan. Set:

```yaml
permissions: {}

jobs:
  prepare:
    permissions:
      contents: read
  create-pr:
    needs: prepare
    permissions:
      contents: write
      pull-requests: write
```

Retain the official roots only:

```text
https://jdk.java.net/valhalla/
https://download.java.net/java/early_access/valhalla/
```

Reject any constructed URL whose parsed scheme is not HTTPS or whose host is
not `download.java.net`.

- [ ] **Step 6: Run focused tests**

Run:

```bash
rtk ruby tests/parse_valhalla_release_test.rb
rtk ruby tests/workflow_security_test.rb
rtk actionlint .github/workflows/update.yml
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
rtk git add .github/workflows/update.yml scripts/parse-valhalla-release.rb tests/parse_valhalla_release_test.rb tests/workflow_security_test.rb
rtk git commit -m "ci(workflow): isolate prebuilt update permissions"
```

### Task 6: Reconcile supporting workflows and remove the unused release path

**Files:**
- Modify: `.github/workflows/audit.yml`
- Modify: `.github/workflows/codeql.yml`
- Modify: `tests/workflow_security_test.rb`
- Delete: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: exact reviewed action revisions in this plan.
- Produces: read-only audit and CodeQL workflows; bottle packages are the only
  repository-owned release path.

- [ ] **Step 1: Add policy assertions**

Assert every workflow has explicit top-level permissions, every checkout
disables persisted credentials, and every `uses:` value has a full SHA.
Assert `.github/workflows/release.yml` does not exist.

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
rtk ruby tests/workflow_security_test.rb
```

Expected: FAIL on current supporting workflows and the obsolete release file.

- [ ] **Step 3: Update audit and CodeQL**

Use checkout `de0fac2e4500dabe0009e67214ff5f5447ce83dd`. Use CodeQL init and
analyze `d198d2fabf39a7f36b5ce57ce70d4942944f006e`. Give audit only
`contents: read`. Give CodeQL the documented minimum:

```yaml
permissions:
  contents: read
  security-events: write
```

Disable persisted checkout credentials in both workflows.

- [ ] **Step 4: Delete `.github/workflows/release.yml`**

Remove it because it publishes no prebuilt JDK artifact, performs best-effort
audits, and duplicates version/release ownership. Keep source bottles under
the validated `bottles.yml` path.

- [ ] **Step 5: Run validation**

Run:

```bash
rtk ruby tests/workflow_security_test.rb
rtk actionlint .github/workflows/audit.yml .github/workflows/codeql.yml .github/workflows/bottles.yml .github/workflows/update.yml .github/workflows/validate.yml
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add .github/workflows tests/workflow_security_test.rb
rtk git commit -m "ci(workflow): pin actions and remove obsolete releases"
```

### Task 7: Document both installation modes and `jenv`

**Files:**
- Create: `tests/documentation_contract.bats`
- Modify: `README.md`
- Modify: `SECURITY.md`

**Interfaces:**
- Consumes: final package tokens and workflow trust model.
- Produces: user-facing install, source-build, `jenv`, and security guidance.

- [ ] **Step 1: Write documentation contracts**

Assert `README.md` contains every canonical token, both commands below, the
source-build warning, and both `jenv add` examples:

```bash
brew install --cask artagon/jdkvalhalla/jdkvalhalla
brew install artagon/jdkvalhalla/jdkvalhalla@27
brew install artagon/jdkvalhalla/openjdk-valhalla@28
jenv add "$(brew --prefix openjdk-valhalla@27)/libexec/openjdk.jdk/Contents/Home"
jenv add "$(brew --prefix openjdk-valhalla@28)/libexec/openjdk.jdk/Contents/Home"
```

Assert `SECURITY.md` contains `read-only`, `full commit SHA`, `immutable
release`, `checksum`, and private vulnerability reporting instructions.

- [ ] **Step 2: Run the documentation contract and verify it fails**

Run:

```bash
rtk bats tests/documentation_contract.bats
```

Expected: FAIL because source tokens and the final trust model are absent.

- [ ] **Step 3: Update `README.md`**

Document:

- prebuilt cask as the macOS fast default;
- `jdkvalhalla@26` and `jdkvalhalla@27` as versioned prebuilt formulas;
- `openjdk-valhalla` as the rolling source/bottle alias;
- `openjdk-valhalla@27` and `openjdk-valhalla@28` as source lines;
- Homebrew uses a compatible bottle when present and otherwise builds from
  source;
- source builds are long-running and capped at four jobs;
- `brew info` should be checked before an unexpected source build;
- version-specific `jenv add` commands and `jenv local`/`jenv global` usage;
- EA builds are not production JDKs.

- [ ] **Step 4: Update `SECURITY.md`**

Document official source allowlists, checksum verification, source revision
pinning, read-only validation, split bottle trust zones, exact artifact
validation, immutable tags/releases, action SHA pinning, and the private
vulnerability reporting route.

- [ ] **Step 5: Run documentation tests**

Run:

```bash
rtk bats tests/documentation_contract.bats
rtk markdownlint README.md SECURITY.md docs/superpowers/specs/2026-07-28-valhalla-tap-consolidation-design.md
```

If `markdownlint` is not installed, record that fact and rely on the contract,
diff review, and GitHub rendering. Do not install a new dependency solely for
this task.

- [ ] **Step 6: Commit**

```bash
rtk git add README.md SECURITY.md tests/documentation_contract.bats
rtk git commit -m "docs: explain prebuilt and source Valhalla installs"
```

### Task 8: Run the complete local migration gate

**Files:**
- Modify only if a test exposes a defect in files already listed above.

**Interfaces:**
- Consumes: all canonical implementation commits.
- Produces: a clean branch with durable local validation evidence.

- [ ] **Step 1: Run static and unit tests**

```bash
rtk bats tests/formula_contract.bats tests/documentation_contract.bats
rtk ruby tests/bottle_artifact_validator_test.rb
rtk ruby tests/parse_valhalla_release_test.rb
rtk ruby tests/workflow_security_test.rb
```

Expected: PASS.

- [ ] **Step 2: Run syntax and lint gates**

```bash
rtk ruby -c Formula/jdkvalhalla@26.rb
rtk ruby -c Formula/jdkvalhalla@27.rb
rtk ruby -c Formula/openjdk-valhalla@27.rb
rtk ruby -c Formula/openjdk-valhalla@28.rb
rtk ruby -c Casks/jdkvalhalla.rb
rtk actionlint .github/workflows/*.yml
rtk shellcheck scripts/test.sh tests/*.bats
```

Expected: PASS.

- [ ] **Step 3: Run Homebrew policy checks**

```bash
rtk brew style Casks/jdkvalhalla.rb Formula/jdkvalhalla@26.rb Formula/jdkvalhalla@27.rb Formula/openjdk-valhalla@27.rb Formula/openjdk-valhalla@28.rb
rtk brew audit --cask artagon/jdkvalhalla/jdkvalhalla
rtk brew audit --formula artagon/jdkvalhalla/jdkvalhalla@26
rtk brew audit --formula artagon/jdkvalhalla/jdkvalhalla@27
rtk brew audit --formula artagon/jdkvalhalla/openjdk-valhalla@27
rtk brew audit --formula artagon/jdkvalhalla/openjdk-valhalla@28
```

Expected: PASS. Do not suppress audit failures.

- [ ] **Step 4: Review the complete diff**

```bash
rtk git diff --check origin/main...HEAD
rtk git status --short --branch
rtk git log --oneline origin/main..HEAD
```

Expected: no whitespace errors, no unrelated files, and a clean worktree.

### Task 9: Publish one consolidation pull request and supersede canonical PRs

**Files:**
- No repository file changes.

**Interfaces:**
- Consumes: the verified branch.
- Produces: one canonical pull request and traceable disposition of PRs
  `#5` through `#10`.

- [ ] **Step 1: Push the consolidation branch**

```bash
rtk git push -u origin feat/consolidate-valhalla-taps
```

- [ ] **Step 2: Open the consolidation pull request**

Use title:

```text
feat: consolidate prebuilt and source Valhalla packages
```

The body lists the six package tokens, test commands, no-source-build
constraint, workflow security controls, and this PR mapping:

- `#5`: rejected because it substitutes the Linux x64 checksum for macOS ARM64
  and corrupts the Ruby test string;
- `#6`: CodeQL revision incorporated;
- `#7`: pull-request action revision incorporated;
- `#8`: cache action revision incorporated;
- `#9`: not incorporated because the obsolete release workflow is removed;
- `#10`: checkout revision incorporated.

- [ ] **Step 3: Wait for all pull-request checks**

Run:

```bash
rtk gh pr checks --watch --fail-fast
```

Expected: every job and `Validation Status` PASS. Do not merge.

- [ ] **Step 4: Close PRs `#5` through `#10`**

For each PR, post one concise comment linking the consolidation PR and its
specific disposition above, then close it. Re-read the PR state after each
close and record the confirmed state.

- [ ] **Step 5: Hand the passing consolidation PR to the owner**

Report the PR URL, exact head SHA, check result, incorporated/rejected PR map,
and that administrator enforcement is still disabled so the owner can merge.
Stop and wait for the owner to confirm the merge.

### Task 10: Harden canonical repository settings after owner merge

**Files:**
- No repository file changes.

**Interfaces:**
- Consumes: owner confirmation plus a verified `main` SHA containing the
  consolidation.
- Produces: read-only workflow defaults, SHA enforcement, immutable releases,
  app-bound required checks, and enforced branch protection.

- [ ] **Step 1: Verify the merge**

```bash
rtk gh pr view --json state,mergedAt,mergeCommit,headRefOid,url
rtk gh api repos/artagon/homebrew-jdkvalhalla/commits/main
```

Expected: PR state `MERGED`; `main` contains the recorded head.

- [ ] **Step 2: Set Actions permissions**

Use the official repository endpoints:

```bash
rtk gh api --method PUT repos/artagon/homebrew-jdkvalhalla/actions/permissions \
  -F enabled=true -f allowed_actions=all -F sha_pinning_required=true

rtk gh api --method PUT repos/artagon/homebrew-jdkvalhalla/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

- [ ] **Step 3: Enable immutable releases**

```bash
rtk gh api --method PUT repos/artagon/homebrew-jdkvalhalla/immutable-releases
```

- [ ] **Step 4: Replace branch protection atomically**

Send one `PUT` to
`repos/artagon/homebrew-jdkvalhalla/branches/main/protection` with:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": [],
    "checks": [
      {
        "context": "Validation Status",
        "app_id": 15368
      }
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1,
    "require_last_push_approval": true
  },
  "restrictions": null,
  "required_linear_history": false,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
```

Use a temporary JSON file outside the repository and delete it after the API
call. Do not print authentication headers or token-bearing configuration.

- [ ] **Step 5: Verify live settings**

Read back:

```bash
rtk gh api repos/artagon/homebrew-jdkvalhalla/actions/permissions
rtk gh api repos/artagon/homebrew-jdkvalhalla/actions/permissions/workflow
rtk gh api repos/artagon/homebrew-jdkvalhalla/immutable-releases
rtk gh api repos/artagon/homebrew-jdkvalhalla/branches/main/protection
```

Expected: SHA pinning true; default token read; workflow approval false;
immutable releases enabled; only `Validation Status` required with app ID
15368; latest-push approval, conversation resolution, and administrator
enforcement true; force pushes and deletions false.

- [ ] **Step 6: Verify canonical prebuilt installation**

In a clean temporary tap location, run:

```bash
rtk brew update
rtk brew tap artagon/jdkvalhalla
rtk brew install artagon/jdkvalhalla/jdkvalhalla@27
rtk brew test artagon/jdkvalhalla/jdkvalhalla@27
rtk brew uninstall artagon/jdkvalhalla/jdkvalhalla@27
```

On macOS, also install the cask, run the absolute `java -version`, and
uninstall it. Record the merged SHA and command results. Do not install a source
formula during this migration gate.

- [ ] **Step 7: Start the legacy compatibility/archive plan**

Proceed to
`docs/superpowers/plans/2026-07-28-legacy-jdk26ea-compatibility-archive.md`
only after all preceding checks succeed.

## External Documentation

- GitHub Actions permissions:
  <https://docs.github.com/en/rest/actions/permissions>
- GitHub branch protection:
  <https://docs.github.com/en/rest/branches/branch-protection>
- GitHub immutable releases:
  <https://docs.github.com/en/rest/repos/repos#enable-immutable-releases-for-a-repository>
