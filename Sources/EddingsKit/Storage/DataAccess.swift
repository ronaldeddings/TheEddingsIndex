import Foundation
import GRDB

public struct DataAccess: Sendable {
    public let dbPool: DatabasePool

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    // MARK: - Single Record Fetch

    public func fetchContact(id: Int64) throws -> Contact? {
        try dbPool.read { db in
            try Contact.fetchOne(db, key: id)
        }
    }

    public func fetchCompany(id: Int64) throws -> Company? {
        try dbPool.read { db in
            try Company.fetchOne(db, key: id)
        }
    }

    public func fetchMeeting(id: Int64) throws -> Meeting? {
        try dbPool.read { db in
            try Meeting.fetchOne(db, key: id)
        }
    }

    // MARK: - Relationship Traversal

    public func contactsForCompany(_ companyId: Int64) throws -> [Contact] {
        try dbPool.read { db in
            try Contact
                .filter(Column("companyId") == companyId)
                .order(sql: "emailCount + meetingCount + slackCount DESC")
                .fetchAll(db)
        }
    }

    public func participantsForMeeting(_ meetingId: Int64) throws -> [(participant: MeetingParticipant, contact: Contact?)] {
        try dbPool.read { db in
            let participants = try MeetingParticipant
                .filter(Column("meetingId") == meetingId)
                .fetchAll(db)
            return try participants.map { p in
                let contact = try Contact.fetchOne(db, key: p.contactId)
                return (participant: p, contact: contact)
            }
        }
    }

    public func transcriptsForMeeting(_ meetingId: String) throws -> [TranscriptChunk] {
        try dbPool.read { db in
            try TranscriptChunk
                .filter(Column("meetingId") == meetingId)
                .order(Column("chunkIndex"))
                .fetchAll(db)
        }
    }

    public func companyForContact(_ contact: Contact) throws -> Company? {
        guard let companyId = contact.companyId else { return nil }
        return try fetchCompany(id: companyId)
    }

    // MARK: - Aggregate Counts

    public func tableCounts() throws -> [String: Int] {
        try dbPool.read { db in
            var counts: [String: Int] = [:]
            counts["contacts"] = try Contact.fetchCount(db)
            counts["companies"] = try Company.fetchCount(db)
            counts["documents"] = try Document.fetchCount(db)
            counts["emailChunks"] = try EmailChunk.fetchCount(db)
            counts["slackChunks"] = try SlackChunk.fetchCount(db)
            counts["transcriptChunks"] = try TranscriptChunk.fetchCount(db)
            counts["financialTransactions"] = try FinancialTransaction.fetchCount(db)
            counts["financialSnapshots"] = try FinancialSnapshot.fetchCount(db)
            counts["meetings"] = try Meeting.fetchCount(db)
            return counts
        }
    }

    // MARK: - Interaction Timeline

    public struct InteractionRecord: Sendable, Identifiable {
        public let id: String
        public let sourceTable: SearchResult.SourceTable
        public let title: String
        public let detail: String
        public let date: Date
    }

    public func interactionTimeline(
        contactName: String,
        contactEmail: String?,
        limit: Int = 20
    ) throws -> [InteractionRecord] {
        try dbPool.read { db in
            var records: [InteractionRecord] = []

            let emails = try EmailChunk
                .filter(Column("fromName") == contactName ||
                        (contactEmail != nil ? Column("fromEmail") == contactEmail! : Column("fromEmail") == ""))
                .order(Column("emailDate").desc)
                .limit(limit)
                .fetchAll(db)
            for e in emails {
                if let date = e.emailDate {
                    records.append(InteractionRecord(
                        id: "email-\(e.id ?? 0)",
                        sourceTable: .emailChunks,
                        title: e.subject ?? "Email",
                        detail: String((e.chunkText ?? "").prefix(120)),
                        date: date
                    ))
                }
            }

            let slacks = try SlackChunk
                .filter(Column("speakers").like("%\(contactName)%"))
                .order(Column("messageDate").desc)
                .limit(limit)
                .fetchAll(db)
            for s in slacks {
                if let date = s.messageDate {
                    records.append(InteractionRecord(
                        id: "slack-\(s.id ?? 0)",
                        sourceTable: .slackChunks,
                        title: s.channel ?? "Slack",
                        detail: String((s.chunkText ?? "").prefix(120)),
                        date: date
                    ))
                }
            }

            let transcripts = try TranscriptChunk
                .filter(Column("speakerName") == contactName ||
                        Column("speakers").like("%\(contactName)%"))
                .order(Column("startTime").desc)
                .limit(limit)
                .fetchAll(db)
            for t in transcripts {
                let date = ISO8601DateFormatter().date(from: t.startTime ?? "") ?? Date.distantPast
                records.append(InteractionRecord(
                    id: "transcript-\(t.id ?? 0)",
                    sourceTable: .transcriptChunks,
                    title: t.speakerName ?? "Meeting",
                    detail: String((t.chunkText ?? "").prefix(120)),
                    date: date
                ))
            }

            records.sort { $0.date > $1.date }
            return Array(records.prefix(limit))
        }
    }

