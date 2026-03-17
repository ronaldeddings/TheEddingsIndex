import SwiftUI
import EddingsKit

enum ContactDepth: String, Sendable {
    case deep, growing, peripheral, fading

    var ringColor: Color {
        switch self {
        case .deep: return EIColor.gold
        case .growing: return EIColor.indigo
        case .peripheral: return EIColor.textTertiary
        case .fading: return EIColor.rose
        }
    }

    var bgColor: Color {
        switch self {
        case .deep: return EIColor.goldDim
        case .growing: return EIColor.indigoDim
        case .peripheral: return EIColor.elevated
        case .fading: return EIColor.roseDim
        }
    }

    var label: String {
        switch self {
        case .deep: return "Deep Partnership"
        case .growing: return "Growing"
        case .peripheral: return "Peripheral"
        case .fading: return "Fading"
        }
    }
}

struct DepthBadge: View {
    let name: String
    let depth: ContactDepth
    var size: CGFloat = 40

    var body: some View {
        Text(initials(from: name))
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(depth.ringColor)
            .frame(width: size, height: size)
            .background(depth.bgColor)
            .clipShape(Circle())
            .overlay(Circle().stroke(depth.ringColor, lineWidth: 2))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last!.prefix(1) : ""
        return "\(first)\(last)".uppercased()
    }
}
