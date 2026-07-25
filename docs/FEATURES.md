# Glance Features

This document lists the current user-facing capabilities and their known limits.

## Menu Bar Status

- Configurable menu bar segments for CPU, memory, network, disk, disk I/O, battery, CPU temperature, and power.
- Display modes: icon plus value, or icon-only.
- Segment order is user-configurable.
- Status colors reflect metric severity where applicable.

Known limits:

- On notched MacBooks, too many menu bar segments can be hidden by the notch. Use icon-only mode or a menu bar manager.

## Main Dropdown

The dropdown shows current system metrics with compact historical context:

- System health banner
- CPU card with usage sparkline and top CPU processes
- Memory card with pressure sparkline and top memory apps/processes
- Network card with send/receive rates
- Disk card with capacity and disk I/O rates/history
- Battery card with charge and advanced battery details
- Sensors card with temperature, power, and fan readings where available

## Memory List

The memory card aggregates by identity: `.app` processes group under their bundle, and non-app processes group under their executable path (so multi-process consumers like `node`/`claude` are summed, not scattered). Different paths are never merged.

Each row shows:

- name
- memory usage
- source kind: `App`, `App 子行程` (helper nested in another `.app`), `系統服務`, `背景程式` (non-app, non-Apple-system process), or `未知來源`
- pid (single-process rows) or process count
- bundle path or executable path when known

A row shows a graceful terminate button only when its bundle is registered in `NSWorkspace.runningApplications` (the same matcher used to actually terminate), so nested helpers and non-app rows never get a button that does nothing. Glance does not force quit.

Known limits:

- Some protected system processes do not expose an executable path; these appear as unknown source.
- Memory grouping depends on executable paths and `.app` bundle path structure.

## Disk Space Analyzer

The disk card can open a disk space analyzer window.

Current behavior:

- Scans the selected root on demand.
- Shows large folders/files as a navigable tree.
- Supports breadcrumb navigation.
- Supports opening selected items in Finder.
- Supports moving eligible scanned items to the trash with safety checks.

Known limits:

- Scans can be expensive on very large trees.
- Symlinks are not followed.
- Delete/trash operations are constrained by safety rules and may skip protected or unsafe paths.

## Cleanup

The cleanup window scans explicit categories:

| Category | Paths |
| --- | --- |
| Trash | `~/.Trash` |
| User caches and logs | `~/Library/Caches`, `~/Library/Logs` |
| Developer caches | `~/Library/Developer/Xcode/DerivedData`, `~/.npm`, `~/.cache` |

Workflow:

1. Scan.
2. Preview category sizes.
3. Select categories.
4. Confirm.
5. Permanently delete selected cleanup contents.

Known limits:

- Cleanup is permanent deletion, not trash. The confirmation step matters.
- Cleanup is intentionally limited to explicit allowlisted roots.

## App Uninstaller

The uninstall window:

- Lists apps from `/Applications` and `~/Applications`.
- Reads bundle ID and display name from app bundles.
- Finds related files in common `~/Library` support locations by bundle ID.
- Blocks uninstall if the app is currently running.
- Moves the app and selected related files to the trash.

Known limits:

- Matching is intentionally conservative; some related files may not be detected.
- App Store distribution is not targeted.

## Health Score

The health banner computes a 0-100 score from the current snapshot.

Inputs include:

- CPU load
- memory usage and pressure
- disk capacity
- CPU temperature
- battery health/cycle data when available

Score bands:

| Score | Label |
| --- | --- |
| `85...100` | 系統健康 |
| `65...84` | 良好 |
| `45...64` | 普通 |
| `<45` | 注意 |

## Sensors

Sensor readings can include:

- CPU temperature
- GPU temperature where available
- SoC power
- fan RPM where available

Known limits:

- Thermal and power readings depend on private APIs and may vary across macOS versions and hardware.
- Fan RPM is absent on fanless Macs.
