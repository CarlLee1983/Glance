# Glance — macOS 選單列主機狀態工具 設計文件

- **日期**:2026-06-03
- **狀態**:設計定案(待轉實作計畫)
- **平台**:macOS 26.2、Apple Silicon(arm64)

## 1. 目標與範圍

開發一個類似 iStat Menus 的 macOS 選單列工具,讓使用者能快速查詢目前主機狀態。

**形態**:常駐選單列 agent app(`LSUIElement = true`,不顯示 Dock 圖示),原生 SwiftUI。

**v1 監控指標**:CPU、記憶體、網路、磁碟、電池。

**選單列常駐顯示**:單一精簡欄位,例如 `23% · 61% · ↓2.1M`(不顯示時鐘,交給 macOS 內建)。可在設定選擇要顯示哪幾格。

**下拉詳情**:豐富版——每個指標含歷史曲線圖 + Top 程式清單。

### 明確不在 v1 範圍(YAGNI,架構預留、日後再加)
- 溫度/風扇(Apple Silicon 無公開 API,日後以 IOKit SMC 私有讀取實作)
- 登入時自動啟動
- 公證 / notarize / App Store 上架(先自用;架構不阻擋日後分享)
- 磁碟即時讀寫活動量(v1 磁碟先做容量,活動量列為選配)

## 2. 技術選型

- **UI 層**:SwiftUI `MenuBarExtra(.window)` —— 標籤放精簡字串,內容放豐富下拉。
- **資料層**:純 Swift + 系統框架,**零第三方依賴**。
  - CPU:`host_processor_info`(processor ticks 差值)
  - 記憶體:`host_statistics64`(`vm_statistics64`)+ `sysctl` 取總量;memory pressure
  - 網路:`getifaddrs` → `if_data`(`ifi_ibytes`/`ifi_obytes`)位元組差值
  - 磁碟:`statfs` 容量(+ 選配 IOKit `IOBlockStorageDriver` 讀寫量)
  - 電池:IOKit `IOPSCopyPowerSourcesInfo`
  - Top 程式:`libproc`(`proc_listallpids` / `proc_pid_rusage` / `proc_name`)

**選型理由**:常駐 App 對效能敏感,純系統框架最輕量、無 spawn 行程開銷、無解析脆弱性,也最貼近 iStat 做法,且日後加 SMC 溫度最順。已排除「呼叫 CLI 解析」(每秒 spawn 太重、文字格式脆弱)與「引入開源套件」(多數 GPL,與日後分享有授權牽絆)。

## 3. 架構與資料流

兩層 + 一個協調者:

```
   DispatchSourceTimer (每 ~2s, 背景佇列)
              │ tick()
              ▼
   MetricsStore (ObservableObject)
   持有各 Sampler、執行取樣、寫入歷史、發佈到主執行緒
              │
   ┌──────┬──────┬──────┬──────┬──────┬──────┐
   CPU   Memory Network Disk  Battery Process   ← Sampler 們
              │ 「現在原始計數 − 上次原始計數」→ snapshot
              ▼
   RingBuffer 歷史(每指標最近 ~90 筆,供曲線圖)
              │ @Published(主執行緒)
              ▼
   SwiftUI MenuBarExtra(.window)
     ├─ MenuBarLabel  → "23% · 61% · ↓2.1M"
     └─ DropdownView  → 各指標區塊(曲線圖 + Top 程式)
```

**資料流**:計時器於背景佇列觸發 → `MetricsStore.tick()` 讓每個 Sampler 取樣(差值計算)→ 寫入該指標 RingBuffer → 切回主執行緒更新 `@Published` → SwiftUI 重繪。取樣全在背景,UI 不卡。

**關鍵點**:
- CPU% 與網速為差值指標,需上一筆原始計數;第一次 tick 顯示 0,第二次起正常。
- 取樣頻率預設 2 秒,可在設定調整(1~5 秒)。
- 歷史長度約 90 筆。

## 4. 模組拆分與檔案組織

採「**純邏輯核心庫 + 薄 UI 層**」分離:核心可單元測試、UI 可獨立替換。遵循「多個小檔案、高內聚低耦合」原則(單檔 200–400 行為宜)。

