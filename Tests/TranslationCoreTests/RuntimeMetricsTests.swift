import XCTest
@testable import LinguaMac

final class RuntimeMetricsTests: XCTestCase {
    func testProcessCPUUsesElapsedTimeAndAllowsMultipleCores() {
        let first = ProcessResourceSample(time: 10, cpuSeconds: 5, residentBytes: nil, mlxBytes: nil)
        let next = ProcessResourceSample(time: 12, cpuSeconds: 8, residentBytes: nil, mlxBytes: nil)
        XCTAssertEqual(next.cpuPercent(since: first), 150)
        XCTAssertNil(first.cpuPercent(since: first))
    }
    func testResourceSampleAndGenerationRate() {
        let sample = ProcessResourceSample.current()
        XCTAssertGreaterThan(sample.residentBytes ?? 0, 0)
        XCTAssertGreaterThanOrEqual(sample.cpuSeconds, 0)
        XCTAssertEqual(NativeGenerationStats().tokensPerSecond, 0)
        XCTAssertEqual(NativeGenerationStats(outputTokens: 40, generationSeconds: 2).tokensPerSecond, 20)
    }
}
