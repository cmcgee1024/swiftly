// Directory Service command line utility for macOS
public struct Dscl {
    var programPath: String?

    var datasource: String?

    public init(
        programPath: String? = nil,
        datasource: String? = nil
    ) {
        self.programPath = programPath
        self.datasource = datasource
    }

    public func args() -> [String] {
        var args = [self.programPath ?? "dscl"]
        if let datasource = self.datasource {
            args += [datasource]
        }
        return args
    }

    public func read(path: String? = nil, keys: String...) -> ReadCommand {
        ReadCommand(dscl: self, path: path, keys: keys)
    }

    public struct ReadCommand {
        var dscl: Dscl
        var path: String?
        var keys: [String]

        internal init(dscl: Dscl, path: String?, keys: [String]) {
            self.dscl = dscl
            self.path = path
            self.keys = keys
        }

        public func args() -> [String] {
            var args = self.dscl.args() + ["-read"]
            if let path = self.path {
                args += [path] + self.keys
            }
            return args
        }

        public func run(env: [String: String]? = nil) async throws -> String? {
            let args = self.args()
            guard let program = args.first else {
                throw CommandLineError.invalidArgs
            }
            return try await runProgramOutput(program, [String](args[1...]), env: env)
        }
    }
}

extension Dscl.ReadCommand {
    public func properties(env: [String: String]? = nil) async throws -> [(key: String, value: String)] {
        let output = try await self.run(env: env)
        guard let output else { return [] }

        var props: [(key: String, value: String)] = []
        for line in output.components(separatedBy: "\n") {
            if case let comps = line.components(separatedBy: ": "), comps.count == 2 {
                props.append((key: comps[0], value: comps[1]))
            }
        }
        return props
    }
}

public struct Lipo {
    var programPath: String?

    var inputFiles: [String]

    public init(programPath: String? = nil, _ inputFiles: String...) {
        self.programPath = programPath
        self.inputFiles = inputFiles
    }

    public func args() -> [String] {
        [self.programPath ?? "lipo"] + self.inputFiles
    }

    public func create(_ options: CreateCommand.Option...) -> CreateCommand {
        CreateCommand(self, options)
    }

    public struct CreateCommand {
        var lipo: Lipo

        var options: [Option]

        init(_ lipo: Lipo, _ options: [Option]) {
            self.lipo = lipo
            self.options = options
        }

        public enum Option {
            case output(String)

            func args() -> [String] {
                switch self {
                case let .output(output):
                    return ["-output", output]
                }
            }
        }

        public func args() -> [String] {
            var args = self.lipo.args()
            for opt in self.options {
                args += opt.args()
            }
            return args
        }

        public func run(env: [String: String]? = nil) throws {
            try runProgram(self.args(), env: env)
        }
    }
}

public struct Pkgbuild {
    var programPath: String?

    var options: [Option]

    var root: String
    var packageOutputPath: String

    public init(programPath: String? = nil, _ options: Option..., root: String, _ packageOutputPath: String) {
        self.programPath = programPath
        self.options = options
        self.root = root
        self.packageOutputPath = packageOutputPath
    }

    public enum Option {
        case installLocation(String)
        case version(String)
        case identifier(String)
        case sign(String)

        func args() -> [String] {
            switch self {
            case let .installLocation(installLocation):
                return ["--install-location", installLocation]
            case let .version(version):
                return ["--version", version]
            case let .identifier(identifier):
                return ["--identifier", identifier]
            case let .sign(identityName):
                return ["--sign", identityName]
            }
        }
    }

    public func args() -> [String] {
        var args = [self.programPath ?? "pkgbuild"]
        for opt in self.options {
            args += opt.args()
        }
        args += ["--root", self.root]
        args += [self.packageOutputPath]
        return args
    }

    public func run(env: [String: String]? = nil) throws {
        try runProgram(self.args(), env: env)
    }
}

public struct Getent {
    var programPath: String?

    var database: String

    var keys: [String]

    public init(
        programPath: String? = nil,
        database: String,
        keys: String...
    ) {
        self.programPath = programPath
        self.database = database
        self.keys = keys
    }

