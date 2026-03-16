import Foundation
import GRDB

public struct SlackChunk: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var channel: String?
    public var channelType: String?
    public var speakers: String?
    public var chunkText: String?
    public var messageDate: Date?
    public var year: Int?
    public var month: Int?
    public var hasFiles: Bool = false
    public var hasReactions: Bool = false
    public var threadTs: String?
    public var isThreadReply: Bool = false

    public static let databaseTableName = "slackChunks"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        channel: String? = nil,
        channelType: String? = nil,
        speakers: String? = nil,
        chunkText: String? = nil,
        messageDate: Date? = nil,
        year: Int? = nil,
        month: Int? = nil,
        hasFiles: Bool = false,
        hasReactions: Bool = false,
        threadTs: String? = nil,
        isThreadReply: Bool = false
    ) {
        self.id = id
        self.channel = channel
        self.channelType = channelType
        self.speakers = speakers
        self.chunkText = chunkText
        self.messageDate = messageDate
        self.year = year
        self.month = month
        self.hasFiles = hasFiles
        self.hasReactions = hasReactions
        self.threadTs = threadTs
        self.isThreadReply = isThreadReply
    }
}
