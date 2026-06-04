import XCTest
@testable import GlanceCore

private struct FakeThermal: ThermalSource {
    let reading: ThermalReading?
    func read() -> ThermalReading? { reading }
}
private struct FakePower: PowerSource {
    let reading: PowerReading?
    func read() -> PowerReading? { reading }
}
private struct FakeFan: FanSource {
    let rpm: [Int]
    func read() -> [Int] { rpm }
}

final class SensorSamplerTests: XCTestCase {
    func testAssemblesAllSources() {
        let sampler = SensorSampler(
            thermal: FakeThermal(reading: ThermalReading(cpu: 52, gpu: 48)),
            power: FakePower(reading: PowerReading(system: 12.4, cpu: 6, gpu: 3)),
            fan: FakeFan(rpm: [1800, 1820]))

        let snap = sampler.sample()

        XCTAssertEqual(snap, SensorSnapshot(
            cpuTemperature: 52, gpuTemperature: 48,
            systemPower: 12.4, cpuPower: 6, gpuPower: 3,
            fanRPM: [1800, 1820]))
    }

    func testPartialSourcesDegradeGracefully() {
        let sampler = SensorSampler(
            thermal: FakeThermal(reading: ThermalReading(cpu: 50, gpu: nil)),
            power: FakePower(reading: nil),
            fan: FakeFan(rpm: []))

        let snap = sampler.sample()

        XCTAssertEqual(snap?.cpuTemperature, 50)
        XCTAssertNil(snap?.gpuTemperature)
        XCTAssertNil(snap?.systemPower)
        XCTAssertEqual(snap?.fanRPM, [])
    }

    func testNilSourcesProduceNil() {
        let sampler = SensorSampler()
        XCTAssertNil(sampler.sample())
    }

    func testAllEmptyReadingsProduceNil() {
        let sampler = SensorSampler(
            thermal: FakeThermal(reading: ThermalReading(cpu: nil, gpu: nil)),
            power: FakePower(reading: nil),
            fan: FakeFan(rpm: []))
        XCTAssertNil(sampler.sample())
    }
}
