import SwiftUI
import GlanceCore

struct DiskNodeRow: View {
    let node: DiskNode
    let fraction: Double            // node.sizeBytes / 父資料夾總大小
    let isSelected: Bool
    let onToggle: () -> Void
    let onDrill: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            checkbox
            icon
            Text(node.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)

            ProgressView(value: max(0, min(1, fraction)))
                .progressViewStyle(.linear)
                .tint(node.kind == .folder ? Color.accentColor : Color.gray)

            Text(Formatters.bytes(node.sizeBytes))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)

            Text(modifiedText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)

            Button(action: onDrill) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .opacity(node.isDrillable ? 1 : 0)
            .disabled(!node.isDrillable)

            Button(action: onReveal) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .opacity(node.isAggregate ? 0 : 1)
            .disabled(node.isAggregate)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(isSelected ? Color.red.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if node.isDrillable { onDrill() } }
    }

    private var checkbox: some View {
        Button(action: onToggle) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.red : Color.secondary)
        }
        .buttonStyle(.borderless)
        .opacity(node.isAggregate ? 0.25 : 1)
        .disabled(node.isAggregate)
    }

    private var icon: some View {
        Image(systemName: node.isAggregate ? "ellipsis.circle" : (node.kind == .folder ? "folder.fill" : "doc.fill"))
            .font(.system(size: 13))
            .foregroundStyle(node.kind == .folder && !node.isAggregate ? Color.accentColor : Color.secondary)
            .frame(width: 16)
    }

    private var modifiedText: String {
        guard let modifiedAt = node.modifiedAt else { return "" }
        return modifiedAt.formatted(date: .abbreviated, time: .omitted)
    }
}
