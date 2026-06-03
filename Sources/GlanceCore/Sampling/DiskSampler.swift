public final class DiskSampler {
    private let source: DiskStatsSource
    public init(source: DiskStatsSource) { self.source = source }

    public func sample() -> DiskSnapshot? {
        guard let s = source.read() else { return nil }
        return DiskSnapshot(totalBytes: s.totalBytes, usedBytes: s.usedBytes)
    }
}
