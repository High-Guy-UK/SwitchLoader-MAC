import Foundation

public struct SwitchTransferFile: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let url: URL
    public let encodedName: String
    public let size: UInt64
    public let kind: Kind

    public enum Kind: Sendable, Hashable {
        case regular
        case split(chunks: [URL], referenceChunkSize: UInt64)
    }

    public init(url: URL) throws {
        self.id = UUID()
        self.url = url

        guard let encodedName = url.lastPathComponent.percentEncodedForSwitchPath else {
            throw SwitchTransferFileError.invalidFileName(url.lastPathComponent)
        }
        self.encodedName = encodedName

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw SwitchTransferFileError.missing(url)
        }

        if isDirectory.boolValue {
            let splitInfo = try Self.splitInfo(for: url)
            self.kind = .split(chunks: splitInfo.chunks, referenceChunkSize: splitInfo.referenceChunkSize)
            self.size = splitInfo.size
        } else {
            self.kind = .regular
            self.size = try Self.fileSize(url)
            guard size > 0 else {
                throw SwitchTransferFileError.empty(url)
            }
        }
    }

    public func readRange(start: UInt64, endInclusive: UInt64, chunkSize: Int = 64 * 1024, sink: (Data) throws -> Void) throws {
        guard start <= endInclusive, endInclusive < size else {
            throw SwitchTransferFileError.invalidRange(start: start, end: endInclusive, size: size)
        }

        switch kind {
        case .regular:
            try readRegularRange(start: start, endInclusive: endInclusive, chunkSize: chunkSize, sink: sink)
        case let .split(chunks, referenceChunkSize):
            try readSplitRange(chunks: chunks, referenceChunkSize: referenceChunkSize, start: start, endInclusive: endInclusive, chunkSize: chunkSize, sink: sink)
        }
    }

    private func readRegularRange(start: UInt64, endInclusive: UInt64, chunkSize: Int, sink: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        try handle.seek(toOffset: start)
        var remaining = endInclusive - start + 1
        while remaining > 0 {
            let nextSize = min(UInt64(chunkSize), remaining)
            let data = try handle.read(upToCount: Int(nextSize)) ?? Data()
            guard !data.isEmpty else {
                throw SwitchTransferFileError.unexpectedEndOfFile(url)
            }
            try sink(data)
            remaining -= UInt64(data.count)
        }
    }

    private func readSplitRange(
        chunks: [URL],
        referenceChunkSize: UInt64,
        start: UInt64,
        endInclusive: UInt64,
        chunkSize: Int,
        sink: (Data) throws -> Void
    ) throws {
        var current = start
        while current <= endInclusive {
            let chunkIndex = Int(current / referenceChunkSize)
            let offsetInChunk = current % referenceChunkSize
            guard chunkIndex < chunks.count else {
                throw SwitchTransferFileError.unexpectedEndOfFile(url)
            }

            let chunkURL = chunks[chunkIndex]
            let chunkLength = try Self.fileSize(chunkURL)
            let availableInChunk = chunkLength - offsetInChunk
            let remaining = endInclusive - current + 1
            let bytesToRead = min(UInt64(chunkSize), availableInChunk, remaining)

            let handle = try FileHandle(forReadingFrom: chunkURL)
            defer {
                try? handle.close()
            }
            try handle.seek(toOffset: offsetInChunk)
            let data = try handle.read(upToCount: Int(bytesToRead)) ?? Data()
            guard UInt64(data.count) == bytesToRead else {
                throw SwitchTransferFileError.unexpectedEndOfFile(chunkURL)
            }
            try sink(data)
            current += UInt64(data.count)
        }
    }

    private static func splitInfo(for directory: URL) throws -> (chunks: [URL], referenceChunkSize: UInt64, size: UInt64) {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let chunks = contents
            .filter { $0.lastPathComponent.range(of: #"^\d\d$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let firstChunk = chunks.first else {
            throw SwitchTransferFileError.invalidSplitDirectory(directory)
        }

        let firstSize = try fileSize(firstChunk)
        var total: UInt64 = 0
        for (index, chunk) in chunks.enumerated() {
            let chunkLength = try fileSize(chunk)
            if index < chunks.count - 1, chunkLength != firstSize {
                throw SwitchTransferFileError.invalidSplitDirectory(directory)
            }
            if index == chunks.count - 1, chunkLength > firstSize {
                throw SwitchTransferFileError.invalidSplitDirectory(directory)
            }
            total += chunkLength
        }

        guard total > 0 else {
            throw SwitchTransferFileError.empty(directory)
        }

        return (chunks, firstSize, total)
    }

    static func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw SwitchTransferFileError.missing(url)
        }
        return size.uint64Value
    }
}

public enum SwitchTransferFileError: LocalizedError, Equatable {
    case missing(URL)
    case empty(URL)
    case invalidFileName(String)
    case invalidSplitDirectory(URL)
    case invalidRange(start: UInt64, end: UInt64, size: UInt64)
    case unexpectedEndOfFile(URL)

    public var errorDescription: String? {
        switch self {
        case let .missing(url):
            "Missing file: \(url.lastPathComponent)"
        case let .empty(url):
            "File is empty: \(url.lastPathComponent)"
        case let .invalidFileName(name):
            "File name cannot be encoded: \(name)"
        case let .invalidSplitDirectory(url):
            "Split folder is not valid: \(url.lastPathComponent)"
        case let .invalidRange(start, end, size):
            "Requested range \(start)-\(end) is outside file size \(size)."
        case let .unexpectedEndOfFile(url):
            "Unexpected end of file while reading \(url.lastPathComponent)."
        }
    }
}

private extension String {
    var percentEncodedForSwitchPath: String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed)
    }
}
