# Optimize Delete and Cleanup UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optimize the Delete and Cleanup UI in Glance App using macOS modern utility styling, actual macOS app icon rendering, selective uninstallation file deletion, and Bento card layouts.

**Architecture:** Build a SwiftUI component `AppIconView` utilizing `NSWorkspace` to load native app icons. Extend `UninstallViewModel` to maintain a set of selected related files, filtering the uninstall plan before running the deletion. Upgrade both `UninstallView` and `CleanupView` layouts with premium styles and SF Symbols.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSWorkspace`).

---

### Task 1: Create AppIconView Component

**Files:**
- Create: `GlanceApp/Components/AppIconView.swift`

- [ ] **Step 1: Create AppIconView.swift**

Create the new file `GlanceApp/Components/AppIconView.swift` with a SwiftUI view that loads macOS application icons.

```swift
import SwiftUI
import AppKit

struct AppIconView: View {
    let bundleURL: URL
    var size: CGFloat = 32

    var body: some View {
        if let image = NSWorkspace.shared.icon(forFile: bundleURL.path) as NSImage? {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 2: Verify Compilation**

Run the build command to ensure the new component compiles correctly.

Run: `swift build --product Glance`
Expected: Build of product 'Glance' complete!

- [ ] **Step 3: Commit Changes**

Run:
```bash
git add GlanceApp/Components/AppIconView.swift
git commit -m "feat: add AppIconView SwiftUI component"
```

---

### Task 2: Update UninstallViewModel to Support Selection

**Files:**
- Modify: `GlanceApp/Uninstall/UninstallViewModel.swift`

- [ ] **Step 1: Add selection properties and logic to UninstallViewModel**

Modify `GlanceApp/Uninstall/UninstallViewModel.swift` to add `@Published var selectedRelatedFiles: Set<RelatedFile> = []`, derived properties for selected bytes/items, update `select(_ app:)` to select all files by default, add `toggleRelatedFile(_ file:)`, and modify `confirmUninstall()` to filter the `UninstallPlan` prior to execution.

```swift
<<<<
    @Published private(set) var runResult: UninstallRunResult?
====
    @Published private(set) var runResult: UninstallRunResult?
    @Published var selectedRelatedFiles: Set<RelatedFile> = []
>>>>
```

```swift
<<<<
    var canUninstall: Bool { phase == .preview && !selectedAppRunning }
====
    var canUninstall: Bool { phase == .preview && !selectedAppRunning }

    var selectedTotalBytes: UInt64 {
        guard let plan = plan else { return 0 }
        return plan.app.sizeBytes + selectedRelatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    var selectedItemCount: Int {
        1 + selectedRelatedFiles.count
    }
>>>>
```

```swift
<<<<
    private func applyPlan(_ plan: UninstallPlan, running: Bool, generation: Int) {
        guard generation == self.generation else { return }
        self.plan = plan
        selectedAppRunning = running
        phase = .preview
        buildTask = nil
    }
====
    private func applyPlan(_ plan: UninstallPlan, running: Bool, generation: Int) {
        guard generation == self.generation else { return }
        self.plan = plan
        self.selectedRelatedFiles = Set(plan.relatedFiles)
        selectedAppRunning = running
        phase = .preview
        buildTask = nil
    }
>>>>
```

```swift
<<<<
    func toggleRelatedFile(_ file: RelatedFile) {
        if selectedRelatedFiles.contains(file) {
            selectedRelatedFiles.remove(file)
        } else {
            selectedRelatedFiles.insert(file)
        }
    }

    func confirmUninstall() {
        guard phase == .confirming, let plan else { return }
        // App 可能在預覽後才被啟動;移到垃圾桶前重新確認,執行中則退回預覽顯示警告。
        guard !isRunning(plan.app.bundleID) else {
            selectedAppRunning = true
            phase = .preview
            return
        }
        runTask?.cancel()
        generation += 1
        let generation = generation
        phase = .running
        currentPath = nil
        runTask = Task { [weak self, uninstaller] in
            let result = await uninstaller.run(plan: plan) { [weak self] progress in
                await self?.applyRunProgress(progress, generation: generation)
            }
            await self?.applyRunResult(result, generation: generation)
        }
    }
====
    func toggleRelatedFile(_ file: RelatedFile) {
        if selectedRelatedFiles.contains(file) {
            selectedRelatedFiles.remove(file)
        } else {
            selectedRelatedFiles.insert(file)
        }
    }

    func confirmUninstall() {
        guard phase == .confirming, let plan else { return }
        // App 可能在預覽後才被啟動;移到垃圾桶前重新確認,執行中則退回預覽顯示警告。
        guard !isRunning(plan.app.bundleID) else {
            selectedAppRunning = true
            phase = .preview
            return
        }
        runTask?.cancel()
        generation += 1
        let generation = generation
        phase = .running
        currentPath = nil
        // Build plan containing only selected related files
        let filteredPlan = UninstallPlan(app: plan.app, relatedFiles: Array(selectedRelatedFiles))
        runTask = Task { [weak self, uninstaller] in
            let result = await uninstaller.run(plan: filteredPlan) { [weak self] progress in
                await self?.applyRunProgress(progress, generation: generation)
            }
            await self?.applyRunResult(result, generation: generation)
        }
    }
>>>>
```

- [ ] **Step 2: Verify Compilation**

Run compilation check.

Run: `swift build --product Glance`
Expected: Build of product 'Glance' complete!

- [ ] **Step 3: Commit Changes**

Run:
```bash
git add GlanceApp/Uninstall/UninstallViewModel.swift
git commit -m "feat: support selective uninstallation in UninstallViewModel"
```

---

### Task 3: Update UninstallView UI

**Files:**
- Modify: `GlanceApp/Uninstall/UninstallView.swift`

- [ ] **Step 1: Replace app icon and list row in UninstallView**

Modify `GlanceApp/Uninstall/UninstallView.swift` to render `AppIconView` in the list, the preview header, render checkboxes for related files, and show selected bytes/item count in actions & sheets.

```swift
<<<<
            List(viewModel.filteredApps) { app in
                Button {
                    viewModel.select(app)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
====
            List(viewModel.filteredApps) { app in
                Button {
                    viewModel.select(app)
                } label: {
                    HStack(spacing: 12) {
                        AppIconView(bundleURL: app.bundleURL, size: 24)
                        VStack(alignment: .leading, spacing: 3) {
>>>>
```

```swift
<<<<
    private var previewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = viewModel.plan {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.app.name).font(.system(size: 15, weight: .semibold))
                        Text(plan.app.bundleID)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatters.bytes(plan.totalBytes))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                if viewModel.selectedAppRunning {
                    Label("此 App 執行中,請先結束後再解除安裝。", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }

                List {
                    Section("本體") {
                        row(path: plan.app.bundleURL.path, bytes: plan.app.sizeBytes)
                    }
                    Section("關聯檔(\(plan.relatedFiles.count))") {
                        if plan.relatedFiles.isEmpty {
                            Text("無").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            ForEach(plan.relatedFiles) { file in
                                row(path: file.url.path, bytes: file.sizeBytes)
                            }
                        }
                    }
                }

                HStack {
                    Button("返回") { viewModel.backToList() }
                    Spacer()
                    Button("移到垃圾桶…") { viewModel.requestConfirmation() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canUninstall)
                }
            }
        }
    }

    private func row(path: String, bytes: UInt64) -> some View {
        HStack {
            Text(path.replacingOccurrences(of: homePath, with: "~"))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(Formatters.bytes(bytes))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
====
    private var previewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = viewModel.plan {
                HStack(spacing: 12) {
                    AppIconView(bundleURL: plan.app.bundleURL, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.app.name).font(.system(size: 15, weight: .semibold))
                        Text(plan.app.bundleID)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatters.bytes(viewModel.selectedTotalBytes))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                if viewModel.selectedAppRunning {
                    Label("此 App 執行中,請先結束後再解除安裝。", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }

                List {
                    Section("本體") {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            row(path: plan.app.bundleURL.path, bytes: plan.app.sizeBytes)
                        }
                    }
                    Section("關聯檔(\(plan.relatedFiles.count))") {
                        if plan.relatedFiles.isEmpty {
                            Text("無").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            ForEach(plan.relatedFiles) { file in
                                let fileSelected = viewModel.selectedRelatedFiles.contains(file)
                                Button {
                                    viewModel.toggleRelatedFile(file)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: fileSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14))
                                            .foregroundStyle(fileSelected ? .blue : .secondary)
                                        row(path: file.url.path, bytes: file.sizeBytes)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(alignment: .center) {
                    Button("返回") { viewModel.backToList() }
                    Spacer()
                    Text("已選 \(viewModel.selectedRelatedFiles.count)/\(plan.relatedFiles.count) 項 · 合計 \(Formatters.bytes(viewModel.selectedTotalBytes))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("移到垃圾桶…") { viewModel.requestConfirmation() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canUninstall)
                }
            }
        }
    }

    private func row(path: String, bytes: UInt64) -> some View {
        HStack {
            Text(path.replacingOccurrences(of: homePath, with: "~"))
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(Formatters.bytes(bytes))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
>>>>
```

```swift
<<<<
            if let plan = viewModel.plan {
                Text("將把「\(plan.app.name)」本體與關聯 \(plan.relatedFiles.count) 件(合計約 \(Formatters.bytes(plan.totalBytes)))移到垃圾桶。可從垃圾桶復原。")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
====
            if let plan = viewModel.plan {
                Text("將把「\(plan.app.name)」本體與選取的 \(viewModel.selectedRelatedFiles.count) 件關聯檔 (合計約 \(Formatters.bytes(viewModel.selectedTotalBytes))) 移到垃圾桶。可從垃圾桶復原。")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
>>>>
```

- [ ] **Step 2: Verify Compilation**

Run compilation check.

Run: `swift build --product Glance`
Expected: Build of product 'Glance' complete!

- [ ] **Step 3: Commit Changes**

Run:
```bash
git add GlanceApp/Uninstall/UninstallView.swift
git commit -m "feat: show app icons and checkable related files in UninstallView"
```

---

### Task 4: Optimize CleanupView UI

**Files:**
- Modify: `GlanceApp/Cleanup/CleanupView.swift`

- [ ] **Step 1: Replace selection list with Bento grid card layout and add ring progress in done screen**

Modify `GlanceApp/Cleanup/CleanupView.swift` to use card styling for categories with SF Symbols, cleaner styling for headers/details, and an elegant circular space reclamation progress chart in `doneView`.

```swift
<<<<
    // MARK: Selection

    private var selectionView: some View {
        VStack(spacing: 12) {
            List(viewModel.rows) { row in
                Button {
                    viewModel.toggle(row.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(row.isSelected ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.category.displayName)
                                .font(.system(size: 13, weight: .medium))
                            Text(pathSummary(row.category))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: 12)

                        Text(Formatters.bytes(row.result.reclaimableBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("已選 \(viewModel.selectedCount) 類 · \(Formatters.bytes(viewModel.selectedBytes))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.requestConfirmation()
                } label: {
                    Text("清理選取…")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasSelection)
            }
        }
    }
====
    // MARK: Selection

    private var selectionView: some View {
        VStack(spacing: 14) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(viewModel.rows) { row in
                        Button {
                            viewModel.toggle(row.id)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(row.isSelected ? .blue : .secondary)

                                let (iconName, iconColor) = getCategoryIcon(row.category.id)
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(iconColor.opacity(0.12))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: iconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(iconColor)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.category.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(pathSummary(row.category))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 12)

                                Text(Formatters.bytes(row.result.reclaimableBytes))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(row.result.reclaimableBytes > 0 ? .primary : .secondary)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(row.isSelected ? Color.blue.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }

            HStack {
                Text("已選 \(viewModel.selectedCount) 類 · \(Formatters.bytes(viewModel.selectedBytes))")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.requestConfirmation()
                } label: {
                    Text("清理選取…")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasSelection)
            }
        }
    }

    private func getCategoryIcon(_ id: CleanupCategoryID) -> (String, Color) {
        switch id {
        case .trash:
            return ("trash", .red)
        case .userCaches:
            return ("folder.badge.gearshape", .blue)
        case .devCaches:
            return ("terminal", .green)
        }
    }
>>>>
```

```swift
<<<<
    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.18), lineWidth: 10)
                    .frame(width: 120, height: 120)
                VStack(spacing: 2) {
                    Text(Formatters.bytes(viewModel.runResult?.totalReclaimedBytes ?? 0))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已回收")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("刪除 \(viewModel.runResult?.totalDeletedCount ?? 0) 項 · 跳過 \(viewModel.runResult?.skippedCount ?? 0) 項(無權限)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
====
    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.08), lineWidth: 10)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0.0, to: 1.0)
                    .stroke(
                        AngularGradient(
                            colors: [.green, .green.opacity(0.7), .green],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 2)

                VStack(spacing: 2) {
                    Text(Formatters.bytes(viewModel.runResult?.totalReclaimedBytes ?? 0))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已回收")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("刪除 \(viewModel.runResult?.totalDeletedCount ?? 0) 項 · 跳過 \(viewModel.runResult?.skippedCount ?? 0) 項 (無權限)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
>>>>
```

- [ ] **Step 2: Verify Compilation**

Run compilation check.

Run: `swift build --product Glance`
Expected: Build of product 'Glance' complete!

- [ ] **Step 3: Commit Changes**

Run:
```bash
git add GlanceApp/Cleanup/CleanupView.swift
git commit -m "style: optimize CleanupView with Bento grids and space ring chart"
```
