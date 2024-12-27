import ArgumentParser
import Foundation

// These functions are cloned and adapted from SwiftlyCore until we can do better bootstrapping
public struct Error: LocalizedError {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { self.message }
}

public func runProgramEnv(_ args: String..., quiet: Bool = false, env: [String: String]?) throws {
    print("\(args.joined(separator: " "))")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args

    if let env = env {
        process.environment = env
    }

    if quiet {
        process.standardOutput = nil
        process.standardError = nil
    }

    try process.run()
    // Attach this process to our process group so that Ctrl-C and other signals work
    let pgid = tcgetpgrp(STDOUT_FILENO)
    if pgid != -1 {
        tcsetpgrp(STDOUT_FILENO, process.processIdentifier)
    }
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw Error(message: "\(args.first!) exited with non-zero status: \(process.terminationStatus)")
    }
}

public func runProgram(_ args: String..., quiet: Bool = false) throws {
    print("\(args.joined(separator: " "))")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args

    if quiet {
        process.standardOutput = nil
        process.standardError = nil
    }

    try process.run()
    // Attach this process to our process group so that Ctrl-C and other signals work
    let pgid = tcgetpgrp(STDOUT_FILENO)
    if pgid != -1 {
        tcsetpgrp(STDOUT_FILENO, process.processIdentifier)
    }
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw Error(message: "\(args.first!) exited with non-zero status: \(process.terminationStatus)")
    }
}

public func runProgramOutput(_ program: String, _ args: String...) async throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [program] + args

    let outPipe = Pipe()
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardOutput = outPipe

    try process.run()
    // Attach this process to our process group so that Ctrl-C and other signals work
    let pgid = tcgetpgrp(STDOUT_FILENO)
    if pgid != -1 {
        tcsetpgrp(STDOUT_FILENO, process.processIdentifier)
    }
    let outData = try outPipe.fileHandleForReading.readToEnd()

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw Error(message: "\(args.first!) exited with non-zero status: \(process.terminationStatus)")
    }

    if let outData = outData {
        return String(data: outData, encoding: .utf8)
    } else {
        return nil
    }
}

#if os(macOS)
public func getShell() async throws -> String {
    if let directoryInfo = try await runProgramOutput("dscl", ".", "-read", FileManager.default.homeDirectoryForCurrentUser.path) {
        for line in directoryInfo.components(separatedBy: "\n") {
            if line.hasPrefix("UserShell: ") {
                if case let comps = line.components(separatedBy: ": "), comps.count == 2 {
                    return comps[1]
                }
            }
        }
    }

    // Fall back to zsh on macOS
    return "/bin/zsh"
}

#elseif os(Linux)
public func getShell() async throws -> String {
    if let passwds = try await runProgramOutput("getent", "passwd") {
        for line in passwds.components(separatedBy: "\n") {
            if line.hasPrefix("root:") {
                if case let comps = line.components(separatedBy: ":"), comps.count > 1 {
                    return comps[comps.count - 1]
                }
            }
        }
    }

    // Fall back on bash on Linux and other Unixes
    return "/bin/bash"
}
#endif

