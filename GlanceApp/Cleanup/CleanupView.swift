import SwiftUI
import GlanceCore

struct CleanupView: View {
    @StateObject private var viewModel = CleanupViewModel()
    @Environment(\.dismiss) private var dismiss

    private let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 440)
        .sheet(isPresented: confirmBinding) { confirmationSheet }
        .onAppear {
            if viewModel.phase == .scanning, viewModel.rows.isEmpty {
                viewModel.startScan()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("清理")
                .font(.system(size: 20, weight: .semibold))
            Text("掃描可回收空間,勾選後永久刪除。快取會在 App 下次使用時自動重建。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Content router

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .scanning:
            scanningView
        case .selecting, .confirming:
            selectionView
        case .running:
            runningView
        case .done:
            doneView
        }
    }

    // MARK: Scanning

    private var scanningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("掃描中…")
                .font(.system(size: 13))
            Text(viewModel.currentPath ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    // MARK: Confirmation sheet

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .confirming },
            set: { if !$0 { viewModel.cancelConfirmation() } }
        )
    }

    private var confirmationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("永久刪除", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.red)

            Text("將永久刪除約 \(Formatters.bytes(viewModel.selectedBytes)),無法復原。快取會在 App 下次使用時自動重建。")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.selectedRows) { row in
                    HStack {
                        Text(row.category.displayName)
                        Spacer()
                        Text(Formatters.bytes(row.result.reclaimableBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }

            HStack {
                Spacer()
                Button("取消") { viewModel.cancelConfirmation() }
                    .keyboardShortcut(.cancelAction)
                Button("永久刪除") { viewModel.confirmDelete() }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    // MARK: Running

    private var runningView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("清理中…")
                .font(.system(size: 13))
            Text(viewModel.currentPath ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    // MARK: Helpers

    private func pathSummary(_ category: CleanupCategory) -> String {
        category.roots
            .map { $0.path.replacingOccurrences(of: homePath, with: "~") }
            .joined(separator: "、")
    }
}
