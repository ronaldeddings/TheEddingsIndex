import Foundation
import GRDB

public struct TranscriptChunk: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var filePath: String?
    public var chunkText: String?
    public var chunkIndex: Int?
    public var speakers: String?
    public var speakerName: String?
    public var meetingId: String?
    public var year: Int?
    public var month: Int?
    public var quarter: Int?
    public var startTime: String?
    public var endTime: String?
    public var speakerConfidence: Double?

    public static let databaseTableName = "transcriptChunks"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        filePath: String? = nil,
        chunkText: String? = nil,
        chunkIndex: Int? = nil,
        speakers: String? = nil,
        speakerName: String? = nil,
        meetingId: String? = nil,
        year: Int? = nil,
        month: Int? = nil,
        quarter: Int? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        speakerConfidence: Double? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.chunkText = chunkText
        self.chunkIndex = chunkIndex
        self.speakers = speakers
        self.speakerName = speakerName
        self.meetingId = meetingId
        self.year = year
        self.month = month
        self.quarter = quarter
        self.startTime = startTime
        self.endTime = endTime
        self.speakerConfidence = speakerConfidence
    }
}
