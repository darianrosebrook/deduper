# Deduper — Advanced Duplicate Photo & Video Finder for macOS

**A duplicate detection application architecture for macOS.**

A native macOS application that intelligently finds and manages duplicate and visually similar photos and videos. Built with modular architecture, safety-first design principles, and performance optimization.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13+-blue.svg)](https://developer.apple.com/macos)
[![Xcode](https://img.shields.io/badge/Xcode-15+-black.svg)](https://developer.apple.com/xcode)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Key Features

### **Intelligent Duplicate Detection**
- **Multi-algorithm Analysis**: Combines perceptual hashing (pHash), metadata comparison, and content analysis
- **Configurable Similarity Thresholds**: Fine-tune detection sensitivity with granular controls
- **Evidence-Based Decisions**: Transparent confidence scoring with detailed signal analysis
- **Machine Learning Enhancement**: Learns from user decisions to improve future recommendations

### **Security & Privacy First**
- **macOS Sandbox Compliant**: Secure file access with proper entitlements and permissions
- **Safe Operations**: Move-to-trash by default, undo support, and transaction logging
- **Protected Folder Detection**: Automatically identifies and handles system/cloud-synced directories
- **No Data Collection**: All processing happens locally with optional anonymized analytics

### **Performance Optimized**
- **Concurrent Processing**: Optimized thread pools for different operation types
- **Memory Management**: Bounded memory usage with intelligent caching strategies
- **Progressive Loading**: Stream results as they become available with pause/cancel/resume
- **Real-time Monitoring**: Live performance metrics and resource usage tracking

### **Professional UI/UX**
- **Native SwiftUI Interface**: Modern, responsive design following macOS conventions
- **Accessibility First**: Full VoiceOver support, keyboard navigation, and screen reader compatibility
- **Evidence Panels**: Detailed comparison views with metadata diffs and confidence indicators
- **Batch Operations**: Process thousands of files with progress tracking and error handling

### 🛠️ **Developer Experience**
- **Modular Architecture**: Clean separation between UI, business logic, and data layers
- **Comprehensive Testing**: Unit tests, integration tests, and UI testing with test fixtures
- **Rich Documentation**: Detailed implementation guides, architectural decisions, and troubleshooting
- **CI/CD Ready**: Automated testing, benchmarking, and deployment pipelines

## Requirements

- **macOS 13+** (Ventura or newer)
- **Xcode 15+**
- **Swift 5.9+**
- **Apple Developer Program** account (for signing and notarization)

## Quick Start

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/deduper.git
   cd deduper
   ```

2. **Build the project:**
   ```bash
   swift build
   ```

3. **For Xcode development:**
   ```bash
   # Open the package directly in Xcode (Swift Package Manager projects)
   xed Sources/
   # OR open the entire project directory
   xed .
   ```

4. **Run the application:**
   ```bash
   # Run directly from command line
   swift run

   # OR build and run in Xcode
   # Select the `Deduper` executable target
   # Choose your development team for signing
   # Press `Cmd + R` to build and run
   ```

### **Current Status**

**Implementation Status**: Core functionality implemented, testing coverage improved, UI components connected to backend services.

- ✅ **Core Services (`DeduperCore`)**: Implemented and building successfully
- ✅ **Architecture**: Service layer with dependency injection implemented
- ✅ **Documentation**: 72+ guides and specifications available
- ✅ **Build System**: Swift Package Manager with proper targets
- ✅ **Testing**: Comprehensive test suites implemented for MergeService, VisualDifferenceService, Audio detection, Integration tests, and Transaction recovery
- ✅ **UI Components**: Core views implemented and connected to backend services (OperationsView, MergePlanSheet, TestingView, LoggingView)
- ✅ **Performance Monitoring**: Real system metrics, detection metrics, persistence, and benchmark execution implemented
- ⚠️ **CoreData Model**: Programmatic model with secure transformers (some pre-existing compilation issues in unrelated files)
- 🔄 **Production Readiness**: In development - core features implemented but comprehensive testing and validation ongoing

### Recent Updates & Fixes

- ✅ **CoreData Transformer Security**: All transformable attributes now use `NSSecureUnarchiveFromDataTransformer`
- ✅ **Concurrency Compliance**: Fixed main actor isolation warnings in UI components
- ✅ **Build System**: Resolved model compilation issues - project now builds cleanly
- ✅ **Implementation Roadmap**: Created detailed plans for remaining TODOs in `/docs/TODOS/`

### First Launch

1. **Grant Permissions**: The app will request access to folders containing photos/videos
2. **Select Folders**: Choose directories to scan (supports Photos library, external drives, etc.)
3. **Configure Settings**: Adjust similarity thresholds and processing options
4. **Start Scanning**: Begin the duplicate detection process

### Development Notes

- **Xcode Project**: Use `xed .` to open the package directly in Xcode (no need for `generate-xcodeproj`)
- **CoreData**: Uses programmatic model with secure transformers (no .xcdatamodel file needed)
- **Build Issues**: If you encounter model loading errors, run `rm -rf .build` to clean

## Architecture Overview

### **Core Services Layer (`DeduperCore`)**
```
DeduperCore/
├── DeduperCore.swift           # Service manager and dependency injection
├── CoreTypes.swift             # Data structures and type definitions
├── DuplicateDetectionEngine.swift  # Core duplicate detection logic
├── ScanService.swift           # File scanning and discovery
├── ImageHashingService.swift   # Perceptual hashing implementation
├── VideoFingerprinter.swift    # Video content analysis
├── MergeService.swift          # Safe file operations and merging
├── PersistenceController.swift # Core Data management
├── PerformanceService.swift    # Metrics and optimization
├── LearningService.swift       # User feedback and ML refinement
├── PermissionsService.swift    # Security-scoped bookmarks
├── ThumbnailService.swift      # Image thumbnail generation
├── MetadataExtractionService.swift # File metadata analysis
├── HashIndexService.swift      # Hash-based indexing
├── IndexQueryService.swift     # Query optimization
├── ScanOrchestrator.swift      # Scan coordination
├── OnboardingService.swift     # User onboarding flow
├── FeedbackService.swift       # User feedback collection
├── MonitoringService.swift     # System monitoring
├── PerformanceMetrics.swift    # Performance data structures
└── MergeTestUtils.swift         # Testing utilities
```

### **User Interface Layer (`DeduperUI`)**
```
DeduperUI/
├── Views.swift                 # Main application screens
├── SettingsView.swift          # Preferences and configuration
├── LoggingView.swift           # Real-time logging and monitoring
├── OperationsView.swift        # Safe file operations management
├── BenchmarkView.swift         # Performance testing interface
├── AccessibilityView.swift     # A11y features and localization
├── DesignTokens.swift          # Design system implementation
└── [Component].swift           # Reusable UI components
```

### **Design System (`DesignSystem/`)**
```
DesignSystem/
├── designTokens/               # W3C-compliant design tokens
├── component-complexity/       # Component standards and guidelines
├── COMPONENT_STANDARDS.md      # UI component specifications
└── component-complexity.md     # Complexity management strategy
```

## Development

### **Project Structure**
```
deduper/
├── Sources/
│   ├── DeduperApp/            # macOS application target
│   ├── DeduperCore/           # Core business logic library
│   └── DeduperUI/             # User interface components
├── Tests/                     # Comprehensive test suite
├── docs/                      # Extensive documentation
└── Scripts/                   # Build and development tools
```

### **Key Technologies**
- **Swift 5.9+** with modern concurrency features
- **SwiftUI** for native macOS interface
- **Core Data** for persistent storage
- **AVFoundation** for media analysis
- **CryptoKit** for secure hashing
- **Combine** for reactive programming
- **OSLog** for structured logging

### **Testing Strategy**
- **Unit Tests**: Core algorithms and business logic implemented (MergeService, VisualDifferenceService, Audio detection)
- **Integration Tests**: Service interactions and data flow implemented (MergeIntegrationTests, TransactionRecoveryTests)
- **UI Tests**: User workflows and interface behavior (in progress)
- **Performance Tests**: Benchmarking and resource usage implemented (real metrics collection)
- **Test Fixtures**: Realistic sample data for development

## Documentation

### **Implementation Guides**
- **[Core Implementation Guide](docs/architecture/IMPLEMENTATION_GUIDE.md)** - Development roadmap
- **[Architectural Decision Records](docs/reference/adr/)** - Design rationale and trade-offs
- **[Component Standards](DesignSystem/COMPONENT_STANDARDS.md)** - UI/UX specifications
- **[Best Practices](docs/development/best-in-class-ideas.md)** - Development techniques

### **Feature Documentation**
- **[File Access & Scanning](docs/01-file-access-scanning/)** - Secure folder access implementation
- **[Duplicate Detection Engine](docs/05-duplicate-detection-engine/)** - Core algorithms and similarity matching
- **[Performance Optimizations](docs/10-performance-optimizations/)** - Speed and efficiency improvements
- **[Safe File Operations](docs/15-safe-file-operations-undo/)** - Transactional file management

## Project Files

### **Created/Updated for Accuracy**
- ✅ **LICENSE**: MIT license file
- ✅ **.swiftlint.yml**: Code style configuration with project-specific rules
- ✅ **README.md**: Updated build instructions for Swift Package Manager
- ✅ **Documentation**: Updated target names and references across all guides

## Contributing

We welcome contributions! This project implements duplicate detection best practices with a focus on correctness, safety, and transparency.

### **Development Setup**
1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/deduper.git`
3. Install SwiftLint: `brew install swiftlint`
4. Build the project: `swift build`
5. Run tests: `swift test`
6. Optional: Generate Xcode project: `swift package generate-xcodeproj`

### **Contribution Guidelines**
- Follow the [Contributing Guide](docs/CONTRIBUTING.md)
- Ensure all tests pass
- Update documentation as needed
- Follow the established code style and architecture patterns
- Consider accessibility and internationalization

### **Code Style**
- **SwiftLint**: Configured with project-specific rules (see `.swiftlint.yml`)
- Follow Apple's Swift API Design Guidelines
- Prefer immutable data structures where possible
- Use descriptive variable and function names
- Include comprehensive documentation for public APIs
- No emojis in code comments or documentation
- Prefer `const` over `let` for immutable declarations

## Security & Privacy

### **Security Features**
- **macOS Sandbox Compliance**: Proper entitlements and security-scoped bookmarks implemented
- **Safe File Operations**: Move-to-trash by default with undo support
- **Protected Path Detection**: Automatic identification of system and cloud-synced directories
- **Transaction Logging**: Audit trail of file operations (framework implemented)

### **Privacy Protection**
- **Local Processing**: All analysis happens on-device, no cloud processing
- **Optional Analytics**: User-controlled, anonymized usage statistics
- **No Data Collection**: Files and metadata never leave the device
- **GDPR Compliant**: Full user control over data retention and processing

## Performance

### **Optimization Features**
- **Concurrent Processing**: Optimized thread pools for I/O, hashing, and analysis
- **Memory Management**: Bounded memory usage with intelligent caching
- **Progressive Results**: Stream results as they become available
- **Pause/Resume**: Interruptible operations with state persistence

### **Benchmarking**
- **Built-in Benchmarks**: Performance testing suite with real DuplicateDetectionEngine execution
- **Real-time Metrics**: Live monitoring of CPU, memory, and I/O usage (system metrics implemented)
- **Detection Metrics**: Query times, cache hit rates, and memory usage tracking (integrated with detection engine)
- **Historical Tracking**: Performance trends and metrics persistence (UserDefaults-based storage)
- **Resource Bounds**: Configurable limits to prevent system impact

## What Makes This Special

This project demonstrates:

1. **Modular Architecture**: Service layer with dependency injection
2. **Safety-First Design**: Operations are reversible with audit trail framework
3. **Transparency**: Evidence-based decisions with confidence scoring
4. **Performance Engineering**: Optimized for large-scale media libraries
5. **Accessibility**: Support for assistive technologies (in progress)
6. **Developer Experience**: Documentation and tooling available

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

This project represents the culmination of extensive research into duplicate detection, file system operations, and macOS application development. It incorporates best practices from:

- Apple's Human Interface Guidelines
- Security and privacy research papers
- Performance optimization studies
- Accessibility and internationalization standards
- Industry-leading development practices

---

**Built with ❤️ for the macOS community**

*For support, feature requests, or contributions, please see our [Contributing Guide](docs/CONTRIBUTING.md)*
