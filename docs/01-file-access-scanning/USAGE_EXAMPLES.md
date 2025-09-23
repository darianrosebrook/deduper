# File Access & Scanning - Usage Examples

## Overview

This document provides comprehensive examples of how to use the enhanced File Access & Scanning module with its new performance optimization, security, and monitoring capabilities.

## 🚀 Basic Usage Examples

### 1. Simple Directory Scanning

```swift
import DeduperCore

// Basic scanning with default settings
let persistenceController = PersistenceController(inMemory: true)
let scanService = ScanService(persistenceController: persistenceController)

let urls = [URL(fileURLWithPath: "/Users/username/Pictures")]
let stream = await scanService.enumerate(urls: urls)

for await event in stream {
    switch event {
    case .started(let url):
        print("Started scanning: \(url.path)")
    case .progress(let count):
        print("Progress: \(count) files processed")
    case .item(let file):
        print("Found media file: \(file.url.lastPathComponent)")
    case .finished(let metrics):
        print("Completed! Found \(metrics.mediaFiles) files in \(String(format: "%.2f", metrics.duration))s")
    }
}
```

### 2. Advanced Scanning with Custom Options

```swift
// Advanced scanning with custom configuration
let options = ScanOptions(
    excludes: [
        ExcludeRule(.pathContains("cache"), description: "Cache directories"),
        ExcludeRule(.pathSuffix(".tmp"), description: "Temporary files")
    ],
    followSymlinks: false,
    concurrency: 4,
    incremental: true,
    incrementalLookbackHours: 24.0
)

let stream = await scanService.enumerate(urls: urls, options: options)
```

## 🔧 Performance Configuration Examples

### 1. High-Performance Configuration

```swift
// Optimized for maximum throughput
let highPerformanceConfig = ScanService.ScanConfig(
    enableMemoryMonitoring: true,        // Monitor system resources
    enableAdaptiveConcurrency: true,     // Scale with system load
    enableParallelProcessing: true,      // Maximum throughput
    maxConcurrency: ProcessInfo.processInfo.activeProcessorCount,
    memoryPressureThreshold: 0.8,        // Conservative memory usage
    healthCheckInterval: 30.0            // Regular health monitoring
)

let scanService = ScanService(
    persistenceController: persistenceController,
    config: highPerformanceConfig
)
```

### 2. Memory-Constrained Environment Configuration

```swift
// Optimized for memory-constrained systems
let memoryConstrainedConfig = ScanService.ScanConfig(
    enableMemoryMonitoring: true,
    enableAdaptiveConcurrency: true,     // Important for memory management
    enableParallelProcessing: false,     // Disable to reduce memory usage
    maxConcurrency: 2,                   // Lower concurrency
    memoryPressureThreshold: 0.6,        // More aggressive memory management
    healthCheckInterval: 10.0            // More frequent monitoring
)

let scanService = ScanService(config: memoryConstrainedConfig)
```

### 3. Development/Testing Configuration

```swift
// Optimized for development and debugging
let devConfig = ScanService.ScanConfig(
    enableMemoryMonitoring: true,
    enableAdaptiveConcurrency: false,    // Fixed concurrency for debugging
    enableParallelProcessing: true,
    maxConcurrency: 2,                   // Limited for development
    memoryPressureThreshold: 0.9,        // High threshold for development
    healthCheckInterval: 5.0             // Frequent monitoring for debugging
)

let scanService = ScanService(config: devConfig)
```

## 📊 Real-time Monitoring Examples

### 1. Performance Monitoring

