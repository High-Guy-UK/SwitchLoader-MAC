import Darwin
import Foundation

public final class NetworkInstallService {
    public init() {}

    public func start(
        configuration: NetworkInstallConfiguration,
        onEvent: @escaping @Sendable (NetworkInstallEvent) -> Void
    ) throws {
        guard !configuration.files.isEmpty else {
            throw NetworkInstallError.noFiles
        }

        let files = try configuration.files.map(SwitchTransferFile.init(url:))
        let hostIP = try configuration.hostIPAddress?.nonEmpty ?? IPv4AddressResolver.localAddress()
        let prefix = configuration.remotePathPrefix.trimmedSlashes
        let handshake = Self.handshakePayload(files: files, hostIP: hostIP, hostPort: configuration.hostPort, remotePathPrefix: prefix)

        let server = configuration.serveRequests
            ? try NetworkFileServer(files: files, port: configuration.hostPort)
            : nil

        try server?.start()
        emit("Network server ready on \(hostIP):\(configuration.hostPort).", .success, onEvent)

        try sendHandshake(to: configuration.switchIPAddress, payload: handshake)
        emit("Sent file list to \(configuration.switchIPAddress).", .success, onEvent)

        guard let server else {
            emit("Serving is disabled; the Switch will use your configured remote URLs.", .warning, onEvent)
            onEvent(.completed)
            return
        }

        try server.serveUntilDrop { event in
            onEvent(event)
        }
        onEvent(.completed)
    }

    public static func handshakePayload(
        files: [SwitchTransferFile],
        hostIP: String,
        hostPort: Int,
        remotePathPrefix: String
    ) -> String {
        let prefix = remotePathPrefix.trimmedSlashes
        return files
            .map { file in
                if prefix.isEmpty {
                    "\(hostIP):\(hostPort)/\(file.encodedName)"
                } else {
                    "\(hostIP):\(hostPort)/\(prefix)/\(file.encodedName)"
                }
            }
            .joined(separator: "\n") + "\n"
    }

    private func sendHandshake(to switchIP: String, payload: String) throws {
        guard let payloadData = payload.data(using: .utf8) else {
            throw NetworkInstallError.invalidHandshake
        }

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = in_port_t(2000).bigEndian

        guard inet_pton(AF_INET, switchIP, &socketAddress.sin_addr) == 1 else {
            throw NetworkInstallError.invalidIPAddress(switchIP)
        }

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            close(descriptor)
        }

        let connected = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            throw NetworkInstallError.connectionFailed(switchIP)
        }

        var size = UInt32(payloadData.count).bigEndian
        try withUnsafeBytes(of: &size) { buffer in
            try writeAll(buffer, to: descriptor)
        }
        try payloadData.withUnsafeBytes { buffer in
            try writeAll(buffer, to: descriptor)
        }
    }

    private func writeAll(_ buffer: UnsafeRawBufferPointer, to descriptor: Int32) throws {
        guard let baseAddress = buffer.baseAddress else { return }
        var sent = 0
        while sent < buffer.count {
            let result = Darwin.write(descriptor, baseAddress.advanced(by: sent), buffer.count - sent)
            if result < 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            sent += result
        }
    }

    private func emit(
        _ message: String,
        _ level: TransferLogLevel,
        _ onEvent: @escaping @Sendable (NetworkInstallEvent) -> Void
    ) {
        onEvent(.log(TransferLogEntry(level: level, message: message)))
    }
}

public enum NetworkInstallError: LocalizedError, Equatable {
    case noFiles
    case invalidHandshake
    case invalidIPAddress(String)
    case connectionFailed(String)
    case noLocalIPAddress

    public var errorDescription: String? {
        switch self {
        case .noFiles:
            "Choose at least one file."
        case .invalidHandshake:
            "Could not build the installer handshake."
        case let .invalidIPAddress(address):
            "Invalid IP address: \(address)"
        case let .connectionFailed(address):
            "Could not connect to the Switch at \(address):2000."
        case .noLocalIPAddress:
            "Could not detect a local IPv4 address. Enter your Mac IP manually."
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedSlashes: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
