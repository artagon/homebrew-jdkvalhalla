# Legacy JDK 26 Compatibility and Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Leave existing `artagon/homebrew-jdk26ea` users with a working OpenJDK 26.0.2 compatibility token, redirect Valhalla users to the canonical tap, and archive the legacy repository only after verified installs.

**Architecture:** Create a small cleanup pull request from legacy `main` rather than merging the mixed Valhalla PR. Update only the legacy formula/cask, a deprecation-focused README, the contract test, and the fail-closed validation job required by the repository's read-only token policy; then use a narrow owner-merge window and archive after durable verification.

**Tech Stack:** Homebrew Ruby DSL, Bats, Bash, GitHub Actions YAML, GitHub CLI.

## Global Constraints

- Start only after the canonical consolidation is merged and canonical
  prebuilt installation is verified.
- Keep the legacy token name `jdk26ea`.
- `jdk26ea` is OpenJDK 26.0.2 GA compatibility, not a Valhalla release.
- Do not port `openjdk-valhalla@27`, `openjdk-valhalla@28`, the rolling alias,
  or bottle publication into legacy `main`.
- Do not merge `homebrew-jdk26ea#6`.
- Preserve read-only workflow tokens, SHA-pinned actions, app-bound required
  checks, latest-push approval, stale-review dismissal, conversation
  resolution, force-push denial, and branch-deletion denial.
- Temporarily disable only administrator enforcement, only after every required
  check passes, and only for the owner merge.
- Restore administrator enforcement if the owner does not merge in the active
  handoff.
- Archive only after both legacy package forms execute `java -version`.
- Use Conventional Commit messages.

---

## File Map

- Modify `Formula/jdk26ea.rb`: repin the legacy formula to official OpenJDK
  26.0.2 GA archives on macOS and Linux.
- Modify `Casks/jdk26ea.rb`: repin the legacy cask to official OpenJDK 26.0.2
  GA macOS archives.
- Create `tests/legacy_contract.bats`: exact version, URL, checksum, and Ruby
  syntax contract.
- Modify `.github/workflows/validate.yml`: remove synthetic status publication,
  retain installation jobs, and make `Validation Status` fail closed under the
  read-only token.
- Modify `README.md`: deprecation notice, compatibility purpose, install
  commands, and canonical Valhalla redirect.
- Preserve all other legacy files unless a focused validation failure proves a
  required correction.

## Official OpenJDK 26.0.2 Coordinates

Release root:

```text
https://download.java.net/java/GA/jdk26.0.2/818d462d89b645c7a1aad49066c454e5/10/GPL
```

| Platform | Archive | SHA-256 |
| --- | --- | --- |
| Linux ARM64 | `openjdk-26.0.2_linux-aarch64_bin.tar.gz` | `0ce6516c459e635d9f263f9b3492d83ec2c1ee26db128a6d904cae3d3096ceee` |
| Linux x64 | `openjdk-26.0.2_linux-x64_bin.tar.gz` | `2da09e9db53e5c4f9eeec045f49e7d8fbcd8e4153edbf0c269f520ff82fd4198` |
| macOS ARM64 | `openjdk-26.0.2_macos-aarch64_bin.tar.gz` | `c99b35ad3063ef555361a243c44280b048e24e3cbbc4a59ee3b368e5a8958f3a` |
| macOS x64 | `openjdk-26.0.2_macos-x64_bin.tar.gz` | `c258f17d4095c0cda0489d33fc4988d4be193a280b7e1f045e961699dedbfc65` |

### Task 1: Create a clean compatibility branch from legacy main

**Files:**
- No file changes.

**Interfaces:**
- Consumes: current `origin/main`.
- Produces: branch `fix/jdk26-compatibility-archive` with no commits from PR
  `#6`.

- [ ] **Step 1: Fetch and verify the legacy default branch**

```bash
rtk git fetch origin main
rtk git rev-parse origin/main
rtk git status --short --branch
```

Expected: the current worktree is clean before changing branches.

- [ ] **Step 2: Create an isolated cleanup worktree**

From the legacy repository:

```bash
rtk git worktree add ../homebrew-jdk26ea-archive -b fix/jdk26-compatibility-archive origin/main
```

