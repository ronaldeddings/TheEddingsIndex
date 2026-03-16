import Testing
import Foundation
@testable import EddingsKit
import GRDB

@Suite("FTS5 BM25 Search")
struct FTSSearchTests {

    func makeDB() throws -> DatabaseManager {
        try DatabaseManager.temporary()
    }

    @Test("Insert and search documents by filename")
    func searchDocumentsByFilename() throws {
        let db = try makeDB()
        try db.dbPool.write { db in
            var doc = Document(
                path: "/Volumes/VRAM/10-19_Work/proposal.md",
                filename: "Optro Sponsorship Proposal",
                content: "Looking at $45K for the podcast sponsorship package."
            )
            try doc.insert(db)
        }

        let fts = FTSIndex(dbPool: db.dbPool)
        let results = try fts.search(query: "Optro", tables: [.documents])

        #expect(!results.isEmpty)
        #expect(results[0].sourceTable == .documents)
    }

    @Test("BM25 ranks subject match above body match for emails")
    func emailSubjectRanksHigher() throws {
        let db = try makeDB()
        try db.dbPool.write { db in
            var emailSubject = EmailChunk(
                emailId: "email-1",
                subject: "Optro Partnership Agreement",
                fromName: "Sarah Chen",
                chunkText: "Please find attached the standard terms."
            )
            try emailSubject.insert(db)

            var emailBody = EmailChunk(
                emailId: "email-2",
                subject: "Weekly Update",
                fromName: "Emily Humphrey",
                chunkText: "Quick note — Optro sent the signed contract today."
            )
            try emailBody.insert(db)
        }

        let fts = FTSIndex(dbPool: db.dbPool)
        let results = try fts.search(query: "Optro", tables: [.emailChunks])

        #expect(results.count == 2)
        #expect(results[0].id == 1)
    }

    @Test("Search transcripts by speaker name")
    func searchTranscriptsBySpeaker() throws {
        let db = try makeDB()
        try db.dbPool.write { db in
            var chunk = TranscriptChunk(
                chunkText: "I think we should focus on the CISO audience for Q2.",
                speakerName: "Emily Humphrey",
                meetingId: "meeting-1",
                year: 2026,
                month: 3
            )
            try chunk.insert(db)
        }

        let fts = FTSIndex(dbPool: db.dbPool)
        let results = try fts.search(query: "Emily", tables: [.transcriptChunks])

        #expect(!results.isEmpty)
        #expect(results[0].sourceTable == .transcriptChunks)
    }

    @Test("Search financial transactions by payee")
    func searchTransactionsByPayee() throws {
        let db = try makeDB()
        try db.dbPool.write { db in
            var txn = FinancialTransaction(
                transactionId: "txn-1",
                source: "simplefin",
                accountId: "acct-1",
                transactionDate: Date(),
                amount: -59.99,
                description: "Monthly subscription",
                payee: "Adobe Creative Cloud",
                year: 2026,
                month: 3
            )
            try txn.insert(db)
        }

        let fts = FTSIndex(dbPool: db.dbPool)
        let results = try fts.search(query: "Adobe", tables: [.financialTransactions])

        #expect(!results.isEmpty)
    }

    @Test("Year/month filtering narrows results")
    func temporalFiltering() throws {
        let db = try makeDB()
        try db.dbPool.write { db in
            var march = SlackChunk(
                channel: "#general",
                chunkText: "Q2 planning meeting tomorrow",
                year: 2026,
                month: 3
            )
            try march.insert(db)

            var feb = SlackChunk(
                channel: "#general",
                chunkText: "Q2 planning is coming up",
                year: 2026,
                month: 2
            )
            try feb.insert(db)
        }

        let fts = FTSIndex(dbPool: db.dbPool)
        let marchOnly = try fts.search(query: "planning", tables: [.slackChunks], year: 2026, month: 3)

        #expect(marchOnly.count == 1)
    }

    @Test("Cross-source search returns results from all tables")
    func crossSourceSearch() throws {
        let db = try makeDB()
        try db.dbPool.write { db in
            var doc = Document(path: "/test.md", filename: "CrowdStrike Notes", content: "CrowdStrike partnership details")
            try doc.insert(db)

            var email = EmailChunk(emailId: "e1", subject: "CrowdStrike Intro", chunkText: "Dana Liu reaching out")
            try email.insert(db)

            var slack = SlackChunk(channel: "#deals", chunkText: "CrowdStrike lead came in today")
            try slack.insert(db)
        }

        let fts = FTSIndex(dbPool: db.dbPool)
        let results = try fts.search(query: "CrowdStrike")

        #expect(results.count == 3)

        let sources = Set(results.map(\.sourceTable))
        #expect(sources.contains(.documents))
        #expect(sources.contains(.emailChunks))
        #expect(sources.contains(.slackChunks))
    }

    @Test("Empty query returns no results")
    func emptyQuery() throws {
        let db = try makeDB()
        let fts = FTSIndex(dbPool: db.dbPool)
        let results = try fts.search(query: "")
        #expect(results.isEmpty)
    }
}
