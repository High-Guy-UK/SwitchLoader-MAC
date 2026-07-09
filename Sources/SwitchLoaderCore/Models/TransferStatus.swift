import Foundation

public enum TransferStatus: Sendable, Equatable {
    case idle
    case running
    case completed
    case failed(String)
}

public enum TransferLogLevel: Sendable, Equatable {
    case info
    case success
    case warning
    case failure
}

public struct TransferLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let date: Date
    public let level: TransferLogLevel
    public let message: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: TransferLogLevel,
        message: String
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
    }
}
