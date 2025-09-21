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
    
    /// Optional BK-tree for faster similarity searches on large datasets
    private var _bkTree: BKTree?
    private let useBKTree: Bool
    private let bkTreeThreshold: Int = 1000  // Enable BK-tree when dataset exceeds this size
    
    public init(config: HashingConfig = .default, hashingService: ImageHashingService? = nil, useBKTree: Bool = false) {
        self.config = config
        self.hashingService = hashingService ?? ImageHashingService(config: config)
        self.useBKTree = useBKTree
        
        if useBKTree {
            self._bkTree = BKTree(hashingService: self.hashingService)
        }
    }
    
    /// Creates a HashIndexService with automatic BK-tree optimization for large datasets
    public static func optimizedForLargeDataset(config: HashingConfig = .default, hashingService: ImageHashingService? = nil) -> HashIndexService {
        return HashIndexService(config: config, hashingService: hashingService, useBKTree: true)
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
            guard let self = self else { return }
            
            self._entries.append(entry)
            
            // Also insert into BK-tree if enabled
            if self.useBKTree, let bkTree = self._bkTree {
                bkTree.insert(
                    fileId: fileId,
                    hash: hashResult.hash,
                    algorithm: hashResult.algorithm,
                    width: hashResult.width,
                    height: hashResult.height,
                    computedAt: hashResult.computedAt
                )
            }
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
            guard let self = self else { return }
            
            self._entries.append(contentsOf: entries)
            
            // Also insert into BK-tree if enabled
            if self.useBKTree, let bkTree = self._bkTree {
                for hashResult in hashResults {
                    bkTree.insert(
                        fileId: fileId,
                        hash: hashResult.hash,
                        algorithm: hashResult.algorithm,
                        width: hashResult.width,
                        height: hashResult.height,
                        computedAt: hashResult.computedAt
                    )
                }
            }
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
            // Use BK-tree if available and enabled, or if dataset is large enough
            let shouldUseBKTree = useBKTree || _entries.count >= bkTreeThreshold
            if shouldUseBKTree, let bkTree = _bkTree {
                return bkTree.search(hash: hash, maxDistance: distance, algorithm: algorithm, excludeFileId: excludeFileId)
            } else if shouldUseBKTree && _bkTree == nil {
                // Dynamically create BK-tree for large dataset
                _bkTree = BKTree(hashingService: hashingService)
                // Populate with existing entries
                for entry in _entries {
                    _bkTree?.insert(
                        fileId: entry.fileId,
                        hash: entry.hash,
                        algorithm: entry.algorithm,
                        width: entry.width,
                        height: entry.height,
                        computedAt: entry.computedAt
                    )
                }
                logger.info("Dynamically enabled BK-tree for large dataset (\(self._entries.count) entries)")
                return self._bkTree?.search(hash: hash, maxDistance: distance, algorithm: algorithm, excludeFileId: excludeFileId) ?? []
            }
            
            // Fallback to linear search
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
            guard let self = self else { return }
            
            self._entries.removeAll()
            
            // Also clear BK-tree if enabled
            if self.useBKTree {
                self._bkTree?.clear()
            }
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

// MARK: - BK-Tree Implementation

/**
 * BK-tree structure for efficient similarity searches using Hamming distance
 * 
 * BK-trees organize data hierarchically based on distance metrics, allowing
 * for O(log n) nearest-neighbor searches instead of O(n) linear scans.
 * 
 * Each node contains a hash and children organized by their distance from
 * the parent hash. This allows pruning of subtrees during search based on
 * the triangle inequality property of distance metrics.
 * 
 * - Author: @darianrosebrook
 */
public final class BKTree {
    private let hashingService: ImageHashingService
    private var root: BKNode?
    private var nodeCount: Int = 0
    
    public init(hashingService: ImageHashingService) {
        self.hashingService = hashingService
    }
    
    /**
     * Inserts a hash entry into the BK-tree
     * 
     * - Parameters:
     *   - fileId: Unique identifier for the file
     *   - hash: Hash value to insert
     *   - algorithm: Hash algorithm type
     *   - width: Image width
     *   - height: Image height
     *   - computedAt: When the hash was computed
     */
    public func insert(fileId: UUID, hash: UInt64, algorithm: HashAlgorithm, width: Int32, height: Int32, computedAt: Date) {
        let entry = HashIndexEntry(
            fileId: fileId,
            algorithm: algorithm,
            hash: hash,
            width: width,
            height: height,
            computedAt: computedAt
        )
        
        if root == nil {
            root = BKNode(entry: entry)
            nodeCount = 1
        } else {
            insert(entry: entry, into: &root!)
            nodeCount += 1
        }
    }
    
    /**
     * Searches for entries within a specified Hamming distance
     * 
     * - Parameters:
     *   - hash: Target hash to search for
     *   - maxDistance: Maximum Hamming distance for matches
     *   - algorithm: Hash algorithm to search within
     *   - excludeFileId: Optional file ID to exclude from results
     * - Returns: Array of matching entries sorted by distance
     */
    public func search(hash: UInt64, maxDistance: Int, algorithm: HashAlgorithm, excludeFileId: UUID? = nil) -> [HashMatch] {
        guard let root = root else { return [] }
        
        var results: [HashMatch] = []
        search(hash: hash, maxDistance: maxDistance, algorithm: algorithm, excludeFileId: excludeFileId, node: root, results: &results)
        
        // Sort by distance (closest first)
        return results.sorted { $0.distance < $1.distance }
    }
    
    /**
     * Gets the current number of nodes in the tree
     * 
     * - Returns: Total node count
     */
    public func count() -> Int {
        return nodeCount
    }
    
    /**
     * Clears all entries from the tree
     */
    public func clear() {
        root = nil
        nodeCount = 0
    }
    
    // MARK: - Private Methods
    
    private func insert(entry: HashIndexEntry, into node: inout BKNode) {
        let distance = hashingService.hammingDistance(node.entry.hash, entry.hash)
        
        if var existingChild = node.children[distance] {
            // Recursively insert into the existing child
            insert(entry: entry, into: &existingChild)
            node.children[distance] = existingChild
        } else {
            // Create new child at this distance
            node.children[distance] = BKNode(entry: entry)
        }
    }
    
    private func search(hash: UInt64, maxDistance: Int, algorithm: HashAlgorithm, excludeFileId: UUID?, node: BKNode, results: inout [HashMatch]) {
        let distance = hashingService.hammingDistance(hash, node.entry.hash)
        
        // Add this node if it matches criteria
        if distance <= maxDistance && 
           node.entry.algorithm == algorithm &&
           (excludeFileId == nil || node.entry.fileId != excludeFileId!) {
            results.append(HashMatch(
                fileId: node.entry.fileId,
                algorithm: node.entry.algorithm,
                hash: node.entry.hash,
                distance: distance,
                width: node.entry.width,
                height: node.entry.height
            ))
        }
        
        // Search children that could potentially contain matches
        // Using triangle inequality: |a - b| <= |a - c| + |c - b|
        // So we need to search distances where |distance - childDistance| <= maxDistance
        for (childDistance, child) in node.children {
            if abs(distance - childDistance) <= maxDistance {
                search(hash: hash, maxDistance: maxDistance, algorithm: algorithm, excludeFileId: excludeFileId, node: child, results: &results)
            }
        }
    }
}

/**
 * Internal node structure for the BK-tree
 */
private final class BKNode {
    let entry: HashIndexEntry
    var children: [Int: BKNode] = [:]
    
    init(entry: HashIndexEntry) {
        self.entry = entry
    }
}
