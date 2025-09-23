## 17 · Edge Cases & Formats — Implementation Plan
Author: @darianrosebrook

### Objectives

- Provide comprehensive support for various file formats and handle edge cases gracefully.

### Strategy

- **Format Detection**: Robust file format identification and validation
- **Edge Case Handling**: Comprehensive error handling for corrupted or unusual files
- **Quality Control**: Format-specific processing thresholds and validation
- **Batch Processing**: Efficient handling of large numbers of files

### Public API

- FormatsViewModel
  - supportedImageFormats: Set<String>
  - supportedVideoFormats: Set<String>
  - supportedAudioFormats: Set<String>
  - supportedDocumentFormats: Set<String>
  - enableImageProcessing: Bool
  - enableVideoProcessing: Bool
  - enableAudioProcessing: Bool
  - enableDocumentProcessing: Bool
  - handleCorruptedFiles: Bool
  - skipZeroByteFiles: Bool
  - processHiddenFiles: Bool
  - processSystemFiles: Bool
  - imageQualityThreshold: Double
  - videoQualityThreshold: Double
  - audioQualityThreshold: Double
  - documentQualityThreshold: Double
  - enableDeepInspection: Bool
  - enableMetadataExtraction: Bool
  - enableThumbnailGeneration: Bool
  - batchProcessingLimit: Int
  - getAllSupportedFormats() -> Set<String>
  - isFormatSupported(_ format: String) -> Bool
  - getFormatStatistics() -> FormatStatistics
  - resetToDefaults()

- FormatStatistics
  - imageFiles: Int
  - videoFiles: Int
  - audioFiles: Int
  - documentFiles: Int
  - totalFiles: Int
  - processingErrors: Int

### Implementation Details

#### Format Support

1. **Image Formats**
   - JPG, PNG, GIF, BMP, TIFF, WebP, HEIC, RAW, CR2, NEF, ARW
   - Quality thresholds and processing options
   - Metadata extraction and thumbnail generation

2. **Video Formats**
   - MP4, MOV, AVI, MKV, WMV, FLV, WebM, M4V, 3GP, OGV, MTS
   - Frame extraction and quality analysis
   - Audio track handling

3. **Audio Formats**
   - MP3, WAV, AAC, OGG, WMA, FLAC, M4A, AIFF, AU, RA, APE
   - Audio quality analysis and metadata extraction
   - Duration and bitrate detection

4. **Document Formats**
   - PDF, DOC, DOCX, TXT, RTF, ODT, Pages, Numbers, Keynote, XLS, XLSX, PPT
   - Text extraction and content analysis
   - Page count and structure detection

#### Edge Case Handling

- **Corrupted Files**: Detection and safe handling
- **Zero-byte Files**: Automatic skipping or special processing
- **Hidden/System Files**: Configurable inclusion/exclusion
- **Large Files**: Efficient processing and memory management
- **Unusual Formats**: Graceful fallback and error reporting

#### Architecture

```swift
final class FormatsViewModel: ObservableObject {
    @Published var supportedImageFormats: Set<String>
    @Published var enableImageProcessing: Bool
    @Published var handleCorruptedFiles: Bool

    private let scanService = ServiceManager.shared.scanService

    init() {
        loadSupportedFormats()
        loadSettings()
    }

    private func loadSupportedFormats() {
        supportedImageFormats = Set([
            "jpg", "jpeg", "png", "gif", "bmp", "tiff",
            "webp", "heic", "heif", "raw", "cr2", "nef", "arw"
        ])
    }
}
```

### Verification

- All supported formats are correctly identified
- Edge cases are handled without crashes
- Quality thresholds work as expected
- Batch processing handles large volumes efficiently

### See Also — External References

- [Established] Apple — File System Programming: `https://developer.apple.com/documentation/foundation/file_system_programming_guide`
- [Established] Apple — Uniform Type Identifiers: `https://developer.apple.com/documentation/uniformtypeidentifiers`
- [Cutting-edge] File Format Analysis: `https://en.wikipedia.org/wiki/File_format`