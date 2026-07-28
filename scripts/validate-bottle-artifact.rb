#!/usr/bin/env ruby

require "digest"
require "json"
require "optparse"
require "pathname"
require "uri"

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

def fail_validation(message)
  warn "ERROR: #{message}"
  exit 1
end

required = %i[directory formula tap version git_revision root_url github_output]
missing = required.reject { |key| options[key] && !options[key].empty? }
fail_validation("missing required options: #{missing.join(", ")}") unless missing.empty?

formula = options.fetch(:formula)
tap = options.fetch(:tap)
version = options.fetch(:version)
git_revision = options.fetch(:git_revision)
root_url = options.fetch(:root_url)

fail_validation("invalid formula token") unless formula.match?(/\Aopenjdk-valhalla@\d+\z/)
fail_validation("invalid tap name") unless tap.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z})
fail_validation("invalid formula version") unless version.match?(/\A[0-9A-Za-z][0-9A-Za-z._+-]*\z/)
fail_validation("invalid git revision") unless git_revision.match?(/\A[0-9a-f]{40}\z/)

uri = URI.parse(root_url)
unless uri.is_a?(URI::HTTPS) && uri.host == "github.com" && uri.userinfo.nil? &&
       uri.query.nil? && uri.fragment.nil? && uri.path.start_with?("/")
  fail_validation("invalid bottle root URL")
end

directory = Pathname(options.fetch(:directory)).realpath
fail_validation("artifact directory is not a directory") unless directory.directory?

bottle_paths = directory.children.select { |path| path.file? && path.basename.to_s.end_with?(".bottle.tar.gz") }
json_paths = directory.children.select { |path| path.file? && path.basename.to_s.end_with?(".bottle.json") }
fail_validation("expected exactly one bottle archive, found #{bottle_paths.length}") unless bottle_paths.one?
fail_validation("expected exactly one bottle JSON, found #{json_paths.length}") unless json_paths.one?

bottle_path = bottle_paths.first
json_path = json_paths.first
fail_validation("bottle archive must not be a symlink") if bottle_path.symlink?
fail_validation("bottle JSON must not be a symlink") if json_path.symlink?

begin
  document = JSON.parse(json_path.read)
rescue JSON::ParserError => e
  fail_validation("invalid bottle JSON: #{e.message}")
end

full_name = "#{tap}/#{formula}"
fail_validation("bottle JSON must contain only #{full_name}") unless document.keys == [full_name]

entry = document.fetch(full_name)
formula_metadata = entry.fetch("formula") { fail_validation("formula metadata is missing") }
bottle_metadata = entry.fetch("bottle") { fail_validation("bottle metadata is missing") }

fail_validation("formula name does not match") unless formula_metadata["name"] == formula
fail_validation("formula version does not match") unless formula_metadata["pkg_version"] == version
unless formula_metadata["tap_git_path"] == "Formula/#{formula}.rb"
  fail_validation("formula path does not match")
end
unless formula_metadata["tap_git_revision"] == git_revision
  fail_validation("git revision does not match")
end
fail_validation("bottle root URL does not match") unless bottle_metadata["root_url"] == root_url

tags = bottle_metadata["tags"]
fail_validation("expected exactly one bottle tag") unless tags.is_a?(Hash) && tags.one?
tag, tag_metadata = tags.first
fail_validation("unexpected bottle tag #{tag}") unless tag.match?(/\Aarm64_[a-z0-9_]+\z/)

local_filename = tag_metadata["local_filename"]
remote_filename = tag_metadata["filename"]
fail_validation("local bottle filename does not match") unless local_filename == bottle_path.basename.to_s
fail_validation("unsafe remote bottle filename") unless remote_filename.is_a?(String) &&
                                                        File.basename(remote_filename) == remote_filename
decoded_remote_filename = URI::DEFAULT_PARSER.unescape(remote_filename)
unless decoded_remote_filename == local_filename
  fail_validation("remote bottle filename does not match")
end

expected_sha256 = tag_metadata["sha256"]
fail_validation("invalid bottle SHA-256") unless expected_sha256&.match?(/\A[0-9a-f]{64}\z/)
actual_sha256 = Digest::SHA256.file(bottle_path).hexdigest
fail_validation("bottle SHA-256 does not match") unless actual_sha256 == expected_sha256

output_values = {
  "bottle_path" => bottle_path.realpath.to_s,
  "json_path" => json_path.realpath.to_s,
}
if output_values.values.any? { |value| value.match?(/[\r\n]/) }
  fail_validation("artifact path contains a newline")
end

File.open(options.fetch(:github_output), "a", 0o600) do |output|
  output_values.each { |key, value| output.puts "#{key}=#{value}" }
end

puts "Validated #{formula} #{version} bottle #{bottle_path.basename}"
