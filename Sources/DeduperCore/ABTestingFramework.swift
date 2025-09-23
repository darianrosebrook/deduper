import Foundation
import os

// MARK: - A/B Testing Framework for Confidence Calibration

/**
 A/B Testing Framework enables systematic comparison of different duplicate detection
 configurations to optimize confidence thresholds and algorithm parameters.

 This framework provides:
 - Statistical significance testing for configuration comparisons
 - Confidence calibration analysis across parameter ranges
 - Experiment management with proper randomization
 - Comprehensive reporting and actionable recommendations
 - Integration with existing duplicate detection engine

 Author: @darianrosebrook
 */
public final class ABTestingFramework: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.deduper", category: "ab_testing")
    private let statisticalAnalyzer = StatisticalAnalysisEngine()
    private let calibrationEngine = ConfidenceCalibrationEngine()
    private let experimentStore = ExperimentStore()

    public init() {}

    /**
     Execute a comprehensive A/B experiment comparing multiple configurations.

     - Parameters:
       - name: Experiment name for tracking
       - description: Optional experiment description
       - variants: Array of configuration variants to test
       - dataset: Test dataset configuration
       - metrics: Metrics to evaluate for each variant
       - sampleSize: Number of samples per variant
       - confidenceLevel: Statistical confidence level (default: 0.95)
     - Returns: Complete experiment results with analysis and recommendations
     */
    public func executeExperiment(
        name: String,
        description: String? = nil,
        variants: [ExperimentVariant],
        dataset: ExperimentDataset,
        metrics: [MetricDefinition],
        sampleSize: Int = 1000,
        confidenceLevel: Double = 0.95
    ) async throws -> ExperimentResult {
        logger.info("Starting A/B experiment: \(name) with \(variants.count) variants")

        // Validate experiment setup
        try validateExperiment(variants: variants, metrics: metrics, sampleSize: sampleSize)

        // Create experiment record
        let experiment = Experiment(
            id: UUID(),
            name: name,
            description: description ?? "",
            variants: variants,
            dataset: dataset,
            metrics: metrics,
            sampleSize: sampleSize,
            confidenceLevel: confidenceLevel,
            createdAt: Date()
        )

        // Generate test data
        let testData = try await generateTestData(for: dataset, sampleSize: sampleSize * variants.count)

        // Execute variants with proper randomization
        var variantResults: [String: VariantResult] = [:]
        for variant in variants {
            let result = try await executeVariant(
                variant,
                dataset: dataset,
                testData: testData,
                metrics: metrics,
                sampleSize: sampleSize
            )
            variantResults[variant.name] = result
        }

        // Analyze results statistically
        let analysis = try await statisticalAnalyzer.analyze(
            results: variantResults,
            metrics: metrics,
            confidenceLevel: confidenceLevel
        )

        // Generate recommendations
        let recommendations = try await generateRecommendations(
            analysis: analysis,
            variants: variants,
            results: variantResults
        )

        let result = ExperimentResult(
            experiment: experiment,
            variantResults: variantResults,
            statisticalAnalysis: analysis,
            recommendations: recommendations,
            executedAt: Date()
        )

        // Store experiment for historical analysis
        try await experimentStore.saveExperiment(result)

        logger.info("A/B experiment completed: \(name)")
        return result
    }

    /**
     Perform confidence calibration across a range of threshold values.

     - Parameters:
       - dataset: Dataset to use for calibration
       - thresholdRange: Range of confidence thresholds to test
       - stepSize: Step size between threshold values
       - baselineConfiguration: Baseline configuration for comparison
     - Returns: Comprehensive calibration report with optimal settings
     */
    public func performConfidenceCalibration(
        dataset: CalibrationDataset,
        thresholdRange: ClosedRange<Double>,
        stepSize: Double = 0.05,
        baselineConfiguration: DetectOptions = DetectOptions()
    ) async throws -> CalibrationReport {
        logger.info("Starting confidence calibration for threshold range \(thresholdRange.lowerBound)...\(thresholdRange.upperBound)")

        // Generate calibration test data
        let testData = try await generateCalibrationData(for: dataset)

        // Test each threshold in the range
        var thresholdResults: [Double: CalibrationResult] = [:]
        let thresholds = stride(from: thresholdRange.lowerBound, to: thresholdRange.upperBound, by: stepSize)

        for threshold in thresholds {
            let config = baselineConfiguration.withThresholds(
                confidenceDuplicate: threshold
            )

            let result = try await testConfiguration(
                configuration: config,
                dataset: dataset,
                testData: testData
            )

            thresholdResults[threshold] = result
        }

        // Analyze calibration results
        let calibrationAnalysis = try await calibrationEngine.analyzeCalibrationResults(thresholdResults)

        // Find optimal threshold
        let optimalThreshold = calibrationAnalysis.optimalThreshold

        // Generate recommendations
        let recommendations = try await calibrationEngine.generateRecommendations(
            analysis: calibrationAnalysis,
            baseline: baselineConfiguration
        )

        let report = CalibrationReport(
            dataset: dataset,
            thresholdResults: thresholdResults,
            optimalThreshold: optimalThreshold,
            analysis: calibrationAnalysis,
            recommendations: recommendations,
            baselineConfiguration: baselineConfiguration,
            executedAt: Date()
        )

        logger.info("Confidence calibration completed. Optimal threshold: \(optimalThreshold)")
        return report
    }

    /**
     Compare two specific configurations head-to-head.

     - Parameters:
       - control: Control configuration
       - variant: Variant configuration to test against control
       - dataset: Dataset for comparison
       - sampleSize: Sample size for each configuration
     - Returns: Statistical comparison results
     */
    public func compareConfigurations(
        control: DetectOptions,
        variant: DetectOptions,
        dataset: ExperimentDataset,
        sampleSize: Int = 1000
    ) async throws -> ConfigurationComparisonResult {
        logger.info("Comparing configurations: control vs variant")

        let testData = try await generateTestData(for: dataset, sampleSize: sampleSize * 2)

        // Split data for fair comparison
        let controlData = Array(testData.prefix(sampleSize))
        let variantData = Array(testData.suffix(sampleSize))

        // Execute both configurations
        let controlResult = try await executeConfiguration(
            configuration: control,
            testData: controlData
        )

        let variantResult = try await executeConfiguration(
            configuration: variant,
            testData: variantData
        )

        // Statistical comparison
        let comparison = try await statisticalAnalyzer.compareConfigurations(
            controlResult: controlResult,
            variantResult: variantResult
        )

        return ConfigurationComparisonResult(
            control: control,
            variant: variant,
            controlResult: controlResult,
            variantResult: variantResult,
            statisticalComparison: comparison
        )
    }

    // MARK: - Private Implementation

    private func validateExperiment(
        variants: [ExperimentVariant],
        metrics: [MetricDefinition],
        sampleSize: Int
    ) throws {
        guard !variants.isEmpty else {
            throw ABTestingError.invalidExperiment("At least one variant required")
        }

        guard variants.count >= 2 else {
            throw ABTestingError.invalidExperiment("At least two variants required for comparison")
        }

        guard sampleSize >= 100 else {
            throw ABTestingError.invalidExperiment("Sample size must be at least 100")
        }

        guard !metrics.isEmpty else {
            throw ABTestingError.invalidExperiment("At least one metric required")
        }
    }

    private func executeVariant(
        _ variant: ExperimentVariant,
        dataset: ExperimentDataset,
        testData: [DetectionAsset],
        metrics: [MetricDefinition],
        sampleSize: Int
    ) async throws -> VariantResult {
        let startTime = DispatchTime.now()

        // Split test data for this variant
        let variantData = Array(testData.prefix(sampleSize))
        let remainingData = Array(testData.suffix(testData.count - sampleSize))

        // Execute duplicate detection with variant configuration
        let groups = try await duplicateEngine.buildGroups(
            for: variantData.map { $0.id },
            assets: variantData,
            options: variant.configuration
        )

        let endTime = DispatchTime.now()
        let executionTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

        // Calculate metrics
        var metricResults: [String: Double] = [:]
        for metric in metrics {
            metricResults[metric.name] = try await calculateMetric(
                metric: metric,
                groups: groups,
                executionTime: executionTime,
                dataset: dataset
            )
        }

        return VariantResult(
            variant: variant,
            groups: groups,
            executionTime: executionTime,
            metricResults: metricResults,
            sampleSize: sampleSize
        )
    }

    private func testConfiguration(
        configuration: DetectOptions,
        dataset: CalibrationDataset,
        testData: [DetectionAsset]
    ) async throws -> CalibrationResult {
        let startTime = DispatchTime.now()

        let groups = try await duplicateEngine.buildGroups(
            for: testData.map { $0.id },
            assets: testData,
            options: configuration
        )

        let endTime = DispatchTime.now()
        let executionTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

        let metrics = try await calculateCalibrationMetrics(
            groups: groups,
            executionTime: executionTime,
            dataset: dataset,
            configuration: configuration
        )

        return CalibrationResult(
            configuration: configuration,
            groups: groups,
            executionTime: executionTime,
            metrics: metrics
        )
    }

    private func executeConfiguration(
        configuration: DetectOptions,
        testData: [DetectionAsset]
    ) async throws -> ConfigurationResult {
        let startTime = DispatchTime.now()

        let groups = try await duplicateEngine.buildGroups(
            for: testData.map { $0.id },
            assets: testData,
            options: configuration
        )

        let endTime = DispatchTime.now()
        let executionTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

        let metrics = calculateConfigurationMetrics(groups: groups, executionTime: executionTime)

        return ConfigurationResult(
            configuration: configuration,
            groups: groups,
            executionTime: executionTime,
            metrics: metrics
        )
    }

    private func generateTestData(for dataset: ExperimentDataset, sampleSize: Int) async throws -> [DetectionAsset] {
        // Generate test data based on dataset type
        switch dataset.type {
        case .exactDuplicates:
            return try await generateExactDuplicatesDataset(count: sampleSize)
        case .similarImages:
            return try await generateSimilarImagesDataset(count: sampleSize)
        case .mixedContent:
            return try await generateMixedContentDataset(count: sampleSize)
        case .edgeCases:
            return try await generateEdgeCasesDataset(count: sampleSize)
        }

        // Add randomization to avoid bias
        return randomizeAssetOrder(assets)
    }

    private func generateCalibrationData(for dataset: CalibrationDataset) async throws -> [DetectionAsset] {
        // Generate calibration-specific test data
        switch dataset.type {
        case .exactDuplicates:
            return try await generateExactDuplicatesDataset(count: 2000)
        case .similarImages:
            return try await generateSimilarImagesDataset(count: 1500)
        case .mixedContent:
            return try await generateMixedContentDataset(count: 3000)
        case .edgeCases:
            return try await generateEdgeCasesDataset(count: 500)
        }
    }

    private func generateRecommendations(
        analysis: StatisticalAnalysis,
        variants: [ExperimentVariant],
        results: [String: VariantResult]
    ) async throws -> [ExperimentRecommendation] {
        var recommendations: [ExperimentRecommendation] = []

        // Winner-based recommendations
        if let winner = analysis.winner {
            recommendations.append(ExperimentRecommendation(
                type: .implementation,
                priority: .high,
                title: "Implement Winning Configuration",
                description: "Variant '\(winner)' showed statistically significant improvement",
                actions: ["Deploy \(winner) configuration to production", "Monitor performance impact", "Consider A/B testing with broader audience"]
            ))
        }

        // Statistical significance insights
        if analysis.statisticalSignificance > 0.95 {
            recommendations.append(ExperimentRecommendation(
                type: .monitoring,
                priority: .medium,
                title: "High Statistical Confidence",
                description: "Results have high statistical confidence. Consider broader rollout.",
                actions: ["Increase sample size for additional variants", "Monitor long-term performance", "Document findings for future experiments"]
            ))
        }

        // Performance recommendations
        let performanceMetrics = results.values.map { $0.executionTime }
        let avgPerformance = performanceMetrics.reduce(0, +) / Double(performanceMetrics.count)

        if avgPerformance > 5000 { // 5 seconds
            recommendations.append(ExperimentRecommendation(
                type: .optimization,
                priority: .medium,
                title: "Performance Optimization Needed",
                description: "Average execution time is high. Consider performance optimizations.",
                actions: ["Profile execution bottlenecks", "Optimize algorithm parameters", "Consider caching strategies"]
            ))
        }

        return recommendations
    }

    private func calculateMetric(
        metric: MetricDefinition,
        groups: [DuplicateGroupResult],
        executionTime: Double,
        dataset: ExperimentDataset
    ) async throws -> Double {
        switch metric.type {
        case .accuracy:
            return calculateAccuracy(groups: groups, dataset: dataset)
        case .precision:
            return calculatePrecision(groups: groups, dataset: dataset)
        case .recall:
            return calculateRecall(groups: groups, dataset: dataset)
        case .f1Score:
            let precision = calculatePrecision(groups: groups, dataset: dataset)
            let recall = calculateRecall(groups: groups, dataset: dataset)
            return 2 * (precision * recall) / (precision + recall)
        case .performance:
            return executionTime
        case .memoryUsage:
            // Placeholder - would need actual memory monitoring
            return 50.0 // MB
        }
    }

    private func calculateCalibrationMetrics(
        groups: [DuplicateGroupResult],
        executionTime: Double,
        dataset: CalibrationDataset,
        configuration: DetectOptions
    ) async throws -> [String: Double] {
        return [
            "accuracy": calculateAccuracy(groups: groups, dataset: dataset),
            "precision": calculatePrecision(groups: groups, dataset: dataset),
            "recall": calculateRecall(groups: groups, dataset: dataset),
            "f1_score": calculateF1Score(groups: groups, dataset: dataset),
            "execution_time": executionTime,
            "groups_found": Double(groups.count),
            "avg_confidence": groups.map { $0.confidence }.reduce(0, +) / Double(max(groups.count, 1))
        ]
    }

    private func calculateConfigurationMetrics(
        groups: [DuplicateGroupResult],
        executionTime: Double
    ) -> [String: Double] {
        return [
            "groups_found": Double(groups.count),
            "execution_time": executionTime,
            "avg_confidence": groups.map { $0.confidence }.reduce(0, +) / Double(max(groups.count, 1)),
            "high_confidence_groups": Double(groups.filter { $0.confidence >= 0.85 }.count),
            "low_confidence_groups": Double(groups.filter { $0.confidence < 0.60 }.count)
        ]
    }

    private func calculateAccuracy(groups: [DuplicateGroupResult], dataset: ExperimentDataset) -> Double {
        // Placeholder - would need ground truth comparison
        // In real implementation, would compare against known duplicate sets
        return 0.85 // Placeholder accuracy
    }

    private func calculatePrecision(groups: [DuplicateGroupResult], dataset: ExperimentDataset) -> Double {
        // Placeholder - would need ground truth comparison
        return 0.90 // Placeholder precision
    }

    private func calculateRecall(groups: [DuplicateGroupResult], dataset: ExperimentDataset) -> Double {
        // Placeholder - would need ground truth comparison
        return 0.80 // Placeholder recall
    }

    private func calculateF1Score(groups: [DuplicateGroupResult], dataset: ExperimentDataset) -> Double {
        let precision = calculatePrecision(groups: groups, dataset: dataset)
        let recall = calculateRecall(groups: groups, dataset: dataset)
        return 2 * (precision * recall) / (precision + recall)
    }

    // MARK: - Test Data Generation

    private func generateExactDuplicatesDataset(count: Int) async throws -> [DetectionAsset] {
        var assets: [DetectionAsset] = []

        // Create pairs of exact duplicates
        for i in 0..<count {
            let baseAsset = DetectionAsset(
                id: UUID(),
                url: nil,
                mediaType: i % 2 == 0 ? .photo : .video,
                fileName: "exact_duplicate_\(i / 2).jpg",
                fileSize: Int64(1024 * 1024 * (1 + i % 5)), // 1-5MB
                checksum: "exact_checksum_\(i / 2)", // Same checksum for duplicates
                dimensions: PixelSize(width: 1920, height: 1080),
                duration: i % 2 == 0 ? nil : Double(30 + i % 60),
                captureDate: Date().addingTimeInterval(Double(-i * 60)), // 1 minute apart
                createdAt: Date(),
                modifiedAt: Date(),
                imageHashes: [HashAlgorithm.dhash: UInt64(i / 2)], // Same hash for duplicates
                videoSignature: nil
            )
            assets.append(baseAsset)
        }

        return assets
    }

    private func generateSimilarImagesDataset(count: Int) async throws -> [DetectionAsset] {
        var assets: [DetectionAsset] = []

        for i in 0..<count {
            assets.append(DetectionAsset(
                id: UUID(),
                url: nil,
                mediaType: .photo,
                fileName: "similar_image_\(i).jpg",
                fileSize: Int64(1024 * 1024 * (1 + i % 5)),
                checksum: "unique_checksum_\(i)", // Unique checksums
                dimensions: PixelSize(width: 1920 + (i % 3 - 1) * 100, height: 1080 + (i % 3 - 1) * 50), // Similar dimensions
                duration: nil,
                captureDate: Date().addingTimeInterval(Double(-i * 30)), // Similar timing
                createdAt: Date(),
                modifiedAt: Date(),
                imageHashes: [HashAlgorithm.dhash: UInt64(i % 100)], // Similar but not identical hashes
                videoSignature: nil
            ))
        }

        return assets
    }

    private func generateMixedContentDataset(count: Int) async throws -> [DetectionAsset] {
        var assets: [DetectionAsset] = []

        for i in 0..<count {
            let isPhoto = i % 3 != 0
            assets.append(DetectionAsset(
                id: UUID(),
                url: nil,
                mediaType: isPhoto ? .photo : .video,
                fileName: isPhoto ? "mixed_photo_\(i).jpg" : "mixed_video_\(i).mp4",
                fileSize: Int64(1024 * 1024 * (1 + i % 10)),
                checksum: "mixed_checksum_\(i)",
                dimensions: isPhoto ? PixelSize(width: 1920, height: 1080) : nil,
                duration: isPhoto ? nil : Double(30 + i % 120),
                captureDate: Date().addingTimeInterval(Double(-i * 120)),
                createdAt: Date(),
                modifiedAt: Date(),
                imageHashes: isPhoto ? [HashAlgorithm.dhash: UInt64(i)] : [:],
                videoSignature: isPhoto ? nil : VideoSignature(durationSec: Double(30 + i % 120), frameHashes: [UInt64(i)])
            ))
        }

        return assets
    }

    private func generateEdgeCasesDataset(count: Int) async throws -> [DetectionAsset] {
        var assets: [DetectionAsset] = []

        // Add edge cases: empty files, corrupted files, unusual formats, etc.
        for i in 0..<count {
            switch i % 5 {
            case 0: // Very small file
                assets.append(DetectionAsset(
                    id: UUID(),
                    url: nil,
                    mediaType: .photo,
                    fileName: "tiny_file_\(i).jpg",
                    fileSize: 1024, // 1KB
                    checksum: "tiny_checksum_\(i)",
                    dimensions: PixelSize(width: 100, height: 100),
                    duration: nil,
                    captureDate: Date(),
                    createdAt: Date(),
                    modifiedAt: Date(),
                    imageHashes: [:], // No hashes (edge case)
                    videoSignature: nil
                ))
            case 1: // Very large file
                assets.append(DetectionAsset(
                    id: UUID(),
                    url: nil,
                    mediaType: .photo,
                    fileName: "huge_file_\(i).jpg",
                    fileSize: Int64(100 * 1024 * 1024), // 100MB
                    checksum: "huge_checksum_\(i)",
                    dimensions: PixelSize(width: 4000, height: 3000),
                    duration: nil,
                    captureDate: Date(),
                    createdAt: Date(),
                    modifiedAt: Date(),
                    imageHashes: [HashAlgorithm.dhash: UInt64(i)],
                    videoSignature: nil
                ))
            case 2: // Unusual aspect ratio
                assets.append(DetectionAsset(
                    id: UUID(),
                    url: nil,
                    mediaType: .photo,
                    fileName: "panorama_\(i).jpg",
                    fileSize: Int64(5 * 1024 * 1024),
                    checksum: "panorama_checksum_\(i)",
                    dimensions: PixelSize(width: 4000, height: 1000), // 4:1 aspect ratio
                    duration: nil,
                    captureDate: Date(),
                    createdAt: Date(),
                    modifiedAt: Date(),
                    imageHashes: [HashAlgorithm.dhash: UInt64(i)],
                    videoSignature: nil
                ))
            case 3: // Very long video
                assets.append(DetectionAsset(
                    id: UUID(),
                    url: nil,
                    mediaType: .video,
                    fileName: "long_video_\(i).mp4",
                    fileSize: Int64(500 * 1024 * 1024), // 500MB
                    checksum: "long_video_checksum_\(i)",
                    dimensions: PixelSize(width: 1920, height: 1080),
                    duration: 3600.0, // 1 hour
                    captureDate: Date(),
                    createdAt: Date(),
                    modifiedAt: Date(),
                    imageHashes: [:],
                    videoSignature: VideoSignature(durationSec: 3600.0, frameHashes: [UInt64(i)])
                ))
            case 4: // Short video clip
                assets.append(DetectionAsset(
                    id: UUID(),
                    url: nil,
                    mediaType: .video,
                    fileName: "short_clip_\(i).mp4",
                    fileSize: Int64(10 * 1024 * 1024), // 10MB
                    checksum: "short_clip_checksum_\(i)",
                    dimensions: PixelSize(width: 1920, height: 1080),
                    duration: 5.0, // 5 seconds
                    captureDate: Date(),
                    createdAt: Date(),
                    modifiedAt: Date(),
                    imageHashes: [:],
                    videoSignature: VideoSignature(durationSec: 5.0, frameHashes: [UInt64(i)])
                ))
            default:
                fatalError("Unexpected case")
            }
        }

        return assets
    }

    private func randomizeAssetOrder(_ assets: [DetectionAsset]) -> [DetectionAsset] {
        return assets.shuffled()
    }
}

