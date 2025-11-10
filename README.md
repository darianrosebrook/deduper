# Deduper — Advanced Duplicate Photo & Video Finder for macOS

**A duplicate detection application architecture for macOS.**

A native macOS application that intelligently finds and manages duplicate and visually similar photos and videos. Built with modular architecture, safety-first design principles, and performance optimization.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13+-blue.svg)](https://developer.apple.com/macos)
[![Xcode](https://img.shields.io/badge/Xcode-15+-black.svg)](https://developer.apple.com/xcode)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Key Features

- **Intelligent Duplicate Detection**: Multi-algorithm analysis combining perceptual hashing (pHash), metadata comparison, and content analysis with configurable similarity thresholds and evidence-based confidence scoring
- **Machine Learning Enhancement**: Learns from user decisions to improve future recommendations
- **Security & Privacy First**: macOS sandbox compliant, safe operations (move-to-trash by default), undo support, protected folder detection, local processing only
- **Performance Optimized**: Concurrent processing, bounded memory usage, progressive loading with pause/cancel/resume, real-time monitoring
- **Professional UI/UX**: Native SwiftUI interface, full accessibility support (VoiceOver, keyboard navigation), evidence panels with detailed comparisons, batch operations
- **Developer Experience**: Modular architecture, comprehensive testing, extensive documentation, CI/CD ready

### Supported Formats

**Images**: JPEG, PNG, HEIC/HEIF, TIFF, WebP, GIF, BMP, RAW formats (CR2, CR3, NEF, ARW, DNG, etc.), professional formats (PSD, AI, EPS, SVG)

**Videos**: MP4, MOV, AVI, MKV, WMV, FLV, WebM, M4V, 3GP, MTS, M2TS, OGV, ProRes, DNxHD, XDCAM, XAVC, RED formats

**Audio**: MP3, WAV, AAC, M4A, FLAC, OGG, Opus, ALAC, APE, WV, AIFF, WMA, AC3, DTS, and more

## Requirements

- **macOS 13+** (Ventura or newer)
- **Xcode 15+**
- **Swift 5.9+**
- **Apple Developer Program** account (for signing and notarization)

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/deduper.git
cd deduper

# Build and run
swift build
swift run Deduper

# OR open in Xcode
xed .
# Select the `Deduper` executable target, choose your development team, press Cmd+R
```

### First Launch

1. **Select Folders**: Click "Add Folder" to choose directories containing photos and videos (supports Photos library, external drives, network volumes)
2. **Start Scanning**: Click "Start Scan" or press `Return` to begin duplicate detection
3. **Review Results**: Duplicate groups are displayed with confidence scores and preview thumbnails
4. **Select Keepers**: Click file thumbnails to select keepers (app suggests best keeper based on quality/metadata)
5. **Merge Duplicates**: Click "Preview Merge" to review plan, then confirm to move duplicates to Trash
6. **Undo Operations**: Use "Undo Last Merge" (`Cmd+Z`) or History view to restore files from Trash

### Keyboard Shortcuts

**Navigation**: `↑`/`↓` - Navigate groups | `Return` - Preview merge | `Space` - Select keeper | `Escape` - Cancel

**Scanning**: `Return` - Start scan | `Escape` - Stop scan | `Cmd+R` - Rescan

**Merge**: `Cmd+M` - Merge group | `Cmd+Z` - Undo merge | `Cmd+Return` - Execute merge

**General**: `Cmd+S` - Similarity settings | `Cmd+,` - Settings | `Cmd+W` - Close | `Cmd+Q` - Quit

## Current Status

**Core functionality implemented and operational**

- ✅ Core services (`DeduperCore`) with service layer architecture and dependency injection
- ✅ Build system (Swift Package Manager) building successfully
- ✅ Testing suites (MergeService, VisualDifferenceService, Audio detection, Integration tests, Transaction recovery)
- ✅ UI components connected to backend services (OperationsView, MergePlanSheet, TestingView, LoggingView)
- ✅ Performance monitoring (system metrics, detection metrics, persistence, benchmark execution)
- ✅ Security fixes (CoreData secure transformers, concurrency compliance, build system resolved)
- 🔄 Remaining work: Enhancements and polish

## Architecture

### Core Services (`DeduperCore`)
Service layer with dependency injection including: duplicate detection engine, scan service, perceptual hashing, video fingerprinting, merge service, persistence controller, performance monitoring, learning service, permissions management, thumbnail generation, metadata extraction, indexing, and orchestration.

### User Interface (`DeduperUI`)
Native SwiftUI interface with main screens, settings, logging, operations management, benchmarking, accessibility features, and design system integration.

### Design System (`DesignSystem`)
W3C-compliant design tokens, component standards, and complexity management guidelines.

## Development

### Project Structure
```
deduper/
├── Sources/
│   ├── DeduperApp/      # macOS application target
│   ├── DeduperCore/     # Core business logic library
│   └── DeduperUI/       # User interface components
├── Tests/               # Test suite
├── docs/                # Extensive documentation
└── Scripts/             # Build and development tools
```

### Key Technologies
- **Swift 5.9+** with modern concurrency features
- **SwiftUI** for native macOS interface
- **Core Data** for persistent storage
- **AVFoundation** for media analysis
- **CryptoKit** for secure hashing
- **Combine** for reactive programming
- **OSLog** for structured logging

### Testing Strategy
- **Unit Tests**: Core algorithms and business logic (MergeService, VisualDifferenceService, Audio detection)
- **Integration Tests**: Service interactions and data flow (MergeIntegrationTests, TransactionRecoveryTests)
- **UI Tests**: User workflows and interface behavior (in progress)
- **Performance Tests**: Benchmarking and resource usage with real metrics collection
- **Test Fixtures**: Realistic sample data for development

### Development Notes
- Use `xed .` to open package directly in Xcode (no `generate-xcodeproj` needed)
- CoreData uses programmatic model with secure transformers (no .xcdatamodel file)
- If model loading errors occur, run `rm -rf .build` to clean
- Executable name: `Deduper` (run with `swift run Deduper`)

## Documentation

### Implementation Guides
- **[Core Implementation Guide](docs/architecture/IMPLEMENTATION_GUIDE.md)** - Development roadmap
- **[Architectural Decision Records](docs/reference/adr/)** - Design rationale and trade-offs
- **[Component Standards](DesignSystem/COMPONENT_STANDARDS.md)** - UI/UX specifications
- **[Best Practices](docs/development/best-in-class-ideas.md)** - Development techniques

### Feature Documentation
- **[File Access & Scanning](docs/01-file-access-scanning/)** - Secure folder access implementation
- **[Duplicate Detection Engine](docs/05-duplicate-detection-engine/)** - Core algorithms and similarity matching
- **[Performance Optimizations](docs/10-performance-optimizations/)** - Speed and efficiency improvements
- **[Safe File Operations](docs/15-safe-file-operations-undo/)** - Transactional file management

## Contributing

We welcome contributions! This project implements duplicate detection best practices with a focus on correctness, safety, and transparency.

### Development Setup
1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/deduper.git`
3. Install SwiftLint: `brew install swiftlint`
4. Build: `swift build`
5. Run tests: `swift test`

### Contribution Guidelines
- Follow the [Contributing Guide](docs/CONTRIBUTING.md)
- Ensure all tests pass
- Update documentation as needed
- Follow established code style and architecture patterns
- Consider accessibility and internationalization

### Code Style
- **SwiftLint**: Configured with project-specific rules (see `.swiftlint.yml`)
- Follow Apple's Swift API Design Guidelines
- Prefer immutable data structures where possible
- Use descriptive variable and function names
- Include documentation for public APIs
- No emojis in code comments or documentation

## Security & Privacy

- **macOS Sandbox Compliance**: Proper entitlements and security-scoped bookmarks implemented
- **Safe File Operations**: Move-to-trash by default with undo support
- **Protected Path Detection**: Automatic identification of system and cloud-synced directories
- **Transaction Logging**: Audit trail of file operations (framework implemented)
- **Local Processing**: All analysis happens on-device, no cloud processing
- **Optional Analytics**: User-controlled, anonymized usage statistics
- **No Data Collection**: Files and metadata never leave the device
- **GDPR Compliant**: Full user control over data retention and processing

## Performance

- **Concurrent Processing**: Optimized thread pools for I/O, hashing, and analysis
- **Memory Management**: Bounded memory usage with intelligent caching
- **Progressive Results**: Stream results as they become available
- **Pause/Resume**: Interruptible operations with state persistence
- **Built-in Benchmarks**: Performance testing suite with real DuplicateDetectionEngine execution
- **Real-time Metrics**: Live monitoring of CPU, memory, and I/O usage
- **Detection Metrics**: Query times, cache hit rates, and memory usage tracking
- **Historical Tracking**: Performance trends and metrics persistence
- **Resource Bounds**: Configurable limits to prevent system impact

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

This project incorporates best practices from Apple's Human Interface Guidelines, security and privacy research, performance optimization studies, accessibility standards, and industry-leading development practices.

---

*For support, feature requests, or contributions, please see our [Contributing Guide](docs/CONTRIBUTING.md)*
