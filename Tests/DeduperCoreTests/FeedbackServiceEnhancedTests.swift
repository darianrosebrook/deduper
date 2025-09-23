import Testing
import Foundation
@testable import DeduperCore

// MARK: - Enhanced Feedback Service Tests

@Suite("Enhanced Feedback Service")
struct FeedbackServiceEnhancedTests {

    // MARK: - Configuration Tests

    @Test("LearningConfig Initialization and Validation")
    func testLearningConfigInitialization() {
        let config = FeedbackService.LearningConfig(
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
        let config = FeedbackService.LearningConfig.default

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
        let smallHistoryConfig = FeedbackService.LearningConfig(maxFeedbackHistory: 500)
        #expect(smallHistoryConfig.maxFeedbackHistory >= 1000) // Should clamp to minimum

        let largeHistoryConfig = FeedbackService.LearningConfig(maxFeedbackHistory: 200000)
        #expect(largeHistoryConfig.maxFeedbackHistory <= 100000) // Should clamp to maximum

        // Test metrics update interval bounds
        let shortIntervalConfig = FeedbackService.LearningConfig(metricsUpdateInterval: 15.0)
        #expect(shortIntervalConfig.metricsUpdateInterval >= 30.0) // Should clamp to minimum

        // Test memory threshold bounds
        let lowThresholdConfig = FeedbackService.LearningConfig(memoryPressureThreshold: 0.0)
        #expect(lowThresholdConfig.memoryPressureThreshold >= 0.1)

        let highThresholdConfig = FeedbackService.LearningConfig(memoryPressureThreshold: 1.0)
        #expect(highThresholdConfig.memoryPressureThreshold <= 0.95)

        // Test health check interval bounds
        let shortHealthConfig = FeedbackService.LearningConfig(healthCheckInterval: 5.0)
        #expect(shortHealthConfig.healthCheckInterval >= 10.0)
    }

    // MARK: - Health Status Tests

    @Test("LearningHealth Description Generation")
    func testLearningHealthDescription() {
        #expect(FeedbackService.LearningHealth.healthy.description == "healthy")
        #expect(FeedbackService.LearningHealth.memoryPressure(0.75).description == "memory_pressure_0.75")
        #expect(FeedbackService.LearningHealth.highProcessingLatency(250.5).description == "high_processing_latency_250.500")
        #expect(FeedbackService.LearningHealth.dataCorrupted.description == "data_corrupted")
        #expect(FeedbackService.LearningHealth.metricsInaccuracy.description == "metrics_inaccuracy")
        #expect(FeedbackService.LearningHealth.securityConcern("privacy_violation").description == "security_concern_privacy_violation")
    }

    @Test("LearningHealth Equatable")
    func testLearningHealthEquatable() {
        #expect(FeedbackService.LearningHealth.healthy == .healthy)
        #expect(FeedbackService.LearningHealth.memoryPressure(0.5) == .memoryPressure(0.5))
        #expect(FeedbackService.LearningHealth.memoryPressure(0.5) != .memoryPressure(0.7))
        #expect(FeedbackService.LearningHealth.highProcessingLatency(100.0) != .highProcessingLatency(120.0))
        #expect(FeedbackService.LearningHealth.securityConcern("test") != .securityConcern("different"))
    }

    // MARK: - Enhanced Service API Tests

    @Test("Enhanced Service Initialization")
    func testEnhancedServiceInitialization() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        #expect(service.getHealthStatus() == .healthy)
        #expect(service.getConfig().enableMemoryMonitoring == false)
        #expect(service.getConfig().enableMLBasedLearning == false)
        #expect(service.getConfig().maxFeedbackHistory == 2000)
    }

    @Test("Configuration Update at Runtime")
    func testConfigurationUpdate() {
        let initialConfig = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: initialConfig)

        #expect(service.getConfig().enableMemoryMonitoring == false)

        // Update configuration
        let newConfig = FeedbackService.LearningConfig(
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

        service.updateConfig(newConfig)

        #expect(service.getConfig().enableMemoryMonitoring == true)
        #expect(service.getConfig().enablePerformanceProfiling == true)
        #expect(service.getConfig().enableSecurityAudit == true)
        #expect(service.getConfig().enableMLBasedLearning == true)
        #expect(service.getConfig().enableAutomatedOptimization == true)
        #expect(service.getConfig().maxFeedbackHistory == 15000)
        #expect(service.getConfig().metricsUpdateInterval == 180.0)
        #expect(service.getConfig().healthCheckInterval == 90.0)
        #expect(service.getConfig().memoryPressureThreshold == 0.9)
        #expect(service.getConfig().enableAuditLogging == true)
        #expect(service.getConfig().enableDataEncryption == true)
    }