Read the cleanup worktree's `AGENTS.md` completely before edits.

- [ ] **Step 3: Prove the branch excludes the mixed PR**

```bash
rtk git log --oneline origin/main..HEAD
rtk rg -n 'openjdk-valhalla' Formula Aliases .github README.md
```

Expected: no new commits and no source-formula package surface on the cleanup
branch. Search exit `1` means the unwanted token is absent.

### Task 2: Repin the legacy formula and cask with contract tests

**Files:**
- Create: `tests/legacy_contract.bats`
- Modify: `Formula/jdk26ea.rb`
- Modify: `Casks/jdk26ea.rb`

**Interfaces:**
- Consumes: the official release root and four checksums above.
- Produces: working `jdk26ea` formula and cask at OpenJDK 26.0.2+10.

- [ ] **Step 1: Write the failing legacy package contract**

Create `tests/legacy_contract.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  RELEASE_ROOT="https://download.java.net/java/GA/jdk26.0.2/818d462d89b645c7a1aad49066c454e5/10/GPL"
}

@test "legacy formula and cask are valid Ruby" {
  run ruby -c "${REPO_ROOT}/Formula/jdk26ea.rb"
  [ "${status}" -eq 0 ]
  [ "${output}" = "Syntax OK" ]
  run ruby -c "${REPO_ROOT}/Casks/jdk26ea.rb"
  [ "${status}" -eq 0 ]
  [ "${output}" = "Syntax OK" ]
}

@test "legacy token is pinned to OpenJDK 26.0.2 GA" {
  local formula cask
  formula="$(<"${REPO_ROOT}/Formula/jdk26ea.rb")"
  cask="$(<"${REPO_ROOT}/Casks/jdk26ea.rb")"
  [[ "${formula}" == *'version "26.0.2+10"'* ]]
  [[ "${formula}" == *"${RELEASE_ROOT}/openjdk-26.0.2_linux-aarch64_bin.tar.gz"* ]]
  [[ "${formula}" == *"${RELEASE_ROOT}/openjdk-26.0.2_linux-x64_bin.tar.gz"* ]]
  [[ "${formula}" == *"${RELEASE_ROOT}/openjdk-26.0.2_macos-aarch64_bin.tar.gz"* ]]
  [[ "${formula}" == *"${RELEASE_ROOT}/openjdk-26.0.2_macos-x64_bin.tar.gz"* ]]
  [[ "${cask}" == *'version "26.0.2,10"'* ]]
  [[ "${cask}" == *'download.java.net/java/GA/jdk#{version.csv.first}'* ]]
}
```

Add checksum assertions for all four exact SHA-256 values in this plan. Assert
neither file contains `/early_access/`.

- [ ] **Step 2: Run the contract and verify it fails**

```bash
rtk bats tests/legacy_contract.bats
```

Expected: FAIL because `main` still references JDK 26 EA build 20.

- [ ] **Step 3: Update `Formula/jdk26ea.rb`**

Set:

```ruby
desc "OpenJDK 26 (legacy jdk26ea token)"
homepage "https://jdk.java.net/26/"
version "26.0.2+10"
```

Use the four exact URLs and checksums in this plan. Keep the existing
platform/architecture branching, installation layout, symlink behavior, and
compile/run test. Change the final assertion to:

```ruby
assert_match(/26/, shell_output("#{bin}/java --enable-preview Hello"))
```

- [ ] **Step 4: Update `Casks/jdk26ea.rb`**

Set:

```ruby
version "26.0.2,10"
sha256 arm:   "c99b35ad3063ef555361a243c44280b048e24e3cbbc4a59ee3b368e5a8958f3a",
       intel: "c258f17d4095c0cda0489d33fc4988d4be193a280b7e1f045e961699dedbfc65"
url "https://download.java.net/java/GA/jdk#{version.csv.first}/818d462d89b645c7a1aad49066c454e5/#{version.csv.second}/GPL/openjdk-#{version.csv.first}_macos-#{arch}_bin.tar.gz"
name "OpenJDK 26"
desc "OpenJDK 26 (legacy jdk26ea token)"
```

