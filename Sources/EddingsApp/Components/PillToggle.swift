import SwiftUI
import EddingsKit

struct PillToggle<T: Hashable & CaseIterable & CustomStringConvertible>: View where T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    var activeColor: Color = EIColor.gold

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(T.allCases), id: \.hashValue) { item in
                Button {
                    selection = item
                } label: {
                    Text(item.description)
                        .font(EITypography.caption())
                        .foregroundStyle(selection == item ? EIColor.deep : EIColor.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selection == item ? activeColor : EIColor.elevated)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
