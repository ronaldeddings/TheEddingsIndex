import Foundation
import GRDB

public struct Contact: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var name: String
    public var email: String?
    public var companyId: Int64?
    public var slackUserId: String?
    public var role: String?
    public var isMe: Bool = false
    public var firstSeenAt: Date?
    public var lastSeenAt: Date?
    public var emailCount: Int = 0
    public var meetingCount: Int = 0
    public var slackCount: Int = 0
    public var tags: String?
    public var notes: String?

    public static let databaseTableName = "contacts"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        name: String,
        email: String? = nil,
        companyId: Int64? = nil,
        slackUserId: String? = nil,
        role: String? = nil,
        isMe: Bool = false,
        firstSeenAt: Date? = nil,
        lastSeenAt: Date? = nil,
        emailCount: Int = 0,
        meetingCount: Int = 0,
        slackCount: Int = 0,
        tags: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.companyId = companyId
        self.slackUserId = slackUserId
        self.role = role
        self.isMe = isMe
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.emailCount = emailCount
        self.meetingCount = meetingCount
        self.slackCount = slackCount
        self.tags = tags
        self.notes = notes
    }
}
