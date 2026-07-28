#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/.." && pwd -P)"
}

@test "README documents every supported Valhalla token" {
  local contents
  contents="$(<"${REPO_ROOT}/README.md")"

  for token in \
    jdkvalhalla \
    jdkvalhalla@26 \
    jdkvalhalla@27 \
    openjdk-valhalla \
    openjdk-valhalla@27 \
    openjdk-valhalla@28; do
    [[ "${contents}" == *"${token}"* ]]
  done
}

@test "README documents prebuilt bottle and source installation modes" {
  local contents
  contents="$(<"${REPO_ROOT}/README.md")"

  [[ "${contents}" == *'brew install --cask artagon/jdkvalhalla/jdkvalhalla'* ]]
  [[ "${contents}" == *'brew install artagon/jdkvalhalla/jdkvalhalla@27'* ]]
  [[ "${contents}" == *'brew install artagon/jdkvalhalla/openjdk-valhalla@28'* ]]
  [[ "${contents}" == *'brew install --build-from-source artagon/jdkvalhalla/openjdk-valhalla@28'* ]]
  [[ "${contents}" == *'Source builds are long-running'* ]]
  [[ "${contents}" == *'brew info artagon/jdkvalhalla/openjdk-valhalla@28'* ]]
}

@test "README documents versioned jenv registration" {
  local contents
  contents="$(<"${REPO_ROOT}/README.md")"

  [[ "${contents}" == *"jenv add \"\$(brew --prefix openjdk-valhalla@27)/libexec/openjdk.jdk/Contents/Home\""* ]]
  [[ "${contents}" == *"jenv add \"\$(brew --prefix openjdk-valhalla@28)/libexec/openjdk.jdk/Contents/Home\""* ]]
  [[ "${contents}" == *'jenv local'* ]]
  [[ "${contents}" == *'jenv global'* ]]
}

@test "security policy records required supply-chain controls" {
  local contents
  contents="$(<"${REPO_ROOT}/SECURITY.md")"

  [[ "${contents}" == *'read-only'* ]]
  [[ "${contents}" == *'full commit SHA'* ]]
  [[ "${contents}" == *'immutable release'* ]]
  [[ "${contents}" == *'checksum'* ]]
  [[ "${contents}" == *'privately'* ]]
  [[ "${contents}" == *'/security/advisories/new'* ]]
}
