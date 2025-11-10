import SwiftUI
import DeduperCore
import OSLog
import Combine

/**
 * FormatsView provides comprehensive support for various file formats and edge cases.
 *
 * - File format detection and handling
 * - Edge case management (corrupted files, unusual formats)
 * - Format-specific processing options
 * - Batch processing capabilities
 * - Design System: Composer component with format-aware processing
 *
 * - Author: @darianrosebrook
 */
@MainActor
public final class FormatsViewModel: ObservableObject {
    private let scanOrchestrator = ServiceManager.shared.scanOrchestrator
    private let scanService = ScanService(persistenceController: ServiceManager.shared.persistence)
    private let logger = Logger(subsystem: "com.deduper", category: "formats")

    // MARK: - Supported Formats
    @Published public var supportedImageFormats: Set<String> = []
    @Published public var supportedVideoFormats: Set<String> = []
    @Published public var supportedAudioFormats: Set<String> = []
    @Published public var supportedDocumentFormats: Set<String> = []

    // MARK: - Format Processing Options
    @Published public var enableImageProcessing: Bool = true
    @Published public var enableVideoProcessing: Bool = true
    @Published public var enableAudioProcessing: Bool = true
    @Published public var enableDocumentProcessing: Bool = true

    // MARK: - Edge Case Handling
    @Published public var handleCorruptedFiles: Bool = true
    @Published public var skipZeroByteFiles: Bool = true
    @Published public var processHiddenFiles: Bool = false
    @Published public var processSystemFiles: Bool = false

    // MARK: - Quality & Performance
    @Published public var imageQualityThreshold: Double = 0.8
    @Published public var videoQualityThreshold: Double = 0.7
    @Published public var audioQualityThreshold: Double = 0.6
    @Published public var documentQualityThreshold: Double = 0.5

    // MARK: - Advanced Options
    @Published public var enableDeepInspection: Bool = false
    @Published public var enableMetadataExtraction: Bool = true
    @Published public var enableThumbnailGeneration: Bool = true
    @Published public var batchProcessingLimit: Int = 1000

    // MARK: - Statistics
    @Published public var totalFilesProcessed: Int = 0
    @Published public var filesByFormat: [String: Int] = [:]
    @Published public var processingErrors: [String] = []
    @Published public var lastTestSummary: String?

    private var cancellables: Set<AnyCancellable> = []

    public init() {
        loadSettings()
        setupBindings()
        loadSupportedFormats()
    }

    private func loadSettings() {
        enableImageProcessing = UserDefaults.standard.bool(forKey: "enableImageProcessing")
        enableVideoProcessing = UserDefaults.standard.bool(forKey: "enableVideoProcessing")
        enableAudioProcessing = UserDefaults.standard.bool(forKey: "enableAudioProcessing")
        enableDocumentProcessing = UserDefaults.standard.bool(forKey: "enableDocumentProcessing")

        handleCorruptedFiles = UserDefaults.standard.bool(forKey: "handleCorruptedFiles")
        skipZeroByteFiles = UserDefaults.standard.bool(forKey: "skipZeroByteFiles")
        processHiddenFiles = UserDefaults.standard.bool(forKey: "processHiddenFiles")
        processSystemFiles = UserDefaults.standard.bool(forKey: "processSystemFiles")

        imageQualityThreshold = UserDefaults.standard.double(forKey: "imageQualityThreshold")
        if imageQualityThreshold <= 0 {
            imageQualityThreshold = 0.8
        }

        videoQualityThreshold = UserDefaults.standard.double(forKey: "videoQualityThreshold")
        if videoQualityThreshold <= 0 {
            videoQualityThreshold = 0.7
        }

        audioQualityThreshold = UserDefaults.standard.double(forKey: "audioQualityThreshold")
        if audioQualityThreshold <= 0 {
            audioQualityThreshold = 0.6
        }

        documentQualityThreshold = UserDefaults.standard.double(forKey: "documentQualityThreshold")
        if documentQualityThreshold <= 0 {
            documentQualityThreshold = 0.5
        }

        enableDeepInspection = UserDefaults.standard.bool(forKey: "enableDeepInspection")
        enableMetadataExtraction = UserDefaults.standard.bool(forKey: "enableMetadataExtraction")
        enableThumbnailGeneration = UserDefaults.standard.bool(forKey: "enableThumbnailGeneration")

        batchProcessingLimit = UserDefaults.standard.integer(forKey: "batchProcessingLimit")
        if batchProcessingLimit <= 0 {
            batchProcessingLimit = 1000
        }
    }

