import Foundation
import GRDB
import os

public final class DatabaseManager: Sendable {
    public let dbPool: DatabasePool
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "database")

    public static var sharedDatabasePath: String? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.hackervalley.eddingsindex"
        ) else { return nil }
        return containerURL.appending(path: "eddingsindex.sqlite").path()
    }

    public init(path: String, foreignKeysEnabled: Bool = true) throws {
        var config = Configuration()
        config.foreignKeysEnabled = foreignKeysEnabled
        dbPool = try DatabasePool(path: path, configuration: config)
        try migrator.migrate(dbPool)
        logger.info("Database initialized at \(path)")
    }

    public static func temporary() throws -> DatabaseManager {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appending(path: "eddingsindex-\(UUID().uuidString).sqlite").path()
        return try DatabaseManager(path: dbPath)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_core_tables") { db in

            // -- Companies (must come before contacts for FK) --
            try db.create(table: "companies") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("domain", .text).unique()
                t.column("aliases", .text)
                t.column("industry", .text)
                t.column("isCustomer", .boolean).defaults(to: false)
                t.column("isPartner", .boolean).defaults(to: false)
                t.column("isProspect", .boolean).defaults(to: false)
                t.column("notes", .text)
            }

            // -- Contacts --
            try db.create(table: "contacts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("email", .text)
                t.column("companyId", .integer).references("companies", onDelete: .setNull)
                t.column("slackUserId", .text)
                t.column("role", .text)
                t.column("isMe", .boolean).defaults(to: false)
                t.column("firstSeenAt", .datetime)
                t.column("lastSeenAt", .datetime)
                t.column("emailCount", .integer).defaults(to: 0)
                t.column("meetingCount", .integer).defaults(to: 0)
                t.column("slackCount", .integer).defaults(to: 0)
                t.column("tags", .text)
                t.column("notes", .text)
            }

            // -- Documents --
            try db.create(table: "documents") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("filename", .text).notNull()
                t.column("content", .text)
                t.column("extension", .text)
                t.column("fileSize", .integer)
                t.column("modifiedAt", .datetime)
                t.column("area", .text)
                t.column("category", .text)
                t.column("contentType", .text)
            }

            try db.create(virtualTable: "documents_fts", using: FTS5()) { t in
                t.synchronize(withTable: "documents")
                t.tokenizer = .unicode61()
                t.column("filename")
                t.column("content")
            }

            // -- Email Chunks --
            try db.create(table: "emailChunks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("emailId", .text).notNull().unique()
                t.column("emailPath", .text)
                t.column("subject", .text)
                t.column("fromName", .text)
                t.column("fromEmail", .text)
                t.column("toEmails", .text)
                t.column("ccEmails", .text)
                t.column("chunkText", .text)
                t.column("chunkIndex", .integer)
                t.column("labels", .text)
                t.column("emailDate", .datetime)
                t.column("year", .integer)
                t.column("month", .integer)
                t.column("quarter", .integer)
                t.column("isSentByMe", .boolean).defaults(to: false)
                t.column("hasAttachments", .boolean).defaults(to: false)
                t.column("isReply", .boolean).defaults(to: false)
                t.column("threadId", .text)
                t.column("fromContactId", .integer)
                    .references("contacts", onDelete: .setNull)
            }

            try db.create(virtualTable: "emailChunks_fts", using: FTS5()) { t in
                t.synchronize(withTable: "emailChunks")
                t.tokenizer = .unicode61()
                t.column("subject")
                t.column("fromName")
                t.column("chunkText")
            }

            // -- Slack Chunks --
            try db.create(table: "slackChunks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("channel", .text)
                t.column("channelType", .text)
                t.column("speakers", .text)
                t.column("chunkText", .text)
                t.column("messageDate", .datetime)
                t.column("year", .integer)
                t.column("month", .integer)
                t.column("hasFiles", .boolean).defaults(to: false)
                t.column("hasReactions", .boolean).defaults(to: false)
                t.column("threadTs", .text)
                t.column("isThreadReply", .boolean).defaults(to: false)
            }

            try db.create(virtualTable: "slackChunks_fts", using: FTS5()) { t in
                t.synchronize(withTable: "slackChunks")
                t.tokenizer = .unicode61()
                t.column("channel")
                t.column("chunkText")
            }

            // -- Transcript Chunks --
            try db.create(table: "transcriptChunks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filePath", .text)
                t.column("chunkText", .text)
                t.column("chunkIndex", .integer)
                t.column("speakers", .text)
                t.column("speakerName", .text)
                t.column("meetingId", .text)
                t.column("year", .integer)
                t.column("month", .integer)
            }

            try db.create(virtualTable: "transcriptChunks_fts", using: FTS5()) { t in
                t.synchronize(withTable: "transcriptChunks")
                t.tokenizer = .unicode61()
                t.column("speakerName")
                t.column("chunkText")
            }

            // -- Financial Transactions --
            try db.create(table: "financialTransactions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("transactionId", .text).notNull().unique()
                t.column("source", .text).notNull()
                t.column("accountId", .text).notNull()
                t.column("accountName", .text)
                t.column("institution", .text)
                t.column("transactionDate", .datetime).notNull()
                t.column("amount", .double).notNull()
                t.column("description", .text)
                t.column("payee", .text)
                t.column("category", .text)
                t.column("subcategory", .text)
                t.column("isRecurring", .boolean).defaults(to: false)
                t.column("isTransfer", .boolean).defaults(to: false)
                t.column("tags", .text)
                t.column("year", .integer)
                t.column("month", .integer)
                t.column("categoryModifiedAt", .datetime)
            }

            try db.create(virtualTable: "financialTransactions_fts", using: FTS5()) { t in
                t.synchronize(withTable: "financialTransactions")
                t.tokenizer = .unicode61()
                t.column("payee")
                t.column("description")
                t.column("category")
            }

            // -- Meetings --
            try db.create(table: "meetings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .text).notNull().unique()
                t.column("title", .text)
                t.column("startTime", .datetime)
                t.column("endTime", .datetime)
                t.column("durationMinutes", .integer)
                t.column("year", .integer)
                t.column("month", .integer)
                t.column("isInternal", .boolean).defaults(to: false)
                t.column("participantCount", .integer)
                t.column("videoUrl", .text)
                t.column("filePath", .text)
            }

            // -- Financial Snapshots --
            try db.create(table: "financialSnapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("snapshotDate", .date).notNull()
                t.column("accountId", .text).notNull()
                t.column("accountName", .text)
                t.column("institution", .text)
                t.column("accountType", .text)
                t.column("balance", .double).notNull()
                t.column("availableBalance", .double)
                t.column("currency", .text).defaults(to: "USD")
                t.column("source", .text).notNull()
                t.uniqueKey(["snapshotDate", "accountId", "source"])
            }

            // -- Pending Embeddings (crash recovery) --
            try db.create(table: "pendingEmbeddings") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sourceTable", .text).notNull()
                t.column("sourceId", .integer).notNull()
                t.column("vector512", .blob)
                t.column("vector4096", .blob)
                t.column("createdAt", .datetime).defaults(sql: "CURRENT_TIMESTAMP")
            }

            // -- Vector Key Map (maps USearch keys to source table + record ID) --
            try db.create(table: "vectorKeyMap") { t in
                t.column("vectorKey", .integer).notNull().primaryKey()
                t.column("sourceTable", .text).notNull()
                t.column("sourceId", .integer).notNull()
            }

            // -- Widget Snapshots (pre-calculated data for WidgetKit) --
            try db.create(table: "widgetSnapshots") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .datetime).notNull()
                t.column("weeklyAmount", .double).notNull()
                t.column("weeklyTarget", .double).notNull()
                t.column("velocityPercent", .double).notNull()
                t.column("netWorth", .double).notNull()
                t.column("dailyChange", .double).notNull()
            }

            // -- Indexes --
            try db.create(index: "idx_email_date", on: "emailChunks", columns: ["emailDate"])
            try db.create(index: "idx_email_contact", on: "emailChunks", columns: ["fromContactId"])
            try db.create(index: "idx_slack_date", on: "slackChunks", columns: ["messageDate"])
            try db.create(index: "idx_transcript_meeting", on: "transcriptChunks", columns: ["meetingId"])
            try db.create(index: "idx_txn_date", on: "financialTransactions", columns: ["transactionDate"])
            try db.create(index: "idx_txn_category", on: "financialTransactions", columns: ["category"])
            try db.create(index: "idx_meeting_date", on: "meetings", columns: ["startTime"])
            try db.create(index: "idx_contact_email", on: "contacts", columns: ["email"])
            try db.create(index: "idx_snap_date", on: "financialSnapshots", columns: ["snapshotDate"])
        }

        migrator.registerMigration("v2_full_content") { db in

            // -- meetingParticipants junction table --
            try db.create(table: "meetingParticipants") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .integer)
                    .notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("contactId", .integer)
                    .notNull()
                    .references("contacts", onDelete: .cascade)
                t.column("role", .text)
                t.column("speakingTimeSeconds", .integer)
                t.uniqueKey(["meetingId", "contactId"])
            }
            try db.create(index: "idx_mp_meeting", on: "meetingParticipants", columns: ["meetingId"])
            try db.create(index: "idx_mp_contact", on: "meetingParticipants", columns: ["contactId"])

            // -- emailChunks: add attachment metadata --
            try db.alter(table: "emailChunks") { t in
                t.add(column: "attachmentCount", .integer).defaults(to: 0)
                t.add(column: "attachmentNames", .text)
                t.add(column: "bccEmails", .text)
                t.add(column: "importance", .text)
            }

            // -- slackChunks: add rich metadata --
            try db.alter(table: "slackChunks") { t in
                t.add(column: "userIds", .text)
                t.add(column: "realNames", .text)
                t.add(column: "companies", .text)
                t.add(column: "quarter", .integer)
                t.add(column: "messageCount", .integer)
                t.add(column: "isEdited", .boolean).defaults(to: false)
                t.add(column: "replyCount", .integer).defaults(to: 0)
                t.add(column: "emojiReactions", .text)
                t.add(column: "chunkIndex", .integer)
            }

            // -- transcriptChunks: add temporal + confidence --
            try db.alter(table: "transcriptChunks") { t in
                t.add(column: "quarter", .integer)
                t.add(column: "startTime", .text)
                t.add(column: "endTime", .text)
                t.add(column: "speakerConfidence", .double)
            }

            // -- meetings: add quarter + description --
            try db.alter(table: "meetings") { t in
                t.add(column: "quarter", .integer)
                t.add(column: "description", .text)
                t.add(column: "teamDomain", .text)
            }

            // -- documents: add file date tracking --
            try db.alter(table: "documents") { t in
                t.add(column: "createdAt", .datetime)
                t.add(column: "indexedAt", .datetime)
            }

            // -- New indexes for filter support --
            try db.create(index: "idx_email_quarter", on: "emailChunks", columns: ["quarter"])
            try db.create(index: "idx_email_sent", on: "emailChunks", columns: ["isSentByMe"])
            try db.create(index: "idx_email_attachments", on: "emailChunks", columns: ["hasAttachments"])
            try db.create(index: "idx_slack_quarter", on: "slackChunks", columns: ["quarter"])
            try db.create(index: "idx_transcript_quarter", on: "transcriptChunks", columns: ["quarter"])
            try db.create(index: "idx_meeting_quarter", on: "meetings", columns: ["quarter"])
            try db.create(index: "idx_meeting_internal", on: "meetings", columns: ["isInternal"])

            // -- Backfill quarter for existing data --
            try db.execute(sql: """
                UPDATE emailChunks SET quarter = CASE
                    WHEN month BETWEEN 1 AND 3 THEN 1
                    WHEN month BETWEEN 4 AND 6 THEN 2
                    WHEN month BETWEEN 7 AND 9 THEN 3
                    WHEN month BETWEEN 10 AND 12 THEN 4
                END WHERE quarter IS NULL AND month IS NOT NULL
            """)

            try db.execute(sql: """
                UPDATE slackChunks SET quarter = CASE
                    WHEN month BETWEEN 1 AND 3 THEN 1
                    WHEN month BETWEEN 4 AND 6 THEN 2
                    WHEN month BETWEEN 7 AND 9 THEN 3
                    WHEN month BETWEEN 10 AND 12 THEN 4
                END WHERE quarter IS NULL AND month IS NOT NULL
            """)

            try db.execute(sql: """
                UPDATE transcriptChunks SET quarter = CASE
                    WHEN month BETWEEN 1 AND 3 THEN 1
                    WHEN month BETWEEN 4 AND 6 THEN 2
                    WHEN month BETWEEN 7 AND 9 THEN 3
                    WHEN month BETWEEN 10 AND 12 THEN 4
                END WHERE quarter IS NULL AND month IS NOT NULL
            """)

            try db.execute(sql: """
                UPDATE meetings SET quarter = CASE
                    WHEN month BETWEEN 1 AND 3 THEN 1
                    WHEN month BETWEEN 4 AND 6 THEN 2
                    WHEN month BETWEEN 7 AND 9 THEN 3
                    WHEN month BETWEEN 10 AND 12 THEN 4
                END WHERE quarter IS NULL AND month IS NOT NULL
            """)
        }

        return migrator
    }
}
