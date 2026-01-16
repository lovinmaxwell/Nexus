import Foundation
import XCTest

@testable import NexusApp

@MainActor
final class PerformanceProfilerTests: XCTestCase {
    func testPerformanceProfilerInitialization() {
        let profiler = PerformanceProfiler.shared
        XCTAssertNotNil(profiler, "PerformanceProfiler should be initialized")
    }
    
    func testPerformanceReportGeneration() {
        let profiler = PerformanceProfiler.shared
        let report = profiler.profileHotPaths()
        
        XCTAssertNotNil(report, "Performance report should be generated")
        XCTAssertGreaterThanOrEqual(report.cpuUsage, 0.0, "CPU usage should be non-negative")
        XCTAssertGreaterThanOrEqual(report.memoryUsage, 0, "Memory usage should be non-negative")
    }
    
    func testMemoryUsageFormatting() {
        let report = PerformanceReport(
            cpuUsage: 2.5,
            memoryUsage: 100 * 1024 * 1024, // 100MB
            activeDownloads: 3,
            recommendations: []
        )
        
        let formatted = report.formattedMemoryUsage
        XCTAssertFalse(formatted.isEmpty, "Formatted memory usage should not be empty")
    }
}
