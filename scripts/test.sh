#!/usr/bin/env bash
# Run local validation for the JDK Valhalla tap.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_USER="artagon"
TAP_REPO="homebrew-jdkvalhalla"
TAP_FULL="${TAP_USER}/${TAP_REPO}"
FORMULA_NAME="jdkvalhalla@27"
FORMULA_FULL="${TAP_USER}/jdkvalhalla/${FORMULA_NAME}"
CASK_NAME="jdkvalhalla"
CASK_FULL="${TAP_USER}/jdkvalhalla/${CASK_NAME}"
PACKAGE_FILES=(
  "${ROOT}"/Casks/*.rb
  "${ROOT}"/Formula/*.rb
)

log() {
  printf '==> %s\n' "$*"
}

abort() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command -v brew >/dev/null 2>&1 || abort "Homebrew is required to run these tests."

cleanup_cmds=()
register_cleanup() {
  cleanup_cmds+=("$*")
}

run_cleanup() {
  local status=$?
  for (( idx=${#cleanup_cmds[@]}-1; idx>=0; idx-- )); do
    eval "${cleanup_cmds[$idx]}" || true
  done
  exit "$status"
}
trap run_cleanup EXIT

link_tap_to_repo() {
  local tap_dir
  tap_dir="$(brew --repository)/Library/Taps/${TAP_USER}/${TAP_REPO}"

  if [[ -e "$tap_dir" && ! -L "$tap_dir" ]]; then
    abort "Existing tap checkout found at ${tap_dir}; move it before running these tests."
  fi

  if [[ -L "$tap_dir" ]]; then
    local current_target
    current_target="$(readlink "$tap_dir")"
    if [[ "$current_target" != "$ROOT" ]]; then
      register_cleanup "ln -snf \"${current_target}\" \"${tap_dir}\""
      ln -snf "$ROOT" "$tap_dir"
    fi
  else
    mkdir -p "$(dirname "$tap_dir")"
    ln -s "$ROOT" "$tap_dir"
    register_cleanup "rm -f \"${tap_dir}\""
  fi
}

run_style_and_audit() {
  log "Running brew style checks"
  brew style "${PACKAGE_FILES[@]}"

  local package token
  for package in "${ROOT}"/Formula/*.rb; do
    token="$(basename "${package}" .rb)"
    log "Running brew audit for formula ${token}"
    brew audit --formula "${TAP_USER}/jdkvalhalla/${token}"
  done

  if [[ "$(uname -s)" == "Darwin" ]]; then
    for package in "${ROOT}"/Casks/*.rb; do
      token="$(basename "${package}" .rb)"
      log "Running brew audit for cask ${token}"
      brew audit --cask "${TAP_USER}/jdkvalhalla/${token}"
    done
  else
    log "Skipping cask audit on non-macOS host"
  fi
}

run_static_tests() {
  command -v bats >/dev/null 2>&1 || abort "Bats is required to run the contract tests."

  log "Running package and documentation contracts"
  bats "${ROOT}/tests/formula_contract.bats" "${ROOT}/tests/documentation_contract.bats"

  log "Running Ruby unit tests"
  ruby "${ROOT}/tests/bottle_artifact_validator_test.rb"
  ruby "${ROOT}/tests/parse_valhalla_release_test.rb"
  ruby "${ROOT}/tests/workflow_security_test.rb"
}

test_formula_install() {
  log "Installing formula ${FORMULA_FULL}"
  brew install "${FORMULA_FULL}"
  register_cleanup "brew uninstall --formula ${FORMULA_FULL} >/dev/null 2>&1 || true"

  log "Running brew test for ${FORMULA_FULL}"
  brew test "${FORMULA_FULL}"
}

test_cask_install() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log "Skipping cask install on non-macOS host"
    return
  fi

  log "Installing cask ${CASK_FULL}"
  brew install --cask "${CASK_FULL}"
  register_cleanup "brew uninstall --cask ${CASK_FULL} >/dev/null 2>&1 || true"

  local app_path="/Library/Java/JavaVirtualMachines/jdk-valhalla.jdk/Contents/Home/bin/java"
  if [[ -x "$app_path" ]]; then
    log "Cask install verification: printing java version"
    "$app_path" -version
  else
    abort "Expected java binary at ${app_path} was not found."
  fi
}

log "Linking tap ${TAP_FULL} to local repository"
link_tap_to_repo

run_style_and_audit
run_static_tests
test_formula_install
test_cask_install

log "All checks completed successfully"
