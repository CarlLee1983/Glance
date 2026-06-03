# GlanceCore 資料層 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 `GlanceCore` Swift Package:取得 macOS 主機 CPU/記憶體/網路/磁碟/電池/Top 程式狀態的純資料層,並附一個 `glance-cli` 可一次性印出狀態。

**Architecture:** 純 Swift + 系統框架(Mach / IOKit / libproc),零第三方依賴。每個指標一個 `Sampler`,差值指標(CPU、網路、程式 CPU%)透過注入的「raw source」protocol 取得原始計數,使差值數學可單元測試;真實系統讀取集中在 `Bridge/` 層,由 `glance-cli` 實機 smoke test 涵蓋。

**Tech Stack:** Swift 5.9、Swift Package Manager、XCTest、Darwin(Mach host_statistics / getifaddrs / statfs / IOKit IOPowerSources / libproc)。

---

## File Structure

```
Glance/
├─ Package.swift
├─ Sources/
│  ├─ GlanceCore/
│  │  ├─ Model/
│  │  │  ├─ CPUSnapshot.swift          不可變 struct + 原始計數型別
│  │  │  ├─ MemorySnapshot.swift
│  │  │  ├─ NetworkSnapshot.swift
│  │  │  ├─ DiskSnapshot.swift
│  │  │  ├─ BatterySnapshot.swift
│  │  │  └─ ProcessUsage.swift
│  │  ├─ Sampling/
│  │  │  ├─ CPUSampler.swift
│  │  │  ├─ MemorySampler.swift
│  │  │  ├─ NetworkSampler.swift
│  │  │  ├─ DiskSampler.swift
│  │  │  ├─ BatterySampler.swift
│  │  │  └─ ProcessSampler.swift
│  │  ├─ Bridge/                        ← 低階系統讀取集中於此
│  │  │  ├─ MachCPUSource.swift
│  │  │  ├─ MachMemorySource.swift
│  │  │  ├─ InterfaceCountersSource.swift
│  │  │  ├─ StatfsDiskSource.swift
│  │  │  ├─ IOKitBatterySource.swift
│  │  │  └─ LibprocSource.swift
│  │  ├─ History/
│  │  │  └─ RingBuffer.swift
│  │  ├─ Format/
│  │  │  └─ Formatters.swift
│  │  └─ SystemSnapshot.swift           聚合一次取樣的所有指標
│  └─ glance-cli/
│     └─ main.swift                     一次性印出 SystemSnapshot
└─ Tests/
   └─ GlanceCoreTests/
      ├─ RingBufferTests.swift
      ├─ FormattersTests.swift
      ├─ CPUSamplerTests.swift
      ├─ NetworkSamplerTests.swift
      ├─ MemorySamplerTests.swift
      └─ ProcessSamplerTests.swift
```

**Naming contract**(後續任務一律沿用):
- 百分比一律用 `Double` 的「分數」`0...1`(非 0~100),格式化時才乘 100。
- 原始計數型別命名:`CPUTicks`、`NetworkCounters`、`MemoryStats`、`DiskStats`、`BatteryStats`、`RawProcess`。
- source protocol 一律 `func read() -> X?`(失敗回 `nil`)。

---

## Task 0:Scaffold Swift Package 與 git

**Files:**
- Create: `Package.swift`
- Create: `Sources/GlanceCore/Placeholder.swift`(暫時讓 target 可編譯,Task 1 移除)
- Create: `Sources/glance-cli/main.swift`(暫時)
- Create: `Tests/GlanceCoreTests/SmokeTests.swift`(暫時)

- [ ] **Step 1:建立 Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlanceCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
        .executable(name: "glance-cli", targets: ["glance-cli"]),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "glance-cli", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ]
)
```

- [ ] **Step 2:建立暫時佔位檔讓三個 target 可編譯**

`Sources/GlanceCore/Placeholder.swift`:
```swift
// 暫時佔位,Task 1 起以實際型別取代。
public enum GlanceCore {}
```

`Sources/glance-cli/main.swift`:
```swift
import GlanceCore

print("glance-cli scaffold ok")
```

`Tests/GlanceCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import GlanceCore

final class SmokeTests: XCTestCase {
    func testScaffoldCompiles() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3:驗證可編譯與測試**

Run: `swift test`
Expected: PASS(1 test,`testScaffoldCompiles`)

- [ ] **Step 4:Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: [glance] scaffold GlanceCore Swift Package"
```

---

## Task 1:RingBuffer(歷史環形緩衝)

**Files:**
- Create: `Sources/GlanceCore/History/RingBuffer.swift`
- Test: `Tests/GlanceCoreTests/RingBufferTests.swift`
- Delete: `Sources/GlanceCore/Placeholder.swift`

- [ ] **Step 1:寫失敗測試**

`Tests/GlanceCoreTests/RingBufferTests.swift`:
```swift
import XCTest
@testable import GlanceCore

final class RingBufferTests: XCTestCase {
    func testAppendBelowCapacityKeepsOrder() {
        var rb = RingBuffer<Int>(capacity: 3)
        rb.append(1); rb.append(2)
        XCTAssertEqual(rb.elements, [1, 2])
    }

