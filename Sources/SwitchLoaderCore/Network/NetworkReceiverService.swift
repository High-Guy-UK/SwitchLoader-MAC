import Foundation

public struct NetworkReceiverConfiguration: Sendable, Equatable {
    public var files: [URL]
    public var hostIPAddress: String?
    public var hostPort: Int

    public init(
        files: [URL],
        hostIPAddress: String? = nil,
        hostPort: Int = 6060
    ) {
        self.files = files
        self.hostIPAddress = hostIPAddress
        self.hostPort = hostPort
    }
}

public struct SwitchLoaderReceiverManifest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let generatedAt: String
    public let host: String
    public let port: Int
    public let files: [SwitchLoaderReceiverManifestFile]
}

public struct SwitchLoaderReceiverManifestFile: Codable, Equatable, Sendable {
    public let name: String
    public let encodedName: String
    public let size: UInt64
    public let kind: String
    public let url: String
}

public final class NetworkReceiverService {
    public init() {}

    public func start(
        configuration: NetworkReceiverConfiguration,
        onEvent: @escaping @Sendable (NetworkInstallEvent) -> Void
    ) throws {
        guard !configuration.files.isEmpty else {
            throw NetworkInstallError.noFiles
        }

        let files = try configuration.files.map(SwitchTransferFile.init(url:))
        let hostIP = try configuration.hostIPAddress?.nonEmpty ?? IPv4AddressResolver.localAddress()
        let manifestData = try Self.manifestPayload(files: files, hostIP: hostIP, hostPort: configuration.hostPort)
        let server = try NetworkFileServer(files: files, port: configuration.hostPort, manifestPayload: manifestData)

        try server.start()
        emit("Receiver server ready at http://\(hostIP):\(configuration.hostPort)/manifest.json.", .success, onEvent)
        emit("Open SwitchLoader Receiver on the Switch and enter the Mac address.", .info, onEvent)

        try server.serveUntilDrop { event in
            onEvent(event)
        }
        onEvent(.completed)
    }

    public static func manifestPayload(
        files: [SwitchTransferFile],
        hostIP: String,
        hostPort: Int,
        generatedAt: Date = Date()
    ) throws -> Data {
        let manifest = SwitchLoaderReceiverManifest(
            protocolVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
            host: hostIP,
            port: hostPort,
            files: files.map { file in
                SwitchLoaderReceiverManifestFile(
                    name: file.url.lastPathComponent,
                    encodedName: file.encodedName,
                    size: file.size,
                    kind: file.kind.manifestKind,
                    url: "http://\(hostIP):\(hostPort)/\(file.encodedName)"
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    private func emit(
        _ message: String,
        _ level: TransferLogLevel,
        _ onEvent: @escaping @Sendable (NetworkInstallEvent) -> Void
    ) {
        onEvent(.log(TransferLogEntry(level: level, message: message)))
    }
}

private extension SwitchTransferFile.Kind {
    var manifestKind: String {
        switch self {
        case .regular:
            "regular"
        case .split:
            "split"
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
