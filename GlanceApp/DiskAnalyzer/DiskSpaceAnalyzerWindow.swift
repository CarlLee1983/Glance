import AppKit
import SwiftUI
import GlanceCore

struct DiskSpaceAnalyzerWindow: View {
    @StateObject private var viewModel = DiskSpaceAnalyzerViewModel()
    @State private var selectedView: ResultView = .folders

    private enum ResultView: String, CaseIterable, Identifiable {
        case folders = "Folders"
        case files = "Files"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryStrip
            resultPicker
            resultList
            footer
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 520)
        .onAppear {
            if viewModel.phase == .idle {
                viewModel.startScan()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disk Space Analyzer")
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

            Button {
                if viewModel.isScanning {
                    viewModel.cancelScan()
                } else {
                    viewModel.startScan()
                }
            } label: {
                Label(
                    viewModel.isScanning ? "Cancel" : "Rescan",
                    systemImage: viewModel.isScanning ? "xmark.circle" : "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            summaryTile("Status", viewModel.statusText)
            summaryTile("Scanned", "\(viewModel.scannedCount)")
            summaryTile("Skipped", "\(viewModel.skippedCount)")
            summaryTile("Visible", "\(currentItems.count)")
        }
    }

    private var resultPicker: some View {
        Picker("Results", selection: $selectedView) {
            ForEach(ResultView.allCases) { view in
                Text(view.rawValue).tag(view)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
    }

    private var resultList: some View {
        List(currentItems) { item in
            HStack(spacing: 12) {
                Image(systemName: item.kind == .folder ? "folder" : "doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(item.kind == .folder ? .blue : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text(item.url.path)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formatters.bytes(item.sizeBytes))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    Text(modifiedDateText(for: item))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 112, alignment: .trailing)

                Button {
                    reveal(item.url)
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if currentItems.isEmpty {
                Text(viewModel.isScanning ? "Scanning..." : "No results")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(viewModel.skippedCount == 0 ? "No skipped paths" : "\(viewModel.skippedCount) paths skipped")
            Spacer()
            Text("Read-only: files are only revealed in Finder. Nothing is deleted or moved.")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func summaryTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var statusLine: String {
        if let currentPath = viewModel.currentPath, viewModel.isScanning {
            return currentPath
        }

        return viewModel.statusText
    }

    private var currentItems: [DiskSpaceItem] {
        selectedView == .folders ? viewModel.largestFolders : viewModel.largestFiles
    }

    private func modifiedDateText(for item: DiskSpaceItem) -> String {
        guard let modifiedAt = item.modifiedAt else { return "Modified --" }
        return modifiedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
