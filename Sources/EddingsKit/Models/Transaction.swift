import Foundation
import GRDB

public struct FinancialTransaction: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var transactionId: String
    public var source: String
    public var accountId: String
    public var accountName: String?
    public var institution: String?
    public var transactionDate: Date
    // TODO: PRD-01 specifies Decimal — evaluate migration cost for financial precision
    public var amount: Double
    public var description: String?
    public var payee: String?
    public var category: String?
    public var subcategory: String?
    public var isRecurring: Bool = false
    public var isTransfer: Bool = false
    public var tags: String?
    public var year: Int?
    public var month: Int?
    public var categoryModifiedAt: Date?

    public static let databaseTableName = "financialTransactions"

    public enum Source: String, Codable, Sendable {
        case simplefin
        case qbo
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        transactionId: String,
        source: String,
        accountId: String,
        accountName: String? = nil,
        institution: String? = nil,
        transactionDate: Date,
        amount: Double,
        description: String? = nil,
        payee: String? = nil,
        category: String? = nil,
        subcategory: String? = nil,
        isRecurring: Bool = false,
        isTransfer: Bool = false,
        tags: String? = nil,
        year: Int? = nil,
        month: Int? = nil,
        categoryModifiedAt: Date? = nil
    ) {
        self.id = id
        self.transactionId = transactionId
        self.source = source
        self.accountId = accountId
        self.accountName = accountName
        self.institution = institution
        self.transactionDate = transactionDate
        self.amount = amount
        self.description = description
        self.payee = payee
        self.category = category
        self.subcategory = subcategory
        self.isRecurring = isRecurring
        self.isTransfer = isTransfer
        self.tags = tags
        self.year = year
        self.month = month
        self.categoryModifiedAt = categoryModifiedAt
    }
}
