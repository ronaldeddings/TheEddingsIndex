import Foundation
import GRDB

public struct EmailChunk: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var emailId: String
    public var emailPath: String?
    public var subject: String?
    public var fromName: String?
    public var fromEmail: String?
    public var toEmails: String?
    public var ccEmails: String?
    public var chunkText: String?
    public var chunkIndex: Int?
    public var labels: String?
    public var emailDate: Date?
    public var year: Int?
    public var month: Int?
    public var quarter: Int?
    public var isSentByMe: Bool = false
    public var hasAttachments: Bool = false
    public var isReply: Bool = false
    public var threadId: String?
    public var fromContactId: Int64?

    public static let databaseTableName = "emailChunks"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    public init(
        id: Int64? = nil,
        emailId: String,
        emailPath: String? = nil,
        subject: String? = nil,
        fromName: String? = nil,
        fromEmail: String? = nil,
        toEmails: String? = nil,
        ccEmails: String? = nil,
        chunkText: String? = nil,
        chunkIndex: Int? = nil,
        labels: String? = nil,
        emailDate: Date? = nil,
        year: Int? = nil,
        month: Int? = nil,
        quarter: Int? = nil,
        isSentByMe: Bool = false,
        hasAttachments: Bool = false,
        isReply: Bool = false,
        threadId: String? = nil,
        fromContactId: Int64? = nil
    ) {
        self.id = id
        self.emailId = emailId
        self.emailPath = emailPath
        self.subject = subject
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.toEmails = toEmails
        self.ccEmails = ccEmails
        self.chunkText = chunkText
        self.chunkIndex = chunkIndex
        self.labels = labels
        self.emailDate = emailDate
        self.year = year
        self.month = month
        self.quarter = quarter
        self.isSentByMe = isSentByMe
        self.hasAttachments = hasAttachments
        self.isReply = isReply
        self.threadId = threadId
        self.fromContactId = fromContactId
    }
}
