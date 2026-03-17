import SwiftUI
import EddingsKit
import GRDB

enum FreedomPeriod: String, CaseIterable, CustomStringConvertible, Sendable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    var description: String { rawValue }

    var startDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .week: return cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month: return cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .quarter: return cal.date(byAdding: .month, value: -3, to: now) ?? now
        case .year: return cal.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }
}

@MainActor
@Observable
final class FreedomViewModel {
    var selectedPeriod: FreedomPeriod = .month
    var freedomScore: FreedomTracker.FreedomScore?
    var netWorthHistory: [Double] = []
    var spendingByCategory: [CategoryItem] = []
    var debtAccounts: [CategoryItem] = []
    var incomeStreams: [CategoryItem] = []
    var recentTransactions: [FinancialTransaction] = []
    var insightText: String = ""
    var isLoading = false

    @ObservationIgnored private let dataAccess: DataAccess?
    @ObservationIgnored private let tracker = FreedomTracker()

    private static let categoryColors: [Color] = [
        EIColor.violet, EIColor.indigo, EIColor.gold,
        EIColor.blue, EIColor.emerald, EIColor.textTertiary,
    ]

    init(dataAccess: DataAccess?) {
        self.dataAccess = dataAccess
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let da = dataAccess else { return }

        do {
            let snapshots = try da.latestSnapshots()
            let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date()) ?? Date()
            let transactions = try await da.dbPool.read { db in
                try FinancialTransaction
                    .filter(Column("transactionDate") >= cutoff)
                    .fetchAll(db)
            }
            freedomScore = tracker.calculate(snapshots: snapshots, transactions: transactions)

            let history = try da.snapshotHistory(since: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date())
            netWorthHistory = aggregateNetWorth(history)

            await loadPeriodData()
        } catch {
            freedomScore = nil
        }
    }

    func changePeriod(_ period: FreedomPeriod) async {
        selectedPeriod = period
        await loadPeriodData()
    }

    private func loadPeriodData() async {
        guard let da = dataAccess else { return }
        let since = selectedPeriod.startDate

        do {
            let spending = try da.spendingByCategory(since: since)
            spendingByCategory = spending.enumerated().map { i, item in
                CategoryItem(
                    label: item.category,
                    amount: item.amount,
                    color: Self.categoryColors[i % Self.categoryColors.count]
                )
            }

            let debt = try da.debtAccounts()
            debtAccounts = debt.map { snap in
                CategoryItem(
                    label: snap.accountName ?? snap.accountId,
                    amount: abs(snap.balance),
                    color: EIColor.rose
                )
            }

            let income = try da.incomeBySource(since: since)
            incomeStreams = income.enumerated().map { i, item in
                let color: Color = item.source.lowercased().contains("mozilla") || item.source.lowercased().contains("w-2")
                    ? EIColor.blue
                    : Self.categoryColors[i % Self.categoryColors.count]
                return CategoryItem(label: item.source, amount: item.amount, color: color)
            }

            recentTransactions = try da.recentTransactions(limit: 20)
            insightText = buildInsight()
        } catch {}
    }

    private func aggregateNetWorth(_ snapshots: [FinancialSnapshot]) -> [Double] {
        let grouped = Dictionary(grouping: snapshots) { snap in
            Calendar.current.startOfDay(for: snap.snapshotDate)
        }
        return grouped.keys.sorted().map { day in
            grouped[day]?.reduce(0.0) { $0 + $1.balance } ?? 0
        }
    }

    private func buildInsight() -> String {
        guard let score = freedomScore else { return "" }
        let velocity = Int(score.velocityPercent)
        let gap = score.gapPerWeek
        var text = "Freedom velocity at \(velocity)%."
        if gap > 0 {
            text += " You need \(gap.formatted(.currency(code: "USD").precision(.fractionLength(0)))) more per week."
        }
        if let debt = score.totalDebt, debt > 0 {
            text += " Total debt: \(debt.formatted(.currency(code: "USD").precision(.fractionLength(0))))."
        }
        if let savings = score.savingsRate {
            text += " Savings rate: \(Int(savings))%."
        }
        return text
    }
}
