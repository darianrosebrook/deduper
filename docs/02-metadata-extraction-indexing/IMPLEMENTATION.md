## 02 · Metadata Extraction & Indexing — Implementation Plan
Author: @darianrosebrook

### Objectives

- Read filesystem and media metadata reliably and quickly.
- Normalize values (dates, orientation) and persist them for fast queries.
- Provide secondary indexes for candidate filtering.

### Responsibilities

- Filesystem attributes via FileManager and URL resource values.
- Image metadata via ImageIO; video metadata via AVFoundation.
- Normalization (timezones, EXIF orientation, missing fields defaulting).
- Write-through to persistence layer (see module 06) with change detection.

### Public API (proposed)

- MetadataReader
  - readFor(url: URL, mediaType: MediaType) -> MediaMetadata
  - normalize(meta: MediaMetadata) -> MediaMetadata

- IndexWriter
  - upsert(file: FileRecord, meta: MediaMetadata) -> IndexResult
  - markInvalidated(fileId) for signatures when size/mtime changed

MediaMetadata
- fileName, fileSize, mediaType, createdAt, modifiedAt
- Image: width, height, captureDate, cameraModel, gpsLat, gpsLon, orientation
- Video: durationSec, width, height, frameRate, codec (optional)

### Normalization Rules

- Dates: prefer captureDate (EXIF) → fallback to createdAt → modifiedAt.
- Orientation: apply orientation when computing dimensions for consistency.
- GPS: clamp precision to ~6 decimals; omit if invalid.
- Missing fields: store nil but add derived indexes (e.g., dimension tuple) when possible.

### Safeguards & Failure Handling

- Graceful handling of corrupted EXIF or unsupported containers; return partial metadata.
- Avoid full image decode; use CGImageSource properties only.
- For videos, guard short/zero duration; handle timescale differences.
- Early return if file changed mid-read (re-stat before commit).

### Secondary Indexes (module 06 persistence)

- fileSize, (width,height), durationSec, captureDate.
- Composite indexes where beneficial (e.g., (width,height,mediaType)).

### Verification

- Unit: EXIF parser on fixtures; AVAsset duration/resolution on clips.
- Integration: mixed set scan populates index; random samples match ground truth.
- Mutation: touch file mtime/size → only affected fields updated; others unchanged.

### Metrics & Observability

- OSLog categories: metadata, index.
- Throughput target ≥ 500 files/sec on Medium dataset.

### Risks & Mitigations
### Pseudocode

```swift
struct MediaMetadata {
    var fileName: String
    var fileSize: Int64
    var mediaType: MediaType
    var createdAt: Date?
    var modifiedAt: Date?
    var dimensions: (width: Int, height: Int)?
    var captureDate: Date?
    var cameraModel: String?
    var gpsLat: Double?
    var gpsLon: Double?
    var durationSec: Double?
}

func readFor(url: URL, mediaType: MediaType) -> MediaMetadata {
    var meta = MediaMetadata(fileName: url.lastPathComponent, fileSize: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0, mediaType: mediaType, createdAt: (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate), modifiedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate), dimensions: nil, captureDate: nil, cameraModel: nil, gpsLat: nil, gpsLon: nil, durationSec: nil)
    if mediaType == .photo {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int { meta.dimensions = (w, h) }
            if let t = (props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String { meta.captureDate = parseEXIFDate(t) }
            meta.cameraModel = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String
            if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
                meta.gpsLat = gps[kCGImagePropertyGPSLatitude] as? Double
                meta.gpsLon = gps[kCGImagePropertyGPSLongitude] as? Double
            }
        }
    } else {
        let asset = AVAsset(url: url)
        meta.durationSec = asset.duration.seconds
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            meta.dimensions = (Int(abs(size.width)), Int(abs(size.height)))
        }
    }
    return normalize(meta: meta)
}

func normalize(meta: MediaMetadata) -> MediaMetadata {
    var m = meta
    if m.captureDate == nil { m.captureDate = m.createdAt ?? m.modifiedAt }
    if let lat = m.gpsLat, let lon = m.gpsLon {
        m.gpsLat = round(lat * 1_000_000) / 1_000_000
        m.gpsLon = round(lon * 1_000_000) / 1_000_000
    }
    return m
}
```


### See Also — External References

- [Established] Apple — Image I/O: `https://developer.apple.com/documentation/imageio`
- [Established] Apple — AVFoundation: `https://developer.apple.com/documentation/avfoundation`
- [Established] Apple — UniformTypeIdentifiers: `https://developer.apple.com/documentation/uniformtypeidentifiers`
- [Established] EXIF Tag Reference (EXIF.org): `https://exif.org/Exif2-2.PDF`
- [Cutting-edge] HEIC/HEIF metadata caveats (WWDC talk): `https://developer.apple.com/videos/` (search “HEIF and HEVC”)

- Inconsistent EXIF across vendors → robust key mapping; test against diverse fixtures.
- Large RAW files → avoid decode; skip image hashing until needed.


