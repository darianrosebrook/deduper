# Mutation Testing Setup Guide

**Author:** @darianrosebrook

## Overview

Mutation testing validates test quality by introducing small changes (mutations) to code and verifying that tests catch these changes. A high mutation score indicates strong test coverage.

## Swift Mutation Testing Tools

### Available Options

1. **Mull** (C/C++/Objective-C/Swift)
   - LLVM-based mutation testing
   - Supports Swift via LLVM IR
   - Requires compilation to bitcode
   - GitHub: https://github.com/mull-project/mull

2. **Custom Framework**
   - Build mutation operators manually
   - Use Swift AST manipulation
   - Integrate with Swift Testing framework

3. **Manual Mutation Analysis**
   - Systematic code review
   - Targeted test improvements
   - Coverage-guided mutation

## Recommended Approach

For Deduper project, we recommend a **hybrid approach**:

1. **Manual Mutation Analysis** for critical components
2. **Custom Mutation Scripts** for common patterns
3. **Coverage-Guided Testing** to identify weak test areas

## Target Components

### Tier 1 (Critical - 70%+ mutation score required)

- `DuplicateDetectionEngine` - Core duplicate detection logic
- `MergeService` - Merge operations and data integrity
- `ConfidenceCalculator` - Confidence scoring algorithms

### Tier 2 (Standard - 50%+ mutation score required)

- `MetadataExtractionService` - Metadata parsing
- `PersistenceController` - Data persistence
- `VideoFingerprinter` - Video comparison logic

### Tier 3 (Low Risk - 30%+ mutation score required)

- UI components
- Utility functions
- Helper classes

## Mutation Operators

### Arithmetic Operators

- `+` → `-`, `*`, `/`
- `-` → `+`, `*`, `/`
- `*` → `+`, `-`, `/`
- `/` → `+`, `-`, `*`

### Comparison Operators

- `==` → `!=`, `<`, `>`
- `!=` → `==`, `<=`, `>=`
- `<` → `<=`, `>`, `>=`
- `>` → `>=`, `<`, `<=`

### Logical Operators

- `&&` → `||`, `!`
- `||` → `&&`, `!`
- `!` → Remove negation

### Conditional Boundaries

- `if condition` → `if !condition`
- `if x > threshold` → `if x >= threshold`, `if x < threshold`

### Return Statements

- `return value` → `return nil`, `return defaultValue`
- Missing return → Add return

## Implementation Strategy

### Phase 1: Manual Analysis

1. Identify critical functions
2. Manually introduce mutations
3. Run tests to verify detection
4. Improve tests for surviving mutants

### Phase 2: Automated Scripts

1. Create mutation scripts for common patterns
2. Run mutations on critical components
3. Analyze results
4. Improve test coverage

### Phase 3: CI/CD Integration

1. Integrate mutation testing into CI pipeline
2. Set mutation score thresholds
3. Block merges below thresholds
4. Track mutation score trends

## Mutation Score Calculation

```
Mutation Score = (Killed Mutants / Total Mutants) * 100

Where:
- Killed Mutants = Mutations that cause test failures
- Surviving Mutants = Mutations that don't cause test failures (weak tests)
```

## Example Mutation Test

```swift
// Original code
func calculateConfidence(signal: ConfidenceSignal) -> Double {
    return signal.weight * signal.rawScore
}

// Mutation 1: Change operator
func calculateConfidence(signal: ConfidenceSignal) -> Double {
    return signal.weight + signal.rawScore  // Should fail test
}

// Mutation 2: Change return value
func calculateConfidence(signal: ConfidenceSignal) -> Double {
    return 0.0  // Should fail test
}

// Good test should catch both mutations
@Test func testCalculateConfidence() {
    let signal = ConfidenceSignal(
        key: "test",
        weight: 0.5,
        rawScore: 0.8,
        contribution: 0.0,
        rationale: "test"
    )
    let result = calculateConfidence(signal: signal)
    #expect(result == 0.4)  // 0.5 * 0.8 = 0.4
}
```

## Next Steps

1. Evaluate Mull framework for Swift compatibility
2. Create custom mutation scripts for critical components
3. Run mutation analysis on Tier 1 components
4. Improve tests to achieve target mutation scores
5. Integrate into CI/CD pipeline

## References

- Mull Project: https://github.com/mull-project/mull
- Mutation Testing Best Practices: Industry standards for mutation testing
- Swift Testing Framework: https://github.com/apple/swift-testing

