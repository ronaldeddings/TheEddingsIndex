import SwiftUI
import EddingsKit

struct SourceIcon: View {
    let source: EISource
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: source.sfSymbol)
            .font(.system(size: size * 0.46))
            .foregroundStyle(source.color)
            .frame(width: size, height: size)
            .background(source.dimColor)
            .clipShape(RoundedRectangle(cornerRadius: EIRadius.sm))
    }
}