public func isSupportedLinux(useRhelUbi9: Bool) -> Bool {
    return true
}

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
    @Flag(name: .long, help: "Use RHEL UBI9 as the supported Linux to build a release instead of Amazon Linux 2")
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
        guard let swiftVersion = try await runProgramOutput(swift, "--version"), swiftVersion.contains("Swift version \(requiredSwiftVersion)") else {
            throw Error(message: "Swiftly releases require a Swift \(requiredSwiftVersion) toolchain available on the path")
        }

        return swift
    }

    func checkGitRepoStatus(_ git: String) async throws {
        guard !self.skip else {
            return
        }

        guard let gitTags = try await runProgramOutput(git, "log", "-n1", "--pretty=format:%d"), gitTags.contains("tag: \(self.version)") else {
            throw Error(message: "Git repo is not yet tagged for release \(self.version). Please tag this commit with that version and push it to GitHub.")
        }

        do {
            try runProgram(git, "diff-index", "--quiet", "HEAD")
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
#if os(Linux)
        // Check system requirements
        guard isSupportedLinux(useRhelUbi9: self.useRhelUbi9) else {
            throw Error(message: "Linux releases must be made from specific distributions so that the binary can be used everyone else because it has the oldest version of glibc for maximum compatibility with other versions of Linux. Please try again with \(!self.useRhelUbi9 ? "Amazon Linux 2" : "RedHat UBI 9").")
        }
#endif

        // TODO: turn these into checks that the system meets the criteria for being capable of using the toolchain + checking for packages, not tools
        let curl = try await self.assertTool("curl", message: "Please install curl with `yum install curl`")
        let tar = try await self.assertTool("tar", message: "Please install tar with `yum install tar`")
        let make = try await self.assertTool("make", message: "Please install make with `yum install make`")
        let git = try await self.assertTool("git", message: "Please install git with `yum install git`")
        let strip = try await self.assertTool("strip", message: "Please install strip with `yum install binutils`")
        let sha256sum = try await self.assertTool("sha256sum", message: "Please install sha256sum with `yum install coreutils`")

        let swift = try await self.checkSwiftRequirement()

        try await self.checkGitRepoStatus(git)

        // Start with a fresh SwiftPM package
        try runProgram(swift, "package", "reset")

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
        let libArchiveTarShaActual = try await runProgramOutput(sha256sum, "\(buildCheckoutsDir)/libarchive-\(libArchiveVersion).tar.gz")
        guard let libArchiveTarShaActual, libArchiveTarShaActual.starts(with: libArchiveTarSha) else {
            let shaActual = libArchiveTarShaActual ?? "none"
            throw Error(message: "The libarchive tar.gz file sha256sum is \(shaActual), but expected \(libArchiveTarSha)")
        }
        try runProgram(tar, "--directory=\(buildCheckoutsDir)", "-xzf", "\(buildCheckoutsDir)/libarchive-\(libArchiveVersion).tar.gz")

        let cwd = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(libArchivePath)

        let sdkName = "swift-6.0.3-RELEASE_static-linux-0.0.1"

        // FIXME: Adjust the URL and checksum to match the toolchain that is being used

#if arch(arm64)
        let arch = "aarch64"
#else
        let arch = "x86_64"
#endif

        try runProgram(swift, "sdk", "install", "https://download.swift.org/swift-6.0.3-release/static-sdk/swift-6.0.3-RELEASE/swift-6.0.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz", "--checksum", "67f765e0030e661a7450f7e4877cfe008db4f57f177d5a08a6e26fd661cdd0bd")

        var customEnv = ProcessInfo.processInfo.environment
        customEnv["CC"] = "\(cwd)/Tools/build-swiftly-release/musl-clang"
        customEnv["MUSL_PREFIX"] = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.swiftpm/swift-sdks/\(sdkName).artifactbundle/\(sdkName)/swift-linux-musl/musl-1.2.5.sdk/\(arch)/usr"

        try runProgramEnv(
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

        try runProgramEnv(make, env: customEnv)

        try runProgram(make, "install")

        FileManager.default.changeCurrentDirectoryPath(cwd)

        // FIXME: running this twice fixes certain linker errors
        try? runProgram(swift, "build", "--swift-sdk", sdkName, "--product=swiftly", "--pkg-config-path=\(pkgConfigPath)/lib/pkgconfig", "--static-swift-stdlib", "--configuration=release")
        try runProgram(swift, "build", "--swift-sdk", sdkName, "--product=swiftly", "--pkg-config-path=\(pkgConfigPath)/lib/pkgconfig", "--static-swift-stdlib", "--configuration=release")
        try runProgram(swift, "sdk", "remove", sdkName)

        let releaseDir = cwd + "/.build/release"

        // Strip the symbols from the binary to decrease its size
        try runProgram(strip, releaseDir + "/swiftly")

        try await self.collectLicenses(releaseDir)

#if arch(arm64)
        let releaseArchive = "\(releaseDir)/swiftly-\(version)-aarch64.tar.gz"
#else
        let releaseArchive = "\(releaseDir)/swiftly-\(version)-x86_64.tar.gz"
#endif

        try runProgram(tar, "--directory=\(releaseDir)", "-czf", releaseArchive, "swiftly", "LICENSE.txt")

        print(releaseArchive)
    }

    func buildMacOSRelease(cert: String?, identifier: String) async throws {
        // Check system requirements
        let git = try await self.assertTool("git", message: "Please install git with either `xcode-select --install` or `brew install git`")

        let swift = try await checkSwiftRequirement()

        try await self.checkGitRepoStatus(git)

        let lipo = try await self.assertTool("lipo", message: "In order to make a universal binary there needs to be the `lipo` tool that is installed on macOS.")
        let pkgbuild = try await self.assertTool("pkgbuild", message: "In order to make pkg installers there needs to be the `pkgbuild` tool that is installed on macOS.")
        let strip = try await self.assertTool("strip", message: "In order to strip binaries there needs to be the `strip` tool that is installed on macOS.")

        try runProgram(swift, "package", "clean")

        for arch in ["x86_64", "arm64"] {
            try runProgram(swift, "build", "--product=swiftly", "--configuration=release", "--arch=\(arch)")
            try runProgram(strip, ".build/\(arch)-apple-macosx/release/swiftly")
        }

        let swiftlyBinDir = FileManager.default.currentDirectoryPath + "/.build/release/usr/local/bin"
        try? FileManager.default.createDirectory(atPath: swiftlyBinDir, withIntermediateDirectories: true)

        try runProgram(lipo, ".build/x86_64-apple-macosx/release/swiftly", ".build/arm64-apple-macosx/release/swiftly", "-create", "-o", "\(swiftlyBinDir)/swiftly")

        let swiftlyLicenseDir = FileManager.default.currentDirectoryPath + "/.build/release/usr/local/share/doc/swiftly/license"
        try? FileManager.default.createDirectory(atPath: swiftlyLicenseDir, withIntermediateDirectories: true)
        try await self.collectLicenses(swiftlyLicenseDir)

        if let cert {
            try runProgram(
                pkgbuild,
                "--root",
                swiftlyBinDir + "/..",
                "--install-location",
                "usr/local",
                "--version",
                self.version,
                "--identifier",
                identifier,
                "--sign",
                cert,
                ".build/release/swiftly-\(self.version).pkg"
            )
        } else {
            try runProgram(
                pkgbuild,
                "--root",
                swiftlyBinDir + "/..",
                "--install-location",
                "usr/local",
                "--version",
                self.version,
                "--identifier",
                identifier,
                ".build/release/swiftly-\(self.version).pkg"
            )
        }
    }
}
