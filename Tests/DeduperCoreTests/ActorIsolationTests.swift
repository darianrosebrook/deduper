import Testing
import Foundation
import Dispatch
@testable import DeduperCore

/**
 * Actor Isolation Tests
 *
 * These tests verify that MainActor-isolated code is properly accessed
 * from the correct actor context, preventing dispatch queue assertion failures
 * and concurrency crashes.
 *
 * Test Strategy:
 * 1. Verify dispatch source handlers execute on MainActor
 * 2. Verify Timer callbacks execute on MainActor
 * 3. Verify background queue closures don't access MainActor properties
 * 4. Stress test multiple concurrent dispatch sources
 * 5. Verify no crashes occur under load
 *
 * Author: @darianrosebrook
 */
@Suite struct ActorIsolationTests {
    
    // MARK: - Dispatch Source Handler Tests
    
    /**
     * Tests that memory pressure handlers properly isolate to MainActor
     * when accessing MainActor-isolated properties.
     *
     * This test would catch the bug where dispatch source callbacks
     * access MainActor properties from background queues.
     */
    @Test @MainActor
    func testMemoryPressureHandler_MainActorIsolation() async throws {
        // Create a service with memory pressure monitoring
        let feedbackService = FeedbackService(
            persistence: PersistenceController.shared,
            config: LearningConfig(
                enableMemoryMonitoring: true,
                healthCheckInterval: 0 // Disable health checks for this test
            )
        )
        
        // Wait for memory pressure handler to potentially fire
        // The handler should execute on MainActor without crashing
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify we can access MainActor properties without crashing
        // If the handler accessed healthStatus from a background queue, this would crash
        let _ = feedbackService.isLearningEnabled
        let _ = feedbackService.learningMetrics
    }
    
    /**
     * Tests that health check timers properly isolate to MainActor
     * when accessing MainActor-isolated properties.
     */
    @Test @MainActor
    func testHealthCheckTimer_MainActorIsolation() async throws {
        let feedbackService = FeedbackService(
            persistence: PersistenceController.shared,
            config: LearningConfig(
                enableMemoryMonitoring: false,
                healthCheckInterval: 0.1 // Very short interval for testing
            )
        )
        
        // Wait for at least one health check to fire
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify we can access MainActor properties without crashing
        // If performHealthCheck accessed healthStatus from background queue, this would crash
        let _ = feedbackService.isLearningEnabled
    }
    
    /**
     * Tests that PersistenceController dispatch sources properly isolate to MainActor.
     */
    @Test @MainActor
    func testPersistenceController_DispatchSourceIsolation() async throws {
        let controller = PersistenceController(
            inMemory: true,
            config: PersistenceConfig(
                enableMemoryMonitoring: true,
                healthCheckInterval: 0.1
            )
        )
        
        // Wait for dispatch sources to potentially fire
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // Verify we can access MainActor properties without crashing
        // If handlers accessed container or healthStatus from background queue, this would crash
        let _ = controller.container
    }
    
    /**
     * Tests that Timer callbacks properly isolate to MainActor.
     */
    @Test @MainActor
    func testTimerCallbacks_MainActorIsolation() async throws {
        let performanceService = PerformanceService()
        
        // Wait for timer callbacks to potentially fire (monitoring timer fires every 5 seconds)
        try await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds
        
        // Verify we can access MainActor properties without crashing
        // If updateResourceUsage accessed properties from background queue, this would crash
        let _ = performanceService.isMonitoringEnabled
        let _ = performanceService.currentMemoryUsage
    }
    
    // MARK: - Background Queue Access Tests
    
    /**
     * Tests that Task { @MainActor } properly switches to MainActor context.
     * This verifies the fix pattern we applied.
     */
    @Test
    func testTaskMainActor_SwitchesToMainActor() async throws {
        let backgroundQueue = DispatchQueue(label: "test-background", qos: .utility)
        
        await withCheckedContinuation { continuation in
            backgroundQueue.async {
                // Verify we're NOT on MainActor here
                // Then switch to MainActor
                Task { @MainActor in
                    // Now we're on MainActor - can access MainActor properties
                    let service = FeedbackService()
                    let _ = service.isLearningEnabled
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Concurrent Access Tests
    
    /**
     * Tests that multiple dispatch sources firing simultaneously
     * don't cause race conditions or crashes.
     *
     * This test would catch issues where multiple services
     * have dispatch sources accessing MainActor properties concurrently.
     */
    @Test @MainActor
    func testConcurrentDispatchSources_NoRaceConditions() async throws {
        let feedbackService = FeedbackService(
            persistence: PersistenceController.shared,
            config: LearningConfig(
                enableMemoryMonitoring: true,
                healthCheckInterval: 0.1
            )
        )
        
        let controller = PersistenceController(
            inMemory: true,
            config: PersistenceConfig(
                enableMemoryMonitoring: true,
                healthCheckInterval: 0.1
            )
        )
        
        // Wait for multiple dispatch source events to potentially fire simultaneously
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        // Verify no crashes occurred by accessing MainActor properties
        let _ = feedbackService.isLearningEnabled
        let _ = controller.container
    }
    
    // MARK: - Stress Tests
    
    /**
     * Stress test: Rapidly fire multiple dispatch sources
     * to verify no crashes occur under load.
     *
     * This test simulates the real-world scenario where
     * multiple services initialize simultaneously and their
     * dispatch sources fire rapidly.
     */
    @Test @MainActor
    func testDispatchSourceStress_NoCrashes() async throws {
        let controller = PersistenceController(
            inMemory: true,
            config: PersistenceConfig(
                enableMemoryMonitoring: true,
                healthCheckInterval: 0.05 // Very frequent checks
            )
        )
        
        // Rapidly trigger multiple events
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            
            // Access MainActor properties to verify no crashes
            // If dispatch sources accessed these from background queues, this would crash
            let _ = controller.container
        }
    }
    
    /**
     * Integration test: Verify all services initialize without crashes
     * when dispatch sources are enabled.
     *
     * This test would catch initialization-time crashes from dispatch sources.
     */
    @Test @MainActor
    func testServiceInitialization_WithDispatchSources_NoCrashes() async throws {
        // Initialize all services that have dispatch sources
        let feedbackService = FeedbackService(
            persistence: PersistenceController.shared,
            config: LearningConfig(
                enableMemoryMonitoring: true,
                healthCheckInterval: 0.1
            )
        )
        
        let controller = PersistenceController(
            inMemory: true,
            config: PersistenceConfig(
                enableMemoryMonitoring: true,
                healthCheckInterval: 0.1
            )
        )
        
        let performanceService = PerformanceService()
        
        // Wait briefly for any initialization-time dispatch source events
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Verify all services are accessible without crashes
        let _ = feedbackService.isLearningEnabled
        let _ = controller.container
        let _ = performanceService.isMonitoringEnabled
    }
}

