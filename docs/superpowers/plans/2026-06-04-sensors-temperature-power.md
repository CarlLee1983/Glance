# 感測器擴充（溫度 / 功耗 / 風扇 / 電池進階）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Glance 下拉選單新增「感測器」區（CPU/GPU 溫度、SoC 功耗、風扇），把電池進階資訊併入電池區，並讓溫度/功耗可選進選單列。

**Architecture:** 沿用既有分層 Bridge → Sampler → Model → SystemSnapshot → MetricsStore → UI。每個系統來源以 protocol 封裝、回傳 optional，達成故障隔離與可注入假物件測試。純邏輯（model / sampler / formatter / status / menubar）以 TDD 開發；依硬體的 bridge（IOKit/IOHID/IOReport/SMC）無法決定性單元測試，改以 CLI 在 M4 Air 手動驗證。

**Tech Stack:** Swift 5.9、SwiftPM（`GlanceCore` + `glance-cli`）、XCTest、SwiftUI（`GlanceApp`，Xcode 專案）、IOKit / IOHIDEventSystemClient / IOReport / AppleSMC。

**驗證指令參考：**
- 核心測試：`swift test`
- 單一測試：`swift test --filter <TestClass>/<testMethod>`
- CLI 手動驗證：`swift run glance-cli`
- App 編譯：`xcodebuild -project Glance.xcodeproj -scheme Glance build`（UI 變更以執行 app 目視驗證）

---

## 檔案結構

**新增（GlanceCore）：**
- `Sources/GlanceCore/Model/SensorSnapshot.swift` — 感測值彙整型別 + 三個來源 protocol 與其讀數結構
- `Sources/GlanceCore/Sampling/SensorSampler.swift` — 組裝三來源 → `SensorSnapshot?`
- `Sources/GlanceCore/Bridge/IOHIDThermalSource.swift` — 溫度（私有 IOHID）
- `Sources/GlanceCore/Bridge/IOReportPowerSource.swift` — 功耗（IOReport 差值）
- `Sources/GlanceCore/Bridge/SMCFanSource.swift` — 風扇（AppleSMC）

**新增（GlanceApp）：**
- `GlanceApp/Dropdown/SensorsSection.swift` — 感測器下拉區

**新增（測試）：**
- `Tests/GlanceCoreTests/SensorSamplerTests.swift`
- `Tests/GlanceCoreTests/BatteryStatsTests.swift`（健康度/瓦數格式化等純邏輯）
- 既有 `FormattersTests.swift` / `MetricStatusTests.swift` / `MenuBarTextTests.swift` 增測

**修改：**
- `Sources/GlanceCore/Model/BatterySnapshot.swift` — 加電池進階欄位
- `Sources/GlanceCore/Bridge/IOKitBatterySource.swift` — 加讀 AppleSmartBattery registry
- `Sources/GlanceCore/SystemSnapshot.swift` — 加 `sensors`
- `Sources/GlanceCore/Sampling/SystemSampler.swift` — 接 `SensorSampler`
- `Sources/GlanceCore/Format/Formatters.swift` — `temperature` / `watts`
- `Sources/GlanceCore/Format/MetricStatus.swift` — `temperature(celsius:)`
- `Sources/GlanceCore/MenuBar/MenuBarSegment.swift` — 加 `.cpuTemp` / `.power` + readings case
- `GlanceApp/MenuBar/MenuBarSegmentIcon.swift` — 新 case 的 SF Symbol（窮舉 switch 必補）
- `GlanceApp/Dropdown/BatterySection.swift` — 顯示電池進階
- `GlanceApp/Dropdown/DropdownView.swift` — 插入 SensorsSection
- `GlanceApp/Settings/SettingsView.swift` — 兩個新標籤
- `Sources/glance-cli/main.swift` — 印出感測器與電池進階

---

## Phase 0：核心型別與彙整（純邏輯，TDD）

### Task 1：SensorSnapshot 型別與來源 protocol

**Files:**
- Create: `Sources/GlanceCore/Model/SensorSnapshot.swift`

- [ ] **Step 1：建立型別檔（無行為，直接寫入）**

```swift
/// 感測值彙整。每欄獨立可缺漏:對應來源失敗 → nil / 空陣列(故障隔離)。
public struct SensorSnapshot: Equatable {
    public let cpuTemperature: Double?   // °C
    public let gpuTemperature: Double?   // °C
    public let systemPower: Double?      // W(SoC 總功耗)
    public let cpuPower: Double?         // W
    public let gpuPower: Double?         // W
    public let fanRPM: [Int]             // 無風扇 → []

    public init(cpuTemperature: Double? = nil, gpuTemperature: Double? = nil,
                systemPower: Double? = nil, cpuPower: Double? = nil,
                gpuPower: Double? = nil, fanRPM: [Int] = []) {
        self.cpuTemperature = cpuTemperature; self.gpuTemperature = gpuTemperature
        self.systemPower = systemPower; self.cpuPower = cpuPower
        self.gpuPower = gpuPower; self.fanRPM = fanRPM
    }

    /// 三類來源皆無資料 → 視為整體無感測器(UI 整區隱藏)。
    public var isEmpty: Bool {
        cpuTemperature == nil && gpuTemperature == nil && systemPower == nil
            && cpuPower == nil && gpuPower == nil && fanRPM.isEmpty
    }
}

/// 溫度來源讀數。
public struct ThermalReading: Equatable {
    public let cpu: Double?
    public let gpu: Double?
    public init(cpu: Double?, gpu: Double?) { self.cpu = cpu; self.gpu = gpu }
}

/// 功耗來源讀數(瓦)。
public struct PowerReading: Equatable {
    public let system: Double?
    public let cpu: Double?
    public let gpu: Double?
    public init(system: Double?, cpu: Double?, gpu: Double?) {
        self.system = system; self.cpu = cpu; self.gpu = gpu
    }
}

public protocol ThermalSource { func read() -> ThermalReading? }
public protocol PowerSource { func read() -> PowerReading? }
public protocol FanSource { func read() -> [Int] }
```

- [ ] **Step 2：編譯確認**

Run: `swift build`
Expected: 成功（新型別不影響既有程式）。

- [ ] **Step 3：Commit**

