import ArgumentParser
import CommandLine
import Foundation

public struct SwiftPlatform: Codable {
    public var name: String?
    public var checksum: String?
}

public struct SwiftRelease: Codable {
    public var name: String?
    public var platforms: [SwiftPlatform]?
}

// These functions are cloned and adapted from SwiftlyCore until we can do better bootstrapping
public struct Error: LocalizedError, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String { self.message }
    public var description: String { self.message }
}

#if os(macOS)

public func getShell() async throws -> String {
    let props = try await properties(Dscl(datasource: ".").read(path: FileManager.default.homeDirectoryForCurrentUser.path, keys: "UserShell"))
    if let shellInfo = props.first, shellInfo.key == "UserShell" { return shellInfo.value }

    // Fall back to zsh on macOS
    return "/bin/zsh"
}

#elseif os(Linux)

public func getShell() async throws -> String {
    if let entry = try await entries(Getent(database: "passwd", keys: ProcessInfo.processInfo.userName)).first {
        if let shell = entry.last { return shell }
    }

    // Fall back on bash on Linux and other Unixes
    return "/bin/bash"
}
#endif

@main
struct BuildSwiftlyRelease: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-swiftly-release",
        abstract: "Build final swiftly product for a release."
    )

    @Flag(name: .long, help: "Skip the git repo checks and proceed.")
    var skip: Bool = false

#if os(macOS)
    @Option(help: "Installation certificate to use when building the macOS package")
    var cert: String?

    @Option(help: "Package identifier of macOS package")
    var identifier: String = "org.swift.swiftly"
#elseif os(Linux)
    @Flag(name: .long, help: "Deprecated option since releases can be built on any swift supported Linux distribution.")
    var useRhelUbi9: Bool = false
