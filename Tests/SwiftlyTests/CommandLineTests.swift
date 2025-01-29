import CommandLine
import XCTest

class CommandLineTests: XCTestCase {
    func testDscl() {
        XCTAssertEqual(
            Dscl(datasource: ".").read(path: "/Users/swiftly", keys: "UserShell").args(),
            ["dscl", ".", "-read", "/Users/swiftly", "UserShell"]
        )

        XCTAssertEqual(
            Dscl(datasource: ".").read(path: "/Users/swiftly", keys: "UserShell", "Picture").args(),
            ["dscl", ".", "-read", "/Users/swiftly", "UserShell", "Picture"]
        )
    }

    func testLipo() {
        XCTAssertEqual(
            Lipo("swiftly1", "swiftly2").create(.output("swiftly-universal")).args(),
            ["lipo", "swiftly1", "swiftly2", "-create", "-output", "swiftly-universal"]
        )
    }

    func testPkgbuild() {
        XCTAssertEqual(
            Pkgbuild(.installLocation("/usr/local"), .version("1.0.0"), .identifier("org.foo.bar"), .sign("mycert"), root: "someroot/", "my.pkg").args(),
            ["pkgbuild", "--install-location", "/usr/local", "--version", "1.0.0", "--identifier", "org.foo.bar", "--sign", "mycert", "--root", "someroot/", "my.pkg"]
        )

        XCTAssertEqual(
            Pkgbuild(.installLocation("/usr/local"), .version("1.0.0"), .identifier("org.foo.bar"), root: "someroot/", "my.pkg").args(),
            ["pkgbuild", "--install-location", "/usr/local", "--version", "1.0.0", "--identifier", "org.foo.bar", "--root", "someroot/", "my.pkg"]
        )
    }

    func testGetent() {
        XCTAssertEqual(
            Getent(database: "passwd", keys: "swiftly").args(),
            ["getent", "passwd", "swiftly"]
        )
    }

    func testGit() {
        XCTAssertEqual(
            Git().log(.maxCount(1), .pretty("format:%d")).args(),
            ["git", "log", "--max-count=1", "--pretty=format:%d"]
        )

        XCTAssertEqual(
            Git().diffIndex(.quiet, treeIsh: "HEAD").args(),
            ["git", "diff-index", "--quiet", "HEAD"]
        )
    }

    func testTar() {
        XCTAssertEqual(
            Tar(.directory("/mydir")).extract(.compressed, .archive("mydir.tar.gz")).args(),
            ["tar", "-C", "/mydir", "-x", "-z", "--file", "mydir.tar.gz"]
        )

        XCTAssertEqual(
            Tar(.directory("/mydir")).create(.compressed, .archive("mydir.tar.gz"), files: "a.txt").args(),
            ["tar", "-C", "/mydir", "-c", "-z", "--file", "mydir.tar.gz", "a.txt"]
        )
    }

    func testSwift() {
        XCTAssertEqual(
            Swift().package().reset().args(),
            ["swift", "package", "reset"]
        )

        XCTAssertEqual(
            Swift().sdk().install("https://example.com/sdk.tar.gz", checksum: "deadbeef").args(),
            ["swift", "sdk", "install", "https://example.com/sdk.tar.gz", "--checksum=deadbeef"]
        )

        XCTAssertEqual(
            Swift().build(.swiftSdk("my-sdk"), .product("product1"), .pkgConfigPath("pkgconfig"), .staticSwiftStdlib, .configuration("release")).args(),
            ["swift", "build", "--swift-sdk=my-sdk", "--product=product1", "--pkg-config-path=pkgconfig", "--static-swift-stdlib", "--configuration=release"]
        )

        XCTAssertEqual(
            Swift().sdk().remove("my-sdk").args(),
            ["swift", "sdk", "remove", "my-sdk"]
        )

        XCTAssertEqual(
            Swift().build(.product("product1"), .configuration("release"), .arch("x86_64")).args(),
            ["swift", "build", "--product=product1", "--configuration=release", "--arch=x86_64"]
        )
    }

    func testMake() {
        XCTAssertEqual(
            Make().args(),
            ["make"]
        )

        XCTAssertEqual(
            Make().install().args(),
            ["make", "install"]
        )
    }

    func testStrip() {
        XCTAssertEqual(
            Strip("foo").args(),
            ["strip", "foo"]
        )
    }

    func testSha256sum() {
        XCTAssertEqual(
            Sha256sum("abc.txt").args(),
            ["sha256sum", "abc.txt"]
        )
    }

    func testPkgutil() {
        XCTAssertEqual(
            Pkgutil(.verbose).expand(pkgPath: "mypkg", dirPath: "somedir").args(),
            ["pkgutil", "--verbose", "--expand", "mypkg", "somedir"]
        )

        XCTAssertEqual(
            Pkgutil(.volume("volume1")).forget(packageId: "org.foo.bar").args(),
            ["pkgutil", "--volume", "volume1", "--forget", "org.foo.bar"]
        )

        XCTAssertEqual(
            Pkgutil().expand(pkgPath: "mypkg", dirPath: "somedir").args(),
            ["pkgutil", "--expand", "mypkg", "somedir"]
        )
    }

    func testInstaller() {
        XCTAssertEqual(
            Installer(pkg: "org.foo.bar", target: "CurrentUserHomeDirectory").args(),
            ["installer", "-pkg", "org.foo.bar", "-target", "CurrentUserHomeDirectory"]
        )

        XCTAssertEqual(
            Installer(verbose: true, pkg: "org.foo.bar", target: "CurrentUserHomeDirectory").args(),
            ["installer", "-verbose", "-pkg", "org.foo.bar", "-target", "CurrentUserHomeDirectory"]
        )
    }

    func testGpg() {
        XCTAssertEqual(
            Gpg()._import(files: "key.asc").args(),
            ["gpg", "--import", "key.asc"]
        )

        XCTAssertEqual(
            Gpg().verify(files: "foo.txt.sig", "foo.txt").args(),
            ["gpg", "--verify", "foo.txt.sig", "foo.txt"]
        )
    }
}
