import Foundation
import SwiftlyCore
import SystemPackage

typealias sys = SwiftlyCore.SystemCommand
typealias fs = SwiftlyCore.FileSystem

public struct SwiftPkgInfo: Codable {
    public var CFBundleIdentifier: String

    public init(CFBundleIdentifier: String) {
        self.CFBundleIdentifier = CFBundleIdentifier
    }
}

/// `Platform` implementation for macOS systems.
public struct MacOS: Platform {
    public init() {}

    public var defaultSwiftlyHomeDir: FilePath {
        fs.home.path / ".swiftly"
    }

    public var defaultToolchainsDirectory: FilePath {
        fs.home.path / "Library/Developer/Toolchains"
    }

    public func swiftlyBinDir(_ ctx: SwiftlyCoreContext) -> InFile {
        InFile(ctx.mockedHomeDir.map { $0 / "bin" }
            ?? ProcessInfo.processInfo.environment["SWIFTLY_BIN_DIR"].map { FilePath($0) }
            ?? fs.home.path / ".swiftly/bin")
    }

    public func swiftlyToolchainsDir(_ ctx: SwiftlyCoreContext) -> InFile {
        InFile(
            ctx.mockedHomeDir.map { $0 / "Toolchains" }
                ?? ProcessInfo.processInfo.environment["SWIFTLY_TOOLCHAINS_DIR"].map { FilePath($0) }
                // This is where the installer will put the toolchains, and where Xcode can find them
                ?? self.defaultToolchainsDirectory
        )
    }

    public var toolchainFileExtension: String {
        "pkg"
    }

    public func verifySwiftlySystemPrerequisites() throws {
        // All system prerequisites are there for swiftly on macOS
    }

    public func verifySystemPrerequisitesForInstall(
        _: SwiftlyCoreContext, platformName _: String, version _: ToolchainVersion,
        requireSignatureValidation _: Bool
    ) async throws -> String? {
        // All system prerequisites should be there for macOS
        nil
    }

    public func install(
        _ ctx: SwiftlyCoreContext, from tmpFile: borrowing InFile, version: ToolchainVersion, verbose: Bool
    ) async throws {
        let toolchainsDir = self.swiftlyToolchainsDir(ctx)

        if toolchainsDir.path == self.defaultToolchainsDirectory {
            // If the toolchains go into the default user location then we use the installer to install them
            await ctx.print("Installing package in user home directory...")
            _ = try runProgram(
                "installer", "-verbose", "-pkg", "\(tmpFile.path)", "-target", "CurrentUserHomeDirectory",
                quiet: !verbose
            )
        } else {
            // Otherwise, we extract the pkg into the requested toolchains directory.
            await ctx.print("Expanding pkg...")
            guard let toolchainDir = try await fs.mkdir(dir: OutFile(toolchainsDir.path / "\(version.identifier).xctoolchain")) else {
                throw SwiftlyError(message: "Unable to create toolchain directory under \(toolchainsDir.path)")
            }

            await ctx.print("Checking package signature...")
            do {
                _ = try runProgram("pkgutil", "--check-signature", "\(tmpFile.path)", quiet: !verbose)
            } catch {
                // If this is not a test that uses mocked toolchains then we must throw this error and abort installation
                guard ctx.mockedHomeDir != nil else {
                    throw error
                }

                // We permit the signature verification to fail during testing
                await ctx.print("Signature verification failed, which is allowable during testing with mocked toolchains")
            }

            let tmpDir = fs.mktemp().path
            guard let tmpDir = try runProgram("pkgutil", "--verbose", "--expand", "\(tmpFile.path)", "\(tmpDir)", quiet: !verbose, creates: tmpDir) else {
                throw SwiftlyError(message: "Temporary directory \(tmpDir) doesn't exist")
            }

            await ctx.print("Untarring package payload...")
            let result = Result { try runProgram("tar", "-C", "\(toolchainDir.path)", "-xvf", "\(tmpDir.path / "\(version.identifier)-osx-package.pkg/Payload")", quiet: !verbose) }
            // There's a slight difference in the location of the special Payload file between official swift packages
            // and the ones that are mocked here in the test framework.
            if case let .failure(e) = result {
                do {
                    _ = try runProgram("tar", "-C", "\(toolchainDir.path)", "-xvf", "\(tmpDir.path / "Payload")", quiet: !verbose)
                } catch {
                    throw e
                }
            }
        }
    }