    private func setupBindings() {
        $enableImageProcessing
            .sink { UserDefaults.standard.set($0, forKey: "enableImageProcessing") }
            .store(in: &cancellables)

        $enableVideoProcessing
            .sink { UserDefaults.standard.set($0, forKey: "enableVideoProcessing") }
            .store(in: &cancellables)

        $enableAudioProcessing
            .sink { UserDefaults.standard.set($0, forKey: "enableAudioProcessing") }
            .store(in: &cancellables)

        $enableDocumentProcessing
            .sink { UserDefaults.standard.set($0, forKey: "enableDocumentProcessing") }
            .store(in: &cancellables)

        $handleCorruptedFiles
            .sink { UserDefaults.standard.set($0, forKey: "handleCorruptedFiles") }
            .store(in: &cancellables)

        $skipZeroByteFiles
            .sink { UserDefaults.standard.set($0, forKey: "skipZeroByteFiles") }
            .store(in: &cancellables)

        $processHiddenFiles
            .sink { UserDefaults.standard.set($0, forKey: "processHiddenFiles") }
            .store(in: &cancellables)

        $processSystemFiles
            .sink { UserDefaults.standard.set($0, forKey: "processSystemFiles") }
            .store(in: &cancellables)

        $imageQualityThreshold
            .sink { UserDefaults.standard.set($0, forKey: "imageQualityThreshold") }
            .store(in: &cancellables)

        $videoQualityThreshold
            .sink { UserDefaults.standard.set($0, forKey: "videoQualityThreshold") }
            .store(in: &cancellables)

        $audioQualityThreshold
            .sink { UserDefaults.standard.set($0, forKey: "audioQualityThreshold") }
            .store(in: &cancellables)

        $documentQualityThreshold
            .sink { UserDefaults.standard.set($0, forKey: "documentQualityThreshold") }
            .store(in: &cancellables)

        $enableDeepInspection
            .sink { UserDefaults.standard.set($0, forKey: "enableDeepInspection") }
            .store(in: &cancellables)

        $enableMetadataExtraction
            .sink { UserDefaults.standard.set($0, forKey: "enableMetadataExtraction") }
            .store(in: &cancellables)

        $enableThumbnailGeneration
            .sink { UserDefaults.standard.set($0, forKey: "enableThumbnailGeneration") }
            .store(in: &cancellables)

        $batchProcessingLimit
            .sink { UserDefaults.standard.set($0, forKey: "batchProcessingLimit") }
            .store(in: &cancellables)
    }

    private func loadSupportedFormats() {
        // Load supported formats from system
        supportedImageFormats = Set([
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif",
            "webp", "heic", "heif", "raw", "cr2", "nef", "arw"
        ])

        supportedVideoFormats = Set([
            "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm",
            "m4v", "3gp", "ogv", "mts", "m2ts"
        ])

        supportedAudioFormats = Set([
            "mp3", "wav", "aac", "ogg", "wma", "flac", "m4a",
            "aiff", "au", "ra", "ape", "ac3"
        ])

        supportedDocumentFormats = Set([
            "pdf", "doc", "docx", "txt", "rtf", "odt", "pages",
            "numbers", "keynote", "xls", "xlsx", "ppt", "pptx"
        ])
    }

    public func getAllSupportedFormats() -> Set<String> {
        var allFormats = supportedImageFormats
        allFormats.formUnion(supportedVideoFormats)
        allFormats.formUnion(supportedAudioFormats)
        allFormats.formUnion(supportedDocumentFormats)
        return allFormats
    }

    public func isFormatSupported(_ format: String) -> Bool {
        return getAllSupportedFormats().contains(format.lowercased())
    }

    public func resetToDefaults() {
        enableImageProcessing = true
        enableVideoProcessing = true
        enableAudioProcessing = true
        enableDocumentProcessing = true

        handleCorruptedFiles = true
        skipZeroByteFiles = true
        processHiddenFiles = false
        processSystemFiles = false

        imageQualityThreshold = 0.8
        videoQualityThreshold = 0.7
        audioQualityThreshold = 0.6
        documentQualityThreshold = 0.5

        enableDeepInspection = false
        enableMetadataExtraction = true
        enableThumbnailGeneration = true
        batchProcessingLimit = 1000

        logger.info("Reset format settings to defaults")
    }

