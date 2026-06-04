import SwiftUI
import GlanceCore

struct MetricCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: Color
    let value: String
    let detail: String
    let status: MetricStatus?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(
                            colors: [accent.opacity(0.14), accent.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(accent.opacity(0.18), lineWidth: 0.8)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .bold))
                        if let status {
                            StatusBadge(status: status, accent: accent)
                        }
                    }
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }

            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.opacity(0.2))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.22),
                            .primary.opacity(0.04),
                            .primary.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

private struct StatusBadge: View {
    let status: MetricStatus
    let accent: Color

    var body: some View {
        let badgeColor: Color = {
            switch status {
            case .critical: return .red
            case .elevated: return .orange
            case .charging: return .mint
            case .normal: return accent
            }
        }()

        Text(status.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(badgeColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(badgeColor.opacity(0.2), lineWidth: 0.5)
            }
    }
}

struct EmptyMetricLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}
