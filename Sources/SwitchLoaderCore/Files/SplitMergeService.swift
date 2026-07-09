import Foundation

public struct SplitMergeProgress: Sendable, Equatable {
    public let fileName: String
    public let fractionCompleted: Double

    public init(fileName: String, fractionCompleted: Double) {
        self.fileName = fileName
        self.fractionCompleted = fractionCompleted
    }
}

public final class SplitMergeService {
    public static let defaultChunkSize = 4_294_901_760
    private let bufferSize = 4 * 1024 * 1024

    public init() {}

    public func split(
        file source: URL,
        destinationDirectory: URL,
        chunkSize: Int = SplitMergeService.defaultChunkSize,
        onProgress: (SplitMergeProgress) -> Void = { _ in }
    ) throws -> URL {
        guard chunkSize > 0 else {
            throw SplitMergeError.invalidChunkSize
        }

        let sourceSize = try SwitchTransferFile.fileSize(source)
        guard sourceSize > 0 else {
            throw SplitMergeError.emptySource(source)
        }

        let resultDirectory = try uniqueURL(
            in: destinationDirectory,
            preferredName: "!_\(source.lastPathComponent)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: resultDirectory, withIntermediateDirectories: true)

        let input = try FileHandle(forReadingFrom: source)
        defer {
            try? input.close()
        }

        var writtenTotal: UInt64 = 0
        var chunkIndex = 0

        while writtenTotal < sourceSize {
            let chunkURL = resultDirectory.appendingPathComponent(String(format: "%02d", chunkIndex))
            FileManager.default.createFile(atPath: chunkURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: chunkURL)
            defer {
                try? output.close()
            }

            var writtenToChunk: UInt64 = 0
            let chunkLimit = UInt64(chunkSize)
            while writtenToChunk < chunkLimit, writtenTotal < sourceSize {
                let nextSize = min(UInt64(bufferSize), chunkLimit - writtenToChunk, sourceSize - writtenTotal)
                let data = try input.read(upToCount: Int(nextSize)) ?? Data()
                guard !data.isEmpty else {
                    throw SplitMergeError.unexpectedEndOfFile(source)
                }
                try output.write(contentsOf: data)
                writtenToChunk += UInt64(data.count)
                writtenTotal += UInt64(data.count)
                onProgress(SplitMergeProgress(fileName: source.lastPathComponent, fractionCompleted: Double(writtenTotal) / Double(sourceSize)))
            }

            chunkIndex += 1
        }

        let transferFile = try SwitchTransferFile(url: resultDirectory)
        guard transferFile.size == sourceSize else {
            throw SplitMergeError.validationFailed
        }

        return resultDirectory
    }

    public func merge(
        splitDirectory: URL,
        destinationDirectory: URL,
        onProgress: (SplitMergeProgress) -> Void = { _ in }
    ) throws -> URL {
        let transferFile = try SwitchTransferFile(url: splitDirectory)
        guard case let .split(chunks, _) = transferFile.kind else {
            throw SplitMergeError.invalidSplitDirectory(splitDirectory)
        }

        let resultFile = try uniqueURL(
            in: destinationDirectory,
            preferredName: "!_\(splitDirectory.lastPathComponent)",
            isDirectory: false
        )
        FileManager.default.createFile(atPath: resultFile.path, contents: nil)

        let output = try FileHandle(forWritingTo: resultFile)
        defer {
            try? output.close()
        }

        var copied: UInt64 = 0
        for chunk in chunks {
            let input = try FileHandle(forReadingFrom: chunk)
            defer {
                try? input.close()
            }

            while true {
                let data = try input.read(upToCount: bufferSize) ?? Data()
                if data.isEmpty {
                    break
                }
                try output.write(contentsOf: data)
                copied += UInt64(data.count)
                onProgress(SplitMergeProgress(fileName: splitDirectory.lastPathComponent, fractionCompleted: Double(copied) / Double(transferFile.size)))
            }
        }

        let mergedSize = try SwitchTransferFile.fileSize(resultFile)
        guard mergedSize == transferFile.size else {
            throw SplitMergeError.validationFailed
        }

        return resultFile
    }

    private func uniqueURL(in directory: URL, preferredName: String, isDirectory: Bool) throws -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(preferredName, isDirectory: isDirectory)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        for index in 0..<50 {
            candidate = directory.appendingPathComponent("!_\(index)_\(preferredName.dropFirst(2))", isDirectory: isDirectory)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        throw SplitMergeError.cannotCreateOutput
    }
}

public enum SplitMergeError: LocalizedError, Equatable {
    case invalidChunkSize
    case emptySource(URL)
    case unexpectedEndOfFile(URL)
    case invalidSplitDirectory(URL)
    case validationFailed
    case cannotCreateOutput

    public var errorDescription: String? {
        switch self {
        case .invalidChunkSize:
            "Chunk size must be greater than zero."
        case let .emptySource(url):
            "Source file is empty: \(url.lastPathComponent)"
        case let .unexpectedEndOfFile(url):
            "Unexpected end of file while reading \(url.lastPathComponent)."
        case let .invalidSplitDirectory(url):
            "Split folder is not valid: \(url.lastPathComponent)"
        case .validationFailed:
            "The output size did not match the input size."
        case .cannotCreateOutput:
            "Could not create a unique output path."
        }
    }
}
