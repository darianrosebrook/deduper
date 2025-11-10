import Testing
import SwiftUI
import Foundation
@testable import DeduperUI
@testable import DeduperCore

/**
 * Unit tests for Evidence Panel mapping and display functionality.
 * 
 * Author: @darianrosebrook
 * 
 * Tests verify that confidence signals are correctly mapped to EvidenceItem format
 * and that the EvidencePanel displays real data from duplicate groups.
 */
@Suite struct EvidencePanelTests {
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithChecksumSignal() {
        // Given: A group with checksum match signal
        let checksumSignal = ConfidenceSignal(
            key: "checksum",
            weight: 1.0,
            rawScore: 1.0,
            contribution: 1.0,
            rationale: "checksum match"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 1.0,
            signals: [checksumSignal],
            penalties: [],
            rationale: ["checksum match"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 1.0,
            rationaleLines: ["checksum match"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should have one evidence item with checksum match
        #expect(evidenceItems.count == 1)
        #expect(evidenceItems[0].id == "checksum")
        #expect(evidenceItems[0].label == "Checksum")
        #expect(evidenceItems[0].distanceText == "0")
        #expect(evidenceItems[0].thresholdText == "0")
        #expect(evidenceItems[0].verdict == .pass)
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithHashSignal() {
        // Given: A group with hash distance signal
        let hashSignal = ConfidenceSignal(
            key: "hash",
            weight: 0.4,
            rawScore: 0.8,
            contribution: 0.32,
            rationale: "dHash distance=5"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.85,
            signals: [hashSignal],
            penalties: [],
            rationale: ["dHash distance=5"],
            fileSize: 2048
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.85,
            rationaleLines: ["dHash distance=5"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let thresholds = DetectOptions.Thresholds(imageDistance: 5)
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group, thresholds: thresholds)
        
        // Then: Should have hash evidence item with correct distance
        #expect(evidenceItems.count == 1)
        #expect(evidenceItems[0].id == "hash")
        #expect(evidenceItems[0].label == "Hash Distance")
        #expect(evidenceItems[0].distanceText == "5")
        #expect(evidenceItems[0].thresholdText == "5")
        #expect(evidenceItems[0].verdict == .pass) // contribution > 0.3
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithNameSignal() {
        // Given: A group with name similarity signal
        let nameSignal = ConfidenceSignal(
            key: "name",
            weight: 0.3,
            rawScore: 0.75,
            contribution: 0.225,
            rationale: "name similarity"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.75,
            signals: [nameSignal],
            penalties: [],
            rationale: ["name similarity"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.75,
            rationaleLines: ["name similarity"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should have name evidence item formatted as percentage
        #expect(evidenceItems.count == 1)
        #expect(evidenceItems[0].id == "name")
        #expect(evidenceItems[0].label == "Name")
        #expect(evidenceItems[0].distanceText == "75%")
        #expect(evidenceItems[0].thresholdText == "50%")
        #expect(evidenceItems[0].verdict == .warn) // 0.1 < contribution <= 0.3
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithCaptureTimeSignal() {
        // Given: A group with capture time signal
        let captureSignal = ConfidenceSignal(
            key: "captureTime",
            weight: 0.2,
            rawScore: 0.9,
            contribution: 0.18,
            rationale: "capture delta=2.00s"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.8,
            signals: [captureSignal],
            penalties: [],
            rationale: ["capture delta=2.00s"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.8,
            rationaleLines: ["capture delta=2.00s"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should have capture time evidence item with formatted time delta
        #expect(evidenceItems.count == 1)
        #expect(evidenceItems[0].id == "captureTime")
        #expect(evidenceItems[0].label == "Capture Date")
        #expect(evidenceItems[0].distanceText == "2s")
        #expect(evidenceItems[0].thresholdText == "5m")
        #expect(evidenceItems[0].verdict == .warn) // 0.1 < contribution <= 0.3
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithPenalties() {
        // Given: A group with penalty for missing hash
        let penalty = ConfidencePenalty(
            key: "hashMissing",
            value: -0.1,
            rationale: "image hash missing"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.5,
            signals: [],
            penalties: [penalty],
            rationale: ["hash missing"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.5,
            rationaleLines: ["hash missing"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should have penalty evidence item
        #expect(evidenceItems.count == 1)
        #expect(evidenceItems[0].id == "penalty_hashMissing")
        #expect(evidenceItems[0].label == "Hash Missing")
        #expect(evidenceItems[0].distanceText == "missing")
        #expect(evidenceItems[0].thresholdText == "required")
        #expect(evidenceItems[0].verdict == .fail)
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithMultipleSignals() {
        // Given: A group with multiple signals
        let checksumSignal = ConfidenceSignal(
            key: "checksum",
            weight: 1.0,
            rawScore: 1.0,
            contribution: 1.0,
            rationale: "checksum match"
        )
        
        let hashSignal = ConfidenceSignal(
            key: "hash",
            weight: 0.4,
            rawScore: 0.8,
            contribution: 0.32,
            rationale: "dHash distance=3"
        )
        
        let nameSignal = ConfidenceSignal(
            key: "name",
            weight: 0.3,
            rawScore: 0.6,
            contribution: 0.18,
            rationale: "name similarity"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.9,
            signals: [checksumSignal, hashSignal, nameSignal],
            penalties: [],
            rationale: ["checksum match", "dHash distance=3", "name similarity"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.9,
            rationaleLines: ["checksum match", "dHash distance=3", "name similarity"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let thresholds = DetectOptions.Thresholds(imageDistance: 5)
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group, thresholds: thresholds)
        
        // Then: Should have all signals sorted by contribution (highest first)
        #expect(evidenceItems.count == 3)
        #expect(evidenceItems[0].id == "checksum") // Highest contribution (1.0)
        #expect(evidenceItems[1].id == "hash") // Second highest (0.32)
        #expect(evidenceItems[2].id == "name") // Third highest (0.18)
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithVideoGroup() {
        // Given: A video group with video-specific signals
        let videoSignal = ConfidenceSignal(
            key: "hash",
            weight: 0.4,
            rawScore: 0.85,
            contribution: 0.34,
            rationale: "max frame distance=4"
        )
        
        let durationSignal = ConfidenceSignal(
            key: "duration",
            weight: 0.2,
            rawScore: 0.9,
            contribution: 0.18,
            rationale: "duration delta=0.5"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.88,
            signals: [videoSignal, durationSignal],
            penalties: [],
            rationale: ["max frame distance=4", "duration delta=0.5"],
            fileSize: 10240
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.88,
            rationaleLines: ["max frame distance=4", "duration delta=0.5"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .video
        )
        
        // When: Mapping signals to evidence items
        let thresholds = DetectOptions.Thresholds(videoFrameDistance: 5, durationTolerancePct: 0.02)
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group, thresholds: thresholds)
        
        // Then: Should use video-specific thresholds
        #expect(evidenceItems.count == 2)
        let hashItem = evidenceItems.first { $0.id == "hash" }
        #expect(hashItem != nil)
        #expect(hashItem?.thresholdText == "5") // videoFrameDistance
        
        let durationItem = evidenceItems.first { $0.id == "duration" }
        #expect(durationItem != nil)
        #expect(durationItem?.thresholdText == "2%") // durationTolerancePct * 100
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithEmptyGroup() {
        // Given: An empty group
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [],
            confidence: 0.0,
            rationaleLines: [],
            keeperSuggestion: nil,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should return empty array
        #expect(evidenceItems.count == 0)
    }
    
    @Test func testMapConfidenceSignalsToEvidenceItems_WithMultipleMembers() {
        // Given: A group with multiple members having different signals
        let member1 = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.9,
            signals: [
                ConfidenceSignal(key: "checksum", weight: 1.0, rawScore: 1.0, contribution: 1.0, rationale: "checksum match")
            ],
            penalties: [],
            rationale: ["checksum match"],
            fileSize: 1024
        )
        
        let member2 = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.85,
            signals: [
                ConfidenceSignal(key: "hash", weight: 0.4, rawScore: 0.8, contribution: 0.32, rationale: "dHash distance=3")
            ],
            penalties: [],
            rationale: ["dHash distance=3"],
            fileSize: 2048
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member1, member2],
            confidence: 0.9,
            rationaleLines: ["checksum match", "dHash distance=3"],
            keeperSuggestion: member1.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals to evidence items
        let thresholds = DetectOptions.Thresholds(imageDistance: 5)
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group, thresholds: thresholds)
        
        // Then: Should aggregate signals from all members
        #expect(evidenceItems.count == 2)
        #expect(evidenceItems.contains { $0.id == "checksum" })
        #expect(evidenceItems.contains { $0.id == "hash" })
    }
    
    @Test func testVerdictDetermination_StrongSignal() {
        // Given: Signal with high contribution
        let strongSignal = ConfidenceSignal(
            key: "checksum",
            weight: 1.0,
            rawScore: 1.0,
            contribution: 1.0,
            rationale: "checksum match"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 1.0,
            signals: [strongSignal],
            penalties: [],
            rationale: ["checksum match"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 1.0,
            rationaleLines: ["checksum match"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should have pass verdict
        #expect(evidenceItems[0].verdict == .pass)
    }
    
    @Test func testVerdictDetermination_ModerateSignal() {
        // Given: Signal with moderate contribution
        let moderateSignal = ConfidenceSignal(
            key: "name",
            weight: 0.3,
            rawScore: 0.6,
            contribution: 0.18,
            rationale: "name similarity"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.6,
            signals: [moderateSignal],
            penalties: [],
            rationale: ["name similarity"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.6,
            rationaleLines: ["name similarity"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should have warn verdict
        #expect(evidenceItems[0].verdict == .warn)
    }
    
    @Test func testVerdictDetermination_WeakSignal() {
        // Given: Signal with low contribution
        let weakSignal = ConfidenceSignal(
            key: "metadata",
            weight: 0.2,
            rawScore: 0.3,
            contribution: 0.06,
            rationale: "metadata similarity"
        )
        
        let member = DuplicateGroupMember(
            fileId: UUID(),
            confidence: 0.3,
            signals: [weakSignal],
            penalties: [],
            rationale: ["metadata similarity"],
            fileSize: 1024
        )
        
        let group = DuplicateGroupResult(
            groupId: UUID(),
            members: [member],
            confidence: 0.3,
            rationaleLines: ["metadata similarity"],
            keeperSuggestion: member.fileId,
            incomplete: false,
            mediaType: .photo
        )
        
        // When: Mapping signals
        let evidenceItems = mapConfidenceSignalsToEvidenceItems(group: group)
        
        // Then: Should have fail verdict
        #expect(evidenceItems[0].verdict == .fail)
    }
}

