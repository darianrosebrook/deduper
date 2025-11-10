import SwiftUI
import DeduperCore

/**
 * Visual difference comparison view for duplicate detection.
 * Shows side-by-side image comparison with difference analysis.
 *
 * Author: @darianrosebrook
 */
public struct VisualDifferenceView: View {
    let keeperURL: URL
    let duplicateURL: URL
    let analysis: VisualDifferenceAnalysis
    @State private var keeperImage: NSImage?
    @State private var duplicateImage: NSImage?
    @State private var showDifferenceMap = false
    
    public init(keeperURL: URL, duplicateURL: URL, analysis: VisualDifferenceAnalysis) {
        self.keeperURL = keeperURL
        self.duplicateURL = duplicateURL
        self.analysis = analysis
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            // Header
            HStack {
                Text("Visual Comparison")
                    .font(DesignToken.fontFamilyHeading)
                Spacer()
                Toggle("Show Difference Map", isOn: $showDifferenceMap)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            // Side-by-side comparison
            HStack(spacing: DesignToken.spacingMD) {
                // Keeper image
                VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                    Text("Keeper")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    
                    if let image = keeperImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 300, maxHeight: 300)
                            .cornerRadius(DesignToken.cornerRadiusSM)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignToken.cornerRadiusSM)
                                    .stroke(DesignToken.colorForegroundSecondary.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        ProgressView()
                            .frame(width: 300, height: 300)
                    }
                }
                
