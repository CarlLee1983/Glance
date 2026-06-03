import Darwin

/// 透過 host_statistics64(HOST_VM_INFO64) + sysctl(hw.memsize) 讀取記憶體狀態。
public struct MachMemorySource: MemoryStatsSource {
    public init() {}

    public func read() -> MemoryStats? {
        guard let total = Self.physicalMemory() else { return nil }
        guard let vm = Self.vmStatistics() else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        // 已用 ≈ active + wired + compressed(以 page 計)
        let used = (UInt64(vm.active_count)
            + UInt64(vm.wire_count)
            + UInt64(vm.compressor_page_count)) * pageSize

        let swap = Self.swapUsedBytes() ?? 0
        let clampedUsed = min(used, total)
        let pressure = MemoryPressure.evaluate(usedBytes: clampedUsed, totalBytes: total, swapUsedBytes: swap)

        return MemoryStats(
            totalBytes: total,
            usedBytes: clampedUsed,
            swapUsedBytes: swap,
            pressure: pressure)
    }

    private static func physicalMemory() -> UInt64? {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        let rc = sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return rc == 0 ? size : nil
    }

    private static func vmStatistics() -> vm_statistics64? {
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? stats : nil
    }

    private static func swapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var len = MemoryLayout<xsw_usage>.size
        let rc = sysctlbyname("vm.swapusage", &usage, &len, nil, 0)
        return rc == 0 ? usage.xsu_used : nil
    }


}