```bash
git add Sources/GlanceCore/Model/SensorSnapshot.swift
git commit -m "feat: [core] 新增 SensorSnapshot 型別與感測來源 protocol"
```

---

### Task 2：SensorSampler 組裝（TDD）

**Files:**
- Create: `Sources/GlanceCore/Sampling/SensorSampler.swift`
- Test: `Tests/GlanceCoreTests/SensorSamplerTests.swift`

- [ ] **Step 1：寫失敗測試**

```swift
import XCTest
@testable import GlanceCore

private struct FakeThermal: ThermalSource {
    let reading: ThermalReading?
    func read() -> ThermalReading? { reading }
}
private struct FakePower: PowerSource {
    let reading: PowerReading?
    func read() -> PowerReading? { reading }
}
private struct FakeFan: FanSource {
    let rpm: [Int]
    func read() -> [Int] { rpm }
}

final class SensorSamplerTests: XCTestCase {
    func testAssemblesAllSources() {
        let sampler = SensorSampler(
            thermal: FakeThermal(reading: ThermalReading(cpu: 52, gpu: 48)),
            power: FakePower(reading: PowerReading(system: 12.4, cpu: 6, gpu: 3)),
            fan: FakeFan(rpm: [1800, 1820]))

        let snap = sampler.sample()

        XCTAssertEqual(snap, SensorSnapshot(
            cpuTemperature: 52, gpuTemperature: 48,
            systemPower: 12.4, cpuPower: 6, gpuPower: 3,
            fanRPM: [1800, 1820]))
    }

    func testPartialSourcesDegradeGracefully() {
        let sampler = SensorSampler(
            thermal: FakeThermal(reading: ThermalReading(cpu: 50, gpu: nil)),
            power: FakePower(reading: nil),
            fan: FakeFan(rpm: []))

        let snap = sampler.sample()

        XCTAssertEqual(snap?.cpuTemperature, 50)
        XCTAssertNil(snap?.gpuTemperature)
        XCTAssertNil(snap?.systemPower)
        XCTAssertEqual(snap?.fanRPM, [])
    }

    func testNilSourcesProduceNil() {
        let sampler = SensorSampler()  // 三來源皆 nil
        XCTAssertNil(sampler.sample())
    }

    func testAllEmptyReadingsProduceNil() {
        let sampler = SensorSampler(
            thermal: FakeThermal(reading: ThermalReading(cpu: nil, gpu: nil)),
            power: FakePower(reading: nil),
            fan: FakeFan(rpm: []))
        XCTAssertNil(sampler.sample())
    }
}
```

- [ ] **Step 2：執行確認失敗**

Run: `swift test --filter SensorSamplerTests`
Expected: 編譯失敗 / FAIL，因 `SensorSampler` 尚未存在。

- [ ] **Step 3：實作 SensorSampler**

```swift
/// 組裝溫度/功耗/風扇三來源 → SensorSnapshot。任一來源缺漏只讓該欄為 nil/空;
/// 三者皆無資料 → 回 nil(UI 整區隱藏)。
public final class SensorSampler {
    private let thermal: ThermalSource?
    private let power: PowerSource?
    private let fan: FanSource?

    public init(thermal: ThermalSource? = nil, power: PowerSource? = nil, fan: FanSource? = nil) {
        self.thermal = thermal; self.power = power; self.fan = fan
    }

    public func sample() -> SensorSnapshot? {
        let t = thermal?.read()
        let p = power?.read()
        let f = fan?.read() ?? []
        let snap = SensorSnapshot(
            cpuTemperature: t?.cpu, gpuTemperature: t?.gpu,
            systemPower: p?.system, cpuPower: p?.cpu, gpuPower: p?.gpu,
            fanRPM: f)
        return snap.isEmpty ? nil : snap
    }
}
```

- [ ] **Step 4：執行確認通過**

Run: `swift test --filter SensorSamplerTests`
Expected: PASS（4 筆）。

- [ ] **Step 5：Commit**

```bash
git add Sources/GlanceCore/Sampling/SensorSampler.swift Tests/GlanceCoreTests/SensorSamplerTests.swift
git commit -m "feat: [core] SensorSampler 組裝感測來源並做缺漏降級"
```

---

### Task 3：SystemSnapshot / SystemSampler 接線

**Files:**
- Modify: `Sources/GlanceCore/SystemSnapshot.swift`
- Modify: `Sources/GlanceCore/Sampling/SystemSampler.swift`

- [ ] **Step 1：SystemSnapshot 加 `sensors`（預設 nil 保相容）**

把 `SystemSnapshot` 改為（新增 `sensors` 欄位與 init 參數，**參數給預設 nil**，使既有位置呼叫端不破壞）：

```swift
public struct SystemSnapshot {
    public let cpu: CPUSnapshot?
    public let memory: MemorySnapshot?
    public let network: NetworkSnapshot?
    public let disk: DiskSnapshot?
    public let battery: BatterySnapshot?
    public let sensors: SensorSnapshot?
    public let topByCPU: [ProcessUsage]
    public let topByMemory: [ProcessUsage]

    public init(cpu: CPUSnapshot?, memory: MemorySnapshot?, network: NetworkSnapshot?,
                disk: DiskSnapshot?, battery: BatterySnapshot?,
                sensors: SensorSnapshot? = nil,
                topByCPU: [ProcessUsage], topByMemory: [ProcessUsage]) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery; self.sensors = sensors
        self.topByCPU = topByCPU; self.topByMemory = topByMemory
    }
}
```

- [ ] **Step 2：SystemSampler 接 SensorSampler**

把 `SystemSampler` 改為（加入 `sensor` 依賴；此階段 `convenience init()` 先以**空** `SensorSampler()` 注入，後續 Phase 再插入真實來源）：

