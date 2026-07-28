require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class BottleArtifactValidatorTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "scripts", "validate-bottle-artifact.rb")
  FORMULA = "openjdk-valhalla@28"
  TAP = "artagon/jdkvalhalla"
  VERSION = "28-ea-20260727-f181286389fa"
  REVISION = "0123456789abcdef0123456789abcdef01234567"
  ROOT_URL = "https://github.com/artagon/homebrew-jdkvalhalla/releases/download/" \
             "bottle-openjdk-valhalla-28-test"
  BOTTLE = "openjdk-valhalla@28--28-ea-20260727-f181286389fa.arm64_sonoma.bottle.tar.gz"

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
      "--github-output", output,
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
          "name" => FORMULA,
          "pkg_version" => VERSION,
          "tap_git_path" => "Formula/#{FORMULA}.rb",
          "tap_git_revision" => REVISION,
        },
        "bottle" => {
          "root_url" => ROOT_URL,
          "tags" => {
            "arm64_sonoma" => {
              "filename" => BOTTLE,
              "local_filename" => BOTTLE,
              "sha256" => sha256,
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
