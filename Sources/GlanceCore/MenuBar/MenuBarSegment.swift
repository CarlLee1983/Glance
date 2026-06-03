/// 選單列上可顯示的欄位。allCases 的順序即為畫面顯示順序。
public enum MenuBarSegment: String, CaseIterable, Codable {
    case cpu, memory, network
}

/// 把 snapshot 依選定欄位組成選單列精簡字串,例如 "23% · 61% · ↓2.1M"。
public enum MenuBarText {
    public static func compose(snapshot: SystemSnapshot?, segments: [MenuBarSegment]) -> String {
        guard let snapshot else { return "—" }
        var parts: [String] = []
        for seg in segments {
            switch seg {
            case .cpu:
                if let c = snapshot.cpu { parts.append(Formatters.percent(c.totalUsage)) }
            case .memory:
                if let m = snapshot.memory { parts.append(Formatters.percent(m.usedFraction)) }
            case .network:
                if let n = snapshot.network { parts.append("↓\(Formatters.rateCompact(n.downBytesPerSec))") }
            }
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
