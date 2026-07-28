# typed: strict
# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

# Exercises strict, unambiguous parsing of the official Valhalla release page.
class ParseValhallaReleaseTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__).freeze
  SCRIPT = File.join(ROOT, "scripts", "parse-valhalla-release.rb").freeze

  def run_parser(html)
    directory = Dir.mktmpdir
    page = File.join(directory, "page.html")
    output = File.join(directory, "output")
    File.write(page, html)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT, page, output)
    [directory, output, stdout, stderr, status]
  end

  def test_parses_one_valid_release
    directory, output, _stdout, stderr, status = run_parser(
      '<a href="/java/early_access/valhalla/27/1/">27-jep401ea3+1-1</a>',
    )

    assert status.success?, stderr
    assert_equal(
      "full_version=27-jep401ea3+1-1\n" \
      "jdk_version=27\n" \
      "ea_tag=jep401ea3\n" \
      "build=1\n",
      File.read(output),
    )
    assert_equal 0600, File.stat(output).mode & 0777
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  def test_rejects_page_without_release
    directory, _output, _stdout, stderr, status = run_parser("<html>No release</html>")

    refute status.success?
    assert_includes stderr, "expected exactly one Valhalla version"
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  def test_rejects_two_different_releases
    directory, _output, _stdout, stderr, status = run_parser(
      "27-jep401ea3+1-1 28-jep401ea4+2-1",
    )

    refute status.success?
    assert_includes stderr, "expected exactly one Valhalla version"
  ensure
    FileUtils.remove_entry(directory) if directory
  end

  def test_rejects_version_split_by_newline
    directory, _output, _stdout, stderr, status = run_parser("27-jep401ea3+\n1-1")

    refute status.success?
    assert_includes stderr, "expected exactly one Valhalla version"
  ensure
    FileUtils.remove_entry(directory) if directory
  end
end
