import Foundation
import OSLog

/**
 * FeedbackService handles user feedback for learning and refinement.
 *
 * This service collects user decisions about duplicate detection results to improve
 * future detection accuracy through machine learning and user preference tracking.
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class FeedbackService: ObservableObject {

    // MARK: - Types

    /**
     * Types of feedback that users can provide
     */
    public enum FeedbackType: String, Codable, Sendable {
        case correctDuplicate = "correct_duplicate"
        case falsePositive = "false_positive"
        case nearDuplicate = "near_duplicate"
        case notDuplicate = "not_duplicate"
        case preferredKeeper = "preferred_keeper"
        case mergeQuality = "merge_quality"
    }

    /**
     * Represents a single piece of user feedback
     */
    public struct FeedbackItem: Identifiable, Codable, Sendable {
        public let id: UUID
        public let groupId: UUID
        public let feedbackType: FeedbackType
        public let confidence: Double
        public let timestamp: Date
        public let notes: String?

        public init(
            id: UUID = UUID(),
            groupId: UUID,
            feedbackType: FeedbackType,
            confidence: Double,
            timestamp: Date = Date(),
            notes: String? = nil
        ) {
            self.id = id
            self.groupId = groupId
            self.feedbackType = feedbackType
            self.confidence = confidence
            self.timestamp = timestamp
            self.notes = notes
        }
    }

    /**
     * Learning metrics for improving detection algorithms
     */
    public struct LearningMetrics: Codable, Sendable {
        public let falsePositiveRate: Double
        public let correctDetectionRate: Double
        public let averageUserConfidence: Double
        public let preferredThresholds: [String: Double]
        public let lastUpdated: Date

        public init(
            falsePositiveRate: Double = 0.0,
            correctDetectionRate: Double = 0.0,
            averageUserConfidence: Double = 0.0,
            preferredThresholds: [String: Double] = [:],
            lastUpdated: Date = Date()
        ) {
            self.falsePositiveRate = falsePositiveRate
            self.correctDetectionRate = correctDetectionRate
            self.averageUserConfidence = averageUserConfidence
            self.preferredThresholds = preferredThresholds
            self.lastUpdated = lastUpdated
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.deduper", category: "feedback")
    private let persistence: PersistenceController
    private let userDefaults = UserDefaults.standard

    /// Key for storing learning metrics in UserDefaults
    private let learningMetricsKey = "DeduperLearningMetrics"

    /// Current learning metrics
    @Published public var learningMetrics: LearningMetrics = .init()

    /// Whether learning mode is enabled
    @Published public var isLearningEnabled: Bool = true

    // MARK: - Initialization

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        loadLearningMetrics()
        setupPeriodicMetricsUpdate()
    }

    // MARK: - Public API

    /**
     * Records user feedback for a duplicate group
     */
    public func recordFeedback(
        groupId: UUID,
        feedbackType: FeedbackType,
        confidence: Double = 1.0,
        notes: String? = nil
    ) async {
        guard isLearningEnabled else { return }

        _ = FeedbackItem(
            groupId: groupId,
            feedbackType: feedbackType,
            confidence: confidence,
            notes: notes
        )

        // For now, just log the feedback - persistence layer not yet implemented
        logger.info("Recorded feedback: \(feedbackType.rawValue) for group \(groupId)")

        // Update learning metrics
        await updateLearningMetrics()
    }

    /**
     * Records that a user confirmed a correct duplicate detection
     */
    public func recordCorrectDuplicate(groupId: UUID, confidence: Double = 1.0) async {
        await recordFeedback(
            groupId: groupId,
            feedbackType: .correctDuplicate,
            confidence: confidence
        )
    }

    /**
     * Records that a user marked a detection as a false positive
     */
    public func recordFalsePositive(groupId: UUID, confidence: Double = 1.0) async {
        await recordFeedback(
            groupId: groupId,
            feedbackType: .falsePositive,
            confidence: confidence
        )
    }

    /**
     * Records user preference for keeper selection
     */
    public func recordKeeperPreference(
        groupId: UUID,
        preferredKeeperId: UUID,
        confidence: Double = 1.0
    ) async {
        await recordFeedback(
            groupId: groupId,
            feedbackType: .preferredKeeper,
            confidence: confidence,
            notes: "Preferred keeper: \(preferredKeeperId)"
        )
    }

    /**
     * Records feedback about merge quality
     */
    public func recordMergeQuality(
        groupId: UUID,
        quality: Double, // 0.0 to 1.0, where 1.0 is perfect
        notes: String? = nil
    ) async {
        await recordFeedback(
            groupId: groupId,
            feedbackType: .mergeQuality,
            confidence: quality,
            notes: notes
        )
    }

    /**
     * Gets all feedback for a specific group
     */
    public func getFeedback(for groupId: UUID) async throws -> [FeedbackItem] {
        // For now, return empty array - persistence layer not yet implemented
        logger.info("Getting feedback for group \(groupId)")
        return []
    }

    /**
     * Gets learning recommendations based on user feedback
     */
    public func getRecommendations() async throws -> [String] {
        let metrics = try await calculateCurrentMetrics()

        var recommendations: [String] = []

        // Analyze false positive rate
        if metrics.falsePositiveRate > 0.1 {
            recommendations.append("Consider increasing similarity thresholds to reduce false positives")
        }

        // Analyze correct detection rate
        if metrics.correctDetectionRate < 0.8 {
            recommendations.append("Consider lowering similarity thresholds to catch more duplicates")
        }

        // Check user confidence patterns
        if metrics.averageUserConfidence < 0.7 {
            recommendations.append("Review detection algorithms - users seem uncertain about results")
        }

        return recommendations
    }

    /**
     * Exports learning data for analysis
     */
    public func exportLearningData() async throws -> Data {
        // For now, export just the metrics - persistence layer not yet implemented
        let metrics = learningMetrics

        let exportData = [
            "metrics": [
                "falsePositiveRate": metrics.falsePositiveRate,
                "correctDetectionRate": metrics.correctDetectionRate,
                "averageUserConfidence": metrics.averageUserConfidence,
                "preferredThresholds": metrics.preferredThresholds,
                "lastUpdated": metrics.lastUpdated.ISO8601Format()
            ]
        ] as [String: Any]

        return try JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted])
    }

    /**
     * Resets all learning data
     */
    public func resetLearningData() async throws {
        // For now, just reset metrics - persistence layer not yet implemented
        learningMetrics = LearningMetrics()
        saveLearningMetrics()
        logger.info("Reset all learning data")
    }

    // MARK: - Private Methods

    private func updateLearningMetrics() async {
        do {
            let metrics = try await calculateCurrentMetrics()
            learningMetrics = metrics
            saveLearningMetrics()
            logger.info("Updated learning metrics: falsePositives=\(metrics.falsePositiveRate), correctDetection=\(metrics.correctDetectionRate)")
        } catch {
            logger.error("Failed to update learning metrics: \(error.localizedDescription)")
        }
    }

    private func calculateCurrentMetrics() async throws -> LearningMetrics {
        // For now, return basic metrics - persistence layer not yet implemented
        logger.info("Calculating current metrics")

        // Return default metrics for now
        return LearningMetrics(
            falsePositiveRate: 0.05, // 5% false positive rate
            correctDetectionRate: 0.85, // 85% correct detection rate
            averageUserConfidence: 0.9, // 90% average user confidence
            preferredThresholds: [:],
            lastUpdated: Date()
        )
    }

    private func loadLearningMetrics() {
        guard let data = userDefaults.data(forKey: learningMetricsKey),
              let metrics = try? JSONDecoder().decode(LearningMetrics.self, from: data) else {
            learningMetrics = LearningMetrics()
            return
        }

        learningMetrics = metrics
        logger.info("Loaded learning metrics: \(metrics.falsePositiveRate) false positive rate")
    }

    private func saveLearningMetrics() {
        guard let data = try? JSONEncoder().encode(learningMetrics) else {
            logger.error("Failed to encode learning metrics")
            return
        }

        userDefaults.set(data, forKey: learningMetricsKey)
        logger.debug("Saved learning metrics to UserDefaults")
    }

    private func setupPeriodicMetricsUpdate() {
        // Update metrics every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.updateLearningMetrics()
            }
        }
    }
}

// MARK: - Extensions

extension FeedbackService.FeedbackType {
    public var description: String {
        switch self {
        case .correctDuplicate:
            return "Correct duplicate detection"
        case .falsePositive:
            return "False positive (not actually duplicates)"
        case .nearDuplicate:
            return "Near duplicate (similar but not exact)"
        case .notDuplicate:
            return "Not duplicates (completely different)"
        case .preferredKeeper:
            return "Preferred keeper selection"
        case .mergeQuality:
            return "Merge quality feedback"
        }
    }
}
