import Foundation

public struct MonthlySummary: Codable, Sendable {
    public let month: String
    public let income: Double
    public let expenses: Double
    public let net: Double
    public let savingsRate: Double
    public let categories: [CategoryBreakdown]
    public let freedomVelocity: FreedomVelocity

    public struct FreedomVelocity: Codable, Sendable {
        public let weeklyNonW2TakeHome: Double
        public let target: Double
        public let onTrack: Bool

        public init(weeklyNonW2TakeHome: Double, target: Double, onTrack: Bool) {
            self.weeklyNonW2TakeHome = weeklyNonW2TakeHome
            self.target = target
            self.onTrack = onTrack
        }
    }

    public init(
        month: String,
        income: Double,
        expenses: Double,
        net: Double,
        savingsRate: Double,
        categories: [CategoryBreakdown],
        freedomVelocity: FreedomVelocity
    ) {
        self.month = month
        self.income = income
        self.expenses = expenses
        self.net = net
        self.savingsRate = savingsRate
        self.categories = categories
        self.freedomVelocity = freedomVelocity
    }
}

public struct CategoryBreakdown: Codable, Sendable {
    public let category: String
    public let amount: Double
    public let transactionCount: Int
    public let percentageOfTotal: Double

    public init(category: String, amount: Double, transactionCount: Int, percentageOfTotal: Double) {
        self.category = category
        self.amount = amount
        self.transactionCount = transactionCount
        self.percentageOfTotal = percentageOfTotal
    }
}