```swift
public final class SystemSampler: SystemSampling {
    private let cpu: CPUSampler
    private let memory: MemorySampler
    private let network: NetworkSampler
    private let disk: DiskSampler
    private let battery: BatterySampler
    private let process: ProcessSampler
    private let sensor: SensorSampler

    public init(cpu: CPUSampler, memory: MemorySampler, network: NetworkSampler,
                disk: DiskSampler, battery: BatterySampler, process: ProcessSampler,
                sensor: SensorSampler) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.battery = battery; self.process = process
        self.sensor = sensor
    }

    public convenience init() {
        self.init(
            cpu: CPUSampler(source: MachCPUSource()),
            memory: MemorySampler(source: MachMemorySource()),
            network: NetworkSampler(source: InterfaceCountersSource()),
            disk: DiskSampler(source: StatfsDiskSource()),
            battery: BatterySampler(source: IOKitBatterySource()),
            process: ProcessSampler(source: LibprocSource(), limit: 5),
            sensor: SensorSampler())  // Phase 1+ 會插入真實來源
    }

    public func sample() -> SystemSnapshot {
        let procs = process.sample()
        return SystemSnapshot(
            cpu: cpu.sample(),
            memory: memory.sample(),
            network: network.sample(),
            disk: disk.sample(),
            battery: battery.sample(),
            sensors: sensor.sample(),
            topByCPU: procs.topCPU,
            topByMemory: procs.topMemory)
    }
}
```

- [ ] **Step 3：執行整套核心測試確認無回歸**

Run: `swift test`
Expected: 全部 PASS（既有測試因 `sensors` 有預設值不受影響）。

- [ ] **Step 4：Commit**

```bash
git add Sources/GlanceCore/SystemSnapshot.swift Sources/GlanceCore/Sampling/SystemSampler.swift
git commit -m "feat: [core] SystemSnapshot/Sampler 納入 sensors"
```

---

### Task 4：Formatters 溫度與瓦數（TDD）

**Files:**
- Modify: `Sources/GlanceCore/Format/Formatters.swift`
- Modify: `Tests/GlanceCoreTests/FormattersTests.swift`

- [ ] **Step 1：寫失敗測試（附加到 FormattersTests）**

```swift
func testTemperatureFormatsWholeDegrees() {
    XCTAssertEqual(Formatters.temperature(52.4), "52°C")
    XCTAssertEqual(Formatters.temperature(47.6), "48°C")
}

func testWattsFormatsOneDecimal() {
    XCTAssertEqual(Formatters.watts(12.43), "12.4 W")
    XCTAssertEqual(Formatters.watts(3), "3.0 W")
    XCTAssertEqual(Formatters.watts(-8.2), "8.2 W")  // 放電負值以絕對值顯示
}
```

- [ ] **Step 2：執行確認失敗**

Run: `swift test --filter FormattersTests`
Expected: 編譯失敗，因 `temperature` / `watts` 未定義。

- [ ] **Step 3：實作（附加到 `Formatters` enum）**

```swift
/// 攝氏溫度 → "52°C"(四捨五入到整數度)。
public static func temperature(_ celsius: Double) -> String {
    "\(Int(celsius.rounded()))°C"
}

/// 瓦數 → "12.4 W"(一位小數,以絕對值顯示)。
public static func watts(_ w: Double) -> String {
    String(format: "%.1f W", abs(w))
}
```

- [ ] **Step 4：執行確認通過**

Run: `swift test --filter FormattersTests`
Expected: PASS。

- [ ] **Step 5：Commit**

```bash
git add Sources/GlanceCore/Format/Formatters.swift Tests/GlanceCoreTests/FormattersTests.swift
git commit -m "feat: [core] Formatters 新增溫度與瓦數格式化"
```

---

### Task 5：MetricStatus 溫度分級（TDD）

**Files:**
- Modify: `Sources/GlanceCore/Format/MetricStatus.swift`
- Modify: `Tests/GlanceCoreTests/MetricStatusTests.swift`

- [ ] **Step 1：寫失敗測試（附加到 MetricStatusTests）**

```swift
func testTemperatureStatusBands() {
    XCTAssertEqual(MetricStatus.temperature(celsius: 60), .normal)
    XCTAssertEqual(MetricStatus.temperature(celsius: 79.9), .normal)
    XCTAssertEqual(MetricStatus.temperature(celsius: 80), .elevated)
    XCTAssertEqual(MetricStatus.temperature(celsius: 94.9), .elevated)
    XCTAssertEqual(MetricStatus.temperature(celsius: 95), .critical)
}
```

- [ ] **Step 2：執行確認失敗**

Run: `swift test --filter MetricStatusTests`
Expected: 編譯失敗，因 `temperature(celsius:)` 未定義。

- [ ] **Step 3：實作（附加到 `MetricStatus` enum）**

```swift
public static func temperature(celsius: Double) -> MetricStatus {
    if celsius >= 95 { return .critical }
    if celsius >= 80 { return .elevated }
    return .normal
}
```

- [ ] **Step 4：執行確認通過**

Run: `swift test --filter MetricStatusTests`
Expected: PASS。

- [ ] **Step 5：Commit**

```bash
git add Sources/GlanceCore/Format/MetricStatus.swift Tests/GlanceCoreTests/MetricStatusTests.swift
git commit -m "feat: [core] MetricStatus 新增溫度分級"
```

---

## Phase 1：電池進階（公開 IOKit，零風險）

### Task 6：擴充 BatteryStats 型別與健康度（TDD）

**Files:**
- Modify: `Sources/GlanceCore/Model/BatterySnapshot.swift`
- Create: `Tests/GlanceCoreTests/BatteryStatsTests.swift`

- [ ] **Step 1：寫失敗測試**

```swift
import XCTest
@testable import GlanceCore

final class BatteryStatsTests: XCTestCase {
    func testAdvancedFieldsDefaultToNil() {
        let b = BatteryStats(isPresent: true, chargeFraction: 0.8, isCharging: false)
        XCTAssertNil(b.cycleCount)
        XCTAssertNil(b.healthFraction)
        XCTAssertNil(b.temperature)
        XCTAssertNil(b.powerWatts)
    }

    func testAdvancedFieldsArePreserved() {
        let b = BatteryStats(
            isPresent: true, chargeFraction: 0.8, isCharging: true,
            cycleCount: 142, healthFraction: 0.95, temperature: 31.2, powerWatts: 18.4)
        XCTAssertEqual(b.cycleCount, 142)
        XCTAssertEqual(b.healthFraction, 0.95)
        XCTAssertEqual(b.temperature, 31.2)
        XCTAssertEqual(b.powerWatts, 18.4)
    }
}
```

- [ ] **Step 2：執行確認失敗**

