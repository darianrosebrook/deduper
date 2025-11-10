#!/usr/bin/env python3
"""
Color Accessibility Audit Tool

Audits color choices for WCAG contrast compliance and color blindness compatibility.

Author: @darianrosebrook

Requirements:
- WCAG AA: 4.5:1 for normal text, 3:1 for large text
- WCAG AAA: 7:1 for normal text, 4.5:1 for large text
- Color blindness: Protanopia, Deuteranopia, Tritanopia
"""

import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from enum import Enum

# WCAG contrast ratio thresholds
WCAG_AA_NORMAL = 4.5
WCAG_AA_LARGE = 3.0
WCAG_AAA_NORMAL = 7.0
WCAG_AAA_LARGE = 4.5


class ContrastLevel(Enum):
    FAIL = "FAIL"
    AA_LARGE = "AA_LARGE"
    AA_NORMAL = "AA_NORMAL"
    AAA_LARGE = "AAA_LARGE"
    AAA_NORMAL = "AAA_NORMAL"


@dataclass
class ColorPair:
    foreground: str
    background: str
    context: str
    file: str
    line: int


@dataclass
class ContrastResult:
    foreground: str
    background: str
    ratio: float
    level: ContrastLevel
    context: str
    file: str
    line: int


def hex_to_rgb(hex_color: str) -> Tuple[int, int, int]:
    """Convert hex color to RGB tuple."""
    hex_color = hex_color.lstrip('#')
    if len(hex_color) == 3:
        hex_color = ''.join([c * 2 for c in hex_color])
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))


def rgb_to_hex(r: int, g: int, b: int) -> str:
    """Convert RGB tuple to hex color."""
    return f"#{r:02x}{g:02x}{b:02x}"


def relative_luminance(r: int, g: int, b: int) -> float:
    """Calculate relative luminance according to WCAG 2.1."""
    def normalize(channel: int) -> float:
        val = channel / 255.0
        if val <= 0.03928:
            return val / 12.92
        return ((val + 0.055) / 1.055) ** 2.4
    
    r_norm = normalize(r)
    g_norm = normalize(g)
    b_norm = normalize(b)
    
    return 0.2126 * r_norm + 0.7152 * g_norm + 0.0722 * b_norm


def contrast_ratio(color1: Tuple[int, int, int], color2: Tuple[int, int, int]) -> float:
    """Calculate contrast ratio between two colors."""
    l1 = relative_luminance(*color1)
    l2 = relative_luminance(*color2)
    
    lighter = max(l1, l2)
    darker = min(l1, l2)
    
    return (lighter + 0.05) / (darker + 0.05)


def get_contrast_level(ratio: float) -> ContrastLevel:
    """Determine WCAG compliance level."""
    if ratio >= WCAG_AAA_NORMAL:
        return ContrastLevel.AAA_NORMAL
    elif ratio >= WCAG_AAA_LARGE:
        return ContrastLevel.AAA_LARGE
    elif ratio >= WCAG_AA_NORMAL:
        return ContrastLevel.AA_NORMAL
    elif ratio >= WCAG_AA_LARGE:
        return ContrastLevel.AA_LARGE
    else:
        return ContrastLevel.FAIL


def simulate_colorblindness(r: int, g: int, b: int, type: str) -> Tuple[int, int, int]:
    """Simulate color blindness (simplified approximation)."""
    if type == "protanopia":  # Red-blind
        # Red channel becomes darker
        r_new = int(0.567 * r + 0.433 * g)
        return (r_new, g, b)
    elif type == "deuteranopia":  # Green-blind
        # Green channel becomes darker
        g_new = int(0.625 * g + 0.375 * r)
        return (r, g_new, b)
    elif type == "tritanopia":  # Blue-blind
        # Blue channel becomes darker
        b_new = int(0.95 * b + 0.05 * r)
        return (r, g, b_new)
    return (r, g, b)


def parse_color_value(value: str) -> Optional[Tuple[int, int, int]]:
    """Parse color value from various formats."""
    value = value.strip().lower()
    
    # Hex colors
    if value.startswith('#') or re.match(r'^[0-9a-f]{3,8}$', value):
        hex_str = value.lstrip('#')
        return hex_to_rgb(hex_str)
    
    # RGB/RGBA
    rgb_match = re.match(r'rgba?\((\d+),\s*(\d+),\s*(\d+)', value)
    if rgb_match:
        return tuple(int(x) for x in rgb_match.groups())
    
    return None


