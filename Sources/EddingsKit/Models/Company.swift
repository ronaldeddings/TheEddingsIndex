import Foundation
import GRDB

public struct Company: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var name: String
    public var domain: String?
    public var aliases: String?
    public var industry: String?
    public var isCustomer: Bool = false
    public var isPartner: Bool = false
    public var isProspect: Bool = false
    public var notes: String?

    public static let databaseTableName = "companies"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        name: String,
        domain: String? = nil,
        aliases: String? = nil,
        industry: String? = nil,
        isCustomer: Bool = false,
        isPartner: Bool = false,
        isProspect: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.aliases = aliases
        self.industry = industry
        self.isCustomer = isCustomer
        self.isPartner = isPartner
        self.isProspect = isProspect
        self.notes = notes
    }
}
