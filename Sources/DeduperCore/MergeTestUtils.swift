import Foundation
import ImageIO
import CoreGraphics

/**
 * Test utilities for merge functionality including fixture creation and validation.
 *
 * - Author: @darianrosebrook
 */
public final class MergeTestUtils {

    // MARK: - Test Fixtures

    /**
     * Creates a test image with EXIF metadata for testing merge operations.
     */
    public static func createTestImageWithEXIF(
        width: Int = 1920,
        height: Int = 1080,
        captureDate: Date = Date(timeIntervalSince1970: 1640995200), // 2022-01-01 00:00:00 UTC
        gpsLat: Double = 37.7749,
        gpsLon: Double = -122.4194,
        cameraModel: String = "Test Camera",
        keywords: [String] = ["test", "fixture", "merge"]
    ) -> Data? {
        // Create a simple test image (RGB bitmap)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        // Fill with a gradient pattern for visual distinction
        for y in 0..<height {
            for x in 0..<width {
                let r = UInt8((x * 255) / width)
                let g = UInt8((y * 255) / height)
                let b = UInt8(((x + y) * 255) / (width + height))
                context.setFillColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }

        guard let cgImage = context.makeImage() else {
            return nil
        }

        // Create EXIF metadata
        let exifProperties: [CFString: Any] = [
            kCGImagePropertyExifDateTimeOriginal: formatEXIFDate(captureDate),
            kCGImagePropertyExifUserComment: "Test fixture for merge testing"
        ]

        let gpsProperties: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: gpsLat,
            kCGImagePropertyGPSLongitude: gpsLon,
            kCGImagePropertyGPSLatitudeRef: gpsLat >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitudeRef: gpsLon >= 0 ? "E" : "W"
        ]

        let tiffProperties: [CFString: Any] = [
            kCGImagePropertyTIFFModel: cameraModel
        ]

        let iptcProperties: [CFString: Any] = [
            kCGImagePropertyIPTCKeywords: keywords
        ]

        let metadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: exifProperties,
            kCGImagePropertyGPSDictionary: gpsProperties,
            kCGImagePropertyTIFFDictionary: tiffProperties,
            kCGImagePropertyIPTCDictionary: iptcProperties
        ]

        // Create image destination
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }

        // Add image with metadata
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    /**
     * Creates a test image without EXIF metadata for testing merge operations.
     */
    public static func createTestImageWithoutEXIF(
        width: Int = 1280,
        height: Int = 720
    ) -> Data? {
        // Create a simple test image (RGB bitmap)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        // Fill with a solid color pattern
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.8, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            return nil
        }

        // Create image destination without metadata
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }

        // Add image without metadata
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }

    /**
     * Creates test files for merge testing scenarios.
     */
    public static func createTestScenario(
        directory: URL,
        highResWithoutEXIF: Bool = true,
        lowResWithEXIF: Bool = true
    ) throws -> [URL] {
        var createdFiles: [URL] = []

        if highResWithoutEXIF {
            let highResData = createTestImageWithoutEXIF(width: 1920, height: 1080)
            let highResURL = directory.appendingPathComponent("high_res_no_exif.jpg")
            try highResData?.write(to: highResURL)
            createdFiles.append(highResURL)
        }

        if lowResWithEXIF {
            let lowResData = createTestImageWithEXIF(
                width: 800,
                height: 600,
                captureDate: Date(timeIntervalSince1970: 1640995200),
                gpsLat: 37.7749,
                gpsLon: -122.4194,
                cameraModel: "iPhone 13",
                keywords: ["san francisco", "test", "fixture"]
            )
            let lowResURL = directory.appendingPathComponent("low_res_with_exif.jpg")
            try lowResData?.write(to: lowResURL)
            createdFiles.append(lowResURL)
        }

        return createdFiles
    }

    // MARK: - Validation Helpers

    /**
     * Validates that a merge operation produced the expected results.
     */
    public static func validateMergeResult(
        keeperURL: URL,
        expectedCaptureDate: Date?,
        expectedGPSLat: Double?,
        expectedGPSLon: Double?,
        expectedKeywords: [String]?
    ) -> Bool {
        guard let imageSource = CGImageSourceCreateWithURL(keeperURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return false
        }

        // Check EXIF data
        if let expectedCaptureDate = expectedCaptureDate {
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                    if parseEXIFDate(dateStr) != expectedCaptureDate {
                        return false
                    }
                } else {
                    return false
                }
            } else {
                return false
            }
        }

        // Check GPS data
        if expectedGPSLat != nil || expectedGPSLon != nil {
            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
                if let lat = gps[kCGImagePropertyGPSLatitude] as? Double {
                    if lat != expectedGPSLat { return false }
                } else if expectedGPSLat != nil {
                    return false
                }

                if let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
                    if lon != expectedGPSLon { return false }
                } else if expectedGPSLon != nil {
                    return false
                }
            } else if expectedGPSLat != nil || expectedGPSLon != nil {
                return false
            }
        }

        // Check IPTC keywords
        if let expectedKeywords = expectedKeywords {
            if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
                if let keywords = iptc[kCGImagePropertyIPTCKeywords] as? [String] {
                    let sortedKeywords = keywords.sorted()
                    let sortedExpected = expectedKeywords.sorted()
                    if sortedKeywords != sortedExpected {
                        return false
                    }
                } else {
                    return false
                }
            } else {
                return false
            }
        }

        return true
    }

    // MARK: - Private Helpers

    private static func formatEXIFDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func parseEXIFDate(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let d = formatter.date(from: str) { return d }
        // Try ISO fallback
        let iso = ISO8601DateFormatter()
        return iso.date(from: str)
    }
}

// MARK: - Test Extensions

extension MergeResult {
    public var description: String {
        return "MergeResult(groupId: \(groupId), keeperId: \(keeperId), removedFileIds: \(removedFileIds.count), mergedFields: \(mergedFields), wasDryRun: \(wasDryRun))"
    }
}

extension UndoResult {
    public var description: String {
        return "UndoResult(transactionId: \(transactionId), restoredFileIds: \(restoredFileIds.count), revertedFields: \(revertedFields), success: \(success))"
    }
}

extension MergePlan {
    public var description: String {
        return "MergePlan(groupId: \(groupId), keeperId: \(keeperId), exifWrites: \(exifWrites.count) fields, trashList: \(trashList.count) files, fieldChanges: \(fieldChanges.count))"
    }
}
