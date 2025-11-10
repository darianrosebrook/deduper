import Foundation

/**
 * SelectionPreset defines automated strategies for selecting keeper files from duplicate groups.
 * 
 * Author: @darianrosebrook
 * 
 * These presets provide different heuristics for automatically determining which file
 * should be kept when duplicates are found. Each preset prioritizes different criteria
 * based on user preferences and use cases.
 */
public enum SelectionPreset: String, Codable, Sendable, CaseIterable {
    /// Keep the file with the highest resolution (pixel count)
    case highestResolution = "highest_resolution"
    
    /// Keep the largest file by size
    case largestFile = "largest_file"
    
    /// Keep the most recently created/modified file
    case keepLatest = "keep_latest"
    
    /// Keep the earliest created file (preserves originals)
    case keepEarliest = "keep_earliest"
    
    /// Keep the file with the most complete metadata
    case bestMetadata = "best_metadata"
    
    /// Keep the file with the best format (RAW > PNG > JPEG > HEIC)
    case bestFormat = "best_format"
    
    /// Use the default intelligent selection (current suggestKeeper logic)
    case intelligent = "intelligent"
    
    /// Custom selection - user manually chooses
    case custom = "custom"
    
    public var displayName: String {
        switch self {
        case .highestResolution:
            return "Highest Resolution"
        case .largestFile:
            return "Largest File"
        case .keepLatest:
            return "Keep Latest"
        case .keepEarliest:
            return "Keep Earliest"
        case .bestMetadata:
            return "Best Metadata"
        case .bestFormat:
            return "Best Format"
        case .intelligent:
            return "Intelligent Selection"
        case .custom:
            return "Manual Selection"
        }
    }
    
    public var description: String {
        switch self {
        case .highestResolution:
            return "Keeps the file with the highest pixel count (width × height)"
        case .largestFile:
            return "Keeps the file with the largest file size"
        case .keepLatest:
            return "Keeps the most recently created or modified file"
        case .keepEarliest:
            return "Keeps the earliest created file (preserves originals)"
        case .bestMetadata:
            return "Keeps the file with the most complete EXIF/metadata"
        case .bestFormat:
            return "Keeps the file with the best format quality (RAW > PNG > JPEG > HEIC)"
        case .intelligent:
            return "Uses intelligent selection considering resolution, size, format, and metadata"
        case .custom:
            return "Manually select which file to keep"
        }
    }
    
    public var iconName: String {
        switch self {
        case .highestResolution:
            return "viewfinder"
        case .largestFile:
            return "doc.fill"
        case .keepLatest:
            return "clock.badge.checkmark"
        case .keepEarliest:
            return "clock.badge.xmark"
        case .bestMetadata:
            return "info.circle.fill"
        case .bestFormat:
            return "photo.fill"
        case .intelligent:
            return "brain.head.profile"
        case .custom:
            return "hand.point.up.left.fill"
        }
    }
}

/**
 * SelectionPresetService applies selection presets to duplicate groups.
 */
@MainActor
public struct SelectionPresetService {
    private let metadataService: MetadataExtractionService
    
    public init(metadataService: MetadataExtractionService) {
        self.metadataService = metadataService
    }
    
    /**
     * Applies a selection preset to a duplicate group and returns the suggested keeper file ID.
     */
    public func applyPreset(
        _ preset: SelectionPreset,
        to group: DuplicateGroupResult
    ) async -> UUID? {
        guard !group.members.isEmpty else { return nil }
        
        // Load metadata for all members
        var membersWithMetadata: [(member: DuplicateGroupMember, metadata: MediaMetadata)] = []
        
        for member in group.members {
            guard let url = ServiceManager.shared.persistence.resolveFileURL(id: member.fileId) else {
                continue
            }
            
            let metadata = metadataService.readFor(url: url, mediaType: group.mediaType)
            membersWithMetadata.append((member, metadata))
        }
        
        guard !membersWithMetadata.isEmpty else { return nil }
        
        switch preset {
        case .highestResolution:
            return selectHighestResolution(from: membersWithMetadata)
        case .largestFile:
            return selectLargestFile(from: membersWithMetadata)
        case .keepLatest:
            return selectLatest(from: membersWithMetadata)
        case .keepEarliest:
            return selectEarliest(from: membersWithMetadata)
        case .bestMetadata:
            return selectBestMetadata(from: membersWithMetadata)
        case .bestFormat:
            return selectBestFormat(from: membersWithMetadata)
        case .intelligent:
            return selectIntelligent(from: membersWithMetadata)
        case .custom:
            return nil // User must manually select
        }
    }
    
    private func selectHighestResolution(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        let sorted = members.sorted { lhs, rhs in
            let res1 = (lhs.metadata.dimensions?.width ?? 0) * (lhs.metadata.dimensions?.height ?? 0)
            let res2 = (rhs.metadata.dimensions?.width ?? 0) * (rhs.metadata.dimensions?.height ?? 0)
            if res1 != res2 {
                return res1 > res2
            }
            // Tiebreaker: file size
            return lhs.metadata.fileSize > rhs.metadata.fileSize
        }
        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }
    
