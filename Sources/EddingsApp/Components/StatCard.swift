import SwiftUI
import EddingsKit

struct StatCard: View {
    let title: String
    let value: String
    var change: String? = nil
    var changePositive: Bool = true
    var detail: String? = nil
    var accentColor: Color = EIColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(EITypography.label())
                .foregroundStyle(EIColor.textTertiary)
            Text(value)
                .font(EITypography.display())
                .foregroundStyle(accentColor)
                .monospacedDigit()
            if let change {
                Text(change)
                    .font(EITypography.caption())
                    .foregroundStyle(changePositive ? EIColor.emerald : EIColor.rose)
            }
            if let detail {
                Text(detail)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(EISpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
    }
}
