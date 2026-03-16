import Foundation
import GRDB

public struct Document: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var path: String
    public var filename: String
    public var content: String?
    public var `extension`: String?
    public var fileSize: Int64?
    public var modifiedAt: Date?
    public var area: String?
    public var category: String?
    public var contentType: String?
    public var createdAt: Date?
    public var indexedAt: Date?

    public static let databaseTableName = "documents"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        path: String,
        filename: String,
        content: String? = nil,
        extension: String? = nil,
        fileSize: Int64? = nil,
        modifiedAt: Date? = nil,
        area: String? = nil,
        category: String? = nil,
        contentType: String? = nil,
        createdAt: Date? = nil,
        indexedAt: Date? = nil
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.content = content
        self.extension = `extension`
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.area = area
        self.category = category
        self.contentType = contentType
        self.createdAt = createdAt
        self.indexedAt = indexedAt
    }
}
