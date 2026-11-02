import Foundation
import Darwin
import OSLog
#if canImport(MLX)
import MLX
#endif

struct ProcessResourceSample: Sendable {
    let time: TimeInterval
    let cpuSeconds: Double
    let residentBytes: UInt64?
    let mlxBytes: Int?

    static func current() -> Self {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        #if canImport(MLX)
        let mlx: Int? = Memory.activeMemory + Memory.cacheMemory
        #else
        let mlx: Int? = nil
        #endif
        return .init(time: ProcessInfo.processInfo.systemUptime, cpuSeconds: cpu,
                     residentBytes: result == KERN_SUCCESS ? info.resident_size : nil, mlxBytes: mlx)
    }
    func cpuPercent(since previous: Self) -> Double? {
        let elapsed = time - previous.time
        guard elapsed > 0 else { return nil }
        return max(0, (cpuSeconds - previous.cpuSeconds) / elapsed * 100)
    }
}

struct NativeGenerationStats: Sendable {
    var promptTokens: Int = 0
    var outputTokens: Int = 0
    var generationSeconds: Double = 0
    var promptSeconds: Double = 0
    var firstTokenSeconds: Double = 0
    var totalSeconds: Double = 0
    var estimated = false
    var tokensPerSecond: Double { generationSeconds > 0 ? Double(outputTokens) / generationSeconds : 0 }
}

/// Numeric performance metadata only: never pass source text, translations or credentials.
struct NativePerformanceTrace: Encodable, Sendable {
    let runID: String
    let event: String
    let requestNumber: Int
    let loadCount: Int
    let warmupCount: Int
    let sinceReadySeconds: Double?
    let idleSeconds: Double?
    let elapsedSeconds: Double
    let firstTokenSeconds: Double?
    let promptSeconds: Double?
    let generationSeconds: Double?
    let promptTokens: Int?
    let outputTokens: Int?
    let residentBytes: UInt64?
    let mlxBytes: Int?
    let wiredBytes: Int
    let readyActivityHeld: Bool
    let cpuSeconds: Double
    let pageIns: Int64

    private static let logger = Logger(subsystem: "app.lingua.mac", category: "LocalInference")

    func emit() {
        guard let data = try? JSONEncoder().encode(self), let record = String(data: data, encoding: .utf8) else { return }
        Self.logger.notice("\(record, privacy: .public)")
    }
}
