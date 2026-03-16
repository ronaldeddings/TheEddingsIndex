import Foundation
import GRDB

public struct MeetingParticipant: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var meetingId: Int64
    public var contactId: Int64
    public var role: String?
    public var speakingTimeSeconds: Int?

    public static let databaseTableName = "meetingParticipants"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        meetingId: Int64,
        contactId: Int64,
        role: String? = nil,
        speakingTimeSeconds: Int? = nil
    ) {
        self.id = id
        self.meetingId = meetingId
        self.contactId = contactId
        self.role = role
        self.speakingTimeSeconds = speakingTimeSeconds
    }
}
