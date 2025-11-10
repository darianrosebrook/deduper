import SwiftUI
import Foundation
@_exported import DeduperCore

/**
 * Author: @darianrosebrook
 * DesignTokenParser bridges the W3C-compliant design token JSON system to SwiftUI.
 * This parser reads the designTokens.json file and provides proper light/dark mode support.
 * - Supports semantic token resolution with light/dark mode variants
 * - Provides type-safe access to design tokens
 * - Design System: Foundation layer for token-based styling
 */
public final class DesignTokenParser: @unchecked Sendable {

    // MARK: - Properties

    public static let shared = DesignTokenParser()
    private let tokenData: DesignTokenData
    private let rootTokenMap: [String: Any]

    // MARK: - Initialization

    private init() {
        // Try multiple approaches to find the designTokens.json file
        var url: URL?

        // First, try the main bundle
        url = Bundle.main.url(forResource: "designTokens", withExtension: "json")

        // If not found, try to find it in the build directory (for development)
        if url == nil {
            let buildDir = URL(fileURLWithPath: ".build/arm64-apple-macosx/debug/DeduperCore_DeduperCore.bundle")
            let designTokensURL = buildDir.appendingPathComponent("designTokens.json")
            if FileManager.default.fileExists(atPath: designTokensURL.path) {
                url = designTokensURL
            }
        }

        guard let designTokensURL = url else {
            fatalError("designTokens.json not found in bundle. Available bundles: \(Bundle.allBundles.map { $0.bundleIdentifier ?? "main" })")
        }

        do {
            let data = try Data(contentsOf: designTokensURL)
            tokenData = try JSONDecoder().decode(DesignTokenData.self, from: data)
            var root: [String: Any] = [
                "core": tokenData.core,
                "semantic": tokenData.semantic
            ]
            if let components = tokenData.components {
                root["components"] = components
            }
            rootTokenMap = root
        } catch {
            fatalError("Failed to parse designTokens.json: \(error)")
        }
    }

    // MARK: - Public Access

    // Access the singleton via the private static property
    // Note: This is handled by the private static let above

    // MARK: - Color Resolution

    public func resolveColor(_ tokenPath: String, for colorScheme: ColorScheme = .light) -> Color {
        // If it's a reference like {core.color.mode.dark}, resolve it
        if tokenPath.hasPrefix("{") && tokenPath.hasSuffix("}") {
            let referencePath = String(tokenPath.dropFirst().dropLast())
            return resolveTokenPath(referencePath, colorScheme: colorScheme)
        }

        return resolveTokenPath(tokenPath, colorScheme: colorScheme)
    }

    private func resolveTokenPath(_ tokenPath: String, colorScheme: ColorScheme = .light) -> Color {
        guard let current = tokenValue(for: tokenPath) else {
            return Color.white
        }

        return resolveTokenValue(current, colorScheme: colorScheme)
    }

    private func tokenValue(for tokenPath: String) -> Any? {
        let components = tokenPath.split(separator: ".").map(String.init)

        guard components.count >= 2 else {
            return nil
        }

        var current: Any = rootTokenMap

        for component in components {
            switch current {
            case let dict as [String: Any]:
                guard let next = dict[component] else {
                    return nil
                }
                current = next
            case let array as [Any]:
                guard let index = Int(component), index < array.count else {
                    return nil
                }
                current = array[index]
            default:
                return nil
            }
        }

        return current
    }

    private func resolveTokenValue(_ value: Any, colorScheme: ColorScheme = .light) -> Color {
        if let colorString = resolveColorStringValue(value, colorScheme: colorScheme) {
            return Color(tokenValue: colorString)
        }

        return Color.white
    }

