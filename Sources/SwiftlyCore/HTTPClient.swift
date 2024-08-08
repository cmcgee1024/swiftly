import _StringProcessing
import AsyncHTTPClient
import Foundation
import NIO
import NIOFoundationCompat
import NIOHTTP1

public protocol HTTPRequestExecutor {
    func execute(_ request: HTTPClientRequest, timeout: TimeAmount) async throws -> HTTPClientResponse
}

/// An `HTTPRequestExecutor` backed by an `HTTPClient`.
internal struct HTTPRequestExecutorImpl: HTTPRequestExecutor {
    fileprivate static let client = HTTPClientWrapper()

    public func execute(_ request: HTTPClientRequest, timeout: TimeAmount) async throws -> HTTPClientResponse {
        try await Self.client.inner.execute(request, timeout: timeout)
    }
}

private func makeRequest(url: String) -> HTTPClientRequest {
    var request = HTTPClientRequest(url: url)
    request.headers.add(name: "User-Agent", value: "swiftly/\(SwiftlyCore.version)")
    return request
}

struct SwiftOrgSwiftlyRelease: Codable {
    var name: String
}

struct SwiftOrgPlatform: Codable {
    var name: String
    var platform: String
    var archs: [String]

    var platformName: String {
        get {
            switch(name) {
            case "Ubuntu 14.04":
                "ubuntu1404"
            case "Ubuntu 15.10":
                "ubuntu1510"
            case "Ubuntu 16.04":
                "ubuntu1604"
            case "Ubuntu 16.10":
                "ubuntu1610"
            case "Ubuntu 18.04":
                "ubuntu1804"
            case "Ubuntu 20.04":
                "ubuntu2004"
            case "Amazon Linux 2":
                "amazonlinux2"
            case "CentOS 8":
                "centos8"
            case "CentOS 7":
                "centos7"
            case "Windows 10":
                "win10"
            case "Ubuntu 22.04":
                "ubuntu2204"
            case "Red Hat Universal Base Image 9":
                "ubi9"
            case "Ubuntu 23.10":
                "ubuntu2310"
            case "Ubuntu 24.04":
                "ubuntu2404"
            case "Debian 12":
                "debian12"
            case "Fedora 39":
                "fedora39"
            default:
                ""
            }
        }
    }
}

public struct SwiftOrgRelease : Codable {
    var name: String
    var platforms: [SwiftOrgPlatform]

    var stableName: String {
        get {
            let components = name.components(separatedBy: ".")
            if components.count == 2 {
                return name + ".0"
            } else {
                return name
            }
        }
    }
}

public struct SwiftOrgSnapshotList: Codable {
    var aarch64: [SwiftOrgSnapshot]?
    var x86_64: [SwiftOrgSnapshot]?
    var universal: [SwiftOrgSnapshot]?
}

public struct SwiftOrgSnapshot: Codable {
    var dir: String

    private static let snapshotRegex: Regex<(Substring, Substring?, Substring?, Substring)> =
        try! Regex("swift(?:-(\\d+)\\.(\\d+))?-DEVELOPMENT-SNAPSHOT-(\\d{4}-\\d{2}-\\d{2})")

    internal func parseSnapshot() throws -> ToolchainVersion.Snapshot? {
        guard let match = try? Self.snapshotRegex.firstMatch(in: self.dir) else {
            return nil
        }

        let branch: ToolchainVersion.Snapshot.Branch
        if let majorString = match.output.1, let minorString = match.output.2 {
            guard let major = Int(majorString), let minor = Int(minorString) else {
                throw Error(message: "malformatted release branch: \"\(majorString).\(minorString)\"")
            }
            branch = .release(major: major, minor: minor)
        } else {
            branch = .main
        }

        return ToolchainVersion.Snapshot(branch: branch, date: String(match.output.3))
    }
}

/// HTTPClient wrapper used for interfacing with various REST APIs and downloading things.
public struct SwiftlyHTTPClient {
    private struct Response {
        let status: HTTPResponseStatus
        let buffer: ByteBuffer
    }

    private let executor: HTTPRequestExecutor

    /// The GitHub authentication token to use for any requests made to the GitHub API.
    public var githubToken: String?

    public init(executor: HTTPRequestExecutor? = nil) {
        self.executor = executor ?? HTTPRequestExecutorImpl()
    }

