import SwiftUI

struct TrashActionBar: View {
    let selectedCount: Int
    let selectedSize: String
    let onTrash: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if selectedCount == 0 {
                Text("勾選項目以移到垃圾桶(可在 Finder 還原)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("已選取 \(selectedCount) 項,共 \(selectedSize) — 將移到垃圾桶(可在 Finder 還原)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清除選取", action: onClear)
                    .buttonStyle(.borderless)
                Button(role: .destructive, action: onTrash) {
                    Label("移到垃圾桶", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
