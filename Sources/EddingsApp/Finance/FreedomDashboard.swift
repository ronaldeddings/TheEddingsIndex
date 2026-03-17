import SwiftUI
import EddingsKit

struct FreedomDashboard: View {
    @Environment(EddingsEngine.self) private var engine
    private let weeklyTarget: Double = FreedomTracker.weeklyTarget

    private var velocityPercent: Double {
        engine.freedomScore?.velocityPercent ?? 0
    }

    private var weeklyAmount: Double {
        engine.freedomScore?.weeklyNonW2TakeHome ?? 0
    }

    private var netWorth: Double {
        engine.freedomScore?.netWorth ?? 0
    }

    private var totalDebt: Double {
        engine.freedomScore?.totalDebt ?? 0
    }

    private var savingsRate: Double {
        engine.freedomScore?.savingsRate ?? 0
    }

    private var projectedDate: String {
        engine.freedomScore?.projectedFreedomDate ?? "—"
    }

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
        .onAppear { engine.loadFreedomScore() }
    }

    private var velocityHero: some View {
        HStack(spacing: 48) {
            gaugeView
            VStack(alignment: .leading, spacing: 16) {
                let gap = max(0, weeklyTarget - weeklyAmount)
                Text("You need ")
                    .font(EITypography.headline())
                    .foregroundStyle(EIColor.textPrimary)
                + Text("$\(Int(gap).formatted()) more per week")
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
                .trim(from: 0, to: min(velocityPercent / 100, 1.0))
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
            Text(projectedDate)
                .font(EITypography.display())
                .foregroundStyle(EIColor.gold)
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
            metricCard(
                title: "NET WORTH",
                value: "$\(Int(netWorth).formatted())",
                change: netWorth > 0 ? "Calculated from all accounts" : "No snapshot data",
                color: EIColor.emerald
            )
            metricCard(
                title: "SAVINGS RATE",
                value: "\(Int(savingsRate))%",
                change: "Last 12 weeks",
                color: EIColor.textPrimary
            )
            metricCard(
                title: "TOTAL DEBT",
                value: "$\(Int(totalDebt).formatted())",
                change: totalDebt > 0 ? "Liabilities from all accounts" : "No debt tracked",
                color: EIColor.rose
            )
            metricCard(
                title: "WEEKLY GAP",
                value: "$\(Int(max(0, weeklyTarget - weeklyAmount)).formatted())",
                change: "To reach $\(Int(weeklyTarget).formatted())/week target",
                color: EIColor.gold
            )
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
