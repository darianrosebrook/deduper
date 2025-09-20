import Foundation
import os

/**
 * In-memory index for fast hash-based similarity queries
 * 
 * This service maintains hash signatures and provides efficient nearest-neighbor
 * lookup using Hamming distance. It supports both exact matches and threshold-based
 * similarity searches.
 * 
 * - Author: @darianrosebrook
 */
public final class HashIndexService: @unchecked Sendable {
    private let logger = Logger(subsystem: "app.deduper", category: "hash")
    private let config: HashingConfig
    private let hashingService: ImageHashingService
    
    /// Thread-safe storage for hash entries
    private let queue = DispatchQueue(label: "hash-index", attributes: .concurrent)
    private var _entries: [HashIndexEntry] = []
    
    public init(config: HashingConfig = .default, hashingService: ImageHashingService? = nil) {
        self.config = config
        self.hashingService = hashingService ?? ImageHashingService(config: config)
    }
    
    // MARK: - Public API
    
    /**
     * Adds a hash entry to the index
     * 
     * - Parameters:
     *   - fileId: Unique identifier for the file
     *   - hashResult: Computed hash result to index
     */
    public func add(fileId: UUID, hashResult: ImageHashResult) {
        let entry = HashIndexEntry(
            fileId: fileId,
            algorithm: hashResult.algorithm,
            hash: hashResult.hash,
            width: hashResult.width,
            height: hashResult.height,
            computedAt: hashResult.computedAt
        )
        
        queue.async(flags: .barrier) { [weak self] in
            self?._entries.append(entry)
        }
        
        logger.debug("Added \(hashResult.algorithm.name) hash for file \(fileId)")
    }
    
    /**
     * Adds multiple hash entries for a single file
     * 
     * - Parameters:
     *   - fileId: Unique identifier for the file
     *   - hashResults: Array of computed hash results to index
     */
    public func add(fileId: UUID, hashResults: [ImageHashResult]) {
        let entries = hashResults.map { hashResult in
            HashIndexEntry(
                fileId: fileId,
                algorithm: hashResult.algorithm,
                hash: hashResult.hash,
                width: hashResult.width,
                height: hashResult.height,
                computedAt: hashResult.computedAt
            )
        }
        
        queue.async(flags: .barrier) { [weak self] in
            self?._entries.append(contentsOf: entries)
        }
        
        logger.debug("Added \(hashResults.count) hash entries for file \(fileId)")
    }
    
    /**
     * Removes all hash entries for a specific file
     * 
     * - Parameter fileId: File identifier to remove
     */
    public func remove(fileId: UUID) {
        queue.async(flags: .barrier) { [weak self] in
            self?._entries.removeAll { $0.fileId == fileId }
        }
        
        logger.debug("Removed hash entries for file \(fileId)")
    }
    
    /**
     * Finds files with hashes within the specified distance of the target hash
     * 
     * - Parameters:
     *   - distance: Maximum Hamming distance for matches
     *   - hash: Target hash to search for
     *   - algorithm: Hash algorithm to search within
     *   - excludeFileId: Optional file ID to exclude from results
     * - Returns: Array of matching file IDs with their distances
     */
    public func queryWithin(distance: Int, of hash: UInt64, algorithm: HashAlgorithm, excludeFileId: UUID? = nil) -> [HashMatch] {
        return queue.sync {
            var matches: [HashMatch] = []
            
            for entry in _entries {
                // Skip if different algorithm
                guard entry.algorithm == algorithm else { continue }
                
                // Skip if this is the excluded file
                if let excludeId = excludeFileId, entry.fileId == excludeId {
                    continue
                }
                
                let hammingDistance = hashingService.hammingDistance(hash, entry.hash)
                if hammingDistance <= distance {
                    matches.append(HashMatch(
                        fileId: entry.fileId,
                        algorithm: entry.algorithm,
                        hash: entry.hash,
                        distance: hammingDistance,
                        width: entry.width,
                        height: entry.height
                    ))
                }
            }
            
            // Sort by distance (closest first)
            return matches.sorted { $0.distance < $1.distance }
        }
    }
    
    /**
     * Finds exact hash matches (distance = 0)
     * 
     * - Parameters:
     *   - hash: Target hash to search for
     *   - algorithm: Hash algorithm to search within
     *   - excludeFileId: Optional file ID to exclude from results
     * - Returns: Array of exactly matching file IDs
     */
    public func findExactMatches(for hash: UInt64, algorithm: HashAlgorithm, excludeFileId: UUID? = nil) -> [HashMatch] {
        return queryWithin(distance: 0, of: hash, algorithm: algorithm, excludeFileId: excludeFileId)
    }
    
    /**
     * Finds near-duplicate matches using configured threshold
     * 
     * - Parameters:
     *   - hash: Target hash to search for
     *   - algorithm: Hash algorithm to search within
     *   - excludeFileId: Optional file ID to exclude from results
     * - Returns: Array of near-duplicate file IDs
     */
    public func findNearDuplicates(for hash: UInt64, algorithm: HashAlgorithm, excludeFileId: UUID? = nil) -> [HashMatch] {
        return queryWithin(distance: config.nearDuplicateThreshold, of: hash, algorithm: algorithm, excludeFileId: excludeFileId)
    }
    