    public func args() -> [String] {
        var args: [String] = [self.programPath ?? "getent"]
        args.append(self.database)
        args += self.keys
        return args
    }

    public func run(env: [String: String]? = nil) async throws -> String? {
        let args = self.args()
        guard let program = args.first else {
            throw CommandLineError.invalidArgs
        }
        return try await runProgramOutput(program, [String](args[1...]), env: env)
    }

    public func entries() async throws -> [[String]] {
        let output = try await self.run()
        guard let output else { return [] }

        var entries: [[String]] = []
        for line in output.components(separatedBy: "\n") {
            entries.append(line.components(separatedBy: ":"))
        }
        return entries
    }
}

public struct Git {
    var programPath: String?

    public init(programPath: String? = nil) {
        self.programPath = programPath
    }

    public func args() -> [String] {
        var args: [String] = [self.programPath ?? "git"]
        return args
    }

    public func log(_ options: LogCommand.Option...) -> LogCommand {
        LogCommand(self, options)
    }

    public func diffIndex(_ options: DiffIndexCommand.Option..., treeIsh: String?) -> DiffIndexCommand {
        DiffIndexCommand(self, options, treeIsh: treeIsh)
    }

    public struct LogCommand {
        var git: Git
        var options: [Option]

        init(_ git: Git, _ options: [Option]) {
            self.git = git
            self.options = options
        }

        public enum Option {
            case maxCount(Int)
            case pretty(String)

            func args() -> [String] {
                switch self {
                case let .maxCount(num):
                    return ["--max-count=\(num)"]
                case let .pretty(format):
                    return ["--pretty=\(format)"]
                }
            }
        }

        public func args() -> [String] {
            var args: [String] = self.git.args()
            for opt in self.options {
                args += opt.args()
            }
            return args
        }

        public func run(env: [String: String]? = nil) async throws -> String? {
            let args = self.args()
            guard let program = args.first else {
                throw CommandLineError.invalidArgs
            }
            return try await runProgramOutput(program, [String](args[1...]), env: env)
        }
    }

    public struct DiffIndexCommand {
        var git: Git
        var options: [Option]
        var treeIsh: String?

        init(_ git: Git, _ options: [Option], treeIsh: String?) {
            self.git = git
            self.options = options
            self.treeIsh = treeIsh
        }

        public enum Option {
            case quiet

            func args() -> [String] {
                switch self {
                case .quiet:
                    return ["--quiet"]
                }
            }
        }

        public func args() -> [String] {
            var args: [String] = self.git.args()
            for opt in self.options {
                args += opt.args()
            }
            if let treeIsh = self.treeIsh {
                args += [treeIsh]
            }
            return args
        }

        public func run(env: [String: String]? = nil) async throws -> String? {
            let args = self.args()
            guard let program = args.first else {
                throw CommandLineError.invalidArgs
            }
            return try await runProgramOutput(program, [String](args[1...]), env: env)
        }
    }
}

public struct Tar {
    var programPath: String?

    var options: [Option]

    public init(programPath: String? = nil, _ options: Option...) {
        self.programPath = programPath

        self.options = options
    }

    public enum Option {
        case directory(String)

        public func args() -> [String] {
            switch self {
            case let .directory(directory):
                return ["-C", directory] // This is the only portable form between macOS and GNU
            }
        }
    }

    public func args() -> [String] {
        var args = [self.programPath ?? "tar"]
        for opt in self.options {
            args += opt.args()
        }

        return args
    }

    public func create(_ options: CreateCommand.Option..., files: String...) -> CreateCommand {
        CreateCommand(self, options, files: files)
    }

    public struct CreateCommand {
        var tar: Tar

        var options: [Option]

        var files: [String]?

        init(_ tar: Tar, _ options: [Option], files: [String]?) {
            self.tar = tar
            self.options = options
            self.files = files
        }

        public enum Option {
            case archive(String)
            case compressed