    private func resolveColorStringValue(_ value: Any, colorScheme: ColorScheme = .light) -> String? {
        if let colorDict = value as? [String: Any] {
            let modeKey = colorScheme == .dark ? "dark" : "light"

            if let extensions = colorDict["$extensions"] as? [String: Any] {
                // Check for nested design.paths structure first
                if let designPaths = extensions["design.paths"] as? [String: Any],
                   let modeColor = designPaths[modeKey] as? String {
                    return resolveColorReference(modeColor, colorScheme: colorScheme)
                }

                // Check for flat design.paths.{mode} structure
                if let flatModeColor = extensions["design.paths.\(modeKey)"] as? String {
                    return resolveColorReference(flatModeColor, colorScheme: colorScheme)
                }
            }

            if let rawValue = colorDict["$value"] {
                return resolveColorStringValue(rawValue, colorScheme: colorScheme)
            }

            if let modeColor = colorDict[modeKey] as? String {
                return resolveColorReference(modeColor, colorScheme: colorScheme)
            }

            if let fallback = colorDict["default"] as? String {
                return resolveColorReference(fallback, colorScheme: colorScheme)
            }
        }

        if let colorString = value as? String {
            return resolveColorReference(colorString, colorScheme: colorScheme)
        }

        return nil
    }

    private func resolveColorReference(_ tokenString: String, colorScheme: ColorScheme) -> String? {
        let trimmed = tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            let referencePath = String(trimmed.dropFirst().dropLast())
            let result = resolveColorTokenString(referencePath, for: colorScheme)
            return result
        }

        return trimmed
    }

    public func resolveColorTokenString(_ tokenPath: String, for colorScheme: ColorScheme = .light) -> String? {
        // Try the path as-is first
        if let current = tokenValue(for: tokenPath) {
            return resolveColorStringValue(current, colorScheme: colorScheme)
        }
        
        // If not found and path doesn't start with "core." or "semantic.", try with "core." prefix
        if !tokenPath.hasPrefix("core.") && !tokenPath.hasPrefix("semantic.") {
            if let current = tokenValue(for: "core.\(tokenPath)") {
                return resolveColorStringValue(current, colorScheme: colorScheme)
            }
            // Try with "semantic." prefix
            if let current = tokenValue(for: "semantic.\(tokenPath)") {
                return resolveColorStringValue(current, colorScheme: colorScheme)
            }
        }
        
        return nil
    }

    // MARK: - Dimension Resolution

    public func resolveDimension(_ tokenPath: String) -> CGFloat {
        // If it's a reference like {core.spacing.size.02}, resolve it
        if tokenPath.hasPrefix("{") && tokenPath.hasSuffix("}") {
            let referencePath = String(tokenPath.dropFirst().dropLast())
            return resolveDimensionPath(referencePath)
        }

        return resolveDimensionPath(tokenPath)
    }

    private func resolveDimensionPath(_ tokenPath: String) -> CGFloat {
        guard let current = tokenValue(for: tokenPath) else {
            return 0
        }

        return resolveDimensionValue(current)
    }

    private func resolveDimensionValue(_ value: Any) -> CGFloat {
        if let dict = value as? [String: Any] {
            if let rawValue = dict["$value"] {
                return resolveDimensionValue(rawValue)
            }

            if let `default` = dict["default"] {
                return resolveDimensionValue(`default`)
            }
        }

        // If it's a direct string value
        if let dimensionString = value as? String {
            // If the string is a reference, resolve it recursively
            if dimensionString.hasPrefix("{") && dimensionString.hasSuffix("}") {
                let referencePath = String(dimensionString.dropFirst().dropLast())
                return resolveDimensionPath(referencePath)
            }

            // Extract numeric value from strings like "16px"
            if let numericValue = Double(dimensionString.replacingOccurrences(of: "px", with: "")) {
                return CGFloat(numericValue)
            }
        }

        // If it's a direct number
        if let numericValue = value as? Double {
            return CGFloat(numericValue)
        }

        if let numericValue = value as? Int {
            return CGFloat(numericValue)
        }

        return 0 // Fallback
    }

    // MARK: - Font Weight Resolution

    public func resolveFontWeight(_ tokenPath: String) -> Font.Weight {
        // If it's a reference like {core.typography.weight.medium}, resolve it
        if tokenPath.hasPrefix("{") && tokenPath.hasSuffix("}") {
            let referencePath = String(tokenPath.dropFirst().dropLast())
            return resolveFontWeightPath(referencePath)
        }

        return resolveFontWeightPath(tokenPath)
    }

    private func resolveFontWeightPath(_ tokenPath: String) -> Font.Weight {
        guard let current = tokenValue(for: tokenPath) else {
            return .regular
        }

        return resolveFontWeightValue(current)
    }

    private func resolveFontWeightValue(_ value: Any) -> Font.Weight {
        if let dict = value as? [String: Any], let rawValue = dict["$value"] {
            return resolveFontWeightValue(rawValue)
        }

        if let numericValue = value as? Double {
            return fontWeight(from: numericValue)
        }

        if let weightString = value as? String {
            if weightString.hasPrefix("{") && weightString.hasSuffix("}") {
                let referencePath = String(weightString.dropFirst().dropLast())
                return resolveFontWeightPath(referencePath)
            }

            return fontWeight(from: weightString)
        }

        return .regular // Fallback
    }

    private func fontWeight(from value: Any) -> Font.Weight {
        if let number = value as? Double {
            switch Int(number) {
            case 100: return .thin
            case 300: return .light
            case 400: return .regular
            case 500: return .medium
            case 600: return .semibold
            case 700: return .bold
            case 800: return .heavy
            case 900: return .black
            default: return .regular
            }
        }

        if let string = value as? String {
            switch string.lowercased() {
            case "100", "thin": return .thin
            case "300", "light": return .light
            case "400", "regular": return .regular
            case "500", "medium": return .medium
            case "600", "semibold": return .semibold
            case "700", "bold": return .bold
            case "800", "heavy": return .heavy
            case "900", "black": return .black
            default: return .regular
            }
        }

        return .regular
    }

    // MARK: - Shadow Resolution (Temporarily Disabled)

    // TODO: Implement shadow resolution once we have proper SwiftUI.Shadow support
    // For now, return a default shadow
    public func resolveShadow(_ tokenPath: String) -> DesignTokenShadow {
        return DesignTokenShadow(color: .black, radius: 0, x: 0, y: 0)
    }

    // MARK: - Border Radius Resolution

    public func resolveBorderRadius(_ tokenPath: String) -> CGFloat {
        return resolveDimension(tokenPath)
    }

    // MARK: - Border Width Resolution

    public func resolveBorderWidth(_ tokenPath: String) -> CGFloat {
        return resolveDimension(tokenPath)
    }
}

