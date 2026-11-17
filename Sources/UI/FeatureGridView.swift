import SwiftUI

/// All features of the device, by section. About 50 cells: an eager layout is cheap and scrolls smoothly,
/// where lazy stacks estimate row heights, load glass views mid-scroll and make the scroller jump.
struct FeatureGridView: View {
    let context: DeviceContext

    var body: some View {
        ScrollView(.vertical) {
            GlassEffectContainer(spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(FeatureCatalog.sections(for: context.device)) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.category.title.uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)
                            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 8) {
                                ForEach(rows(of: section.features), id: \.first?.id) { row in
                                    GridRow {
                                        ForEach(row, id: \.id) { feature in
                                            FeatureCell(feature: feature, context: context)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        // Room for the glass of the first and last rows, and for the toast over the last row.
        .contentMargins(.top, 4, for: .scrollContent)
        .contentMargins(.bottom, 40, for: .scrollContent)
        // Content fades under the edges: shows there is more to scroll without a scroller in a narrow panel.
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .scrollBounceBehavior(.basedOnSize)
        // A new device has other sections: start at the top.
        .id(context.device.serial)
    }

    private func rows(of features: [any Feature]) -> [[any Feature]] {
        stride(from: 0, to: features.count, by: Theme.columns).map {
            Array(features[$0..<min($0 + Theme.columns, features.count)])
        }
    }
}
