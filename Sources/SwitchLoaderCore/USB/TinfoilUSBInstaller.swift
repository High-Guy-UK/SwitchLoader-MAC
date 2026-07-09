import Foundation

public final class TinfoilUSBInstaller {
    private static let inEndpoint: UInt8 = 0x81
    private static let outEndpoint: UInt8 = 0x01
    private static let chunkSize = 0x800000
    private static let handshakeMagic = Data("TUL0".utf8)
    private static let replyMagic = "TUC0"
    private static let standardReply = Data([0x54, 0x55, 0x43, 0x30, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    private static let twelveZeroBytes = Data(repeating: 0, count: 12)
    private static let eightZeroBytes = Data(repeating: 0, count: 8)

    public init() {}

    public func install(
        configuration: USBInstallConfiguration,
        onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) throws {
        guard !configuration.files.isEmpty else {
            throw USBInstallError.noFiles
        }

        let files = try configuration.files.map(SwitchTransferFile.init(url:))
        let filesByName = Dictionary(uniqueKeysWithValues: files.map { ($0.url.lastPathComponent, $0) })

        emit("Looking for USB installer device.", .info, onEvent)
        let connection = USBDeviceConnection()
        try connection.openHomebrewDevice()
        defer {
            connection.close()
        }

        emit("Device connected. Sending file list.", .success, onEvent)
        try sendFileList(files, connection: connection)
        emit("File list sent. Waiting for install requests.", .success, onEvent)

        while true {
            let reply = try readNonEmptyPacket(connection: connection)
            guard reply.count >= 9,
                  String(data: reply.prefix(4), encoding: .utf8) == Self.replyMagic
            else {
                continue
            }

            switch reply[8] {
            case 0x00:
                emit("USB install complete.", .success, onEvent)
                onEvent(.completed)
                return
            case 0x01, 0x02:
                try sendRequestedRange(filesByName: filesByName, connection: connection, onEvent: onEvent)
            default:
                emit("Ignoring unknown USB command \(reply[8]).", .warning, onEvent)
            }
        }
    }

    public static func fileListPayload(for files: [SwitchTransferFile]) -> Data {
        Data(files.map(\.url.lastPathComponent).joined(separator: "\n").appending("\n").utf8)
    }

    private func sendFileList(_ files: [SwitchTransferFile], connection: USBDeviceConnection) throws {
        let names = Self.fileListPayload(for: files)
        try connection.bulkWrite(endpoint: Self.outEndpoint, data: Self.handshakeMagic)
        try connection.bulkWrite(endpoint: Self.outEndpoint, data: Data(UInt32(names.count).littleEndianBytes))
        try connection.bulkWrite(endpoint: Self.outEndpoint, data: Self.eightZeroBytes)
        try connection.bulkWrite(endpoint: Self.outEndpoint, data: names)
    }

    private func sendRequestedRange(
        filesByName: [String: SwitchTransferFile],
        connection: USBDeviceConnection,
        onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) throws {
        let rangePacket = try readNonEmptyPacket(connection: connection)
        guard rangePacket.count >= 16 else {
            throw USBInstallError.unexpectedReply
        }

        let requestedSize = UInt64(littleEndianBytes: rangePacket[0..<8])
        let offset = UInt64(littleEndianBytes: rangePacket[8..<16])
        let fileNamePacket = try readNonEmptyPacket(connection: connection)
        guard let fileName = String(data: fileNamePacket, encoding: .utf8) else {
            throw USBInstallError.unexpectedReply
        }
        guard let file = filesByName[fileName] else {
            throw USBInstallError.requestedFileMissing(fileName)
        }

        emit("Sending \(file.url.lastPathComponent).", .info, onEvent)

        try connection.bulkWrite(endpoint: Self.outEndpoint, data: Self.standardReply)
        try connection.bulkWrite(endpoint: Self.outEndpoint, data: Data(UInt64(requestedSize).littleEndianBytes))
        try connection.bulkWrite(endpoint: Self.outEndpoint, data: Self.twelveZeroBytes)

        var sent: UInt64 = 0
        let end = offset + requestedSize - 1
        try file.readRange(start: offset, endInclusive: end, chunkSize: Self.chunkSize) { chunk in
            try connection.bulkWrite(endpoint: Self.outEndpoint, data: chunk)
            sent += UInt64(chunk.count)
            onEvent(.progress(Double(sent) / Double(requestedSize)))
        }
        emit("Sent \(file.url.lastPathComponent).", .success, onEvent)
    }

    private func readNonEmptyPacket(connection: USBDeviceConnection) throws -> Data {
        while true {
            let packet = try connection.bulkRead(endpoint: Self.inEndpoint)
            if !packet.isEmpty {
                return packet
            }
        }
    }

    private func emit(
        _ message: String,
        _ level: TransferLogLevel,
        _ onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) {
        onEvent(.log(TransferLogEntry(level: level, message: message)))
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}

private extension UInt64 {
    init(littleEndianBytes bytes: Data.SubSequence) {
        var value: UInt64 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt64(byte) << UInt64(index * 8)
        }
        self = value
    }

    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}