    public func extractSwiftlyAndInstall(_ ctx: SwiftlyCoreContext, from archive: borrowing InFile) async throws {
        let userHomeDir = ctx.homeDir

        if ctx.mockedHomeDir == nil {
            await ctx.print("Extracting the swiftly package...")
            _ = try runProgram("installer", "-pkg", "\(archive.path)", "-target", "CurrentUserHomeDirectory")
            _ = try? runProgram("pkgutil", "--volume", "\(userHomeDir.path)", "--forget", "org.swift.swiftly")
        } else {
            let installDir = OutFile((userHomeDir / ".swiftly").path)
            guard let installDir = try await fs.mkdir(.parents, dir: installDir) else { fatalError() }

            // In the case of a mock for testing purposes we won't use the installer, perferring a manual process because
            //  the installer will not install to an arbitrary path, only a volume or user home directory.
            let tmpDir = fs.mktemp().path
            guard let tmpDir = try runProgram("pkgutil", "--expand", "\(archive.path)", "\(tmpDir)", creates: tmpDir) else { fatalError() }

            let payload = tmpDir / "Payload"

            await ctx.print("Extracting the swiftly package into \(installDir.path)...")
            _ = try runProgram("tar", "-C", "\(installDir.path)", "-xvf", "\(payload.path)", quiet: false)
        }

        _ = try self.runProgram((userHomeDir / ".swiftly/bin/swiftly").path.string, "init")
    }

    public func uninstall(_ ctx: SwiftlyCoreContext, _ toolchain: ToolchainVersion, verbose: Bool)
        async throws
    {
        await ctx.print("Uninstalling package in user home directory...")

        let toolchainDir = self.swiftlyToolchainsDir(ctx) / "\(toolchain.identifier).xctoolchain"

        let decoder = PropertyListDecoder()
        let infoPlist = toolchainDir / "Info.plist"
        let data = try await fs.cat(file: infoPlist)

        guard let pkgInfo = try? decoder.decode(SwiftPkgInfo.self, from: data) else {
            throw SwiftlyError(message: "could not decode plist at \(infoPlist.path)")
        }

        try await fs.remove(file: toolchainDir)

        _ = try? runProgram(
            "pkgutil", "--volume", "\(fs.home.path)", "--forget", pkgInfo.CFBundleIdentifier, quiet: !verbose
        )
    }

    public func getExecutableName() -> String {
        "swiftly-macos-osx"
    }

    public func verifyToolchainSignature(
        _: SwiftlyCoreContext, toolchainFile _: ToolchainFile, archive _: borrowing InFile, verbose _: Bool
    ) async throws {
        // No signature verification is required on macOS since the pkg files have their own signing
        //  mechanism and the swift.org downloadables are trusted by stock macOS installations.
    }

    public func verifySwiftlySignature(
        _: SwiftlyCoreContext, archiveDownloadURL _: URL, archive _: borrowing InFile, verbose _: Bool
    ) async throws {
        // No signature verification is required on macOS since the pkg files have their own signing
        //  mechanism and the swift.org downloadables are trusted by stock macOS installations.
    }

    public func detectPlatform(
        _: SwiftlyCoreContext, disableConfirmation _: Bool, platform _: String?
    ) async -> PlatformDefinition {
        // No special detection required on macOS platform
        .macOS
    }

    public func getShell() async throws -> String {
        for (_, value) in try await sys.dscl(datasource: ".").read(path: fs.home, keys: "UserShell").properties(self) {
            return value
        }

        // Fall back to zsh on macOS
        return "/bin/zsh"
    }

    public func findToolchainLocation(_ ctx: SwiftlyCoreContext, _ toolchain: ToolchainVersion) -> InFile
    {
        self.swiftlyToolchainsDir(ctx) / "\(toolchain.identifier).xctoolchain"
    }

    public static let currentPlatform: any Platform = MacOS()
}