Keep the existing destination path
`/Library/Java/JavaVirtualMachines/jdk-26-ea.jdk` for backward compatibility.
Keep realpath validation and `ditto`.

- [ ] **Step 5: Run focused package checks**

```bash
rtk bats tests/legacy_contract.bats
rtk brew style Formula/jdk26ea.rb Casks/jdk26ea.rb
rtk brew audit --formula artagon/jdk26ea/jdk26ea
rtk brew audit --cask artagon/jdk26ea/jdk26ea
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
rtk git add Formula/jdk26ea.rb Casks/jdk26ea.rb tests/legacy_contract.bats
rtk git commit -m "fix: restore legacy JDK 26 compatibility"
```

### Task 3: Make legacy validation work under read-only tokens

**Files:**
- Modify: `.github/workflows/validate.yml`

**Interfaces:**
- Consumes: `validate-syntax`, `test-install-macos`, and
  `test-install-linux` results.
- Produces: one fail-closed `Validation Status` check without posting a
  synthetic commit status.

- [ ] **Step 1: Add a workflow contract to `tests/legacy_contract.bats`**

Use Ruby's YAML parser from Bats to assert:

```bash
run ruby -ryaml -e '
  workflow = YAML.load_file(ARGV.fetch(0))
  abort unless workflow["permissions"] == { "contents" => "read" }
  job = workflow.fetch("jobs").fetch("validation-status")
  abort unless job["if"] == "${{ always() }}"
  abort unless job.fetch("needs").sort == %w[
    test-install-linux
    test-install-macos
    validate-syntax
  ]
  text = job.fetch("steps").fetch(0).fetch("run")
  abort unless text.include?("[[ \"${result}\" == \"success\" ]]")
  abort if text.include?("gh api")
' .github/workflows/validate.yml
[ "${status}" -eq 0 ]
```

- [ ] **Step 2: Run the contract and verify it fails**

```bash
rtk bats tests/legacy_contract.bats
```

Expected: FAIL because `main` posts a synthetic `Validate` status and lacks a
read-only top-level permission.

- [ ] **Step 3: Correct `.github/workflows/validate.yml`**

Add:

```yaml
permissions:
  contents: read
```

Set `persist-credentials: false` on every checkout. Keep the existing syntax,
macOS installation, and Linux installation jobs. Replace `validation-status`
with:

```yaml
validation-status:
  name: Validation Status
  if: ${{ always() }}
  runs-on: ubuntu-latest
  needs:
    - validate-syntax
    - test-install-macos
    - test-install-linux
  steps:
    - name: Confirm completion
      env:
        VALIDATE_SYNTAX_RESULT: ${{ needs.validate-syntax.result }}
        TEST_INSTALL_MACOS_RESULT: ${{ needs.test-install-macos.result }}
        TEST_INSTALL_LINUX_RESULT: ${{ needs.test-install-linux.result }}
      run: |
        set -Eeuo pipefail
        for result in \
          "${VALIDATE_SYNTAX_RESULT}" \
          "${TEST_INSTALL_MACOS_RESULT}" \
          "${TEST_INSTALL_LINUX_RESULT}"; do
          [[ "${result}" == "success" ]] || exit 1
        done
```

Run `tests/legacy_contract.bats` from `validate-syntax`.

- [ ] **Step 4: Validate workflow and contract**

```bash
rtk bats tests/legacy_contract.bats
rtk actionlint .github/workflows/validate.yml
rtk shellcheck tests/legacy_contract.bats
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add .github/workflows/validate.yml tests/legacy_contract.bats
rtk git commit -m "ci(workflow): make legacy validation fail closed"
```

### Task 4: Replace active-project claims with a deprecation redirect

**Files:**
- Modify: `README.md`
- Modify: `tests/legacy_contract.bats`

**Interfaces:**
- Consumes: canonical repository URL and compatibility package details.
- Produces: an unambiguous archived-tap landing page.

- [ ] **Step 1: Add documentation assertions**

Assert `README.md` contains:

```text
This repository is deprecated
https://github.com/artagon/homebrew-jdkvalhalla
OpenJDK 26.0.2
brew install artagon/jdk26ea/jdk26ea
brew install --cask artagon/jdk26ea/jdk26ea
```

