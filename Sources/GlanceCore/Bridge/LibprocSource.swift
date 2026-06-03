import Darwin

/// 列舉所有 pid,讀取各程式累計 CPU 時間與記憶體足跡。取樣中消失的 pid 直接略過。
public struct LibprocSource: RawProcessSource {
    public init() {}

    public func read() -> [RawProcess]? {
        let maxPids = proc_listallpids(nil, 0)
        guard maxPids > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(maxPids))
        let count = proc_listallpids(&pids, maxPids * Int32(MemoryLayout<pid_t>.size))
        guard count > 0 else { return nil }

        var result: [RawProcess] = []
        result.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            guard let proc = Self.rawProcess(pid: pid) else { continue }
            result.append(proc)
        }
        return result
    }

    private static func rawProcess(pid: pid_t) -> RawProcess? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard rc == 0 else { return nil }

        // ri_user_time / ri_system_time 為奈秒累計
        let cpuSeconds = Double(info.ri_user_time + info.ri_system_time) / 1_000_000_000
        let memory = info.ri_phys_footprint

        var nameBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let nameLen = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
        let name = nameLen > 0 ? String(cString: nameBuf) : "pid \(pid)"

        return RawProcess(pid: pid, name: name, cpuTimeSeconds: cpuSeconds, memoryBytes: memory)
    }
}
