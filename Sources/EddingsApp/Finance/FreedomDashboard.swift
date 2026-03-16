import SwiftUI
import EddingsKit

struct FreedomDashboard: View {
    @State private var velocityPercent: Double = 47
    @State private var weeklyAmount: Double = 2847
    private let weeklyTarget: Double = 6058

    var body: some View {
        ScrollView {
            VStack(spacing: EISpacing.sectionGap) {
                velocityHero
                projectionCard
                statsGrid
            }
            .padding(EISpacing.detailPadding)
        }
        .background(EIColor.deep)
        .navigationTitle("Freedom Dashboard")
    }

    private var velocityHero: some View {
        HStack(spacing: 48) {
            gaugeView
            VStack(alignment: .leading, spacing: 16) {
                Text("You need ")
                    .font(EITypography.headline())
                    .foregroundStyle(EIColor.textPrimary)
                + Text("$\(Int(weeklyTarget - weeklyAmount).formatted()) more per week")
                    .font(EITypography.headline())
                    .foregroundStyle(EIColor.gold)
                + Text(" to replace your W-2")
                    .font(EITypography.headline())
                    .foregroundStyle(EIColor.textPrimary)

                Text("At current trajectory, non-W2 income covers **\(Int(velocityPercent))% of your freedom target**.")
                    .font(EITypography.body())
                    .foregroundStyle(EIColor.textSecondary)
            }
        }
        .padding(EISpacing.cardPaddingLarge)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: EIRadius.xl)
                .stroke(EIColor.border, lineWidth: 1)
        )
    }

    private var gaugeView: some View {
        ZStack {
            Circle()
                .stroke(EIColor.elevated, lineWidth: 10)
            Circle()
                .trim(from: 0, to: velocityPercent / 100)
                .stroke(
                    EIColor.gold.gradient,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.5), value: velocityPercent)

            VStack(spacing: 2) {
                Text("$\(Int(weeklyAmount).formatted())")
                    .font(EITypography.metric())
                    .foregroundStyle(EIColor.gold)
                Text("of $\(Int(weeklyTarget).formatted()) / week")
                    .font(EITypography.caption())
                    .foregroundStyle(EIColor.textTertiary)
                Text("\(Int(velocityPercent))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EIColor.textSecondary)
            }
        }
        .frame(width: 220, height: 220)
    }

    private var projectionCard: some View {
        VStack(spacing: 4) {
            Text("At current velocity, you replace your W-2 income by")
                .font(EITypography.caption())
                .foregroundStyle(EIColor.textTertiary)
            Text("November 2027")
                .font(EITypography.display())
                .foregroundStyle(EIColor.gold)
            Text("If CrowdStrike closes → **June 2027** · If Optro + CrowdStrike → **March 2027**")
                .font(EITypography.bodySmall())
                .foregroundStyle(EIColor.textSecondary)
        }
        .padding(EISpacing.cardPaddingLarge)
        .frame(maxWidth: .infinity)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: EIRadius.xl)
                .stroke(EIColor.border, lineWidth: 1)
        )
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
            metricCard(title: "NET WORTH", value: "$89,490", change: "▲ $1,435 today", color: EIColor.emerald)
            metricCard(title: "MARCH SPENDING", value: "$8,437", change: "Savings rate: 18%", color: EIColor.textPrimary)
            metricCard(title: "TOTAL DEBT", value: "$13,105", change: "Debt-free by Sep 2026", color: EIColor.rose)
            metricCard(title: "HVM REVENUE (Q1)", value: "$62,000", change: "▲ 12% vs Q4", color: EIColor.gold)
        }
    }

    private func metricCard(title: String, value: String, change: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(EITypography.label())
                .foregroundStyle(EIColor.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(color)
            Text(change)
                .font(EITypography.caption())
                .foregroundStyle(EIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EISpacing.cardPaddingLarge)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: EIRadius.xl)
                .stroke(EIColor.border, lineWidth: 1)
        )
    }
}