Assert it does not claim automatic EA updates or new Valhalla releases.

- [ ] **Step 2: Run the contract and verify it fails**

```bash
rtk bats tests/legacy_contract.bats
```

Expected: FAIL because the current README presents the repository as an active
JDK 26 EA tap.

- [ ] **Step 3: Rewrite README for compatibility-only status**

Use this top-level structure:

```markdown
# homebrew-jdk26ea

> This repository is deprecated and retained only for the legacy `jdk26ea`
> package token. New Project Valhalla installations belong in
> [artagon/homebrew-jdkvalhalla](https://github.com/artagon/homebrew-jdkvalhalla).

## Legacy compatibility

The formula and cask install official OpenJDK 26.0.2 GA under the historical
`jdk26ea` token. They are not Project Valhalla builds.

## Install

```bash
brew tap artagon/jdk26ea
brew install artagon/jdk26ea/jdk26ea
# macOS cask:
brew install --cask artagon/jdk26ea/jdk26ea
```

## Migrate to Project Valhalla

See https://github.com/artagon/homebrew-jdkvalhalla for current prebuilt and
source-built Valhalla packages.
```

Retain license and archival support language. Remove release badges and claims
about automatic JDK 26 EA updates.

- [ ] **Step 4: Run documentation contract**

```bash
rtk bats tests/legacy_contract.bats
rtk git diff --check
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add README.md tests/legacy_contract.bats
rtk git commit -m "docs: deprecate the legacy JDK 26 tap"
```

### Task 5: Verify and publish the legacy cleanup pull request

**Files:**
- No additional file changes.

**Interfaces:**
- Consumes: three cleanup commits.
- Produces: one small legacy cleanup PR ready for owner merge.

- [ ] **Step 1: Run the complete local gate**

```bash
rtk bats tests/legacy_contract.bats
rtk ruby -c Formula/jdk26ea.rb
rtk ruby -c Casks/jdk26ea.rb
rtk actionlint .github/workflows/validate.yml
rtk shellcheck tests/legacy_contract.bats scripts/test.sh
rtk brew style Formula/jdk26ea.rb Casks/jdk26ea.rb
rtk brew audit --formula artagon/jdk26ea/jdk26ea
rtk brew audit --cask artagon/jdk26ea/jdk26ea
rtk git diff --check origin/main...HEAD
```

Expected: PASS.

- [ ] **Step 2: Verify exact scope**

```bash
rtk git diff --name-status origin/main...HEAD
rtk git log --oneline origin/main..HEAD
rtk rg -n 'openjdk-valhalla|bottles.yml|early_access' Formula Casks Aliases .github README.md
```

Expected changed paths:

```text
.github/workflows/validate.yml
Casks/jdk26ea.rb
Formula/jdk26ea.rb
README.md
tests/legacy_contract.bats
```

Search output may mention the canonical URL in README, but no source formula,
bottle workflow, or early-access artifact URL may exist.

- [ ] **Step 3: Push and open the cleanup PR**

```bash
rtk git push -u origin fix/jdk26-compatibility-archive
```

Use title:

```text
fix: preserve JDK 26 compatibility before archival
```

The body states that the PR updates the legacy token to OpenJDK 26.0.2,
corrects validation for read-only tokens, redirects Valhalla users, and will be
followed by repository archival. It links the merged canonical consolidation
PR and records its merge SHA.

- [ ] **Step 4: Wait for every required check**

```bash
rtk gh pr checks --watch --fail-fast
```

Expected: all matrix jobs and `Validation Status` PASS.

### Task 6: Close mixed legacy PR #6 and execute the owner merge window

**Files:**
- No repository file changes.

**Interfaces:**
- Consumes: passing cleanup PR and canonical merge URL.
- Produces: closed PR `#6` and an owner-merged cleanup PR.

- [ ] **Step 1: Close `homebrew-jdk26ea#6`**

Comment that its source formulas, validator, bottle workflow, tests, and
security design were ported to the canonical consolidation PR, while the
legacy JDK 26 compatibility fix is isolated in the cleanup PR. Link both PRs,
then close `#6`. Re-read it and confirm state `CLOSED`.

- [ ] **Step 2: Record protection before changing it**

