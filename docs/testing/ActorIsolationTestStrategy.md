# Actor Isolation Test Strategy

## Overview

This document outlines the test strategy for catching concurrency bugs related to actor isolation, specifically dispatch source handlers accessing MainActor-isolated properties from background queues.

## Types of Tests Needed

### 1. **Actor Isolation Tests** ✅ (Created: `ActorIsolationTests.swift`)

**Purpose**: Verify that MainActor-isolated code is properly accessed from the correct actor context.

**What They Catch**:
- Dispatch source handlers accessing MainActor properties from background queues
- Timer callbacks accessing MainActor properties without proper isolation
- Background queue closures directly accessing MainActor properties

**Key Tests**:
- `testMemoryPressureHandler_MainActorIsolation()` - Verifies memory pressure handlers execute on MainActor
- `testHealthCheckTimer_MainActorIsolation()` - Verifies health check timers execute on MainActor
- `testTimerCallbacks_MainActorIsolation()` - Verifies Timer callbacks execute on MainActor
- `testTaskMainActor_SwitchesToMainActor()` - Verifies Task { @MainActor } pattern works correctly

### 2. **Integration Tests with Dispatch Sources**

**Purpose**: Verify that services initialize and run with dispatch sources enabled without crashing.

**What They Catch**:
- Initialization-time crashes from dispatch sources
- Runtime crashes when dispatch sources fire
- Race conditions between multiple dispatch sources

**Example Test**:
```swift
@Test @MainActor
func testServiceInitialization_WithDispatchSources_NoCrashes() async throws {
    // Initialize services with dispatch sources enabled
    let service = FeedbackService(config: LearningConfig(enableMemoryMonitoring: true))
    
    // Wait for dispatch sources to potentially fire
    try await Task.sleep(nanoseconds: 200_000_000)
    
    // Verify no crashes occurred
    let _ = service.isLearningEnabled
}
```

### 3. **Concurrency Stress Tests**

**Purpose**: Verify that multiple concurrent dispatch sources don't cause crashes or race conditions.

**What They Catch**:
- Multiple dispatch sources firing simultaneously
- Race conditions when accessing shared MainActor properties
- Thread safety issues under load

**Example Test**:
```swift
@Test @MainActor
func testConcurrentDispatchSources_NoRaceConditions() async throws {
    // Initialize multiple services with dispatch sources
    let services = [FeedbackService(...), PersistenceController(...)]
    
    // Wait for concurrent events
    try await Task.sleep(nanoseconds: 300_000_000)
    
    // Verify no crashes
    for service in services {
        // Access MainActor properties
    }
}
```

### 4. **Static Analysis / Compile-Time Checks**

**Purpose**: Catch actor isolation violations at compile time.

**What They Catch**:
- Direct access to MainActor properties from non-MainActor contexts
- Missing `@MainActor` annotations on Task closures
- Incorrect actor isolation annotations

**Tools**:
- Swift compiler warnings/errors (already catches many issues)
- SwiftLint rules for actor isolation
- Custom static analysis scripts

**Example Rule**:
```swift
// This should fail to compile:
DispatchQueue.global().async {
    let service = FeedbackService() // Error: MainActor-isolated initializer
}
```

### 5. **Runtime Assertion Tests**

**Purpose**: Verify that dispatch queue assertions don't fail at runtime.

**What They Catch**:
- Dispatch queue assertion failures (`_dispatch_assert_queue_fail`)
- Incorrect actor context when accessing MainActor properties
- Thread safety violations

**Implementation**:
- Use `XCTAssertNoThrow` or similar to verify no crashes
- Monitor for specific crash signatures
- Use crash reporting tools to detect dispatch queue assertion failures

### 6. **Property Access Pattern Tests**

**Purpose**: Verify that MainActor-isolated properties are only accessed from MainActor context.

**What They Catch**:
- Direct property access from background queues
- Missing `Task { @MainActor }` wrappers
- Incorrect use of `await MainActor.run`

**Example Test**:
```swift
@Test
func testPropertyAccess_RequiresMainActor() async throws {
    let backgroundQueue = DispatchQueue(label: "test", qos: .utility)
    
    await withCheckedContinuation { continuation in
        backgroundQueue.async {
            // This should NOT compile if accessing MainActor properties directly
            Task { @MainActor in
                // This SHOULD work - we're on MainActor
                let service = FeedbackService()
                let _ = service.isLearningEnabled
                continuation.resume()
            }
        }
    }
}
```

## Test Coverage Requirements

