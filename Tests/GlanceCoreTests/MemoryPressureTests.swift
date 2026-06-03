import XCTest
@testable import GlanceCore

final class MemoryPressureTests: XCTestCase {
    func testNormalBelow75Percent() {
        // 50% used, no swap
        XCTAssertEqual(MemoryPressure.evaluate(usedBytes: 8_000_000_000, totalBytes: 16_000_000_000, swapUsedBytes: 0), .normal)
    }
    func testWarningBetween75And90() {
        // 80% used
        XCTAssertEqual(MemoryPressure.evaluate(usedBytes: 12_800_000_000, totalBytes: 16_000_000_000, swapUsedBytes: 0), .warning)
    }
    func testCriticalAbove90() {
        // 95% used
        XCTAssertEqual(MemoryPressure.evaluate(usedBytes: 15_200_000_000, totalBytes: 16_000_000_000, swapUsedBytes: 0), .critical)
    }
    func testCriticalWhenSwapExceedsHalfOfRam() {
        // 50% used but swap > half of total
        XCTAssertEqual(MemoryPressure.evaluate(usedBytes: 8_000_000_000, totalBytes: 16_000_000_000, swapUsedBytes: 9_000_000_000), .critical)
    }
    func testNormalWhenTotalZero() {
        XCTAssertEqual(MemoryPressure.evaluate(usedBytes: 0, totalBytes: 0, swapUsedBytes: 0), .normal)
    }
}
