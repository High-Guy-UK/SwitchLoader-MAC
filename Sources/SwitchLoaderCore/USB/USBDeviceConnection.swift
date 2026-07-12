import CLibUSB
import Foundation

final class USBDeviceConnection {
    private static let homebrewVendorID: UInt16 = 0x057E
    private static let homebrewProductID: UInt16 = 0x3000
    private static let rcmVendorID: UInt16 = 0x0955
    private static let rcmProductID: UInt16 = 0x7321
    private static let configuration: Int32 = 1
    private static let interfaceNumber: Int32 = 0

    private var context: OpaquePointer?
    private var handle: OpaquePointer?
    private var interfaceClaimed = false

    deinit {
        close()
    }

    func openHomebrewDevice() throws {
        try openDevice(
            vendorID: Self.homebrewVendorID,
            productID: Self.homebrewProductID,
            notFoundMessage: USBInstallError.deviceNotFound
        )
    }

    func openRCMDevice() throws {
        try openDevice(
            vendorID: Self.rcmVendorID,
            productID: Self.rcmProductID,
            notFoundMessage: RCMPayloadError.deviceNotFound
        )
    }

    private func openDevice(vendorID: UInt16, productID: UInt16, notFoundMessage: Error) throws {
        var contextPointer: OpaquePointer?
        let initResult = libusb_init(&contextPointer)
        guard initResult == LIBUSB_SUCCESS.rawValue, let contextPointer else {
            throw USBInstallError.openFailed(Self.errorName(initResult))
        }
        context = contextPointer

        handle = libusb_open_device_with_vid_pid(
            contextPointer,
            vendorID,
            productID
        )
        guard let handle else {
            throw notFoundMessage
        }

        _ = libusb_set_auto_detach_kernel_driver(handle, 1)

        let configResult = libusb_set_configuration(handle, Self.configuration)
        guard configResult == LIBUSB_SUCCESS.rawValue || configResult == LIBUSB_ERROR_BUSY.rawValue else {
            throw USBInstallError.configurationFailed(Self.errorName(configResult))
        }

        let claimResult = libusb_claim_interface(handle, Self.interfaceNumber)
        guard claimResult == LIBUSB_SUCCESS.rawValue else {
            throw USBInstallError.claimFailed(Self.errorName(claimResult))
        }
        interfaceClaimed = true
    }

    func bulkWrite(endpoint: UInt8, data: Data, timeout: UInt32 = 5_050) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var transferred: Int32 = 0
            let result = libusb_bulk_transfer(
                handle,
                endpoint,
                UnsafeMutablePointer(mutating: baseAddress.assumingMemoryBound(to: UInt8.self)),
                Int32(data.count),
                &transferred,
                timeout
            )
            guard result == LIBUSB_SUCCESS.rawValue, transferred == data.count else {
                throw USBInstallError.transferFailed("\(Self.errorName(result)); requested \(data.count), transferred \(transferred)")
            }
        }
    }

    func bulkRead(endpoint: UInt8, maxLength: Int = 512, timeout: UInt32 = 1_000) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        var transferred: Int32 = 0

        let result = libusb_bulk_transfer(
            handle,
            endpoint,
            &buffer,
            Int32(buffer.count),
            &transferred,
            timeout
        )

        if result == LIBUSB_ERROR_TIMEOUT.rawValue {
            return Data()
        }

        guard result == LIBUSB_SUCCESS.rawValue else {
            throw USBInstallError.transferFailed(Self.errorName(result))
        }

        return Data(buffer.prefix(Int(transferred)))
    }

    func controlRead(
        requestType: UInt8,
        request: UInt8,
        value: UInt16,
        index: UInt16,
        length: Int,
        timeout: UInt32 = 1_000
    ) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: length)
        let result = libusb_control_transfer(
            handle,
            requestType,
            request,
            value,
            index,
            &buffer,
            UInt16(length),
            timeout
        )

        guard result >= 0 else {
            throw USBInstallError.transferFailed(Self.errorName(result))
        }

        return Data(buffer.prefix(Int(result)))
    }

    func close() {
        if let handle {
            if interfaceClaimed {
                libusb_release_interface(handle, Self.interfaceNumber)
            }
            libusb_close(handle)
        }
        if let context {
            libusb_exit(context)
        }
        handle = nil
        context = nil
        interfaceClaimed = false
    }

    private static func errorName(_ code: Int32) -> String {
        String(cString: libusb_error_name(code))
    }
}