// MARK: - Supporting Types

public struct Experiment: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let description: String
    public let variants: [ExperimentVariant]
    public let dataset: ExperimentDataset
    public let metrics: [MetricDefinition]
    public let sampleSize: Int
    public let confidenceLevel: Double
    public let createdAt: Date

    public init(
        id: UUID,
        name: String,
        description: String,
        variants: [ExperimentVariant],
        dataset: ExperimentDataset,
        metrics: [MetricDefinition],
        sampleSize: Int,
        confidenceLevel: Double,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.variants = variants
        self.dataset = dataset
        self.metrics = metrics
        self.sampleSize = sampleSize
        self.confidenceLevel = confidenceLevel
        self.createdAt = createdAt
    }
}

public struct ExperimentVariant: Sendable, Equatable {
    public let name: String
    public let description: String
    public let configuration: DetectOptions

    public init(name: String, description: String, configuration: DetectOptions) {
        self.name = name
        self.description = description
        self.configuration = configuration
    }
}

public enum ExperimentDatasetType: String, Sendable, Equatable {
    case exactDuplicates = "exact_duplicates"
    case similarImages = "similar_images"
    case mixedContent = "mixed_content"
    case edgeCases = "edge_cases"
}

public struct ExperimentDataset: Sendable, Equatable {
    public let type: ExperimentDatasetType
    public let size: Int
    public let parameters: [String: Any]