            func args() -> [String] {
                switch self {
                case let .archive(archive):
                    return ["--file", archive]
                case .compressed:
                    return ["-z"]
                }
            }
        }

        public func args() -> [String] {
            var args = self.tar.args()

            for opt in self.options {
                args += opt.args()
            }

            if let files = self.files {
                args += files
            }

            return args
        }

        public func run(env: [String: String]? = nil) async throws -> String? {
            let args = self.args()
            guard let program = args.first else {
                throw CommandLineError.invalidArgs
            }
            return try await runProgramOutput(program, [String](args[1...]), env: env)
        }
    }

    public func extract(_ options: ExtractCommand.Option...) -> ExtractCommand {
        ExtractCommand(self, options)
    }

    public struct ExtractCommand {
        var tar: Tar

        var options: [Option]

        init(_ tar: Tar, _ options: [Option]) {
            self.tar = tar
            self.options = options
        }

        public enum Option {
            case archive(String)
            case compressed

            public func args() -> [String] {
                switch self {
                case let .archive(archive):
                    return ["--file", archive]
                case .compressed:
                    return ["-z"]
                }
            }
        }

        public func args() -> [String] {
            var args = self.tar.args()

            for opt in self.options {
                args += opt.args()
            }

            return args
        }

        public func run(quiet: Bool = false, env: [String: String]? = nil) throws {
            try runProgram(self.args(), quiet: quiet, env: env)
        }
    }
}

public struct Swift {
    var programPath: String?

    public init(programPath: String? = nil) {
        self.programPath = programPath
    }

    public func version(env: [String: String]? = nil) async throws -> String {
        do {
            guard let version = try? await runProgramOutput(self.programPath ?? "swift", "--version", env: env) else {
                throw CommandLineError.unknownVersion
            }
            return version
        } catch {
            throw CommandLineError.unknownVersion
        }
    }

    public func args() -> [String] {
        var args: [String] = [self.programPath ?? "swift"]
        return args
    }

    public func package() -> PackageCommand {
        PackageCommand(self)
    }

    public struct PackageCommand {
        var swift: Swift

        init(_ swift: Swift) {
            self.swift = swift
        }

        public func args() -> [String] {
            self.swift.args() + ["package"]
        }

        public func reset() -> ResetCommand {
            ResetCommand(self)
        }

        public struct ResetCommand {
            var packageCommand: PackageCommand

            init(_ packageCommand: PackageCommand) {
                self.packageCommand = packageCommand
            }

            public func args() -> [String] {
                self.packageCommand.args() + ["reset"]
            }

            public func run(env: [String: String]? = nil) async throws -> String? {
                let args = self.args()
                guard let program = args.first else {
                    throw CommandLineError.invalidArgs
                }
                return try await runProgramOutput(program, [String](args[1...]), env: env)
            }
        }
    }

    public func sdk() -> SdkCommand {
        SdkCommand(self)
    }

    public struct SdkCommand {
        var swift: Swift

        init(_ swift: Swift) {
            self.swift = swift
        }

        public func args() -> [String] {
            self.swift.args() + ["sdk"]
        }

        public func install(_ bundlePathOrUrl: String, checksum: String? = nil) -> InstallCommand {
            InstallCommand(self, bundlePathOrUrl, checksum: checksum)
        }

        public struct InstallCommand {
            var sdkCommand: SdkCommand
            var bundlePathOrUrl: String
            var checksum: String?

            init(_ sdkCommand: SdkCommand, _ bundlePathOrUrl: String, checksum: String?) {
                self.sdkCommand = sdkCommand
                self.bundlePathOrUrl = bundlePathOrUrl
                self.checksum = checksum
            }

            public func args() -> [String] {
                var args = self.sdkCommand.args() + ["install"] + [self.bundlePathOrUrl]
                if let checksum = self.checksum {
                    args += ["--checksum=\(checksum)"]
                }
                return args
            }

            public func run(env: [String: String]? = nil) async throws -> String? {
                let args = self.args()
                guard let program = args.first else {
                    throw CommandLineError.invalidArgs
                }
                return try await runProgramOutput(program, [String](args[1...]), env: env)
            }
        }

