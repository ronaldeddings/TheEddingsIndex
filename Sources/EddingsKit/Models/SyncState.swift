import Foundation
import GRDB

public struct SyncState: Codable, Sendable {
    public var sources: [String: SourceState]
    public var seenTransactionIds: Set<String> = []

    public struct SourceState: Codable, Sendable {
        public var lastSyncAt: Date?
        public var lastStatus: Status
        public var recordsSynced: Int
        public var error: String?

        public enum Status: String, Codable, Sendable {
            case success
            case partial
            case failed
            case neverRun = "never_run"
        }

        public init(lastSyncAt: Date? = nil, lastStatus: Status, recordsSynced: Int, error: String? = nil) {
            self.lastSyncAt = lastSyncAt
            self.lastStatus = lastStatus
            self.recordsSynced = recordsSynced
            self.error = error
        }
    }

    public static var empty: SyncState {
        SyncState(sources: [:], seenTransactionIds: [])
    }

    public init(sources: [String: SourceState], seenTransactionIds: Set<String> = []) {
        self.sources = sources
        self.seenTransactionIds = seenTransactionIds
    }
}

public struct PendingEmbedding: Codable, Sendable {
    public var id: Int64?
    public var sourceTable: String
    public var sourceId: Int64
    public var vector512: Data?
    public var vector4096: Data?
    public var createdAt: Date?

    public init(
        id: Int64? = nil,
        sourceTable: String,
        sourceId: Int64,
        vector512: Data? = nil,
        vector4096: Data? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.sourceTable = sourceTable
        self.sourceId = sourceId
        self.vector512 = vector512
        self.vector4096 = vector4096
        self.createdAt = createdAt
    }
}

extension PendingEmbedding: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pendingEmbeddings"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
