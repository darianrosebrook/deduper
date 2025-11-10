## 14 · Logging & Observability — Checklist
Author: @darianrosebrook

### For Agents

- See `docs/agents.md`. Stream logs; monitor performance; provide diagnostics.
- Ensure logs are searchable and exportable.

### Scope

Comprehensive logging system with real-time monitoring, performance metrics, and diagnostic capabilities.

### Acceptance Criteria

- [x] Real-time log streaming with configurable levels and categories.
- [x] Performance metrics collection and visualization.
- [x] Search and filtering capabilities across logs.
- [x] Statistics and analytics for log patterns.
- [x] Export functionality for logs and performance data.
- [x] System resource monitoring (memory, CPU).
- [x] Time-based filtering and retention policies.
- [x] Diagnostic tools for troubleshooting.

### Verification (Automated)

- [x] Log entries stream correctly with proper formatting.
- [x] Performance metrics update in real-time.
- [x] Search and filtering work across all log attributes.
- [x] Export functionality generates valid JSON data.
- [x] Statistics calculations are accurate.

### Implementation Tasks

- [x] Resolve ambiguities (see `../../../development/ambiguities.md#14--logging--observability`).
- [x] LoggingViewModel with log streaming and performance monitoring.
- [x] LogEntry and LogLevel types with proper styling.
- [x] TimeRange and filtering options.
- [x] Real-time log collection with AsyncStream.
- [x] Performance metrics integration with PerformanceService.
- [x] Search and filtering functionality.
- [x] Export and statistics capabilities.
- [x] LoggingView with organized layout and controls.

### Done Criteria

- Complete logging and observability system; tests green; UI polished.

✅ Complete logging and observability system with real-time monitoring, search, and export capabilities.

### Performance Monitoring Implementation Status

**Last Updated**: December 2024

#### Real Metrics Collection
- ✅ **System Metrics**: Implemented using macOS APIs (`host_processor_info`, `getifaddrs`, `task_threads`) for CPU, memory, disk, network usage
- ✅ **Detection Metrics**: Integrated with `DuplicateDetectionEngine` for real query times, cache hit rates, and memory usage
- ✅ **Metrics Persistence**: UserDefaults-based storage for historical trends (replaced print statements)
- ✅ **Benchmark Execution**: Real `DuplicateDetectionEngine` execution with synthetic datasets (replaced placeholder logic)

#### Implementation Details
- **Query Timestamps**: Thread-safe tracking using `QueryTimestampsActor` for queries per second calculation
- **Memory Usage**: Real-time process memory tracking using `mach_task_basic_info`
- **CPU Usage**: System-wide CPU usage via `host_processor_info` with proper memory management
- **Trends**: Historical metrics aggregation with time-based filtering and granularity (hourly, daily, weekly, monthly)

### Known Limitations

1. **Persistence**: Uses UserDefaults for metrics storage - may need CoreData migration for large datasets
2. **Network Usage**: Estimated from interface statistics - may not reflect all network activity
3. **Cache Hit Rate**: Falls back to estimation from `reductionPercentage` if not available from index service
4. **Metrics Retention**: Limited by UserDefaults storage capacity - may need archival strategy for long-term trends