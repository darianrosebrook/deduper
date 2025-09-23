# Test Plan: Safe File Merging Operations

## Unit Tests

### Core Business Logic
- **File: `Sources/DeduperCore/MergeService.swift`**

```typescript
// Property-based tests for file operations safety
it('merge operation preserves keeper file [INV: Keeper file must exist]', () => {
  fc.assert(
    fc.property(groupArb(), keeperIdArb(), (group, keeperId) => {
      const result = mergeService.executeMerge(group, keeperId);
      return result.keeperPreserved && result.duplicatesRemoved;
    })
  );
});

// Edge case: empty group
it('handles empty duplicate groups gracefully', async () => {
  const emptyGroup = { id: uuid(), members: [], keeperSuggestion: null };
  const result = await mergeService.executeMerge(emptyGroup, null);
  expect(result.filesMovedToTrash).toBe(0);
  expect(result.keeperPreserved).toBe(true);
});

// Error path: missing keeper file
it('fails safely when keeper file is inaccessible', async () => {
  const group = createTestGroup();
  const missingKeeperId = uuid();

  await expect(mergeService.executeMerge(group, missingKeeperId))
    .rejects.toThrow('Keeper file not accessible');
});
```

### Persistence Layer
- **File: `Sources/DeduperCore/PersistenceController.swift`**

```typescript
// Transaction atomicity
it('merge transaction is atomic [INV: Merge transactions must be atomic]', async () => {
  const group = await createTestGroup();
  const keeperId = group.members[0].fileId;

  await persistence.transaction(async (context) => {
    const transaction = await mergeService.createMergeTransaction(group, keeperId);
    await persistence.saveMergeTransaction(transaction, context);
    // Simulate failure after partial save
    throw new Error('Simulated failure');
  });

  // Verify no partial state was persisted
  const persistedTransaction = await persistence.getMergeTransaction(group.groupId);
  expect(persistedTransaction).toBeNull();
});

// Undo operation completeness
it('undo operation restores all files [A3]', async () => {
  const transaction = await createCompletedMergeTransaction();
  const filesBeforeUndo = await fileSystem.getFilesInDirectory(testDirectory);

  await mergeService.undoMerge(transaction.id);

  const filesAfterUndo = await fileSystem.getFilesInDirectory(testDirectory);
  expect(filesAfterUndo.length).toBe(filesBeforeUndo.length);
});
```

## Contract Tests

### API Contract Validation
- **File: `contracts/merge-operations.yaml`**

```typescript
// Consumer contract tests
it('conforms to merge preview schema [contract]', async () => {
  const response = await client.previewMerge({
    groupId: 'test-group-id',
    keeperFileId: 'keeper-file-id'
  });

  expect(response).toMatchSchema(MergePreviewResponse);
  expect(response.groupId).toBe('test-group-id');
  expect(response.keeperFile.fileId).toBe('keeper-file-id');
});

// Provider contract tests
it('provides valid merge execution contract [contract]', async () => {
  const mockMergeService = {
    executeMerge: jest.fn().mockResolvedValue({
      transactionId: 'test-transaction',
      groupId: 'test-group',
      keeperFileId: 'keeper-id',
      filesMovedToTrash: ['dup1.jpg', 'dup2.jpg'],
      totalSpaceFreed: 1024,
      undoDeadline: new Date(Date.now() + 24 * 60 * 60 * 1000),
      operationDuration: 150
    })
  };

  const result = await mockMergeService.executeMerge(testRequest);
  expect(result).toMatchSchema(MergeExecuteResponse);
});
```

## Integration Tests

### Database Integration
- **Files: `Tests/DeduperCoreTests/PersistenceControllerTests.swift`**

```typescript
// Test file operation persistence
it('persists merge transaction with file references [A2]', async () => {
  const group = await createTestGroupWithFiles();
  const keeperId = group.members[0].fileId;

  const transaction = await mergeService.createMergeTransaction(group, keeperId);
  await persistenceController.saveMergeTransaction(transaction);

  // Verify transaction persisted correctly
  const persisted = await persistenceController.getMergeTransaction(transaction.id);
  expect(persisted.groupId).toBe(group.groupId);
  expect(persisted.keeperFileId).toBe(keeperId);
  expect(persisted.filesMovedToTrash).toHaveLength(group.members.length - 1);
});

// Test undo persistence
it('persists undo operation results [A3]', async () => {
  const transaction = await createCompletedMergeTransaction();

  await mergeService.undoMerge(transaction.id);

  const updatedTransaction = await persistenceController.getMergeTransaction(transaction.id);
  expect(updatedTransaction.undoneAt).toBeDefined();
  expect(updatedTransaction.undoneAt).toBeInstanceOf(Date);
});
```

### File System Integration
- **Files: `Tests/DeduperCoreTests/FileSystemIntegrationTests.swift`**

```typescript
// Test actual file operations
it('moves duplicate files to trash safely [A2]', async () => {
  const testFiles = await createTestFilesInDirectory(testDirectory, 5);
  const group = createGroupFromFiles(testFiles);
  const keeperId = testFiles[0].id;

  const result = await mergeService.executeMerge(group, keeperId);

  // Verify keeper file remains
  expect(await fileExists(testFiles[0].path)).toBe(true);

  // Verify duplicates moved to trash
  for (let i = 1; i < testFiles.length; i++) {
    expect(await fileExists(testFiles[i].path)).toBe(false);
    expect(await fileExistsInTrash(testFiles[i].name)).toBe(true);
  }

  expect(result.totalSpaceFreed).toBeGreaterThan(0);
});

// Test error recovery
it('rolls back partial operations on failure [A4]', async () => {
  const testFiles = await createTestFilesInDirectory(testDirectory, 3);

  // Simulate failure during merge
  const mockFileSystem = {
    moveToTrash: jest.fn()
      .mockResolvedValueOnce(true) // First file succeeds
      .mockRejectedValueOnce(new Error('Permission denied')) // Second file fails
  };

  await expect(mergeService.executeMerge(group, keeperId, { fileSystem: mockFileSystem }))
    .rejects.toThrow('Permission denied');

  // Verify rollback: all files should be restored
  for (const file of testFiles) {
    expect(await fileExists(file.path)).toBe(true);
  }
});
```

