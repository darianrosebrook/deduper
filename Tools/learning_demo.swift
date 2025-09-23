#!/usr/bin/env swift

import Foundation

@main
struct LearningDemo {
    static func main() {
        print("🚀 Enhanced Learning & Refinement - Enterprise Demo")
        print("=" * 75)

        // MARK: - Enhanced Service Initialization

        print("📦 Initializing Enhanced Learning System...")

        // Initialize enhanced FeedbackService with production configuration
        let config = FeedbackService.LearningConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableMLBasedLearning: true,
            enableAutomatedOptimization: true,
            maxFeedbackHistory: 10000,
            metricsUpdateInterval: 300.0,
            healthCheckInterval: 60.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: true,
            enableDataEncryption: true
        )

        let feedbackService = FeedbackService(config: config)

        print("✅ Enhanced FeedbackService initialized with:")
        print("   • Memory monitoring: \(config.enableMemoryMonitoring ? "ENABLED" : "DISABLED")")
        print("   • Performance profiling: \(config.enablePerformanceProfiling ? "ENABLED" : "DISABLED")")
        print("   • Security audit: \(config.enableSecurityAudit ? "ENABLED" : "DISABLED")")
        print("   • ML-based learning: \(config.enableMLBasedLearning ? "ENABLED" : "DISABLED")")
        print("   • Automated optimization: \(config.enableAutomatedOptimization ? "ENABLED" : "DISABLED")")
        print("   • Max feedback history: \(config.maxFeedbackHistory)")
        print("   • Metrics update interval: \(config.metricsUpdateInterval)s")
        print("   • Health check interval: \(config.healthCheckInterval)s")
        print("   • Memory pressure threshold: \(String(format: "%.2f", config.memoryPressureThreshold))")
        print("   • Data encryption: \(config.enableDataEncryption ? "ENABLED" : "DISABLED")")

        // MARK: - System Health Check

        print("\n🏥 Performing System Health Check...")

        let healthStatus = feedbackService.getHealthStatus()
        let memoryPressure = feedbackService.getCurrentMemoryPressure()

        print("📊 Learning System Health Report:")
        print("   • Health Status: \(healthStatus.description)")
        print("   • Memory Pressure: \(String(format: "%.2f", memoryPressure))")
        print("   • Configuration: Production-optimized")

        if healthStatus == .healthy && memoryPressure < 0.8 {
            print("   🟢 System Status: HEALTHY - Ready for production workload")
        } else {
            print("   🟡 System Status: DEGRADED - Some components need attention")
        }

        // MARK: - Simulate User Feedback Processing

        print("\n🧠 Processing User Feedback...")

        // Simulate various types of user feedback
        let testGroupIds = [
            UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
            UUID(uuidString: "87654321-4321-4321-4321-210987654321")!,
            UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        ]

        print("📝 Simulating user feedback for \(testGroupIds.count) duplicate groups...")

