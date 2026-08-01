class OpenjdkValhallaAT27 < Formula
  desc "JDK 27 Valhalla JEP 401 early-access milestone built from source"
  homepage "https://openjdk.org/projects/valhalla/"
  url "https://github.com/openjdk/valhalla/archive/f9799f4c1a35694951413fda0986cdebe49f85d0.tar.gz"
  version "27-ea-20260310-f9799f4c1a35"
  sha256 "eb44694f4525aa7e57a6304d4c01f17ffaf78824ec76016e512742b643664367"
  license "GPL-2.0-only" => { with: "Classpath-exception-2.0" }

  livecheck do
    skip "pinned to the source tag for the published JEP 401 EA3 milestone"
  end

  keg_only :versioned_formula

  depends_on "autoconf" => :build
  depends_on "make" => :build
  depends_on "pkgconf" => :build
  depends_on xcode: ["15.4", :build] # for metal
  depends_on arch: :arm64
  depends_on "freetype"
  depends_on "giflib"
  depends_on "harfbuzz"
  depends_on "jpeg-turbo"
  depends_on "libpng"
  depends_on "little-cms2"
  depends_on macos: :sonoma

  uses_from_macos "unzip" => :build
  uses_from_macos "zip" => :build
  uses_from_macos "cups" => :no_linkage

  resource "boot-jdk" do
    url "https://download.java.net/java/GA/jdk26/c3cc523845074aa0af4f5e1e1ed4151d/35/GPL/" \
        "openjdk-26_macos-aarch64_bin.tar.gz"
    sha256 "254586bcd1bf6dcd125ad667ac32562cb1e2ab1abf3a61fb117b6fabb571e765"
  end

  def install
    boot_jdk = buildpath/"boot-jdk"
    resource("boot-jdk").stage boot_jdk
    boot_jdk /= "Contents/Home"
    java_options = ENV.delete("_JAVA_OPTIONS")

    args = %W[
      --disable-warnings-as-errors
      --with-boot-jdk-jvmargs=#{java_options}
      --with-boot-jdk=#{boot_jdk}
      --with-debug-level=release
      --with-jvm-variants=server
      --with-native-debug-symbols=none
      --with-source-date=1773137610
      --with-vendor-bug-url=https://bugs.openjdk.org/
      --with-vendor-name=Artagon
      --with-vendor-url=https://openjdk.org/projects/valhalla/
      --with-vendor-version-string=Artagon
      --with-vendor-vm-bug-url=https://bugs.openjdk.org/
      --with-version-opt=valhalla-f9799f4c1a35
      --with-version-pre=ea
      --without-version-build
      --with-freetype=system
      --with-giflib=system
      --with-harfbuzz=system
      --with-lcms=system
      --with-libjpeg=system
      --with-libpng=system
      --with-zlib=system
    ]

    ldflags = %W[
      -Wl,-rpath,#{loader_path.gsub("$", "\\$$")}
      -Wl,-rpath,#{loader_path.gsub("$", "\\$$")}/server
      -headerpad_max_install_names
    ]

    inreplace "make/autoconf/lib-freetype.m4", '= "xmacosx"', '= ""'

    args += %W[
      --enable-dtrace
      --with-extra-ldflags=#{ldflags.join(" ")}
      --with-freetype-include=#{formula_opt_include("freetype")}
      --with-freetype-lib=#{formula_opt_lib("freetype")}
      --with-sysroot=#{MacOS.sdk_path}
    ]

    system "bash", "configure", *args
    ENV["MAKEFLAGS"] = "JOBS=#{[ENV.make_jobs, 4].min}"
    system "gmake", "images"

    libexec.install Dir["build/*/images/jdk-bundle/*"].first => "openjdk.jdk"
    jdk = libexec/"openjdk.jdk/Contents/Home"
    bin.install_symlink Dir[jdk/"bin/*"]
    include.install_symlink Dir[jdk/"include/*.h"]
    include.install_symlink Dir[jdk/"include"/OS.kernel_name.downcase/"*.h"]
    man1.install_symlink Dir[jdk/"man/man1/*"]
  end

  def caveats
    <<~EOS
      For the system Java wrappers to find this JDK, symlink it with
        sudo ln -sfn #{opt_libexec}/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-valhalla-27.jdk
    EOS
  end

  test do
    (testpath/"ValueSmoke.java").write <<~JAVA
      import java.util.Objects;

      class ValueSmoke {
          value record Point(int x, int y) {
          }

          public static void main(String[] args) {
              Point first = new Point(3, 4);
              Point second = new Point(3, 4);
              System.out.println("equal = " + first.equals(second));
              System.out.println("identity = " + Objects.hasIdentity(first));
          }
      }
    JAVA

    system bin/"javac", "--enable-preview", "--release", "27", "ValueSmoke.java"
    output = shell_output("#{bin}/java --enable-preview ValueSmoke")
    assert_match "equal = true", output
    assert_match "identity = false", output
    assert_match "valhalla-f9799f4c1a35", shell_output("#{bin}/java --version 2>&1")
  end
end
