import ArgumentParser
import SwiftlyCore

struct List: SwiftlyCommand {
    public static var configuration = CommandConfiguration(
        abstract: "List installed toolchains."
    )

    @Argument(help: ArgumentHelp(
        "A filter to use when listing toolchains.",
        discussion: """

        The toolchain selector determines which toolchains to list. If no selector \
        is provided, all installed toolchains will be listed:

            $ swiftly list

        The installed toolchains associated with a given major version can be listed by \
        specifying the major version as the selector: 

            $ swiftly list 5

        Likewise, the installed toolchains associated with a given minor version can be listed \
        by specifying the minor version as the selector:

            $ swiftly list 5.2

        The installed snapshots for a given devlopment branch can be listed by specifying the branch as the selector:

            $ swiftly list main-snapshot
            $ swiftly list 5.7-snapshot
        """
    ))
    var toolchainSelector: String?

    @OptionGroup var root: GlobalOptions

    internal mutating func run() async throws {
        // First, validate the installation of swiftly
        let config = try await validate(root)

        let selector: ToolchainSelector? = try self.toolchainSelector.map( { input in
            try ToolchainSelector(parsing: input)
        })

        let toolchains = config.listInstalledToolchains(selector: selector).sorted { $0 > $1 }
        let defaultToolchain = config.inUse

        let printToolchain = { (toolchain: ToolchainVersion) in
            var message = "\(toolchain)"
            if toolchain == defaultToolchain {
                message += " (default)"
            }
            SwiftlyCore.print(message)
        }

        if let selector {
            let modifier: String
            switch selector {
            case let .stable(major, minor, nil):
                if let minor {
                    modifier = "Swift \(major).\(minor) release"
                } else {
                    modifier = "Swift \(major) release"
                }
            case .snapshot(.main, nil):
                modifier = "main development snapshot"
            case let .snapshot(.release(major, minor), nil):
                modifier = "\(major).\(minor) development snapshot"
            default:
                modifier = "matching"
            }

            let message = "Installed \(modifier) toolchains"
            SwiftlyCore.print(message)
            SwiftlyCore.print(String(repeating: "-", count: message.count))
            for toolchain in toolchains {
                printToolchain(toolchain)
            }
        } else {
            SwiftlyCore.print("Installed release toolchains")
            SwiftlyCore.print("----------------------------")
            for toolchain in toolchains {
                guard toolchain.isStableRelease() else {
                    continue
                }
                printToolchain(toolchain)
            }

            SwiftlyCore.print("")
            SwiftlyCore.print("Installed snapshot toolchains")
            SwiftlyCore.print("-----------------------------")
            for toolchain in toolchains where toolchain.isSnapshot() {
                printToolchain(toolchain)
            }
        }
    }
}
