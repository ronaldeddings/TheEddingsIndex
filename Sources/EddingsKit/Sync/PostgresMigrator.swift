import Foundation
import GRDB
import os

public struct PostgresMigrator: Sendable {
    private let dbManager: DatabaseManager
    private let pgPort: Int
    private let pgDatabase: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "migrate")

    public init(
        dbManager: DatabaseManager,
        pgPort: Int = 4432,
        pgDatabase: String = "vram_embeddings"
    ) {
        self.dbManager = dbManager
        self.pgPort = pgPort
        self.pgDatabase = pgDatabase
    }

    public struct MigrationResult: Sendable {
        public var documents: Int = 0
        public var emailChunks: Int = 0
        public var slackChunks: Int = 0
        public var transcriptChunks: Int = 0
        public var contacts: Int = 0
        public var companies: Int = 0
        public var meetings: Int = 0
    }

    public func migrate() throws -> MigrationResult {
        logger.info("Starting PostgreSQL migration from localhost:\(pgPort)/\(pgDatabase)")

        var result = MigrationResult()

        logger.info("Dropping FTS5 tables for bulk insert performance")
        try dropFTSTables()

        result.documents = try migrateDocuments()
        result.emailChunks = try migrateEmailChunks()
        result.slackChunks = try migrateSlackChunks()
        result.transcriptChunks = try migrateTranscriptChunks()
        result.contacts = try migrateContacts()
        result.companies = try migrateCompanies()
        result.meetings = try migrateMeetings()

        logger.info("Rebuilding FTS5 indexes")
        try rebuildFTSTables()


        logger.info("Migration complete: docs=\(result.documents) emails=\(result.emailChunks) slack=\(result.slackChunks) transcripts=\(result.transcriptChunks) contacts=\(result.contacts) companies=\(result.companies) meetings=\(result.meetings)")

        return result
    }

    private static let fieldSep = "\u{1F}"
    private static let fieldSepChar: Character = "\u{1F}"

    private func psqlExport(query: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [
            "psql", "-p", String(pgPort), "-d", pgDatabase,
            "-t", "-A", "-F", Self.fieldSep,
            "-c", query
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func psqlStreamingExport(query: String, batchSize: Int = 50000, handler: (String) throws -> Void) throws {
        let countQuery = "SELECT count(*) FROM (\(query)) sub"
        let countStr = try psqlExport(query: countQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        let totalRows = Int(countStr) ?? 0
        logger.info("  Total rows: \(totalRows)")

        var offset = 0
        while offset < totalRows {
            let pagedQuery = "\(query) ORDER BY id LIMIT \(batchSize) OFFSET \(offset)"
            let output = try psqlExport(query: pagedQuery)
            try handler(output)
            offset += batchSize
            if offset % 100000 == 0 || offset >= totalRows {
                logger.info("  Exported \(min(offset, totalRows))/\(totalRows) rows")
            }
        }
    }

    private func migrateDocuments() throws -> Int {
        logger.info("Migrating documents...")
        var count = 0

        try psqlStreamingExport(
            query: "SELECT id, path, filename, extension, REPLACE(REPLACE(LEFT(content, 10000), E'\\n', ' '), E'\\r', ' '), file_size, modified_at, area, category, content_type FROM documents",
            batchSize: 50000
        ) { output in
            try dbManager.dbPool.write { db in
                for line in output.split(separator: "\n") {
                    let fields = line.split(separator: Self.fieldSepChar, omittingEmptySubsequences: false).map(String.init)
                    guard fields.count >= 10 else { continue }

                    var doc = Document(
                        id: Int64(fields[0]),
                        path: fields[1],
                        filename: fields[2],
                        content: fields[4].isEmpty ? nil : fields[4],
                        extension: fields[3].isEmpty ? nil : fields[3],
                        fileSize: Int64(fields[5]),
                        modifiedAt: self.parseTimestamp(fields[6]),
                        area: fields[7].isEmpty ? nil : fields[7],
                        category: fields[8].isEmpty ? nil : fields[8],
                        contentType: fields[9].isEmpty ? nil : fields[9]
                    )
                    try doc.insert(db, onConflict: .ignore)
                    count += 1
                }
            }
            self.logger.info("  documents: \(count) migrated...")
        }

        logger.info("Migrated \(count) documents")
        return count
    }

    private func migrateEmailChunks() throws -> Int {
        logger.info("Migrating email chunks...")
        var count = 0

        try psqlStreamingExport(
            query: """
                SELECT id, email_id, email_path, REPLACE(REPLACE(subject, E'\\n', ' '), E'\\r', ' '), from_name, from_email,
                       array_to_string(to_emails, ','), array_to_string(cc_emails, ','),
                       REPLACE(REPLACE(chunk_text, E'\\n', ' '), E'\\r', ' '), chunk_index, array_to_string(labels, ','),
                       email_date, year, month, quarter, is_sent_by_me, has_attachments,
                       is_reply, thread_id, from_contact_id
                FROM email_chunks
                """,
            batchSize: 50000
        ) { output in
            try dbManager.dbPool.write { db in
                for line in output.split(separator: "\n") {
                    let fields = line.split(separator: Self.fieldSepChar, omittingEmptySubsequences: false).map(String.init)
                    guard fields.count >= 20 else { continue }

                    var chunk = EmailChunk(
                        id: Int64(fields[0]),
                        emailId: fields[1],
                        emailPath: fields[2].isEmpty ? nil : fields[2],
                        subject: fields[3].isEmpty ? nil : fields[3],
                        fromName: fields[4].isEmpty ? nil : fields[4],
                        fromEmail: fields[5].isEmpty ? nil : fields[5],
                        toEmails: fields[6].isEmpty ? nil : fields[6],
                        ccEmails: fields[7].isEmpty ? nil : fields[7],
                        chunkText: fields[8].isEmpty ? nil : fields[8],
                        chunkIndex: Int(fields[9]),
                        labels: fields[10].isEmpty ? nil : fields[10],
                        emailDate: self.parseTimestamp(fields[11]),
                        year: Int(fields[12]),
                        month: Int(fields[13]),
                        quarter: Int(fields[14]),
                        isSentByMe: fields[15] == "t",
                        hasAttachments: fields[16] == "t",
                        isReply: fields[17] == "t",
                        threadId: fields[18].isEmpty ? nil : fields[18],
                        fromContactId: Int64(fields[19])
                    )
                    try chunk.insert(db, onConflict: .ignore)
                    count += 1
                }
            }
            self.logger.info("  email chunks: \(count) migrated...")
        }

        logger.info("Migrated \(count) email chunks")
        return count
    }

    private func migrateSlackChunks() throws -> Int {
        logger.info("Migrating slack chunks...")
        let output = try psqlExport(query: """
            SELECT id, channel, channel_type, array_to_string(speakers, ','),
                   REPLACE(REPLACE(chunk_text, E'\\n', ' '), E'\\r', ' '), message_date, year, month,
                   has_files, has_reactions, thread_ts, is_thread_reply
            FROM slack_chunks
            """)

        var count = 0
        try dbManager.dbPool.write { db in
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: Self.fieldSepChar, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 12 else { continue }

                var chunk = SlackChunk(
                    id: Int64(fields[0]),
                    channel: fields[1],
                    channelType: fields[2],
                    speakers: fields[3].isEmpty ? nil : fields[3],
                    chunkText: fields[4].isEmpty ? nil : fields[4],
                    messageDate: parseTimestamp(fields[5]),
                    year: Int(fields[6]),
                    month: Int(fields[7]),
                    hasFiles: fields[8] == "t",
                    hasReactions: fields[9] == "t",
                    threadTs: fields[10].isEmpty ? nil : fields[10],
                    isThreadReply: fields[11] == "t"
                )
                try chunk.insert(db, onConflict: .ignore)
                count += 1
            }
        }

        logger.info("Migrated \(count) slack chunks")
        return count
    }

    private func migrateTranscriptChunks() throws -> Int {
        logger.info("Migrating transcript chunks...")
        let output = try psqlExport(query: """
            SELECT c.id, c.file_path, REPLACE(REPLACE(c.chunk_text, E'\\n', ' '), E'\\r', ' '), c.chunk_index,
                   c.speaker_name, c.meeting_id
            FROM chunks c
            WHERE c.content_type = 'transcript'
            """)

        var count = 0
        try dbManager.dbPool.write { db in
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: Self.fieldSepChar, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 6 else { continue }

                var chunk = TranscriptChunk(
                    id: Int64(fields[0]),
                    filePath: fields[1].isEmpty ? nil : fields[1],
                    chunkText: fields[2].isEmpty ? nil : fields[2],
                    chunkIndex: Int(fields[3]),
                    speakerName: fields[4].isEmpty ? nil : fields[4],
                    meetingId: fields[5].isEmpty ? nil : fields[5]
                )
                try chunk.insert(db, onConflict: .ignore)
                count += 1
            }
        }

        logger.info("Migrated \(count) transcript chunks")
        return count
    }

    private func migrateContacts() throws -> Int {
        logger.info("Migrating contacts...")
        let output = try psqlExport(query: """
            SELECT id, name, email, company_id, role,
                   first_seen_at, last_seen_at, email_count, meeting_count, slack_count
            FROM contacts
            """)

        var count = 0
        try dbManager.dbPool.write { db in
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: Self.fieldSepChar, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 10 else { continue }

                var contact = Contact(
                    id: Int64(fields[0]),
                    name: fields[1],
                    email: fields[2].isEmpty ? nil : fields[2],
                    companyId: Int64(fields[3]),
                    role: fields[4].isEmpty ? nil : fields[4],
                    firstSeenAt: parseTimestamp(fields[5]),
                    lastSeenAt: parseTimestamp(fields[6]),
                    emailCount: Int(fields[7]) ?? 0,
                    meetingCount: Int(fields[8]) ?? 0,
                    slackCount: Int(fields[9]) ?? 0
                )
                try contact.insert(db, onConflict: .ignore)
                count += 1
            }
        }

        logger.info("Migrated \(count) contacts")
        return count
    }

    private func migrateCompanies() throws -> Int {
        logger.info("Migrating companies...")
        let output = try psqlExport(query: """
            SELECT id, name, domain
            FROM companies
            """)

        var count = 0
        try dbManager.dbPool.write { db in
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: Self.fieldSepChar, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 3 else { continue }

                var company = Company(
                    id: Int64(fields[0]),
                    name: fields[1],
                    domain: fields[2].isEmpty ? nil : fields[2]
                )
                try company.insert(db, onConflict: .ignore)
                count += 1
            }
        }

        logger.info("Migrated \(count) companies")
        return count
    }

    private func migrateMeetings() throws -> Int {
        logger.info("Migrating meetings...")
        let output = try psqlExport(query: """
            SELECT id, meeting_id, title, start_time, end_time,
                   duration_minutes, is_internal, participant_count,
                   video_url, file_path
            FROM transcript_meetings
            """)

        var count = 0
        try dbManager.dbPool.write { db in
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: Self.fieldSepChar, omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 10 else { continue }

                let startTime = parseTimestamp(fields[3])
                let components = startTime.map { Calendar.current.dateComponents([.year, .month], from: $0) }

                var meeting = Meeting(
                    id: Int64(fields[0]),
                    meetingId: fields[1],
                    title: fields[2].isEmpty ? nil : fields[2],
                    startTime: startTime,
                    endTime: parseTimestamp(fields[4]),
                    durationMinutes: Int(fields[5]),
                    year: components?.year,
                    month: components?.month,
                    isInternal: fields[6] == "t",
                    participantCount: Int(fields[7]),
                    videoUrl: fields[8].isEmpty ? nil : fields[8],
                    filePath: fields[9].isEmpty ? nil : fields[9]
                )
                try meeting.insert(db, onConflict: .ignore)
                count += 1
            }
        }

        logger.info("Migrated \(count) meetings")
        return count
    }

    private func dropFTSTables() throws {
        try dbManager.dbPool.write { db in
            let tables = ["documents", "emailChunks", "slackChunks", "transcriptChunks", "financialTransactions"]
            for table in tables {
                for suffix in ["_ai", "_ad", "_au"] {
                    try db.execute(sql: "DROP TRIGGER IF EXISTS __\(table)_fts\(suffix)")
                    try db.execute(sql: "DROP TRIGGER IF EXISTS \(table)_fts\(suffix)")
                }
                try db.execute(sql: "DROP TABLE IF EXISTS \(table)_fts")
            }
        }
    }

    private func rebuildFTSTables() throws {
        try dbManager.dbPool.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
                    filename, content, content=documents, content_rowid=id,
                    tokenize='unicode61'
                )
                """)
            try db.execute(sql: "INSERT INTO documents_fts(documents_fts) VALUES('rebuild')")
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS documents_fts_ai AFTER INSERT ON documents BEGIN
                    INSERT INTO documents_fts(rowid, filename, content) VALUES (new.rowid, new.filename, new.content);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS documents_fts_ad AFTER DELETE ON documents BEGIN
                    INSERT INTO documents_fts(documents_fts, rowid, filename, content) VALUES('delete', old.rowid, old.filename, old.content);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS documents_fts_au AFTER UPDATE ON documents BEGIN
                    INSERT INTO documents_fts(documents_fts, rowid, filename, content) VALUES('delete', old.rowid, old.filename, old.content);
                    INSERT INTO documents_fts(rowid, filename, content) VALUES (new.rowid, new.filename, new.content);
                END
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS emailChunks_fts USING fts5(
                    subject, fromName, chunkText, content=emailChunks, content_rowid=id,
                    tokenize='unicode61'
                )
                """)
            try db.execute(sql: "INSERT INTO emailChunks_fts(emailChunks_fts) VALUES('rebuild')")
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS emailChunks_fts_ai AFTER INSERT ON emailChunks BEGIN
                    INSERT INTO emailChunks_fts(rowid, subject, fromName, chunkText) VALUES (new.rowid, new.subject, new.fromName, new.chunkText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS emailChunks_fts_ad AFTER DELETE ON emailChunks BEGIN
                    INSERT INTO emailChunks_fts(emailChunks_fts, rowid, subject, fromName, chunkText) VALUES('delete', old.rowid, old.subject, old.fromName, old.chunkText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS emailChunks_fts_au AFTER UPDATE ON emailChunks BEGIN
                    INSERT INTO emailChunks_fts(emailChunks_fts, rowid, subject, fromName, chunkText) VALUES('delete', old.rowid, old.subject, old.fromName, old.chunkText);
                    INSERT INTO emailChunks_fts(rowid, subject, fromName, chunkText) VALUES (new.rowid, new.subject, new.fromName, new.chunkText);
                END
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS slackChunks_fts USING fts5(
                    channel, chunkText, content=slackChunks, content_rowid=id,
                    tokenize='unicode61'
                )
                """)
            try db.execute(sql: "INSERT INTO slackChunks_fts(slackChunks_fts) VALUES('rebuild')")
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS slackChunks_fts_ai AFTER INSERT ON slackChunks BEGIN
                    INSERT INTO slackChunks_fts(rowid, channel, chunkText) VALUES (new.rowid, new.channel, new.chunkText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS slackChunks_fts_ad AFTER DELETE ON slackChunks BEGIN
                    INSERT INTO slackChunks_fts(slackChunks_fts, rowid, channel, chunkText) VALUES('delete', old.rowid, old.channel, old.chunkText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS slackChunks_fts_au AFTER UPDATE ON slackChunks BEGIN
                    INSERT INTO slackChunks_fts(slackChunks_fts, rowid, channel, chunkText) VALUES('delete', old.rowid, old.channel, old.chunkText);
                    INSERT INTO slackChunks_fts(rowid, channel, chunkText) VALUES (new.rowid, new.channel, new.chunkText);
                END
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS transcriptChunks_fts USING fts5(
                    speakerName, chunkText, content=transcriptChunks, content_rowid=id,
                    tokenize='unicode61'
                )
                """)
            try db.execute(sql: "INSERT INTO transcriptChunks_fts(transcriptChunks_fts) VALUES('rebuild')")
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS transcriptChunks_fts_ai AFTER INSERT ON transcriptChunks BEGIN
                    INSERT INTO transcriptChunks_fts(rowid, speakerName, chunkText) VALUES (new.rowid, new.speakerName, new.chunkText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS transcriptChunks_fts_ad AFTER DELETE ON transcriptChunks BEGIN
                    INSERT INTO transcriptChunks_fts(transcriptChunks_fts, rowid, speakerName, chunkText) VALUES('delete', old.rowid, old.speakerName, old.chunkText);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS transcriptChunks_fts_au AFTER UPDATE ON transcriptChunks BEGIN
                    INSERT INTO transcriptChunks_fts(transcriptChunks_fts, rowid, speakerName, chunkText) VALUES('delete', old.rowid, old.speakerName, old.chunkText);
                    INSERT INTO transcriptChunks_fts(rowid, speakerName, chunkText) VALUES (new.rowid, new.speakerName, new.chunkText);
                END
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS financialTransactions_fts USING fts5(
                    payee, description, category, content=financialTransactions, content_rowid=id,
                    tokenize='unicode61'
                )
                """)
            try db.execute(sql: "INSERT INTO financialTransactions_fts(financialTransactions_fts) VALUES('rebuild')")
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS financialTransactions_fts_ai AFTER INSERT ON financialTransactions BEGIN
                    INSERT INTO financialTransactions_fts(rowid, payee, description, category) VALUES (new.rowid, new.payee, new.description, new.category);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS financialTransactions_fts_ad AFTER DELETE ON financialTransactions BEGIN
                    INSERT INTO financialTransactions_fts(financialTransactions_fts, rowid, payee, description, category) VALUES('delete', old.rowid, old.payee, old.description, old.category);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS financialTransactions_fts_au AFTER UPDATE ON financialTransactions BEGIN
                    INSERT INTO financialTransactions_fts(financialTransactions_fts, rowid, payee, description, category) VALUES('delete', old.rowid, old.payee, old.description, old.category);
                    INSERT INTO financialTransactions_fts(rowid, payee, description, category) VALUES (new.rowid, new.payee, new.description, new.category);
                END
                """)
        }

        logger.info("FTS5 indexes and sync triggers rebuilt")
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func parseTimestamp(_ str: String) -> Date? {
        guard !str.isEmpty else { return nil }
        if let date = Self.timestampFormatter.date(from: str) { return date }
        if let date = Self.dateOnlyFormatter.date(from: str) { return date }
        return nil
    }
}
