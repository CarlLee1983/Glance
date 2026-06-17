import SwiftUI
import GlanceCore

struct BreadcrumbBar: View {
    let nodes: [DiskNode]            // root...current
    let onJump: (Int) -> Void        // depth: 0 = root

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        onJump(index)
                    } label: {
                        Text(node.name)
                            .font(.system(size: 11, weight: index == nodes.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == nodes.count - 1 ? Color.primary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
