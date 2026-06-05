import SwiftUI

/// Presentational container for one triage "band" on the funnel summary.
/// Intentionally modest and native (no design-system abstraction yet): an
/// icon + title header, a headline stat, supporting detail lines, and a
/// caller-supplied actions row. Used by the exact band and the "other groups"
/// summary row. (UI-TRIAGE-FUNNEL-EXACT-BAND-001)
struct TriageBandCard<Actions: View>: View {
    let icon: String
    let title: String
    let tint: Color
    /// Large primary stat line, e.g. "10,739 exact groups".
    let headline: String
    /// Supporting status lines under the headline.
    let detailLines: [String]
    @ViewBuilder var actions: () -> Actions

    init(
        icon: String,
        title: String,
        tint: Color,
        headline: String,
        detailLines: [String],
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.tint = tint
        self.headline = headline
        self.detailLines = detailLines
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .imageScale(.large)
                Text(title)
                    .font(.headline)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            Text(headline)
                .font(.title2)
                .fontWeight(.semibold)

            if !detailLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(detailLines, id: \.self) { line in
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

/// Shared byte formatter for reclaimable-space copy.
enum TriageFormat {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
    static func int(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
