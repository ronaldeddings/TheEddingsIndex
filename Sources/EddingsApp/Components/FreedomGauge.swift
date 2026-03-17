import SwiftUI
import EddingsKit

struct FreedomGauge: View {
    let weeklyAmount: Double
    let weeklyTarget: Double
    var size: CGFloat = 220
    var strokeWidth: CGFloat = 10

    @State private var animatedProgress: Double = 0

    private var progress: Double {
        min(max(weeklyAmount / weeklyTarget, 0), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(EIColor.elevated, lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.83, green: 0.58, blue: 0.18),
                            Color(red: 0.94, green: 0.75, blue: 0.38),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(weeklyAmount, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(EITypography.metric())
                    .foregroundStyle(EIColor.gold)
                Text("of \(weeklyTarget, format: .currency(code: "USD").precision(.fractionLength(0))) / week")
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textTertiary)
                Text("\(Int(progress * 100))%")
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 1.5)) {
                animatedProgress = newValue
            }
        }
    }
}
