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
- **Supported Formats**: 
  - **Images**: JPEG, PNG, HEIC/HEIF, TIFF, WebP, GIF, BMP, RAW formats (CR2, CR3, NEF, ARW, DNG, etc.), professional formats (PSD, AI, EPS, SVG)
  - **Videos**: MP4, MOV, AVI, MKV, WMV, FLV, WebM, M4V, 3GP, MTS, M2TS, OGV, ProRes, DNxHD, XDCAM, XAVC, RED formats
  - **Audio**: MP3, WAV, AAC, M4A, FLAC, OGG, Opus, ALAC, APE, WV, AIFF, WMA, AC3, DTS, and more

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
- **Testing**: Unit tests, integration tests, and UI testing with test fixtures
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

3. **Run the application:**
   ```bash
   # Run directly from command line
   swift run Deduper

   # OR build the executable and run it
   swift build
   .build/arm64-apple-macosx/debug/Deduper

   # OR open in Xcode and run
   xed .
   # Select the `Deduper` executable target
   # Choose your development team for signing
   # Press `Cmd + R` to build and run
   ```

### **Current Status**

**Implementation Status**: Core functionality implemented and operational

- ✅ **Core Services (`DeduperCore`)**: Implemented and building successfully
- ✅ **Architecture**: Service layer with dependency injection implemented
- ✅ **Documentation**: 72+ guides and specifications available
- ✅ **Build System**: Swift Package Manager with proper targets
- ✅ **Testing**: Test suites implemented for MergeService, VisualDifferenceService, Audio detection, Integration tests, and Transaction recovery
- ✅ **UI Components**: Core views implemented and connected to backend services (OperationsView, MergePlanSheet, TestingView, LoggingView)
- ✅ **Performance Monitoring**: Real system metrics, detection metrics, persistence, and benchmark execution implemented
- ✅ **Critical Issues**: Critical bugs fixed, critical TODOs resolved
- ✅ **Safety**: Safety issues addressed, error handling implemented
- 🔄 **Release Status**: Core features implemented, remaining work is enhancements and polish

### Recent Updates & Fixes

- ✅ **CoreData Transformer Security**: All transformable attributes now use `NSSecureUnarchiveFromDataTransformer`
- ✅ **Concurrency Compliance**: Fixed main actor isolation warnings in UI components
- ✅ **Build System**: Resolved model compilation issues - project now builds cleanly
- ✅ **Implementation Roadmap**: Created detailed plans for remaining TODOs in `/docs/TODOS/`

## Getting Started

### First Launch

When you first launch Deduper, you'll see the main interface with a sidebar navigation and the folder selection screen.

1. **Select Folders**: Click "Add Folder" to choose directories containing photos and videos
   - The app will request macOS permissions to access selected folders
   - Supports Photos library, external drives, network volumes, and local directories
   - You can add multiple folders to scan

2. **Start Scanning**: Click "Start Scan" or press `Return` to begin duplicate detection
   - Progress is shown in real-time with item counts and current folder being scanned
   - You can cancel the scan at any time with "Stop Scan" or `Escape`

3. **Review Results**: After scanning completes, duplicate groups are displayed
   - Each group shows similar files with confidence scores
   - Preview thumbnails help identify duplicates visually

4. **Select Keepers**: For each duplicate group, choose which file to keep
   - Click on a file thumbnail to select it as the keeper
   - The app suggests a keeper based on file quality and metadata
   - Selected keepers are highlighted with a star indicator

5. **Merge Duplicates**: Review the merge plan and execute
   - Click "Preview Merge" or press `Return` on a selected group
   - Review which files will be moved to trash and space savings
   - Confirm the merge operation
   - Duplicate files are moved to Trash (not permanently deleted)

6. **Undo Operations**: If you need to restore files
   - Use the "Undo Last Merge" menu item (`Cmd+Z`) or navigate to History view
   - Files are restored from Trash to their original locations
   - Undo is available for recent operations within the configured undo depth

## Key Functionality

### Main Workflows