    public func testFormatDetection() {
        processingErrors.removeAll()
        lastTestSummary = nil

        let formatsToTest = supportedImageFormats
            .union(supportedVideoFormats)
            .union(supportedAudioFormats)

        Task.detached { [weak self, formatsToTest] in
            guard let self else { return }

            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DeduperFormatTest-\(UUID().uuidString)", isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

                var formatResults: [String: Int] = [:]
                var errors: [String] = []

                for format in formatsToTest {
                    let sampleURL = tempDirectory.appendingPathComponent("sample.\(format)")
                    try Data([0x00]).write(to: sampleURL)

                    let detected = self.scanService.isMediaFile(url: sampleURL)
                    formatResults[format] = detected ? 1 : 0
                    if !detected {
                        errors.append("Failed to detect .\(format) as supported media")
                    }
                }

                try? FileManager.default.removeItem(at: tempDirectory)

                await MainActor.run {
                    self.filesByFormat = formatResults
                    self.totalFilesProcessed = formatResults.values.reduce(0, +)
                    self.processingErrors = errors
                    if errors.isEmpty {
                        self.lastTestSummary = "All tested media formats were detected successfully."
                    } else {
                        self.lastTestSummary = "Detected \(formatResults.values.filter { $0 > 0 }.count) format(s) with \(errors.count) warning(s)."
                    }
                }
            } catch {
                await MainActor.run {
                    self.processingErrors = ["Unable to perform format detection test: \(error.localizedDescription)"]
                    self.lastTestSummary = nil
                }
            }
        }
    }

    public func getFormatStatistics() -> FormatStatistics {
        return FormatStatistics(
            imageFiles: filesByFormat.filter { supportedImageFormats.contains($0.key) }.values.reduce(0, +),
            videoFiles: filesByFormat.filter { supportedVideoFormats.contains($0.key) }.values.reduce(0, +),
            audioFiles: filesByFormat.filter { supportedAudioFormats.contains($0.key) }.values.reduce(0, +),
            documentFiles: filesByFormat.filter { supportedDocumentFormats.contains($0.key) }.values.reduce(0, +),
            totalFiles: totalFilesProcessed,
            processingErrors: processingErrors.count
        )
    }
}

public struct FormatStatistics: Sendable {
    public let imageFiles: Int
    public let videoFiles: Int
    public let audioFiles: Int
    public let documentFiles: Int
    public let totalFiles: Int
    public let processingErrors: Int

    public init(
        imageFiles: Int = 0,
        videoFiles: Int = 0,
        audioFiles: Int = 0,
        documentFiles: Int = 0,
        totalFiles: Int = 0,
        processingErrors: Int = 0
    ) {
        self.imageFiles = imageFiles
        self.videoFiles = videoFiles
        self.audioFiles = audioFiles
        self.documentFiles = documentFiles
        self.totalFiles = totalFiles
        self.processingErrors = processingErrors
    }
}

/**
 * FormatsView main view implementation
 */