    private func get(url: String, headers: [String: String]) async throws -> Response {
        var request = makeRequest(url: url)

        for (k, v) in headers {
            request.headers.add(name: k, value: v)
        }

        let response = try await self.executor.execute(request, timeout: .seconds(30))

        // if defined, the content-length headers announces the size of the body
        let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init) ?? 1024 * 1024
        return Response(status: response.status, buffer: try await response.body.collect(upTo: expectedBytes))
    }

    /// Decode the provided type `T` from the JSON body of the response from a GET request
    /// to the given URL.
    public func getFromJSON<T: Decodable>(
        url: String,
        type: T.Type,
        headers: [String: String] = [:]
    ) async throws -> T {
        let response = try await self.get(url: url, headers: headers)

        guard case .ok = response.status else {
            var message = "received status \"\(response.status)\" when reaching \(url)"
            if let json = response.buffer.getString(at: 0, length: response.buffer.readableBytes) {
                message += ": \(json)"
            }
            throw Error(message: message)
        }

        return try JSONDecoder().decode(type.self, from: response.buffer)
    }

    /// Return an array of released Swift versions that match the given filter, up to the provided
    /// limit (default unlimited).
    public func getReleaseToolchains(
        platform: PlatformDefinition,
        limit: Int? = nil,
        filter: ((ToolchainVersion.StableRelease) -> Bool)? = nil
    ) async throws -> [ToolchainVersion.StableRelease] {
        #if arch(x86_64)
        let arch = "x86_64"
        #elseif arch(arm64)
        let arch = "aarch64"
        #else
        #error("Unsupported processor architecture")
        #endif

        let url = "https://swift.org/api/v1/install/releases.json"
        let swiftOrgReleases: [SwiftOrgRelease] = try await self.getFromJSON(url: url, type: [SwiftOrgRelease].self)

        var swiftOrgFiltered: [ToolchainVersion.StableRelease] = swiftOrgReleases.compactMap( { swiftOrgRelease in
            guard let swiftOrgPlatform = swiftOrgRelease.platforms.first(where: { $0.platformName == platform.name || platform.name == "xcode"}) else {
                return nil
            }

            guard swiftOrgPlatform.archs.contains(arch) || platform.name == "xcode" else {
                return nil
            }

            guard let version = try? ToolchainVersion(parsing: swiftOrgRelease.stableName),
                case let .stable(release) = version else {
                return nil
            }

            if let filter {
                guard filter(release) else {
                    return nil
                }
            }

            return release
        })

        guard !swiftOrgFiltered.isEmpty else {
            return []
        }

        swiftOrgFiltered.sort(by: >)

        return if let limit = limit {
            Array(swiftOrgFiltered[0 ..< limit])
        } else {
            swiftOrgFiltered
        }
    }

    /// Return an array of Swift snapshots that match the given filter, up to the provided
    /// limit (default unlimited).
    public func getSnapshotToolchains(
        platform: PlatformDefinition,
        branch: ToolchainVersion.Snapshot.Branch,
        limit: Int? = nil,
        filter: ((ToolchainVersion.Snapshot) -> Bool)? = nil
    ) async throws -> [ToolchainVersion.Snapshot] {
        #if arch(x86_64)
        let arch = "x86_64"
        #elseif arch(arm64)
        let arch = "aarch64"
        #else
        fatalError("Unsupported processor architecture")
        #endif

        // TODO use the GitHub API's for older snapshot toolchains on older release branches than 6.0
        let branchLabel = switch branch {
        case .main:
            "main"
        case let .release(major, minor):
            "\(major).\(minor)"
        }

        var snapshotToolchains: Set<ToolchainVersion.Snapshot> = []

        let platformName = if platform.name == "xcode" {
            "macos"
        } else {
            platform.name
        }

        let url = "https://swift.org/api/v1/install/dev/\(branchLabel)/\(platformName).json"

        let swiftOrgSnapshotList: SwiftOrgSnapshotList = try await self.getFromJSON(url: url, type: SwiftOrgSnapshotList.self)
        let swiftOrgSnapshots = if platform.name == "xcode" {
            swiftOrgSnapshotList.universal ?? Array<SwiftOrgSnapshot>()
        } else if arch == "aarch64" {
            swiftOrgSnapshotList.aarch64 ?? Array<SwiftOrgSnapshot>()
        } else if arch == "x86_64" {
            swiftOrgSnapshotList.x86_64 ?? Array<SwiftOrgSnapshot>()
        } else {
            Array<SwiftOrgSnapshot>()
        }

        let swiftOrgFiltered: [ToolchainVersion.Snapshot] = swiftOrgSnapshots.compactMap( { swiftOrgSnapshot in
            guard let snapshot = try? swiftOrgSnapshot.parseSnapshot() else {
                return nil
            }

            if let filter {
                guard filter(snapshot) else {
                    return nil
                }
            }

            return snapshot
        })

        snapshotToolchains.formUnion(Set(swiftOrgFiltered))

        guard !swiftOrgFiltered.isEmpty else {
            return []
        }

        var finalSnapshotToolchains = Array(snapshotToolchains)
        finalSnapshotToolchains.sort(by: >)

        return if let limit = limit {
            Array(finalSnapshotToolchains[0 ..< limit])
        } else {
            finalSnapshotToolchains
        }
    }

    public struct DownloadProgress {
        public let receivedBytes: Int
        public let totalBytes: Int?
    }

    public struct DownloadNotFoundError: LocalizedError {
        public let url: String
    }

    public func downloadFile(
        url: URL,
        to destination: URL,
        reportProgress: ((DownloadProgress) -> Void)? = nil
    ) async throws {
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? fileHandle.close()
        }

        let request = makeRequest(url: url.absoluteString)
        let response = try await self.executor.execute(request, timeout: .seconds(30))

        switch response.status {
        case .ok:
            break
        case .notFound:
            throw SwiftlyHTTPClient.DownloadNotFoundError(url: url.path)
        default:
            throw Error(message: "Received \(response.status) when trying to download \(url)")
        }

        // if defined, the content-length headers announces the size of the body
        let expectedBytes = response.headers.first(name: "content-length").flatMap(Int.init)

        var lastUpdate = Date()
        var receivedBytes = 0
        for try await buffer in response.body {
            receivedBytes += buffer.readableBytes

            let byteData = buffer.getData(at: buffer.readerIndex, length: buffer.readableBytes)
            if let data = byteData {
                try fileHandle.write(contentsOf: data)
            }

            let now = Date()
            if let reportProgress, lastUpdate.distance(to: now) > 0.25 || receivedBytes == expectedBytes {
                lastUpdate = now
                reportProgress(SwiftlyHTTPClient.DownloadProgress(
                    receivedBytes: receivedBytes,
                    totalBytes: expectedBytes
                ))
            }
        }

        try fileHandle.synchronize()
    }
}

private class HTTPClientWrapper {
    fileprivate let inner = HTTPClient(eventLoopGroupProvider: .singleton)

    deinit {
        try? self.inner.syncShutdown()
    }
}
