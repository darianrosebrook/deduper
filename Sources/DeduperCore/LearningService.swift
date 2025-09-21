import Foundation
import OSLog

/**
 * LearningService manages user feedback and threshold adjustments for duplicate detection.
 *
 * - Persists user decisions about duplicate groups
 * - Provides ignore lists for future scans
 * - Optional threshold tuning based on user confirmations
 * - Integrates with preferences for learning settings
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class LearningService: ObservableObject {
    private let logger = Logger(subsystem: "com.deduper", category: "learning")
    private let persistenceController: PersistenceController

    @Published public var ignoredPairs: Set<String> = []
    @Published public var isLearningEnabled = true
    @Published public var isThresholdTuningEnabled = false

    public init(persistenceController: PersistenceController = PersistenceController.shared) {
        self.persistenceController = persistenceController
        loadPreferences()
    }

    // MARK: - Public API

    /**
     * Marks a group as not containing duplicates for future scans.
     */
    public func ignoreGroup(_ groupId: String, reason: String = "user_decision") async throws {
        guard isLearningEnabled else {
            logger.info("Learning disabled - ignoring group \(groupId)")
            return
        }

        logger.info("Ignoring duplicate group: \(groupId)")

        // Store in preferences
        var ignoredGroups = try await getIgnoredGroups()
        ignoredGroups.insert(groupId)

        try await persistenceController.setPreference("ignoredGroups", value: Array(ignoredGroups))
        logger.info("Stored ignored group: \(groupId)")
    }

    /**
     * Checks if a group should be ignored based on previous user decisions.
     */
    public func shouldIgnoreGroup(_ groupId: String) async throws -> Bool {
        let ignoredGroups = try await getIgnoredGroups()
        return ignoredGroups.contains(groupId)
    }

    /**
     * Records a user decision about a duplicate group.
     */
    public func recordDecision(
        groupId: String,
        accepted: Bool,
        confidence: Double
    ) async throws {
        guard isLearningEnabled else { return }

        let decision = UserDecision(
            groupId: groupId,
            accepted: accepted,
            confidence: confidence,
            timestamp: Date()
        )

        // Store decision for potential threshold tuning
        var decisions = try await getDecisions()
        decisions.append(decision)

        // Keep only recent decisions (last 1000)
        if decisions.count > 1000 {
            decisions = Array(decisions.suffix(1000))
        }

        try await persistenceController.setPreference("userDecisions", value: decisions)
        logger.info("Recorded decision for group \(groupId): accepted=\(accepted)")
    }

    /**
     * Gets suggested threshold adjustments based on user decisions.
     */
    public func suggestThresholdAdjustments() async throws -> [String: Double] {
        guard isThresholdTuningEnabled else {
            return [:]
        }

        let decisions = try await getDecisions()

        // Simple threshold adjustment logic
        var falsePositiveCount = 0
        var falseNegativeCount = 0
        var totalDecisions = 0

        for decision in decisions {
            totalDecisions += 1
            if !decision.accepted && decision.confidence > 0.8 {
                falsePositiveCount += 1
            } else if decision.accepted && decision.confidence < 0.6 {
                falseNegativeCount += 1
            }
        }

        var adjustments: [String: Double] = [:]

        if Double(falsePositiveCount) / Double(totalDecisions) > 0.2 {
            adjustments["duplicateThreshold"] = 0.9 // Make stricter
        } else if Double(falseNegativeCount) / Double(totalDecisions) > 0.2 {
            adjustments["duplicateThreshold"] = 0.7 // Make more lenient
        }

        return adjustments
    }

    /**
     * Clears all learned data and resets to defaults.
     */
    public func resetLearning() async throws {
        try await persistenceController.removePreference(for: "ignoredGroups")
        try await persistenceController.removePreference(for: "userDecisions")
        ignoredPairs.removeAll()
        logger.info("Reset all learning data")
    }

    // MARK: - Private Methods

    private func loadPreferences() {
        Task {
            do {
                if let ignoredGroups: Set<String> = try await persistenceController.preferenceValue(for: "ignoredGroups", as: Set<String>.self) {
                    ignoredPairs = ignoredGroups
                }

                if let decisions: [UserDecision] = try await persistenceController.preferenceValue(for: "userDecisions", as: [UserDecision].self) {
                    // Process decisions if needed
                    logger.info("Loaded \(decisions.count) user decisions")
                }

                if let learningEnabled: Bool = try await persistenceController.preferenceValue(for: "learningEnabled", as: Bool.self) {
                    isLearningEnabled = learningEnabled
                }

                if let thresholdTuning: Bool = try await persistenceController.preferenceValue(for: "thresholdTuningEnabled", as: Bool.self) {
                    isThresholdTuningEnabled = thresholdTuning
                }
            } catch {
                logger.error("Failed to load preferences: \(error.localizedDescription)")
            }
        }
    }

    private func getIgnoredGroups() async throws -> Set<String> {
        if let groups: Set<String> = try await persistenceController.preferenceValue(for: "ignoredGroups", as: Set<String>.self) {
            return groups
        }
        return []
    }

    private func getDecisions() async throws -> [UserDecision] {
        if let decisions: [UserDecision] = try await persistenceController.preferenceValue(for: "userDecisions", as: [UserDecision].self) {
            return decisions
        }
        return []
    }
}

// MARK: - Supporting Types

public struct UserDecision: Codable, Equatable {
    public let groupId: String
    public let accepted: Bool
    public let confidence: Double
    public let timestamp: Date

    public init(groupId: String, accepted: Bool, confidence: Double, timestamp: Date = Date()) {
        self.groupId = groupId
        self.accepted = accepted
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

// MARK: - Preview Support

extension LearningService {
    static func preview() -> LearningService {
        LearningService()
    }
}
