import Foundation
import Testing
@testable import SwitchLoaderCore

@Suite("RCM payload launcher")
struct RCMPayloadLauncherTests {
    @Test("Exploit payload places stage and user payload at expected offsets")
    func exploitPayloadLayout() throws {
        let intermezzo = [UInt8](repeating: 0x7c, count: 124)
        let userPayload = Data((0..<128).map { UInt8($0) })

        let exploit = try RCMPayloadLauncher.exploitPayload(for: userPayload, intermezzo: intermezzo)
        let bytes = [UInt8](exploit)

        #expect(Array(bytes[0..<4]) == [0x98, 0x02, 0x03, 0x00])
        #expect(Array(bytes[680..<(680 + intermezzo.count)]) == intermezzo)
        let referencePayloadOffset = 680 + intermezzo.count + (0x0E40 - intermezzo.count)
        #expect(Array(bytes[referencePayloadOffset..<(referencePayloadOffset + userPayload.count)]) == [UInt8](userPayload))
        #expect(exploit.count.isMultiple(of: 0x1000))
    }

    @Test("Oversized payload is rejected before USB transfer")
    func oversizedPayload() {
        let largePayload = Data(repeating: 0xaa, count: 0x30000)

        #expect(throws: RCMPayloadError.self) {
            _ = try RCMPayloadLauncher.exploitPayload(for: largePayload)
        }
    }

    @Test("Hekate sized payload matches reference chunk count")
    func hekateSizedPayloadChunkCount() throws {
        let hekateSizedPayload = Data(repeating: 0xaa, count: 110_028)
        let exploit = try RCMPayloadLauncher.exploitPayload(for: hekateSizedPayload)

        #expect(exploit.count == 126_976)
        #expect(exploit.count / 0x1000 == 31)
    }
}
