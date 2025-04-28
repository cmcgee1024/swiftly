import Foundation
import SystemPackage

typealias fs = FileSystem

// Represents an output file to be created
public struct OutFile: ~Copyable {
    private let p: FilePath

    public var path: FilePath { borrowing get { self.p } }

    public init(_ path: FilePath) {
        self.p = path
    }

    public static func / (left: borrowing OutFile, right: String) -> OutFile {
        OutFile(left.p / right)
    }
}

// Represents a file that will be used as input
public struct InFile: ~Copyable {
    private let p: FilePath

    public var path: FilePath { borrowing get { self.p } }

    public init(_ path: FilePath) {
        self.p = path
    }

    public static func / (left: borrowing InFile, right: String) -> InFile {
        InFile(left.p / right)
    }
}

public struct InFileError: Error {
    private var path: FilePath
    public var error: Error

    public init(file: consuming InFile, error: Error) {
        self.path = file.path
        self.error = error
    }

    public var file: InFile {
        InFile(self.path)
    }
}

public struct OutFileError: Error {
    private var path: FilePath
    public var error: Error

    public init(file: consuming OutFile, error: Error) {
        self.path = file.path
        self.error = error
    }

    public var file: OutFile {
        OutFile(self.path)
    }
}

public enum FileSystem {
    public static var cwd: InFile {
        InFile(FileManager.default.currentDir)
    }

    public static var home: InFile {
        InFile(FileManager.default.homeDir)
    }

    public static var tmp: InFile {
        InFile(FileManager.default.temporaryDir)
    }

    public static func exists(atPath path: FilePath) async throws -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    // TODO: figure out if we can remove this, or otherwise make it a more rare operation
    public static func exists2(file: consuming OutFile) async throws -> InFile? {
        let path = file.path

        guard FileManager.default.fileExists(atPath: path) else {
            throw SwiftlyError(message: "File \(path) doesn't exist")
        }

        return InFile(path)
    }

    public static func remove(file: consuming InFile) async throws -> OutFile? {
        do {
            try FileManager.default.removeItem(atPath: file.path)
            return OutFile(file.path)
        } catch {
            throw InFileError(file: file, error: error)
        }
    }

    public static func move(file: consuming InFile, to: consuming OutFile) async throws -> InFile? {
        let destPath = to.path

        do {
            try FileManager.default.moveItem(atPath: file.path, toPath: destPath)
        } catch {
            throw OutFileError(file: OutFile(destPath), error: error)
        }

        return InFile(destPath)
    }

    public static func copy(file: borrowing InFile, to: consuming OutFile) async throws -> InFile? {
        let destPath = to.path

        do {
            try FileManager.default.copyItem(atPath: file.path, toPath: destPath)
        } catch {
            throw OutFileError(file: OutFile(destPath), error: error)
        }

        return InFile(destPath)
    }

    public enum MkdirOptions {
        case parents
    }

    public static func mkdir(_ options: MkdirOptions..., dir: consuming OutFile) async throws -> InFile? {
        try await Self.mkdir(options, dir: dir)
    }

    public static func mkdir(_ options: [MkdirOptions] = [], dir: consuming OutFile) async throws -> InFile? {
        let path = dir.path
        do {
            try FileManager.default.createDir(atPath: path, withIntermediateDirectories: options.contains(.parents))
        } catch {
            throw OutFileError(file: OutFile(path), error: error)
        }
        return InFile(path)
    }

    public static func cat(file: borrowing InFile) async throws -> Data {
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw SwiftlyError(message: "File at path \(file.path) could not be read")
        }

        return data
    }

    public static func mktemp(ext: String? = nil) -> OutFile {
        OutFile(FileManager.default.temporaryDir.appending("swiftly-\(UUID())\(ext ?? "")"))
    }

    public enum CreateOptions {
        case mode(Int)
    }

    public static func create(_ options: CreateOptions..., file: consuming OutFile, contents: Data?) async throws -> InFile? {
        try await Self.create(options, file: file, contents: contents)
    }

    public static func create(_ options: [CreateOptions] = [], file: consuming OutFile, contents: Data?) async throws -> InFile? {
        let path = file.path

        let attributes = options.reduce(into: [FileAttributeKey: Any]()) {
            switch $1 {
            case let .mode(m):
                $0[FileAttributeKey.posixPermissions] = m
            }
        }

        if !FileManager.default.createFile(atPath: path.string, contents: contents, attributes: attributes) {
            throw OutFileError(file: OutFile(path), error: SwiftlyError(message: "Unable to create file \(path)"))
        }

        return InFile(path)
    }

    public static func ls(file: borrowing InFile) async throws -> [String] {
        try FileManager.default.contentsOfDir(atPath: file.path)
    }

    public static func readlink(file: borrowing InFile) async throws -> FilePath {
        try FileManager.default.destinationOfSymbolicLink(atPath: file.path)
    }

    public static func symlink(atPath: consuming OutFile, linkPath: FilePath) async throws -> InFile? {
        let path = atPath.path

        do {
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: linkPath)
        } catch {
            throw OutFileError(file: OutFile(path), error: error)
        }

        return InFile(path)
    }

    public static func chmod(atPath: borrowing InFile, mode: Int) async throws {
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: atPath.path.string)
    }

    public static func withTemporary<T>(file: consuming InFile, f: (_: borrowing InFile) async throws -> T) async throws -> T {
        do {
            let t: T = try await f(file)

            try? await Self.remove(file: file)

            return t
        } catch {
            try? await Self.remove(file: file)

            throw error
        }
    }

    public static func withTemporary<T>(files: FilePath..., f: () async throws -> T) async throws -> T {
        try await self.withTemporary(files: files, f: f)
    }

    public static func withTemporary<T>(files: [FilePath], f: () async throws -> T) async throws -> T {
        do {
            let t: T = try await f()

            for f in files {
                try? await Self.remove(file: InFile(f))
            }

            return t
        } catch {
            // Sort the list in case there are temporary files nested within other temporary files
            for f in files.map(\.string).sorted() {
                try? await Self.remove(file: InFile(FilePath(f)))
            }

            throw error
        }
    }
}