        public func remove(_ sdkName: String) -> RemoveCommand {
            RemoveCommand(self, sdkName)
        }

        public struct RemoveCommand {
            var sdkCommand: SdkCommand
            var sdkIdOrBundleName: String

            init(_ sdkCommand: SdkCommand, _ sdkIdOrBundleName: String) {
                self.sdkCommand = sdkCommand
                self.sdkIdOrBundleName = sdkIdOrBundleName
            }

            public func args() -> [String] {
                var args = self.sdkCommand.args() + ["remove"] + [self.sdkIdOrBundleName]
                return args
            }

            public func run(env: [String: String]? = nil) async throws -> String? {
                let args = self.args()
                guard let program = args.first else {
                    throw CommandLineError.invalidArgs
                }
                return try await runProgramOutput(program, [String](args[1...]), env: env)
            }
        }
    }

    public func build(_ options: BuildCommand.Option...) -> BuildCommand {
        BuildCommand(self, options)
    }

    public struct BuildCommand {
        var swift: Swift
        var options: [Option]

        init(_ swift: Swift, _ options: [Option]) {
            self.swift = swift
            self.options = options
        }

        public func args() -> [String] {
            var args = self.swift.args() + ["build"]
            for opt in self.options {
                args += opt.args()
            }
            return args
        }

        public enum Option {
            case arch(String)
            case configuration(String)
            case pkgConfigPath(String)
            case product(String)
            case swiftSdk(String)
            case staticSwiftStdlib

            public func args() -> [String] {
                switch self {
                case let .arch(arch):
                    return ["--arch=\(arch)"]
                case let .configuration(configuration):
                    return ["--configuration=\(configuration)"]
                case let .pkgConfigPath(pkgConfigPath):
                    return ["--pkg-config-path=\(pkgConfigPath)"]
                case let .swiftSdk(sdk):
                    return ["--swift-sdk=\(sdk)"]
                case .staticSwiftStdlib:
                    return ["--static-swift-stdlib"]
                case let .product(product):
                    return ["--product=\(product)"]
                }
            }
        }

        public func run(env: [String: String]? = nil) async throws -> String? {
            let args = self.args()
            guard let program = args.first else {
                throw CommandLineError.invalidArgs
            }
            return try await runProgramOutput(program, [String](args[1...]), env: env)
        }
    }
}

public struct Make {
    var programPath: String?

    public init(programPath: String? = nil) {
        self.programPath = programPath
    }

    public func install() -> InstallCommand {
        InstallCommand(self)
    }

    public struct InstallCommand {
        var make: Make

        init(_ make: Make) {
            self.make = make
        }

        public func args() -> [String] {
            self.make.args() + ["install"]
        }

        public func run(env: [String: String]? = nil) throws {
            try runProgram(self.args(), env: env)
        }
    }

    public func args() -> [String] {
        var args = [self.programPath ?? "make"]
        return args
    }

    public func run(env: [String: String]? = nil) throws {
        try runProgram(self.args(), env: env)
    }
}

public struct Strip {
    var programPath: String?

    var names: [String]

    public init(programPath: String? = nil, _ names: String...) {
        self.programPath = programPath
        self.names = names
    }

    public func args() -> [String] {
        [self.programPath ?? "strip"] + self.names
    }

    public func run(env: [String: String]? = nil) throws {
        try runProgram(self.args(), env: env)
    }
}

public struct Sha256sum {
    var programPath: String?

    var files: [String]

    public init(programPath: String? = nil, _ files: String...) {
        self.programPath = programPath
        self.files = files
    }

    public func args() -> [String] {
        [self.programPath ?? "strip"] + self.files
    }

    public func run(env: [String: String]? = nil) async throws -> String? {
        let args = self.args()
        guard let program = args.first else {
            throw CommandLineError.invalidArgs
        }

        return try await runProgramOutput(program, [String](args[1...]), env: env)
    }
}

public struct Pkgutil {
    var programPath: String?

    var options: [Option]

    public enum Option {
        case verbose
        case volume(String)

