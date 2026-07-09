import Foundation
import Testing
@testable import SwitchLoaderCore

@Suite("Tinfoil USB installer")
struct TinfoilUSBInstallerTests {
    @Test("File list payload is newline separated")
    func fileListPayload() throws {
        let directory = try temporaryDirectory()
        let first = directory.appendingPathComponent("first.nsp")
        let second = directory.appendingPathComponent("second.xci")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        let files = try [first, second].map(SwitchTransferFile.init(url:))
        let payload = TinfoilUSBInstaller.fileListPayload(for: files)

        #expect(String(data: payload, encoding: .utf8) == "first.nsp\nsecond.xci\n")
    }
}
