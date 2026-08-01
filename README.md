# Homebrew JDK Valhalla

Homebrew packages for supported [OpenJDK Project
Valhalla](https://openjdk.org/projects/valhalla/) early-access releases.
Choose an official prebuilt JDK for a fast install, or a pinned source formula
when you need an Artagon-built Valhalla snapshot.

[![Validate](https://github.com/artagon/homebrew-jdkvalhalla/actions/workflows/validate.yml/badge.svg)](https://github.com/artagon/homebrew-jdkvalhalla/actions/workflows/validate.yml)
[![CodeQL](https://github.com/artagon/homebrew-jdkvalhalla/actions/workflows/codeql.yml/badge.svg)](https://github.com/artagon/homebrew-jdkvalhalla/actions/workflows/codeql.yml)

These are experimental EA JDKs for testing and development. They are not
production JDKs, and preview APIs or class-file formats may change.

## Install

You can use fully qualified commands without tapping first.

### Official prebuilt binaries

The cask is the fast default on macOS:

```bash
brew install --cask artagon/jdkvalhalla/jdkvalhalla
```

Versioned prebuilt formulas work on macOS and Linux:

```bash
brew install artagon/jdkvalhalla/jdkvalhalla@27
brew install artagon/jdkvalhalla/jdkvalhalla@26
```

The existing `jdkvalhalla`, `jdkvalhalla@26`, and `jdkvalhalla@27` tokens
remain supported for backward compatibility.

### Bottled or source-built JDKs

`openjdk-valhalla` is the rolling source/bottle alias. The versioned source
lines are `openjdk-valhalla@27` and `openjdk-valhalla@28`.

```bash
# Current rolling source line
brew install artagon/jdkvalhalla/openjdk-valhalla

# Select an exact line
brew install artagon/jdkvalhalla/openjdk-valhalla@27
brew install artagon/jdkvalhalla/openjdk-valhalla@28
```

Homebrew installs a compatible bottle when one is published. Otherwise, the
same command builds the formula's pinned OpenJDK revision locally. To require a
local source build even when a bottle exists:

```bash
brew install --build-from-source artagon/jdkvalhalla/openjdk-valhalla@28
```

Source builds are long-running and can take hours. They are Apple
Silicon-only, require macOS Sonoma or newer and Xcode 15.4 or newer, and cap
the build at four jobs. Check the selected package before an unexpected build:

```bash
brew info artagon/jdkvalhalla/openjdk-valhalla@28
```

## Package matrix

| Token | Mode | Release line | Platforms |
| --- | --- | --- | --- |
| `jdkvalhalla` | Official prebuilt cask | Current Valhalla EA | macOS |
| `jdkvalhalla@26` | Official prebuilt formula | JDK 26 Valhalla EA | macOS, Linux |
| `jdkvalhalla@27` | Official prebuilt formula | JDK 27 Valhalla EA | macOS, Linux |
| `openjdk-valhalla` | Rolling source/bottle alias | Current source line | Apple Silicon macOS |
| `openjdk-valhalla@27` | Pinned source/bottle formula | JDK 27 Valhalla | Apple Silicon macOS |
| `openjdk-valhalla@28` | Pinned source/bottle formula | JDK 28 Valhalla | Apple Silicon macOS |

The current prebuilt releases are `26-jep401ea2+1-1` and
`27-jep401ea3+1-1`. Source formula versions include the pinned OpenJDK commit
so an update is explicit and reviewable.

## Use with jenv

Register the installed JDK home that matches the package mode.

```bash
# Prebuilt cask
jenv add /Library/Java/JavaVirtualMachines/jdk-valhalla.jdk/Contents/Home

# Versioned prebuilt formula
jenv add "$(brew --prefix jdkvalhalla@27)/libexec"

# Versioned source/bottle formulas
jenv add "$(brew --prefix openjdk-valhalla@27)/libexec/openjdk.jdk/Contents/Home"
jenv add "$(brew --prefix openjdk-valhalla@28)/libexec/openjdk.jdk/Contents/Home"
```

List the identifiers discovered by `jenv`, then select one for a project or
for your user account:

```bash
jenv versions
jenv local <version>
jenv global <version>
```

If `java -version` does not follow the selected version, enable the export
plugin and restart the shell:

```bash
jenv enable-plugin export
```

## Preview features

Valhalla language and VM features require preview flags. Match `--release` to
the installed JDK line:

```bash
javac --enable-preview --release 28 ValueDemo.java
java --enable-preview ValueDemo
```

## Updates and validation

The weekly update workflow reads only the official Valhalla page and
`download.java.net` archives. It validates the release string, verifies the
published SHA-256 value against each downloaded archive, and opens a pull
request containing only the current versioned prebuilt formula and cask.

Pull requests run Ruby syntax, Homebrew policy, contract, workflow, and
prebuilt installation checks. Source formulas are not built in ordinary pull
request validation because a Valhalla source build is intentionally
long-running. Source bottle publication performs the full build and smoke test
in a separate manual workflow.

For local repository checks:

```bash
./scripts/test.sh
```

## Security and support

Report sensitive issues through the repository's private security advisory
form. See [SECURITY.md](SECURITY.md) for the source allowlist, checksum,
workflow, and bottle publication controls.

For non-sensitive defects or package requests, open a
[GitHub issue](https://github.com/artagon/homebrew-jdkvalhalla/issues).

## License

The tap is distributed under the same GPL-2.0 with Classpath Exception terms
as the packaged OpenJDK builds. See [LICENSE](LICENSE).