public struct FormatsView: View {
    @StateObject private var viewModel = FormatsViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.spacingXXXL) {
                // Format Support
                SettingsSection(title: "Supported Formats", icon: "doc.text") {
                    FormatSupportView(
                        imageFormats: viewModel.supportedImageFormats,
                        videoFormats: viewModel.supportedVideoFormats,
                        audioFormats: viewModel.supportedAudioFormats,
                        documentFormats: viewModel.supportedDocumentFormats
                    )
                }

                // Processing Options
                SettingsSection(title: "Processing Options", icon: "gear") {
                    Toggle("Enable image processing", isOn: $viewModel.enableImageProcessing)
                    Toggle("Enable video processing", isOn: $viewModel.enableVideoProcessing)
                    Toggle("Enable audio processing", isOn: $viewModel.enableAudioProcessing)
                    Toggle("Enable document processing", isOn: $viewModel.enableDocumentProcessing)
                }

                // Quality Thresholds
                SettingsSection(title: "Quality Thresholds", icon: "star.circle") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Image quality threshold")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.imageQualityThreshold))")
                        }
                        Slider(value: $viewModel.imageQualityThreshold, in: 0.1...1.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Video quality threshold")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.videoQualityThreshold))")
                        }
                        Slider(value: $viewModel.videoQualityThreshold, in: 0.1...1.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Audio quality threshold")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.audioQualityThreshold))")
                        }
                        Slider(value: $viewModel.audioQualityThreshold, in: 0.1...1.0, step: 0.1)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Document quality threshold")
                            Spacer()
                            Text("\(String(format: "%.1f", viewModel.documentQualityThreshold))")
                        }
                        Slider(value: $viewModel.documentQualityThreshold, in: 0.1...1.0, step: 0.1)
                    }
                }

                // Edge Case Handling
                SettingsSection(title: "Edge Case Handling", icon: "exclamationmark.triangle") {
                    Toggle("Handle corrupted files", isOn: $viewModel.handleCorruptedFiles)
                    Toggle("Skip zero-byte files", isOn: $viewModel.skipZeroByteFiles)
                    Toggle("Process hidden files", isOn: $viewModel.processHiddenFiles)
                    Toggle("Process system files", isOn: $viewModel.processSystemFiles)
                }

                // Advanced Options
                SettingsSection(title: "Advanced Options", icon: "wrench.and.screwdriver") {
                    Toggle("Enable deep inspection", isOn: $viewModel.enableDeepInspection)
                    Toggle("Enable metadata extraction", isOn: $viewModel.enableMetadataExtraction)
                    Toggle("Enable thumbnail generation", isOn: $viewModel.enableThumbnailGeneration)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Batch processing limit")
                            Spacer()
                            Text("\(viewModel.batchProcessingLimit)")
                        }
                        Slider(value: Binding(
                            get: { Double(viewModel.batchProcessingLimit).mapToSliderValue(minValue: 100, maxValue: 5000) },
                            set: { newValue in
                                viewModel.batchProcessingLimit = Int(newValue.sliderValueToActual(minValue: 100, maxValue: 5000))
                            }
                        ),
                               in: 0...1,
                               step: 0.1)
                    }
                }

                // Statistics
                if !viewModel.filesByFormat.isEmpty {
                    SettingsSection(title: "Processing Statistics", icon: "chart.bar") {
                        FormatStatisticsView(statistics: viewModel.getFormatStatistics())
                    }
                }

                // Action Buttons
                VStack(spacing: DesignToken.spacingMD) {
                    Button("Reset to Defaults", action: viewModel.resetToDefaults)
                        .buttonStyle(.bordered)
                        .foregroundStyle(DesignToken.colorDestructive)

                    Button("Test Format Detection") {
                        viewModel.testFormatDetection()
                    }
                    .buttonStyle(.borderedProminent)

                    if let summary = viewModel.lastTestSummary {
                        Text(summary)
                            .font(DesignToken.fontFamilyCaption)
                            .foregroundStyle(DesignToken.colorForegroundSecondary)
                            .multilineTextAlignment(.center)
                    }

                    if !viewModel.processingErrors.isEmpty {
                        VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                            ForEach(viewModel.processingErrors, id: \.self) { error in
                                Text(error)
                                    .font(DesignToken.fontFamilyCaption)
                                    .foregroundStyle(DesignToken.colorStatusWarning)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(DesignToken.spacingXXXL)
        }
        .navigationTitle("File Formats & Edge Cases")
        .background(DesignToken.colorBackgroundPrimary)
    }
}

/**
 * Format support display component
 */
public struct FormatSupportView: View {
    public let imageFormats: Set<String>
    public let videoFormats: Set<String>
    public let audioFormats: Set<String>
    public let documentFormats: Set<String>

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            FormatCategoryView(title: "Images", formats: imageFormats, icon: "photo")
            FormatCategoryView(title: "Videos", formats: videoFormats, icon: "video")
            FormatCategoryView(title: "Audio", formats: audioFormats, icon: "music.note")
            FormatCategoryView(title: "Documents", formats: documentFormats, icon: "doc.text")
        }
    }
}

public struct FormatCategoryView: View {
    public let title: String
    public let formats: Set<String>
    public let icon: String

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                Text(title)
                    .font(DesignToken.fontFamilySubheading)
                    .foregroundStyle(DesignToken.colorForegroundPrimary)
                Spacer()
                Text("\(formats.count) formats")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }

            Text(formats.sorted().joined(separator: ", "))
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
                .lineLimit(3)
        }
    }
}

/**
 * Format statistics display component
 */
public struct FormatStatisticsView: View {
    public let statistics: FormatStatistics

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            HStack {
                StatCard(
                    title: "Images",
                    value: "\(statistics.imageFiles)",
                    icon: "photo.circle.fill",
                    color: DesignToken.colorStatusInfo
                )

                StatCard(
                    title: "Videos",
                    value: "\(statistics.videoFiles)",
                    icon: "video.circle.fill",
                    color: DesignToken.colorStatusError
                )

                StatCard(
                    title: "Audio",
                    value: "\(statistics.audioFiles)",
                    icon: "music.note.circle.fill",
                    color: DesignToken.colorStatusSuccess
                )

                StatCard(
                    title: "Documents",
                    value: "\(statistics.documentFiles)",
                    icon: "doc.circle.fill",
                    color: DesignToken.colorStatusInfo
                )
            }

            HStack {
                StatCard(
                    title: "Total Files",
                    value: "\(statistics.totalFiles)",
                    icon: "doc.text.fill",
                    color: DesignToken.colorStatusWarning
                )

                StatCard(
                    title: "Errors",
                    value: "\(statistics.processingErrors)",
                    icon: "exclamationmark.triangle.fill",
                    color: statistics.processingErrors > 0 ? .red : .green
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FormatsView()
}
