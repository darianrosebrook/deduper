# Implementation Details: Specific Changes Required

This document provides explicit implementation details for each TODO, showing exactly what needs to be changed where.

---

## 🔴 CRITICAL PRIORITY

### 1. Detection Engine - Persistence Integration
**Location**: `Sources/DeduperCore/DuplicateDetectionEngine.swift:717`

**Current Code**:
```swift
// TODO: Integrate with Module 06 - Results Storage & Persistence
// - Persist DuplicateGroup entities with confidenceScore, rationaleSummary, keeperSuggestion
// - Persist GroupMember entities with per-signal contributions and distance values
```

**Changes Needed**:

**A. In PersistenceController.swift** (new methods):
```swift
// Add these methods to PersistenceController class:

// Save detection results to CoreData
public func saveDetectionResults(_ groups: [DuplicateGroupResult], metrics: DetectionMetrics) throws {
    let context = container.viewContext

    // Create or update DuplicateGroup entities
    for group in groups {
        let groupEntity = DuplicateGroup(context: context)
        groupEntity.id = group.groupId
        groupEntity.confidenceScore = group.confidence
        groupEntity.rationale = group.rationaleLines.joined(separator: "\n")
        groupEntity.createdAt = Date()

        // Save group members with signal contributions
        for member in group.members {
            let memberEntity = GroupMember(context: context)
            memberEntity.id = member.fileId
            memberEntity.confidenceScore = member.confidence
            memberEntity.hammingDistance = Int16(member.hammingDistance)
            // Store signal contributions as JSON
            let signalsData = try JSONEncoder().encode(member.signals)
            memberEntity.signalsBlob = signalsData
            // ... continue for penalties and other fields
        }
    }

    try context.save()
}
```

**B. In DuplicateDetectionEngine.swift:716**:
```swift
// Replace the TODO with:
do {
    try PersistenceController.shared.saveDetectionResults(grouped, metrics: metrics)
    logger.info("Detection results persisted successfully")
} catch {
    logger.error("Failed to persist detection results: \(error.localizedDescription)")
}
```

**C. In PersistenceController programmatic model** (add these entities):
```swift
// In the programmatic model creation, add:
func createDuplicateGroupEntity() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "DuplicateGroup"
    entity.properties = [
        makeAttribute("id", .UUIDAttributeType, optional: false),
        makeAttribute("confidenceScore", .doubleAttributeType, defaultValue: 0.0),
        makeAttribute("rationale", .stringAttributeType),
        makeAttribute("createdAt", .dateAttributeType, optional: false),
        // Add other properties...
    ]
    return entity
}

func createGroupMemberEntity() -> NSEntityDescription {
    let entity = NSEntityDescription()
    entity.name = "GroupMember"
    entity.properties = [
        makeAttribute("id", .UUIDAttributeType, optional: false),
        makeAttribute("confidenceScore", .doubleAttributeType, defaultValue: 0.0),
        makeAttribute("hammingDistance", .integer16AttributeType, defaultValue: 0),
        makeTransformableAttribute("signalsBlob", transformerName: "NSSecureUnarchiveFromDataTransformer"),
        // Add other properties...
    ]
    return entity
}
```

---

## 🟠 HIGH PRIORITY

### 2. Scan Pause/Resume Implementation
**Location**: `Sources/DeduperUI/Views.swift:193-194`

**Current Code**:
```swift
public func pause() {
    isPaused.toggle()
    // TODO: Implement pause/resume
}
```

**Changes Needed**:

**A. In ScanStatusViewModel** (add properties):
```swift
@Published public var isPaused: Bool = false
@Published public var canPause: Bool = true
private var currentTask: Task<Void, Never>?
```

**B. In ScanStatusViewModel** (implement pause/resume):
```swift
public func pause() {
    isPaused = true
    // Signal detection engine to pause
    NotificationCenter.default.post(name: .scanPaused, object: nil)
}

public func resume() {
    isPaused = false
    // Signal detection engine to resume
    NotificationCenter.default.post(name: .scanResumed, object: nil)
}
```

**C. In DuplicateDetectionEngine** (add pause support):
```swift
private var isPaused = false
private var pauseContinuation: CheckedContinuation<Void, Never>?

public func pauseScan() async {
    guard !isPaused else { return }
    isPaused = true

    await withCheckedContinuation { continuation in
        pauseContinuation = continuation
        // Wait for resume signal
    }
}

public func resumeScan() {
    isPaused = false
    pauseContinuation?.resume()
    pauseContinuation = nil
}
```

**D. In UI** (update button logic):
```swift
Button(isPaused ? "Resume" : "Pause", action: isPaused ? viewModel.resume : viewModel.pause)
    .disabled(!viewModel.canPause)
```

---

