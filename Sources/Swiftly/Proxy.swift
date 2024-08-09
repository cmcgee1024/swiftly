import Foundation
import SwiftlyCore

// This is the allowed list of executables that we will proxy
let proxyList = [
    "clang",
    "lldb",
    "lldb-dap",
    "lldb-server",
    "clang++",
    "sourcekit-lsp",
    "clangd",
    "swift",
    "docc",
    "swiftc",
    "lld",
    "llvm-ar",
    "plutil",
    "repl_swift",
    "wasm-ld",
]

@main
public enum Proxy {
    static func main() async throws {
        do {
            let zero = CommandLine.arguments[0]
            guard let binName = zero.components(separatedBy: "/").last else {
                fatalError("Could not determine the binary name for proxying")
            }

            guard proxyList.contains(binName) else {
                // Treat this as a swiftly invocation
                await Swiftly.main()
                return
            }

            var config = try Config.load()
            let proxyArgs = CommandLine.arguments.filter { $0.hasPrefix("+") }.map { String($0.dropFirst(1)) }
            let toolchain: ToolchainVersion

            if proxyArgs.count > 0 {
                guard proxyArgs.count == 1 else {
                    throw Error(message: "More than one toolchain selector specified")
                }

                toolchain = try await findInstalledToolchain(&config, proxyArgs[0])
            } else if let swiftVersion = findSwiftVersionFromFile() {
                toolchain = try await findInstalledToolchain(&config, swiftVersion)
            } else if let inUse = config.inUse {
                toolchain = inUse
            } else {
                throw Error(message: "No swift toolchain could be determined either through a toolchain selector (e.g. +5.7.2, +latest), .swift-version file, or default.")
            }

            try await Swiftly.currentPlatform.proxy(toolchain, binName, CommandLine.arguments[1...].filter { !$0.hasPrefix("+") })
        } catch {
            SwiftlyCore.print("\(error)")
            exit(1)
        }
    }
}

private func findSwiftVersionFromFile() -> String? {
    var cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    while cwd.path != "" && cwd.path != "/" {
        guard FileManager.default.fileExists(atPath: cwd.path) else {
            break
        }

        let svFile = cwd.appendingPathComponent(".swift-version")

        if FileManager.default.fileExists(atPath: svFile.path) {
            do {
                let contents = try String(contentsOf: svFile, encoding: .utf8)
                if !contents.isEmpty {
                    return contents.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
                }
            } catch {}
        }

        cwd = cwd.deletingLastPathComponent()
    }

    return nil
}

private func findInstalledToolchain(_ config: inout Config, _ selection: String) async throws -> ToolchainVersion {
    let selector = try ToolchainSelector(parsing: selection)

    if let matched = config.listInstalledToolchains(selector: selector).max() {
        return matched
    } else {
        let toolchainVersion = try await Install.resolve(selector: selector)

        let postInstallScript = try await Install.execute(
            version: toolchainVersion,
            &config,
            useInstalledToolchain: config.inUse == nil,
            verifySignature: true // TODO: consider making this a proxy parameter
        )

        if let postInstallScript = postInstallScript {
            throw Error(message: """

            There are some system dependencies that should be installed before using this toolchain.
            You can run the following script as the system administrator (e.g. root) to prepare
            your system and try again:

            \(postInstallScript)
            """)
        }

        let config = try Config.load()

        guard let matched = config.listInstalledToolchains(selector: selector).max() else {
            throw Error(message: "Toolchain was not installed: \(selector)")
        }

        return matched
    }
}
