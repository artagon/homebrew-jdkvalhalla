# typed: strict
# frozen_string_literal: true

require "minitest/autorun"
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

  def test_bottle_package_is_bound_to_main_commit_and_refuses_overwrite
    document = workflow("bottles.yml")
    build = document.fetch("jobs").fetch("build")
    publish = document.fetch("jobs").fetch("publish")
    metadata = build.fetch("steps").find { |step| step["name"] == "Resolve bottle metadata" }
    package_step = publish.fetch("steps").find { |step| step["name"] == "Publish bottle package" }

    assert_includes metadata.fetch("run"), '[[ "${GITHUB_REF}" == "refs/heads/main" ]]'
    assert_includes metadata.fetch("run"), "${GITHUB_SHA::12}"
    assert_includes metadata.fetch("run"), 'formula.fetch("revision", 0)'
    assert_includes package_step.fetch("run"), "brew pr-upload --upload-only"
    refute_includes package_step.fetch("run"), "--keep-old"
    refute_includes package_step.fetch("run"), "--warn-on-upload-failure"
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
end
