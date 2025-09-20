## Glossary & Data Dictionary
Author: @darianrosebrook

### Terms

- Duplicate (Exact): Byte-identical files (SHA256 and size match).
- Visually Similar: Files whose visual content matches within perceptual hash thresholds.
- Keeper: The file retained after merge, possibly enriched with metadata.
- Group: Set of files considered duplicates/similar by the engine.
- Evidence Panel: UI section listing signals, distances, thresholds, and weights used.
- Placeholder (Cloud): File stub not fully present locally (e.g., iCloud status not current).

### Entities

- File
  - id: UUID
  - path: String (canonicalized); bookmarkData: Data
  - fileSize: Int64 (bytes)
  - createdAt, modifiedAt: Date
  - mediaType: {photo, video}
  - inodeOrFileId: String
  - checksumSHA256: String (hex)
  - isTrashed: Bool

- ImageSignature
  - fileId: UUID (FK)
  - width, height: Int
  - hashType: {aHash, dHash, pHash}
  - hash64: UInt64
  - computedAt: Date

- VideoSignature
  - fileId: UUID (FK)
  - durationSec: Double (seconds)
  - width, height: Int
  - frameHashes: [UInt64]
  - computedAt: Date

- Metadata
  - fileId: UUID (FK)
  - captureDate: Date
  - cameraModel: String
  - gpsLat, gpsLon: Double (clamped to 6 decimals)
  - keywords: [String]
  - exifBlob: Data

- DuplicateGroup
  - id: UUID
  - createdAt: Date
  - status: {open, resolved}
  - rationale: String (human-readable summary)

- GroupMember
  - groupId: UUID (FK)
  - fileId: UUID (FK)
  - isKeeperSuggestion: Bool
  - hammingDistance: Int
  - nameSimilarity: Double [0.0–1.0]

- UserDecision
  - groupId: UUID (FK)
  - keeperFileId: UUID (FK)
  - action: {merge, skip}
  - mergedFields: {String: Any}
  - performedAt: Date

- Preference
  - key: String
  - value: Any (JSON)

### Units & Ranges

- Dimensions: pixels (Int, ≥ 1)
- Duration: seconds (Double, ≥ 0.0)
- Hamming Distance: Int [0–64]
- Name Similarity: Double [0.0–1.0]

### Normalization Rules (Authoritative)

- Dates: prefer EXIF DateTimeOriginal → createdAt → modifiedAt.
- GPS: drop if components missing; else clamp to 6 decimals.
- Paths: canonicalize, normalize Unicode (NFC), resolve aliases/symlinks.
- Live Photos: link HEIC+MOV by base name and timestamp proximity.