### 3. Scan Cancellation Implementation
**Location**: `Sources/DeduperUI/Views.swift:197-199`

**Current Code**:
```swift
public func cancel() {
    // TODO: Implement cancellation
    print("Scan cancelled")
}
```

**Changes Needed**:

**A. In ScanStatusViewModel** (add cancellation):
```swift
@Published public var isCancelling: Bool = false
@Published public var canCancel: Bool = true

public func cancel() {
    isCancelling = true
    canCancel = false

    // Cancel the current task
    currentTask?.cancel()

    // Clean up resources
    cleanupScan()

    // Notify UI
    NotificationCenter.default.post(name: .scanCancelled, object: nil)
}

private func cleanupScan() {
    // Clean up temporary files, reset state, etc.
    // Implementation depends on what resources need cleaning
}
```

**B. In detection engine** (add cancellation support):
```swift
public func cancelScan() {
    // Cancel any ongoing tasks
    currentTask?.cancel()

    // Clean up engine state
    resetEngineState()

    // Remove partial results
    cleanupPartialResults()
}
```

---

### 4. Keeper Selection Implementation
**Location**: `Sources/DeduperUI/Views.swift:394-396`

**Current Code**:
```swift
public func setKeeper(for group: DuplicateGroupResult) {
    // TODO: Implement keeper selection
    print("Set keeper for group: \(group.id)")
}
```

**Changes Needed**:

**A. In GroupsListViewModel** (add keeper selection):
```swift
@Published public var selectedKeeper: [UUID: UUID] = [:] // groupId -> keeperFileId

public func setKeeper(for group: DuplicateGroupResult, keeperId: UUID) {
    selectedKeeper[group.id] = keeperId

    // Update the group with new keeper suggestion
    if let index = groups.firstIndex(where: { $0.id == group.id }) {
        var updatedGroup = groups[index]
        updatedGroup.keeperSuggestion = keeperId
        groups[index] = updatedGroup

        // Persist the selection
        Task {
            try await mergeService.updateKeeperSuggestion(groupId: group.id, keeperId: keeperId)
        }
    }
}
```

**B. In GroupDetailView** (add UI for keeper selection):
```swift
// Add picker or radio buttons for keeper selection
Picker("Select Keeper", selection: $viewModel.selectedKeeper) {
    ForEach(group.members, id: \.fileId) { member in
        Text(member.fileName).tag(member.fileId)
    }
}
.onChange(of: viewModel.selectedKeeper) { newKeeper in
    if let keeperId = newKeeper {
        viewModel.setKeeper(for: group, keeperId: keeperId)
    }
}
```

---

### 5. Group Merge Implementation
**Location**: `Sources/DeduperUI/Views.swift:399-401`

**Current Code**:
```swift
public func mergeGroup(_ group: DuplicateGroupResult) {
    // TODO: Implement group merge
    print("Merge group: \(group.id)")
}
```

**Changes Needed**:

**A. In GroupsListViewModel** (implement merge):
```swift
public func mergeGroup(_ group: DuplicateGroupResult) async throws {
    guard let keeperId = selectedKeeper[group.id] ?? group.keeperSuggestion ?? group.members.first?.fileId else {
        throw MergeError.keeperNotFound(group.id)
    }

    // Show merge progress
    isProcessing = true

    do {
        let result = try await mergeService.merge(groupId: group.id, keeperId: keeperId)

        // Remove merged group from list
        groups.removeAll { $0.id == group.id }
        applyFilters()

        // Show success feedback
        showMergeResult(result)
    } catch {
        // Show error feedback
        error = error.localizedDescription
    }

    isProcessing = false
}
```

**B. In GroupDetailView** (add merge button):
```swift
if viewModel.isProcessing {
    ProgressView("Merging...")
} else {
    Button("Merge Group", action: {
        Task {
            try await viewModel.mergeGroup(group)
        }
    })
    .disabled(viewModel.selectedKeeper == nil)
    .keyboardShortcut(.return, modifiers: .command)
}
```

---

### 6. Finder Integration
**Location**: `Sources/DeduperUI/Views.swift:404-406`

**Current Code**:
```swift
public func showInFinder(_ group: DuplicateGroupResult) {
    // TODO: Implement Finder integration
    print("Show group in Finder: \(group.id)")
}
```

**Changes Needed**:

**A. In GroupsListViewModel** (implement Finder integration):
```swift
public func showInFinder(_ group: DuplicateGroupResult) {
    let fileManager = FileManager.default

    // Collect all file URLs for the group
    var fileURLs: [URL] = []
    for member in group.members {
        // This would need to be implemented to get file paths from fileIds
        // For now, this is a placeholder
        if let filePath = getFilePath(for: member.fileId) {
            fileURLs.append(filePath)
        }
    }

    guard !fileURLs.isEmpty else { return }

    // Show files in Finder
    NSWorkspace.shared.activateFileViewerSelecting(fileURLs)
}
```

