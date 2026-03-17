import Foundation
import GRDB

public struct VectorKeyMap: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var vectorKey: Int64
    public var sourceTable: String
    public var sourceId: Int64
    public var embeddingRevision: Int?

    public static let databaseTableName = "vectorKeyMap"

    public init(vectorKey: Int64, sourceTable: String, sourceId: Int64, embeddingRevision: Int? = nil) {
        self.vectorKey = vectorKey
        self.sourceTable = sourceTable
        self.sourceId = sourceId
        self.embeddingRevision = embeddingRevision
    }

    public func toSourceTable() -> SearchResult.SourceTable? {
        SearchResult.SourceTable(rawValue: sourceTable)
    }
}