#endif

    @Argument(help: "Version of swiftly to build the release.")
    var version: String

    func validate() throws {}

    func run() async throws {
#if os(Linux)
        try await self.buildLinuxRelease()
#elseif os(macOS)
        try await self.buildMacOSRelease(cert: self.cert, identifier: self.identifier)
#else
        #error("Unsupported OS")
#endif
    }

    func assertTool(_ name: String, message: String) async throws -> String {
        guard let _ = try? await runProgramOutput(getShell(), "-c", "which which") else {
            throw Error(message: "The which command could not be found. Please install it with your package manager.")
        }

        guard let location = try? await runProgramOutput(getShell(), "-c", "which \(name)") else {
            throw Error(message: message)
        }

        return location.replacingOccurrences(of: "\n", with: "")
    }

    func findSwiftVersion() throws -> String? {
        var cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        while cwd.path != "" && cwd.path != "/" {
            guard FileManager.default.fileExists(atPath: cwd.path) else {
                break
            }

            let svFile = cwd.appendingPathComponent(".swift-version")

            if FileManager.default.fileExists(atPath: svFile.path) {
                let selector = try? String(contentsOf: svFile, encoding: .utf8)
                if let selector = selector {
                    return selector.replacingOccurrences(of: "\n", with: "")
                }
                return selector
            }

            cwd = cwd.deletingLastPathComponent()
        }

        return nil
    }

    func checkSwiftRequirement() async throws -> String {
        guard !self.skip else {
            return try await self.assertTool("swift", message: "Please install swift and make sure that it is added to your path.")
        }

        guard let requiredSwiftVersion = try? self.findSwiftVersion() else {
            throw Error(message: "Unable to determine the required swift version for this version of swiftly. Please make sure that you `cd <swiftly_git_dir>` and there is a .swift-version file there.")
        }

        let swift = try await self.assertTool("swift", message: "Please install swift \(requiredSwiftVersion) and make sure that it is added to your path.")

        // We also need a swift toolchain with the correct version
        guard case let swiftVersion = try await commandVersion(Swift()), swiftVersion.contains("Swift version \(requiredSwiftVersion)") else {
            throw Error(message: "Swiftly releases require a Swift \(requiredSwiftVersion) toolchain available on the path")
        }

        return swift
    }

    func checkGitRepoStatus() async throws {
        guard !self.skip else {
            return
        }

        guard let gitTags = try await runCommand(Git().log(.maxCount(1), .pretty("format:%d"))), gitTags.contains("tag: \(self.version)") else {
            throw Error(message: "Git repo is not yet tagged for release \(self.version). Please tag this commit with that version and push it to GitHub.")
        }

        do {
            _ = try await runCommand(try await Git().diffIndex(.quiet, treeIsh: "HEAD"))
        } catch {
            throw Error(message: "Git repo has local changes. First commit these changes, tag the commit with release \(self.version) and push the tag to GitHub.")
        }
    }

    func collectLicenses(_ licenseDir: String) async throws {
        try FileManager.default.createDirectory(atPath: licenseDir, withIntermediateDirectories: true)

        let cwd = FileManager.default.currentDirectoryPath

        // Copy the swiftly license to the bundle
        try FileManager.default.copyItem(atPath: cwd + "/LICENSE.txt", toPath: licenseDir + "/LICENSE.txt")
    }

    func buildLinuxRelease() async throws {
        // TODO: turn these into checks that the system meets the criteria for being capable of using the toolchain + checking for packages, not tools
        let curl = try await self.assertTool("curl", message: "Please install curl with `yum install curl`")
        _ = try await self.assertTool("tar", message: "Please install tar with `yum install tar`")
        _ = try await self.assertTool("make", message: "Please install make with `yum install make`")
        _ = try await self.assertTool("git", message: "Please install git with `yum install git`")
        _ = try await self.assertTool("strip", message: "Please install strip with `yum install binutils`")
        _ = try await self.assertTool("sha256sum", message: "Please install sha256sum with `yum install coreutils`")

        _ = try await self.checkSwiftRequirement()

        try await self.checkGitRepoStatus()

        // Start with a fresh SwiftPM package
        _ = try await runCommand(Swift().package().reset())

        // Build a specific version of libarchive with a check on the tarball's SHA256
        let libArchiveVersion = "3.7.4"
        let libArchiveTarSha = "7875d49596286055b52439ed42f044bd8ad426aa4cc5aabd96bfe7abb971d5e8"

        let buildCheckoutsDir = FileManager.default.currentDirectoryPath + "/.build/checkouts"
        let libArchivePath = buildCheckoutsDir + "/libarchive-\(libArchiveVersion)"
        let pkgConfigPath = libArchivePath + "/pkgconfig"

        try? FileManager.default.createDirectory(atPath: buildCheckoutsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: pkgConfigPath, withIntermediateDirectories: true)

        try? FileManager.default.removeItem(atPath: libArchivePath)
        try runProgram(curl, "-o", "\(buildCheckoutsDir + "/libarchive-\(libArchiveVersion).tar.gz")", "--remote-name", "--location", "https://github.com/libarchive/libarchive/releases/download/v\(libArchiveVersion)/libarchive-\(libArchiveVersion).tar.gz")
        let libArchiveTarShaActual = try await runCommand(Sha256sum("\(buildCheckoutsDir)/libarchive-\(libArchiveVersion).tar.gz"))
        guard let libArchiveTarShaActual, libArchiveTarShaActual.starts(with: libArchiveTarSha) else {
            let shaActual = libArchiveTarShaActual ?? "none"
            throw Error(message: "The libarchive tar.gz file sha256sum is \(shaActual), but expected \(libArchiveTarSha)")
        }
        _ = try await runCommand(Tar(.directory(buildCheckoutsDir)).extract(.compressed, .archive("\(buildCheckoutsDir)/libarchive-\(libArchiveVersion).tar.gz")))

        let cwd = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(libArchivePath)

        let swiftVerRegex: Regex<(Substring, Substring)> = try! Regex("Swift version (\\d+\\.\\d+\\.\\d+) ")
        let swiftVerOutput = (try await commandVersion(Swift())) ?? ""
        guard let swiftVerMatch = try swiftVerRegex.firstMatch(in: swiftVerOutput) else {
            throw Error(message: "Unable to detect swift version")
        }

        let swiftVersion = swiftVerMatch.output.1

        let sdkName = "swift-\(swiftVersion)-RELEASE_static-linux-0.0.1"

#if arch(arm64)
        let arch = "aarch64"
#else
        let arch = "x86_64"
#endif

        let swiftReleasesJson = (try await runProgramOutput(curl, "https://www.swift.org/api/v1/install/releases.json")) ?? "[]"
        let swiftReleases = try JSONDecoder().decode([SwiftRelease].self, from: swiftReleasesJson.data(using: .utf8)!)

        guard let swiftRelease = swiftReleases.first(where: { ($0.name ?? "") == swiftVersion }) else {
            throw Error(message: "Unable to find swift release using swift.org API: \(swiftVersion)")
        }

        guard let sdkPlatform = (swiftRelease.platforms ?? [SwiftPlatform]()).first(where: { ($0.name ?? "") == "Static SDK" }) else {
            throw Error(message: "Swift release \(swiftVersion) has no Static SDK offering")
        }

        _ = try await runCommand(Swift().sdk().install("https://download.swift.org/swift-\(swiftVersion)-release/static-sdk/swift-\(swiftVersion)-RELEASE/swift-\(swiftVersion)-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz", checksum: sdkPlatform.checksum ?? "deadbeef"))

        var customEnv = ProcessInfo.processInfo.environment
        customEnv["CC"] = "\(cwd)/Tools/build-swiftly-release/musl-clang"
        customEnv["MUSL_PREFIX"] = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.swiftpm/swift-sdks/\(sdkName).artifactbundle/\(sdkName)/swift-linux-musl/musl-1.2.5.sdk/\(arch)/usr"

        try runProgram(
            "./configure",
            "--prefix=\(pkgConfigPath)",
            "--enable-shared=no",
            "--with-pic",
            "--without-nettle",
            "--without-openssl",
            "--without-lzo2",
            "--without-expat",
            "--without-xml2",
            "--without-bz2lib",
            "--without-libb2",
            "--without-iconv",
            "--without-zstd",
            "--without-lzma",
            "--without-lz4",
            "--disable-acl",
            "--disable-bsdtar",
            "--disable-bsdcat",
            env: customEnv
        )

        try await runCommand(Make(), env: customEnv)

        try await runCommand(Make().install())

        FileManager.default.changeCurrentDirectoryPath(cwd)

        _ = try await runCommand(Swift().build(.swiftSdk("\(arch)-swift-linux-musl"), .product("swiftly"), .pkgConfigPath("\(pkgConfigPath)/lib/pkgconfig"), .staticSwiftStdlib, .configuration("release")))
        _ = try await runCommand(Swift().sdk().remove(sdkName))

        let releaseDir = cwd + "/.build/release"

        // Strip the symbols from the binary to decrease its size
        try await runCommand(Strip(releaseDir + "/swiftly"))

        try await self.collectLicenses(releaseDir)

#if arch(arm64)
        let releaseArchive = "\(releaseDir)/swiftly-\(version)-aarch64.tar.gz"
#else
        let releaseArchive = "\(releaseDir)/swiftly-\(version)-x86_64.tar.gz"
#endif

        _ = try await runCommand(Tar(.directory(releaseDir)).create(.compressed, .archive(releaseArchive), files: "swiftly", "LICENSE.txt"))

        print(releaseArchive)
    }

    func buildMacOSRelease(cert: String?, identifier: String) async throws {
        // Check system requirements
        _ = try await self.assertTool("git", message: "Please install git with either `xcode-select --install` or `brew install git`")

        _ = try await self.checkSwiftRequirement()

        try await self.checkGitRepoStatus()

        _ = try await self.assertTool("lipo", message: "In order to make a universal binary there needs to be the `lipo` tool that is installed on macOS.")
        _ = try await self.assertTool("pkgbuild", message: "In order to make pkg installers there needs to be the `pkgbuild` tool that is installed on macOS.")
        _ = try await self.assertTool("strip", message: "In order to strip binaries there needs to be the `strip` tool that is installed on macOS.")

        _ = try await runCommand(Swift().package().reset())

        for arch in ["x86_64", "arm64"] {
            _ = try await runCommand(Swift().build(.product("swiftly"), .configuration("release"), .arch(arch)))
            try await runCommand(Strip(".build/\(arch)-apple-macosx/release/swiftly"))
        }

        let swiftlyBinDir = FileManager.default.currentDirectoryPath + "/.build/release/usr/local/bin"
        try? FileManager.default.createDirectory(atPath: swiftlyBinDir, withIntermediateDirectories: true)

        try await runCommand(Lipo(".build/x86_64-apple-macosx/release/swiftly", ".build/arm64-apple-macosx/release/swiftly").create(.output("\(swiftlyBinDir)/swiftly")))

        let swiftlyLicenseDir = FileManager.default.currentDirectoryPath + "/.build/release/usr/local/share/doc/swiftly/license"
        try? FileManager.default.createDirectory(atPath: swiftlyLicenseDir, withIntermediateDirectories: true)
        try await self.collectLicenses(swiftlyLicenseDir)

        if let cert {
            try await runCommand(Pkgbuild(.installLocation("/usr/local"), .version(self.version), .identifier(identifier), .sign(cert), root: swiftlyBinDir + "/..", ".build/release/swiftly-\(self.version).pkg"))
        } else {
            try await runCommand(Pkgbuild(.installLocation("/usr/local"), .version(self.version), .identifier(identifier), root: swiftlyBinDir + "/..", ".build/release/swiftly-\(self.version).pkg"))
        }
    }
}
