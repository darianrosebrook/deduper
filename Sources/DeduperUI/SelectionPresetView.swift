import SwiftUI
import Foundation
import DeduperCore

/**
 * SelectionPresetView displays a picker for selecting keeper selection strategies.
 * 
 * Author: @darianrosebrook
 * 
 * This component allows users to choose from predefined selection presets
 * (highest resolution, largest file, keep latest, etc.) and apply them to
 * duplicate groups for automated keeper selection.
 * 
 * Design System: Compound component following `/Sources/DesignSystem/COMPONENT_STANDARDS.md`
 */
public struct SelectionPresetView: View {
    @Binding var selectedPreset: SelectionPreset
    let onPresetChanged: ((SelectionPreset) -> Void)?
    
    public init(
        selectedPreset: Binding<SelectionPreset>,
        onPresetChanged: ((SelectionPreset) -> Void)? = nil
    ) {
        self._selectedPreset = selectedPreset
        self.onPresetChanged = onPresetChanged
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingMD) {
            Text("Selection Strategy")
                .font(DesignToken.fontFamilyHeading)
            
            Text("Choose how to automatically select which file to keep")
                .font(DesignToken.fontFamilyCaption)
                .foregroundStyle(DesignToken.colorForegroundSecondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DesignToken.spacingSM) {
                ForEach(SelectionPreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                    PresetCard(
                        preset: preset,
                        isSelected: selectedPreset == preset,
                        onSelect: {
                            selectedPreset = preset
                            onPresetChanged?(preset)
                        }
                    )
                }
            }
        }
    }
}

/**
 * PresetCard displays a single selection preset option.
 */
struct PresetCard: View {
    let preset: SelectionPreset
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        SwiftUI.Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DesignToken.spacingXS) {
                HStack {
                    Image(systemName: preset.iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? DesignToken.colorSuccess : DesignToken.colorForegroundSecondary)
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DesignToken.colorSuccess)
                            .font(.system(size: 20))
                    }
                }
                
                Text(preset.displayName)
                    .font(DesignToken.fontFamilyBody)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(DesignToken.colorForegroundPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(preset.description)
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DesignToken.spacingMD)
            .frame(maxWidth: .infinity)
            .background(isSelected ? DesignToken.colorBackgroundElevated : DesignToken.colorBackgroundSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.radiusMD)
                    .stroke(isSelected ? DesignToken.colorSuccess : DesignToken.colorBorderSubtle, lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        }
        .buttonStyle(.plain)
    }
}

/**
 * SelectionPresetPreview shows a preview of what files would be selected with a given preset.
 */
public struct SelectionPresetPreview: View {
    let group: DuplicateGroupResult
    let preset: SelectionPreset
    @State private var previewKeeperId: UUID?
    @State private var isCalculating = false
    
    public init(group: DuplicateGroupResult, preset: SelectionPreset) {
        self.group = group
        self.preset = preset
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.spacingSM) {
            HStack {
                Text("Preview")
                    .font(DesignToken.fontFamilyBody)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if isCalculating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            
            if let keeperId = previewKeeperId,
               let keeperMember = group.members.first(where: { $0.fileId == keeperId }) {
                HStack(spacing: DesignToken.spacingSM) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignToken.colorSuccess)
                    
                    Text("Would keep: \(keeperMember.fileId.uuidString.prefix(8))...")
                        .font(DesignToken.fontFamilyCaption)
                        .foregroundStyle(DesignToken.colorForegroundSecondary)
                }
            } else {
                Text("Select a preset to preview")
                    .font(DesignToken.fontFamilyCaption)
                    .foregroundStyle(DesignToken.colorForegroundSecondary)
            }
        }
        .padding(DesignToken.spacingMD)
        .background(DesignToken.colorBackgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.radiusMD))
        .onAppear {
            calculatePreview(for: preset)
        }
        .onChange(of: preset) { newPreset in
            calculatePreview(for: newPreset)
        }
    }
    
    private func calculatePreview(for preset: SelectionPreset) {
        guard preset != .custom else {
            previewKeeperId = nil
            return
        }
        
        isCalculating = true
        Task {
            let service = SelectionPresetService(metadataService: ServiceManager.shared.metadataService)
            let keeperId = await service.applyPreset(preset, to: group)
            await MainActor.run {
                previewKeeperId = keeperId
                isCalculating = false
            }
        }
    }
}

