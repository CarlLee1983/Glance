# Memory Service Identification Implementation Plan

> **Status (2026-07-25):** 完成。經 `/grilling` + `/domain-modeling` 拷問後,範圍從原定的
> 「加分類標籤」擴大為「加分類 + 修分組 + 修結束鈕判準」。相關決策見
> `docs/adr/0001-aggregate-non-app-processes-by-executable-path.md`、
> `docs/adr/0002-terminate-eligibility-by-running-apps-membership.md`,詞彙見根目錄 `CONTEXT.md`。

**Goal:** 讓記憶體排行的每一列能回答「這是什麼、我能不能關掉它」——以「出身(Kind)」標籤說明來源,並確保能結束的列才長出結束鈕。

**Architecture:** 分類與聚合留在 GlanceCore(純函式、可單元測試);AppKit 圖示、row 繪製、結束鈕判準留在 GlanceApp。出身(Kind)與可處置性(Terminability)是兩條正交的線。

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, existing GlanceCore process sampling model.

---

### Task 1: Classification + Path Aggregation in GlanceCore

**Files:**
- Modify: `Sources/GlanceCore/Model/AppMemoryUsage.swift`
- Modify: `Sources/GlanceCore/Sampling/ProcessSampler.swift`
- Test: `Tests/GlanceCoreTests/ProcessSamplerMemoryAppsTests.swift`

- [x] **Step 1: Write failing tests** — 同路徑非 app 行程聚合成一列、不同路徑分開、巢狀 helper 為 `.appChild`、Apple 目錄為 `.systemService`、第三方 daemon 為 `.userProcess`、無路徑為 `.unknown`;單行程群組有 `soloPID`、多行程為 `nil`。
- [x] **Step 2: Run focused test** (`swift test --filter ProcessSamplerMemoryAppsTests`) → RED。
- [x] **Step 3: Implement**
  - `AppMemoryUsage.Kind`:`app` / `appChild` / `systemService` / `userProcess` / `unknown`(原 `commandLine` 更名為 `userProcess`,新增 `appChild`)。
  - 欄位:`kind` + `executablePath` + `soloPID: Int32?`(移除 `representativePID` / `representativePath` 與挑代表的 `representativeBytes` 邏輯)。
  - `aggregateMemory`:非 app 行程改以**執行檔路徑**為聚合鍵(見 ADR-0001);`kind` 以路徑中 `.app` 元件數判定(≥2 → `appChild`、==1 → `app`、0 → 系統/使用者/未知)。
- [x] **Step 4: Re-run focused test** → GREEN。

### Task 2: Source Subtitle + Terminability in GlanceApp

**Files:**
- Modify: `GlanceApp/Components/AppMemoryList.swift`

- [x] **Step 1: Source subtitle** — 以 `kind` 標籤 + 行程數 / `soloPID` + 來源路徑組成 subtitle。標籤:App / App 子行程 / 系統服務 / 背景程式 / 未知來源。
- [x] **Step 2: Terminability** — `eligible()` 改用 `terminator.isRunning(matching:)`(running-apps 成員資格,見 ADR-0002),取代 `bundleURL != nil`;巢狀 helper 不再長出無效結束鈕。
- [x] **Step 3: Verify**
  - `swift test` → 175 passed。
  - `swift build --product Glance` → 成功。

### 尚待後續(不在本次範圍)

- Row expansion:展開多行程群組看各子行程 pid / 記憶體明細(ROADMAP 已列)。
- Copy pid / path 動作(ROADMAP 已列)。
