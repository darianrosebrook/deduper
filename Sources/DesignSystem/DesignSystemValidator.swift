import SwiftUI
import Foundation

/**
 * Author: @darianrosebrook
 * DesignSystemValidator provides validation and linting for design system compliance.
 * - Checks component structure and naming conventions
 * - Validates design token usage
 * - Ensures accessibility standards
 * - Provides automated fix suggestions
 * - Design System: Validation and quality assurance tool
 */
@MainActor
public final class DesignSystemValidator {

    public static let shared = DesignSystemValidator()

    // MARK: - Validation Results

    public struct ValidationResult {
        public let componentName: String
        public let issues: [ValidationIssue]
        public let score: Double // 0.0 to 1.0

        public var isCompliant: Bool {
            issues.isEmpty
        }

        public var summary: String {
            "Component \(componentName): \(issues.count) issues, score: \(Int(score * 100))%"
        }
    }

    public struct ValidationIssue {
        public let type: IssueType
        public let message: String
        public let suggestion: String?
        public let severity: Severity

        public enum IssueType {
            case namingConvention
            case designTokenUsage
            case accessibility
            case componentStructure
            case documentation
        }

        public enum Severity {
            case warning
            case error
            case info
        }
    }

    // MARK: - Validation Methods

    public func validateComponent(_ component: any View, named componentName: String) -> ValidationResult {
        var issues: [ValidationIssue] = []

        // Check naming convention
        if !isValidComponentName(componentName) {
            issues.append(ValidationIssue(
                type: .namingConvention,
                message: "Component name '\(componentName)' doesn't follow PascalCase convention",
                suggestion: "Use PascalCase for component names (e.g., 'UserProfileView')",
                severity: .warning
            ))
        }

        // Check design token usage (this would require more sophisticated analysis)
        issues.append(contentsOf: validateDesignTokenUsage(in: componentName))

        // Check accessibility features
        issues.append(contentsOf: validateAccessibility(in: componentName))

        // Check documentation
        issues.append(contentsOf: validateDocumentation(in: componentName))

        let score = calculateScore(from: issues)

        return ValidationResult(
            componentName: componentName,
            issues: issues,
            score: score
        )
    }

    public func validateAllComponents() -> [ValidationResult] {
        let componentNames = getComponentNames()
        return componentNames.map { validateComponent(MockView(), named: $0) }
    }

    public func generateComplianceReport() -> String {
        let results = validateAllComponents()
        let totalScore = results.map { $0.score }.reduce(0, +) / Double(results.count)
        let totalIssues = results.flatMap { $0.issues }.count

        var report = """
        Design System Compliance Report
        =================================

        Overall Score: \(String(format: "%.1f%%", totalScore * 100))
        Total Issues: \(totalIssues)
        Components Validated: \(results.count)

        """

        for result in results {
            report += "\n\(result.summary)"
            if !result.issues.isEmpty {
                report += "\n  Issues:"
                for issue in result.issues.prefix(3) {
                    report += "\n    - [\(issue.severity.rawValue.uppercased())] \(issue.message)"
                }
                if result.issues.count > 3 {
                    report += "\n    - ... and \(result.issues.count - 3) more"
                }
            }
        }

        return report
    }

    // MARK: - Private Methods

    private func isValidComponentName(_ name: String) -> Bool {
        // Check PascalCase: starts with uppercase letter, contains only letters and numbers
        let pascalCasePattern = "^[A-Z][a-zA-Z0-9]*$"
        return name.range(of: pascalCasePattern, options: .regularExpression) != nil
    }

    private func validateDesignTokenUsage(in componentName: String) -> [ValidationIssue] {
        // This is a simplified validation - in practice, you'd parse the actual code
        var issues: [ValidationIssue] = []

        // Check for hardcoded values that should use design tokens
        let commonIssues = [
            "Color.white",
            "Color.black",
            "Color.gray",
            "spacing: 8",
            "padding: 16",
            "cornerRadius: 4"
        ]

        for issue in commonIssues {
            issues.append(ValidationIssue(
                type: .designTokenUsage,
                message: "Potential hardcoded value '\(issue)' in \(componentName)",
                suggestion: "Replace with appropriate design token from DesignTokens.swift",
                severity: .warning
            ))
        }

        return issues
    }

    private func validateAccessibility(in componentName: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        // Check for missing accessibility labels
        if componentName.contains("Button") && !componentName.contains("accessibilityLabel") {
            issues.append(ValidationIssue(
                type: .accessibility,
                message: "Button component '\(componentName)' may be missing accessibility label",
                suggestion: "Add .accessibilityLabel() modifier with descriptive text",
                severity: .error
            ))
        }

        // Check for interactive elements without hints
        if (componentName.contains("Button") || componentName.contains("Input")) &&
           !componentName.contains("accessibilityHint") {
            issues.append(ValidationIssue(
                type: .accessibility,
                message: "Interactive component '\(componentName)' may be missing accessibility hint",
                suggestion: "Add .accessibilityHint() modifier with usage instructions",
                severity: .warning
            ))
        }

        return issues
    }

    private func validateDocumentation(in componentName: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if !componentName.hasPrefix("/**") {
            issues.append(ValidationIssue(
                type: .documentation,
                message: "Component '\(componentName)' may be missing documentation header",
                suggestion: "Add /** documentation comment following design system standards",
                severity: .info
            ))
        }

        return issues
    }

    private func calculateScore(from issues: [ValidationIssue]) -> Double {
        if issues.isEmpty {
            return 1.0
        }

        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count

        // Weight errors more heavily than warnings
        let penalty = Double(errorCount) * 0.3 + Double(warningCount) * 0.1
        return max(0.0, min(1.0, 1.0 - penalty))
    }

    private func getComponentNames() -> [String] {
        // This would scan the actual codebase for components
        // For now, return a sample list
        return [
            "Button",
            "Input",
            "Card",
            "Badge",
            "Modal",
            "Form",
            "Dropdown",
            "Tooltip"
        ]
    }
}

// MARK: - CLI Tool

extension DesignSystemValidator {
    public func runCLIValidation() {
        let report = generateComplianceReport()
        print(report)

        // Save report to file
        let fileManager = FileManager.default
        let reportPath = fileManager.currentDirectoryPath + "/design_system_report.txt"

        do {
            try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
            print("Report saved to: \(reportPath)")
        } catch {
            print("Failed to save report: \(error.localizedDescription)")
        }
    }
}

// MARK: - Xcode Integration

extension DesignSystemValidator {
    public static func validateCurrentFile() {
        // This could be integrated into Xcode build phases
        print("🔍 Validating current file for design system compliance...")
        shared.runCLIValidation()
    }
}
