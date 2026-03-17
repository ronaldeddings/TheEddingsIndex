import SwiftUI
import EddingsKit

struct CategoryItem: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let amount: Double
    let color: Color
}

struct CategoryBar: View {
    let items: [CategoryItem]

    private var total: Double {
        items.reduce(0) { $0 + abs($1.amount) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(items) { item in
                        item.color
                            .frame(width: total > 0
                                   ? max(geo.size.width * (abs(item.amount) / total), 2)
                                   : 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 6)

            ForEach(items) { item in
                HStack {
                    Circle().fill(item.color).frame(width: 6, height: 6)
                    Text(item.label)
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textSecondary)
                    Spacer()
                    Text(abs(item.amount), format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textPrimary)
                        .monospacedDigit()
                }
            }
        }
    }
}