                // Duplicate image
                VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                    Text("Duplicate")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                    
                    if let image = duplicateImage {
                        ZStack {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 300, maxHeight: 300)
                                .cornerRadius(DesignToken.cornerRadiusSM)
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignToken.cornerRadiusSM)
                                        .stroke(DesignToken.colorForegroundSecondary.opacity(0.3), lineWidth: 1)
                                )
                            
                            // Difference map overlay
                            if showDifferenceMap, let diffMap = createDifferenceMapImage() {
                                Image(nsImage: diffMap)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 300, maxHeight: 300)
                                    .opacity(0.6)
                                    .blendMode(.multiply)
                            }
                        }
                    } else {
                        ProgressView()
                            .frame(width: 300, height: 300)
                    }
                }
            }
            
            // Analysis summary
            VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
                Text("Analysis Results")
                    .font(DesignToken.fontFamilySubheading)
                
                // Similarity score
                HStack {
                    Text("Overall Similarity:")
                        .font(DesignToken.fontFamilyBody)
                    Spacer()
                    Text("\(Int(analysis.overallSimilarity * 100))%")
                        .font(DesignToken.fontFamilyBody)
                        .fontWeight(.bold)
                        .foregroundStyle(similarityColor(analysis.overallSimilarity))
                }
                
                // Verdict
                HStack {
                    Text("Verdict:")
                        .font(DesignToken.fontFamilyBody)
                    Spacer()
                    Text(analysis.verdict.description)
                        .font(DesignToken.fontFamilyBody)
                        .fontWeight(.bold)
                        .foregroundStyle(verdictColor(analysis.verdict))
                }
                
                Divider()
                
                // Detailed metrics
                VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                    MetricRow(
                        label: "Hash Distance",
                        value: hashDistanceString,
                        verdict: hashDistanceVerdict
                    )
                    
                    if let ssim = analysis.structuralSimilarity {
                        MetricRow(label: "Structural Similarity", value: String(format: "%.3f", ssim), verdict: ssim > 0.9 ? .pass : ssim > 0.7 ? .warn : .fail)
                    }
                    
                    MetricRow(label: "Color Histogram Distance", value: String(format: "%.3f", analysis.colorHistogramDistance), verdict: analysis.colorHistogramDistance < 0.1 ? .pass : analysis.colorHistogramDistance < 0.3 ? .warn : .fail)
                    
                    MetricRow(
                        label: "Pixel Difference",
                        value: pixelDifferenceString,
                        verdict: pixelDifferenceVerdict
                    )
                }
            }
            .padding(DesignToken.spacingSM)
            .background(DesignToken.colorBackgroundSecondary)
            .cornerRadius(DesignToken.cornerRadiusSM)
        }
        .padding(DesignToken.spacingMD)
        .onAppear {
            loadImages()
        }
    }
    
    private func loadImages() {
        Task {
            keeperImage = NSImage(contentsOf: keeperURL)
            duplicateImage = NSImage(contentsOf: duplicateURL)
        }
    }
    
    private func createDifferenceMapImage() -> NSImage? {
        // Create a visual representation of the difference map
        let diffMap = analysis.differenceMap
        
        let width = Int(diffMap.width)
        let height = Int(diffMap.height)
        let size = NSSize(width: width, height: height)
        
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw difference map
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard index < diffMap.data.count else { continue }
                
                let diff = diffMap.data[index]
                let color = diff > 0.5 ? NSColor.red.withAlphaComponent(0.8) : NSColor.clear
                color.setFill()
                NSRect(x: x, y: height - y - 1, width: 1, height: 1).fill()
            }
        }
        
        image.unlockFocus()
        return image
    }
    
    private var hashDistanceString: String {
        let hashValue = analysis.hashDistance.dHash ?? analysis.hashDistance.pHash ?? 0
        return "\(hashValue)"
    }
    
    private var hashDistanceVerdict: EvidenceItem.Verdict {
        let hashValue = analysis.hashDistance.dHash ?? analysis.hashDistance.pHash ?? 0
        return hashValue <= 5 ? .pass : .fail
    }
    
    private var pixelDifferenceString: String {
        let count = analysis.pixelDifference.differentPixelCount ?? 0
        let total = analysis.pixelDifference.totalPixels ?? 1
        let percentage = total > 0 ? Double(count) / Double(total) * 100.0 : 0.0
        return "\(count) pixels (\(String(format: "%.1f", percentage))%)"
    }
    
    private var pixelDifferenceVerdict: EvidenceItem.Verdict {
        let count = analysis.pixelDifference.differentPixelCount ?? 0
        let total = analysis.pixelDifference.totalPixels ?? 1
        let percentage = total > 0 ? Double(count) / Double(total) * 100.0 : 0.0
        return percentage < 1.0 ? .pass : percentage < 5.0 ? .warn : .fail
    }
    
    private func similarityColor(_ similarity: Double) -> Color {
        if similarity > 0.9 {
            return .green
        } else if similarity > 0.7 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func verdictColor(_ verdict: VisualDifferenceVerdict) -> Color {
        switch verdict {
        case .identical:
            return .green
        case .nearlyIdentical:
            return .green
        case .verySimilar:
            return .green
        case .similar:
            return .orange
        case .somewhatDifferent:
            return .red
        case .veryDifferent:
            return .red
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    let verdict: EvidenceItem.Verdict
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
            Spacer()
            Text(value)
                .font(DesignToken.fontFamilyCaption)
            verdictIcon
        }
    }
    
    @ViewBuilder
    private var verdictIcon: some View {
        switch verdict {
        case .pass:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignToken.colorStatusSuccess)
        case .warn:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignToken.colorStatusWarning)
        case .fail:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(DesignToken.colorStatusError)
        }
    }
}

#Preview {
    VisualDifferenceView(
        keeperURL: URL(fileURLWithPath: "/tmp/keeper.jpg"),
        duplicateURL: URL(fileURLWithPath: "/tmp/duplicate.jpg"),
        analysis: VisualDifferenceAnalysis(
            hashDistance: HashDistance(dHash: 3, pHash: 5),
            pixelDifference: PixelDifference(meanDifference: 0.1, maxDifference: 0.5, differentPixelCount: 1000, totalPixels: 1000000),
            structuralSimilarity: 0.95,
            colorHistogramDistance: 0.05,
            differenceMap: DifferenceMap(width: 100, height: 100, data: Array(repeating: 0.0, count: 10000)),
            overallSimilarity: 0.92,
            verdict: .nearlyIdentical
        )
    )
    .padding()
}