```swift
// Monitor scan performance in real-time
let scanService = ScanService(persistenceController: persistenceController)

let urls = [URL(fileURLWithPath: "/Users/username/Pictures")]
let stream = await scanService.enumerate(urls: urls)

// Monitor performance metrics
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
    let memoryPressure = scanService.getCurrentMemoryPressure()
    let concurrency = scanService.getCurrentConcurrency()
    let healthStatus = scanService.getHealthStatus()

    print("Memory Pressure: \(String(format: "%.2f", memoryPressure))")
    print("Current Concurrency: \(concurrency)")
    print("Health Status: \(healthStatus)")

    // Adjust configuration based on performance
    if memoryPressure > 0.7 {
        let newConfig = scanService.getConfig()
        scanService.updateConfig(ScanService.ScanConfig(
            enableMemoryMonitoring: newConfig.enableMemoryMonitoring,
            enableAdaptiveConcurrency: newConfig.enableAdaptiveConcurrency,
            enableParallelProcessing: false, // Reduce memory usage
            maxConcurrency: max(1, newConfig.maxConcurrency - 1),
            memoryPressureThreshold: newConfig.memoryPressureThreshold,
            healthCheckInterval: newConfig.healthCheckInterval
        ))
        print("Reduced concurrency due to memory pressure")
    }
}

// Process scan results
for await event in stream {
    switch event {
    case .item(let file):
        // Process discovered files
        print("Processing: \(file.url.path)")
    case .finished(let metrics):
        print("Scan completed in \(metrics.duration) seconds")
        timer.invalidate()
    }
}
```

### 2. Health Status Monitoring

```swift
// Monitor scan health and respond to issues
let scanService = ScanService(persistenceController: persistenceController)

let urls = [URL(fileURLWithPath: "/Users/username/Pictures")]
let stream = await scanService.enumerate(urls: urls)

for await event in stream {
    switch event {
    case .started(let url):
        print("Started: \(url.path)")

        // Start health monitoring
        let healthTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { timer in
            let healthStatus = scanService.getHealthStatus()

            switch healthStatus {
            case .healthy:
                print("✓ Scan operating normally")
            case .memoryPressure(let pressure):
                print("⚠️ High memory usage: \(String(format: "%.2f", pressure))")
                // Could trigger memory cleanup or reduce concurrency
            case .slowProgress(let rate):
                print("⚠️ Slow progress: \(String(format: "%.1f", rate)) files/sec")
                // Could increase concurrency or check for I/O issues
            case .highErrorRate(let rate):
                print("⚠️ High error rate: \(String(format: "%.2f", rate))")
                // Could validate scan configuration or check disk health
            case .stalled:
                print("❌ Scan operation stalled!")
                // Emergency intervention required
            }
        }

    case .finished(let metrics):
        healthTimer.invalidate()
        print("Scan completed successfully")
    }
}
```

## 🔒 Security Usage Examples

### 1. Bookmark Management with Security

```swift
// Secure bookmark management with audit trails
let bookmarkManager = BookmarkManager()

do {
    // Create a secure bookmark
    let bookmark = try bookmarkManager.save(
        folderURL: URL(fileURLWithPath: "/Users/username/Pictures"),
        name: "My Pictures"
    )

    // Verify bookmark security
    let isValid = bookmark.isSecurityHashValid()
    print("Bookmark security hash valid: \(isValid)")

    // Get security status
    let (isSecureMode, violationCount, lastCheck) = bookmarkManager.getSecurityStatus()
    print("Secure mode: \(isSecureMode), Violations: \(violationCount)")

    // Get security health score
    let securityScore = bookmarkManager.getSecurityHealthScore()
    print("Security health score: \(String(format: "%.2f", securityScore))")

    // Access security event audit trail
    let securityEvents = bookmarkManager.getSecurityEvents()
    print("Recent security events: \(securityEvents.count)")

    for event in securityEvents.suffix(5) { // Show last 5 events
        print("[\(event.severity.rawValue.uppercased())] \(event.event.rawValue): \(event.details ?? "")")
    }

} catch {
    print("Failed to create bookmark: \(error.localizedDescription)")
}
```

### 2. Security Monitoring and Response