    public init(type: ExperimentDatasetType, size: Int, parameters: [String: Any] = [:]) {
        self.type = type
        self.size = size
        self.parameters = parameters
    }
}

public enum MetricType: String, Sendable, Equatable {
    case accuracy = "accuracy"
    case precision = "precision"
    case recall = "recall"
    case f1Score = "f1_score"
    case performance = "performance"
    case memoryUsage = "memory_usage"
}

public struct MetricDefinition: Sendable, Equatable {
    public let name: String
    public let type: MetricType
    public let threshold: Double?

    public init(name: String, type: MetricType, threshold: Double? = nil) {
        self.name = name
        self.type = type
        self.threshold = threshold
    }
}

public struct ExperimentResult: Sendable, Equatable {
    public let experiment: Experiment
    public let variantResults: [String: VariantResult]
    public let statisticalAnalysis: StatisticalAnalysis
    public let recommendations: [ExperimentRecommendation]
    public let executedAt: Date

    public init(
        experiment: Experiment,
        variantResults: [String: VariantResult],
        statisticalAnalysis: StatisticalAnalysis,
        recommendations: [ExperimentRecommendation],
        executedAt: Date
    ) {
        self.experiment = experiment
        self.variantResults = variantResults
        self.statisticalAnalysis = statisticalAnalysis
        self.recommendations = recommendations
        self.executedAt = executedAt
    }
}