Run: `swift test --filter BatteryStatsTests`
Expected: 編譯失敗，因新欄位/init 參數不存在。

- [ ] **Step 3：擴充 `BatteryStats`（新欄位 + init 預設 nil，保既有呼叫端相容）**

```swift
public struct BatteryStats: Equatable {
    public let isPresent: Bool
    public let chargeFraction: Double  // 0...1
    public let isCharging: Bool
    public let cycleCount: Int?        // 循環次數
    public let healthFraction: Double? // maxCapacity / designCapacity(0...1)
    public let temperature: Double?    // °C
    public let powerWatts: Double?     // 充/放電瓦數(放電為負)

    public init(isPresent: Bool, chargeFraction: Double, isCharging: Bool,
                cycleCount: Int? = nil, healthFraction: Double? = nil,
                temperature: Double? = nil, powerWatts: Double? = nil) {
        self.isPresent = isPresent; self.chargeFraction = chargeFraction
        self.isCharging = isCharging; self.cycleCount = cycleCount
        self.healthFraction = healthFraction; self.temperature = temperature
        self.powerWatts = powerWatts
    }
}

public typealias BatterySnapshot = BatteryStats

public protocol BatteryStatsSource {
    func read() -> BatteryStats?
}
```

- [ ] **Step 4：執行確認通過 + 全套無回歸**

Run: `swift test`
Expected: 全部 PASS（既有 `BatteryStats(isPresent:chargeFraction:isCharging:)` 呼叫因預設值不破壞）。

- [ ] **Step 5：Commit**

```bash
git add Sources/GlanceCore/Model/BatterySnapshot.swift Tests/GlanceCoreTests/BatteryStatsTests.swift
git commit -m "feat: [core] BatteryStats 新增循環/健康/溫度/瓦數欄位"
```

---

### Task 7：IOKitBatterySource 讀 AppleSmartBattery registry（硬體整合，CLI 驗證）

**Files:**
- Modify: `Sources/GlanceCore/Bridge/IOKitBatterySource.swift`

> 此任務讀真實硬體,無法決定性單元測試。既有 `IOPowerSources` 取 charge%/charging 路徑不變;新增從 `AppleSmartBattery` IORegistry 取進階欄位,任一缺漏該欄留 nil。

- [ ] **Step 1：實作（覆寫整檔）**

```swift
import Foundation
import IOKit
import IOKit.ps

/// 透過 IOPowerSources 讀基本電源資訊;再從 AppleSmartBattery registry 補進階欄位。
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
        let adv = readAdvanced()
        return BatteryStats(
            isPresent: true,
            chargeFraction: Double(current) / Double(max),
            isCharging: charging,
            cycleCount: adv.cycleCount,
            healthFraction: adv.healthFraction,
            temperature: adv.temperature,
            powerWatts: adv.powerWatts)
    }

    private struct Advanced {
        var cycleCount: Int?
        var healthFraction: Double?
        var temperature: Double?
        var powerWatts: Double?
    }

    /// 從 AppleSmartBattery IORegistry 節點讀進階屬性。讀不到回全 nil。
    private func readAdvanced() -> Advanced {
        var adv = Advanced()
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return adv }
        defer { IOObjectRelease(service) }

        func intProp(_ key: String) -> Int? {
            guard let ref = IORegistryEntryCreateCFProperty(
                service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            else { return nil }
            return (ref as? NSNumber)?.intValue
        }

        adv.cycleCount = intProp("CycleCount")
        if let design = intProp("DesignCapacity"), design > 0,
           let maxCap = intProp("AppleRawMaxCapacity") ?? intProp("MaxCapacity") {
            adv.healthFraction = Double(maxCap) / Double(design)
        }
        // 溫度單位為 1/100 °C。
        if let t = intProp("Temperature") {
            adv.temperature = Double(t) / 100.0
        }
        // 瞬時功率 = 電壓(mV) × 電流(mA) / 1e6 → W;電流放電為負。
        if let voltage = intProp("Voltage"), let amperage = intProp("InstantAmperage") ?? intProp("Amperage") {
            adv.powerWatts = Double(voltage) * Double(amperage) / 1_000_000.0
        }
        return adv
    }
}
```

- [ ] **Step 2：編譯**

Run: `swift build`
Expected: 成功。

- [ ] **Step 3：CLI 手動驗證（M4 Air 應有電池進階值）**

先更新 CLI 輸出再驗證 → 見 Task 9。此步暫以 `swift build` 通過為準；實際數值於 Task 9 一併驗證。

- [ ] **Step 4：Commit**

```bash
git add Sources/GlanceCore/Bridge/IOKitBatterySource.swift
git commit -m "feat: [core] IOKitBatterySource 讀 AppleSmartBattery 進階欄位"
```

---

### Task 8：BatterySection 顯示電池進階（UI，目視驗證）

**Files:**
- Modify: `GlanceApp/Dropdown/BatterySection.swift`

- [ ] **Step 1：擴充 detail 顯示進階欄位（覆寫整檔）**

```swift
import SwiftUI
import GlanceCore

struct BatterySection: View {
    let snapshot: BatterySnapshot

    var body: some View {
        MetricCard(
            title: "電池",
            systemImage: batteryIcon,
            accent: .mint,
            value: Formatters.percent(snapshot.chargeFraction),
            detail: detailText,
            status: MetricStatus.battery(chargeFraction: snapshot.chargeFraction,
                                         isCharging: snapshot.isCharging)
        ) {
            CustomProgressBar(value: snapshot.chargeFraction, color: .mint)
        }
    }

    /// 主狀態 + 可得的進階資訊(只串接有值者)。
    private var detailText: String {
        var parts: [String] = [snapshot.isCharging ? "已連接電源" : "使用電池供電"]
        if let cycles = snapshot.cycleCount { parts.append("循環 \(cycles)") }
        if let health = snapshot.healthFraction { parts.append("健康 \(Formatters.percent(health))") }
        if let watts = snapshot.powerWatts { parts.append(Formatters.watts(watts)) }
        if let temp = snapshot.temperature { parts.append(Formatters.temperature(temp)) }
        return parts.joined(separator: " · ")
    }

    private var batteryIcon: String {
        if snapshot.isCharging { return "battery.100.bolt" }
        if snapshot.chargeFraction < 0.25 { return "battery.25" }
        if snapshot.chargeFraction < 0.75 { return "battery.50" }
        return "battery.100"
    }
}
```

