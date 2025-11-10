# Color Accessibility Audit Report

## Summary

**Total color pairs tested:** 34

### Compliance Breakdown

| Level | Count | Percentage |
|-------|-------|------------|
| FAIL | 12 | 35.3% |
| AA_LARGE | 4 | 11.8% |
| AA_NORMAL | 0 | 0.0% |
| AAA_LARGE | 5 | 14.7% |
| AAA_NORMAL | 13 | 38.2% |

## Failures (WCAG AA Non-Compliant)

| Foreground | Background | Ratio | Context | File |
|------------|------------|-------|---------|------|
| core.color.palette.brand.primary.100 | light | 1.11:1 | Palette color on light background | designTokens |
| core.color.palette.brand.primary.100 | white | 1.15:1 | Palette color on white background | designTokens |
| core.color.palette.brand.primary.200 | light | 1.50:1 | Palette color on light background | designTokens |
| core.color.palette.brand.primary.200 | white | 1.57:1 | Palette color on white background | designTokens |
| core.color.palette.brand.primary.300 | light | 2.13:1 | Palette color on light background | designTokens |
| core.color.palette.brand.primary.300 | white | 2.23:1 | Palette color on white background | designTokens |
| core.color.palette.brand.primary.600 | dark | 2.47:1 | Palette color on dark background | designTokens |
| core.color.palette.brand.primary.600 | black | 2.81:1 | Palette color on black background | designTokens |
| core.color.palette.brand.primary.700 | dark | 1.61:1 | Palette color on dark background | designTokens |
| core.color.palette.brand.primary.700 | black | 1.84:1 | Palette color on black background | designTokens |
| core.color.palette.brand.primary.800 | dark | 1.14:1 | Palette color on dark background | designTokens |
| core.color.palette.brand.primary.800 | black | 1.30:1 | Palette color on black background | designTokens |

## Recommendations

### Critical Issues

The following color combinations fail WCAG AA standards:

- **Palette color on light background**: Ratio 1.11:1
  - Increase contrast by at least 3.39

- **Palette color on white background**: Ratio 1.15:1
  - Increase contrast by at least 3.35

- **Palette color on light background**: Ratio 1.50:1
  - Increase contrast by at least 3.00

- **Palette color on white background**: Ratio 1.57:1
  - Increase contrast by at least 2.93

- **Palette color on light background**: Ratio 2.13:1
  - Increase contrast by at least 2.37

- **Palette color on white background**: Ratio 2.23:1
  - Increase contrast by at least 2.27

- **Palette color on dark background**: Ratio 2.47:1
  - Increase contrast by at least 2.03

- **Palette color on black background**: Ratio 2.81:1
  - Increase contrast by at least 1.69

- **Palette color on dark background**: Ratio 1.61:1
  - Increase contrast by at least 2.89

- **Palette color on black background**: Ratio 1.84:1
  - Increase contrast by at least 2.66

### Hardcoded Colors

The following files contain hardcoded colors that should use design tokens:

- `Sources/DeduperUI/DesignTokenParser.swift:311`: `return DesignTokenShadow(color: .black, radius: 0, x: 0, y: 0)`
- `Sources/DeduperUI/DesignTokens.swift:241`: `public static let shadowSM: DesignTokenShadow = DesignTokenShadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)`
- `Sources/DeduperUI/DesignTokens.swift:242`: `public static let shadowMD: DesignTokenShadow = DesignTokenShadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)`
- `Sources/DeduperUI/DesignTokens.swift:243`: `public static let shadowLG: DesignTokenShadow = DesignTokenShadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)`

**Recommendation:** Replace hardcoded colors with `DesignToken` references.

## Color Blindness Compatibility

### Status Colors

Ensure status colors (success, warning, danger, info) are distinguishable:

- ✅ Use icons or patterns in addition to color
- ✅ Ensure sufficient contrast even when color is removed
- ✅ Test with color blindness simulators