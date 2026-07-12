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
        #expect(Array(bytes[0x0E40..<(0x0E40 + userPayload.count)]) == [UInt8](userPayload))
        #expect(exploit.count.isMultiple(of: 0x1000))
    }

    @Test("Oversized payload is rejected before USB transfer")
    func oversizedPayload() {
        let largePayload = Data(repeating: 0xaa, count: 0x30000)

        #expect(throws: RCMPayloadError.self) {
            _ = try RCMPayloadLauncher.exploitPayload(for: largePayload)
        }
    }
}
