import SwiftUI

/// A single session row in the sidebar.
public struct SessionRowView: View {
    public let session: SessionIndex

    public init(session: SessionIndex) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Directory name (hidden sessions are dimmed + badged
            // when listed via Show Hidden Sessions)
            HStack(spacing: 4) {
                Text(directoryName)
                    .font(.callout.bold())
                    .lineLimit(1)
                    .truncationMode(.head)
                if session.isHidden {
                    Image(systemName: "eye.slash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Hidden session")
                }
            }

            // Stats line
            HStack(spacing: 8) {
                Label(
                    "\(session.duplicateGroups)",
                    systemImage: "square.stack.3d.up"
                )
                Label(
                    "\(session.mediaFiles) files",
                    systemImage: "photo.on.rectangle"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Date
            Text(session.startedAt.formatted(
                .dateTime.month(.abbreviated).day().year()
                    .hour().minute()
            ))
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .opacity(session.isHidden ? 0.55 : 1)
    }

    private var directoryName: String {
        let url = URL(fileURLWithPath: session.directoryPath)
        return url.lastPathComponent
    }
}