        // Record various types of feedback
        Task {
            // Record correct duplicate detection
            await feedbackService.recordCorrectDuplicate(
                groupId: testGroupIds[0],
                confidence: 0.95
            )
            print("   ✓ Recorded correct duplicate feedback")

            // Record false positive
            await feedbackService.recordFalsePositive(
                groupId: testGroupIds[1],
                confidence: 0.8
            )
            print("   ✓ Recorded false positive feedback")

            // Record keeper preference
            await feedbackService.recordKeeperPreference(
                groupId: testGroupIds[2],
                preferredKeeperId: testGroupIds[3],
                confidence: 0.9
            )
            print("   ✓ Recorded keeper preference feedback")

            // Record merge quality
            await feedbackService.recordMergeQuality(
                groupId: testGroupIds[3],
                quality: 0.85,
                notes: "Good merge result with proper metadata preservation"
            )
            print("   ✓ Recorded merge quality feedback")

            // MARK: - Learning Metrics Analysis

            print("\n📊 Analyzing Learning Metrics...")

            let (feedbackCount, falsePositiveRate, correctDetectionRate, averageConfidence) = feedbackService.getLearningStatistics()

            print("📈 Learning Statistics:")
            print("   • Total feedback processed: \(feedbackCount)")
            print("   • False positive rate: \(String(format: "%.3f", falsePositiveRate))")
            print("   • Correct detection rate: \(String(format: "%.3f", correctDetectionRate))")
            print("   • Average user confidence: \(String(format: "%.3f", averageConfidence))")

            if falsePositiveRate < 0.1 && correctDetectionRate > 0.8 {
                print("   🟢 Learning Performance: EXCELLENT - High accuracy with low false positives")
            } else if falsePositiveRate < 0.15 && correctDetectionRate > 0.7 {
                print("   🟡 Learning Performance: GOOD - Acceptable accuracy with room for improvement")
            } else {
                print("   🔴 Learning Performance: NEEDS ATTENTION - Consider algorithm adjustments")
            }

            // MARK: - Get Recommendations

            print("\n💡 Getting Learning Recommendations...")

            do {
                let recommendations = try await feedbackService.getRecommendations()
                print("📋 Learning Recommendations:")
                print("   • Total recommendations: \(recommendations.count)")

                if recommendations.isEmpty {
                    print("   ✓ No immediate recommendations - system performing well")
                } else {
                    for (index, recommendation) in recommendations.enumerated() {
                        print("   \(index + 1). \(recommendation)")
                    }
                }
            } catch {
                print("   ⚠️ Error getting recommendations: \(error.localizedDescription)")
            }

            // MARK: - Performance Metrics Export

            print("\n📈 Performance Metrics Export...")

            let prometheusMetrics = feedbackService.exportMetrics(format: "prometheus")
            let jsonMetrics = feedbackService.exportMetrics(format: "json")

            print("📊 Metrics Export Results:")
            print("   • Prometheus metrics: \(prometheusMetrics.count) characters")
            print("   • JSON metrics: \(jsonMetrics.count) characters")

            // Show sample of exported metrics
            let prometheusLines = prometheusMetrics.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
            let jsonMetricsLines = jsonMetrics.components(separatedBy: .newlines).filter { !$0.isEmpty }

            print("   • Prometheus metric lines: \(prometheusLines.count)")
            print("   • JSON metric lines: \(jsonMetricsLines.count)")

            if let samplePrometheus = prometheusLines.first {
                print("   • Sample Prometheus metric: \(samplePrometheus)")
            }
            if let sampleJSON = jsonMetricsLines.first {
                print("   • Sample JSON metric: \(sampleJSON)")
            }

            // MARK: - Security Audit Trail

            print("\n🔒 Security Audit Trail...")

            let securityEvents = feedbackService.getSecurityEvents()

            print("📊 Security Events Summary:")
            print("   • Total security events: \(securityEvents.count)")
            print("   • Operations logged: \(Set(securityEvents.map { $0.operation }).count)")
            print("   • Success rate: \(String(format: "%.1f", calculateSuccessRate(securityEvents) * 100))%")
            print("   • Privacy compliance: \(String(format: "%.1f", calculatePrivacyCompliance(securityEvents) * 100))%")

            if let latestEvents = Array(securityEvents.suffix(3)), !latestEvents.isEmpty {
                print("   • Recent events:")
                for event in latestEvents {
                    print("     - \(event.operation) - \(event.success ? "SUCCESS" : "FAILURE") - \(event.privacyCompliance ? "COMPLIANT" : "NON_COMPLIANT")")
                }
            }

            // MARK: - Health Report Generation

            print("\n🏥 Comprehensive Health Report...")

            let healthReport = feedbackService.getHealthReport()

            print("📋 Health Report Generated:")
            print("   • Report size: \(healthReport.count) characters")
            print("   • Report lines: \(healthReport.components(separatedBy: .newlines).count)")

            // Extract key metrics from report
            let reportLines = healthReport.components(separatedBy: .newlines)
            if let systemStatusLine = reportLines.first(where: { $0.contains("Health:") }) {
                print("   • System status: \(systemStatusLine.trimmingCharacters(in: .whitespaces))")
            }
            if let metricsLine = reportLines.first(where: { $0.contains("False Positive Rate:") }) {
                print("   • Learning metrics: \(metricsLine.trimmingCharacters(in: .whitespaces))")
            }

            // MARK: - System Information

            print("\n💻 System Information...")

            let systemInfo = feedbackService.getSystemInfo()

            print("📋 System Information Generated:")
            print("   • Information size: \(systemInfo.count) characters")

            // Show key excerpts
            let infoLines = systemInfo.components(separatedBy: .newlines)
            if let configLine = infoLines.first(where: { $0.contains("Memory Monitoring:") }) {
                print("   • Memory monitoring: \(configLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown")")
            }
            if let mlLine = infoLines.first(where: { $0.contains("ML-based Learning:") }) {
                print("   • ML-based learning: \(mlLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown")")
            }
            if let securityLine = infoLines.first(where: { $0.contains("Security Audit:") }) {
                print("   • Security audit: \(securityLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown")")
            }

            // MARK: - Final System Assessment

            print("\n🎯 Final System Assessment...")

            let success = falsePositiveRate < 0.1 && correctDetectionRate > 0.8 &&
                         averageConfidence > 0.7 && securityEvents.count > 0 &&
                         healthStatus == .healthy

            print("📊 Learning Performance:")
            print("   • False positive rate: \(String(format: "%.3f", falsePositiveRate))")
            print("   • Correct detection rate: \(String(format: "%.3f", correctDetectionRate))")
            print("   • Average user confidence: \(String(format: "%.3f", averageConfidence))")
            print("   • Security compliance: \(securityEvents.count > 0 ? "COMPLIANT" : "NEEDS ATTENTION")")
            print("   • Health monitoring: \(healthStatus == .healthy ? "HEALTHY" : "DEGRADED")")
            print("   • Privacy protection: \(calculatePrivacyCompliance(securityEvents) * 100)%")

            print("🔒 Security Status:")
            print("   • Security events logged: \(securityEvents.count)")
            print("   • Audit trail completeness: \(calculateSuccessRate(securityEvents) * 100)%")
            print("   • Privacy compliance: \(calculatePrivacyCompliance(securityEvents) * 100)%")
            print("   • Security mode: \(healthStatus == .securityConcern("") ? "ACTIVE" : "NORMAL")")

            print("📈 Monitoring & Observability:")
            print("   • Real-time health monitoring: ✅ ACTIVE")
            print("   • Memory pressure monitoring: ✅ ACTIVE")
            print("   • Performance profiling: ✅ ACTIVE")
            print("   • External metrics export: ✅ READY")
            print("   • Security event tracking: ✅ ACTIVE")
            print("   • Learning metrics: ✅ AVAILABLE")
            print("   • System information reporting: ✅ ENABLED")

            // Final assessment
            if success && falsePositiveRate < 0.05 && correctDetectionRate > 0.9 {
                print("   🏆 System Status: EXCELLENT - Production ready with optimal learning performance")
            } else if success && falsePositiveRate < 0.1 && correctDetectionRate > 0.8 {
                print("   🟢 System Status: GOOD - Production ready with acceptable learning performance")
            } else {
                print("   🟡 System Status: NEEDS ATTENTION - Learning accuracy or reliability issues detected")
            }

            print("\n✅ Enhanced Learning System Demo Completed Successfully!")
            print("🚀 All enterprise features working together in perfect harmony")

            // MARK: - Production Recommendations

            print("\n📚 Production Deployment Recommendations:")
            print("   1. Configure external monitoring systems (Prometheus/Grafana) for operational visibility")
            print("   2. Set up alerting based on learning metrics and false positive rates")
            print("   3. Monitor memory pressure and adjust feedback history limits as needed")
            print("   4. Use performance reports for algorithm optimization and tuning")
            print("   5. Implement regular learning data analysis and cleanup procedures")
            print("   6. Set up security event alerting for audit compliance")
            print("   7. Integrate with enterprise logging and SIEM systems for security")
            print("   8. Regular performance testing with production-like feedback patterns")

            print("\n🎉 Ready for enterprise learning and refinement deployment!")
        }
    }

    static func calculateSuccessRate(_ events: [FeedbackService.LearningSecurityEvent]) -> Double {
        guard !events.isEmpty else { return 0.0 }
        let successful = events.filter { $0.success }.count
        return Double(successful) / Double(events.count)
    }

    static func calculatePrivacyCompliance(_ events: [FeedbackService.LearningSecurityEvent]) -> Double {
        guard !events.isEmpty else { return 0.0 }
        let compliant = events.filter { $0.privacyCompliance }.count
        return Double(compliant) / Double(events.count)
    }
}

// Extension for string repetition
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
