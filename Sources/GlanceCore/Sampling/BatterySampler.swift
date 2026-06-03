public final class BatterySampler {
    private let source: BatteryStatsSource
    public init(source: BatteryStatsSource) { self.source = source }
    public func sample() -> BatterySnapshot? { source.read() }
}