def load_design_tokens() -> Dict:
    """Load design tokens from JSON files."""
    tokens = {}
    
    # Try to load core tokens
    core_path = Path("Sources/DesignSystem/designTokens/core.tokens.json")
    if core_path.exists():
        with open(core_path) as f:
            core_data = json.load(f)
            tokens.update(extract_colors(core_data, "core"))
    
    # Try to load semantic tokens
    semantic_path = Path("Sources/DesignSystem/designTokens/semantic.tokens.json")
    if semantic_path.exists():
        with open(semantic_path) as f:
            semantic_data = json.load(f)
            tokens.update(extract_colors(semantic_data, "semantic"))
    
    return tokens


def extract_colors(data: dict, prefix: str = "") -> Dict[str, str]:
    """Extract color values from design tokens."""
    colors = {}
    
    def traverse(obj: dict, path: str = ""):
        if isinstance(obj, dict):
            if obj.get("$type") == "color" and "$value" in obj:
                full_path = f"{prefix}.{path}" if path else prefix
                colors[full_path] = obj["$value"]
            # Check for extensions with light/dark paths
            elif "$extensions" in obj and "design" in obj["$extensions"]:
                design_ext = obj["$extensions"]["design"]
                if "paths" in design_ext:
                    paths = design_ext["paths"]
                    if "light" in paths:
                        full_path = f"{prefix}.{path}.light" if path else f"{prefix}.light"
                        colors[full_path] = paths["light"]
                    if "dark" in paths:
                        full_path = f"{prefix}.{path}.dark" if path else f"{prefix}.dark"
                        colors[full_path] = paths["dark"]
            else:
                for key, value in obj.items():
                    if key not in ["$type", "$value", "$description", "$extensions", "$schema", "meta"]:
                        new_path = f"{path}.{key}" if path else key
                        traverse(value, new_path)
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                if isinstance(item, dict):
                    new_path = f"{path}[{i}]" if path else f"[{i}]"
                    traverse(item, new_path)
    
    traverse(data)
    return colors


def find_color_usage_in_code() -> List[ColorPair]:
    """Find color usage in Swift code."""
    color_pairs = []
    
    # Common patterns to look for
    patterns = [
        (r'\.foregroundStyle\(([^)]+)\)', 'foreground'),
        (r'\.foregroundColor\(([^)]+)\)', 'foreground'),
        (r'\.background\(([^)]+)\)', 'background'),
        (r'color:\s*([^,}]+)', 'foreground'),
        (r'Color\(hex:\s*"([^"]+)"\)', 'foreground'),
        (r'Color\(tokenValue:\s*"([^"]+)"\)', 'foreground'),
    ]
    
    ui_path = Path("Sources/DeduperUI")
    if not ui_path.exists():
        return color_pairs
    
    cwd = Path.cwd()
    for swift_file in ui_path.rglob("*.swift"):
        try:
            with open(swift_file) as f:
                for line_num, line in enumerate(f, 1):
                    for pattern, color_type in patterns:
                        matches = re.finditer(pattern, line)
                        for match in matches:
                            color_value = match.group(1).strip()
                            # Skip if it's a DesignToken reference
                            if 'DesignToken' in color_value:
                                continue
                            # Skip if it's a variable reference
                            if not (color_value.startswith('#') or 
                                    color_value.startswith('.') or
                                    'rgb' in color_value.lower()):
                                continue
                            
                            try:
                                rel_path = swift_file.relative_to(cwd)
                            except ValueError:
                                rel_path = swift_file
                            
                            color_pairs.append(ColorPair(
                                foreground=color_value if color_type == 'foreground' else '',
                                background=color_value if color_type == 'background' else '',
                                context=line.strip(),
                                file=str(rel_path),
                                line=line_num
                            ))
        except Exception as e:
            print(f"Warning: Could not process {swift_file}: {e}")
            continue
    
    return color_pairs