        public func args() -> [String] {
            switch self {
            case .verbose:
                return ["--verbose"]
            case let .volume(volume):
                return ["--volume", volume]
            }
        }
    }

    public init(programPath: String? = nil, _ options: Option...) {
        self.programPath = programPath
        self.options = options
    }

    public func args() -> [String] {
        var args = [self.programPath ?? "pkgutil"]
        for opt in self.options {
            args += opt.args()
        }
        return args
    }

    public func expand(pkgPath: String, dirPath: String) -> ExpandCommand {
        ExpandCommand(self, pkgPath: pkgPath, dirPath: dirPath)
    }

    public struct ExpandCommand {
        var pkgutil: Pkgutil
        var pkgPath: String
        var dirPath: String

        init(_ pkgutil: Pkgutil, pkgPath: String, dirPath: String) {
            self.pkgutil = pkgutil
            self.pkgPath = pkgPath
            self.dirPath = dirPath
        }

        public func args() -> [String] {
            var args = self.pkgutil.args()
            args += ["--expand"] + [self.pkgPath, self.dirPath]
            return args
        }

        public func run(quiet: Bool = false, env: [String: String]? = nil) throws {
            try runProgram(self.args(), quiet: quiet, env: env)
        }
    }

    public func forget(packageId: String) -> ForgetCommand {
        ForgetCommand(self, packageId: packageId)
    }

    public struct ForgetCommand {
        var pkgutil: Pkgutil
        var packageId: String

        init(_ pkgutil: Pkgutil, packageId: String) {
            self.pkgutil = pkgutil
            self.packageId = packageId
        }

        public func args() -> [String] {
            var args = self.pkgutil.args()
            args += ["--forget", self.packageId]
            return args
        }

        public func run(quiet: Bool = false, env: [String: String]? = nil) throws {
            try runProgram(self.args(), quiet: quiet, env: env)
        }
    }
}

public struct Installer {
    var programPath: String?

    var verbose: Bool

    var pkg: String
    var target: String

    public init(programPath: String? = nil, verbose: Bool = false, pkg: String, target: String) {
        self.programPath = programPath
        self.verbose = verbose
        self.pkg = pkg
        self.target = target
    }

    public func args() -> [String] {
        var args = [self.programPath ?? "installer"]
        if self.verbose {
            args += ["-verbose"]
        }
        args += ["-pkg", self.pkg]
        args += ["-target", self.target]
        return args
    }

    public func run(quiet: Bool = false, env: [String: String]? = nil) throws {
        try runProgram(self.args(), quiet: quiet, env: env)
    }
}

public struct Gpg {
    var programPath: String?

    public init(programPath: String? = nil) {
        self.programPath = programPath
    }

    public func version() async throws -> String? {
        try await runProgramOutput(self.programPath ?? "gpg", "--version")
    }

    public func args() -> [String] {
        [self.programPath ?? "gpg"]
    }

    public func _import(files: String...) -> ImportCommand {
        ImportCommand(self, files: files)
    }

    public struct ImportCommand {
        var gpg: Gpg
        var files: [String]

        init(_ gpg: Gpg, files: [String]) {
            self.gpg = gpg
            self.files = files
        }

        public func args() -> [String] {
            var args = self.gpg.args()
            args += ["--import"]
            args += self.files
            return args
        }

        public func run(quiet: Bool = false, env: [String: String]? = nil) throws {
            try runProgram(self.args(), quiet: quiet, env: env)
        }
    }

    public func verify(files: String...) -> VerifyCommand {
        VerifyCommand(self, files: files)
    }

    public struct VerifyCommand {
        var gpg: Gpg
        var files: [String]

        init(_ gpg: Gpg, files: [String]) {
            self.gpg = gpg
            self.files = files
        }

        public func args() -> [String] {
            var args = self.gpg.args()
            args += ["--verify"]
            args += self.files
            return args
        }

        public func run(quiet: Bool = false, env: [String: String]? = nil) throws {
            try runProgram(self.args(), quiet: quiet, env: env)
        }
    }
}