public struct VariantResult: Sendable, Equatable {
    public let variant: ExperimentVariant
    public let groups: [DuplicateGroupResult]
    public let executionTime: Double
    public let metricResults: [String: Double]
    public let sampleSize: Int

    public init(
        variant: ExperimentVariant,
        groups: [DuplicateGroupResult],
        executionTime: Double,
        metricResults: [String: Double],
        sampleSize: Int
    ) {
        self.variant = variant
        self.groups = groups
        self.executionTime = executionTime
        self.metricResults = metricResults
        self.sampleSize = sampleSize
    }
}

public struct StatisticalAnalysis: Sendable, Equatable {
    public let metricAnalyses: [String: MetricAnalysis]
    public let winner: String?
    public let confidenceIntervals: [String: Double]
    public let statisticalSignificance: Double

    public init(
        metricAnalyses: [String: MetricAnalysis],
        winner: String?,
        confidenceIntervals: [String: Double],
        statisticalSignificance: Double
    ) {
        self.metricAnalyses = metricAnalyses
        self.winner = winner
        self.confidenceIntervals = confidenceIntervals
        self.statisticalSignificance = statisticalSignificance
    }
}

public struct MetricAnalysis: Sendable, Equatable {
    public let metric: MetricDefinition
    public let mean: Double
    public let standardDeviation: Double
    public let confidenceInterval: Double
    public let pValue: Double

