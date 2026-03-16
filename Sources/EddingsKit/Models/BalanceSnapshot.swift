import Foundation
import GRDB

public struct FinancialSnapshot: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var snapshotDate: Date
    public var accountId: String
    public var accountName: String?
    public var institution: String?
    public var accountType: String?
    public var balance: Double
    public var availableBalance: Double?
    public var currency: String = "USD"
    public var source: String

    public static let databaseTableName = "financialSnapshots"

    public enum AccountType: String, Codable, Sendable {
        case checking, savings, creditCard, investment, mortgage, loan, other
    }

    public mutating func willInsert(_ db: Database) throws {
        snapshotDate = Calendar.current.startOfDay(for: snapshotDate)
    }

    public mutating func willUpdate(_ db: Database, columns: Set<String>) throws {
        if columns.contains("snapshotDate") {
            snapshotDate = Calendar.current.startOfDay(for: snapshotDate)
        }
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        snapshotDate: Date,
        accountId: String,
        accountName: String? = nil,
        institution: String? = nil,
        accountType: String? = nil,
        balance: Double,
        availableBalance: Double? = nil,
        currency: String = "USD",
        source: String
    ) {
        self.id = id
        self.snapshotDate = snapshotDate
        self.accountId = accountId
        self.accountName = accountName
        self.institution = institution
        self.accountType = accountType
        self.balance = balance
        self.availableBalance = availableBalance
        self.currency = currency
        self.source = source
    }
}
