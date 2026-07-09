import Foundation
import Testing
@testable import SwitchLoaderCore

@Suite("Split and merge")
struct SplitMergeServiceTests {
    @Test("Split creates numbered chunks and merge restores bytes")
    func splitAndMerge() throws {
        let root = try temporaryDirectory()
        let input = root.appendingPathComponent("sample.bin")
        let original = Data((0..<10_000).map { UInt8($0 % 251) })
        try original.write(to: input)

        let service = SplitMergeService()
        let splitFolder = try service.split(file: input, destinationDirectory: root, chunkSize: 4096)

        let chunks = try FileManager.default.contentsOfDirectory(at: splitFolder, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .sorted()
        #expect(chunks == ["00", "01", "02"])

        let merged = try service.merge(splitDirectory: splitFolder, destinationDirectory: root)
        let mergedData = try Data(contentsOf: merged)
        #expect(mergedData == original)
    }

    @Test("Split folder reader can read across chunk boundary")
    func splitRangeRead() throws {
        let root = try temporaryDirectory()
        let splitFolder = root.appendingPathComponent("split", isDirectory: true)
        try FileManager.default.createDirectory(at: splitFolder, withIntermediateDirectories: true)
        try Data("abcd".utf8).write(to: splitFolder.appendingPathComponent("00"))
        try Data("efgh".utf8).write(to: splitFolder.appendingPathComponent("01"))

        let transferFile = try SwitchTransferFile(url: splitFolder)
        var output = Data()
        try transferFile.readRange(start: 2, endInclusive: 5) { data in
            output.append(data)
        }

        #expect(String(data: output, encoding: .utf8) == "cdef")
    }
}