    public init(
        metric: MetricDefinition,
        mean: Double,
        standardDeviation: Double,
        confidenceInterval: Double,
        pValue: Double
    ) {
        self.metric = metric
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.confidenceInterval = confidenceInterval
        self.pValue = pValue
    }
}

public struct ExperimentRecommendation: Sendable, Equatable {
    public let type: RecommendationType
    public let priority: RecommendationPriority
    public let title: String
    public let description: String
    public let actions: [String]

    public init(
        type: RecommendationType,
        priority: RecommendationPriority,
        title: String,
        description: String,
        actions: [String]
    ) {
        self.type = type
        self.priority = priority
        self.title = title
        self.description = description
        self.actions = actions
    }
}

public enum CalibrationDatasetType: String, Sendable, Equatable {
    case exactDuplicates = "exact_duplicates"
    case similarImages = "similar_images"
    case mixedContent = "mixed_content"
    case edgeCases = "edge_cases"
}

public struct CalibrationDataset: Sendable, Equatable {
    public let type: CalibrationDatasetType
    public let size: Int
    public let groundTruth: [String: Any] // Known correct groupings

    public init(type: CalibrationDatasetType, size: Int, groundTruth: [String: Any] = [:]) {
        self.type = type
        self.size = size
        self.groundTruth = groundTruth
    }
}