    /**
     * Gets statistics about the current index state
     * 
     * - Returns: Index statistics
     */
    public func getStatistics() -> HashIndexStatistics {
        return queue.sync {
            var algorithmCounts: [HashAlgorithm: Int] = [:]
            var totalDistances: [HashAlgorithm: Int] = [:]
            var comparisonCounts: [HashAlgorithm: Int] = [:]
            
            // Count entries by algorithm
            for entry in _entries {
                algorithmCounts[entry.algorithm, default: 0] += 1
            }
            
            // Calculate average distances for each algorithm
            for algorithm in HashAlgorithm.allCases {
                let entriesForAlgorithm = _entries.filter { $0.algorithm == algorithm }
                var totalDistance = 0
                var comparisons = 0
                
                for i in 0..<entriesForAlgorithm.count {
                    for j in (i+1)..<entriesForAlgorithm.count {
                        let distance = hashingService.hammingDistance(
                            entriesForAlgorithm[i].hash,
                            entriesForAlgorithm[j].hash
                        )
                        totalDistance += distance
                        comparisons += 1
                    }
                }
                
                totalDistances[algorithm] = totalDistance
                comparisonCounts[algorithm] = comparisons
            }
            
            // Compute averages per algorithm
            var averages: [HashAlgorithm: Double] = [:]
            for (alg, total) in totalDistances {
                let comps = comparisonCounts[alg] ?? 0
                averages[alg] = comps > 0 ? Double(total) / Double(comps) : 0.0
            }
            return HashIndexStatistics(
                totalEntries: _entries.count,
                entriesByAlgorithm: algorithmCounts,
                averageDistances: averages
            )
        }
    }
    
    /**
     * Clears all entries from the index
     */
    public func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?._entries.removeAll()
        }
        
        logger.debug("Cleared hash index")
    }
    
    /**
     * Gets the current number of entries in the index
     * 
     * - Returns: Total entry count
     */
    public func count() -> Int {
        return queue.sync { _entries.count }
    }
}

// MARK: - Supporting Types

/**
 * Internal representation of a hash entry in the index
 */
private struct HashIndexEntry {
    let fileId: UUID
    let algorithm: HashAlgorithm
    let hash: UInt64
    let width: Int32
    let height: Int32
    let computedAt: Date
}

/**
 * Result of a hash similarity query
 * 
 * - Author: @darianrosebrook
 */
public struct HashMatch: Sendable, Equatable {
    public let fileId: UUID
    public let algorithm: HashAlgorithm
    public let hash: UInt64
    public let distance: Int
    public let width: Int32
    public let height: Int32
    
    /// Confidence level based on distance (0.0 = no match, 1.0 = exact match)
    public var confidence: Double {
        // For 64-bit hashes, maximum distance is 64
        return max(0.0, 1.0 - (Double(distance) / 64.0))
    }
    
    /// Whether this is considered an exact duplicate
    public var isExactDuplicate: Bool {
        return distance == 0
    }
    
    /// Whether this is considered a near duplicate (within reasonable threshold)
    public var isNearDuplicate: Bool {
        return distance <= 5 // Default threshold, could be configurable
    }
    
    public init(fileId: UUID, algorithm: HashAlgorithm, hash: UInt64, distance: Int, width: Int32, height: Int32) {
        self.fileId = fileId
        self.algorithm = algorithm
        self.hash = hash
        self.distance = distance
        self.width = width
        self.height = height
    }
}

/**
 * Statistics about the hash index state
 * 
 * - Author: @darianrosebrook
 */
public struct HashIndexStatistics: Sendable {
    public let totalEntries: Int
    public let entriesByAlgorithm: [HashAlgorithm: Int]
    public let averageDistances: [HashAlgorithm: Double]
    
    public init(totalEntries: Int, entriesByAlgorithm: [HashAlgorithm: Int], averageDistances: [HashAlgorithm: Double]) {
        self.totalEntries = totalEntries
        self.entriesByAlgorithm = entriesByAlgorithm
        self.averageDistances = averageDistances
    }
}

// MARK: - BK-Tree Implementation (Future Enhancement)

/**
 * Optional BK-tree structure for faster similarity searches on large datasets
 * 
 * This is a placeholder for future optimization when the dataset grows large.
 * BK-trees can significantly speed up nearest-neighbor searches by pre-organizing
 * data based on distance metrics.
 * 
 * - Author: @darianrosebrook
 */
public final class BKTree {
    // TODO: Implement BK-tree for O(log n) similarity searches
    // See: https://en.wikipedia.org/wiki/BK-tree
    
    // For now, we use linear search which is adequate for moderate dataset sizes
    // Implementation can be added when performance testing indicates need
}
