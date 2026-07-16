import Darwin
import Foundation

final class NetworkFileServer {
    private let filesByEncodedName: [String: SwitchTransferFile]
    private let manifestPayload: Data?
    private let port: Int
    private let descriptor: Int32

    init(files: [SwitchTransferFile], port: Int, manifestPayload: Data? = nil) throws {
        self.filesByEncodedName = Dictionary(uniqueKeysWithValues: files.map { ($0.encodedName, $0) })
        self.manifestPayload = manifestPayload
        self.port = port
        self.descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    deinit {
        close(descriptor)
    }

    func start() throws {
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = INADDR_ANY.bigEndian
        address.sin_port = in_port_t(port).bigEndian

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
        }

        guard listen(descriptor, 8) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func serveUntilDrop(onEvent: @escaping @Sendable (NetworkInstallEvent) -> Void) throws {
        var shouldContinue = true
        while shouldContinue {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            defer {
                close(client)
            }

            let request = try readRequest(from: client)
            if request.method == "DROP" || request.path == "/__switchloader/drop" {
                try writeString(HTTPResponse.noContent(), to: client)
                shouldContinue = false
                continue
            }

            try handle(request: request, client: client, onEvent: onEvent)
        }
    }

    private func handle(
        request: HTTPRequest,
        client: Int32,
        onEvent: @escaping @Sendable (NetworkInstallEvent) -> Void
    ) throws {
        if request.method == "GET", request.isManifestRequest, let manifestPayload {
            try writeString(HTTPResponse.json(length: manifestPayload.count), to: client)
            try manifestPayload.withUnsafeBytes { buffer in
                try writeAll(buffer, to: client)
            }
            onEvent(.log(TransferLogEntry(level: .info, message: "Served receiver manifest.")))
            return
        }

        guard let encodedName = request.encodedFileName,
              let file = filesByEncodedName[encodedName],
              file.size > 0
        else {
            try writeString(HTTPResponse.notFound(), to: client)
            onEvent(.log(TransferLogEntry(level: .failure, message: "Requested file was not found.")))
            return
        }

        if request.method == "HEAD" {
            try writeString(HTTPResponse.ok(size: file.size), to: client)
            onEvent(.log(TransferLogEntry(level: .info, message: "Answered size check for \(file.url.lastPathComponent).")))
            return
        }

        guard request.method == "GET" else {
            try writeString(HTTPResponse.badRequest(), to: client)
            return
        }

        let range = request.range ?? (0, file.size - 1)
        guard range.start <= range.end, range.end < file.size else {
            try writeString(HTTPResponse.rangeNotSatisfiable(), to: client)
            onEvent(.log(TransferLogEntry(level: .failure, message: "Invalid range requested for \(file.url.lastPathComponent).")))
            return
        }

        try writeString(HTTPResponse.partialContent(size: file.size, start: range.start, end: range.end), to: client)
        var transferred: UInt64 = 0
        let total = range.end - range.start + 1
        try file.readRange(start: range.start, endInclusive: range.end) { data in
            try data.withUnsafeBytes { buffer in
                try writeAll(buffer, to: client)
            }
            transferred += UInt64(data.count)
            onEvent(.progress(Double(transferred) / Double(total)))
        }
        onEvent(.log(TransferLogEntry(level: .success, message: "Served \(file.url.lastPathComponent).")))
    }

    private func readRequest(from client: Int32) throws -> HTTPRequest {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            if count < 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
            if data.range(of: Data("\r\n\r\n".utf8)) != nil || data.range(of: Data("\n\n".utf8)) != nil {
                break
            }
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw NetworkInstallError.invalidHandshake
        }
        return HTTPRequest(rawValue: string)
    }

    private func writeString(_ string: String, to descriptor: Int32) throws {
        try Data(string.utf8).withUnsafeBytes { buffer in
            try writeAll(buffer, to: descriptor)
        }
    }

    private func writeAll(_ buffer: UnsafeRawBufferPointer, to descriptor: Int32) throws {
        guard let baseAddress = buffer.baseAddress else { return }
        var sent = 0
        while sent < buffer.count {
            let result = Darwin.send(descriptor, baseAddress.advanced(by: sent), buffer.count - sent, 0)
            if result < 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            sent += result
        }
    }
}

private struct HTTPRequest {
    let rawValue: String

    var lines: [String] {
        rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    var firstLine: String {
        lines.first ?? ""
    }

    var method: String {
        firstLine.split(separator: " ").first.map(String.init) ?? ""
    }

    var path: String {
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "" }
        return String(parts[1])
    }

    var isManifestRequest: Bool {
        path == "/manifest.json" || path == "/__switchloader/manifest.json"
    }

    var encodedFileName: String? {
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var path = String(parts[1])
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        if let queryIndex = path.firstIndex(of: "?") {
            path = String(path[..<queryIndex])
        }
        return path.split(separator: "/").last.map(String.init)
    }

    var range: (start: UInt64, end: UInt64)? {
        guard let header = lines.first(where: { $0.lowercased().hasPrefix("range:") }) else {
            return nil
        }
        let value = header
            .replacingOccurrences(of: "Range:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "bytes=", with: "", options: [.caseInsensitive])
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              let start = UInt64(pieces[0]),
              let end = UInt64(pieces[1])
        else {
            return nil
        }
        return (start, end)
    }
}

private enum HTTPResponse {
    static func json(length: Int) -> String {
        """
        HTTP/1.0 200 OK\r
        Server: SwitchLoader\r
        Date: \(date)\r
        Content-Type: application/json; charset=utf-8\r
        Cache-Control: no-store\r
        Content-Length: \(length)\r
        \r

        """
    }

    static func ok(size: UInt64) -> String {
        """
        HTTP/1.0 200 OK\r
        Server: SwitchLoader\r
        Date: \(date)\r
        Content-Type: application/octet-stream\r
        Accept-Ranges: bytes\r
        Content-Range: bytes 0-\(size - 1)/\(size)\r
        Content-Length: \(size)\r
        Last-Modified: Thu, 01 Jan 1970 00:00:00 GMT\r
        \r

        """
    }

    static func partialContent(size: UInt64, start: UInt64, end: UInt64) -> String {
        """
        HTTP/1.0 206 Partial Content\r
        Server: SwitchLoader\r
        Date: \(date)\r
        Content-Type: application/octet-stream\r
        Accept-Ranges: bytes\r
        Content-Range: bytes \(start)-\(end)/\(size)\r
        Content-Length: \(end - start + 1)\r
        Last-Modified: Thu, 01 Jan 1970 00:00:00 GMT\r
        \r

        """
    }

    static func badRequest() -> String {
        empty(status: "400 invalid range")
    }

    static func notFound() -> String {
        empty(status: "404 Not Found")
    }

    static func rangeNotSatisfiable() -> String {
        empty(status: "416 Requested Range Not Satisfiable")
    }

    static func noContent() -> String {
        empty(status: "204 No Content")
    }

    private static func empty(status: String) -> String {
        """
        HTTP/1.0 \(status)\r
        Server: SwitchLoader\r
        Date: \(date)\r
        Connection: close\r
        Content-Type: text/html;charset=utf-8\r
        Content-Length: 0\r
        \r

        """
    }

    private static var date: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}