extension FileManager {
    public var currentDir: FilePath {
        FilePath(Self.default.currentDirectoryPath)
    }

    public var homeDir: FilePath {
        FilePath(Self.default.homeDirectoryForCurrentUser.path)
    }

    public func fileExists(atPath path: FilePath) -> Bool {
        Self.default.fileExists(atPath: path.string, isDirectory: nil)
    }

    public func removeItem(atPath path: FilePath) throws {
        try Self.default.removeItem(atPath: path.string)
    }

    public func moveItem(atPath: FilePath, toPath: FilePath) throws {
        try Self.default.moveItem(atPath: atPath.string, toPath: toPath.string)
    }

    public func copyItem(atPath: FilePath, toPath: FilePath) throws {
        try Self.default.copyItem(atPath: atPath.string, toPath: toPath.string)
    }

    public func deleteIfExists(atPath path: FilePath) throws {
        do {
            try Self.default.removeItem(atPath: path.string)
        } catch let error as NSError {
            guard error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileNoSuchFile.rawValue else {
                throw error
            }
        }
    }

    public func createDir(atPath: FilePath, withIntermediateDirectories: Bool) throws {
        try Self.default.createDirectory(atPath: atPath.string, withIntermediateDirectories: withIntermediateDirectories)
    }

    public func contents(atPath: FilePath) -> Data? {
        Self.default.contents(atPath: atPath.string)
    }

    public var temporaryDir: FilePath {
        FilePath(Self.default.temporaryDirectory.path)
    }

    public func contentsOfDir(atPath: FilePath) throws -> [String] {
        try Self.default.contentsOfDirectory(atPath: atPath.string)
    }

    public func destinationOfSymbolicLink(atPath: FilePath) throws -> FilePath {
        FilePath(try Self.default.destinationOfSymbolicLink(atPath: atPath.string))
    }

    public func createSymbolicLink(atPath: FilePath, withDestinationPath: FilePath) throws {
        try Self.default.createSymbolicLink(atPath: atPath.string, withDestinationPath: withDestinationPath.string)
    }
}

extension Data {
    public func write(to path: FilePath, options: Data.WritingOptions = []) throws {
        try self.write(to: URL(fileURLWithPath: path.string), options: options)
    }

    public func write(to file: consuming OutFile, options: Data.WritingOptions = []) throws -> InFile? {
        let path = file.path
        try self.write(to: URL(fileURLWithPath: path.string), options: options)
        return InFile(path)
    }

    public init(contentsOf path: FilePath) throws {
        try self.init(contentsOf: URL(fileURLWithPath: path.string))
    }

    public init(contentsOf file: borrowing InFile) throws {
        try self.init(contentsOf: URL(fileURLWithPath: file.path.string))
    }
}

extension String {
    public func write(to path: FilePath, atomically: Bool, encoding enc: String.Encoding = .utf8) throws {
        try self.write(to: URL(fileURLWithPath: path.string), atomically: atomically, encoding: enc)
    }

    public func write(to file: consuming OutFile, atomically: Bool, encoding enc: String.Encoding = .utf8) throws -> InFile? {
        let path = file.path
        try self.write(to: URL(fileURLWithPath: path.string), atomically: atomically, encoding: enc)
        return InFile(path)
    }

    public init(contentsOf path: FilePath, encoding enc: String.Encoding = .utf8) throws {
        try self.init(contentsOf: URL(fileURLWithPath: path.string), encoding: enc)
    }

    public init(contentsOf file: borrowing InFile, encoding enc: String.Encoding = .utf8) throws {
        try self.init(contentsOf: URL(fileURLWithPath: file.path.string), encoding: enc)
    }
}

extension FilePath {
    public static func / (left: FilePath, right: String) -> FilePath {
        left.appending(right)
    }

    public var parent: FilePath { self.removingLastComponent() }
}