## E2E Smoke Tests

### Critical User Paths
- **File: `Tests/DeduperUITests/MergeOperationsE2ETests.swift`**

```typescript
// Complete merge workflow
test('complete merge workflow [A1,A2]', async ({ page }) => {
  // Navigate to duplicate groups
  await page.goto('/duplicate-groups');

  // Select a group and choose keeper
  await page.getByRole('button', { name: /select keeper/i }).click();
  await page.getByRole('button', { name: /file-1.jpg/i }).click();

  // Preview merge
  await page.getByRole('button', { name: /preview merge/i }).click();
  await expect(page.getByRole('heading', { name: /merge preview/i })).toBeVisible();

  // Verify preview shows correct information
  await expect(page.getByText('Keeper: file-1.jpg')).toBeVisible();
  await expect(page.getByText('Duplicates to remove: 2')).toBeVisible();
  await expect(page.getByText('Space to reclaim: 5.2 MB')).toBeVisible();

  // Execute merge
  await page.getByRole('button', { name: /execute merge/i }).click();

  // Verify merge completed
  await expect(page.getByText('Merge completed successfully')).toBeVisible();
  await expect(page.getByText('3 files moved to trash')).toBeVisible();
  await expect(page.getByText('Undo available for 24 hours')).toBeVisible();
});

// Undo workflow
test('merge undo workflow [A3]', async ({ page }) => {
  // Execute merge first (reuse previous test setup)
  await completeMergeTestSetup(page);

  // Navigate to merge history
  await page.goto('/merge-history');

  // Find recent merge and undo
  await page.getByRole('button', { name: /undo merge/i }).click();
  await page.getByRole('button', { name: /confirm undo/i }).click();

  // Verify undo completed
  await expect(page.getByText('Merge undone successfully')).toBeVisible();
  await expect(page.getByText('All files restored')).toBeVisible();
});
```

## Mutation Testing Requirements

### Tier 1 Requirements (≥70% mutation score)
- All merge operation decision logic
- File system operation error handling
- Transaction rollback logic
- Undo operation validation
- Persistence layer consistency checks

### Edge Cases for Mutation Testing
- Concurrent merge operations on same files
- Network failures during file operations
- Disk space exhaustion scenarios
- Permission denied on keeper files
- Corrupted file system bookmarks

## Test Data Strategy

### Factories and Fixtures
- **File: `Tests/helpers/test-data-factories.swift`**

```typescript
// Generate realistic duplicate groups for testing
export const groupArb = (): DuplicateGroupResult => ({
  groupId: uuid(),
  members: fc.array(fileMemberArb(), { minLength: 2, maxLength: 10 }),
  confidence: fc.float({ min: 0.8, max: 1.0 }),
  rationaleLines: ['Perceptual hash match', 'Name similarity', 'Size match'],
  keeperSuggestion: null,
  incomplete: false,
  mediaType: fc.oneof({ arbitrary: () => MediaType.photo })
});

// Generate file members with realistic metadata
export const fileMemberArb = (): DuplicateGroupMember => ({
  fileId: uuid(),
  fileSize: fc.integer({ min: 1024, max: 10485760 }), // 1KB to 10MB
  confidence: fc.float({ min: 0.5, max: 1.0 }),
  hammingDistance: fc.integer({ min: 0, max: 10 }),
  nameSimilarity: fc.float({ min: 0.8, max: 1.0 }),
  rationale: ['Perceptual hash match']
});
```

## Performance Testing

### Load Testing Scenarios
- **File: `Tests/DeduperCoreTests/MergeServiceLoadTests.swift`**

```typescript
// Large group merge performance
it('handles large duplicate groups efficiently', async () => {
  const largeGroup = createLargeGroup(100); // 100 duplicate files
  const startTime = Date.now();

  const result = await mergeService.executeMerge(largeGroup, largeGroup.members[0].fileId);

  const duration = Date.now() - startTime;
  expect(duration).toBeLessThan(5000); // Should complete within 5 seconds
  expect(result.operationDuration).toBeLessThan(3000);
});

// Concurrent merge operations
it('handles concurrent merge operations safely', async () => {
  const groups = await Promise.all([
    createTestGroup(),
    createTestGroup(),
    createTestGroup()
  ]);

  const results = await Promise.allSettled(
    groups.map(group => mergeService.executeMerge(group, group.members[0].fileId))
  );

  // All operations should succeed without conflicts
  expect(results.every(r => r.status === 'fulfilled')).toBe(true);
});
```

## Flake Control Strategy

### Deterministic Test Setup
- Use fixed timestamps for file creation/modification
- Mock file system operations with predictable results
- Use seeded random generators for consistent test data
- Isolate file system dependencies with test doubles

### Test Quarantine Policy
- Any test with >0.5% flake rate auto-quarantined
- Quarantined tests must have owner + 7-day expiry
- Flake analysis runs nightly with historical comparison
- Retry policy: 0 retries (fail immediately to detect flakes)

This test plan ensures comprehensive coverage of the merge functionality while maintaining the safety invariants required for file operations.
