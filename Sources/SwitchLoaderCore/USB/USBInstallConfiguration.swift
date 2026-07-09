import Foundation

public struct USBInstallConfiguration: Sendable, Equatable {
    public var files: [URL]

    public init(files: [URL]) {
        self.files = files
    }
}

public enum USBInstallEvent: Sendable, Equatable {
    case log(TransferLogEntry)
    case progress(Double)
    case completed
}

public enum USBInstallError: LocalizedError, Equatable {
    case noFiles
    case deviceNotFound
    case openFailed(String)
    case configurationFailed(String)
    case claimFailed(String)
    case transferFailed(String)
    case unexpectedReply
    case requestedFileMissing(String)

    public var errorDescription: String? {
        switch self {
        case .noFiles:
            "Choose at least one XCI, NSP, NSZ, or split folder."
        case .deviceNotFound:
            "No compatible USB device was found. Open your installer on the device and set it to wait for USB files."
        case let .openFailed(message):
            "Could not open the USB device: \(message)"
        case let .configurationFailed(message):
            "Could not configure the USB device: \(message)"
        case let .claimFailed(message):
            "Could not claim the USB interface: \(message)"
        case let .transferFailed(message):
            "USB transfer failed: \(message)"
        case .unexpectedReply:
            "The device sent an unexpected USB reply."
        case let .requestedFileMissing(name):
            "The device requested a file that is not selected: \(name)"
        }
    }
}
