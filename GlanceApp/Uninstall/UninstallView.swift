import SwiftUI
import GlanceCore

struct UninstallView: View {
    @StateObject private var viewModel = UninstallViewModel()
    @Environment(\.dismiss) private var dismiss

    private let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)
        .sheet(isPresented: confirmBinding) { confirmationSheet }
        .onAppear {
            if viewModel.phase == .loading, viewModel.apps.isEmpty {
                viewModel.load()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("解除安裝")
                .font(.system(size: 20, weight: .semibold))
            Text("選擇 App,連帶移除其關聯檔。本體與關聯檔會移到垃圾桶,可從垃圾桶復原。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            centeredProgress("讀取 App 一覽…")
        case .list:
            listView
        case .building:
            centeredProgress("分析關聯檔…")
        case .preview, .confirming:
            previewView
        case .running:
            centeredProgress("移到垃圾桶…", path: viewModel.currentPath)
        case .done:
            doneView
        }
    }

    private func centeredProgress(_ title: String, path: String? = nil) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(title).font(.system(size: 13))
            if let path {
                Text(path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: List

    private var listView: some View {
        VStack(spacing: 10) {
            TextField("搜尋 App", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            List(viewModel.filteredApps) { app in
                Button {
                    viewModel.select(app)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .medium))
                            Text(app.bundleID)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 12)
                        Text(Formatters.bytes(app.sizeBytes))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Preview

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

    // MARK: Confirmation sheet

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .confirming },
            set: { if !$0 { viewModel.cancelConfirmation() } }
        )
    }

    private var confirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("解除安裝", systemImage: "trash.fill")
                .font(.system(size: 16, weight: .semibold))

            if let plan = viewModel.plan {
                Text("將把「\(plan.app.name)」本體與關聯 \(plan.relatedFiles.count) 件(合計約 \(Formatters.bytes(plan.totalBytes)))移到垃圾桶。可從垃圾桶復原。")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消") { viewModel.cancelConfirmation() }
                    .keyboardShortcut(.cancelAction)
                Button("移到垃圾桶") { viewModel.confirmUninstall() }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: Done

    private var doneView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.18), lineWidth: 10)
                    .frame(width: 120, height: 120)
                VStack(spacing: 2) {
                    Text(Formatters.bytes(viewModel.runResult?.freedBytes ?? 0))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("已釋放").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text("移到垃圾桶 \(viewModel.runResult?.trashedCount ?? 0) 項 · 跳過 \(viewModel.runResult?.skippedCount ?? 0) 項(無權限)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("繼續解除安裝") { viewModel.backToList() }
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