### Critical Services (Must Have Tests)

1. **FeedbackService** ✅
   - Memory pressure handler
   - Health check timer
   - Metrics collection timer
   - Security event logging

2. **PersistenceController** ✅
   - Memory pressure handler
   - Health check timer
   - Metrics export
   - Security event logging

3. **PerformanceService** ✅
   - Resource monitoring timer
   - Metrics update timer

### Recommended Services (Should Have Tests)

4. **ScanService**
   - Memory pressure handler
   - Health check timer

5. **MetadataExtractionService**
   - Memory pressure handler
   - Health check timer

6. **VideoFingerprinter**
   - Memory pressure handler
   - Health check timer

7. **ThumbnailService**
   - Health check timer

## Test Execution Strategy

### Pre-Commit Hooks

Run actor isolation tests before every commit:
```bash
swift test --filter ActorIsolationTests
```

### CI/CD Integration

1. **Fast Feedback**: Run actor isolation tests on every PR
2. **Comprehensive**: Run all concurrency tests before merge
3. **Stress Tests**: Run stress tests nightly

### Test Categories

1. **Unit Tests** (Fast, < 1 second)
   - Actor isolation verification
   - Property access pattern tests

2. **Integration Tests** (Medium, 1-5 seconds)
   - Service initialization with dispatch sources
   - Concurrent dispatch source tests

3. **Stress Tests** (Slow, 5-30 seconds)
   - Multiple concurrent services
   - Rapid dispatch source firing
   - Long-running stability tests

## Detection Methods

### 1. Compile-Time Detection ✅

Swift compiler already catches many issues:
```swift
// Error: Main actor-isolated property 'healthStatus' can not be referenced from a nonisolated autoclosure
```

### 2. Runtime Detection ✅

Dispatch queue assertions catch violations:
```
_dispatch_assert_queue_fail + 120 in libdispatch.dylib
```

### 3. Test-Based Detection ✅

Tests verify correct behavior:
- No crashes when dispatch sources fire
- Properties accessible after dispatch source events
- Concurrent access doesn't cause issues

### 4. Static Analysis (Future)

Potential SwiftLint rules:
- Detect `DispatchSource.setEventHandler` without `Task { @MainActor }`
- Detect `Timer.scheduledTimer` callbacks without `@MainActor`
- Detect `DispatchQueue.async` accessing MainActor properties

## Best Practices

### ✅ Correct Pattern

```swift
// Dispatch source handler
memoryPressureSource?.setEventHandler { [weak self] in
    Task { @MainActor [weak self] in
        self?.handleMemoryPressureEvent()
    }
}

// Timer callback
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
    Task { @MainActor [weak self] in
        self?.updateResourceUsage()
    }
}

// Background queue closure
backgroundQueue.async { [weak self] in
    Task { @MainActor [weak self] in
        self?.updateProperty()
    }
}
```

### ❌ Incorrect Pattern

```swift
// BAD: Direct access from dispatch source handler
memoryPressureSource?.setEventHandler { [weak self] in
    self?.healthStatus = .memoryPressure(0.5) // CRASH!
}

// BAD: Direct access from Timer callback
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
    self?.currentMemoryUsage = 1000 // CRASH!
}

// BAD: Direct access from background queue
backgroundQueue.async { [weak self] in
    self?.securityEvents.append(event) // CRASH!
}
```

## Implementation Status

- ✅ **ActorIsolationTests.swift** - Created with comprehensive test coverage
- ✅ **FeedbackService** - All dispatch sources fixed
- ✅ **PersistenceController** - All dispatch sources fixed
- ✅ **PerformanceService** - All timers fixed
- ⚠️ **ScanService** - Needs tests (not MainActor, but should verify thread safety)
- ⚠️ **MetadataExtractionService** - Needs tests (not MainActor, but should verify thread safety)
- ⚠️ **VideoFingerprinter** - Needs tests (not MainActor, but should verify thread safety)
- ⚠️ **ThumbnailService** - Needs tests (not MainActor, but should verify thread safety)

## Next Steps

1. **Run ActorIsolationTests** to verify current fixes work
2. **Add tests for non-MainActor services** to verify thread safety
3. **Create SwiftLint rules** for static analysis
4. **Add pre-commit hooks** to run actor isolation tests
5. **Document patterns** in code review guidelines

## References

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [MainActor Isolation](https://developer.apple.com/documentation/swift/mainactor)
- [Dispatch Sources](https://developer.apple.com/documentation/dispatch/dispatchsource)

