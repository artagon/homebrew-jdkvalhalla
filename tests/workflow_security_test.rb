require "minitest/autorun"
require "yaml"

class WorkflowSecurityTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def workflow(name)
    YAML.load_file(File.join(ROOT, ".github", "workflows", name))
  end

  def checkout_steps(document)
    document.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
            .select { |step| step["uses"]&.start_with?("actions/checkout@") }
  end

  def test_bottle_build_cannot_write_repository_state
    document = workflow("bottles.yml")
    build = document.fetch("jobs").fetch("build")

    assert_equal({}, document["permissions"])
    assert_equal({ "contents" => "read" }, build["permissions"])
    assert checkout_steps({ "jobs" => { "build" => build } }).all? {
      |step| step.dig("with", "persist-credentials") == false
    }
  end

  def test_bottle_publish_has_narrow_write_permissions
    document = workflow("bottles.yml")
    publish = document.fetch("jobs").fetch("publish")

    assert_equal(
      { "contents" => "write", "pull-requests" => "write" },
      publish["permissions"],
    )
    refute publish.fetch("env", {}).key?("GH_TOKEN")

    release_step = publish.fetch("steps").find { |step| step["name"] == "Publish bottle release" }
    assert_equal "${{ github.token }}", release_step.fetch("env").fetch("GH_TOKEN")
  end

  def test_bottle_release_is_bound_to_main_commit_and_is_immutable
    document = workflow("bottles.yml")
    build = document.fetch("jobs").fetch("build")
    publish = document.fetch("jobs").fetch("publish")
    metadata = build.fetch("steps").find { |step| step["name"] == "Resolve bottle metadata" }
    release_step = publish.fetch("steps").find { |step| step["name"] == "Publish bottle release" }

    assert_includes metadata.fetch("run"), '[[ "${GITHUB_REF}" == "refs/heads/main" ]]'
    assert_includes metadata.fetch("run"), "${GITHUB_SHA::12}"
    assert_includes release_step.fetch("run"), '--target "${GITHUB_SHA}"'
    assert_includes release_step.fetch("run"), '"repos/${GITHUB_REPOSITORY}/git/refs"'
    assert_includes release_step.fetch("run"), 'ref="refs/tags/${BOTTLE_TAG}"'
    assert_includes release_step.fetch("run"), 'sha="${GITHUB_SHA}"'
    assert_includes release_step.fetch("run"), "--verify-tag"
    assert_operator(
      release_step.fetch("run").index('"repos/${GITHUB_REPOSITORY}/git/refs"'),
      :<,
      release_step.fetch("run").index("gh release create"),
    )
    refute_includes release_step.fetch("run"), "--clobber"
  end

  def test_bottle_artifact_paths_come_from_validator_outputs
    document = workflow("bottles.yml")
    build_steps = document.fetch("jobs").fetch("build").fetch("steps")
    publish_steps = document.fetch("jobs").fetch("publish").fetch("steps")
    upload = build_steps.find { |step| step["name"] == "Upload bottle job artifact" }
    validate = publish_steps.find { |step| step["name"] == "Validate bottle artifact" }
    release_step = publish_steps.find { |step| step["name"] == "Publish bottle release" }
    merge = publish_steps.find { |step| step["name"] == "Merge bottle metadata into formula" }

    assert_equal(
      "${{ steps.artifact.outputs.bottle_path }}\n${{ steps.artifact.outputs.json_path }}",
      upload.fetch("with").fetch("path"),
    )
    assert validate, "missing Validate bottle artifact step"
    assert_includes validate.fetch("run"), "scripts/validate-bottle-artifact.rb"
    assert_includes release_step.fetch("run"), '"${BOTTLE_PATH}"'
    assert_includes merge.fetch("run"), '"${BOTTLE_JSON}"'
    refute_includes release_step.fetch("run"), "*.tar.gz"
    refute_includes merge.fetch("run"), "find bottle-artifact"
  end

  def test_every_action_reference_is_an_immutable_commit
    action_references = Dir[File.join(ROOT, ".github", "workflows", "*.yml")].flat_map do |path|
      document = YAML.load_file(path)
      document.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }
              .map { |step| step["uses"] }
              .compact
    end

    action_references.each do |reference|
      assert_match(%r{\A[^@\s]+@[0-9a-f]{40}\z}, reference)
    end
  end
end