    func testAppendBeyondCapacityDropsOldest() {
        var rb = RingBuffer<Int>(capacity: 3)
        [1, 2, 3, 4, 5].forEach { rb.append($0) }
        XCTAssertEqual(rb.elements, [3, 4, 5])
    }

    func testCapacityOneKeepsLatest() {
        var rb = RingBuffer<Int>(capacity: 1)
        rb.append(7); rb.append(9)
        XCTAssertEqual(rb.elements, [9])
    }

    func testEmptyStartsEmpty() {
        let rb = RingBuffer<Int>(capacity: 3)
        XCTAssertEqual(rb.elements, [])
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter RingBufferTests`
Expected: FAIL(`cannot find 'RingBuffer' in scope`)

- [ ] **Step 3:刪除佔位檔並實作 RingBuffer**

先刪 `Sources/GlanceCore/Placeholder.swift`。

`Sources/GlanceCore/History/RingBuffer.swift`:
```swift
/// 固定容量的環形緩衝,超出容量時丟棄最舊元素。供歷史曲線使用。
public struct RingBuffer<Element> {
    public let capacity: Int
    private var storage: [Element] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be > 0")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public mutating func append(_ element: Element) {
        storage.append(element)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    /// 由舊到新排列的元素快照。
    public var elements: [Element] { storage }

    public var last: Element? { storage.last }
    public var isEmpty: Bool { storage.isEmpty }
}
```

- [ ] **Step 4:跑測試確認通過**

Run: `swift test --filter RingBufferTests`
Expected: PASS(4 tests)

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/History/RingBuffer.swift Tests/GlanceCoreTests/RingBufferTests.swift
git rm Sources/GlanceCore/Placeholder.swift
git commit -m "feat: [glance] add RingBuffer for metric history"
```

---

## Task 2:格式化工具(bytes / 百分比 / 速率)

**Files:**
- Create: `Sources/GlanceCore/Format/Formatters.swift`
- Test: `Tests/GlanceCoreTests/FormattersTests.swift`

- [ ] **Step 1:寫失敗測試**

`Tests/GlanceCoreTests/FormattersTests.swift`:
```swift
import XCTest
@testable import GlanceCore

final class FormattersTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(Formatters.percent(0.234), "23%")
        XCTAssertEqual(Formatters.percent(0), "0%")
        XCTAssertEqual(Formatters.percent(1), "100%")
    }

    func testBytesGB() {
        // 9.8 GB(以 1024 為基底)
        XCTAssertEqual(Formatters.bytes(10_522_669_875), "9.8 GB")
    }

    func testBytesMB() {
        XCTAssertEqual(Formatters.bytes(5_242_880), "5.0 MB")
    }

    func testRateCompact() {
        // 2.1 MB/s 的常駐列精簡字串
        XCTAssertEqual(Formatters.rateCompact(2_202_009), "2.1M")
        XCTAssertEqual(Formatters.rateCompact(3072), "3.0K")
        XCTAssertEqual(Formatters.rateCompact(0), "0")
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter FormattersTests`
Expected: FAIL(`cannot find 'Formatters' in scope`)

- [ ] **Step 3:實作 Formatters**

`Sources/GlanceCore/Format/Formatters.swift`:
```swift
import Foundation

/// 集中所有人類可讀字串轉換,純函式、可測試。
public enum Formatters {
    /// 0...1 分數 → "23%"。
    public static func percent(_ fraction: Double) -> String {
        let clamped = max(0, min(1, fraction))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// 位元組 → "9.8 GB" / "5.0 MB"(1024 基底,一位小數)。
    public static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(value)
        var idx = 0
        while v >= 1024 && idx < units.count - 1 {
            v /= 1024
            idx += 1
        }
        if idx == 0 {
            return "\(Int(v)) B"
        }
        return String(format: "%.1f %@", v, units[idx])
    }

    /// 速率(bytes/sec)→ 選單列精簡字串 "2.1M" / "3.0K" / "0"。
    public static func rateCompact(_ bytesPerSec: Double) -> String {
        let v = max(0, bytesPerSec)
        if v < 1 { return "0" }
        if v < 1024 { return String(format: "%.0f", v) }
        if v < 1024 * 1024 { return String(format: "%.1fK", v / 1024) }
        return String(format: "%.1fM", v / (1024 * 1024))
    }
}
```

- [ ] **Step 4:跑測試確認通過**

Run: `swift test --filter FormattersTests`
Expected: PASS(4 tests)

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/Format/Formatters.swift Tests/GlanceCoreTests/FormattersTests.swift
git commit -m "feat: [glance] add human-readable formatters"
```

---

## Task 3:CPU 模型、Sampler 與 Mach 來源

**Files:**
- Create: `Sources/GlanceCore/Model/CPUSnapshot.swift`
- Create: `Sources/GlanceCore/Sampling/CPUSampler.swift`
- Create: `Sources/GlanceCore/Bridge/MachCPUSource.swift`
- Test: `Tests/GlanceCoreTests/CPUSamplerTests.swift`

- [ ] **Step 1:寫失敗測試(差值數學)**

`Tests/GlanceCoreTests/CPUSamplerTests.swift`:
```swift
import XCTest
@testable import GlanceCore

private final class StubCPUSource: CPUTicksSource {
    var queue: [CPUTicks]
    init(_ q: [CPUTicks]) { queue = q }
    func read() -> CPUTicks? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class CPUSamplerTests: XCTestCase {
    func testFirstSampleIsZero() {
        let src = StubCPUSource([CPUTicks(user: 100, system: 50, idle: 850, nice: 0)])
        let sampler = CPUSampler(source: src)
        let snap = sampler.sample()
        XCTAssertEqual(snap?.totalUsage, 0)
    }

    func testSecondSampleComputesUsageFromDelta() {
        // delta: user+50, system+20, idle+930, nice+0 → total 1000, busy 70 → 7%
        let src = StubCPUSource([
            CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            CPUTicks(user: 150, system: 70, idle: 1780, nice: 0),
        ])
        let sampler = CPUSampler(source: src)
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertEqual(snap?.totalUsage ?? -1, 0.07, accuracy: 0.0001)
        XCTAssertEqual(snap?.system ?? -1, 0.02, accuracy: 0.0001)
    }

    func testReturnsNilWhenSourceFails() {
        let src = StubCPUSource([])
        XCTAssertNil(CPUSampler(source: src).sample())
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter CPUSamplerTests`
Expected: FAIL(`cannot find 'CPUTicks' / 'CPUSampler' in scope`)

- [ ] **Step 3:實作模型**

`Sources/GlanceCore/Model/CPUSnapshot.swift`:
```swift
/// CPU 原始累計 ticks(host_statistics HOST_CPU_LOAD_INFO 對應欄位)。
public struct CPUTicks: Equatable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

/// 一次取樣的 CPU 使用情形,百分比為 0...1 分數。
public struct CPUSnapshot: Equatable {
    public let totalUsage: Double  // user+system+nice 佔比
    public let user: Double        // 含 nice
    public let system: Double
    public let idle: Double
    public init(totalUsage: Double, user: Double, system: Double, idle: Double) {
        self.totalUsage = totalUsage; self.user = user; self.system = system; self.idle = idle
    }

    public static let zero = CPUSnapshot(totalUsage: 0, user: 0, system: 0, idle: 1)
}

/// 提供 CPU 原始 ticks 的來源(可注入測試替身)。
public protocol CPUTicksSource {
    func read() -> CPUTicks?
}
```

- [ ] **Step 4:實作 Sampler**

`Sources/GlanceCore/Sampling/CPUSampler.swift`:
```swift
/// 以兩次 ticks 的差值計算 CPU 使用率。第一次取樣無前值 → 回傳 zero。
public final class CPUSampler {
    private let source: CPUTicksSource
    private var previous: CPUTicks?

    public init(source: CPUTicksSource) {
        self.source = source
    }

    public func sample() -> CPUSnapshot? {
        guard let now = source.read() else { return nil }
        defer { previous = now }
        guard let prev = previous else { return .zero }

        let dUser = Double(now.user &- prev.user)
        let dSystem = Double(now.system &- prev.system)
        let dIdle = Double(now.idle &- prev.idle)
        let dNice = Double(now.nice &- prev.nice)
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return .zero }

        let busy = dUser + dSystem + dNice
        return CPUSnapshot(
            totalUsage: busy / total,
            user: (dUser + dNice) / total,
            system: dSystem / total,
            idle: dIdle / total
        )
    }
}
```

- [ ] **Step 5:跑測試確認通過**

Run: `swift test --filter CPUSamplerTests`
Expected: PASS(3 tests)

- [ ] **Step 6:實作真實 Mach 來源(實機 smoke,非單元測試)**

`Sources/GlanceCore/Bridge/MachCPUSource.swift`:
```swift
import Darwin

/// 透過 host_statistics(HOST_CPU_LOAD_INFO) 讀取整機 CPU ticks。
public struct MachCPUSource: CPUTicksSource {
    public init() {}

    public func read() -> CPUTicks? {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        // cpu_ticks 索引:0=USER, 1=SYSTEM, 2=IDLE, 3=NICE
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }
}
```

- [ ] **Step 7:Commit**

```bash
git add Sources/GlanceCore/Model/CPUSnapshot.swift Sources/GlanceCore/Sampling/CPUSampler.swift Sources/GlanceCore/Bridge/MachCPUSource.swift Tests/GlanceCoreTests/CPUSamplerTests.swift
git commit -m "feat: [glance] add CPU snapshot, sampler and Mach source"
```

---

## Task 4:記憶體模型、Sampler 與 Mach 來源

**Files:**
- Create: `Sources/GlanceCore/Model/MemorySnapshot.swift`
- Create: `Sources/GlanceCore/Sampling/MemorySampler.swift`
- Create: `Sources/GlanceCore/Bridge/MachMemorySource.swift`
- Test: `Tests/GlanceCoreTests/MemorySamplerTests.swift`

- [ ] **Step 1:寫失敗測試**

`Tests/GlanceCoreTests/MemorySamplerTests.swift`:
```swift
import XCTest
@testable import GlanceCore

private struct StubMemorySource: MemoryStatsSource {
    let stats: MemoryStats?
    func read() -> MemoryStats? { stats }
}

final class MemorySamplerTests: XCTestCase {
    func testSnapshotComputesUsedFraction() {
        let stats = MemoryStats(
            totalBytes: 16_000_000_000,
            usedBytes: 9_760_000_000,
            swapUsedBytes: 200_000_000,
            pressure: .normal)
        let snap = MemorySampler(source: StubMemorySource(stats: stats)).sample()
        XCTAssertEqual(snap?.usedFraction ?? -1, 0.61, accuracy: 0.001)
        XCTAssertEqual(snap?.pressure, .normal)
    }

    func testReturnsNilWhenSourceFails() {
        XCTAssertNil(MemorySampler(source: StubMemorySource(stats: nil)).sample())
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter MemorySamplerTests`
Expected: FAIL(`cannot find 'MemoryStats' in scope`)

- [ ] **Step 3:實作模型**

`Sources/GlanceCore/Model/MemorySnapshot.swift`:
```swift
public enum MemoryPressure: String, Equatable {
    case normal, warning, critical
}

/// 記憶體原始統計(已換算為位元組)。
public struct MemoryStats: Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressure: MemoryPressure
    public init(totalBytes: UInt64, usedBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes
        self.swapUsedBytes = swapUsedBytes; self.pressure = pressure
    }
}

public struct MemorySnapshot: Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressure: MemoryPressure
    public init(usedBytes: UInt64, totalBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = usedBytes; self.totalBytes = totalBytes
        self.swapUsedBytes = swapUsedBytes; self.pressure = pressure
    }
    public var usedFraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

public protocol MemoryStatsSource {
    func read() -> MemoryStats?
}
```

- [ ] **Step 4:實作 Sampler**

`Sources/GlanceCore/Sampling/MemorySampler.swift`:
```swift
/// 記憶體非差值指標,直接把 raw stats 轉成 snapshot。
public final class MemorySampler {
    private let source: MemoryStatsSource
    public init(source: MemoryStatsSource) { self.source = source }

    public func sample() -> MemorySnapshot? {
        guard let s = source.read() else { return nil }
        return MemorySnapshot(
            usedBytes: s.usedBytes,
            totalBytes: s.totalBytes,
            swapUsedBytes: s.swapUsedBytes,
            pressure: s.pressure)
    }
}
```

- [ ] **Step 5:跑測試確認通過**

Run: `swift test --filter MemorySamplerTests`
Expected: PASS(2 tests)

- [ ] **Step 6:實作真實 Mach 來源**

`Sources/GlanceCore/Bridge/MachMemorySource.swift`:
```swift
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
        let pressure: MemoryPressure = Self.pressure()

        return MemoryStats(
            totalBytes: total,
            usedBytes: min(used, total),
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

    /// 以 vm.memory_pressure 概略判斷;失敗則回 normal。
    private static func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var len = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, nil, 0) == 0 else {
            return .normal
        }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
```

- [ ] **Step 7:Commit**

```bash
git add Sources/GlanceCore/Model/MemorySnapshot.swift Sources/GlanceCore/Sampling/MemorySampler.swift Sources/GlanceCore/Bridge/MachMemorySource.swift Tests/GlanceCoreTests/MemorySamplerTests.swift
git commit -m "feat: [glance] add memory snapshot, sampler and Mach source"
```

---

## Task 5:網路模型、Sampler 與介面來源

**Files:**
- Create: `Sources/GlanceCore/Model/NetworkSnapshot.swift`
- Create: `Sources/GlanceCore/Sampling/NetworkSampler.swift`
- Create: `Sources/GlanceCore/Bridge/InterfaceCountersSource.swift`
- Test: `Tests/GlanceCoreTests/NetworkSamplerTests.swift`

- [ ] **Step 1:寫失敗測試(速率 = 位元組差值 ÷ 時間)**

`Tests/GlanceCoreTests/NetworkSamplerTests.swift`:
```swift
import XCTest
@testable import GlanceCore

private final class StubNetSource: NetworkCountersSource {
    var queue: [NetworkCounters]
    init(_ q: [NetworkCounters]) { queue = q }
    func read() -> NetworkCounters? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class NetworkSamplerTests: XCTestCase {
    func testFirstSampleHasZeroRate() {
        let src = StubNetSource([NetworkCounters(received: 1000, sent: 500)])
        var t = 0.0
        let snap = NetworkSampler(source: src, clock: { t }).sample()
        XCTAssertEqual(snap?.downBytesPerSec, 0)
        XCTAssertEqual(snap?.totalDownBytes, 1000)
    }

    func testSecondSampleComputesRate() {
        // +4_194_304 bytes 收 / 2 秒 = 2_097_152 B/s(2 MB/s)
        let src = StubNetSource([
            NetworkCounters(received: 1000, sent: 500),
            NetworkCounters(received: 1000 + 4_194_304, sent: 500 + 1_048_576),
        ])
        var times = [0.0, 2.0]
        let sampler = NetworkSampler(source: src, clock: { times.removeFirst() })
        _ = sampler.sample()
        let snap = sampler.sample()
        XCTAssertEqual(snap?.downBytesPerSec ?? -1, 2_097_152, accuracy: 1)
        XCTAssertEqual(snap?.upBytesPerSec ?? -1, 524_288, accuracy: 1)
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter NetworkSamplerTests`
Expected: FAIL(`cannot find 'NetworkCounters' in scope`)

- [ ] **Step 3:實作模型**

`Sources/GlanceCore/Model/NetworkSnapshot.swift`:
```swift
/// 介面累計位元組數(自開機起)。
public struct NetworkCounters: Equatable {
    public let received: UInt64
    public let sent: UInt64
    public init(received: UInt64, sent: UInt64) {
        self.received = received; self.sent = sent
    }
}

public struct NetworkSnapshot: Equatable {
    public let downBytesPerSec: Double
    public let upBytesPerSec: Double
    public let totalDownBytes: UInt64
    public let totalUpBytes: UInt64
    public init(downBytesPerSec: Double, upBytesPerSec: Double, totalDownBytes: UInt64, totalUpBytes: UInt64) {
        self.downBytesPerSec = downBytesPerSec; self.upBytesPerSec = upBytesPerSec
        self.totalDownBytes = totalDownBytes; self.totalUpBytes = totalUpBytes
    }
}

public protocol NetworkCountersSource {
    func read() -> NetworkCounters?
}
```

- [ ] **Step 4:實作 Sampler**

`Sources/GlanceCore/Sampling/NetworkSampler.swift`:
```swift
import Foundation

/// 以兩次累計位元組差值 ÷ 經過時間計算上/下載速率。clock 可注入以便測試。
public final class NetworkSampler {
    private let source: NetworkCountersSource
    private let clock: () -> TimeInterval
    private var previous: (counters: NetworkCounters, time: TimeInterval)?

    public init(source: NetworkCountersSource, clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.source = source
        self.clock = clock
    }

    public func sample() -> NetworkSnapshot? {
        guard let now = source.read() else { return nil }
        let t = clock()
        defer { previous = (now, t) }
        guard let prev = previous else {
            return NetworkSnapshot(downBytesPerSec: 0, upBytesPerSec: 0,
                                   totalDownBytes: now.received, totalUpBytes: now.sent)
        }
        let dt = t - prev.time
        guard dt > 0 else {
            return NetworkSnapshot(downBytesPerSec: 0, upBytesPerSec: 0,
                                   totalDownBytes: now.received, totalUpBytes: now.sent)
        }
        let down = Double(now.received &- prev.counters.received) / dt
        let up = Double(now.sent &- prev.counters.sent) / dt
        return NetworkSnapshot(downBytesPerSec: down, upBytesPerSec: up,
                               totalDownBytes: now.received, totalUpBytes: now.sent)
    }
}
```

- [ ] **Step 5:跑測試確認通過**

Run: `swift test --filter NetworkSamplerTests`
Expected: PASS(2 tests)

- [ ] **Step 6:實作真實介面來源(getifaddrs,排除 loopback)**

`Sources/GlanceCore/Bridge/InterfaceCountersSource.swift`:
```swift
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
```

- [ ] **Step 7:Commit**

```bash
git add Sources/GlanceCore/Model/NetworkSnapshot.swift Sources/GlanceCore/Sampling/NetworkSampler.swift Sources/GlanceCore/Bridge/InterfaceCountersSource.swift Tests/GlanceCoreTests/NetworkSamplerTests.swift
git commit -m "feat: [glance] add network snapshot, sampler and interface source"
```

---

## Task 6:磁碟模型、Sampler 與 statfs 來源

**Files:**
- Create: `Sources/GlanceCore/Model/DiskSnapshot.swift`
- Create: `Sources/GlanceCore/Sampling/DiskSampler.swift`
- Create: `Sources/GlanceCore/Bridge/StatfsDiskSource.swift`

> 磁碟為非差值指標(v1 只做容量),邏輯極薄,以真實來源 + CLI smoke 涵蓋;不另寫單元測試。

- [ ] **Step 1:實作模型**

`Sources/GlanceCore/Model/DiskSnapshot.swift`:
```swift
public struct DiskStats: Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public init(totalBytes: UInt64, usedBytes: UInt64) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes
    }
}

public struct DiskSnapshot: Equatable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public init(totalBytes: UInt64, usedBytes: UInt64) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes
    }
    public var usedFraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

public protocol DiskStatsSource {
    func read() -> DiskStats?
}
```

- [ ] **Step 2:實作 Sampler**

`Sources/GlanceCore/Sampling/DiskSampler.swift`:
```swift
public final class DiskSampler {
    private let source: DiskStatsSource
    public init(source: DiskStatsSource) { self.source = source }

    public func sample() -> DiskSnapshot? {
        guard let s = source.read() else { return nil }
        return DiskSnapshot(totalBytes: s.totalBytes, usedBytes: s.usedBytes)
    }
}
```

- [ ] **Step 3:實作真實 statfs 來源(根目錄)**

`Sources/GlanceCore/Bridge/StatfsDiskSource.swift`:
```swift
import Darwin

/// 以 statfs("/") 取得根卷容量。
public struct StatfsDiskSource: DiskStatsSource {
    private let path: String
    public init(path: String = "/") { self.path = path }

    public func read() -> DiskStats? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        let blockSize = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * blockSize
        let free = UInt64(fs.f_bavail) * blockSize
        let used = total >= free ? total - free : 0
        return DiskStats(totalBytes: total, usedBytes: used)
    }
}
```

- [ ] **Step 4:驗證可編譯**

Run: `swift build`
Expected: 編譯成功,無錯誤。

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/Model/DiskSnapshot.swift Sources/GlanceCore/Sampling/DiskSampler.swift Sources/GlanceCore/Bridge/StatfsDiskSource.swift
git commit -m "feat: [glance] add disk snapshot, sampler and statfs source"
```

---

## Task 7:電池模型、Sampler 與 IOKit 來源

**Files:**
- Create: `Sources/GlanceCore/Model/BatterySnapshot.swift`
- Create: `Sources/GlanceCore/Sampling/BatterySampler.swift`
- Create: `Sources/GlanceCore/Bridge/IOKitBatterySource.swift`

> 邏輯極薄(直接映射),以真實來源 + CLI smoke 涵蓋;桌機無電池時回 `isPresent = false`。

- [ ] **Step 1:實作模型**

`Sources/GlanceCore/Model/BatterySnapshot.swift`:
```swift
public struct BatteryStats: Equatable {
    public let isPresent: Bool
    public let chargeFraction: Double  // 0...1
    public let isCharging: Bool
    public init(isPresent: Bool, chargeFraction: Double, isCharging: Bool) {
        self.isPresent = isPresent; self.chargeFraction = chargeFraction; self.isCharging = isCharging
    }
}

public typealias BatterySnapshot = BatteryStats

public protocol BatteryStatsSource {
    func read() -> BatteryStats?
}
```

- [ ] **Step 2:實作 Sampler**

`Sources/GlanceCore/Sampling/BatterySampler.swift`:
```swift
public final class BatterySampler {
    private let source: BatteryStatsSource
    public init(source: BatteryStatsSource) { self.source = source }
    public func sample() -> BatterySnapshot? { source.read() }
}
```

- [ ] **Step 3:實作真實 IOKit 來源**

`Sources/GlanceCore/Bridge/IOKitBatterySource.swift`:
```swift
import Foundation
import IOKit.ps

/// 透過 IOPowerSources 讀取第一個電源資訊;無電池時回 isPresent = false。
public struct IOKitBatterySource: BatteryStatsSource {
    public init() {}

    public func read() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false)
        }
        guard let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
              let current = desc[kIOPSCurrentCapacityKey] as? Int,
              let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
        else {
            return BatteryStats(isPresent: false, chargeFraction: 0, isCharging: false)
        }
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        return BatteryStats(
            isPresent: true,
            chargeFraction: Double(current) / Double(max),
            isCharging: charging)
    }
}
```

- [ ] **Step 4:驗證可編譯**

Run: `swift build`
Expected: 編譯成功。

- [ ] **Step 5:Commit**

```bash
git add Sources/GlanceCore/Model/BatterySnapshot.swift Sources/GlanceCore/Sampling/BatterySampler.swift Sources/GlanceCore/Bridge/IOKitBatterySource.swift
git commit -m "feat: [glance] add battery snapshot, sampler and IOKit source"
```

---

## Task 8:Top 程式模型、Sampler 與 libproc 來源

**Files:**
- Create: `Sources/GlanceCore/Model/ProcessUsage.swift`
- Create: `Sources/GlanceCore/Sampling/ProcessSampler.swift`
- Create: `Sources/GlanceCore/Bridge/LibprocSource.swift`
- Test: `Tests/GlanceCoreTests/ProcessSamplerTests.swift`

- [ ] **Step 1:寫失敗測試(程式 CPU% = cpu 時間差 ÷ 牆鐘時間差)**

`Tests/GlanceCoreTests/ProcessSamplerTests.swift`:
```swift
import XCTest
@testable import GlanceCore

private final class StubProcSource: RawProcessSource {
    var queue: [[RawProcess]]
    init(_ q: [[RawProcess]]) { queue = q }
    func read() -> [RawProcess]? { queue.isEmpty ? nil : queue.removeFirst() }
}

final class ProcessSamplerTests: XCTestCase {
    func testComputesCPUFractionFromDelta() {
        // pid 1:1 秒內 cpu 時間 +0.5s → 0.5;pid 2:+0.1s → 0.1
        let first = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.0, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.0, memoryBytes: 200),
        ]
        let second = [
            RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.5, memoryBytes: 100),
            RawProcess(pid: 2, name: "B", cpuTimeSeconds: 5.1, memoryBytes: 200),
        ]
        var times = [0.0, 1.0]
        let sampler = ProcessSampler(source: StubProcSource([first, second]),
                                     clock: { times.removeFirst() }, limit: 5)
        _ = sampler.sampleTopByCPU()
        let top = sampler.sampleTopByCPU()
        XCTAssertEqual(top.first?.pid, 1)
        XCTAssertEqual(top.first?.cpuFraction ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(top.first?.name, "A")
    }

    func testNewProcessHasZeroCPUUntilSecondSample() {
        let first = [RawProcess(pid: 1, name: "A", cpuTimeSeconds: 10.0, memoryBytes: 100)]
        var times = [0.0]
        let sampler = ProcessSampler(source: StubProcSource([first]),
                                     clock: { times.removeFirst() }, limit: 5)
        let top = sampler.sampleTopByCPU()
        XCTAssertEqual(top.first?.cpuFraction, 0)
    }
}
```

- [ ] **Step 2:跑測試確認失敗**

Run: `swift test --filter ProcessSamplerTests`
Expected: FAIL(`cannot find 'RawProcess' in scope`)

- [ ] **Step 3:實作模型**

`Sources/GlanceCore/Model/ProcessUsage.swift`:
```swift
/// libproc 取得的單一程式原始資料。cpuTimeSeconds 為累計使用者+系統 CPU 秒數。
public struct RawProcess: Equatable {
    public let pid: Int32
    public let name: String
    public let cpuTimeSeconds: Double
    public let memoryBytes: UInt64
    public init(pid: Int32, name: String, cpuTimeSeconds: Double, memoryBytes: UInt64) {
        self.pid = pid; self.name = name
        self.cpuTimeSeconds = cpuTimeSeconds; self.memoryBytes = memoryBytes
    }
}

/// 對外呈現的單一程式使用率。cpuFraction 可能 > 1(多核)。
public struct ProcessUsage: Equatable {
    public let pid: Int32
    public let name: String
    public let cpuFraction: Double
    public let memoryBytes: UInt64
    public init(pid: Int32, name: String, cpuFraction: Double, memoryBytes: UInt64) {
        self.pid = pid; self.name = name
        self.cpuFraction = cpuFraction; self.memoryBytes = memoryBytes
    }
}

public protocol RawProcessSource {
    func read() -> [RawProcess]?
}
```

- [ ] **Step 4:實作 Sampler**

`Sources/GlanceCore/Sampling/ProcessSampler.swift`:
```swift
import Foundation

/// 以兩次取樣間各 pid 的 cpu 時間差 ÷ 牆鐘時間差,計算每個程式 CPU 佔比。
public final class ProcessSampler {
    private let source: RawProcessSource
    private let clock: () -> TimeInterval
    private let limit: Int
    private var previous: (byPid: [Int32: Double], time: TimeInterval)?

    public init(source: RawProcessSource,
                clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
                limit: Int = 5) {
        self.source = source
        self.clock = clock
        self.limit = limit
    }

    public func sampleTopByCPU() -> [ProcessUsage] {
        guard let raws = source.read() else { return [] }
        let t = clock()
        let cpuByPid = Dictionary(uniqueKeysWithValues: raws.map { ($0.pid, $0.cpuTimeSeconds) })
        defer { previous = (cpuByPid, t) }

        let prev = previous
        let dt = prev.map { t - $0.time } ?? 0

        let usages: [ProcessUsage] = raws.map { p in
            let fraction: Double
            if let prev, dt > 0, let prevCPU = prev.byPid[p.pid] {
                fraction = max(0, (p.cpuTimeSeconds - prevCPU) / dt)
            } else {
                fraction = 0
            }
            return ProcessUsage(pid: p.pid, name: p.name, cpuFraction: fraction, memoryBytes: p.memoryBytes)
        }
        return Array(usages.sorted { $0.cpuFraction > $1.cpuFraction }.prefix(limit))
    }

    public func sampleTopByMemory() -> [ProcessUsage] {
        guard let raws = source.read() else { return [] }
        let usages = raws.map {
            ProcessUsage(pid: $0.pid, name: $0.name, cpuFraction: 0, memoryBytes: $0.memoryBytes)
        }
        return Array(usages.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
    }
}
```

- [ ] **Step 5:跑測試確認通過**

Run: `swift test --filter ProcessSamplerTests`
Expected: PASS(2 tests)

> 註:`testNewProcessHasZeroCPUUntilSecondSample` 只取樣一次即驗證,故 source queue 只放一組。

- [ ] **Step 6:實作真實 libproc 來源**

`Sources/GlanceCore/Bridge/LibprocSource.swift`:
```swift
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
```

- [ ] **Step 7:Commit**

```bash
git add Sources/GlanceCore/Model/ProcessUsage.swift Sources/GlanceCore/Sampling/ProcessSampler.swift Sources/GlanceCore/Bridge/LibprocSource.swift Tests/GlanceCoreTests/ProcessSamplerTests.swift
git commit -m "feat: [glance] add process usage model, sampler and libproc source"
```

---

## Task 9:SystemSnapshot 聚合型別

**Files:**
- Create: `Sources/GlanceCore/SystemSnapshot.swift`

- [ ] **Step 1:實作聚合型別**

`Sources/GlanceCore/SystemSnapshot.swift`:
```swift
/// 一次取樣的全部指標聚合。任一指標可能取樣失敗 → nil(故障隔離)。
public struct SystemSnapshot {
    public let cpu: CPUSnapshot?
    public let memory: MemorySnapshot?
    public let network: NetworkSnapshot?
    public let disk: DiskSnapshot?
    public let battery: BatterySnapshot?
    public let topByCPU: [ProcessUsage]
    public let topByMemory: [ProcessUsage]

    public init(cpu: CPUSnapshot?, memory: MemorySnapshot?, network: NetworkSnapshot?,
                disk: DiskSnapshot?, battery: BatterySnapshot?,
                topByCPU: [ProcessUsage], topByMemory: [ProcessUsage]) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery
        self.topByCPU = topByCPU; self.topByMemory = topByMemory
    }
}
```

- [ ] **Step 2:驗證可編譯與全部測試通過**

Run: `swift test`
Expected: PASS(全部測試,涵蓋 RingBuffer / Formatters / CPU / Memory / Network / Process)

- [ ] **Step 3:Commit**

```bash
git add Sources/GlanceCore/SystemSnapshot.swift
git commit -m "feat: [glance] add aggregate SystemSnapshot"
```

---

## Task 10:glance-cli 一次性狀態輸出(實機 smoke)

**Files:**
- Modify: `Sources/glance-cli/main.swift`

- [ ] **Step 1:實作 CLI**

`Sources/glance-cli/main.swift`(完整取代 Task 0 的佔位內容):
```swift
import GlanceCore
import Foundation

// 為了讓差值指標(CPU/網路/程式)有第二筆,取樣兩次、中間間隔 1 秒。
let cpu = CPUSampler(source: MachCPUSource())
let memory = MemorySampler(source: MachMemorySource())
let network = NetworkSampler(source: InterfaceCountersSource())
let disk = DiskSampler(source: StatfsDiskSource())
let battery = BatterySampler(source: IOKitBatterySource())
let process = ProcessSampler(source: LibprocSource(), limit: 5)

func sampleAll() -> SystemSnapshot {
    SystemSnapshot(
        cpu: cpu.sample(),
        memory: memory.sample(),
        network: network.sample(),
        disk: disk.sample(),
        battery: battery.sample(),
        topByCPU: process.sampleTopByCPU(),
        topByMemory: process.sampleTopByMemory())
}

_ = sampleAll()                 // 第一筆:建立差值基準
Thread.sleep(forTimeInterval: 1)
let s = sampleAll()

func line(_ label: String, _ value: String) {
    print("\(label.padding(toLength: 10, withPad: " ", startingAt: 0)) \(value)")
}

print("=== Glance ===")
if let c = s.cpu { line("CPU", Formatters.percent(c.totalUsage)) }
if let m = s.memory {
    line("記憶體", "\(Formatters.bytes(m.usedBytes)) / \(Formatters.bytes(m.totalBytes)) (\(Formatters.percent(m.usedFraction)))")
}
if let n = s.network {
    line("網路", "↓\(Formatters.rateCompact(n.downBytesPerSec)) ↑\(Formatters.rateCompact(n.upBytesPerSec))")
}
if let d = s.disk {
    line("磁碟", "\(Formatters.bytes(d.usedBytes)) / \(Formatters.bytes(d.totalBytes)) (\(Formatters.percent(d.usedFraction)))")
}
if let b = s.battery, b.isPresent {
    line("電池", "\(Formatters.percent(b.chargeFraction))\(b.isCharging ? " ⚡" : "")")
}
print("\n-- Top CPU --")
for p in s.topByCPU {
    print("  \(Formatters.percent(p.cpuFraction))\t\(p.name)")
}
```

- [ ] **Step 2:實機執行 smoke test**

Run: `swift run glance-cli`
Expected: 印出非空的 CPU / 記憶體 / 網路 / 磁碟 數值,Top CPU 至少列出數個程式;數值合理(CPU 0~100%、記憶體已用 < 總量)。若某指標顯示缺失,表示對應 Bridge 需檢查回傳碼。

- [ ] **Step 3:Commit**

```bash
git add Sources/glance-cli/main.swift
git commit -m "feat: [glance] add glance-cli one-shot status output"
```

---

## Task 11:README

**Files:**
- Create: `README.md`

- [ ] **Step 1:撰寫 README**

`README.md`:
```markdown
# Glance

macOS 選單列主機狀態工具(類 iStat Menus)。本套件 `GlanceCore` 為純資料層,提供 CPU、記憶體、網路、磁碟、電池與 Top 程式取樣。

## 需求
- macOS 13+(Apple Silicon)
- Swift 5.9+

## 使用
```bash
swift test          # 執行單元測試
swift run glance-cli # 一次性印出目前主機狀態
```

## 架構
- `Model/`:不可變 snapshot 與原始計數型別
- `Sampling/`:各指標 Sampler(差值指標注入 raw source,可測試)
- `Bridge/`:系統讀取(Mach / getifaddrs / statfs / IOKit / libproc)
- `History/`:RingBuffer 歷史緩衝
- `Format/`:人類可讀字串

選單列 UI(`MenuBarExtra`)於後續 GlanceApp 計畫實作。
```

- [ ] **Step 2:Commit**

```bash
git add README.md
git commit -m "docs: [glance] add GlanceCore README"
```

---

## Self-Review Notes

- **Spec 覆蓋**:CPU/記憶體/網路/磁碟/電池/Top 程式皆有對應 Task(3–8);RingBuffer 歷史(Task 1);格式化(Task 2);錯誤處理以各 sampler 回 `nil` + `SystemSnapshot` 可選欄位達成。溫度/風扇依 spec 明確排除。`MetricsStore`、選單列字串組裝、設定項移至 Plan 2(UI)。
- **型別一致性**:百分比一律 `0...1` 分數;source protocol 一律 `read() -> X?`;`BatterySnapshot = BatteryStats` typealias 避免重複。CLI 與各 sampler 的型別/方法名稱(`sample()`、`sampleTopByCPU()`、`sampleTopByMemory()`)一致。
- **無 placeholder**:每個 code step 均含完整可編譯內容。Bridge 層的 IOKit/Mach 呼叫以 Task 10 實機 smoke test 驗證(非單元測試,已於測試策略說明)。