```swift
// Comprehensive security monitoring
let bookmarkManager = BookmarkManager()
let scanService = ScanService(persistenceController: persistenceController)

// Security monitoring loop
let securityTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { timer in
    // Check security health
    let securityScore = bookmarkManager.getSecurityHealthScore()
    let (isSecureMode, violationCount, lastCheck) = bookmarkManager.getSecurityStatus()

    print("Security Score: \(String(format: "%.2f", securityScore))")
    print("Secure Mode: \(isSecureMode)")
    print("Violations: \(violationCount)")

    if securityScore < 0.7 {
        print("⚠️ Security health degraded - consider security reset")

        // Get recent security events for analysis
        let recentEvents = bookmarkManager.getSecurityEvents().suffix(10)
        let criticalEvents = recentEvents.filter { $0.severity == .critical || $0.severity == .error }

        if criticalEvents.count > 3 {
            print("🚨 Multiple critical security events detected!")
            print("Consider running: bookmarkManager.forceSecurityReset()")
        }
    }

    // Check scan service health
    let scanHealth = scanService.getHealthStatus()
    if case .memoryPressure(let pressure) = scanHealth, pressure > 0.8 {
        print("⚠️ High memory pressure in scan service")
    }
}

// Perform security validation
let isSecure = bookmarkManager.performManualSecurityCheck()
print("Security validation passed: \(isSecure)")

// In case of security incidents
if bookmarkManager.getSecurityStatus().0 { // isSecureMode
    print("System is in secure mode - enhanced monitoring active")

    // Force security reset if needed
    bookmarkManager.forceSecurityReset()
    print("Security reset performed - all access revoked")
}
```

## 📈 Metrics and Observability Examples

### 1. Prometheus Metrics Integration

```swift
// Export metrics for Prometheus monitoring
let scanService = ScanService(persistenceController: persistenceController)

let prometheusMetrics = scanService.exportMetrics(format: "prometheus")
print("Prometheus Metrics:")
print(prometheusMetrics)

// Example output:
// # HELP deduper_scan_files_processed Total files processed
// # TYPE deduper_scan_files_processed counter
// deduper_scan_files_processed 1250
//
// # HELP deduper_scan_memory_pressure Current memory pressure
// # TYPE deduper_scan_memory_pressure gauge
// deduper_scan_memory_pressure 0.45
//
// # HELP deduper_scan_current_concurrency Current concurrency level
// # TYPE deduper_scan_current_concurrency gauge
// deduper_scan_current_concurrency 4

// For production monitoring, you would send this to a Prometheus pushgateway
// or expose it via HTTP endpoint
func sendToMonitoringSystem(_ metrics: String) {
    // Implementation would depend on your monitoring infrastructure
    // e.g., HTTP POST to Prometheus pushgateway, write to file, etc.
}
```

### 2. JSON Metrics for Custom Dashboards

```swift
// Export metrics as JSON for custom dashboards
let scanService = ScanService(persistenceController: persistenceController)

let jsonMetrics = scanService.exportMetrics(format: "json")
print("JSON Metrics:")
print(jsonMetrics)

// Example output:
// {
//   "files_processed": 1250,
//   "memory_pressure": 0.45,
//   "current_concurrency": 4,
//   "health_status": "healthy",
//   "config": {
//     "max_concurrency": 8,
//     "memory_monitoring_enabled": true,
//     "adaptive_concurrency_enabled": true,
//     "parallel_processing_enabled": true
//   }
// }

// Parse and use in custom monitoring dashboards
if let jsonData = jsonMetrics.data(using: .utf8),
   let metricsDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

    let filesProcessed = metricsDict["files_processed"] as? Int ?? 0
    let memoryPressure = metricsDict["memory_pressure"] as? Double ?? 0.0
    let healthStatus = metricsDict["health_status"] as? String ?? "unknown"

    // Update your custom dashboard
    updateDashboard(filesProcessed: filesProcessed,
                   memoryPressure: memoryPressure,
                   healthStatus: healthStatus)
}
```

### 3. Real-time Metrics Streaming

```swift
// Stream metrics for real-time monitoring
let scanService = ScanService(persistenceController: persistenceController)

let urls = [URL(fileURLWithPath: "/Users/username/Pictures")]
let stream = await scanService.enumerate(urls: urls)

// Metrics streaming for real-time dashboards
let metricsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
    let metrics = scanService.exportMetrics(format: "json")

    // Send to real-time dashboard (WebSocket, Server-Sent Events, etc.)
    sendToRealtimeDashboard(metrics)

    // Check for performance issues
    if let jsonData = metrics.data(using: .utf8),
       let metricsDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

        let memoryPressure = metricsDict["memory_pressure"] as? Double ?? 0.0
        let healthStatus = metricsDict["health_status"] as? String ?? "unknown"

        if memoryPressure > 0.8 {
            print("🚨 High memory pressure detected!")
        }

        if healthStatus != "healthy" {
            print("⚠️ Scan health issue: \(healthStatus)")
        }
    }
}

for await event in stream {
    switch event {
    case .finished(let metrics):
        metricsTimer.invalidate()
        print("Scan completed in \(metrics.duration) seconds")
    case .error(let path, let reason):
        print("Error in \(path): \(reason)")
    }
}
```

