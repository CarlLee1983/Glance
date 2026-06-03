/// 記憶體非差值指標,直接把 raw stats 轉成 snapshot。
public final class MemorySampler {
    private let source: MemoryStatsSource
    public init(source: MemoryStatsSource) { self.source = source }

    public func sample() -> MemorySnapshot? {
        guard let s = source.read() else { return nil }
        return MemorySnapshot(
            usedBytes: s.usedBytes,
            totalBytes: s.totalBytes,
            swapUsedBytes: s.swapUsedBytes,
            pressure: s.pressure)
    }
}