- [ ] **Step 2：編譯 app**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance build`
Expected: BUILD SUCCEEDED。

- [ ] **Step 3：Commit**

```bash
git add GlanceApp/Dropdown/BatterySection.swift
git commit -m "feat: [app] 電池區顯示循環/健康/瓦數/溫度"
```

---

### Task 9：CLI 印出感測器與電池進階（手動驗證入口）

**Files:**
- Modify: `Sources/glance-cli/main.swift`

- [ ] **Step 1：在電池行後加進階與感測器輸出**

在 `main.swift` 中,把電池區塊替換、並於 Top CPU 前加入感測器輸出：

```swift
if let b = s.battery, b.isPresent {
    var extra: [String] = []
    if let c = b.cycleCount { extra.append("循環\(c)") }
    if let h = b.healthFraction { extra.append("健康\(Formatters.percent(h))") }
    if let w = b.powerWatts { extra.append(Formatters.watts(w)) }
    if let t = b.temperature { extra.append(Formatters.temperature(t)) }
    let suffix = extra.isEmpty ? "" : "  [\(extra.joined(separator: " "))]"
    line("電池", "\(Formatters.percent(b.chargeFraction))\(b.isCharging ? " ⚡" : "")\(suffix)")
}

if let sensor = s.sensors {
    print("\n-- 感測器 --")
    if let t = sensor.cpuTemperature { line("CPU 溫", Formatters.temperature(t)) }
    if let t = sensor.gpuTemperature { line("GPU 溫", Formatters.temperature(t)) }
    if let p = sensor.systemPower { line("功耗", Formatters.watts(p)) }
    if !sensor.fanRPM.isEmpty {
        line("風扇", sensor.fanRPM.map { "\($0) RPM" }.joined(separator: " / "))
    }
}
```

- [ ] **Step 2：執行 CLI 驗證電池進階**

Run: `swift run glance-cli`
Expected: 「電池」行帶 `[循環N 健康XX% Y.Y W ...]`；此時感測器區尚無溫度/功耗（Phase 2/4 才接），可能不印感測器區（正常）。

- [ ] **Step 3：Commit**

```bash
git add Sources/glance-cli/main.swift
git commit -m "feat: [cli] 印出電池進階與感測器讀數"
```

---

## Phase 2：溫度（私有 IOHID）

### Task 10：IOHIDThermalSource（硬體整合，CLI 驗證）

**Files:**
- Create: `Sources/GlanceCore/Bridge/IOHIDThermalSource.swift`

> 使用私有 `IOHIDEventSystemClient`(IOKit 內含符號,以 `@_silgen_name` / dlsym 取得)。讀不到回 nil。此來源依硬體,以 CLI 驗證。

- [ ] **Step 1：實作**

```swift
import Foundation
import IOKit

// 私有 IOHIDEventSystemClient 符號宣告(IOKit 內,無公開 header)。
private typealias IOHIDEventSystemClientRef = CFTypeRef
private typealias IOHIDServiceClientRef = CFTypeRef
private typealias IOHIDEventRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClientRef?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: IOHIDEventSystemClientRef, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: IOHIDEventSystemClientRef) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: IOHIDServiceClientRef, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: IOHIDServiceClientRef, _ type: Int64,
                                         _ options: Int32, _ timeout: Int64) -> IOHIDEventRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

// kIOHIDEventTypeTemperature = 15;field = (type << 16)。
private let kIOHIDEventTypeTemperature: Int64 = 15
private let kIOHIDEventFieldTemperature: Int32 = Int32(15 << 16)

/// 透過 IOHIDEventSystemClient 讀溫度感測器,依名稱前綴歸類 CPU/GPU 取平均。
public struct IOHIDThermalSource: ThermalSource {
    public init() {}

    public func read() -> ThermalReading? {
        // page = 0xff00 (kHIDPage_AppleVendor), usage = 0x0005 (TemperatureSensor)
        let matching: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 0x0005]
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return nil }
        IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClientRef] else {
            return nil
        }

        var cpuTemps: [Double] = []
        var gpuTemps: [Double] = []
        for service in services {
            guard let nameRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString),
                  let name = nameRef as? String else { continue }
            guard let event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperature)
            guard value > 0, value < 150 else { continue }  // 過濾異常讀數
            let lower = name.lowercased()
            if lower.contains("gpu") { gpuTemps.append(value) }
            else if lower.contains("cpu") || lower.contains("pmgr") || lower.contains("soc") { cpuTemps.append(value) }
        }

        func avg(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        let reading = ThermalReading(cpu: avg(cpuTemps), gpu: avg(gpuTemps))
        return (reading.cpu == nil && reading.gpu == nil) ? nil : reading
    }
}
```

- [ ] **Step 2：編譯**

Run: `swift build`
Expected: 成功。

- [ ] **Step 3：暫時把真實溫度來源接入 CLI 用的 SystemSampler（Task 11）後驗證**

此步不單獨驗證,於 Task 11 接線後一併以 CLI 驗證。

- [ ] **Step 4：Commit**

```bash
git add Sources/GlanceCore/Bridge/IOHIDThermalSource.swift
git commit -m "feat: [core] IOHIDThermalSource 以私有 IOHID 讀 CPU/GPU 溫度"
```

---

### Task 11：把溫度來源接入 SystemSampler，CLI 驗證

**Files:**
- Modify: `Sources/GlanceCore/Sampling/SystemSampler.swift`

- [ ] **Step 1：`convenience init()` 的 SensorSampler 注入溫度來源**

把 Task 3 的 `sensor: SensorSampler()` 改為：

```swift
            sensor: SensorSampler(thermal: IOHIDThermalSource()))
