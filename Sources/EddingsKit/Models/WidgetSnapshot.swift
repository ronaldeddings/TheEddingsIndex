import Foundation
import GRDB

public struct WidgetSnapshot: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var date: Date
    public var weeklyAmount: Double
    public var weeklyTarget: Double
    public var velocityPercent: Double
    public var netWorth: Double
    public var dailyChange: Double

    public static let databaseTableName = "widgetSnapshots"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        date: Date = Date(),
        weeklyAmount: Double,
        weeklyTarget: Double,
        velocityPercent: Double,
        netWorth: Double,
        dailyChange: Double
    ) {
        self.id = id
        self.date = date
        self.weeklyAmount = weeklyAmount
        self.weeklyTarget = weeklyTarget
        self.velocityPercent = velocityPercent
        self.netWorth = netWorth
        self.dailyChange = dailyChange
    }
}