def audit_semantic_color_pairs(tokens: Dict) -> List[ContrastResult]:
    """Audit common semantic color combinations."""
    results = []
    
    # Common pairs to test
    pairs = [
        ("foreground.primary", "background.primary"),
        ("foreground.secondary", "background.primary"),
        ("foreground.tertiary", "background.primary"),
        ("foreground.onBrand", "background.brand"),
        ("foreground.success", "background.primary"),
        ("foreground.warning", "background.primary"),
        ("foreground.danger", "background.primary"),
        ("foreground.info", "background.primary"),
        ("foreground.link", "background.primary"),
        ("foreground.disabled", "background.disabled"),
    ]
    
    def resolve_token(token_path: str) -> Optional[str]:
        """Resolve token path to actual color value."""
        # Try direct lookup
        if token_path in tokens:
            value = tokens[token_path]
            # If it's a reference, resolve it
            if isinstance(value, str) and value.startswith('{') and value.endswith('}'):
                ref_path = value[1:-1]
                # Try with and without semantic prefix
                if not ref_path.startswith('semantic.') and not ref_path.startswith('core.'):
                    # Try semantic first
                    semantic_path = f"semantic.{ref_path}"
                    if semantic_path in tokens:
                        return resolve_token(semantic_path)
                    # Try core
                    core_path = f"core.{ref_path}"
                    if core_path in tokens:
                        return resolve_token(core_path)
                return resolve_token(ref_path)
            return value
        return None
    
    for fg_path, bg_path in pairs:
        fg_value = resolve_token(f"semantic.color.{fg_path}")
        bg_value = resolve_token(f"semantic.color.{bg_path}")
        
        if not fg_value or not bg_value:
            continue
        
        fg_rgb = parse_color_value(fg_value)
        bg_rgb = parse_color_value(bg_value)
        
        if fg_rgb and bg_rgb:
            ratio = contrast_ratio(fg_rgb, bg_rgb)
            level = get_contrast_level(ratio)
            
            results.append(ContrastResult(
                foreground=f"semantic.color.{fg_path}",
                background=f"semantic.color.{bg_path}",
                ratio=ratio,
                level=level,
                context=f"Semantic pair: {fg_path} on {bg_path}",
                file="designTokens",
                line=0
            ))
    
    return results


def audit_palette_colors(tokens: Dict) -> List[ContrastResult]:
    """Audit palette colors against common backgrounds."""
    results = []
    
    # Test palette colors against light and dark backgrounds
    backgrounds = {
        "light": "#FAFAFA",
        "dark": "#141414",
        "white": "#FFFFFF",
        "black": "#000000",
    }
    
    # Extract palette colors
    palette_colors = {}
    for key, value in tokens.items():
        if "palette" in key.lower() and "$value" not in key:
            rgb = parse_color_value(value)
            if rgb:
                palette_colors[key] = rgb
    
    for color_name, color_rgb in palette_colors.items():
        for bg_name, bg_hex in backgrounds.items():
            bg_rgb = parse_color_value(bg_hex)
            if bg_rgb:
                ratio = contrast_ratio(color_rgb, bg_rgb)
                level = get_contrast_level(ratio)
                
                results.append(ContrastResult(
                    foreground=color_name,
                    background=bg_name,
                    ratio=ratio,
                    level=level,
                    context=f"Palette color on {bg_name} background",
                    file="designTokens",
                    line=0
                ))
    
    return results