```

- [ ] **Step 2：CLI 驗證溫度**

Run: `swift run glance-cli`
Expected: 出現「-- 感測器 --」區，含「CPU 溫 XX°C」（M4 Air 上應有合理值，約 30–60°C 視負載）。GPU 溫可能有或無，視感測器命名。

- [ ] **Step 3：核心測試無回歸**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 4：Commit**

```bash
git add Sources/GlanceCore/Sampling/SystemSampler.swift
git commit -m "feat: [core] SystemSampler 接入溫度感測來源"
```

---

### Task 12：SensorsSection 下拉區（UI，目視驗證）

**Files:**
- Create: `GlanceApp/Dropdown/SensorsSection.swift`
- Modify: `GlanceApp/Dropdown/DropdownView.swift`

- [ ] **Step 1：建立 SensorsSection**

先確認 `MetricCard` 的對外介面（在 `DropdownChrome.swift`），此處沿用既有 `MetricCard` 樣式呈現多列。實作：

```swift
import SwiftUI
import GlanceCore

/// 感測器區:逐列顯示有資料的溫度/功耗/風扇。整體無資料時呼叫端不渲染本區。
struct SensorsSection: View {
    let snapshot: SensorSnapshot

    var body: some View {
        MetricCard(
            title: "感測器",
            systemImage: "thermometer.medium",
            accent: .orange,
            value: primaryValue,
            detail: detailText,
            status: primaryStatus
        ) {
            EmptyView()
        }
    }

    /// 主數值優先顯示 CPU 溫度,否則功耗,否則風扇。
    private var primaryValue: String {
        if let t = snapshot.cpuTemperature { return Formatters.temperature(t) }
        if let p = snapshot.systemPower { return Formatters.watts(p) }
        if let f = snapshot.fanRPM.first { return "\(f) RPM" }
        return "—"
    }

    private var primaryStatus: MetricStatus {
        if let t = snapshot.cpuTemperature { return MetricStatus.temperature(celsius: t) }
        return .normal
    }

    private var detailText: String {
        var parts: [String] = []
        if let t = snapshot.gpuTemperature { parts.append("GPU \(Formatters.temperature(t))") }
        if let p = snapshot.systemPower, snapshot.cpuTemperature != nil { parts.append(Formatters.watts(p)) }
        if let f = snapshot.fanRPM.first { parts.append("風扇 \(f) RPM") }
        return parts.isEmpty ? "即時感測讀數" : parts.joined(separator: " · ")
    }
}
```

> 若 `MetricCard` 不接受 `EmptyView()` 作為尾隨內容（例如要求具體型別），改傳一個 `Color.clear.frame(height: 0)`。實作時依 `DropdownChrome.swift` 的實際簽章調整。

- [ ] **Step 2：DropdownView 插入（在 Battery 之後）**

把 `DropdownView.body` 中電池區塊之後加入：

```swift
            if let b = s?.battery, b.isPresent {
                BatterySection(snapshot: b)
            }
            if let sensors = s?.sensors, !sensors.isEmpty {
                SensorsSection(snapshot: sensors)
            }
```

- [ ] **Step 3：編譯並執行 app 目視驗證**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance build`
Expected: BUILD SUCCEEDED。執行 app,下拉選單出現「感測器」區，顯示 CPU 溫度。

- [ ] **Step 4：Commit**

```bash
git add GlanceApp/Dropdown/SensorsSection.swift GlanceApp/Dropdown/DropdownView.swift
git commit -m "feat: [app] 下拉選單新增感測器區"
```

---

## Phase 3：選單列整合（溫度/功耗）

### Task 13：MenuBarSegment 與 MenuBarText 新增欄位（TDD）

**Files:**
- Modify: `Sources/GlanceCore/MenuBar/MenuBarSegment.swift`
- Modify: `Tests/GlanceCoreTests/MenuBarTextTests.swift`

- [ ] **Step 1：寫失敗測試（附加到 MenuBarTextTests）**

先把 `makeSnapshot` 增加 `sensors` 參數（預設 nil），再加測試。把既有 `makeSnapshot` 簽章末端 `battery:` 後加入 `sensors: SensorSnapshot? = nil`，並在建構 `SystemSnapshot` 時帶入 `sensors: sensors`。然後新增：

```swift
func testTemperatureAndPowerReadings() {
    let snapshot = makeSnapshot(
        sensors: SensorSnapshot(cpuTemperature: 82, systemPower: 12.4))

    let readings = MenuBarText.readings(snapshot: snapshot, segments: [.cpuTemp, .power])

    XCTAssertEqual(readings, [
        SegmentReading(segment: .cpuTemp, value: "82°C", status: .elevated),
        SegmentReading(segment: .power, value: "12.4 W", status: .normal),
    ])
}

func testSensorSegmentsSkippedWhenMissing() {
    // 無 sensors → 兩欄皆略過
    let readings = MenuBarText.readings(snapshot: makeSnapshot(), segments: [.cpuTemp, .power])
    XCTAssertEqual(readings, [])
}
```

- [ ] **Step 2：執行確認失敗**

Run: `swift test --filter MenuBarTextTests`
Expected: 編譯失敗，因 `.cpuTemp` / `.power` case 不存在。

- [ ] **Step 3：MenuBarSegment 加 case（append 到尾端保順序相容）**

```swift
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network, disk, battery, cpuTemp, power
}
```

- [ ] **Step 4：MenuBarText.readings 加兩個 case**

在 `switch seg` 的 `.battery` case 之後加入：

```swift
            case .cpuTemp:
                if let t = snapshot.sensors?.cpuTemperature {
                    result.append(SegmentReading(
                        segment: .cpuTemp,
                        value: Formatters.temperature(t),
                        status: MetricStatus.temperature(celsius: t)
                    ))
                }
            case .power:
                if let p = snapshot.sensors?.systemPower {
                    result.append(SegmentReading(
                        segment: .power,
                        value: Formatters.watts(p),
                        status: .normal
                    ))
                }
```

- [ ] **Step 5：執行確認通過 + 全套無回歸**

Run: `swift test`
Expected: 全部 PASS（無測試硬編 `MenuBarSegment.allCases` 數量；`MenuBarDisplayModeTests` 測的是顯示模式，不受影響）。

- [ ] **Step 6：Commit**

```bash
git add Sources/GlanceCore/MenuBar/MenuBarSegment.swift Tests/GlanceCoreTests/MenuBarTextTests.swift
git commit -m "feat: [core] 選單列支援 CPU 溫度與功耗欄位"
```

---

### Task 14：App 端補齊新欄位（窮舉 switch + 設定標籤）（UI）