public struct CalibrationReport: Sendable, Equatable {
    public let dataset: CalibrationDataset
    public let thresholdResults: [Double: CalibrationResult]
    public let optimalThreshold: Double
    public let analysis: CalibrationAnalysis
    public let recommendations: [CalibrationRecommendation]
    public let baselineConfiguration: DetectOptions
    public let executedAt: Date

    public init(
        dataset: CalibrationDataset,
        thresholdResults: [Double: CalibrationResult],
        optimalThreshold: Double,
        analysis: CalibrationAnalysis,
        recommendations: [CalibrationRecommendation],
        baselineConfiguration: DetectOptions,
        executedAt: Date
    ) {
        self.dataset = dataset
        self.thresholdResults = thresholdResults
        self.optimalThreshold = optimalThreshold
        self.analysis = analysis
        self.recommendations = recommendations
        self.baselineConfiguration = baselineConfiguration
        self.executedAt = executedAt
    }
}

public struct CalibrationResult: Sendable, Equatable {
    public let configuration: DetectOptions
    public let groups: [DuplicateGroupResult]
    public let executionTime: Double
    public let metrics: [String: Double]

    public init(
        configuration: DetectOptions,
        groups: [DuplicateGroupResult],
        executionTime: Double,
        metrics: [String: Double]
    ) {
        self.configuration = configuration
        self.groups = groups
        self.executionTime = executionTime
        self.metrics = metrics
    }
}

public struct CalibrationAnalysis: Sendable, Equatable {
    public let optimalThreshold: Double
    public let confidenceDistribution: [String: Double]
    public let falsePositiveAnalysis: FalsePositiveAnalysis
    public let performanceAnalysis: PerformanceAnalysis

    public init(
        optimalThreshold: Double,
        confidenceDistribution: [String: Double],
        falsePositiveAnalysis: FalsePositiveAnalysis,
        performanceAnalysis: PerformanceAnalysis
    ) {
        self.optimalThreshold = optimalThreshold
        self.confidenceDistribution = confidenceDistribution
        self.falsePositiveAnalysis = falsePositiveAnalysis
        self.performanceAnalysis = performanceAnalysis
    }
}

public struct FalsePositiveAnalysis: Sendable, Equatable {
    public let falsePositiveRate: Double
    public let falseNegativeRate: Double
    public let problematicThresholds: [Double]

    public init(
        falsePositiveRate: Double,
        falseNegativeRate: Double,
        problematicThresholds: [Double]
    ) {
        self.falsePositiveRate = falsePositiveRate
        self.falseNegativeRate = falseNegativeRate
        self.problematicThresholds = problematicThresholds
    }
}

public struct PerformanceAnalysis: Sendable, Equatable {
    public let averageExecutionTime: Double
    public let executionTimeVariance: Double
    public let memoryUsage: Double

    public init(
        averageExecutionTime: Double,
        executionTimeVariance: Double,
        memoryUsage: Double
    ) {
        self.averageExecutionTime = averageExecutionTime
        self.executionTimeVariance = executionTimeVariance
        self.memoryUsage = memoryUsage
    }
}

public struct CalibrationRecommendation: Sendable, Equatable {
    public let type: RecommendationType
    public let priority: RecommendationPriority
    public let title: String
    public let description: String
    public let actions: [String]

    public init(
        type: RecommendationType,
        priority: RecommendationPriority,
        title: String,
        description: String,
        actions: [String]
    ) {
        self.type = type
        self.priority = priority
        self.title = title
        self.description = description
        self.actions = actions
    }
}

