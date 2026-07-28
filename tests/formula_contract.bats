#!/usr/bin/env bats

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
  [ -e "${REPO_ROOT}/Aliases/openjdk-valhalla" ]

  run readlink "${REPO_ROOT}/Aliases/openjdk-valhalla"

  [ "${status}" -eq 0 ]
  [ "${output}" = "../Formula/openjdk-valhalla@28.rb" ]
}

@test "JDK 27 source formula is pinned to the reviewed milestone" {
  local contents

  contents="$(<"${REPO_ROOT}/Formula/openjdk-valhalla@27.rb")"
  [[ "${contents}" == *"f9799f4c1a35694951413fda0986cdebe49f85d0.tar.gz"* ]]
  [[ "${contents}" == *'version "27-ea-20260310-f9799f4c1a35"'* ]]
  [[ "${contents}" == *'sha256 "eb44694f4525aa7e57a6304d4c01f17ffaf78824ec76016e512742b643664367"'* ]]
  [[ "${contents}" != *"/archive/refs/heads/"* ]]
}

@test "JDK 28 source formula is pinned to the reviewed lworld snapshot" {
  local contents

  contents="$(<"${REPO_ROOT}/Formula/openjdk-valhalla@28.rb")"
  [[ "${contents}" == *"f181286389fad995be1e71de60f30d14eb1c9122.tar.gz"* ]]
  [[ "${contents}" == *'version "28-ea-20260727-f181286389fa"'* ]]
  [[ "${contents}" == *'sha256 "d44923f1e68651f85080e53a27afd23fcc3ac23e0022bde7ba1309ca0d5bcf25"'* ]]
  [[ "${contents}" != *"/archive/refs/heads/"* ]]
}

@test "source formulae declare the reviewed build requirements" {
  local contents formula

  for formula in \
    "${REPO_ROOT}/Formula/openjdk-valhalla@27.rb" \
    "${REPO_ROOT}/Formula/openjdk-valhalla@28.rb"; do
    contents="$(<"${formula}")"
    [[ "${contents}" == *'depends_on xcode: ["15.4", :build]'* ]]
    [[ "${contents}" == *'depends_on arch: :arm64'* ]]
    [[ "${contents}" == *'depends_on macos: :sonoma'* ]]
    [[ "${contents}" == *'resource "boot-jdk" do'* ]]
    [[ "${contents}" == *'ENV["MAKEFLAGS"] = "JOBS=#{[ENV.make_jobs, 4].min}"'* ]]
    [[ "${contents}" == *'keg_only :versioned_formula'* ]]
  done
}
