import SwiftUI
import EddingsKit

struct CardContainer<Content: View>: View {
    var padding: CGFloat = EISpacing.cardPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(EIColor.card)
            .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: EIRadius.md)
                    .stroke(EIColor.borderSubtle, lineWidth: 0.5)
            )
    }
}