## 🏗️ Advanced Configuration Examples

### 1. Dynamic Configuration Based on Environment

```swift
// Detect environment and configure accordingly
func createOptimalScanService() -> ScanService {
    let memoryMB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
    let cpuCount = ProcessInfo.processInfo.activeProcessorCount

    let config = if memoryMB < 4096 { // Less than 4GB RAM
        // Memory-constrained configuration
        ScanService.ScanConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveConcurrency: true,
            enableParallelProcessing: memoryMB > 2048, // Enable parallel on >2GB systems
            maxConcurrency: min(2, cpuCount),
            memoryPressureThreshold: 0.6, // More aggressive memory management
            healthCheckInterval: 10.0
        )
    } else if memoryMB < 8192 { // 4-8GB RAM
        // Balanced configuration
        ScanService.ScanConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveConcurrency: true,
            enableParallelProcessing: true,
            maxConcurrency: min(4, cpuCount),
            memoryPressureThreshold: 0.8,
            healthCheckInterval: 30.0
        )
    } else { // 8GB+ RAM
        // High-performance configuration
        ScanService.ScanConfig(
            enableMemoryMonitoring: true,
            enableAdaptiveConcurrency: true,
            enableParallelProcessing: true,
            maxConcurrency: cpuCount,
            memoryPressureThreshold: 0.9,
            healthCheckInterval: 60.0
        )
    }

    return ScanService(persistenceController: PersistenceController(), config: config)
}
```

### 2. Adaptive Scanning Strategy

```swift
// Implement adaptive scanning based on directory characteristics
func scanWithAdaptiveStrategy(_ urls: [URL]) async {
    let scanService = createOptimalScanService()

    for url in urls {
        // Analyze directory before scanning
        let fileManager = FileManager.default
        let properties = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = properties?.isDirectory ?? false

        if !isDirectory {
            continue // Skip non-directories
        }

        // Count items in directory for strategy selection
        let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [])
        let itemCount = contents?.count ?? 0

        let options = if itemCount < 100 {
            // Small directory - use simple scanning
            ScanOptions(concurrency: 1, incremental: true)
        } else if itemCount < 1000 {
            // Medium directory - moderate parallelization
            ScanOptions(concurrency: 2, incremental: true)
        } else {
            // Large directory - full parallelization
            ScanOptions(concurrency: 4, incremental: false)
        }

        print("Scanning \(url.path) with \(itemCount) items using concurrency: \(options.concurrency)")

        let stream = await scanService.enumerate(urls: [url], options: options)

        for await event in stream {
            switch event {
            case .item(let file):
                // Process file
                print("Found: \(file.url.lastPathComponent)")
            case .finished(let metrics):
                print("Completed \(url.path): \(metrics.mediaFiles) files in \(metrics.duration)s")
            }
        }
    }
}
```

## 🛠️ Error Handling and Recovery Examples

### 1. Comprehensive Error Handling

