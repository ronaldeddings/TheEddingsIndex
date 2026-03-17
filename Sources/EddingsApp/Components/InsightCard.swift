import SwiftUI
import EddingsKit

struct InsightCard: View {
    let label: String
    let text: String
    var accentColor: Color = EIColor.indigo

    var body: some View {
        HStack(spacing: 0) {
            accentColor
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(EITypography.label())
                        .foregroundStyle(accentColor)
                        .textCase(.uppercase)
                }
                Text(text)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        }
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
    }
}
