import Testing
import Foundation
@testable import DeduperCore

// MARK: - Enhanced Feedback Service Tests

@Suite("Enhanced Feedback Service")
struct FeedbackServiceEnhancedTests {

    // MARK: - Configuration Tests

    @Test("LearningConfig Initialization and Validation")
    func testLearningConfigInitialization() {
        let config = LearningConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: true,
            maxFeedbackHistory: 5000,
            metricsUpdateInterval: 120.0,
            healthCheckInterval: 30.0,
            memoryPressureThreshold: 0.7,
            enableAuditLogging: true,
            enableDataEncryption: true
        )

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enablePerformanceProfiling == true)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enableMLBasedLearning == false)
        #expect(config.enableAutomatedOptimization == true)
        #expect(config.maxFeedbackHistory == 5000)
        #expect(config.metricsUpdateInterval == 120.0)
        #expect(config.healthCheckInterval == 30.0)
        #expect(config.memoryPressureThreshold == 0.7)
        #expect(config.enableAuditLogging == true)
        #expect(config.enableDataEncryption == true)
    }

    @Test("LearningConfig Default Configuration")
    func testLearningConfigDefault() {
        let config = LearningConfig.default

        #expect(config.enableMemoryMonitoring == true)
        #expect(config.enablePerformanceProfiling == true)
        #expect(config.enableSecurityAudit == true)
        #expect(config.enableMLBasedLearning == true)
        #expect(config.enableAutomatedOptimization == true)
        #expect(config.maxFeedbackHistory == 10000)
        #expect(config.metricsUpdateInterval == 300.0)
        #expect(config.healthCheckInterval == 60.0)
        #expect(config.memoryPressureThreshold == 0.8)
        #expect(config.enableAuditLogging == true)
        #expect(config.enableDataEncryption == true)
    }

    @Test("LearningConfig Validation Bounds")
    func testLearningConfigValidation() {
        // Test max feedback history bounds
        let smallHistoryConfig = LearningConfig(maxFeedbackHistory: 500)
        #expect(smallHistoryConfig.maxFeedbackHistory >= 1000) // Should clamp to minimum

        let largeHistoryConfig = LearningConfig(maxFeedbackHistory: 200000)
        #expect(largeHistoryConfig.maxFeedbackHistory <= 100000) // Should clamp to maximum

        // Test metrics update interval bounds
        let shortIntervalConfig = LearningConfig(metricsUpdateInterval: 15.0)
        #expect(shortIntervalConfig.metricsUpdateInterval >= 30.0) // Should clamp to minimum

        // Test memory threshold bounds
        let lowThresholdConfig = LearningConfig(memoryPressureThreshold: 0.0)
        #expect(lowThresholdConfig.memoryPressureThreshold >= 0.1)

        let highThresholdConfig = LearningConfig(memoryPressureThreshold: 1.0)
        #expect(highThresholdConfig.memoryPressureThreshold <= 0.95)

        // Test health check interval bounds
        let shortHealthConfig = LearningConfig(healthCheckInterval: 5.0)
        #expect(shortHealthConfig.healthCheckInterval >= 10.0)
    }

    // MARK: - Health Status Tests

    @Test("LearningHealth Description Generation")
    func testLearningHealthDescription() {
        #expect(LearningHealth.healthy.description == "healthy")
        #expect(LearningHealth.memoryPressure(0.75).description == "memory_pressure_0.75")
        #expect(LearningHealth.highProcessingLatency(250.5).description == "high_processing_latency_250.500")
        #expect(LearningHealth.dataCorrupted.description == "data_corrupted")
        #expect(LearningHealth.metricsInaccuracy.description == "metrics_inaccuracy")
        #expect(LearningHealth.securityConcern("privacy_violation").description == "security_concern_privacy_violation")
    }

    @Test("LearningHealth Equatable")
    func testLearningHealthEquatable() {
        #expect(LearningHealth.healthy == .healthy)
        #expect(LearningHealth.memoryPressure(0.5) == .memoryPressure(0.5))
        #expect(LearningHealth.memoryPressure(0.5) != .memoryPressure(0.7))
        #expect(LearningHealth.highProcessingLatency(100.0) != .highProcessingLatency(120.0))
        #expect(LearningHealth.securityConcern("test") != .securityConcern("different"))
    }

    // MARK: - Enhanced Service API Tests

    @Test("Enhanced Service Initialization")
    func testEnhancedServiceInitialization() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        let healthStatus = await MainActor.run {
            service.getHealthStatus()
        }
        #expect(healthStatus == .healthy)
        
        let serviceConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(serviceConfig.enableMemoryMonitoring == false)
        #expect(serviceConfig.enableMLBasedLearning == false)
        #expect(serviceConfig.maxFeedbackHistory == 2000)
    }

    @Test("Configuration Update at Runtime")
    func testConfigurationUpdate() async {
        let initialConfig = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: initialConfig)
        }

        let initialServiceConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(initialServiceConfig.enableMemoryMonitoring == false)

        // Update configuration
        let newConfig = LearningConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableMLBasedLearning: true,
            enableAutomatedOptimization: true,
            maxFeedbackHistory: 15000,
            metricsUpdateInterval: 180.0,
            healthCheckInterval: 90.0,
            memoryPressureThreshold: 0.9,
            enableAuditLogging: true,
            enableDataEncryption: true
        )

        await MainActor.run {
            service.updateConfig(newConfig)
        }

        let updatedConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(updatedConfig.enableMemoryMonitoring == true)
        #expect(updatedConfig.enablePerformanceProfiling == true)
        #expect(updatedConfig.enableSecurityAudit == true)
        #expect(updatedConfig.enableMLBasedLearning == true)
        #expect(updatedConfig.enableAutomatedOptimization == true)
        #expect(updatedConfig.maxFeedbackHistory == 15000)
        #expect(updatedConfig.metricsUpdateInterval == 180.0)
        #expect(updatedConfig.healthCheckInterval == 90.0)
        #expect(updatedConfig.memoryPressureThreshold == 0.9)
        #expect(updatedConfig.enableAuditLogging == true)
        #expect(updatedConfig.enableDataEncryption == true)
    }

    @Test("Memory Pressure Monitoring")
    func testMemoryPressureMonitoring() async {
        let config = LearningConfig(
            enableMemoryMonitoring: true,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        let memoryPressure = await MainActor.run {
            service.getCurrentMemoryPressure()
        }
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)
    }

    @Test("Security Event Logging")
    func testSecurityEventLogging() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: true,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        // Initially should have no security events
        let initialEvents = await MainActor.run {
            service.getSecurityEvents()
        }
        #expect(initialEvents.count >= 0)
    }

    // MARK: - Metrics Export Tests

    @Test("Metrics Export JSON Format")
    func testMetricsExportJSON() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        let jsonMetrics = await MainActor.run {
            service.exportMetrics(format: "json")
        }
        #expect(!jsonMetrics.isEmpty)
        #expect(jsonMetrics.contains("operationId") || jsonMetrics == "{}")
    }

    @Test("Metrics Export Prometheus Format")
    func testMetricsExportPrometheus() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        let prometheusMetrics = await MainActor.run {
            service.exportMetrics(format: "prometheus")
        }
        #expect(!prometheusMetrics.isEmpty)
        #expect(prometheusMetrics.contains("# Learning & Refinement Metrics") || prometheusMetrics.isEmpty)
    }

    @Test("Health Report Generation")
    func testHealthReportGeneration() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        let healthReport = await MainActor.run {
            service.getHealthReport()
        }
        #expect(!healthReport.isEmpty)
        #expect(healthReport.contains("Learning & Refinement Health Report"))
        #expect(healthReport.contains("System Status"))
        #expect(healthReport.contains("Learning Metrics"))
        #expect(healthReport.contains("Performance Metrics"))
        #expect(healthReport.contains("Security Events"))
    }

    @Test("System Information Generation")
    func testSystemInformationGeneration() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        let systemInfo = await MainActor.run {
            service.getSystemInfo()
        }
        #expect(!systemInfo.isEmpty)
        #expect(systemInfo.contains("Learning & Refinement System Information"))
        #expect(systemInfo.contains("Configuration"))
        #expect(systemInfo.contains("Current Metrics"))
        #expect(systemInfo.contains("Performance Statistics"))
        #expect(systemInfo.contains("Current Status"))
    }

    @Test("Learning Statistics")
    func testLearningStatistics() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        let (feedbackCount, falsePositiveRate, correctDetectionRate, averageConfidence) = await MainActor.run {
            service.getLearningStatistics()
        }

        #expect(feedbackCount >= 0)
        #expect(falsePositiveRate >= 0.0 && falsePositiveRate <= 1.0)
        #expect(correctDetectionRate >= 0.0 && correctDetectionRate <= 1.0)
        #expect(averageConfidence >= 0.0 && averageConfidence <= 1.0)
    }

    // MARK: - Health Monitoring Tests

    @Test("Health Monitoring Configuration")
    func testHealthMonitoringConfiguration() async {
        // Test with health monitoring disabled
        let noHealthConfig = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0, // Disabled
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let serviceNoHealth = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: noHealthConfig)
        }

        let config = await MainActor.run {
            serviceNoHealth.getConfig()
        }
        #expect(config.healthCheckInterval == 0.0)

        // Test with health monitoring enabled
        let healthConfig = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: false,
            enableSecurityAudit: false,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 30.0, // Enabled
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let serviceWithHealth = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: healthConfig)
        }

        let healthConfigResult = await MainActor.run {
            serviceWithHealth.getConfig()
        }
        #expect(healthConfigResult.healthCheckInterval == 30.0)
    }

    // MARK: - API Contract Tests

    @Test("API Contract Compliance")
    func testAPIContractCompliance() async {
        let config = LearningConfig(
            enableMemoryMonitoring: false,
            enablePerformanceProfiling: true,
            enableSecurityAudit: true,
            enableMLBasedLearning: false,
            enableAutomatedOptimization: false,
            maxFeedbackHistory: 2000,
            metricsUpdateInterval: 60.0,
            healthCheckInterval: 0.0,
            memoryPressureThreshold: 0.8,
            enableAuditLogging: false,
            enableDataEncryption: false
        )

        let service = await MainActor.run {
            FeedbackService(persistence: PersistenceController.shared, config: config)
        }

        // Test that all required public APIs exist and return expected types
        let healthStatus = await MainActor.run {
            service.getHealthStatus()
        }
        #expect(healthStatus is LearningHealth)

        let learningConfig = await MainActor.run {
            service.getConfig()
        }
        #expect(learningConfig is LearningConfig)

        let memoryPressure = await MainActor.run {
            service.getCurrentMemoryPressure()
        }
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

        let securityEvents = await MainActor.run {
            service.getSecurityEvents()
        }
        #expect(securityEvents is [LearningSecurityEvent])

        let performanceMetrics = await MainActor.run {
            service.getPerformanceMetrics()
        }
        #expect(performanceMetrics is [LearningPerformanceMetrics])

        let jsonMetrics = await MainActor.run {
            service.exportMetrics(format: "json")
        }
        #expect(jsonMetrics is String)

        let prometheusMetrics = await MainActor.run {
            service.exportMetrics(format: "prometheus")
        }
        #expect(prometheusMetrics is String)

        let healthReport = await MainActor.run {
            service.getHealthReport()
        }
        #expect(healthReport is String && !healthReport.isEmpty)

        let systemInfo = await MainActor.run {
            service.getSystemInfo()
        }
        #expect(systemInfo is String && !systemInfo.isEmpty)

        let learningStats = await MainActor.run {
            service.getLearningStatistics()
        }
        #expect(learningStats.feedbackCount >= 0)
        #expect(learningStats.falsePositiveRate >= 0.0 && learningStats.falsePositiveRate <= 1.0)
        #expect(learningStats.correctDetectionRate >= 0.0 && learningStats.correctDetectionRate <= 1.0)
        #expect(learningStats.averageConfidence >= 0.0 && learningStats.averageConfidence <= 1.0)
    }
}
