import Darwin
import Foundation

enum IPv4AddressResolver {
    static func localAddress() throws -> String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            throw NetworkInstallError.noLocalIPAddress
        }
        defer {
            freeifaddrs(interfaces)
        }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer {
                cursor = current.pointee.ifa_next
            }

            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp, !isLoopback, let address = current.pointee.ifa_addr else {
                continue
            }
            guard address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let endIndex = hostname.firstIndex(of: 0) ?? hostname.endIndex
                return String(decoding: hostname[..<endIndex].map(UInt8.init(bitPattern:)), as: UTF8.self)
            }
        }

        throw NetworkInstallError.noLocalIPAddress
    }
}
