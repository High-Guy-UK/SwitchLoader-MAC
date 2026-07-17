import Foundation
import Testing
@testable import SwitchLoaderCore

@Suite("SwitchLoader USB receiver sender")
struct SwitchLoaderUSBReceiverSenderTests {
    @Test("Manifest payload includes names and sizes")
    func manifestPayload() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("hello world.nsp")
        try Data("abcdef".utf8).write(to: fileURL)

        let file = try SwitchTransferFile(url: fileURL)
        let payload = try SwitchLoaderUSBReceiverSender.manifestPayload(for: [file])

        #expect(String(data: payload[0..<4], encoding: .utf8) == "SLR0")
        #expect(UInt16(littleEndianBytes: payload[4..<6]) == 1)
        #expect(UInt16(littleEndianBytes: payload[6..<8]) == 1)
        #expect(UInt16(littleEndianBytes: payload[8..<10]) == 15)
        #expect(String(data: payload[10..<25], encoding: .utf8) == "hello world.nsp")
        #expect(UInt64(littleEndianBytes: payload[25..<33]) == 6)
    }

    @Test("Manifest packets match receiver read sizes")
    func manifestPackets() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("hello world.nsp")
        try Data("abcdef".utf8).write(to: fileURL)

        let file = try SwitchTransferFile(url: fileURL)
        let packets = try SwitchLoaderUSBReceiverSender.manifestPackets(for: [file])

        #expect(packets.map(\.count) == [4, 2, 2, 2, 15, 8])
        #expect(String(data: packets[0], encoding: .utf8) == "SLR0")
        #expect(String(data: packets[4], encoding: .utf8) == "hello world.nsp")
        #expect(UInt64(littleEndianBytes: packets[5][...]) == 6)
    }

    @Test("Homebrew manifest preserves generated folder paths")
    func homebrewManifestPayload() throws {
        let directory = try temporaryDirectory()
        let appDirectory = directory
            .appendingPathComponent("switch", isDirectory: true)
            .appendingPathComponent("Example", isDirectory: true)
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        let nroURL = appDirectory.appendingPathComponent("Example.nro")
        try Data("nro".utf8).write(to: nroURL)

        let payload = try SwitchLoaderUSBReceiverSender.homebrewManifestPayload(for: directory)

        #expect(String(data: payload[0..<4], encoding: .utf8) == "SLR0")
        #expect(UInt16(littleEndianBytes: payload[6..<8]) == 1)
        #expect(UInt16(littleEndianBytes: payload[8..<10]) == 26)
        #expect(String(data: payload[10..<36], encoding: .utf8) == "switch/Example/Example.nro")
        #expect(UInt64(littleEndianBytes: payload[36..<44]) == 3)
    }
}

private extension UInt16 {
    init(littleEndianBytes bytes: Data.SubSequence) {
        var value: UInt16 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt16(byte) << UInt16(index * 8)
        }
        self = value
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
}
