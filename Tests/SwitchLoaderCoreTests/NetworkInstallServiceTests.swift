import Foundation
import Testing
@testable import SwitchLoaderCore

@Suite("Network install")
struct NetworkInstallServiceTests {
    @Test("Handshake payload lists encoded file URLs")
    func handshakePayload() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("hello world.nsp")
        try Data("abc".utf8).write(to: fileURL)

        let file = try SwitchTransferFile(url: fileURL)
        let payload = NetworkInstallService.handshakePayload(
            files: [file],
            hostIP: "192.168.1.10",
            hostPort: 6060,
            remotePathPrefix: ""
        )

        #expect(payload == "192.168.1.10:6060/hello%20world.nsp\n")
    }

    @Test("Handshake payload includes remote prefix")
    func handshakePayloadWithPrefix() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("game.nsz")
        try Data("abc".utf8).write(to: fileURL)

        let file = try SwitchTransferFile(url: fileURL)
        let payload = NetworkInstallService.handshakePayload(
            files: [file],
            hostIP: "10.0.0.2",
            hostPort: 8080,
            remotePathPrefix: "/ROMS/NS/"
        )

        #expect(payload == "10.0.0.2:8080/ROMS/NS/game.nsz\n")
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
