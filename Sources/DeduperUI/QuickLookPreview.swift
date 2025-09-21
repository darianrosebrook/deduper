import SwiftUI
import Quartz

/**
 Author: @darianrosebrook
 QuickLookPreview provides full-size preview functionality for media files.
 - Integrates with macOS QuickLook for native preview experience.
 - Supports images, videos, and other file types.
 - Design System: Integration layer for macOS services.
 */
public struct QuickLookPreview: View {
    public let url: URL
    public let title: String

    public var body: some View {
        QuickLookPreviewRepresentable(url: url, title: title)
    }
}

// MARK: - Preview Representable

public struct QuickLookPreviewRepresentable: NSViewRepresentable {
    public typealias NSViewType = QLPreviewView
    public typealias Coordinator = Void

    public let url: URL
    public let title: String

    public func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView()
        previewView.autostarts = true
        previewView.previewItem = PreviewItem(url: url, title: title)
        return previewView
    }

    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        // Update preview if needed
    }

    public func makeCoordinator() -> Coordinator {
        ()
    }
}

// MARK: - Preview Item

public class PreviewItem: NSObject, QLPreviewItem {
    @objc public let previewItemURL: URL?
    @objc public let previewItemTitle: String?

    public init(url: URL, title: String) {
        self.previewItemURL = url
        self.previewItemTitle = title
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Text("QuickLook Preview")
        QuickLookPreview(
            url: URL(fileURLWithPath: "/System/Library/Desktop Pictures/National Geographic 1.jpg"),
            title: "Sample Image"
        )
        .frame(width: 400, height: 300)
    }
}