    // MARK: - Financial Aggregations

    public func spendingByCategory(since: Date) throws -> [(category: String, amount: Double)] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT category, SUM(amount) as total
                FROM financialTransactions
                WHERE transactionDate >= ? AND amount < 0 AND isTransfer = 0
                GROUP BY category
                ORDER BY total ASC
                """, arguments: [since])
            return rows.map { row in
                (category: (row["category"] as String?) ?? "Uncategorized",
                 amount: row["total"] as Double)
            }
        }
    }

    public func incomeBySource(since: Date) throws -> [(source: String, amount: Double)] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT COALESCE(payee, category, 'Other') as source, SUM(amount) as total
                FROM financialTransactions
                WHERE transactionDate >= ? AND amount > 0 AND isTransfer = 0
                GROUP BY source
                ORDER BY total DESC
                """, arguments: [since])
            return rows.map { row in
                (source: row["source"] as String,
                 amount: row["total"] as Double)
            }
        }
    }

    public func recentTransactions(limit: Int = 20) throws -> [FinancialTransaction] {
        try dbPool.read { db in
            try FinancialTransaction
                .order(Column("transactionDate").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func snapshotHistory(since: Date) throws -> [FinancialSnapshot] {
        try dbPool.read { db in
            try FinancialSnapshot
                .filter(Column("snapshotDate") >= since)
                .order(Column("snapshotDate"))
                .fetchAll(db)
        }
    }

    public func latestSnapshots() throws -> [FinancialSnapshot] {
        try dbPool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.*
                FROM financialSnapshots s
                INNER JOIN (
                    SELECT accountId, MAX(snapshotDate) as maxDate
                    FROM financialSnapshots
                    GROUP BY accountId
                ) latest ON s.accountId = latest.accountId AND s.snapshotDate = latest.maxDate
                ORDER BY s.balance DESC
                """)
                .map { try FinancialSnapshot(row: $0) }
        }
    }

    public func debtAccounts() throws -> [FinancialSnapshot] {
        try dbPool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.*
                FROM financialSnapshots s
                INNER JOIN (
                    SELECT accountId, MAX(snapshotDate) as maxDate
                    FROM financialSnapshots
                    WHERE accountType IN ('creditCard', 'loan', 'mortgage')
                    GROUP BY accountId
                ) latest ON s.accountId = latest.accountId AND s.snapshotDate = latest.maxDate
                ORDER BY s.balance ASC
                """)
                .map { try FinancialSnapshot(row: $0) }
        }
    }

    // MARK: - Contact Queries

    public func allContacts(excludeSelf: Bool = true) throws -> [Contact] {
        try dbPool.read { db in
            var request = Contact.order(sql: "emailCount + meetingCount + slackCount DESC")
            if excludeSelf {
                request = request.filter(Column("isMe") == false)
            }
            return try request.fetchAll(db)
        }
    }

    public func recentContacts(limit: Int = 5) throws -> [Contact] {
        try dbPool.read { db in
            try Contact
                .filter(Column("isMe") == false)
                .filter(Column("lastSeenAt") != nil)
                .order(Column("lastSeenAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func allCompanies() throws -> [Company] {
        try dbPool.read { db in
            try Company.order(Column("name")).fetchAll(db)
        }
    }

    // MARK: - Meeting Queries

    public func recentMeetings(limit: Int = 50) throws -> [Meeting] {
        try dbPool.read { db in
            try Meeting
                .order(Column("startTime").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func upcomingMeetings(limit: Int = 3) throws -> [Meeting] {
        try dbPool.read { db in
            try Meeting
                .filter(Column("startTime") >= Date())
                .order(Column("startTime"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Full Record for Search Result

    public func resolveSearchResult(_ result: SearchResult) throws -> (title: String, fullText: String, metadata: [String: String]) {
        try dbPool.read { db in
            switch result.sourceTable {
            case .emailChunks:
                if let chunk = try EmailChunk.fetchOne(db, key: result.id) {
                    return (
                        title: chunk.subject ?? "Email",
                        fullText: chunk.chunkText ?? "",
                        metadata: [
                            "from": chunk.fromName ?? chunk.fromEmail ?? "",
                            "to": chunk.toEmails ?? "",
                            "date": chunk.emailDate?.formatted(.dateTime) ?? "",
                            "sent": chunk.isSentByMe ? "true" : "false",
                        ]
                    )
                }
            case .slackChunks:
                if let chunk = try SlackChunk.fetchOne(db, key: result.id) {
                    return (
                        title: chunk.channel ?? "Slack",
                        fullText: chunk.chunkText ?? "",
                        metadata: [
                            "channel": chunk.channel ?? "",
                            "speakers": chunk.speakers ?? "",
                            "date": chunk.messageDate?.formatted(.dateTime) ?? "",
                        ]
                    )
                }
            case .transcriptChunks:
                if let chunk = try TranscriptChunk.fetchOne(db, key: result.id) {
                    return (
                        title: chunk.speakerName ?? "Transcript",
                        fullText: chunk.chunkText ?? "",
                        metadata: [
                            "speaker": chunk.speakerName ?? "",
                            "meeting": chunk.meetingId ?? "",
                            "start": chunk.startTime ?? "",
                        ]
                    )
                }
            case .documents:
                if let doc = try Document.fetchOne(db, key: result.id) {
                    return (
                        title: doc.filename,
                        fullText: doc.content ?? "",
                        metadata: [
                            "path": doc.path,
                            "modified": doc.modifiedAt?.formatted(.dateTime) ?? "",
                            "size": doc.fileSize.map { "\($0)" } ?? "",
                        ]
                    )
                }
            case .financialTransactions:
                if let tx = try FinancialTransaction.fetchOne(db, key: result.id) {
                    return (
                        title: tx.payee ?? tx.description ?? "Transaction",
                        fullText: [tx.payee, tx.description, tx.category].compactMap { $0 }.joined(separator: " — "),
                        metadata: [
                            "amount": tx.amount.formatted(.currency(code: "USD")),
                            "date": tx.transactionDate.formatted(.dateTime),
                            "category": tx.category ?? "",
                            "account": tx.accountName ?? "",
                        ]
                    )
                }
            case .contacts:
                if let c = try Contact.fetchOne(db, key: result.id) {
                    return (
                        title: c.name,
                        fullText: [c.name, c.email, c.role].compactMap { $0 }.joined(separator: " — "),
                        metadata: [
                            "email": c.email ?? "",
                            "role": c.role ?? "",
                            "emails": "\(c.emailCount)",
                            "meetings": "\(c.meetingCount)",
                        ]
                    )
                }
            case .meetings:
                if let m = try Meeting.fetchOne(db, key: result.id) {
                    return (
                        title: m.title ?? "Meeting",
                        fullText: m.description ?? "",
                        metadata: [
                            "date": m.startTime?.formatted(.dateTime) ?? "",
                            "duration": m.durationMinutes.map { "\($0) min" } ?? "",
                            "participants": m.participantCount.map { "\($0)" } ?? "",
                        ]
                    )
                }
            }
            return (title: result.title, fullText: result.fullContent ?? "", metadata: result.metadata ?? [:])
        }
    }
}
