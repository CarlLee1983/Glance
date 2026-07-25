# Glance

Glance 是 macOS 選單列主機狀態工具。它提供 CPU、記憶體、網路、磁碟、磁碟 I/O、電池、感測器、系統健康分數、磁碟空間分析、清理與 App 解除安裝等功能。

專案分成兩層:

- `GlanceCore`: 純資料、取樣、格式化、歷史、安全護欄與健康評分邏輯。
- `GlanceApp`: SwiftUI/AppKit 選單列 App、設定、視窗與使用者動作。

## Current Capabilities

- 可自訂選單列欄位與順序。
- 下拉視窗顯示各項系統指標與歷史趨勢。
- CPU top process 與記憶體 top app/process 列表。
- 記憶體列表可辨識 `App`、`App 子行程`、`系統服務`、`背景程式`、`未知來源`，並顯示 pid 或來源路徑。
- 系統健康分數橫幅。
- 磁碟空間分析與安全移到垃圾桶。
- 清理白名單快取/日誌/開發工具快取。
- App 解除安裝與 bundle ID 關聯檔比對。
- CPU/GPU 溫度、SoC 功耗、風扇、電池健康度等進階資訊。

## Requirements

- macOS 14+
- Swift 5.9+
- Xcode command line tools
- XcodeGen only when regenerating/building the Xcode project

## Quick Commands

```bash
swift test
swift build --product Glance
swift run glance-cli
```

`glance-cli` prints a one-shot system snapshot in the terminal. `Glance` is the menu bar app product.

## Run The Menu Bar App Locally

For the local user-installed app bundle:

```bash
swift build --product Glance
cp .build/debug/Glance /Users/carl/Applications/Glance.app/Contents/MacOS/Glance
chmod +x /Users/carl/Applications/Glance.app/Contents/MacOS/Glance
pkill -x Glance || true
open /Users/carl/Applications/Glance.app
```

Verify the running app and binary:

```bash
pgrep -fl Glance
shasum -a 256 .build/debug/Glance /Users/carl/Applications/Glance.app/Contents/MacOS/Glance
```

## Xcode Build

```bash
xcodegen generate
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' build
```

Then open the built `Glance.app` from the Xcode build products.

## Documentation

| Document | Purpose |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Targets, data flow, source layout, safety boundaries |
| [docs/FEATURES.md](docs/FEATURES.md) | Current user-facing features and known limits |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Build, test, local restart, and development conventions |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Product and architecture decisions not to rediscover |
| [docs/ROADMAP.md](docs/ROADMAP.md) | High-signal follow-up work and explicit non-goals |
| [docs/superpowers](docs/superpowers) | Historical design specs and implementation plans |

## Important Constraints

- Glance uses private macOS APIs for some sensor readings, so it is intended for direct distribution rather than Mac App Store distribution.
- The project intentionally does not provide a memory purge / sudo optimize button.
- Cleanup permanently deletes selected allowlisted cleanup contents.
- Uninstall and disk analyzer delete actions prefer moving items to trash with safety checks.

## Verification

Before claiming changes are ready:

```bash
swift test
swift build --product Glance
```

For model or sampler changes, run the focused test first, then the full suite.
