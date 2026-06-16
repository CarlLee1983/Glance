# 記憶體壓力功能 後續待辦 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收尾「記憶體壓力當主角」合併後列為非阻擋的四項 follow-up:無障礙(VoiceOver)、淺色模式對比、防呆 assert,以及一次實機綠→黃→紅目視驗證。

**Architecture:** 全部落在 App 層三處:`PressureColor`(改警告色 + default 防呆 assert)、`MemorySection`(在記憶體卡片外層加 VoiceOver 合併標籤)。不動 `GlanceCore`、不改壓力門檻、不改任何資料流。每項改動互相獨立、可單獨 build 驗證。

**Tech Stack:** Swift 5.9、SwiftPM(`GlanceApp` executable)、SwiftUI。

**測試前提:** 改動僅在 `GlanceApp`(executable,無單元測試 target),依專案慣例以 `swift build` 綠燈 + 實機啟動目視為準;`swift test` 用於確認未波及 `GlanceCore`(應維持原有 135 測試全綠)。

**全建置指令:** `swift build`　**全測試指令:** `swift test`

**對應原 TODO:** 見 `docs/superpowers/plans/2026-06-16-memory-pressure-sparkline.md` 末「後續待辦」四點。

---

### Task 1: PressureColor 淺色對比改色 + default 防呆 assert(App)

**Files:**
- Modify: `GlanceApp/Dropdown/PressureColor.swift`

> 警告色 `.yellow` 在 macOS Light Mode 卡片淺底下對比接近 WCAG AA 邊緣,改用系統橘 `Color(.systemOrange)`(深淺模式皆自適應、對比更穩)。同時把 `color(forLevel:)` 的 `default` 從「靜默回綠」改為「assert + 回綠」,讓非 0/1/2 的誤用在 debug 早期現形;正常 0 改為顯式 `case`,避免落入 default 觸發 assert。
>
> 注意:此函式同時供標題數字(`color(for:)`)與 sparkline 分段色(`color(forLevel:)`)取色,改色會同步影響兩者,屬預期行為。

- [ ] **Step 1: 改寫 color(forLevel:)**

把 `GlanceApp/Dropdown/PressureColor.swift` 的:

```swift
    /// 供 sparkline 由歷史序數(0/1/2)取色。
    static func color(forLevel level: Int) -> Color {
        switch level {
        case 2: return .red
        case 1: return .yellow
        default: return .green
        }
    }
```

整段替換為:

```swift
    /// 供 sparkline 由歷史序數(0/1/2)取色。
    /// 警告色用系統橘(深淺模式自適應、淺底對比優於 .yellow)。
    static func color(forLevel level: Int) -> Color {
        switch level {
        case 0: return .green
        case 1: return Color(.systemOrange)
        case 2: return .red
        default:
            assertionFailure("非預期的記憶體壓力序數 \(level);預期 0(正常)/1(警告)/2(嚴重)")
            return .green
        }
    }
```

- [ ] **Step 2: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: 回歸確認(未波及 Core)**

Run: `swift test`
Expected: 全綠(135 個,0 失敗)。

- [ ] **Step 4: Commit**

```bash
git add GlanceApp/Dropdown/PressureColor.swift
git commit -m "fix: [app] 記憶體警告色改系統橘提升淺色對比、default 加防呆 assert"
```

---

### Task 2: 記憶體卡片 VoiceOver 無障礙標籤(App)

**Files:**
- Modify: `GlanceApp/Dropdown/MemorySection.swift`

> 壓力目前靠「標題數字顏色 + 副標文字」傳達,顏色對 VoiceOver 無語義。做法:在記憶體 `MetricCard` 外層加 `.accessibilityElement(children: .combine)` 把整張卡片合併為單一無障礙元素,再用 `.accessibilityLabel(...)` 提供簡潔朗讀字串「記憶體 79%,壓力警告」。僅套用在記憶體卡片,不影響其他 Section。
>
> 取捨:採「簡潔型」標籤,只報用量+壓力,不念高記憶體 app 清單(避免朗讀過長);app 清單視為裝飾性細節。

- [ ] **Step 1: 在記憶體卡片外層加無障礙修飾**

把 `MemorySection.body` 內 `MetricCard(...) { ... }` 整個閉包結束的那一行(目前是第 36 行的 `}`,即 `MetricCard` 尾括號)之後,接上兩個修飾子。具體把:

```swift
            if topApps.isEmpty {
                EmptyMetricLine(text: "暫無高記憶體程式")
            } else {
                AppMemoryList(apps: topApps, accent: .blue)
            }
        }
    }
```

