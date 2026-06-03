import Darwin

/// 加總所有非 loopback 介面的 if_data 位元組計數。
public struct InterfaceCountersSource: NetworkCountersSource {
    public init() {}

    public func read() -> NetworkCounters? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let addr = cur.pointee.ifa_addr
            // 只看 AF_LINK(連結層)層級的統計
            if let a = addr, a.pointee.sa_family == UInt8(AF_LINK),
               let dataPtr = cur.pointee.ifa_data {
                let name = String(cString: cur.pointee.ifa_name)
                if !name.hasPrefix("lo") {
                    let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(data.ifi_ibytes)
                    totalOut += UInt64(data.ifi_obytes)
                }
            }
            ptr = cur.pointee.ifa_next
        }
        return NetworkCounters(received: totalIn, sent: totalOut)
    }
}