**B. Helper method needed**:
```swift
private func getFilePath(for fileId: UUID) -> URL? {
    // Query CoreData for file path by fileId
    // Implementation depends on File entity structure
    // This would need to be implemented based on the persistence layer
}
```

---

## 🟡 MEDIUM PRIORITY

### 7. Similarity Settings Re-ranking
**Location**: `Sources/DeduperUI/Views.swift:429-432`

**Current Code**:
```swift
@objc private func similaritySettingsChanged() {
    // TODO: Re-rank groups based on new similarity settings
    print("Similarity settings changed - re-ranking groups")
    loadGroups()
}
```

**Changes Needed**:

**A. In GroupsListViewModel** (implement re-ranking):
```swift
@objc private func similaritySettingsChanged() {
    // Get current settings from SimilarityControlsView
    let newOptions = getCurrentDetectionOptions()

    Task {
        do {
            // Re-run detection with new parameters
            let updatedGroups = try await duplicateEngine.findDuplicates(options: newOptions)

            await MainActor.run {
                // Preserve user selections where possible
                let preservedSelections = selectedKeeper

                groups = updatedGroups
                applyFilters()

                // Restore previous selections if groups still exist
                selectedKeeper = preservedSelections.filter { groupId, _ in
                    groups.contains { $0.id == groupId }
                }
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to re-rank groups: \(error.localizedDescription)"
            }
        }
    }
}

private func getCurrentDetectionOptions() -> DetectOptions {
    // Get current settings from user defaults or similarity controls
    // Implementation depends on how settings are stored
}
```

---

### 8. MergePlanSheet Component
**Location**: `Sources/DeduperUI/Views.swift:632-635`

**Current Code**:
```swift
// TODO: Implement MergePlanSheet component
Text("Merge plan preview coming soon...")
```

**Changes Needed**:

**A. Create new file** `Sources/DeduperUI/MergePlanSheet.swift`:
```swift
public struct MergePlanSheet: View {
    let group: DuplicateGroupResult
    let mergePlan: MergePlan
    @Binding var isPresented: Bool

    public var body: some View {
        VStack {
            Text("Merge Plan Preview")
                .font(DesignToken.fontFamilyTitle)

            ScrollView {
                // Show detailed comparison of what will be kept vs deleted
                ForEach(mergePlan.fieldChanges) { change in
                    FieldComparisonRow(change: change)
                }
            }

            HStack {
                Button("Cancel", action: { isPresented = false })
                Button("Confirm Merge", action: {
                    // Execute merge
                    isPresented = false
                })
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}
```

**B. In GroupDetailView** (integrate the sheet):
```swift
.sheet(isPresented: $showMergePlan) {
    if let plan = viewModel.mergePlan {
        MergePlanSheet(group: group, mergePlan: plan, isPresented: $showMergePlan)
    }
}
```

---

## 🟢 LOW PRIORITY

### 9. History Data Loading
**Location**: `Sources/DeduperUI/HistoryView.swift:204-207`

**Current Code**:
```swift
// TODO: Replace with actual data loading from persistence layer
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
    self.historyItems = [
        // Mock data
    ]
}
```

**Changes Needed**:

**A. In HistoryViewModel** (implement data loading):
```swift
public func loadHistory() async {
    do {
        let historyData = try await historyService.getHistoryItems()

        await MainActor.run {
            self.historyItems = historyData
            self.isLoading = false
        }
    } catch {
        await MainActor.run {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
}
```

**B. In HistoryService** (new service needed):
```swift
// This would be a new service file
public class HistoryService {
    private let persistence: PersistenceController

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    public func getHistoryItems() async throws -> [HistoryItem] {
        let context = persistence.container.viewContext

        let fetchRequest = NSFetchRequest<MergeTransaction>(entityName: "MergeTransaction")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let transactions = try context.fetch(fetchRequest)

        return transactions.map { transaction in
            // Convert transaction to HistoryItem
            HistoryItem(
                id: transaction.id,
                title: "Group \(transaction.groupId.uuidString.prefix(8))",
                description: "Merged \(transaction.removedFileIds.count) duplicates",
                timestamp: transaction.createdAt,
                // ... other fields
            )
        }
    }
}
```

---

## Summary

This document provides explicit implementation details for each TODO, showing:

1. **Exact file locations** where changes need to be made
2. **Specific code snippets** that need to be added or modified
3. **New methods and properties** that need to be created
4. **Integration points** between different components
5. **Dependencies** that need to be implemented first

Each implementation includes both the UI changes needed in the ViewModels and the backend logic needed in the services/engines.
