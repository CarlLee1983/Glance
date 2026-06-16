import XCTest
@testable import GlanceCore

final class HealthScoreCalculatorTests: XCTestCase {
    func testBandBoundaries() {
        XCTAssertEqual(HealthBand.from(score: 100), .excellent)
        XCTAssertEqual(HealthBand.from(score: 85), .excellent)
        XCTAssertEqual(HealthBand.from(score: 84), .good)
        XCTAssertEqual(HealthBand.from(score: 65), .good)
        XCTAssertEqual(HealthBand.from(score: 64), .fair)
        XCTAssertEqual(HealthBand.from(score: 45), .fair)
        XCTAssertEqual(HealthBand.from(score: 44), .needsAttention)
        XCTAssertEqual(HealthBand.from(score: 0), .needsAttention)
    }

    func testBandLabels() {
        XCTAssertEqual(HealthBand.excellent.label, "系統健康")
        XCTAssertEqual(HealthBand.good.label, "良好")
        XCTAssertEqual(HealthBand.fair.label, "普通")
        XCTAssertEqual(HealthBand.needsAttention.label, "注意")
    }

    // MARK: - helpers

    private func snapshot(
        cpuFraction: Double = 0.1,
        memFraction: Double = 0.3,
        pressure: MemoryPressure = .normal,
        diskFraction: Double = 0.3,
        cpuTemp: Double? = 40,
        battery: BatterySnapshot? = nil
    ) -> SystemSnapshot {
        let cpu = CPUSnapshot(totalUsage: cpuFraction, user: cpuFraction, system: 0, idle: 1 - cpuFraction)
        let total: UInt64 = 16_000_000_000
        let mem = MemorySnapshot(
            usedBytes: UInt64(Double(total) * memFraction),
            totalBytes: total,
            swapUsedBytes: 0,
            pressure: pressure
        )
        let disk = DiskSnapshot(
            totalBytes: total,
            usedBytes: UInt64(Double(total) * diskFraction)
        )
        let sensors = SensorSnapshot(cpuTemperature: cpuTemp)
        return SystemSnapshot(
            cpu: cpu, memory: mem, network: nil, disk: disk,
            battery: battery, sensors: sensors,
            topByCPU: [], topMemoryApps: []
        )
    }

    // MARK: - scoring

    func testAllNormalScoresHundred() {
        let result = HealthScoreCalculator.evaluate(snapshot())
        XCTAssertEqual(result.value, 100)
        XCTAssertEqual(result.band, .excellent)
    }

    func testCPUAtHighBoundaryDeductsFullHalfWeight() {
        let result = HealthScoreCalculator.evaluate(snapshot(cpuFraction: 0.85))
        XCTAssertEqual(result.value, 85)
    }

    func testMemoryCriticalPressureDeductsFifteen() {
        let result = HealthScoreCalculator.evaluate(snapshot(memFraction: 0.5, pressure: .critical))
        XCTAssertEqual(result.value, 85)
    }

    func testMemoryWarningPressureDeductsFive() {
        let result = HealthScoreCalculator.evaluate(snapshot(memFraction: 0.5, pressure: .warning))
        XCTAssertEqual(result.value, 95)
    }

    func testMemoryFullWeightBranchExactDeduction() {
        // 記憶體 95% (>88 滿權重) → 25*(95-70)/70 ≈ 8.93,score = 100 - 8.93 → 91
        let result = HealthScoreCalculator.evaluate(snapshot(memFraction: 0.95))
        XCTAssertEqual(result.value, 91)
    }

    func testDiskAlmostFullDeductsTowardFullWeight() {
        let result = HealthScoreCalculator.evaluate(snapshot(diskFraction: 0.95))
        XCTAssertEqual(result.value, 85)
    }

    func testThermalAboveHighDeductsFullWeight() {
        let result = HealthScoreCalculator.evaluate(snapshot(cpuTemp: 90))
        XCTAssertEqual(result.value, 85)
    }

    func testBatteryDangerDeductsFive() {
        let bat = BatterySnapshot(isPresent: true, chargeFraction: 0.9, isCharging: false,
                                  cycleCount: 950, healthFraction: 0.5)
        let result = HealthScoreCalculator.evaluate(snapshot(battery: bat))
        XCTAssertEqual(result.value, 95)
    }

    func testNilMetricsDoNotCrashOrDeduct() {
        let cpu = CPUSnapshot(totalUsage: 0.1, user: 0.1, system: 0, idle: 0.9)
        let snap = SystemSnapshot(cpu: cpu, memory: nil, network: nil, disk: nil,
                                  battery: nil, sensors: nil, topByCPU: [], topMemoryApps: [])
        let result = HealthScoreCalculator.evaluate(snap)
        XCTAssertEqual(result.value, 100)
        XCTAssertEqual(result.band, .excellent)
    }

    func testHeavyLoadLandsInNeedsAttention() {
        let bat = BatterySnapshot(isPresent: true, chargeFraction: 0.5, isCharging: false,
                                  cycleCount: 950, healthFraction: 0.5)
        let result = HealthScoreCalculator.evaluate(
            snapshot(cpuFraction: 1.0, memFraction: 1.0, pressure: .critical,
                     diskFraction: 1.0, cpuTemp: 100, battery: bat)
        )
        XCTAssertEqual(result.band, .needsAttention)
        XCTAssertGreaterThanOrEqual(result.value, 0)
        XCTAssertLessThan(result.value, 45)
    }
}
