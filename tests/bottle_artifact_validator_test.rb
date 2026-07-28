# typed: strict
# frozen_string_literal: true

require "digest"
require "erb"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

# Exercises strict bottle artifact and metadata validation.
class BottleArtifactValidatorTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__).freeze
  SCRIPT = File.join(ROOT, "scripts", "validate-bottle-artifact.rb").freeze
  FORMULA = "openjdk-valhalla@28"
  TAP = "artagon/jdkvalhalla"
  VERSION = "28-ea-20260727-f181286389fa"
  REVISION = "0123456789abcdef0123456789abcdef01234567"
  ROOT_URL = "https://ghcr.io/v2/artagon/jdkvalhalla"
  BOTTLE = "openjdk-valhalla@28--28-ea-20260727-f181286389fa.arm64_sonoma.bottle.tar.gz"

  def remote_filename(local_filename)
    ERB::Util.url_encode(local_filename.sub(/\A#{Regexp.escape(FORMULA)}--/o, "#{FORMULA}-"))
  end

  def run_validator(directory, output)
    Open3.capture3(
      RbConfig.ruby,
      SCRIPT,
      "--directory", directory,
      "--formula", FORMULA,
      "--tap", TAP,
      "--version", VERSION,
      "--git-revision", REVISION,
      "--root-url", ROOT_URL,
      "--github-output", output
    )
  end

  def write_valid_artifact(directory)
    bottle_path = File.join(directory, BOTTLE)
    File.binwrite(bottle_path, "immutable bottle payload")
    sha256 = Digest::SHA256.file(bottle_path).hexdigest
    json_path = File.join(directory, "#{FORMULA}--#{VERSION}.bottle.json")
    payload = {
      "#{TAP}/#{FORMULA}" => {
        "formula" => {
          "name"             => FORMULA,
          "pkg_version"      => VERSION,
          "tap_git_path"     => "Formula/#{FORMULA}.rb",
          "tap_git_revision" => REVISION,
        },
        "bottle"  => {
          "root_url" => ROOT_URL,
          "tags"     => {
            "arm64_sonoma" => {
              "filename"       => remote_filename(BOTTLE),
              "local_filename" => BOTTLE,
              "sha256"         => sha256,
            },
          },
        },
      },
    }
    File.write(json_path, JSON.pretty_generate(payload))
    [bottle_path, json_path]
  end

  def test_accepts_one_matching_bottle_and_writes_exact_paths
    Dir.mktmpdir do |directory|
      bottle_path, json_path = write_valid_artifact(directory)
      output = File.join(directory, "github-output")

      _stdout, stderr, status = run_validator(directory, output)

      assert status.success?, stderr
      assert_equal(
        "bottle_path=#{File.realpath(bottle_path)}\njson_path=#{File.realpath(json_path)}\n",
        File.read(output),
      )
    end
  end

  def test_accepts_revisioned_formula_version
    Dir.mktmpdir do |directory|
      revisioned_version = "#{VERSION}_1"
      bottle_path, json_path = write_valid_artifact(directory)
      revisioned_bottle = File.join(directory, File.basename(bottle_path).sub(VERSION, revisioned_version))
      revisioned_json = File.join(directory, File.basename(json_path).sub(VERSION, revisioned_version))
      FileUtils.mv(bottle_path, revisioned_bottle)
      payload = JSON.parse(File.read(json_path))
      entry = payload.fetch("#{TAP}/#{FORMULA}")
      entry.fetch("formula")["pkg_version"] = revisioned_version
      tag = entry.fetch("bottle").fetch("tags").values.first
      tag["local_filename"] = File.basename(revisioned_bottle)
      tag["filename"] = remote_filename(File.basename(revisioned_bottle))
      tag["sha256"] = Digest::SHA256.file(revisioned_bottle).hexdigest
      File.write(revisioned_json, JSON.pretty_generate(payload))
      FileUtils.rm_f(json_path)
      output = File.join(directory, "github-output")

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT,
        "--directory", directory,
        "--formula", FORMULA,
        "--tap", TAP,
        "--version", revisioned_version,
        "--git-revision", REVISION,
        "--root-url", ROOT_URL,
        "--github-output", output
      )

      assert status.success?, stderr
    end
  end

  def test_rejects_noncanonical_container_registry_root
    Dir.mktmpdir do |directory|
      write_valid_artifact(directory)

      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        SCRIPT,
        "--directory", directory,
        "--formula", FORMULA,
        "--tap", TAP,
        "--version", VERSION,
        "--git-revision", REVISION,
        "--root-url", "https://ghcr.io/v2/another/tap",
        "--github-output", File.join(directory, "output")
      )

      refute status.success?
      assert_includes stderr, "invalid bottle root URL"
    end
  end

  def test_rejects_additional_bottle_files
    Dir.mktmpdir do |directory|
      write_valid_artifact(directory)
      File.binwrite(File.join(directory, "unexpected.bottle.tar.gz"), "extra")

      _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))

      refute status.success?
      assert_includes stderr, "expected exactly one bottle archive"
    end
  end

  def test_rejects_additional_json_files
    Dir.mktmpdir do |directory|
      write_valid_artifact(directory)
      File.write(File.join(directory, "unexpected.bottle.json"), "{}")

      _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))

      refute status.success?
      assert_includes stderr, "expected exactly one bottle JSON"
    end
  end

  def test_rejects_metadata_from_another_git_revision
    Dir.mktmpdir do |directory|
      _bottle_path, json_path = write_valid_artifact(directory)
      payload = JSON.parse(File.read(json_path))
      payload.fetch("#{TAP}/#{FORMULA}").fetch("formula")["tap_git_revision"] = "f" * 40
      File.write(json_path, JSON.pretty_generate(payload))

      _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))

      refute status.success?
      assert_includes stderr, "git revision does not match"
    end
  end

  def test_rejects_checksum_mismatch
    Dir.mktmpdir do |directory|
      bottle_path, _json_path = write_valid_artifact(directory)
      File.binwrite(bottle_path, "modified after metadata generation")

      _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))

      refute status.success?
      assert_includes stderr, "SHA-256 does not match"
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

  def test_rejects_symlinked_bottle_archive
    Dir.mktmpdir do |directory|
      bottle_path, _json_path = write_valid_artifact(directory)
      target_path = File.join(directory, "payload")
      FileUtils.mv(bottle_path, target_path)
      File.symlink(target_path, bottle_path)

      _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))

      refute status.success?
      assert_includes stderr, "bottle archive must not be a symlink"
    end
  end

  def test_rejects_symlinked_bottle_json
    Dir.mktmpdir do |directory|
      _bottle_path, json_path = write_valid_artifact(directory)
      target_path = File.join(directory, "metadata")
      FileUtils.mv(json_path, target_path)
      File.symlink(target_path, json_path)

      _stdout, stderr, status = run_validator(directory, File.join(directory, "output"))

      refute status.success?
      assert_includes stderr, "bottle JSON must not be a symlink"
    end
  end
end
