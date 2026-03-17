import SwiftUI
import EddingsKit

struct FreedomDashboard: View {
    @Environment(FreedomViewModel.self) private var freedomVM
    @State private var appeared = false

    var body: some View {
        @Bindable var freedomVM = freedomVM

        ScrollView {
            VStack(spacing: EISpacing.sectionGap) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Freedom Dashboard")
                            .font(EITypography.display())
                            .foregroundStyle(EIColor.textPrimary)
                        Text("Your path from W-2 to financial independence")
                            .font(EITypography.bodySmall())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                    Spacer()
                    PillToggle(selection: $freedomVM.selectedPeriod)
                }
                .staggerFadeIn(appeared: appeared, index: 0)

                VelocityHeroCard()
                    .staggerFadeIn(appeared: appeared, index: 1)

                ProjectionCard()
                    .staggerFadeIn(appeared: appeared, index: 2)

                if !freedomVM.insightText.isEmpty {
                    InsightCard(label: "PAI Financial Insight", text: freedomVM.insightText)
                        .staggerFadeIn(appeared: appeared, index: 3)
                }

                #if os(macOS)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: EISpacing.sectionGap) {
                    NetWorthCard()
                        .staggerFadeIn(appeared: appeared, index: 4)
                    SpendingCard()
                        .staggerFadeIn(appeared: appeared, index: 5)
                    DebtCard()
                        .staggerFadeIn(appeared: appeared, index: 6)
                    IncomeCard()
                        .staggerFadeIn(appeared: appeared, index: 7)
                }
                #else
                NetWorthCard()
                    .staggerFadeIn(appeared: appeared, index: 4)
                SpendingCard()
                    .staggerFadeIn(appeared: appeared, index: 5)
                DebtCard()
                    .staggerFadeIn(appeared: appeared, index: 6)
                IncomeCard()
                    .staggerFadeIn(appeared: appeared, index: 7)
                #endif

                if !freedomVM.recentTransactions.isEmpty {
                    CardContainer(padding: EISpacing.cardPadding) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RECENT TRANSACTIONS")
                                .font(EITypography.label())
                                .foregroundStyle(EIColor.textTertiary)
                            ForEach(freedomVM.recentTransactions) { tx in
                                TransactionRow(transaction: tx)
                                if tx.id != freedomVM.recentTransactions.last?.id {
                                    Divider().background(EIColor.borderSubtle)
                                }
                            }
                        }
                    }
                    .staggerFadeIn(appeared: appeared, index: 8)
                }
            }
            .padding(EISpacing.detailPadding)
        }
        .background(EIColor.deep)
        .task { await freedomVM.load() }
        .onChange(of: freedomVM.selectedPeriod) { _, newPeriod in
            Task { await freedomVM.changePeriod(newPeriod) }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
    }
}

struct VelocityHeroCard: View {
    @Environment(FreedomViewModel.self) private var freedomVM
    private let weeklyTarget = FreedomTracker.weeklyTarget

    var body: some View {
        let weeklyAmount = freedomVM.freedomScore?.weeklyNonW2TakeHome ?? 0
        let gap = max(0, weeklyTarget - weeklyAmount)
        let velocity = freedomVM.freedomScore?.velocityPercent ?? 0

        CardContainer(padding: EISpacing.cardPaddingLarge) {
            HStack(spacing: 48) {
                #if os(macOS)
                FreedomGauge(weeklyAmount: weeklyAmount, weeklyTarget: weeklyTarget, size: 220, strokeWidth: 10)
                #else
                FreedomGauge(weeklyAmount: weeklyAmount, weeklyTarget: weeklyTarget, size: 180, strokeWidth: 12)
                #endif

                VStack(alignment: .leading, spacing: 16) {
                    (Text("You need ")
                        .font(EITypography.headline())
                        .foregroundStyle(EIColor.textPrimary)
                     + Text(gap, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(EITypography.headline())
                        .foregroundStyle(EIColor.gold)
                     + Text(" more per week to replace your W-2")
                        .font(EITypography.headline())
                        .foregroundStyle(EIColor.textPrimary))

                    Text("At current trajectory, non-W2 income covers **\(Int(velocity))%** of your freedom target.")
                        .font(EITypography.body())
                        .foregroundStyle(EIColor.textSecondary)
                }
            }
        }
    }
}

struct ProjectionCard: View {
    @Environment(FreedomViewModel.self) private var freedomVM

