import CLibUSB
import Foundation

struct USBBulkEndpoints {
    let inEndpoint: UInt8
    let outEndpoint: UInt8
}

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

    static func rcmDeviceExists() -> Bool {
        deviceExists(vendorID: rcmVendorID, productID: rcmProductID)
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

    private static func deviceExists(vendorID: UInt16, productID: UInt16) -> Bool {
        var contextPointer: OpaquePointer?
        let initResult = libusb_init(&contextPointer)
        guard initResult == LIBUSB_SUCCESS.rawValue, let contextPointer else {
            return false
        }
        defer {
            libusb_exit(contextPointer)
        }

        var deviceList: UnsafeMutablePointer<OpaquePointer?>?
        let deviceCount = libusb_get_device_list(contextPointer, &deviceList)
        guard deviceCount > 0, let deviceList else {
            return false
        }
        defer {
            libusb_free_device_list(deviceList, 1)
        }

        for index in 0..<Int(deviceCount) {
            guard let device = deviceList[index] else { continue }

            var descriptor = libusb_device_descriptor()
            let descriptorResult = libusb_get_device_descriptor(device, &descriptor)
            guard descriptorResult == LIBUSB_SUCCESS.rawValue else { continue }

            if descriptor.idVendor == vendorID && descriptor.idProduct == productID {
                return true
            }
        }

        return false
    }

    func bulkWrite(endpoint: UInt8, data: Data, timeout: UInt32 = 5_050) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var offset = 0
            var lastProgress = Date()
            let stallLimit: TimeInterval = 15

            while offset < data.count {
                var transferred: Int32 = 0
                let remaining = data.count - offset
                let result = libusb_bulk_transfer(
                    handle,
                    endpoint,
                    UnsafeMutablePointer(mutating: baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)),
                    Int32(remaining),
                    &transferred,
                    timeout
                )

                if transferred > 0 {
                    offset += Int(transferred)
                    lastProgress = Date()
                }

                if result == LIBUSB_SUCCESS.rawValue {
                    if transferred == 0, Date().timeIntervalSince(lastProgress) > stallLimit {
                        throw USBInstallError.transferFailed("\(Self.errorName(result)); requested \(remaining), transferred \(transferred)")
                    }
                    if transferred == 0 {
                        Thread.sleep(forTimeInterval: 0.002)
                    }
                    continue
                }

                if result == LIBUSB_ERROR_TIMEOUT.rawValue, Date().timeIntervalSince(lastProgress) <= stallLimit {
                    Thread.sleep(forTimeInterval: 0.002)
                    continue
                }

                if result == LIBUSB_ERROR_TIMEOUT.rawValue, transferred > 0 {
                    continue
                } else {
                    throw USBInstallError.transferFailed("\(Self.errorName(result)); requested \(remaining), transferred \(transferred)")
                }
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

    func bulkEndpoints() -> USBBulkEndpoints? {
        guard let handle, let device = libusb_get_device(handle) else {
            return nil
        }

        var configPointer: UnsafeMutablePointer<libusb_config_descriptor>?
        let result = libusb_get_active_config_descriptor(device, &configPointer)
        guard result == LIBUSB_SUCCESS.rawValue, let configPointer else {
            return nil
        }
        defer {
            libusb_free_config_descriptor(configPointer)
        }

        let config = configPointer.pointee
        var inEndpoint: UInt8?
        var outEndpoint: UInt8?

        for interfaceIndex in 0..<Int(config.bNumInterfaces) {
            let interface = config.interface[interfaceIndex]
            for alternateIndex in 0..<Int(interface.num_altsetting) {
                let alternate = interface.altsetting[alternateIndex]
                for endpointIndex in 0..<Int(alternate.bNumEndpoints) {
                    let endpoint = alternate.endpoint[endpointIndex]
                    let transferType = endpoint.bmAttributes & 0x03
                    guard transferType == 0x02 else { continue }

                    if endpoint.bEndpointAddress & 0x80 == 0x80 {
                        inEndpoint = endpoint.bEndpointAddress
                    } else {
                        outEndpoint = endpoint.bEndpointAddress
                    }

                    if let inEndpoint, let outEndpoint {
                        return USBBulkEndpoints(inEndpoint: inEndpoint, outEndpoint: outEndpoint)
                    }
                }
            }
        }

        guard let inEndpoint, let outEndpoint else {
            return nil
        }
        return USBBulkEndpoints(inEndpoint: inEndpoint, outEndpoint: outEndpoint)
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