    private func selectLargestFile(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        let sorted = members.sorted { lhs, rhs in
            if lhs.metadata.fileSize != rhs.metadata.fileSize {
                return lhs.metadata.fileSize > rhs.metadata.fileSize
            }
            // Tiebreaker: resolution
            let res1 = (lhs.metadata.dimensions?.width ?? 0) * (lhs.metadata.dimensions?.height ?? 0)
            let res2 = (rhs.metadata.dimensions?.width ?? 0) * (rhs.metadata.dimensions?.height ?? 0)
            return res1 > res2
        }
        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }
    
    private func selectLatest(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        let sorted = members.sorted { lhs, rhs in
            // Compare modification dates first
            if let date1 = lhs.metadata.modifiedAt, let date2 = rhs.metadata.modifiedAt {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if lhs.metadata.modifiedAt != nil {
                return true
            } else if rhs.metadata.modifiedAt != nil {
                return false
            }
            
            // Fallback to creation date
            if let date1 = lhs.metadata.createdAt, let date2 = rhs.metadata.createdAt {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if lhs.metadata.createdAt != nil {
                return true
            } else if rhs.metadata.createdAt != nil {
                return false
            }
            
            // Fallback to capture date
            if let date1 = lhs.metadata.captureDate, let date2 = rhs.metadata.captureDate {
                if date1 != date2 {
                    return date1 > date2
                }
            } else if lhs.metadata.captureDate != nil {
                return true
            } else if rhs.metadata.captureDate != nil {
                return false
            }
            
            // Final fallback: filename
            return lhs.metadata.fileName > rhs.metadata.fileName
        }
        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }
    
    private func selectEarliest(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        let sorted = members.sorted { lhs, rhs in
            // Compare creation dates first
            if let date1 = lhs.metadata.createdAt, let date2 = rhs.metadata.createdAt {
                if date1 != date2 {
                    return date1 < date2
                }
            } else if lhs.metadata.createdAt != nil {
                return true
            } else if rhs.metadata.createdAt != nil {
                return false
            }
            
            // Fallback to capture date
            if let date1 = lhs.metadata.captureDate, let date2 = rhs.metadata.captureDate {
                if date1 != date2 {
                    return date1 < date2
                }
            } else if lhs.metadata.captureDate != nil {
                return true
            } else if rhs.metadata.captureDate != nil {
                return false
            }
            
            // Fallback to modification date
            if let date1 = lhs.metadata.modifiedAt, let date2 = rhs.metadata.modifiedAt {
                if date1 != date2 {
                    return date1 < date2
                }
            } else if lhs.metadata.modifiedAt != nil {
                return true
            } else if rhs.metadata.modifiedAt != nil {
                return false
            }
            
            // Final fallback: filename
            return lhs.metadata.fileName < rhs.metadata.fileName
        }
        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }
    
    private func selectBestMetadata(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        let sorted = members.sorted { lhs, rhs in
            let score1 = lhs.metadata.completenessScore
            let score2 = rhs.metadata.completenessScore
            if score1 != score2 {
                return score1 > score2
            }
            // Tiebreaker: resolution
            let res1 = (lhs.metadata.dimensions?.width ?? 0) * (lhs.metadata.dimensions?.height ?? 0)
            let res2 = (rhs.metadata.dimensions?.width ?? 0) * (rhs.metadata.dimensions?.height ?? 0)
            return res1 > res2
        }
        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }
    
    private func selectBestFormat(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        let sorted = members.sorted { lhs, rhs in
            let score1 = lhs.metadata.formatPreferenceScore
            let score2 = rhs.metadata.formatPreferenceScore
            if score1 != score2 {
                return score1 > score2
            }
            // Tiebreaker: resolution
            let res1 = (lhs.metadata.dimensions?.width ?? 0) * (lhs.metadata.dimensions?.height ?? 0)
            let res2 = (rhs.metadata.dimensions?.width ?? 0) * (rhs.metadata.dimensions?.height ?? 0)
            return res1 > res2
        }
        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }
    
    private func selectIntelligent(from members: [(member: DuplicateGroupMember, metadata: MediaMetadata)]) -> UUID {
        // Use the same logic as MergeService.selectBestKeeper
        let sorted = members.sorted { lhs, rhs in
            let meta1 = lhs.metadata
            let meta2 = rhs.metadata
            
            // Primary: resolution (higher is better)
            let res1 = (meta1.dimensions?.width ?? 0) * (meta1.dimensions?.height ?? 0)
            let res2 = (meta2.dimensions?.width ?? 0) * (meta2.dimensions?.height ?? 0)
            if res1 != res2 {
                return res1 > res2
            }
            
            // Secondary: file size (larger is better)
            if meta1.fileSize != meta2.fileSize {
                return meta1.fileSize > meta2.fileSize
            }
            
            // Tertiary: format preference (RAW/PNG > JPEG > HEIC)
            if meta1.formatPreferenceScore != meta2.formatPreferenceScore {
                return meta1.formatPreferenceScore > meta2.formatPreferenceScore
            }
            
            // Quaternary: metadata completeness
            if meta1.completenessScore != meta2.completenessScore {
                return meta1.completenessScore > meta2.completenessScore
            }
            
            // Final: earliest capture date
            if let date1 = meta1.captureDate, let date2 = meta2.captureDate {
                if date1 != date2 {
                    return date1 < date2
                }
            } else if meta1.captureDate != nil {
                return true
            } else if meta2.captureDate != nil {
                return false
            }
            
            // Ultimate fallback: deterministic path comparison
            return meta1.fileName < meta2.fileName
        }
        
        return sorted.first?.member.fileId ?? members.first!.member.fileId
    }
}