```swift
// Robust error handling with recovery strategies
func scanWithErrorRecovery(_ urls: [URL]) async {
    let scanService = ScanService(persistenceController: PersistenceController())

    for url in urls {
        do {
            let stream = await scanService.enumerate(urls: [url])

            for await event in stream {
                switch event {
                case .started(let url):
                    print("Started: \(url.path)")
                case .item(let file):
                    print("Processing: \(file.url.path)")
                case .error(let path, let reason):
                    print("Error in \(path): \(reason)")
                    await handleScanError(path: path, reason: reason)
                case .finished(let metrics):
                    print("Completed successfully: \(metrics.mediaFiles) files")
                }
            }
        } catch {
            print("Failed to start scan for \(url.path): \(error.localizedDescription)")
            await handleScanError(path: url.path, reason: error.localizedDescription)
        }
    }
}

func handleScanError(path: String, reason: String) async {
    print("Handling error for: \(path)")
    print("Reason: \(reason)")

    // Implement recovery strategies based on error type
    if reason.contains("permission") {
        print("Permission error - checking security status")
        let bookmarkManager = BookmarkManager()
        let securityScore = bookmarkManager.getSecurityHealthScore()

        if securityScore < 0.5 {
            print("Low security score - performing security reset")
            bookmarkManager.forceSecurityReset()
        }
    } else if reason.contains("memory") {
        print("Memory error - reducing concurrency")
        let scanService = ScanService(persistenceController: PersistenceController())
        let config = scanService.getConfig()
        let newConfig = ScanService.ScanConfig(
            enableMemoryMonitoring: config.enableMemoryMonitoring,
            enableAdaptiveConcurrency: config.enableAdaptiveConcurrency,
            enableParallelProcessing: false, // Disable parallel processing
            maxConcurrency: max(1, config.maxConcurrency - 1), // Reduce concurrency
            memoryPressureThreshold: config.memoryPressureThreshold,
            healthCheckInterval: config.healthCheckInterval
        )
        scanService.updateConfig(newConfig)
    }
}
```

### 2. Security Incident Response

```swift
// Handle security incidents with automatic response
func handleSecurityIncident(_ incident: BookmarkManager.SecurityEventRecord) async {
    print("Security incident detected: \(incident.event.rawValue)")
    print("Severity: \(incident.severity.rawValue)")
    print("Details: \(incident.details ?? "No details")")

    let bookmarkManager = BookmarkManager()

    switch incident.event {
    case .securityScopeViolation:
        print("Security scope violation - entering secure mode")
        // System automatically enters secure mode, but we can add additional response
        await sendSecurityAlert("Critical security violation detected")

    case .bookmarkStale:
        print("Stale bookmark detected - performing cleanup")
        let _ = bookmarkManager.performManualSecurityCheck()

    case .accessDenied:
        print("Access denied - checking security status")
        let (isSecureMode, violationCount, _) = bookmarkManager.getSecurityStatus()
        if violationCount > 5 {
            print("Multiple access denials - potential security issue")
            await sendSecurityAlert("Multiple access denials detected")
        }

    case .bookmarkRemoved:
        print("Bookmark removed - checking for patterns")
        let recentEvents = bookmarkManager.getSecurityEvents().suffix(10)
        let removalEvents = recentEvents.filter { $0.event == .bookmarkRemoved }

        if removalEvents.count > 3 {
            print("Multiple bookmark removals detected")
            await sendSecurityAlert("Suspicious bookmark removal pattern")
        }
    }
}

func sendSecurityAlert(_ message: String) async {
    // Implementation would depend on your alerting system
    // e.g., send email, Slack notification, PagerDuty alert, etc.
    print("SECURITY ALERT: \(message)")
}
```

## 🎯 Best Practices Examples

### 1. Production-Ready Scanning Pipeline