```
Glance/
├─ Glance.xcodeproj                 (保留 xcodebuild CLI 可建置)
├─ GlanceCore/                      ← 純邏輯,可測試(framework target)
│  ├─ Model/
│  │   ├─ CPUSnapshot.swift         不可變 struct
│  │   ├─ MemorySnapshot.swift
│  │   ├─ NetworkSnapshot.swift
│  │   ├─ DiskSnapshot.swift
│  │   ├─ BatterySnapshot.swift
│  │   └─ ProcessInfo.swift         (Top 程式一筆:名稱/pid/cpu/mem)
│  ├─ Sampling/
│  │   ├─ Sampler.swift             protocol { associatedtype Snapshot; func sample() }
│  │   ├─ CPUSampler.swift
│  │   ├─ MemorySampler.swift
│  │   ├─ NetworkSampler.swift
│  │   ├─ DiskSampler.swift
│  │   ├─ BatterySampler.swift
│  │   └─ ProcessSampler.swift
│  ├─ Bridge/                       ← 低階 C 互通隔離於此層
│  │   ├─ MachHost.swift
│  │   ├─ LibprocBridge.swift
│  │   ├─ Interfaces.swift
│  │   └─ IOKitPower.swift
│  ├─ History/
│  │   ├─ RingBuffer.swift          泛型固定長度環形緩衝
│  │   └─ MetricHistory.swift
│  └─ Store/
│      └─ MetricsStore.swift        ObservableObject + DispatchSourceTimer
├─ GlanceApp/                       ← 薄 UI 層(app target)
│  ├─ GlanceApp.swift               @main, MenuBarExtra(.window)
│  ├─ MenuBar/
│  │   └─ MenuBarLabel.swift
│  ├─ Dropdown/
│  │   ├─ DropdownView.swift
│  │   ├─ CPUSection.swift          每 Section = 曲線 + 數字 + Top 程式
│  │   ├─ MemorySection.swift
│  │   ├─ NetworkSection.swift
│  │   ├─ DiskSection.swift
│  │   └─ BatterySection.swift
│  ├─ Components/
│  │   ├─ Sparkline.swift           可重用曲線圖(Swift Charts 或 Canvas)
│  │   └─ TopProcessList.swift
│  ├─ Settings/
│  │   ├─ SettingsView.swift        取樣頻率、選單列顯示哪幾格
│  │   └─ AppSettings.swift         @AppStorage 包 UserDefaults
│  └─ Info.plist                    LSUIElement = true
└─ GlanceCoreTests/                 ← XCTest,測核心邏輯
```

**刻意的邊界**:
- **Sampler 注入原始計數來源**:sampler 不直接呼叫系統 API,而依賴一個「raw source」protocol/函式;真實版讀系統、測試版餵固定值,使差值數學可單元測試。
- **Bridge 層集中所有不安全 / C 互通**,其餘保持純 Swift。
- **擴充預留**:日後加溫度只需在 `Sampling/` 新增 `SensorSampler` + Bridge 的 SMC 讀取,不動其他層。

## 5. 錯誤處理

邊界設在 Sampler:
- 每個系統呼叫檢查回傳碼;`sample()` 回 `Snapshot?`(失敗回 `nil`),絕不 crash/trap。
- 某指標取樣失敗 → 該區塊顯示 `—`,其他指標照常(故障隔離)。
- 失敗以 `os.Logger` 記錄(syscall 名稱 + 錯誤碼)。
- 第一次 tick 差值指標無前值 → 顯示 0,屬正常,不視為錯誤。
- libproc 列舉時部分 pid 可能於取樣中消失(權限/結束)→ 跳過該筆,不中斷整批。

## 6. 測試策略(核心邏輯目標 80%+)

- **RingBuffer**:寫滿、繞回、容量邊界、讀取順序。
- **差值數學(重點)**:餵兩組固定原始計數,驗證
  - CPU%:user/system/idle ticks 差值換算。
  - 網速:位元組差值 ÷ 時間 = MB/s。
  - 程式 CPU%:兩次取樣間 cpu time 差值。
  靠「注入 raw source」達成,不碰真實系統。
- **Snapshot 格式化**:GB/MB、百分比、`↓2.1M` 字串。
- **Bridge / IOKit**:屬難測系統邊界 → 包在 protocol 後、以假實作測上層;真實 Bridge 以一個實機 smoke test(跑一次確認不為 nil)涵蓋。
- 工具:XCTest;核心庫獨立於 UI,免啟動畫面即可測。

## 7. 設定項(v1)

`AppSettings`(@AppStorage / UserDefaults):
- 取樣頻率(1~5 秒,預設 2)
- 選單列要顯示哪幾格(CPU / 記憶體 / 網路 …)