#### 1. **Folder Selection & Scanning**
- **Add Folders**: Click "Add Folder" button or use folder picker dialog
- **Start Scan**: Click "Start Scan" button or press `Return` key
- **Monitor Progress**: Real-time progress shows items processed and current folder
- **Cancel Scan**: Click "Stop Scan" or press `Escape` to cancel
- **Rescan**: Click "Rescan" or press `Cmd+R` to re-analyze selected folders

#### 2. **Reviewing Duplicate Groups**
- **Groups List**: Navigate to "Duplicate Groups" in sidebar to see all detected duplicates
- **Search & Filter**: Use search bar to find specific groups or files
- **Group Details**: Click on a group to see detailed comparison view
- **Navigation**: Use arrow keys (`↑`/`↓`) to navigate between groups

#### 3. **Selecting Keepers**
- **Visual Selection**: Click on file thumbnails to select as keeper
- **Keyboard Shortcut**: Press `Space` to select/deselect keeper
- **Auto-Suggestion**: App suggests best keeper based on file quality and metadata
- **Manual Override**: You can always change the suggested keeper

#### 4. **Merging Duplicates**
- **Preview Merge**: Click "Preview Merge" button or press `Return` on selected group
- **Review Plan**: Merge plan sheet shows:
  - Keeper file (file to keep)
  - Files to remove (moved to Trash)
  - Estimated space savings
  - Metadata changes (if any)
- **Execute Merge**: Click "Merge" button or press `Cmd+Return` in merge plan sheet
- **Safety**: Files are moved to Trash, not permanently deleted

#### 5. **Undo Operations**
- **Undo Last**: Use menu "Merge > Undo Last Merge" or `Cmd+Z`
- **History View**: Navigate to "History" in sidebar to see all operations
- **Restore Files**: Undo restores files from Trash to original locations
- **Transaction Logging**: All operations are logged for recovery

### Keyboard Shortcuts

#### Navigation
- `↑` / `↓` - Navigate between duplicate groups
- `Return` - Preview merge plan for selected group
- `Space` - Select/deselect keeper for current group
- `Tab` - Navigate to next interactive element
- `Escape` - Cancel current operation or close sheet

#### Scanning
- `Return` - Start scan (when folders selected)
- `Escape` - Stop/cancel scan
- `Cmd+R` - Rescan selected folders

#### Merge Operations
- `Cmd+M` - Merge current group (from menu)
- `Cmd+Z` - Undo last merge (from menu)
- `Cmd+S` - Skip current group (from menu)
- `Cmd+Return` - Execute merge (in merge plan sheet)
- `Escape` - Cancel merge plan sheet

#### General
- `Cmd+S` - Open similarity settings
- `Cmd+,` - Open application settings
- `Cmd+W` - Close window
- `Cmd+Q` - Quit application

### Main Screens

#### Dashboard (Default)
- Folder selection and scanning interface
- Real-time scan progress
- Quick preview of duplicate groups
- Session metrics and recovery options

#### Duplicate Groups
- List view of all detected duplicate groups
- Search and filter capabilities
- Group preview cards with thumbnails
- Quick actions (Preview Merge, Show in Finder)

#### Group Detail
- Detailed view of a single duplicate group
- Side-by-side file comparison
- Evidence panel with confidence signals
- Metadata differences
- Merge plan preview

#### History
- List of all merge operations
- Undo capabilities
- Operation details and timestamps
- File restoration options

#### Settings
- Similarity threshold configuration
- Processing options
- Safety settings (dry-run mode, undo depth)
- Performance preferences

#### Tools & Utilities
- **Logs**: Real-time logging and diagnostics
- **Benchmarking**: Performance testing interface
- **Testing**: Quality metrics and test execution
- **Accessibility**: VoiceOver and accessibility settings
- **File Formats**: Supported format information

### Development Notes

- **Xcode Project**: Use `xed .` to open the package directly in Xcode (no need for `generate-xcodeproj`)
- **CoreData**: Uses programmatic model with secure transformers (no .xcdatamodel file needed)
- **Build Issues**: If you encounter model loading errors, run `rm -rf .build` to clean
- **Executable Name**: The app executable is named `Deduper` (run with `swift run Deduper`)

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
├── Tests/                     # Test suite
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
- Include documentation for public APIs
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
