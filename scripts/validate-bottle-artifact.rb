#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "digest"
require "erb"
require "json"
require "optparse"

options = {}
OptionParser.new do |parser|
  parser.on("--directory PATH") { |value| options[:directory] = value }
  parser.on("--formula TOKEN") { |value| options[:formula] = value }
  parser.on("--tap NAME") { |value| options[:tap] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--git-revision SHA") { |value| options[:git_revision] = value }
  parser.on("--root-url URL") { |value| options[:root_url] = value }
  parser.on("--github-output PATH") { |value| options[:github_output] = value }
end.parse!

# Reports a validation failure without exposing artifact content.
module Validator
  def self.fail(message)
    warn "ERROR: #{message}"
    exit 1
  end
end

required = [:directory, :formula, :tap, :version, :git_revision, :root_url, :github_output]
missing = required.select { |key| options.fetch(key, "").empty? }
Validator.fail("missing required options: #{missing.join(", ")}") unless missing.empty?

formula = options.fetch(:formula)
tap = options.fetch(:tap)
version = options.fetch(:version)
git_revision = options.fetch(:git_revision)
root_url = options.fetch(:root_url)

Validator.fail("invalid formula token") unless formula.match?(/\Aopenjdk-valhalla@\d+\z/)
Validator.fail("invalid tap name") unless tap.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z})
Validator.fail("invalid formula version") unless version.match?(/\A[0-9A-Za-z][0-9A-Za-z._+-]*\z/)
Validator.fail("invalid git revision") unless git_revision.match?(/\A[0-9a-f]{40}\z/)

expected_root_url = "https://ghcr.io/v2/#{tap.downcase}"
Validator.fail("invalid bottle root URL") if root_url != expected_root_url

directory = File.realpath(options.fetch(:directory))
Validator.fail("artifact directory is not a directory") unless File.directory?(directory)

bottle_paths = Dir.children(directory).each_with_object([]) do |name, paths|
  path = File.join(directory, name)
  paths << path if File.file?(path) && name.end_with?(".bottle.tar.gz")
end
json_paths = Dir.children(directory).each_with_object([]) do |name, paths|
  path = File.join(directory, name)
  paths << path if File.file?(path) && name.end_with?(".bottle.json")
end
Validator.fail("expected exactly one bottle archive, found #{bottle_paths.length}") unless bottle_paths.one?
Validator.fail("expected exactly one bottle JSON, found #{json_paths.length}") unless json_paths.one?

bottle_path = bottle_paths.first
json_path = json_paths.first
Validator.fail("bottle archive must not be a symlink") if File.symlink?(bottle_path)
Validator.fail("bottle JSON must not be a symlink") if File.symlink?(json_path)

begin
  document = JSON.parse(File.read(json_path))
rescue JSON::ParserError => e
  Validator.fail("invalid bottle JSON: #{e.message}")
end

full_name = "#{tap}/#{formula}"
Validator.fail("bottle JSON must contain only #{full_name}") if document.keys != [full_name]

entry = document.fetch(full_name)
formula_metadata = entry.fetch("formula") { Validator.fail("formula metadata is missing") }
bottle_metadata = entry.fetch("bottle") { Validator.fail("bottle metadata is missing") }

Validator.fail("formula name does not match") if formula_metadata["name"] != formula
Validator.fail("formula version does not match") if formula_metadata["pkg_version"] != version
Validator.fail("formula path does not match") if formula_metadata["tap_git_path"] != "Formula/#{formula}.rb"
Validator.fail("git revision does not match") if formula_metadata["tap_git_revision"] != git_revision
Validator.fail("bottle root URL does not match") if bottle_metadata["root_url"] != root_url

tags = bottle_metadata["tags"]
Validator.fail("expected bottle tags") unless tags.is_a?(Hash)
Validator.fail("expected exactly one bottle tag") unless tags.one?
tag, tag_metadata = tags.first
Validator.fail("unexpected bottle tag #{tag}") unless tag.match?(/\Aarm64_[a-z0-9_]+\z/)

local_filename = tag_metadata["local_filename"]
remote_filename = tag_metadata["filename"]
Validator.fail("local bottle filename does not match") if local_filename != File.basename(bottle_path)
Validator.fail("unsafe remote bottle filename") unless remote_filename.is_a?(String)
Validator.fail("unsafe remote bottle filename") if File.basename(remote_filename) != remote_filename
remote_basename = local_filename.sub(/\A#{Regexp.escape(formula)}--/, "#{formula}-")
expected_remote_filename = ERB::Util.url_encode(remote_basename)
Validator.fail("remote bottle filename does not match") if remote_filename != expected_remote_filename

expected_sha256 = tag_metadata["sha256"]
Validator.fail("invalid bottle SHA-256") unless expected_sha256&.match?(/\A[0-9a-f]{64}\z/)
actual_sha256 = Digest::SHA256.file(bottle_path).hexdigest
Validator.fail("bottle SHA-256 does not match") if actual_sha256 != expected_sha256

output_values = {
  "bottle_path" => File.realpath(bottle_path),
  "json_path"   => File.realpath(json_path),
}
Validator.fail("artifact path contains a newline") if output_values.values.any? { |value| value.match?(/[\r\n]/) }

File.open(options.fetch(:github_output), "a", 0600) do |output|
  output_values.each { |key, value| output.puts "#{key}=#{value}" }
end

puts "Validated #{formula} #{version} bottle #{File.basename(bottle_path)}"
