# Glance Architecture

Glance is split into a pure data and policy layer (`GlanceCore`) and a macOS menu bar application layer (`GlanceApp`). The boundary is intentional: system sampling, grouping, scoring, cleanup safety, and uninstall safety live in testable Swift library code; AppKit and SwiftUI side effects stay in the app target.

## Targets

| Target | Path | Responsibility |
| --- | --- | --- |
| `GlanceCore` | `Sources/GlanceCore` | Snapshots, samplers, formatting, history, safety rules, cleanup, uninstall, health score |
| `glance-cli` | `Sources/glance-cli` | One-shot terminal status output for smoke testing core sampling |
| `Glance` | `GlanceApp` | Menu bar UI, settings, windows, AppKit integration, user actions |
| `GlanceCoreTests` | `Tests/GlanceCoreTests` | Unit tests for core data, math, grouping, safety, and workflow logic |

## Data Flow

```text
Bridge raw source
  -> Sampler
  -> Snapshot / usage model
  -> SystemSampler
  -> SystemSnapshot
  -> MetricsStore
  -> SwiftUI dropdown / menu bar label
```

Examples:

- CPU: `MachCPUSource` -> `CPUSampler` -> `CPUSnapshot`
- Memory: `MachMemorySource` -> `MemorySampler` -> `MemorySnapshot`
- Top processes: `LibprocSource` -> `ProcessSampler` -> CPU process rows and memory app rows
- Disk space: `StatfsDiskSource` -> `DiskSampler` -> `DiskSnapshot`
- Disk I/O: `IOBlockStorageIOSource` -> `DiskIOSampler` -> `DiskIOSnapshot`
- Sensors: `IOHIDThermalSource`, `IOReportPowerSource`, `SMCFanSource` -> `SensorSampler` -> `SensorSnapshot`

## GlanceCore Layout

| Directory | Responsibility |
| --- | --- |
| `Model/` | Immutable snapshot and usage types |
| `Sampling/` | Sampling logic and diff math |
| `Bridge/` | System API adapters: Mach, libproc, IOKit, statfs, getifaddrs |
| `History/` | Ring buffers and metric history |
| `Format/` | Byte, percentage, rate, and status formatting |
| `Health/` | Pure system health scoring |
| `Cleanup/` | Cleanup categories, sizing, scanning, execution, and safety |
| `Uninstall/` | App discovery, related-file matching, trash execution, and safety |
| `Process/` | Process-related pure helpers such as termination matching |
| `Store/` | Observable metric store and disk scan cache |

## GlanceApp Layout

| Directory | Responsibility |
| --- | --- |
| `Dropdown/` | Main menu bar dropdown sections |
| `MenuBar/` | Menu bar segment rendering and status colors |
| `Settings/` | Settings UI for update rate, login item, and menu bar segment selection |
| `Cleanup/` | Cleanup window and view model |
| `Uninstall/` | Uninstall window and view model |
| `DiskAnalyzer/` | Disk space analyzer window, tree navigation UI, and delete action bar |
| `Components/` | Shared SwiftUI components and AppKit action wrappers |
| `Login/` | Login item registration |

## Process And Memory Design

CPU top list is per process. Memory top list is grouped by identity: `.app` processes group under their bundle, and non-app processes group under their executable path. Different paths are never merged, so unrelated processes are not summed while genuine multi-process consumers (`node`, `claude`) are. See `docs/adr/0001-aggregate-non-app-processes-by-executable-path.md`.

Kind (origin) and terminability are two orthogonal axes: kind describes where the executable lives; whether a row can be terminated is decided separately by running-apps membership in the UI. See `CONTEXT.md` and `docs/adr/0002-terminate-eligibility-by-running-apps-membership.md`.

`AppMemoryUsage` stores:

- grouped app name and optional `.app` bundle URL
- total memory and process count
- source kind: app, app child (nested `.app` helper), system service, user process, or unknown
- executable path, and a solo pid present only for single-process rows

This lets the UI show a concise source subtitle such as `系統服務 · pid 10 · /usr/sbin/cfprefsd` or `背景程式 · 3 個行程 · /usr/local/bin/node`.

## Safety Boundaries

Cleanup and uninstall actions are deliberately conservative.

- Cleanup uses explicit categories and root allowlists.
- Disk analyzer trash operations require the target to stay inside the scanned root and reject symlink escape.
- App uninstall moves items to the trash instead of permanently deleting them.
- Uninstall related files are matched by bundle ID and constrained to known support directories.
- Destructive side effects are wrapped behind injectable closures/services where practical so safety rules can be unit-tested.

## Private API Boundary

Glance uses private macOS interfaces for thermal and power readings:

- `IOHIDEventSystemClient` for thermal sensors
- `IOReport` for SoC power

Those are isolated in `Bridge/`. Because of this, Glance is intended for direct distribution, not Mac App Store distribution.
