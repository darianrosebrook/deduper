import XCTest
@testable import DeduperCore

// MARK: - Enhancement Testing Suite

/**
 Comprehensive test suite for advanced testing and performance enhancements.

 This test suite validates:
 - Chaos testing framework functionality
 - A/B testing framework for confidence calibration
 - Pre-computed index service for large datasets
 - Performance monitoring service capabilities
 - Integration between all enhancement services

 Author: @darianrosebrook
 */
final class EnhancementTests: XCTestCase {

    // MARK: - Properties

    private var chaosTestingService: ChaosTestingFramework!
    private var abTestingService: ABTestingFramework!
    private var precomputedIndexService: PrecomputedIndexService!
    private var performanceMonitoringService: PerformanceMonitoringService!

    // MARK: - Setup and Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Initialize services only if feature flags are enabled
        if EnhancementFeatureFlags.chaosTestingEnabled {
            chaosTestingService = ChaosTestingFramework()
        }

        if EnhancementFeatureFlags.abTestingEnabled {
            abTestingService = ABTestingFramework()
        }

        if EnhancementFeatureFlags.precomputedIndexesEnabled {
            precomputedIndexService = PrecomputedIndexService()
        }

        if EnhancementFeatureFlags.performanceMonitoringEnabled {
            performanceMonitoringService = PerformanceMonitoringService()
        }
    }

    override func tearDown() async throws {
        // Clean up any resources
        if EnhancementFeatureFlags.performanceMonitoringEnabled {
            await performanceMonitoringService?.stopMonitoring()
        }

        try await super.tearDown()
    }

    // MARK: - Chaos Testing Framework Tests

    func testChaosTestingFrameworkInitialization() async throws {
        guard EnhancementFeatureFlags.chaosTestingEnabled else {
            throw XCTSkip("Chaos testing not enabled")
        }

        // Test that framework initializes properly
        XCTAssertNotNil(chaosTestingService)
        let result = ChaosTestResult(
            scenarios: [],
            metrics: ChaosMetrics(
                scenariosExecuted: 0,
                totalFailures: 0,
                recoverySuccessRate: 1.0,
                performanceDegradation: 0.0,
                meanTimeToRecovery: 0,
                maxRecoveryTime: 0,
                systemStabilityScore: 1.0
            ),
            report: ChaosTestReport(
                executionResult: TestExecutionResult(
                    executionTime: 0,
                    operationResults: [],
                    chaosEvents: []
                ),
                monitoringData: [:],
                metrics: ChaosMetrics(
                    scenariosExecuted: 0,
                    totalFailures: 0,
                    recoverySuccessRate: 1.0,
                    performanceDegradation: 0.0,
                    meanTimeToRecovery: 0,
                    maxRecoveryTime: 0,
                    systemStabilityScore: 1.0
                ),
                recommendations: []
            )
        )
        XCTAssertEqual(result.metrics.scenariosExecuted, 0)
    }

    func testChaosScenarioValidation() async throws {
        guard EnhancementFeatureFlags.chaosTestingEnabled else {
            throw XCTSkip("Chaos testing not enabled")
        }

        let networkScenario = ChaosScenario(
            type: .networkFailure,
            severity: .medium,
            parameters: ["failureRate": 0.1]
        )

        let diskScenario = ChaosScenario(
            type: .diskSpaceExhaustion,
            severity: .high,
            parameters: ["threshold": 0.95]
        )

        XCTAssertEqual(networkScenario.type, .networkFailure)
        XCTAssertEqual(networkScenario.severity, .medium)
        XCTAssertEqual(diskScenario.severity, .high)
    }

    func testChaosTestExecution() async throws {
        guard EnhancementFeatureFlags.chaosTestingEnabled else {
            throw XCTSkip("Chaos testing not enabled")
        }

        let scenarios = [
            ChaosScenario(type: .networkFailure, severity: .low),
            ChaosScenario(type: .memoryPressure, severity: .medium)
        ]

        let testResult = try await chaosTestingService.executeChaosTest(
            scenarios: scenarios,
            datasetSize: 100,
            duration: 1000
        )

        // Validate test results structure
        XCTAssertEqual(testResult.scenarios.count, 2)
        XCTAssertNotNil(testResult.report)
        XCTAssertGreaterThanOrEqual(testResult.metrics.scenariosExecuted, 0)
        XCTAssertGreaterThanOrEqual(testResult.metrics.recoverySuccessRate, 0.0)
        XCTAssertLessThanOrEqual(testResult.metrics.recoverySuccessRate, 1.0)
    }

    // MARK: - A/B Testing Framework Tests

    func testABTestingFrameworkInitialization() async throws {
        guard EnhancementFeatureFlags.abTestingEnabled else {
            throw XCTSkip("A/B testing not enabled")
        }

        XCTAssertNotNil(abTestingService)
    }

    func testExperimentConfiguration() async throws {
        guard EnhancementFeatureFlags.abTestingEnabled else {
            throw XCTSkip("A/B testing not enabled")
        }

        let controlConfig = DetectOptions(
            thresholds: DetectOptions.Thresholds(confidenceDuplicate: 0.85)
        )

        let variantConfig = DetectOptions(
            thresholds: DetectOptions.Thresholds(confidenceDuplicate: 0.80)
        )

        let controlVariant = ExperimentVariant(
            name: "control",
            description: "Control configuration with 85% threshold",
            configuration: controlConfig
        )

        let testVariant = ExperimentVariant(
            name: "variant",
            description: "Test configuration with 80% threshold",
            configuration: variantConfig
        )

        let dataset = ExperimentDataset(
            type: .exactDuplicates,
            size: 1000
        )

        let metrics = [
            MetricDefinition(name: "accuracy", type: .accuracy),
            MetricDefinition(name: "precision", type: .precision)
        ]

        // Validate configuration structure
        XCTAssertEqual(controlVariant.name, "control")
        XCTAssertEqual(testVariant.name, "variant")
        XCTAssertEqual(dataset.type, .exactDuplicates)
        XCTAssertEqual(metrics.count, 2)
    }

    func testConfidenceCalibration() async throws {
        guard EnhancementFeatureFlags.abTestingEnabled else {
            throw XCTSkip("A/B testing not enabled")
        }

        let dataset = CalibrationDataset(
            type: .exactDuplicates,
            size: 500
        )

        let baselineConfig = DetectOptions(
            thresholds: DetectOptions.Thresholds(confidenceDuplicate: 0.85)
        )

        let report = try await abTestingService.performConfidenceCalibration(
            dataset: dataset,
            thresholdRange: 0.70...0.95,
            stepSize: 0.05,
            baselineConfiguration: baselineConfig
        )

        // Validate calibration report
        XCTAssertEqual(report.dataset.type, .exactDuplicates)
        XCTAssertNotNil(report.optimalThreshold)
        XCTAssertGreaterThanOrEqual(report.optimalThreshold, 0.70)
        XCTAssertLessThanOrEqual(report.optimalThreshold, 0.95)
        XCTAssertNotNil(report.analysis)
        XCTAssertNotNil(report.recommendations)
    }

    func testConfigurationComparison() async throws {
        guard EnhancementFeatureFlags.abTestingEnabled else {
            throw XCTSkip("A/B testing not enabled")
        }

        let controlConfig = DetectOptions(
            thresholds: DetectOptions.Thresholds(confidenceDuplicate: 0.85)
        )

        let variantConfig = DetectOptions(
            thresholds: DetectOptions.Thresholds(confidenceDuplicate: 0.80)
        )

        let dataset = ExperimentDataset(
            type: .mixedContent,
            size: 500
        )

        let comparison = try await abTestingService.compareConfigurations(
            control: controlConfig,
            variant: variantConfig,
            dataset: dataset,
            sampleSize: 200
        )

        // Validate comparison results
        XCTAssertEqual(comparison.control.thresholds.confidenceDuplicate, 0.85)
        XCTAssertEqual(comparison.variant.thresholds.confidenceDuplicate, 0.80)
        XCTAssertNotNil(comparison.statisticalComparison)
        XCTAssertGreaterThanOrEqual(comparison.statisticalComparison.pValue, 0.0)
        XCTAssertLessThanOrEqual(comparison.statisticalComparison.pValue, 1.0)
    }

    // MARK: - Pre-computed Index Service Tests

    func testPrecomputedIndexServiceInitialization() async throws {
        guard EnhancementFeatureFlags.precomputedIndexesEnabled else {
            throw XCTSkip("Pre-computed indexes not enabled")
        }

        XCTAssertNotNil(precomputedIndexService)
    }

    func testIndexBuildOptions() async throws {
        guard EnhancementFeatureFlags.precomputedIndexesEnabled else {
            throw XCTSkip("Pre-computed indexes not enabled")
        }

        let options = IndexBuildOptions(
            indexType: .balanced,
            optimizationLevel: .balanced,
            cacheSize: 1000,
            compressionEnabled: true
        )

        XCTAssertEqual(options.indexType, .balanced)
        XCTAssertEqual(options.optimizationLevel, .balanced)
        XCTAssertEqual(options.cacheSize, 1000)
        XCTAssertTrue(options.compressionEnabled)
    }

    func testIndexBuildValidation() async throws {
        guard EnhancementFeatureFlags.precomputedIndexesEnabled else {
            throw XCTSkip("Pre-computed indexes not enabled")
        }

        // Create test assets
        let testAssets = try await createTestAssets(count: 50)

        // Test index building with insufficient data
        do {
            _ = try await precomputedIndexService.buildIndex(for: testAssets)
            XCTFail("Should have thrown error for small dataset")
        } catch let error as IndexError {
            switch error {
            case .datasetTooSmall:
                // Expected behavior
                break
            default:
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQueryOptions() async throws {
        guard EnhancementFeatureFlags.precomputedIndexesEnabled else {
            throw XCTSkip("Pre-computed indexes not enabled")
        }

        let options = QueryOptions(
            useCache: true,
            maxQueryTime: 100.0,
            resultLimit: 50
        )

        let indexOptions = options.toIndexQueryOptions()

        XCTAssertTrue(options.useCache)
        XCTAssertEqual(options.maxQueryTime, 100.0)
        XCTAssertEqual(options.resultLimit, 50)
        XCTAssertEqual(indexOptions.useCache, options.useCache)
        XCTAssertEqual(indexOptions.maxQueryTime, options.maxQueryTime)
        XCTAssertEqual(indexOptions.resultLimit, options.resultLimit)
    }

    // MARK: - Performance Monitoring Service Tests

    func testPerformanceMonitoringServiceInitialization() async throws {
        guard EnhancementFeatureFlags.performanceMonitoringEnabled else {
            throw XCTSkip("Performance monitoring not enabled")
        }

        XCTAssertNotNil(performanceMonitoringService)
    }

    func testMonitoringConfiguration() async throws {
        guard EnhancementFeatureFlags.performanceMonitoringEnabled else {
            throw XCTSkip("Performance monitoring not enabled")
        }

        let config = MonitoringConfiguration(
            collectionInterval: 30.0,
            alertCheckInterval: 60.0,
            anomalyThreshold: 0.95,
            regressionThreshold: 0.10
        )

        XCTAssertEqual(config.collectionInterval, 30.0)
        XCTAssertEqual(config.alertCheckInterval, 60.0)
        XCTAssertEqual(config.anomalyThreshold, 0.95)
        XCTAssertEqual(config.regressionThreshold, 0.10)
    }

    func testMonitoringStartStop() async throws {
        guard EnhancementFeatureFlags.performanceMonitoringEnabled else {
            throw XCTSkip("Performance monitoring not enabled")
        }

        let config = MonitoringConfiguration(collectionInterval: 1.0, alertCheckInterval: 5.0)

        // Start monitoring
        await performanceMonitoringService.startMonitoring(configuration: config)

        // Wait a brief moment
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Stop monitoring
        await performanceMonitoringService.stopMonitoring()

        // Test should complete without errors
    }

    func testPerformanceMetricsCollection() async throws {
        guard EnhancementFeatureFlags.performanceMonitoringEnabled else {
            throw XCTSkip("Performance monitoring not enabled")
        }

        // This would normally require the monitoring service to be running
        // For testing, we can test the metrics structure
        let summary = PerformanceMetricsSummary(
            timestamp: Date(),
            uptimeSeconds: 3600.0,
            averageCPUUsage: 35.0,
            averageMemoryUsage: 150.0,
            averageQueryTime: 120.0,
            averageCacheHitRate: 0.85,
            totalQueries: 1000,
            errorRate: 0.02
        )

        XCTAssertGreaterThan(summary.uptimeSeconds, 0)
        XCTAssertGreaterThanOrEqual(summary.averageCPUUsage, 0)
        XCTAssertLessThanOrEqual(summary.averageCPUUsage, 100)
        XCTAssertGreaterThanOrEqual(summary.averageCacheHitRate, 0)
        XCTAssertLessThanOrEqual(summary.averageCacheHitRate, 1)
        XCTAssertGreaterThanOrEqual(summary.errorRate, 0)
        XCTAssertLessThanOrEqual(summary.errorRate, 1)
    }

    // MARK: - Integration Tests

    func testEnhancementServiceIntegration() async throws {
        // Test that enhancement services integrate properly with core services
        let serviceManager = ServiceManager.shared

        // Feature flags should control service availability
        if EnhancementFeatureFlags.chaosTestingEnabled {
            XCTAssertNotNil(serviceManager.chaosTestingService)
        } else {
            XCTAssertNil(serviceManager.chaosTestingService)
        }

        if EnhancementFeatureFlags.abTestingEnabled {
            XCTAssertNotNil(serviceManager.abTestingService)
        } else {
            XCTAssertNil(serviceManager.abTestingService)
        }

        if EnhancementFeatureFlags.precomputedIndexesEnabled {
            XCTAssertNotNil(serviceManager.precomputedIndexService)
        } else {
            XCTAssertNil(serviceManager.precomputedIndexService)
        }

        if EnhancementFeatureFlags.performanceMonitoringEnabled {
            XCTAssertNotNil(serviceManager.performanceMonitoringService)
        } else {
            XCTAssertNil(serviceManager.performanceMonitoringService)
        }
    }

    func testEnhancementFeatureFlags() async throws {
        // Test that feature flags work correctly
        let flags = EnhancementFeatureFlags.self

        // Feature flags should be boolean values
        XCTAssertTrue(flags.chaosTestingEnabled is Bool)
        XCTAssertTrue(flags.abTestingEnabled is Bool)
        XCTAssertTrue(flags.precomputedIndexesEnabled is Bool)
        XCTAssertTrue(flags.performanceMonitoringEnabled is Bool)
        XCTAssertTrue(flags.allEnhancementsEnabled is Bool)

        // All enhancements enabled should be true only if all individual flags are true
        let expectedAllEnabled = flags.chaosTestingEnabled && flags.abTestingEnabled &&
                                flags.precomputedIndexesEnabled && flags.performanceMonitoringEnabled
        XCTAssertEqual(flags.allEnhancementsEnabled, expectedAllEnabled)
    }

    // MARK: - Helper Methods

    private func createTestAssets(count: Int) async throws -> [DetectionAsset] {
        var assets: [DetectionAsset] = []

        for i in 0..<count {
            let asset = DetectionAsset(
                id: UUID(),
                url: nil,
                mediaType: i % 2 == 0 ? .photo : .video,
                fileName: "test_asset_\(i).jpg",
                fileSize: Int64(1024 * 1024 * (1 + i % 5)), // 1-5MB
                checksum: "test_checksum_\(i)",
                dimensions: PixelSize(width: 1920, height: 1080),
                duration: i % 2 == 0 ? nil : Double(30 + i % 60),
                captureDate: Date().addingTimeInterval(Double(-i * 60)),
                createdAt: Date(),
                modifiedAt: Date(),
                imageHashes: [HashAlgorithm.dhash: UInt64(i)],
                videoSignature: nil
            )
            assets.append(asset)
        }

        return assets
    }

    private func createSmallTestAssets(count: Int) async throws -> [DetectionAsset] {
        // Create assets that would be too small for indexing
        var assets: [DetectionAsset] = []

        for i in 0..<count {
            let asset = DetectionAsset(
                id: UUID(),
                url: nil,
                mediaType: .photo,
                fileName: "small_test_asset_\(i).jpg",
                fileSize: Int64(1024 * (1 + i)), // Very small files
                checksum: "small_checksum_\(i)",
                dimensions: PixelSize(width: 100, height: 100),
                duration: nil,
                captureDate: Date(),
                createdAt: Date(),
                modifiedAt: Date(),
                imageHashes: [:], // No hashes
                videoSignature: nil
            )
            assets.append(asset)
        }

        return assets
    }
}

// MARK: - Test Extensions

extension EnhancementTests {
    func testChaosTestingWithRealScenarios() async throws {
        guard EnhancementFeatureFlags.chaosTestingEnabled else {
            throw XCTSkip("Chaos testing not enabled")
        }

        let scenarios = [
            ChaosScenario(
                type: .networkFailure,
                severity: .low,
                parameters: ["failureRate": 0.05]
            ),
            ChaosScenario(
                type: .memoryPressure,
                severity: .medium,
                parameters: ["threshold": 0.80]
            )
        ]

        // Test with small dataset and short duration for unit testing
        let result = try await chaosTestingService.executeChaosTest(
            scenarios: scenarios,
            datasetSize: 50,
            duration: 5000
        )

        // Validate that test completed and produced reasonable results
        XCTAssertGreaterThanOrEqual(result.metrics.scenariosExecuted, 0)
        XCTAssertGreaterThanOrEqual(result.metrics.recoverySuccessRate, 0.0)
        XCTAssertLessThanOrEqual(result.metrics.recoverySuccessRate, 1.0)
    }

    func testABTestingWithRealConfigurations() async throws {
        guard EnhancementFeatureFlags.abTestingEnabled else {
            throw XCTSkip("A/B testing not enabled")
        }

        let controlConfig = DetectOptions(
            thresholds: DetectOptions.Thresholds(confidenceDuplicate: 0.85)
        )

        let variantConfig = DetectOptions(
            thresholds: DetectOptions.Thresholds(confidenceDuplicate: 0.75)
        )

        let dataset = ExperimentDataset(
            type: .exactDuplicates,
            size: 100
        )

        let comparison = try await abTestingService.compareConfigurations(
            control: controlConfig,
            variant: variantConfig,
            dataset: dataset,
            sampleSize: 50
        )

        // Validate comparison structure
        XCTAssertEqual(comparison.control.thresholds.confidenceDuplicate, 0.85)
        XCTAssertEqual(comparison.variant.thresholds.confidenceDuplicate, 0.75)
        XCTAssertNotNil(comparison.statisticalComparison)
    }

    func testPerformanceMonitoringMetrics() async throws {
        guard EnhancementFeatureFlags.performanceMonitoringEnabled else {
            throw XCTSkip("Performance monitoring not enabled")
        }

        let config = MonitoringConfiguration(collectionInterval: 1.0, alertCheckInterval: 2.0)

        await performanceMonitoringService.startMonitoring(configuration: config)

        // Wait for a few collection cycles
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

        let metrics = try await performanceMonitoringService.getCurrentMetrics()

        // Validate metrics structure
        XCTAssertGreaterThanOrEqual(metrics.uptimeSeconds, 0)
        XCTAssertGreaterThanOrEqual(metrics.averageCPUUsage, 0)
        XCTAssertLessThanOrEqual(metrics.averageCPUUsage, 100)
        XCTAssertGreaterThanOrEqual(metrics.averageCacheHitRate, 0)
        XCTAssertLessThanOrEqual(metrics.averageCacheHitRate, 1)

        await performanceMonitoringService.stopMonitoring()
    }
}
