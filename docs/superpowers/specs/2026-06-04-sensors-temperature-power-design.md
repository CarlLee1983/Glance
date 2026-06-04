# 設計：感測器擴充（溫度 / 功耗 / 風扇 / 電池進階）

- 日期：2026-06-04
- 狀態：已核准設計，待寫實作計畫
- 範圍：在 Glance 既有分層（Bridge → Sampler → Model → Snapshot → Store → UI）上新增系統感測資訊

## 目標

於下拉選單新增「感測器」區，呈現 CPU/GPU 溫度、SoC 功耗、風扇轉速；並把電池進階資訊（循環次數、健康度、溫度、充放電瓦數）併入既有電池區。溫度與功耗另可選進選單列顯示。

## 技術現實與風險

| 指標 | 取得方式 | M4 Air | 風險 |
|---|---|---|---|
| 電池進階（循環/健康/容量/溫度/瓦數） | 公開 IOKit registry（`AppleSmartBattery`） | ✅ 完整支援 | 低 |
| 溫度（CPU/GPU） | 私有 `IOHIDEventSystemClient` 熱感測器 | ✅ 可讀 | 中（私有 API，**不可上架 App Store**） |
| 功耗瓦數（SoC/CPU/GPU） | `IOReport` 能量通道（累積→差值取樣） | ✅ 可讀 | 中高（API 繁瑣） |
| 風扇 RPM | SMC keys（`AppleSMC`） | ❌ 無風扇恆空 | 中 |

> 採用私有 API（IOHID）後此 app 無法上架 App Store；本專案採 GitHub 直接散佈，可接受。

## 架構決策

維持現有慣例：
- **零外部依賴**：自行封裝各系統來源。
- **故障隔離**：任一來源失敗 → 對應欄位 `nil` / 空陣列，不影響其他指標。
- **來源 protocol 化**：每個 Bridge 來源都有對應 protocol，可注入假物件做決定性測試。
- **不可變值型別**：snapshot 全為 `struct`，沿用 `Equatable`。

### 實作分階段（依價值/風險比，由低到高）

1. 電池進階（公開 API、零風險、馬上有感）
2. 溫度感測（私有 IOHID，新增 Sensors 區骨架）
3. 功耗瓦數（IOReport）
4. 風扇（SMC，M4 上 no-op）

每階段為獨立可測單元、可各自 commit。溫度/功耗在其階段完成後接上選單列。

## 1. 資料模型（`Sources/GlanceCore/Model`）

新增 `SensorSnapshot.swift`：

```swift
public struct SensorSnapshot: Equatable {
    public let cpuTemperature: Double?   // °C
    public let gpuTemperature: Double?   // °C
    public let systemPower: Double?      // W（SoC 總功耗）
    public let cpuPower: Double?         // W
    public let gpuPower: Double?         // W
    public let fanRPM: [Int]             // 無風扇 → []
}
```

每欄獨立可缺漏；`SensorSampler` 逐來源組裝，失敗者留 `nil`/`[]`。

擴充 `BatterySnapshot.swift` 的 `BatteryStats`（新欄位皆為 optional 並於 `init` 給預設值，**不破壞既有呼叫端**）：

```swift
// 既有：isPresent / chargeFraction / isCharging
public let cycleCount: Int?        // 循環次數
public let healthFraction: Double? // maxCapacity / designCapacity（0...1）
public let temperature: Double?    // °C
public let powerWatts: Double?     // 充/放電瓦數（帶正負號；放電為負）
```

## 2. Bridge 來源（`Sources/GlanceCore/Bridge`）

| 階段 | 檔案 | protocol | 實作重點 |
|---|---|---|---|
| 1 | 改 `IOKitBatterySource` | 既有 `BatteryStatsSource` | 既有 `IOPowerSources` 取 charge%/charging 不變；新增讀 `AppleSmartBattery` IORegistry：`CycleCount`、`DesignCapacity`、`AppleRawMaxCapacity`（或 `NominalChargeCapacity`）、`Temperature`（centi-°C ÷100）、`Amperage`×`Voltage`→瓦數 |
| 2 | 新 `IOHIDThermalSource` | 新 `ThermalSource` | `IOHIDEventSystemClientCreate` → 比對 `kHIDPage_AppleVendor` 溫度感測器 → `IOHIDServiceClientCopyEvent`（`kIOHIDEventTypeTemperature`）讀值；依感測器命名歸類 CPU/GPU 取平均 |
| 3 | 新 `IOReportPowerSource` | 新 `PowerSource` | 訂閱 Energy Model 通道，保留上一筆累積值做差值（套用 CPU/網路既有 delta 模式），換算瞬時瓦數 |
| 4 | 新 `SMCFanSource` | 新 `FanSource` | 開 `AppleSMC` service，讀風扇數與 RPM 鍵；無風扇回 `[]` |

