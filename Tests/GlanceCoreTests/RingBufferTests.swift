import XCTest
@testable import GlanceCore

final class RingBufferTests: XCTestCase {
    func testAppendBelowCapacityKeepsOrder() {
        var rb = RingBuffer<Int>(capacity: 3)
        rb.append(1); rb.append(2)
        XCTAssertEqual(rb.elements, [1, 2])
    }

    func testAppendBeyondCapacityDropsOldest() {
        var rb = RingBuffer<Int>(capacity: 3)
        [1, 2, 3, 4, 5].forEach { rb.append($0) }
        XCTAssertEqual(rb.elements, [3, 4, 5])
    }

    func testCapacityOneKeepsLatest() {
        var rb = RingBuffer<Int>(capacity: 1)
        rb.append(7); rb.append(9)
        XCTAssertEqual(rb.elements, [9])
    }

    func testEmptyStartsEmpty() {
        let rb = RingBuffer<Int>(capacity: 3)
        XCTAssertEqual(rb.elements, [])
    }
}
