#!/bin/bash

# Mutation Testing Script for Deduper
# 
# Author: @darianrosebrook
# 
# This script runs mutation testing analysis on critical components.
# Currently uses manual mutation analysis approach until Mull or similar tool is integrated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Mutation Testing Analysis for Deduper"
echo "======================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Target components for mutation testing
TARGET_COMPONENTS=(
    "Sources/DeduperCore/DuplicateDetectionEngine.swift"
    "Sources/DeduperCore/MergeService.swift"
    "Sources/DeduperCore/DuplicateDetectionEngine.swift:ConfidenceCalculator"
)

# Mutation operators to check
MUTATION_PATTERNS=(
    "\\+.*-|\\-.*\\+|\\*.*/|/.*\\*"  # Arithmetic operator changes
    "==.*!=|!=.*=="  # Comparison operator changes
    "&&.*\\|\\||\\|\\|.*&&"  # Logical operator changes
    "if.*>.*if.*<|if.*<.*if.*>"  # Conditional boundary changes
)

# Function to analyze mutation potential
analyze_mutation_potential() {
    local file="$1"
    local component_name=$(basename "$file" .swift)
    
    echo "Analyzing: $component_name"
    echo "----------------------------------------"
    
    # Count testable functions
    local function_count=$(grep -c "^[[:space:]]*func\|^[[:space:]]*private func\|^[[:space:]]*public func" "$file" 2>/dev/null || echo "0")
    echo "  Functions: $function_count"
    
    # Count test files
    local test_file="Tests/DeduperCoreTests/${component_name}Tests.swift"
    if [ -f "$test_file" ]; then
        local test_count=$(grep -c "@Test\|func test" "$test_file" 2>/dev/null || echo "0")
        echo "  Tests: $test_count"
        
        # Calculate test-to-function ratio
        if [ "$function_count" -gt 0 ]; then
            local ratio=$(echo "scale=2; $test_count / $function_count" | bc)
            echo "  Test/Function Ratio: $ratio"
        fi
    else
        echo "  Tests: 0 (no test file found)"
    fi
    
    # Check for mutation-prone patterns
    local mutation_risks=0
    for pattern in "${MUTATION_PATTERNS[@]}"; do
        local matches=$(grep -E "$pattern" "$file" 2>/dev/null | wc -l || echo "0")
        mutation_risks=$((mutation_risks + matches))
    done
    
    echo "  Mutation-Prone Patterns: $mutation_risks"
    echo ""
}

# Function to check if Mull is available
check_mull_availability() {
    if command -v mull-cxx &> /dev/null; then
        echo "Mull framework detected"
        return 0
    else
        echo "Mull framework not available - using manual analysis"
        return 1
    fi
}

# Function to run manual mutation analysis
run_manual_analysis() {
    echo "Running Manual Mutation Analysis"
    echo "================================="
    echo ""
    echo "This analysis identifies areas where mutations would likely survive"
    echo "due to weak test coverage or missing assertions."
    echo ""
    
    for component in "${TARGET_COMPONENTS[@]}"; do
        if [[ "$component" == *":"* ]]; then
            # Component with specific class
            local file=$(echo "$component" | cut -d: -f1)
            local class=$(echo "$component" | cut -d: -f2)
            if [ -f "$file" ]; then
                echo "Component: $class in $file"
                analyze_mutation_potential "$file"
            fi
        else
            # Regular file
            if [ -f "$component" ]; then
                analyze_mutation_potential "$component"
            fi
        fi
    done
}

# Function to generate mutation test report
generate_report() {
    local report_file="mutation-test-report.md"
    
    cat > "$report_file" << EOF
# Mutation Testing Report

**Generated:** $(date)
**Author:** @darianrosebrook

## Summary

This report provides mutation testing analysis for critical Deduper components.

## Analysis Method

- Manual mutation analysis
- Pattern-based risk assessment
- Test coverage analysis

## Target Components

EOF

    for component in "${TARGET_COMPONENTS[@]}"; do
        echo "- \`$component\`" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Recommendations

1. **Improve Test Assertions**: Add more specific assertions to catch mutations
2. **Increase Test Coverage**: Target 80%+ line coverage for Tier 1 components
3. **Add Edge Case Tests**: Test boundary conditions and error paths
4. **Verify Return Values**: Ensure tests verify exact return values, not just non-nil

## Next Steps

1. Evaluate Mull framework for automated mutation testing
2. Create custom mutation scripts for common patterns
3. Run mutation analysis on Tier 1 components
4. Improve tests to achieve target mutation scores (70%+ for Tier 1)

EOF

    echo "Report generated: $report_file"
}

# Main execution
main() {
    echo "Starting mutation testing analysis..."
    echo ""
    
    if check_mull_availability; then
        echo "Using Mull framework for mutation testing"
        # TODO: Integrate Mull when available
    else
        run_manual_analysis
    fi
    
    generate_report
    
    echo ""
    echo "Mutation testing analysis complete"
    echo ""
    echo "Note: Full mutation testing requires Mull framework or custom implementation."
    echo "Current analysis provides manual assessment and recommendations."
}

main "$@"