`ThermalSource` / `PowerSource` / `FanSource` 回傳值皆為 optional 子結果，方便假物件覆蓋各種缺漏組合。

## 3. 取樣彙整（`Sources/GlanceCore/Sampling`）

新增 `SensorSampler.swift`：注入 `ThermalSource` / `PowerSource` / `FanSource`，`sample() -> SensorSnapshot?`，逐來源組裝、缺漏降級。三者皆無資料時回 `nil`（讓 UI 整區隱藏）。

`SystemSnapshot` 加 `sensors: SensorSnapshot?`；`SystemSampler`：
- `init` 多收 `sensor: SensorSampler`
- `convenience init()` 以真實來源建立 `SensorSampler`
- `sample()` 納入 `sensors: sensor.sample()`

## 4. 選單列整合（`Sources/GlanceCore/MenuBar`、`Format`）

- `MenuBarSegment` **附加** `.cpuTemp`、`.power`（append 到 `allCases` 尾端 → 既有 `menuBarSegments` 逗號字串與順序相容）
- `MenuBarText.readings` 加兩個 case：
  - `.cpuTemp`：值 `Formatters.temperature(sensors.cpuTemperature)`，狀態 `MetricStatus.temperature(...)`；無值則略過
  - `.power`：值 `Formatters.watts(sensors.systemPower)`，狀態 `.normal`；無值略過
- `MetricStatus` 加 `temperature(celsius:) -> MetricStatus`：≥80°C → `.elevated`、≥95°C → `.critical`、否則 `.normal`
- `Formatters` 加 `temperature(_ c: Double) -> String`（`"52°C"`）、`watts(_ w: Double) -> String`（`"12.4 W"`）

## 5. UI（`GlanceApp`）

- 新 `GlanceApp/Dropdown/SensorsSection.swift`：標題「感測器」，逐列顯示 CPU 溫 / GPU 溫 / 功耗 / 風扇；**僅渲染有資料的列**，`sensors` 為 nil 或全空則整區隱藏（比照 Battery `isPresent` 守門）。沿用 `MetricCard` 視覺語彙。
- `GlanceApp/Dropdown/BatterySection.swift`：`detail` 區增列循環次數 / 健康度 / 溫度 / 充電瓦數（僅顯示有值者）。
- `GlanceApp/Dropdown/DropdownView.swift`：在 `BatterySection` 之後插入 `SensorsSection`。
- `SettingsView.label()`：加 `.cpuTemp` →「CPU 溫度」、`.power` →「功耗」。
- `Sources/glance-cli/main.swift`：印出感測器與電池進階欄位（手動驗證用）。

## 6. 測試策略（`Tests/GlanceCoreTests`）

可決定性單元測試（用假來源）：
- `SensorSampler`：完整組裝、各種缺漏組合降級、三來源皆空 → `nil`
- `MenuBarText`：`.cpuTemp` / `.power` 格式與略過行為
- `MetricStatus.temperature`：分級邊界（79/80/94/95°C）
- `Formatters.temperature` / `.watts`
- 電池新欄位：健康度計算、瓦數正負號、缺漏時 nil

無法決定性測試（依硬體）：真實 IOKit/IOHID/IOReport/SMC bridge → 以 CLI 在 M4 Air 手動驗證（預期：電池/溫度/功耗有值、風扇為空）。

核心邏輯維持 80%+ 覆蓋。

## 範圍界線（YAGNI）

- 第一版**不**做溫度/功耗的歷史 sparkline（`MetricHistory` 暫不擴充）。
- 風扇於 M4 Air 恆空，程式保留以利換機自動生效。
- 不引入第三方套件。

## 影響的既有檔案一覽

新增：`SensorSnapshot.swift`、`IOHIDThermalSource.swift`、`IOReportPowerSource.swift`、`SMCFanSource.swift`、`SensorSampler.swift`、`SensorsSection.swift`，以及對應測試。

修改：`BatterySnapshot.swift`、`IOKitBatterySource.swift`、`SystemSnapshot.swift`、`SystemSampler.swift`、`MenuBarSegment.swift`、`MetricStatus.swift`、`Formatters.swift`、`BatterySection.swift`、`DropdownView.swift`、`SettingsView.swift`、`main.swift`。