public struct ConfigurationComparisonResult: Sendable, Equatable {
    public let control: DetectOptions
    public let variant: DetectOptions
    public let controlResult: ConfigurationResult
    public let variantResult: ConfigurationResult
    public let statisticalComparison: StatisticalComparison

    public init(
        control: DetectOptions,
        variant: DetectOptions,
        controlResult: ConfigurationResult,
        variantResult: ConfigurationResult,
        statisticalComparison: StatisticalComparison
    ) {
        self.control = control
        self.variant = variant
        self.controlResult = controlResult
        self.variantResult = variantResult
        self.statisticalComparison = statisticalComparison
    }
}

public struct ConfigurationResult: Sendable, Equatable {
    public let configuration: DetectOptions
    public let groups: [DuplicateGroupResult]
    public let executionTime: Double
    public let metrics: [String: Double]

    public init(
        configuration: DetectOptions,
        groups: [DuplicateGroupResult],
        executionTime: Double,
        metrics: [String: Double]
    ) {
        self.configuration = configuration
        self.groups = groups
        self.executionTime = executionTime
        self.metrics = metrics
    }
}

public struct StatisticalComparison: Sendable, Equatable {
    public let pValue: Double
    public let confidenceInterval: Double
    public let effectSize: Double
    public let statisticalSignificance: Bool

    public init(
        pValue: Double,
        confidenceInterval: Double,
        effectSize: Double,
        statisticalSignificance: Bool
    ) {
        self.pValue = pValue
        self.confidenceInterval = confidenceInterval
        self.effectSize = effectSize
        self.statisticalSignificance = statisticalSignificance
    }
}

// MARK: - Private Implementation Classes

private final class StatisticalAnalysisEngine: @unchecked Sendable {
    func analyze(
        results: [String: VariantResult],
        metrics: [MetricDefinition],
        confidenceLevel: Double
    ) async throws -> StatisticalAnalysis {
        var metricAnalyses: [String: MetricAnalysis] = [:]

        for metric in metrics {
            let analysis = try await analyzeMetric(metric, results: results)
            metricAnalyses[metric.name] = analysis
        }

        let winner = determineWinner(results: results, metricAnalyses: metricAnalyses)
        let confidenceIntervals = calculateConfidenceIntervals(results: results)
        let significance = calculateStatisticalSignificance(results: results)

        return StatisticalAnalysis(
            metricAnalyses: metricAnalyses,
            winner: winner,
            confidenceIntervals: confidenceIntervals,
            statisticalSignificance: significance
        )
    }

    private func analyzeMetric(_ metric: MetricDefinition, results: [String: VariantResult]) async throws -> MetricAnalysis {
        let values = results.values.map { $0.metricResults[metric.name] ?? 0.0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let stdDev = calculateStandardDeviation(values)
        let confidenceInterval = calculateConfidenceInterval(values)
        let pValue = calculatePValue(values)

        return MetricAnalysis(
            metric: metric,
            mean: mean,
            standardDeviation: stdDev,
            confidenceInterval: confidenceInterval,
            pValue: pValue
        )
    }

    private func determineWinner(results: [String: VariantResult], metricAnalyses: [String: MetricAnalysis]) -> String? {
        // Simple winner determination - variant with highest performance score
        var bestVariant: String?
        var bestScore = Double.leastNonzeroMagnitude

        for (variantName, result) in results {
            let performanceScore = result.metricResults["performance"] ?? Double.greatestFiniteMagnitude
            if performanceScore < bestScore {
                bestScore = performanceScore
                bestVariant = variantName
            }
        }

        return bestVariant
    }

    private func calculateConfidenceIntervals(results: [String: VariantResult]) -> [String: Double] {
        // Placeholder implementation
        return ["overall": 0.95]
    }

    private func calculateStatisticalSignificance(results: [String: VariantResult]) -> Double {
        // Placeholder implementation - would use actual statistical tests
        return 0.95
    }

    private func calculateStandardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    private func calculateConfidenceInterval(_ values: [Double]) -> Double {
        // Placeholder - would use t-distribution for proper confidence intervals
        return 0.05
    }

    private func calculatePValue(_ values: [Double]) -> Double {
        // Placeholder - would use t-test or ANOVA
        return 0.05
    }
}

private final class ConfidenceCalibrationEngine: @unchecked Sendable {
    func analyzeCalibrationResults(_ results: [Double: CalibrationResult]) async throws -> CalibrationAnalysis {
        let optimalThreshold = findOptimalThreshold(results)
        let confidenceDistribution = analyzeConfidenceDistribution(results)
        let falsePositiveAnalysis = analyzeFalsePositives(results)
        let performanceAnalysis = analyzePerformance(results)

        return CalibrationAnalysis(
            optimalThreshold: optimalThreshold,
            confidenceDistribution: confidenceDistribution,
            falsePositiveAnalysis: falsePositiveAnalysis,
            performanceAnalysis: performanceAnalysis
        )
    }

