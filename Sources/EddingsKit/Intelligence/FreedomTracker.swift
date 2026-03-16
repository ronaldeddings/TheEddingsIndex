import Foundation
import os

public struct FreedomTracker: Sendable {
    public static let weeklyTarget: Double = 6058.0
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "freedom")

    public init() {}

    public struct FreedomScore: Codable, Sendable {
        public let weeklyNonW2TakeHome: Double
        public let weeklyTarget: Double
        public let velocityPercent: Double
        public let gapPerWeek: Double
        public let projectedFreedomDate: String?
        public let netWorth: Double?
        public let totalDebt: Double?
        public let savingsRate: Double?
    }

    public func calculate(
        snapshots: [FinancialSnapshot],
        transactions: [FinancialTransaction],
        weeksElapsed: Int? = nil
    ) -> FreedomScore {
        let weeks: Int
        if let explicit = weeksElapsed {
            weeks = explicit
        } else if let earliest = transactions.map(\.transactionDate).min(),
                  let latest = transactions.map(\.transactionDate).max() {
            let span = latest.timeIntervalSince(earliest)
            weeks = max(1, Int(ceil(span / (7 * 86400))))
        } else {
            weeks = 12
        }
        let nonW2Income = calculateNonW2Income(transactions, weeks: weeks)
        let velocity = nonW2Income / Self.weeklyTarget
        let gap = max(0, Self.weeklyTarget - nonW2Income)

        let assetTypes: Set<String> = ["checking", "savings", "investment", "brokerage", "retirement", "other"]

        let assets = snapshots
            .filter { assetTypes.contains($0.accountType ?? "") }
            .reduce(0.0) { $0 + $1.balance }

        let liabilities = snapshots
            .filter { !assetTypes.contains($0.accountType ?? "") }
            .reduce(0.0) { $0 + abs($1.balance) }

        let netWorth = assets - liabilities

        let totalIncome = transactions
            .filter { $0.amount > 0 }
            .reduce(0.0) { $0 + $1.amount }
        let totalExpenses = transactions
            .filter { $0.amount < 0 }
            .reduce(0.0) { $0 + abs($1.amount) }
        let savingsRate = totalIncome > 0 ? (totalIncome - totalExpenses) / totalIncome : 0

        let projectedDate = projectFreedomDate(
            currentWeekly: nonW2Income,
            target: Self.weeklyTarget,
            growthRate: 0.003
        )

        logger.info("Freedom Velocity: $\(String(format: "%.0f", nonW2Income))/week (\(String(format: "%.0f", velocity * 100))% of $\(String(format: "%.0f", Self.weeklyTarget)))")

        return FreedomScore(
            weeklyNonW2TakeHome: nonW2Income,
            weeklyTarget: Self.weeklyTarget,
            velocityPercent: velocity * 100,
            gapPerWeek: gap,
            projectedFreedomDate: projectedDate,
            netWorth: netWorth,
            totalDebt: liabilities,
            savingsRate: savingsRate * 100
        )
    }

    private static let w2PayeePatterns: [String] = [
        "mozilla",
        "hacker valley media salary",
        "hvm salary",
        "payroll",
        "gusto",
    ]

    private static let nonW2CategoryPatterns: [String] = [
        "owner's draw",
        "owners draw",
        "distribution",
        "client payment",
        "consulting",
        "sponsorship",
        "advertising revenue",
    ]

    private func calculateNonW2Income(_ transactions: [FinancialTransaction], weeks: Int) -> Double {
        let nonW2 = transactions.filter { txn in
            guard txn.amount > 0 else { return false }

            let payeeLower = (txn.payee ?? "").lowercased()
            let categoryLower = (txn.category ?? "").lowercased()
            let descLower = (txn.description ?? "").lowercased()

            let isW2 = Self.w2PayeePatterns.contains { pattern in
                payeeLower.contains(pattern) || descLower.contains(pattern)
            }
            if isW2 { return false }

            if txn.source == "qbo" {
                return Self.nonW2CategoryPatterns.contains { pattern in
                    categoryLower.contains(pattern) || descLower.contains(pattern) || payeeLower.contains(pattern)
                }
            }

            return txn.source == "simplefin"
        }

        let total = nonW2.reduce(0.0) { $0 + $1.amount }
        return weeks > 0 ? total / Double(weeks) : 0
    }

    private func projectFreedomDate(currentWeekly: Double, target: Double, growthRate: Double) -> String? {
        guard currentWeekly > 0 else { return nil }
        guard currentWeekly < target else { return "Now" }

        let weeksNeeded = log(target / currentWeekly) / log(1 + growthRate)
        let months = Int(ceil(weeksNeeded / 4.33))

        let future = Calendar.current.date(byAdding: .month, value: months, to: Date())
        guard let date = future else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
