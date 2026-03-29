class JdkvalhallaAT27 < Formula
  desc "Project Valhalla JDK 27 - Value Classes and Objects (JEP 401)"
  homepage "https://jdk.java.net/valhalla/"
  version "27-jep401ea3+1-1"
  on_macos do
    if Hardware::CPU.arm?
      url "https://download.java.net/java/early_access/valhalla/27/1/openjdk-27-jep401ea3+1-1_macos-aarch64_bin.tar.gz"
      sha256 "b8bdd7b181c6a5ea2dd9959255e222cd9d9a9f42cca4f2400991b9b2ff7ffb7d"
    else
      url "https://download.java.net/java/early_access/valhalla/27/1/openjdk-27-jep401ea3+1-1_macos-x64_bin.tar.gz"
      sha256 "64d2deee65c221b7fbdfb936d42981987c1505a6057a1847e5fdb37afabb103a"
    end
  end
  on_linux do
    if Hardware::CPU.arm?
      url "https://download.java.net/java/early_access/valhalla/27/1/openjdk-27-jep401ea3+1-1_linux-aarch64_bin.tar.gz"
      sha256 "f9b56dd9fed330aa30ff2428f58358dc2cc67eae53be8805f819062d925d314a"
    else
      url "https://download.java.net/java/early_access/valhalla/27/1/openjdk-27-jep401ea3+1-1_linux-x64_bin.tar.gz"
      sha256 "b8bdd7b181c6a5ea2dd9959255e222cd9d9a9f42cca4f2400991b9b2ff7ffb7d"
    end
  end
  def install
    if OS.mac?
      jdk_home = Dir["jdk-*.jdk/Contents/Home"].first
      libexec.install Dir["#{jdk_home}/*"]
    else
      libexec.install Dir["*"]
    end
    bin.install_symlink Dir["#{libexec}/bin/*"]
  end
  test do
    (testpath/"Hello.java").write <<~JAVA
      class Hello {
          public static void main(String[] args) {
              System.out.println("hi");
          }
      }
    JAVA
    system "#{bin}/javac", "--enable-preview", "--release", "27", "Hello.java"
    assert_equal "hi
", shell_output("#{bin}/java --enable-preview Hello")
    assert_match(/27/, shell_output("#{bin}/java --version 2>&1"))
  end
end
