import SwiftUI
import DeduperCore

/**
 Author: @darianrosebrook
 MetadataDiff shows side-by-side metadata fields, highlighting differences.
 - Provide already-parsed fields; heavy metadata parsing should not occur here.
 */
public struct MetadataField: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let leftValue: String?
    public let rightValue: String?
    
    public init(id: String, label: String, leftValue: String?, rightValue: String?) {
        self.id = id
        self.label = label
        self.leftValue = leftValue
        self.rightValue = rightValue
    }
}

public struct MetadataDiff: View {
    private let fields: [MetadataField]
    private let leftTitle: String
    private let rightTitle: String
    
    public init(fields: [MetadataField] = [], leftTitle: String = "A", rightTitle: String = "B") {
        self.fields = fields
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(leftTitle).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                Text(rightTitle).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 4)
            ForEach(fields) { field in
                HStack(alignment: .top, spacing: 12) {
                    Text(field.label).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
                    cellText(field.leftValue, differs: differs(field)).frame(maxWidth: .infinity, alignment: .leading)
                    cellText(field.rightValue, differs: differs(field)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(field.label), left \(field.leftValue ?? "none"), right \(field.rightValue ?? "none")")
                Divider()
            }
        }
    }
    
    private func differs(_ field: MetadataField) -> Bool {
        let lhs = field.leftValue ?? ""
        let rhs = field.rightValue ?? ""
        return lhs != rhs
    }
    
    private func cellText(_ value: String?, differs: Bool) -> some View {
        let text = (value?.isEmpty ?? true) ? "—" : (value ?? "—")
        return Text(text)
            .font(.caption)
            .padding(4)
            .background(differs ? Color.yellow.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    MetadataDiff(fields: [
        MetadataField(id: "date", label: "Date", leftValue: "2021-06-01", rightValue: "2021-06-01"),
        MetadataField(id: "camera", label: "Camera", leftValue: "iPhone 14 Pro", rightValue: "iPhone 13"),
        MetadataField(id: "size", label: "Resolution", leftValue: "4032×3024", rightValue: "4032×3024"),
        MetadataField(id: "gps", label: "GPS", leftValue: nil, rightValue: "37.7749,-122.4194"),
    ], leftTitle: "Keep", rightTitle: "Remove")
    .padding()
}