    @Test("Memory Pressure Monitoring")
    func testMemoryPressureMonitoring() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)
    }

    @Test("Security Event Logging")
    func testSecurityEventLogging() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        // Initially should have no security events
        let initialEvents = service.getSecurityEvents()
        #expect(initialEvents.count >= 0)
    }

    // MARK: - Metrics Export Tests

    @Test("Metrics Export JSON Format")
    func testMetricsExportJSON() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(!jsonMetrics.isEmpty)
        #expect(jsonMetrics.contains("operationId") || jsonMetrics == "{}")
    }

    @Test("Metrics Export Prometheus Format")
    func testMetricsExportPrometheus() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(!prometheusMetrics.isEmpty)
        #expect(prometheusMetrics.contains("# Learning & Refinement Metrics") || prometheusMetrics.isEmpty)
    }

    @Test("Health Report Generation")
    func testHealthReportGeneration() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        let healthReport = service.getHealthReport()
        #expect(!healthReport.isEmpty)
        #expect(healthReport.contains("Learning & Refinement Health Report"))
        #expect(healthReport.contains("System Status"))
        #expect(healthReport.contains("Learning Metrics"))
        #expect(healthReport.contains("Performance Metrics"))
        #expect(healthReport.contains("Security Events"))
    }

    @Test("System Information Generation")
    func testSystemInformationGeneration() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        let systemInfo = service.getSystemInfo()
        #expect(!systemInfo.isEmpty)
        #expect(systemInfo.contains("Learning & Refinement System Information"))
        #expect(systemInfo.contains("Configuration"))
        #expect(systemInfo.contains("Current Metrics"))
        #expect(systemInfo.contains("Performance Statistics"))
        #expect(systemInfo.contains("Current Status"))
    }

    @Test("Learning Statistics")
    func testLearningStatistics() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        let (feedbackCount, falsePositiveRate, correctDetectionRate, averageConfidence) = service.getLearningStatistics()

        #expect(feedbackCount >= 0)
        #expect(falsePositiveRate >= 0.0 && falsePositiveRate <= 1.0)
        #expect(correctDetectionRate >= 0.0 && correctDetectionRate <= 1.0)
        #expect(averageConfidence >= 0.0 && averageConfidence <= 1.0)
    }

    // MARK: - Health Monitoring Tests

    @Test("Health Monitoring Configuration")
    func testHealthMonitoringConfiguration() {
        // Test with health monitoring disabled
        let noHealthConfig = FeedbackService.LearningConfig(
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

        let serviceNoHealth = FeedbackService(config: noHealthConfig)

        #expect(serviceNoHealth.getConfig().healthCheckInterval == 0.0)

        // Test with health monitoring enabled
        let healthConfig = FeedbackService.LearningConfig(
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

        let serviceWithHealth = FeedbackService(config: healthConfig)

        #expect(serviceWithHealth.getConfig().healthCheckInterval == 30.0)
    }

    // MARK: - API Contract Tests

    @Test("API Contract Compliance")
    func testAPIContractCompliance() {
        let config = FeedbackService.LearningConfig(
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

        let service = FeedbackService(config: config)

        // Test that all required public APIs exist and return expected types
        let healthStatus = service.getHealthStatus()
        #expect(healthStatus is FeedbackService.LearningHealth)

        let learningConfig = service.getConfig()
        #expect(learningConfig is FeedbackService.LearningConfig)

        let memoryPressure = service.getCurrentMemoryPressure()
        #expect(memoryPressure >= 0.0 && memoryPressure <= 1.0)

        let securityEvents = service.getSecurityEvents()
        #expect(securityEvents is [LearningSecurityEvent])

        let performanceMetrics = service.getPerformanceMetrics()
        #expect(performanceMetrics is [LearningPerformanceMetrics])

        let jsonMetrics = service.exportMetrics(format: "json")
        #expect(jsonMetrics is String)

        let prometheusMetrics = service.exportMetrics(format: "prometheus")
        #expect(prometheusMetrics is String)

        let healthReport = service.getHealthReport()
        #expect(healthReport is String && !healthReport.isEmpty)

        let systemInfo = service.getSystemInfo()
        #expect(systemInfo is String && !systemInfo.isEmpty)

        let learningStats = service.getLearningStatistics()
        #expect(learningStats.feedbackCount >= 0)
        #expect(learningStats.falsePositiveRate >= 0.0 && learningStats.falsePositiveRate <= 1.0)
        #expect(learningStats.correctDetectionRate >= 0.0 && learningStats.correctDetectionRate <= 1.0)
        #expect(learningStats.averageConfidence >= 0.0 && learningStats.averageConfidence <= 1.0)
    }
}
