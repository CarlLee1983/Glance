import SwiftUI

struct ScanSummaryStrip: View {
    let folderSize: String
    let itemCount: Int
    let selectedCount: Int
    let selectedSize: String
    let availableSize: String

    var body: some View {
        HStack(spacing: 10) {
            tile("目前資料夾", folderSize, accent: false)
            tile("項目數", "\(itemCount)", accent: false)
            tile("已選取", selectedCount == 0 ? "—" : "\(selectedCount) 項 · \(selectedSize)", accent: selectedCount > 0)
            tile("磁碟可用", availableSize, accent: false)
        }
    }

    private func tile(_ title: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ? Color.red : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