```swift
// Complete production-ready scanning pipeline
func productionScanPipeline(_ urls: [URL]) async throws {
    // 1. Pre-flight checks
    await performPreflightChecks(urls)

    // 2. Initialize services with optimal configuration
    let persistenceController = PersistenceController()
    let scanService = await createProductionScanService()

    // 3. Set up monitoring and alerting
    let monitoringTask = Task {
        await monitorScanHealth(scanService)
    }

    defer {
        monitoringTask.cancel()
    }

    // 4. Perform the scan with error handling
    let scanTask = Task {
        try await performSecureScan(scanService, urls)
    }

    // 5. Handle results
    do {
        let metrics = try await scanTask.value
        await processScanResults(metrics)
        await logSuccessMetrics(metrics)
    } catch {
        await handleScanFailure(error)
        throw error
    }
}

func performPreflightChecks(_ urls: [URL]) async {
    print("Performing pre-flight checks...")

    for url in urls {
        // Check if directory exists
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: nil) else {
            throw ScanError.directoryNotFound(url)
        }

        // Check if directory is accessible
        let bookmarkManager = BookmarkManager()
        let validationResult = bookmarkManager.validateAccess(url)
        if case .failure(let error) = validationResult {
            throw ScanError.accessDenied(url, error.localizedDescription)
        }

        print("✓ \(url.path) is accessible")
    }
}

func createProductionScanService() async -> ScanService {
    let config = ScanService.ScanConfig(
        enableMemoryMonitoring: true,
        enableAdaptiveConcurrency: true,
        enableParallelProcessing: true,
        maxConcurrency: ProcessInfo.processInfo.activeProcessorCount,
        memoryPressureThreshold: 0.8,
        healthCheckInterval: 30.0
    )

    return ScanService(persistenceController: PersistenceController(), config: config)
}

func monitorScanHealth(_ scanService: ScanService) async {
    let healthTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { timer in
        let healthStatus = scanService.getHealthStatus()
        let memoryPressure = scanService.getCurrentMemoryPressure()

        switch healthStatus {
        case .healthy:
            print("✓ Scan health: Normal")
        case .memoryPressure(let pressure):
            print("⚠️ Memory pressure: \(String(format: "%.2f", pressure))")
        case .slowProgress(let rate):
            print("⚠️ Slow progress: \(String(format: "%.1f", rate)) files/sec")
        case .stalled:
            print("❌ Scan stalled!")
        case .highErrorRate(let rate):
            print("⚠️ High error rate: \(String(format: "%.2f", rate))")
        }
    }

    // Keep monitoring until cancelled
    try? await Task.sleep(nanoseconds: UInt64(1e12)) // 1000 seconds
    healthTimer.invalidate()
}
```

### 2. Secure Bookmark Management Workflow

```swift
// Complete secure bookmark management workflow
func secureBookmarkWorkflow(_ urls: [URL]) async throws {
    let bookmarkManager = BookmarkManager()

    // 1. Security assessment
    let securityScore = bookmarkManager.getSecurityHealthScore()
    print("Initial security score: \(String(format: "%.2f", securityScore))")

    if securityScore < 0.7 {
        print("⚠️ Low security score - performing security check")
        let isSecure = bookmarkManager.performManualSecurityCheck()
        if !isSecure {
            print("❌ Security check failed - aborting operation")
            return
        }
    }

    // 2. Create secure bookmarks
    var bookmarks: [BookmarkManager.BookmarkRef] = []

    for url in urls {
        do {
            let bookmark = try bookmarkManager.save(folderURL: url, name: url.lastPathComponent)
            bookmarks.append(bookmark)
            print("✓ Created bookmark: \(bookmark.name) (\(bookmark.id))")

            // Validate security hash
            if !bookmark.isSecurityHashValid() {
                throw BookmarkError.securityHashInvalid(bookmark.id)
            }
        } catch {
            print("❌ Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            throw error
        }
    }

    // 3. Monitor bookmark health
    let healthTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { timer in
        for bookmark in bookmarks {
            let isExpired = bookmark.isExpired
            let accessFreq = bookmark.accessFrequency

            if isExpired {
                print("⚠️ Bookmark \(bookmark.name) is expired")
            }

            if accessFreq > 100 { // More than 100 accesses per day
                print("⚠️ High access frequency for \(bookmark.name): \(String(format: "%.1f", accessFreq)) per day")
            }
        }
    }

    // 4. Use bookmarks securely
    for bookmark in bookmarks {
        if let url = bookmarkManager.resolve(bookmark: bookmark) {
            print("✓ Resolved bookmark: \(url.path)")

            // Validate access
            let validation = bookmarkManager.validateAccess(url)
            switch validation {
            case .success:
                print("✓ Access validated for \(url.path)")
            case .failure(let error):
                print("❌ Access validation failed: \(error.localizedDescription)")
            }
        }
    }

    // 5. Cleanup
    healthTimer.invalidate()
    print("Secure bookmark workflow completed successfully")
}
```

## 📈 Summary

These examples demonstrate how to use the enhanced File Access & Scanning module with:

- ✅ **Performance Optimization**: Adaptive concurrency, memory monitoring, parallel processing
- ✅ **Security**: Comprehensive audit trails, security health monitoring, tamper detection
- ✅ **Monitoring**: Real-time health checks, metrics export, external integration
- ✅ **Error Handling**: Robust error recovery, security incident response
- ✅ **Best Practices**: Production-ready patterns, configuration management

The system is now **enterprise-ready** with world-class performance, security, and observability capabilities.