    var body: some View {
        let projectedDate = freedomVM.freedomScore?.projectedFreedomDate ?? "—"

        CardContainer(padding: EISpacing.cardPaddingLarge) {
            VStack(spacing: 4) {
                Text("At current velocity, you replace your W-2 income by")
                    .font(EITypography.caption())
                    .foregroundStyle(EIColor.textTertiary)
                Text(projectedDate)
                    .font(EITypography.display())
                    .foregroundStyle(EIColor.gold)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct NetWorthCard: View {
    @Environment(FreedomViewModel.self) private var freedomVM

    var body: some View {
        let netWorth = freedomVM.freedomScore?.netWorth ?? 0

        StatCard(
            title: "Net Worth",
            value: netWorth.formatted(.currency(code: "USD").precision(.fractionLength(0))),
            change: netWorth > 0 ? "Calculated from all accounts" : nil,
            changePositive: true,
            accentColor: EIColor.emerald
        )
        .overlay(alignment: .bottomTrailing) {
            if !freedomVM.netWorthHistory.isEmpty {
                MiniSparkline(data: freedomVM.netWorthHistory, color: EIColor.emerald, height: 24)
                    .frame(width: 80)
                    .padding(12)
            }
        }
    }
}

struct SpendingCard: View {
    @Environment(FreedomViewModel.self) private var freedomVM

    var body: some View {
        let total = freedomVM.spendingByCategory.reduce(0.0) { $0 + abs($1.amount) }

        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("SPENDING")
                    .font(EITypography.label())
                    .foregroundStyle(EIColor.textTertiary)
                Text(total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(EITypography.display())
                    .foregroundStyle(EIColor.textPrimary)
                    .monospacedDigit()
                if !freedomVM.spendingByCategory.isEmpty {
                    CategoryBar(items: freedomVM.spendingByCategory)
                }
            }
        }
    }
}

struct DebtCard: View {
    @Environment(FreedomViewModel.self) private var freedomVM

    var body: some View {
        let total = freedomVM.freedomScore?.totalDebt ?? 0

        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("DEBT PAYDOWN")
                    .font(EITypography.label())
                    .foregroundStyle(EIColor.textTertiary)
                Text(total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(EITypography.display())
                    .foregroundStyle(EIColor.rose)
                    .monospacedDigit()
                if !freedomVM.debtAccounts.isEmpty {
                    CategoryBar(items: freedomVM.debtAccounts)
                }
            }
        }
    }
}

struct IncomeCard: View {
    @Environment(FreedomViewModel.self) private var freedomVM

    var body: some View {
        let total = freedomVM.incomeStreams.reduce(0.0) { $0 + $1.amount }

        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("INCOME STREAMS")
                    .font(EITypography.label())
                    .foregroundStyle(EIColor.textTertiary)
                Text(total, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .font(EITypography.display())
                    .foregroundStyle(EIColor.emerald)
                    .monospacedDigit()
                if !freedomVM.incomeStreams.isEmpty {
                    CategoryBar(items: freedomVM.incomeStreams)
                }
            }
        }
    }
}

struct TransactionRow: View {
    let transaction: FinancialTransaction

    var body: some View {
        HStack(spacing: 12) {
            SourceIcon(source: .finance)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.payee ?? transaction.description ?? "Transaction")
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let account = transaction.accountName {
                        Text(account)
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                    Text(transaction.transactionDate, style: .date)
                        .font(EITypography.caption())
                        .foregroundStyle(EIColor.textTertiary)
                }
            }

            Spacer()

            if let cat = transaction.category, !cat.isEmpty {
                Text(cat)
                    .font(EITypography.micro())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(EIColor.elevated)
                    .foregroundStyle(EIColor.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: EIRadius.sm))
            }

            Text(transaction.amount, format: .currency(code: "USD").precision(.fractionLength(2)))
                .font(EITypography.body())
                .foregroundStyle(transaction.amount > 0 ? EIColor.emerald : EIColor.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

extension View {
    func staggerFadeIn(appeared: Bool, index: Int) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
            .animation(.easeOut(duration: 0.25).delay(Double(index) * 0.06), value: appeared)
    }
}