改為(只在最外層 `MetricCard` 的尾 `}` 後加兩行修飾,並保留 `body` 的 `}`):

```swift
            if topApps.isEmpty {
                EmptyMetricLine(text: "暫無高記憶體程式")
            } else {
                AppMemoryList(apps: topApps, accent: .blue)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
```

- [ ] **Step 2: 新增 accessibilityLabel 計算屬性**

在 `MemorySection` 內 `private var pressureBandColors: [Color]?` 之後(struct 尾 `}` 之前)新增:

```swift
    /// VoiceOver 朗讀用簡潔標籤:用量 + 壓力。例:「記憶體 79%,壓力警告」。
    private var accessibilityLabel: String {
        let pct = Formatters.percent(snapshot?.usedFraction ?? 0)
        let label = (snapshot?.pressure ?? .normal).displayLabel
        return "記憶體 \(pct),壓力\(label)"
    }
```

- [ ] **Step 3: 建置確認**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add GlanceApp/Dropdown/MemorySection.swift
git commit -m "feat: [app] 記憶體卡片加 VoiceOver 合併標籤(用量+壓力)"
```

---

### Task 3: 實機綠→黃→紅 + VoiceOver 目視驗證(App)

**Files:**
- (無檔案改動;純驗證)

> 結構已由 build/測試/啟動冒煙驗證,但壓力色的實際綠→黃(橘)→紅切換、淺色對比、VoiceOver 標籤尚未在執行中下拉目視確認。

- [ ] **Step 1: 啟動 app**

Run: `swift run Glance`
Expected: app 啟動,選單列出現圖示,點開下拉可見記憶體卡片。

- [ ] **Step 2: 低壓力(綠)基線**

逐項確認:
- 記憶體卡片標題數字為**綠色**;副標顯示「… · 壓力:正常」。
- sparkline 線色為綠、曲線連續無破圖。

- [ ] **Step 3: 製造壓力觀察轉色**

開大量分頁 / 啟動大型 app(如 Xcode、瀏覽器多視窗)拉高記憶體用量,確認:
- 數字與 sparkline 線色由綠轉**橘(警告)**,副標轉「壓力:警告」。
- 用量極高時轉**紅(嚴重)**,副標轉「壓力:嚴重」。
- 三者(數字、副標、sparkline)同步轉色。

- [ ] **Step 4: 淺色模式對比確認**

系統設定切到 Light Mode(或 `外觀:淺色`),重開下拉,確認警告(橘)色在淺底卡片上清楚可辨、不致與綠/紅混淆。

- [ ] **Step 5: VoiceOver 標籤確認**

開啟 VoiceOver(`Cmd-F5`),聚焦記憶體卡片,確認朗讀為「記憶體 79%,壓力警告」之類的單一合併語句(用量 + 壓力詞),而非僅逐項念顏色無語義的數字。

- [ ] **Step 6: 其他卡片未受影響**

確認 CPU/網路/磁碟/電池/感測器卡片外觀與 VoiceOver 行為與先前一致(未被 `PressureColor` 改色或記憶體無障礙修飾波及)。

- [ ] **Step 7: 收尾**

驗證通過後,於原 TODO 檔 `docs/superpowers/plans/2026-06-16-memory-pressure-sparkline.md` 末「後續待辦」四個 `- [ ]` 勾為 `- [x]`,並 commit:

```bash
git add docs/superpowers/plans/2026-06-16-memory-pressure-sparkline.md
git commit -m "docs: [app] 記憶體壓力 follow-up 完成(無障礙/淺色對比/防呆/目視)"
```

---

## 自審結果

- **Spec 覆蓋**:原 TODO 四點 ——(1)無障礙 → Task 2;(2)淺色對比 → Task 1 改 `.systemOrange`;(3)實機目視 → Task 3;(4)防呆 assert → Task 1 `default: assertionFailure`。四點皆有對應 task。
- **占位掃描**:無 TBD/TODO;每個 code step 皆含完整程式碼與確切路徑/指令;Task 3 為純驗證,逐步列出可觀察的預期結果。
- **型別一致**:Task 1 沿用既有 `color(for:)`/`color(forLevel:)` 簽章(僅改 case 內容,未動對外介面),故 `MemorySection` 既有呼叫端不需改;Task 2 的 `accessibilityLabel` 使用既有 `Formatters.percent`、`snapshot?.usedFraction`、`MemoryPressure.displayLabel`(均已存在於現行碼),`.accessibilityElement`/`.accessibilityLabel` 為 SwiftUI 標準修飾子。
