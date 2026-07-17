import Foundation

public final class SwitchLoaderUSBReceiverSender {
    private static let outEndpoint: UInt8 = 0x01
    private static let chunkSize = 0x1000
    private static let magic = Data("SLR0".utf8)
    private static let fileMagic = Data("FILE".utf8)
    private static let protocolVersion: UInt16 = 1

    public init() {}

    public func send(
        configuration: USBInstallConfiguration,
        onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) throws {
        guard !configuration.files.isEmpty else {
            throw USBInstallError.noFiles
        }

        let files = try configuration.files.map { try ReceiverTransferFile(url: $0, relativePath: $0.lastPathComponent) }
        try send(files: files, onEvent: onEvent)
    }

    public func sendHomebrewFolder(
        _ folderURL: URL,
        onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) throws {
        let files = try Self.homebrewTransferFiles(in: folderURL)
        guard !files.isEmpty else {
            throw USBInstallError.noFiles
        }

        try send(files: files, onEvent: onEvent)
    }

    private func send(
        files: [ReceiverTransferFile],
        onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) throws {

        emit("Looking for SwitchLoader Receiver over USB.", .info, onEvent)
        let connection = USBDeviceConnection()
        try connection.openHomebrewDevice()
        defer {
            connection.close()
        }

        emit("Receiver connected. Sending queue manifest.", .success, onEvent)
        for packet in try Self.manifestPackets(for: files) {
            try connection.bulkWrite(endpoint: Self.outEndpoint, data: packet)
        }

        let totalBytes = files.reduce(UInt64(0)) { $0 + $1.size }
        var sentBytes: UInt64 = 0

        for file in files {
            emit("Sending \(file.relativePath).", .info, onEvent)
            try connection.bulkWrite(endpoint: Self.outEndpoint, data: Self.fileMagic)

            try file.readChunks(chunkSize: Self.chunkSize) { chunk in
                try connection.bulkWrite(endpoint: Self.outEndpoint, data: chunk)
                sentBytes += UInt64(chunk.count)
                onEvent(.progress(totalBytes == 0 ? 0 : Double(sentBytes) / Double(totalBytes)))
            }
        }

        emit("SwitchLoader Receiver transfer complete.", .success, onEvent)
        onEvent(.completed)
    }

    public static func manifestPayload(for files: [SwitchTransferFile]) throws -> Data {
        let receiverFiles = files.map { ReceiverTransferFile(transferFile: $0) }
        return try manifestPackets(for: receiverFiles).reduce(into: Data()) { payload, packet in
            payload.append(packet)
        }
    }

    public static func homebrewManifestPayload(for folderURL: URL) throws -> Data {
        try manifestPackets(for: homebrewTransferFiles(in: folderURL)).reduce(into: Data()) { payload, packet in
            payload.append(packet)
        }
    }

    static func manifestPackets(for files: [SwitchTransferFile]) throws -> [Data] {
        try manifestPackets(for: files.map { ReceiverTransferFile(transferFile: $0) })
    }

    private static func manifestPackets(for files: [ReceiverTransferFile]) throws -> [Data] {
        guard files.count <= UInt16.max else {
            throw USBInstallError.transferFailed("Too many files for SwitchLoader Receiver.")
        }

        var packets: [Data] = [
            Self.magic,
            Data(Self.protocolVersion.littleEndianBytes),
            Data(UInt16(files.count).littleEndianBytes)
        ]

        for file in files {
            guard let nameData = file.relativePath.data(using: .utf8),
                  nameData.count <= UInt16.max
            else {
                throw SwitchTransferFileError.invalidFileName(file.relativePath)
            }

            packets.append(Data(UInt16(nameData.count).littleEndianBytes))
            packets.append(nameData)
            packets.append(Data(file.size.littleEndianBytes))
        }

        return packets
    }

    private static func homebrewTransferFiles(in folderURL: URL) throws -> [ReceiverTransferFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw USBInstallError.transferFailed("Generated Homebrew folder was not found.")
        }

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw USBInstallError.transferFailed("Could not read generated Homebrew folder.")
        }

        var files: [ReceiverTransferFile] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let relativePath = Self.relativePath(from: folderURL, to: fileURL)
            guard Self.isAllowedHomebrewInstallPath(relativePath) else {
                continue
            }

            files.append(try ReceiverTransferFile(url: fileURL, relativePath: relativePath))
        }

        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func relativePath(from root: URL, to file: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let startIndex = filePath.index(filePath.startIndex, offsetBy: min(rootPath.count + 1, filePath.count))
        return String(filePath[startIndex...])
    }

    private static func isAllowedHomebrewInstallPath(_ path: String) -> Bool {
        guard let firstComponent = path.split(separator: "/", omittingEmptySubsequences: true).first else {
            return false
        }

        return ["atmosphere", "bootloader", "config", "switch", "themes"].contains(firstComponent.lowercased())
    }

    private func emit(
        _ message: String,
        _ level: TransferLogLevel,
        _ onEvent: @escaping @Sendable (USBInstallEvent) -> Void
    ) {
        onEvent(.log(TransferLogEntry(level: level, message: message)))
    }
}

private struct ReceiverTransferFile {
    let url: URL
    let relativePath: String
    let size: UInt64

    init(url: URL, relativePath: String) throws {
        self.url = url
        self.relativePath = relativePath
        self.size = try Self.fileSize(url)
        guard size > 0 else {
            throw SwitchTransferFileError.empty(url)
        }
    }

    init(transferFile: SwitchTransferFile) {
        self.url = transferFile.url
        self.relativePath = transferFile.url.lastPathComponent
        self.size = transferFile.size
    }

    func readChunks(chunkSize: Int, sink: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        while true {
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            guard !data.isEmpty else {
                break
            }
            try sink(data)
        }
    }

    private static func fileSize(_ url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
            throw SwitchTransferFileError.missing(url)
        }
        return UInt64(fileSize)
    }
}

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}

private extension UInt64 {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian, Array.init)
    }
}