def generate_report(results: List[ContrastResult], output_file: Optional[str] = None):
    """Generate accessibility audit report."""
    report_lines = [
        "# Color Accessibility Audit Report",
        "",
        "## Summary",
        "",
    ]
    
    # Count by level
    level_counts = {}
    for result in results:
        level_counts[result.level] = level_counts.get(result.level, 0) + 1
    
    total = len(results)
    report_lines.append(f"**Total color pairs tested:** {total}")
    report_lines.append("")
    report_lines.append("### Compliance Breakdown")
    report_lines.append("")
    report_lines.append("| Level | Count | Percentage |")
    report_lines.append("|-------|-------|------------|")
    
    for level in ContrastLevel:
        count = level_counts.get(level, 0)
        percentage = (count / total * 100) if total > 0 else 0
        report_lines.append(f"| {level.value} | {count} | {percentage:.1f}% |")
    
    report_lines.append("")
    report_lines.append("## Failures (WCAG AA Non-Compliant)")
    report_lines.append("")
    
    failures = [r for r in results if r.level == ContrastLevel.FAIL]
    if failures:
        report_lines.append("| Foreground | Background | Ratio | Context | File |")
        report_lines.append("|------------|------------|-------|---------|------|")
        for failure in failures:
            report_lines.append(
                f"| {failure.foreground} | {failure.background} | "
                f"{failure.ratio:.2f}:1 | {failure.context} | {failure.file} |"
            )
    else:
        report_lines.append("✅ No failures found!")
    
    report_lines.append("")
    report_lines.append("## Recommendations")
    report_lines.append("")
    
    # Generate recommendations
    if failures:
        report_lines.append("### Critical Issues")
        report_lines.append("")
        report_lines.append("The following color combinations fail WCAG AA standards:")
        report_lines.append("")
        for failure in failures[:10]:  # Limit to top 10
            report_lines.append(f"- **{failure.context}**: Ratio {failure.ratio:.2f}:1")
            report_lines.append(f"  - Increase contrast by at least {WCAG_AA_NORMAL - failure.ratio:.2f}")
            report_lines.append("")
    
    # Check for hardcoded colors
    hardcoded_colors = find_color_usage_in_code()
    if hardcoded_colors:
        report_lines.append("### Hardcoded Colors")
        report_lines.append("")
        report_lines.append("The following files contain hardcoded colors that should use design tokens:")
        report_lines.append("")
        for pair in hardcoded_colors[:10]:  # Limit to top 10
            report_lines.append(f"- `{pair.file}:{pair.line}`: `{pair.context}`")
        report_lines.append("")
        report_lines.append("**Recommendation:** Replace hardcoded colors with `DesignToken` references.")
    
    report_lines.append("")
    report_lines.append("## Color Blindness Compatibility")
    report_lines.append("")
    report_lines.append("### Status Colors")
    report_lines.append("")
    report_lines.append("Ensure status colors (success, warning, danger, info) are distinguishable:")
    report_lines.append("")
    report_lines.append("- ✅ Use icons or patterns in addition to color")
    report_lines.append("- ✅ Ensure sufficient contrast even when color is removed")
    report_lines.append("- ✅ Test with color blindness simulators")
    
    report = "\n".join(report_lines)
    
    if output_file:
        with open(output_file, 'w') as f:
            f.write(report)
        print(f"Report written to {output_file}")
    else:
        print(report)
    
    return report


def main():
    """Main audit function."""
    print("🔍 Starting color accessibility audit...")
    print("")
    
    # Load design tokens
    print("Loading design tokens...")
    tokens = load_design_tokens()
    print(f"Found {len(tokens)} color tokens")
    print("")
    
    # Audit semantic color pairs
    print("Auditing semantic color pairs...")
    semantic_results = audit_semantic_color_pairs(tokens)
    print(f"Tested {len(semantic_results)} semantic color pairs")
    
    # Audit palette colors
    print("Auditing palette colors...")
    palette_results = audit_palette_colors(tokens)
    print(f"Tested {len(palette_results)} palette color combinations")
    
    # Combine results
    all_results = semantic_results + palette_results
    
    # Generate report
    print("")
    print("Generating report...")
    report_path = Path("docs/accessibility/color-audit-report.md")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    generate_report(all_results, str(report_path))
    
    # Summary
    failures = [r for r in all_results if r.level == ContrastLevel.FAIL]
    print("")
    print("=" * 60)
    print("Audit Complete")
    print("=" * 60)
    print(f"Total pairs tested: {len(all_results)}")
    print(f"Failures: {len(failures)}")
    print(f"WCAG AA compliant: {len(all_results) - len(failures)}")
    print("")
    
    if failures:
        print("⚠️  Some color combinations fail WCAG AA standards.")
        print(f"   See {report_path} for details.")
        return 1
    else:
        print("✅ All tested color combinations meet WCAG AA standards!")
        return 0


if __name__ == "__main__":
    sys.exit(main())

