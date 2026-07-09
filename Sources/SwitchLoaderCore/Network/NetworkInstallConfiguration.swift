import Foundation

public struct NetworkInstallConfiguration: Sendable, Equatable {
    public var files: [URL]
    public var switchIPAddress: String
    public var hostIPAddress: String?
    public var hostPort: Int
    public var remotePathPrefix: String
    public var serveRequests: Bool

    public init(
        files: [URL],
        switchIPAddress: String,
        hostIPAddress: String? = nil,
        hostPort: Int = 6060,
        remotePathPrefix: String = "",
        serveRequests: Bool = true
    ) {
        self.files = files
        self.switchIPAddress = switchIPAddress
        self.hostIPAddress = hostIPAddress
        self.hostPort = hostPort
        self.remotePathPrefix = remotePathPrefix
        self.serveRequests = serveRequests
    }
}

public enum NetworkInstallEvent: Sendable, Equatable {
    case log(TransferLogEntry)
    case progress(Double)
    case completed
}
