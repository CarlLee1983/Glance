import AppKit
import SwiftUI
import GlanceCore

struct DiskSpaceAnalyzerWindow: View {
    @StateObject private var viewModel = DiskSpaceAnalyzerViewModel()
    @State private var showTrashConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary
            if viewModel.navigator != nil { breadcrumb }
            content
            TrashActionBar(
                selectedCount: viewModel.selection.count,
                selectedSize: Formatters.bytes(viewModel.selectedTotalBytes),
                onTrash: { showTrashConfirm = true },
                onClear: viewModel.clearSelection
            )
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 540)
        .onAppear { viewModel.onAppear() }
        .confirmationDialog(
            "移到垃圾桶?",
            isPresented: $showTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("移到垃圾桶(\(viewModel.selection.count) 項)", role: .destructive) {
                viewModel.moveSelectedToTrash()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("將把所選 \(viewModel.selection.count) 項(共 \(Formatters.bytes(viewModel.selectedTotalBytes)))移到垃圾桶,可在 Finder 還原。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("磁碟空間分析")
                    .font(.system(size: 20, weight: .semibold))
                Text(viewModel.rootURL.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    chooseRoot()
                } label: {
                    Label("選擇資料夾…", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    if viewModel.isScanning { viewModel.cancelScan() } else { viewModel.startScan() }
                } label: {
                    Label(
                        viewModel.isScanning ? "取消" : "重新掃描",
                        systemImage: viewModel.isScanning ? "xmark.circle" : "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summary: some View {
        ScanSummaryStrip(
            folderSize: Formatters.bytes(viewModel.currentFolderSize),
            itemCount: viewModel.currentChildren.count,
            selectedCount: viewModel.selection.count,
            selectedSize: Formatters.bytes(viewModel.selectedTotalBytes),
            availableSize: Formatters.bytes(viewModel.availableDiskBytes)
        )
    }

    private var breadcrumb: some View {
        BreadcrumbBar(nodes: viewModel.breadcrumb) { depth in
            viewModel.jump(toDepth: depth)
        }
    }

    private var content: some View {
        let parentSize = max(viewModel.currentFolderSize, 1)
        return List(viewModel.currentChildren) { node in
            DiskNodeRow(
                node: node,
                fraction: Double(node.sizeBytes) / Double(parentSize),
                isSelected: viewModel.selection.contains(node.id),
                onToggle: { viewModel.toggleSelection(node.id) },
                onDrill: { viewModel.drill(into: node) },
                onReveal: { viewModel.reveal(node.url) }
            )
            .listRowInsets(EdgeInsets())
        }
        .overlay {
            if viewModel.currentChildren.isEmpty {
                Text(viewModel.isScanning ? "掃描中…" : "沒有項目")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLine: String {
        if viewModel.isScanning {
            return viewModel.currentPath ?? "掃描中…(已掃描 \(viewModel.scannedCount))"
        }
        if let last = viewModel.lastScannedText { return last }
        return viewModel.statusText
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = viewModel.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.chooseRoot(url)
        }
    }
}