```bash
rtk gh api repos/artagon/homebrew-jdk26ea/branches/main/protection
```

Confirm:

- `Validation Status` is required from app ID 15368;
- one approving review is required;
- latest-push approval and stale-review dismissal are true;
- administrator enforcement is true;
- conversation resolution is true;
- force pushes and deletions are false.

Do not continue if any other protection differs; reconcile it first without
weakening checks.

- [ ] **Step 3: Disable only administrator enforcement**

```bash
rtk gh api --method DELETE repos/artagon/homebrew-jdk26ea/branches/main/protection/enforce_admins
```

Immediately read the full protection object again. Every setting above must be
unchanged except `enforce_admins.enabled == false`.

- [ ] **Step 4: Hand the exact PR head to the owner**

Report cleanup PR URL, exact head SHA, passing checks, and the active
administrator-bypass window. Stop and wait for the owner to merge.

- [ ] **Step 5: Close the window**

If the owner confirms merge, verify the merged commit before proceeding. If
the owner does not merge during this handoff or the PR head changes, restore
administrator enforcement immediately:

```bash
rtk gh api --method POST repos/artagon/homebrew-jdk26ea/branches/main/protection/enforce_admins
```

No other protection setting may change.

### Task 7: Verify compatibility and archive the legacy repository

**Files:**
- No repository file changes.

**Interfaces:**
- Consumes: verified cleanup merge and package install evidence.
- Produces: archived `artagon/homebrew-jdk26ea`.

- [ ] **Step 1: Verify the cleanup merge**

```bash
rtk gh pr view --json state,mergedAt,mergeCommit,headRefOid,url
rtk gh api repos/artagon/homebrew-jdk26ea/commits/main
```

Expected: cleanup PR state `MERGED`; `main` contains the recorded head SHA.

- [ ] **Step 2: Verify the formula from the merged tap**

```bash
rtk brew update
rtk brew untap artagon/jdk26ea
rtk brew tap artagon/jdk26ea
rtk brew install artagon/jdk26ea/jdk26ea
rtk brew test artagon/jdk26ea/jdk26ea
rtk brew uninstall artagon/jdk26ea/jdk26ea
```

Record `java -version`; it must identify OpenJDK 26.0.2.

- [ ] **Step 3: Verify the cask on macOS**

```bash
rtk brew install --cask artagon/jdk26ea/jdk26ea
rtk /Library/Java/JavaVirtualMachines/jdk-26-ea.jdk/Contents/Home/bin/java -version
rtk brew uninstall --cask artagon/jdk26ea/jdk26ea
```

Expected: installation succeeds and reports OpenJDK 26.0.2. If cask
installation cannot run in the current environment, archival remains blocked
until a successful macOS CI or local record is available.

- [ ] **Step 4: Confirm no open work remains**

```bash
rtk gh pr list --repo artagon/homebrew-jdk26ea --state open
rtk gh issue list --repo artagon/homebrew-jdk26ea --state open
```

Expected: empty. Close or transfer any remaining item with a traceable
canonical link before archival.

- [ ] **Step 5: Archive**

```bash
rtk gh api --method PATCH repos/artagon/homebrew-jdk26ea -F archived=true
```

- [ ] **Step 6: Verify final state**

```bash
rtk gh api repos/artagon/homebrew-jdk26ea
```

Expected: `archived == true`, default branch `main`, and the cleanup merge SHA
is reachable. Report the canonical repository URL, archived legacy URL, both
merge SHAs, install evidence, and any unsupported platform not exercised.

## Rollback

- Before merge: restore administrator enforcement and leave the cleanup PR
  open.
- After merge but before install verification: do not archive; fix the package
  on a new protected pull request.
- After one package form passes but the other fails: do not archive; retain the
  repository until both formula and cask evidence are green.
- After archival: do not unarchive for new Valhalla development. Unarchive only
  to correct a severe compatibility or security defect in the legacy token,
  then rearchive after verification.

## External Documentation

- GitHub branch protection:
  <https://docs.github.com/en/rest/branches/branch-protection>
- GitHub repository archive setting:
  <https://docs.github.com/en/rest/repos/repos#update-a-repository>
