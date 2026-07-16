import Foundation
import Testing
@testable import SwitchLoaderCore

@Suite("Network receiver")
struct NetworkReceiverServiceTests {
    @Test("Manifest payload describes files")
    func manifestPayload() throws {
        let directory = try temporaryDirectory()
        let fileURL = directory.appendingPathComponent("hello world.nsp")
        try Data("abc".utf8).write(to: fileURL)

        let file = try SwitchTransferFile(url: fileURL)
        let payload = try NetworkReceiverService.manifestPayload(
            files: [file],
            hostIP: "192.168.1.10",
            hostPort: 6060,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let manifest = try JSONDecoder().decode(SwitchLoaderReceiverManifest.self, from: payload)
        #expect(manifest.protocolVersion == 1)
        #expect(manifest.generatedAt == "1970-01-01T00:00:00Z")
        #expect(manifest.host == "192.168.1.10")
        #expect(manifest.port == 6060)
        #expect(manifest.files == [
            SwitchLoaderReceiverManifestFile(
                name: "hello world.nsp",
                encodedName: "hello%20world.nsp",
                size: 3,
                kind: "regular",
                url: "http://192.168.1.10:6060/hello%20world.nsp"
            )
        ])
    }
}