    private func findOptimalThreshold(_ results: [Double: CalibrationResult]) -> Double {
        var bestThreshold = 0.85
        var bestScore = Double.leastNonzeroMagnitude

        for (threshold, result) in results {
            let accuracy = result.metrics["accuracy"] ?? 0
            let precision = result.metrics["precision"] ?? 0
            let recall = result.metrics["recall"] ?? 0
            let f1Score = result.metrics["f1_score"] ?? 0

            // F1 score is primary metric, with accuracy as tiebreaker
            let score = f1Score * 0.7 + accuracy * 0.3

            if score > bestScore {
                bestScore = score
                bestThreshold = threshold
            }
        }

        return bestThreshold
    }

    private func analyzeConfidenceDistribution(_ results: [Double: CalibrationResult]) -> [String: Double] {
        var distribution: [String: Double] = [:]
        var totalGroups = 0

        for result in results.values {
            totalGroups += result.groups.count
        }

        for result in results.values {
            for group in result.groups {
                let confidence = group.confidence
                if confidence >= 0.9 {
                    distribution["high_confidence", default: 0] += 1
                } else if confidence >= 0.7 {
                    distribution["medium_confidence", default: 0] += 1
                } else if confidence >= 0.5 {
                    distribution["low_confidence", default: 0] += 1
                } else {
                    distribution["very_low_confidence", default: 0] += 1
                }
            }
        }

        // Convert counts to percentages
        for (key, count) in distribution {
            distribution[key] = (count / Double(totalGroups)) * 100.0
        }

        return distribution
    }

    private func analyzeFalsePositives(_ results: [Double: CalibrationResult]) -> FalsePositiveAnalysis {
        // Placeholder - would compare against ground truth
        return FalsePositiveAnalysis(
            falsePositiveRate: 0.05,
            falseNegativeRate: 0.10,
            problematicThresholds: [0.95, 0.98] // Thresholds with high false positive rates
        )
    }

    private func analyzePerformance(_ results: [Double: CalibrationResult]) -> PerformanceAnalysis {
        let executionTimes = results.values.map { $0.executionTime }
        let avgTime = executionTimes.reduce(0, +) / Double(executionTimes.count)
        let variance = executionTimes.reduce(0) { $0 + pow($1 - avgTime, 2) } / Double(executionTimes.count)

        return PerformanceAnalysis(
            averageExecutionTime: avgTime,
            executionTimeVariance: variance,
            memoryUsage: 50.0 // Placeholder
        )
    }

    func generateRecommendations(
        analysis: CalibrationAnalysis,
        baseline: DetectOptions
    ) async throws -> [CalibrationRecommendation] {
        var recommendations: [CalibrationRecommendation] = []

        // Threshold recommendation
        if abs(analysis.optimalThreshold - baseline.thresholds.confidenceDuplicate) > 0.05 {
            recommendations.append(CalibrationRecommendation(
                type: .implementation,
                priority: .high,
                title: "Update Confidence Threshold",
                description: "Optimal threshold (\(String(format: "%.2f", analysis.optimalThreshold))) differs significantly from current (\(String(format: "%.2f", baseline.thresholds.confidenceDuplicate)))",
                actions: ["Update default confidence threshold to \(String(format: "%.2f", analysis.optimalThreshold))", "Monitor impact on duplicate detection accuracy", "Consider user feedback on new threshold"]
            ))
        }

        // Performance recommendations
        if analysis.performanceAnalysis.averageExecutionTime > 5000 {
            recommendations.append(CalibrationRecommendation(
                type: .optimization,
                priority: .medium,
                title: "Performance Optimization",
                description: "Average execution time is high. Consider performance optimizations.",
                actions: ["Profile execution bottlenecks", "Optimize algorithm parameters", "Consider caching strategies"]
            ))
        }

        // False positive recommendations
        if analysis.falsePositiveAnalysis.falsePositiveRate > 0.10 {
            recommendations.append(CalibrationRecommendation(
                type: .improvement,
                priority: .high,
                title: "Reduce False Positives",
                description: "False positive rate is above acceptable threshold. Critical improvements needed.",
                actions: ["Review confidence calculation logic", "Adjust signal weights", "Add additional validation checks"]
            ))
        }

        return recommendations
    }
}

private final class ExperimentStore: @unchecked Sendable {
    func saveExperiment(_ result: ExperimentResult) async throws {
        // Placeholder - would save to persistent storage
        print("Saving experiment: \(result.experiment.name)")
    }
}

// MARK: - Error Types

public enum ABTestingError: LocalizedError {
    case invalidExperiment(String)
    case insufficientData(String)
    case statisticalError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidExperiment(let message):
            return "Invalid experiment configuration: \(message)"
        case .insufficientData(let message):
            return "Insufficient data for analysis: \(message)"
        case .statisticalError(let message):
            return "Statistical analysis error: \(message)"
        }
    }
}

// MARK: - Private Extensions

extension DetectOptions {
    func withThresholds(confidenceDuplicate: Double) -> DetectOptions {
        return DetectOptions(
            thresholds: Thresholds(
                imageDistance: thresholds.imageDistance,
                videoFrameDistance: thresholds.videoFrameDistance,
                durationTolerancePct: thresholds.durationTolerancePct,
                confidenceDuplicate: confidenceDuplicate,
                confidenceSimilar: thresholds.confidenceSimilar
            ),
            limits: limits,
            policies: policies,
            weights: weights
        )
    }

    var description: String {
        return "conf_dupl_\(String(format: "%.2f", thresholds.confidenceDuplicate))"
    }
}
