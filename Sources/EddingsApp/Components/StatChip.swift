import SwiftUI
import EddingsKit

struct StatChip: View {
    let icon: String
    let count: Int
    var color: Color = EIColor.textSecondary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text("\(count)")
                .font(EITypography.micro())
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
    }
}