**Files:**
- Modify: `GlanceApp/MenuBar/MenuBarSegmentIcon.swift`
- Modify: `GlanceApp/Settings/SettingsView.swift`

> `MenuBarSegmentIcon.name(for:)` 與 `SettingsView.label(_:)` 皆為**無 `default` 的窮舉 switch**，加了新 enum case 後不補 case 會編譯失敗。兩者一併更新。

- [ ] **Step 1：MenuBarSegmentIcon 加兩個 case**

在 `switch segment` 內、`.battery` 之後加入：

```swift
        case .cpuTemp: return "thermometer.medium"
        case .power:   return "bolt"
```

- [ ] **Step 2：SettingsView `label(_:)` 加兩個 case**

在 `switch s` 內、`.battery` 之後加入：

```swift
        case .cpuTemp: return "CPU 溫度"
        case .power:   return "功耗"
```

- [ ] **Step 3：編譯 app**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance build`
Expected: BUILD SUCCEEDED（兩個 `switch` 現已涵蓋全部 case）。執行 app → 設定頁「選單列欄位」清單出現「CPU 溫度」「功耗」可勾選，勾選後選單列以溫度計/閃電圖示顯示。

- [ ] **Step 4：Commit**

```bash
git add GlanceApp/MenuBar/MenuBarSegmentIcon.swift GlanceApp/Settings/SettingsView.swift
git commit -m "feat: [app] 選單列圖示與設定頁加入 CPU 溫度/功耗欄位"
```

---

## Phase 4：功耗（IOReport）

### Task 15：IOReportPowerSource（硬體整合，差值取樣，CLI 驗證）

**Files:**
- Create: `Sources/GlanceCore/Bridge/IOReportPowerSource.swift`

> 使用私有 `IOReport`(IOKit 內符號)。能量通道為累積值,需保留上一筆做差值換算瞬時功率。`read()` 第一次回 nil(建立基準),之後回瓦數。讀不到回 nil。依硬體,CLI 驗證。

- [ ] **Step 1：實作**

```swift
import Foundation
import IOKit

// 私有 IOReport 符號宣告。
@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(_ group: CFString?, _ subgroup: CFString?,
                                         _ a: UInt64, _ b: UInt64, _ c: UInt64) -> Unmanaged<CFMutableDictionary>?

@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(_ a: UnsafeMutableRawPointer?, _ channels: CFMutableDictionary,
                                        _ subbed: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>,
                                        _ flags: UInt64, _ b: UnsafeMutableRawPointer?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(_ subscription: CFTypeRef, _ channels: CFMutableDictionary,
                                   _ a: UnsafeMutableRawPointer?) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(_ prev: CFDictionary, _ current: CFDictionary,
                                        _ a: UnsafeMutableRawPointer?) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ ch: CFDictionary) -> Unmanaged<CFString>?

@_silgen_name("IOReportSimpleGetIntegerValue")
private func IOReportSimpleGetIntegerValue(_ ch: CFDictionary, _ a: Int32) -> Int64

/// 以 IOReport「Energy Model」群組讀 SoC 能量,兩次取樣間差值換算瞬時瓦數。
public final class IOReportPowerSource: PowerSource {
    private var subscription: CFTypeRef?
    private var channels: CFMutableDictionary?
    private var lastSample: CFDictionary?
    private var lastTime: TimeInterval?

    public init() {
        guard let chans = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return }
        self.channels = chans
        var subbed: Unmanaged<CFMutableDictionary>?
        if let sub = IOReportCreateSubscription(nil, chans, &subbed, 0, nil)?.takeRetainedValue() {
            self.subscription = sub
        }
    }

    public func read() -> PowerReading? {
        guard let subscription, let channels,
              let current = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue()
        else { return nil }
        let now = Date().timeIntervalSince1970
        defer { lastSample = current; lastTime = now }

        guard let prev = lastSample, let prevTime = lastTime,
              let delta = IOReportCreateSamplesDelta(prev, current, nil)?.takeRetainedValue()
        else { return nil }  // 第一次:僅建立基準
        let dt = now - prevTime
        guard dt > 0 else { return nil }

        // delta 內每個 channel 的整數值為該期間消耗能量(mJ);/dt → mW;/1000 → W。
        var cpu = 0.0, gpu = 0.0, total = 0.0
        let items = delta as NSDictionary
        if let chList = items["IOReportChannels"] as? [CFDictionary] {
            for ch in chList {
                guard let nameRef = IOReportChannelGetChannelName(ch)?.takeRetainedValue() else { continue }
                let name = (nameRef as String).lowercased()
                let energy_mJ = Double(IOReportSimpleGetIntegerValue(ch, 0))
                let watts = (energy_mJ / dt) / 1000.0
                total += watts
                if name.contains("gpu") { gpu += watts }
                else if name.contains("cpu") || name.contains("ecpu") || name.contains("pcpu") { cpu += watts }
            }
        }
        guard total > 0 else { return nil }
        return PowerReading(
            system: total,
            cpu: cpu > 0 ? cpu : nil,
            gpu: gpu > 0 ? gpu : nil)
    }
}
```

> IOReport 樣本的字典結構（`IOReportChannels` 鍵、整數取值 API）實作時若與真機不符，依 CLI 觀察到的實際鍵名調整解析；核心契約（第一次回 nil、之後回瓦數、讀不到回 nil）不變。

- [ ] **Step 2：編譯**

Run: `swift build`
Expected: 成功。

- [ ] **Step 3：接入 SystemSampler**

把 `convenience init()` 的 SensorSampler 改為：

```swift
            sensor: SensorSampler(thermal: IOHIDThermalSource(), power: IOReportPowerSource()))