// MARK: - Data Structures

private struct DesignTokenData: Decodable {
    let core: [String: Any]
    let semantic: [String: Any]
    let components: [String: Any]?

    // Custom decoding to handle Any types
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // For core, semantic, and components, we need to decode them as raw JSON
        // and then convert to [String: Any]
        let coreValue = try container.decode(JSONValue.self, forKey: .core)
        core = try coreValue.toAny() as! [String: Any]

        let semanticValue = try container.decode(JSONValue.self, forKey: .semantic)
        semantic = try semanticValue.toAny() as! [String: Any]

        if let componentsValue = try container.decodeIfPresent(JSONValue.self, forKey: .components) {
            components = try componentsValue.toAny() as! [String: Any]
        } else {
            components = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case core
        case semantic
        case components
    }
}

// Helper enum to decode arbitrary JSON
private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case object([String: JSONValue])
    case array([JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    func toAny() throws -> Any {
        switch self {
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = try value.toAny()
            }
            return result
        case .array(let array):
            return try array.map { try $0.toAny() }
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let bool):
            return bool
        case .null:
            return NSNull()
        }
    }
}



// MARK: - ColorScheme Environment Extension

extension EnvironmentValues {
    var colorScheme: ColorScheme {
        get { self[ColorSchemeKey.self] }
        set { self[ColorSchemeKey.self] = newValue }
    }
}

private struct ColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}
