import Foundation
import GRDB

public struct Meeting: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var meetingId: String
    public var title: String?
    public var startTime: Date?
    public var endTime: Date?
    public var durationMinutes: Int?
    public var year: Int?
    public var month: Int?
    public var isInternal: Bool = false
    public var participantCount: Int?
    public var videoUrl: String?
    public var filePath: String?

    public static let databaseTableName = "meetings"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        meetingId: String,
        title: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        durationMinutes: Int? = nil,
        year: Int? = nil,
        month: Int? = nil,
        isInternal: Bool = false,
        participantCount: Int? = nil,
        videoUrl: String? = nil,
        filePath: String? = nil
    ) {
        self.id = id
        self.meetingId = meetingId
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.year = year
        self.month = month
        self.isInternal = isInternal
        self.participantCount = participantCount
        self.videoUrl = videoUrl
        self.filePath = filePath
    }
}