```

- [ ] **Step 4：CLI 驗證功耗**

Run: `swift run glance-cli`
Expected: 感測器區出現「功耗 X.X W」（CLI 已取樣兩次：第一次建基準、第二次出值）。M4 Air 閒置約數瓦。

- [ ] **Step 5：核心測試無回歸 + Commit**

Run: `swift test`
Expected: 全部 PASS。

```bash
git add Sources/GlanceCore/Bridge/IOReportPowerSource.swift Sources/GlanceCore/Sampling/SystemSampler.swift
git commit -m "feat: [core] IOReportPowerSource 以差值取樣讀 SoC 功耗"
```

---

## Phase 5：風扇（SMC）

### Task 16：SMCFanSource（硬體整合，CLI 驗證；M4 Air 恆空）

**Files:**
- Create: `Sources/GlanceCore/Bridge/SMCFanSource.swift`

> 透過 `AppleSMC` IOService 讀風扇數（鍵 `FNum`）與各風扇 RPM（鍵 `F0Ac`, `F1Ac`...）。無風扇機型回 `[]`。依硬體,CLI 驗證。

- [ ] **Step 1：實作**

```swift
import Foundation
import IOKit

/// 透過 AppleSMC 讀風扇轉速。無風扇(如 MacBook Air)回 []。
public final class SMCFanSource: FanSource {
    private var conn: io_connect_t = 0

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        IOServiceOpen(service, mach_task_self_, 0, &conn)
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    public func read() -> [Int] {
        guard conn != 0 else { return [] }
        guard let count = readUInt8(key: "FNum"), count > 0 else { return [] }
        var result: [Int] = []
        for i in 0..<count {
            if let rpm = readFloat(key: "F\(i)Ac"), rpm > 0 {
                result.append(Int(rpm.rounded()))
            }
        }
        return result
    }

    // --- SMC 讀取原語 ---
    // 註:SMC 的 SMCKeyData_t 結構與呼叫選擇器(kSMCReadKey/kSMCGetKeyInfo)為已知慣例。
    // 以下封裝最小讀取;若真機鍵型不同(uint8 / flt / fpe2),依 keyInfo 的 dataType 解析。

    private func readUInt8(key: String) -> Int? {
        guard let bytes = readKeyBytes(key) else { return nil }
        return Int(bytes.first ?? 0)
    }

    private func readFloat(key: String) -> Double? {
        guard let bytes = readKeyBytes(key), bytes.count >= 4 else { return nil }
        // 風扇鍵常見為 'flt'(little-endian Float32)。
        let value = bytes.prefix(4).withUnsafeBytes { $0.load(as: Float32.self) }
        return Double(value)
    }

    /// 讀取指定 SMC key 的原始位元組。實作時依 SMCKeyData_t 慣例填入結構與選擇器。
    private func readKeyBytes(_ key: String) -> [UInt8]? {
        // SMC 呼叫細節(SMCKeyData_t、kSMCReadKey=5、kSMCGetKeyInfo=9、IOConnectCallStructMethod index=2)
        // 於實作時補齊。讀不到回 nil → read() 退回 []。
        return nil
    }
}
```

> 本任務的 SMC 結構/選擇器屬已知慣例（參考開源 SMCKit / stats 的 `SMCKeyData_t`）。實作 `readKeyBytes` 時填入 `IOConnectCallStructMethod` 與結構;在 M4 Air 上 `FNum` 預期讀不到或為 0 → `read()` 回 `[]`，**這是預期行為**。

- [ ] **Step 2：編譯**

Run: `swift build`
Expected: 成功。

- [ ] **Step 3：接入 SystemSampler**

把 `convenience init()` 的 SensorSampler 改為：

```swift
            sensor: SensorSampler(
                thermal: IOHIDThermalSource(),
                power: IOReportPowerSource(),
                fan: SMCFanSource()))
```

- [ ] **Step 4：CLI 驗證（M4 Air 應無風扇行）**

Run: `swift run glance-cli`
Expected: 感測器區**不**出現風扇行（M4 Air 無風扇，`fanRPM` 為空）。在有風扇機型上才會出現「風扇 N RPM」。

- [ ] **Step 5：核心測試無回歸 + Commit**

Run: `swift test`
Expected: 全部 PASS。

```bash
git add Sources/GlanceCore/Bridge/SMCFanSource.swift Sources/GlanceCore/Sampling/SystemSampler.swift
git commit -m "feat: [core] SMCFanSource 讀風扇轉速(無風扇機型回空)"
```

---

## Phase 6：收尾驗證

### Task 17：全流程驗證與 README

**Files:**
- Modify: `README.md`（功能列表補感測器/電池進階）

- [ ] **Step 1：完整核心測試**

Run: `swift test`
Expected: 全部 PASS。

- [ ] **Step 2：App 編譯 + 目視驗證**

Run: `xcodebuild -project Glance.xcodeproj -scheme Glance build`
Expected: BUILD SUCCEEDED。執行 app：
- 下拉選單有「感測器」區（CPU 溫度、功耗；無風扇行）
- 電池區顯示循環/健康/瓦數/溫度
- 設定頁可勾選「CPU 溫度」「功耗」進選單列，勾選後選單列顯示對應數值

- [ ] **Step 3：更新 README 功能列表**

於 README 功能段落補一句說明感測器（溫度/功耗/風扇）與電池進階資訊，並註明溫度/功耗使用私有 API、不上架 App Store。

- [ ] **Step 4：Commit**

```bash
git add README.md
git commit -m "docs: README 補充感測器與電池進階功能"
```

---

## 自審紀錄

- **Spec 覆蓋**：電池進階(Task 6–9)、溫度(Task 10–12)、功耗(Task 15)、風扇(Task 16)、選單列整合(Task 13–14)、Sensors 區(Task 12)、CLI 驗證(Task 9)、不做 sparkline/零依賴(全程遵守) — 皆有對應任務。
- **相容性**：`SystemSnapshot.sensors` 與 `BatteryStats` 新欄位均給 init 預設值,既有位置呼叫端(含 `MenuBarTextTests`)不破壞;`MenuBarSegment` 新 case append 到尾端保 UserDefaults 順序相容。
- **型別一致**:`ThermalReading`/`PowerReading`/`FanSource` 在 Task 1 定義,Task 2/10/15/16 沿用同簽章;`SensorSnapshot.isEmpty` 於 Task 1 定義、Task 2 與 Task 12 使用。
- **硬體限制誠實標註**:依硬體的 4 個 bridge 任務明確標為「無法決定性單元測試,以 CLI 驗證」,風扇於 M4 Air 恆空為預期行為。
- **已知待實作細節**:`SMCFanSource.readKeyBytes` 與 `IOReportPowerSource` 的字典解析依真機鍵名於實作時校準,契約已固定。
