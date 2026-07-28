# typed: strict
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

# Enforces least-privilege and immutable-reference workflow contracts.
class WorkflowSecurityTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__).freeze

  def workflow(name)
    YAML.load_file(File.join(ROOT, ".github", "workflows", name))
  end

  def checkout_steps(document)
    document.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
                                 .select { |step| step["uses"]&.start_with?("actions/checkout@") }
  end

  def renderer_environment
    {
      "BUILD"         => "1",
      "FULL_VERSION"  => "27-jep401ea3+1-1",
      "JDK_VERSION"   => "27",
      "SHA_LINUX_ARM" => "f9b56dd9fed330aa30ff2428f58358dc2cc67eae53be8805f819062d925d314a",
      "SHA_LINUX_X64" => "b8bdd7b181c6a5ea2dd9959255e222cd9d9a9f42cca4f2400991b9b2ff7ffb7d",
      "SHA_MAC_ARM"   => "d97c8e0d90d95b81bf99cfef0b1e1edebeb07655fc84c42e6ed99d882aebe76b",
      "SHA_MAC_INTEL" => "64d2deee65c221b7fbdfb936d42981987c1505a6057a1847e5fdb37afabb103a",
      "URL_LINUX_ARM" => "https://download.java.net/java/early_access/valhalla/27/1/" \
                         "openjdk-27-jep401ea3+1-1_linux-aarch64_bin.tar.gz",
      "URL_LINUX_X64" => "https://download.java.net/java/early_access/valhalla/27/1/" \
                         "openjdk-27-jep401ea3+1-1_linux-x64_bin.tar.gz",
      "URL_MAC_ARM"   => "https://download.java.net/java/early_access/valhalla/27/1/" \
                         "openjdk-27-jep401ea3+1-1_macos-aarch64_bin.tar.gz",
      "URL_MAC_INTEL" => "https://download.java.net/java/early_access/valhalla/27/1/" \
                         "openjdk-27-jep401ea3+1-1_macos-x64_bin.tar.gz",
    }
  end

  def test_bottle_build_cannot_write_repository_state
    document = workflow("bottles.yml")
    build = document.fetch("jobs").fetch("build")

    assert_equal({}, document["permissions"])
    assert_equal({ "contents" => "read" }, build["permissions"])
    assert checkout_steps({ "jobs" => { "build" => build } }).all? { |step|
      step.dig("with", "persist-credentials") == false
    }
  end

  def test_bottle_publish_has_narrow_write_permissions
    document = workflow("bottles.yml")
    publish = document.fetch("jobs").fetch("publish")

    assert_equal(
      { "contents" => "write", "packages" => "write", "pull-requests" => "write" },
      publish["permissions"],
    )
    assert_equal "github.ref == 'refs/heads/main'", publish["if"]
    refute publish.fetch("env", {}).key?("HOMEBREW_GITHUB_PACKAGES_TOKEN")

    package_step = publish.fetch("steps").find { |step| step["name"] == "Publish bottle package" }
    assert_equal(
      "${{ github.token }}",
      package_step.fetch("env").fetch("HOMEBREW_GITHUB_PACKAGES_TOKEN"),
    )
  end

  def test_bottle_package_is_bound_to_main_commit_and_requires_exact_anonymous_retry
    document = workflow("bottles.yml")
    build = document.fetch("jobs").fetch("build")
    publish = document.fetch("jobs").fetch("publish")
    metadata = build.fetch("steps").find { |step| step["name"] == "Resolve bottle metadata" }
    package_step = publish.fetch("steps").find { |step| step["name"] == "Publish bottle package" }
    verify_step = publish.fetch("steps").find { |step| step["name"] == "Verify anonymous bottle package" }
    pull_request_step = publish.fetch("steps").find { |step| step["name"] == "Create bottle block pull request" }

    assert_includes metadata.fetch("run"), '[[ "${GITHUB_REF}" == "refs/heads/main" ]]'
    assert_includes metadata.fetch("run"), "${GITHUB_SHA::12}"
    assert_includes metadata.fetch("run"), 'formula.fetch("revision", 0)'
    assert_includes package_step.fetch("run"), "brew pr-upload --upload-only"
    refute_includes package_step.fetch("run"), "--keep-old"
    assert_includes package_step.fetch("run"), "--warn-on-upload-failure"
    assert_empty verify_step.fetch("env").keys.grep(/TOKEN/)
    assert_includes verify_step.fetch("run"), 'image_formula="${FORMULA%@*}/${FORMULA#*@}"'
    assert_includes verify_step.fetch("run"), "skopeo inspect --raw"
    assert_includes verify_step.fetch("run"), '"sh.brew.bottle.digest"'
    assert_includes verify_step.fetch("run"), '"architecture") == "arm64"'
    assert_includes verify_step.fetch("run"), '"os") == "darwin"'
    assert_operator publish.fetch("steps").index(package_step), :<, publish.fetch("steps").index(verify_step)
    assert_operator publish.fetch("steps").index(verify_step), :<, publish.fetch("steps").index(pull_request_step)
  end

  def test_bottle_build_uses_nonconflicting_homebrew_flags
    document = workflow("bottles.yml")
    build_step = document.fetch("jobs").fetch("build").fetch("steps")
                         .find { |step| step["name"] == "Build from the pinned source" }

    assert_includes build_step.fetch("run"), "brew install --build-bottle"
    refute_includes build_step.fetch("run"), "--build-from-source"
  end

  def test_bottle_artifact_paths_come_from_validator_outputs
    document = workflow("bottles.yml")
    build_steps = document.fetch("jobs").fetch("build").fetch("steps")
    publish_steps = document.fetch("jobs").fetch("publish").fetch("steps")
    upload = build_steps.find { |step| step["name"] == "Upload bottle job artifact" }
    validate = publish_steps.find { |step| step["name"] == "Validate bottle artifact" }
    package_step = publish_steps.find { |step| step["name"] == "Publish bottle package" }
    merge = publish_steps.find { |step| step["name"] == "Merge bottle metadata into formula" }

    assert_equal(
      "${{ steps.artifact.outputs.bottle_path }}\n${{ steps.artifact.outputs.json_path }}",
      upload.fetch("with").fetch("path"),
    )
    assert validate, "missing Validate bottle artifact step"
    assert_includes validate.fetch("run"), "scripts/validate-bottle-artifact.rb"
    assert_includes package_step.fetch("run"), "cd bottle-artifact"
    assert_includes merge.fetch("run"), '"${BOTTLE_JSON}"'
    assert_includes merge.fetch("run"), 'git diff --quiet -- "Formula/${FORMULA}.rb"'
    refute_includes package_step.fetch("run"), "*.tar.gz"
    refute_includes merge.fetch("run"), "find bottle-artifact"
  end

  def test_validation_fan_in_is_read_only_and_fail_closed
    document = workflow("validate.yml")
    status = document.fetch("jobs").fetch("validation-status")
    confirm = status.fetch("steps").find { |step| step["name"] == "Confirm completion" }

    assert_equal({ "contents" => "read" }, document["permissions"])
    assert document.fetch(true).key?("workflow_dispatch")
    assert_equal "${{ always() }}", status["if"]
    assert_equal(
      %w[test-cask-macos test-prebuilt-formula validate-static],
      status.fetch("needs").sort,
    )
    assert_equal(
      {
        "VALIDATE_STATIC_RESULT"       => "${{ needs.validate-static.result }}",
        "TEST_CASK_MACOS_RESULT"       => "${{ needs.test-cask-macos.result }}",
        "TEST_PREBUILT_FORMULA_RESULT" => "${{ needs.test-prebuilt-formula.result }}",
      },
      confirm["env"],
    )
    assert_includes confirm.fetch("run"), "for result in \\"
    assert_includes confirm.fetch("run"), 'if [[ "${result}" != "success" ]]'
    assert_includes confirm.fetch("run"), "exit 1"

    all_steps = document.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
    all_steps.each do |step|
      refute step.fetch("env", {}).key?("GH_TOKEN")
      refute_includes step.fetch("run", ""), "/statuses/"
    end
  end

  def test_validation_never_installs_source_formulae
    document = workflow("validate.yml")
    commands = document.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
                                            .each_with_object([]) do |step, run_steps|
      run_steps << step["run"] if step["run"]
    end.join("\n")

    refute_match(/brew install .*openjdk-valhalla/, commands)
    assert_equal(
      %w[jdkvalhalla@26 jdkvalhalla@27],
      document.dig("jobs", "test-prebuilt-formula", "strategy", "matrix", "formula"),
    )
  end

  def test_update_workflow_separates_read_and_write_trust_zones
    document = workflow("update.yml")
    prepare = document.fetch("jobs").fetch("prepare")
    create_pr = document.fetch("jobs").fetch("create-pr")

    assert_equal({}, document["permissions"])
    assert_equal({ "contents" => "read" }, prepare["permissions"])
    assert_equal(
      { "actions" => "write", "contents" => "write", "pull-requests" => "write" },
      create_pr["permissions"],
    )

    all_steps = document.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
    pull_request_steps = all_steps.select do |step|
      step["uses"]&.start_with?("peter-evans/create-pull-request@")
    end
    assert_equal 1, pull_request_steps.length
    assert_includes create_pr.fetch("steps"), pull_request_steps.first
    assert_equal(
      "peter-evans/create-pull-request@5f6978faf089d4d20b00c7766989d076bb2fc7f1",
      pull_request_steps.first["uses"],
    )

    assert_equal "create-pull-request", pull_request_steps.first["id"]
    dispatch = create_pr.fetch("steps").find { |step| step["name"] == "Dispatch validation" }
    assert_equal(
      "${{ steps.create-pull-request.outputs.pull-request-number != '' }}",
      dispatch["if"],
    )
    assert_equal "${{ github.token }}", dispatch.dig("env", "GH_TOKEN")
    assert_equal(
      "${{ steps.create-pull-request.outputs.pull-request-branch }}",
      dispatch.dig("env", "VALIDATION_REF"),
    )
    assert_includes dispatch.fetch("run"), 'gh workflow run validate.yml --ref "${VALIDATION_REF}"'
  end

  def test_update_workflow_validates_sources_checksums_and_exact_artifact
    document = workflow("update.yml")
    prepare_steps = document.dig("jobs", "prepare", "steps")
    create_steps = document.dig("jobs", "create-pr", "steps")
    parse = prepare_steps.find { |step| step["name"] == "Parse official Valhalla release" }
    archives = prepare_steps.find { |step| step["name"] == "Download and verify official archives" }
    upload = prepare_steps.find { |step| step["name"] == "Upload generated packages" }
    validate = create_steps.find { |step| step["name"] == "Validate exact generated paths" }

    assert_includes parse.fetch("run"), "scripts/parse-valhalla-release.rb"
    assert_includes parse.fetch("run"), "https://jdk.java.net/valhalla/"
    assert_includes archives.fetch("run"), 'uri.host == "download.java.net"'
    assert_includes archives.fetch("run"), '[[ "${expected}" =~ ^[0-9a-f]{64}$ ]]'
    assert_includes archives.fetch("run"), 'if [[ -f "${archive}" ]]'
    assert_includes archives.fetch("run"), 'actual="$(sha256sum "${archive}")"'
    cache = prepare_steps.find { |step| step["name"] == "Cache JDK downloads" }
    assert_operator prepare_steps.index(parse), :<, prepare_steps.index(cache)
    assert_equal "valhalla-${{ steps.release.outputs.full_version }}", cache.dig("with", "key")
    assert_equal(
      "generated/Casks/jdkvalhalla.rb\n" \
      "generated/Formula/jdkvalhalla@${{ steps.release.outputs.jdk_version }}.rb",
      upload.dig("with", "path"),
    )
    assert_includes validate.fetch("run"), 'abort "generated package allowlist mismatch"'
    assert_includes validate.fetch("run"), "File.symlink?(path)"
    assert_includes validate.fetch("run"), 'cp "generated/Formula/jdkvalhalla@${JDK_VERSION}.rb" Formula/'
    assert_includes validate.fetch("run"), "cp generated/Casks/jdkvalhalla.rb Casks/"
  end

  def test_update_renderer_reproduces_current_prebuilt_packages
    render = workflow("update.yml").dig("jobs", "prepare", "steps")
                                   .find { |step| step["name"] == "Render formula and cask" }

    Dir.mktmpdir do |directory|
      FileUtils.cp_r(File.join(ROOT, "Formula"), directory)
      FileUtils.cp_r(File.join(ROOT, "Casks"), directory)
      _stdout, stderr, status = Open3.capture3(
        renderer_environment,
        "bash",
        "-c",
        render.fetch("run"),
        chdir: directory,
      )

      assert status.success?, stderr
      assert_equal(
        File.read(File.join(ROOT, "Formula", "jdkvalhalla@27.rb")),
        File.read(File.join(directory, "generated", "Formula", "jdkvalhalla@27.rb")),
      )
      assert_equal(
        File.read(File.join(ROOT, "Casks", "jdkvalhalla.rb")),
        File.read(File.join(directory, "generated", "Casks", "jdkvalhalla.rb")),
      )
    end
  end

  def test_update_renderer_rejects_cask_template_drift
    render = workflow("update.yml").dig("jobs", "prepare", "steps")
                                   .find { |step| step["name"] == "Render formula and cask" }

    Dir.mktmpdir do |directory|
      FileUtils.cp_r(File.join(ROOT, "Formula"), directory)
      FileUtils.cp_r(File.join(ROOT, "Casks"), directory)
      cask_path = File.join(directory, "Casks", "jdkvalhalla.rb")
      File.write(cask_path, File.read(cask_path).sub("sha256 arm:", "sha256 arm64:"))

      _stdout, stderr, status = Open3.capture3(
        renderer_environment,
        "bash",
        "-c",
        render.fetch("run"),
        chdir: directory,
      )

      refute status.success?
      assert_includes stderr, "cask checksum pattern missing"
    end
  end

  def test_update_renderer_selects_formula_template_by_numeric_jdk_line
    render = workflow("update.yml").dig("jobs", "prepare", "steps")
                                   .find { |step| step["name"] == "Render formula and cask" }

    Dir.mktmpdir do |directory|
      FileUtils.cp_r(File.join(ROOT, "Formula"), directory)
      FileUtils.cp_r(File.join(ROOT, "Casks"), directory)
      File.write(File.join(directory, "Formula", "jdkvalhalla@9.rb"), "not a formula\n")

      _stdout, stderr, status = Open3.capture3(
        renderer_environment.merge(
          "BUILD"        => "2",
          "FULL_VERSION" => "28-jep401ea4+2-1",
          "JDK_VERSION"  => "28",
        ),
        "bash",
        "-c",
        render.fetch("run"),
        chdir: directory,
      )

      assert status.success?, stderr
      assert File.exist?(File.join(directory, "generated", "Formula", "jdkvalhalla@28.rb"))
    end
  end

  def test_every_action_reference_is_an_immutable_commit
    action_references = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].flat_map do |path|
      document = YAML.load_file(path)
      document.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
                                   .each_with_object([]) do |step, references|
        references << step["uses"] if step["uses"]
      end
    end

    action_references.each do |reference|
      assert_match(/\A[^@\s]+@[0-9a-f]{40}\z/, reference)
    end
  end

  def test_every_workflow_declares_permissions_and_safe_checkout
    workflow_paths = Dir[File.join(ROOT, ".github", "workflows", "*.yml")]

    workflow_paths.each do |path|
      document = YAML.load_file(path)
      assert document.key?("permissions"), "#{File.basename(path)} has no top-level permissions"
      checkout_steps(document).each do |step|
        assert_equal(
          false,
          step.dig("with", "persist-credentials"),
          "#{File.basename(path)} checkout persists credentials",
        )
      end
    end
  end

  def test_obsolete_release_workflow_is_removed
    refute File.exist?(File.join(ROOT, ".github", "workflows", "release.yml"))
  end
end
