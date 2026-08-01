#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

pattern = /\b(?<full>(?<jdk>\d{2})-(?<tag>jep401ea\d+)\+(?<build>\d+)-\d+)\b/
matches = File.read(ARGV.fetch(0), encoding: "UTF-8").scan(pattern)
versions = matches.map(&:first).uniq
abort "expected exactly one Valhalla version" unless versions.one?

match = pattern.match(versions.fetch(0))
abort "invalid JDK line" unless (26..99).cover?(Integer(match[:jdk], 10))
abort "invalid build" unless (1..999).cover?(Integer(match[:build], 10))

values = {
  "full_version" => match[:full],
  "jdk_version"  => match[:jdk],
  "ea_tag"       => match[:tag],
  "build"        => match[:build],
}
abort "unsafe Valhalla version value" if values.values.any? { |value| value.match?(/[\r\n]/) }

output_path = ARGV.fetch(1)
File.open(output_path, "a", 0600) do |output|
  values.each { |key, value| output.puts "#{key}=#{value}" }
end
File.chmod(0600, output_path)
