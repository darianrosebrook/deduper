## Error Codes & UX Copy
Author: @darianrosebrook

### Taxonomy

- UserError (actionable): caused by missing permission, invalid selection, or user decisions.
- SystemError (environment): sandbox, disk I/O, cloud placeholders, external media.
- InternalError (bugs): invariant violations, unexpected nil, logic errors.

### Format

Code: `DEDUPER/<area>/<code>` — short title — user-facing message

### Codes

- DEDUPER/ACCESS/BOOKMARK_DENIED — Access not granted — We couldn’t access one or more selected folders. Re-authorize to continue.
- DEDUPER/ACCESS/BOOKMARK_STALE — Access expired — Folder access expired. Re-select the folder to renew permissions.
- DEDUPER/SCAN/MANAGED_LIBRARY — Managed library detected — This is a Photos/Lightroom library. Use the guided export → dedupe → re-import workflow.
- DEDUPER/SCAN/CLOUD_PLACEHOLDER — Cloud item not downloaded — This file is not available locally. Download first or enable fetching in Settings.
- DEDUPER/SCAN/UNREADABLE_FILE — Can’t read file — We couldn’t read this file. It was skipped.
- DEDUPER/META/EXIF_CORRUPT — Image metadata unreadable — We couldn’t parse EXIF for this image. Comparison will rely on other signals.
- DEDUPER/VIDEO/FRAME_EXTRACT_FAIL — Frame extraction failed — We couldn’t extract frames from this video. Comparison will rely on duration and metadata.
- DEDUPER/HASH/COMPUTE_FAIL — Hash computation failed — We couldn’t compute a visual hash. The file will be compared by other signals.
- DEDUPER/GROUP/NO_CANDIDATES — No groups found — No duplicates or similar items were found for the current selection.
- DEDUPER/MERGE/NO_KEEPER — Keeper not selected — Choose a file to keep before merging.
- DEDUPER/MERGE/EXIF_WRITE_FAIL — Metadata update failed — We couldn’t update the keeper’s metadata. No changes were saved.
- DEDUPER/MERGE/TRASH_FAIL — Move to Trash failed — We couldn’t move one or more files to Trash. Check permissions and try again.
- DEDUPER/UNDO/NO_TRANSACTION — Nothing to undo — There’s no recent merge to undo.
- DEDUPER/UNDO/RESTORE_FAIL — Undo failed — We couldn’t restore all files. Some items may need manual recovery.

### UX Copy Principles

- Simple, precise, and actionable. Offer a next step.
- Avoid jargon; explain what happened, what was affected, and how to fix.
- Consistency: title case for titles, sentence case for messages, no emojis.
- Redaction: don’t show full paths; show base names and parent directories only.

### Usage

- Map module errors to these codes; log the code with `OSLog` and show user copy.
- Include a “Learn more” link to documentation where helpful.


