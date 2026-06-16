import Foundation
import IOKit

/// 列舉所有實體磁碟(IOBlockStorageDriver),加總累計讀/寫位元組。
public struct IOBlockStorageIOSource: DiskIOStatsSource {
    public init() {}

    public func read() -> DiskIOCounters? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var found = false

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = statistics(of: service) {
                // 鍵名對應 IOBlockStorageDriver.h 的 kIOBlockStorageDriverStatisticsBytesRead/WriteKey
                // (IOKit 字串常數,非公開匯出,故以字面值取值;缺鍵則該磁碟略過)。
                if let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value {
                    totalRead += r; found = true
                }
                if let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                    totalWrite += w; found = true
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return found ? DiskIOCounters(readBytes: totalRead, writeBytes: totalWrite) : nil
    }

    /// 取出某 driver 的 Statistics 子字典(找不到回 nil)。
    private func statistics(of service: io_object_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict["Statistics"] as? [String: Any]
    }
}
