import Foundation
import GRDB

public actor QueryEngine {
    private let ftsIndex: FTSIndex
    private let vectorIndex: VectorIndex
    private let ranker: HybridRanker
    private let dbPool: DatabasePool

    public init(dbPool: DatabasePool, vectorIndex: VectorIndex) {
        self.ftsIndex = FTSIndex(dbPool: dbPool)
        self.vectorIndex = vectorIndex
        self.ranker = HybridRanker()
        self.dbPool = dbPool
    }

    public func search(
        query: String,
        embedding: [Float]? = nil,
        sources: [FTSIndex.FTSTable]? = nil,
        year: Int? = nil,
        month: Int? = nil,
        limit: Int = 20
    ) async throws -> [SearchResult] {
        let tables = sources ?? FTSIndex.FTSTable.allCases

        let ftsResults = try ftsIndex.search(
            query: query,
            tables: tables,
            limit: limit * 3,
            year: year,
            month: month
        )

        var semanticResults: [(id: Int64, sourceTable: SearchResult.SourceTable, distance: Float)] = []
        if let embedding {
            let hits = try await vectorIndex.search(vector: embedding, count: limit * 3)
            let vectorKeys = hits.map { Int64($0.key) }
            let keyMap = try resolveVectorKeys(vectorKeys, dbPool: dbPool)
            semanticResults = hits.compactMap { hit in
                let vk = Int64(hit.key)
                guard let mapped = keyMap[vk] else { return nil }
                return (id: mapped.sourceId, sourceTable: mapped.sourceTable, distance: hit.distance)
            }
        }

        let ranked = ranker.rank(ftsResults: ftsResults, semanticResults: semanticResults)
        let topResults = Array(ranked.prefix(limit))

        return try resolveResults(topResults, dbPool: dbPool)
    }
}

private func resolveVectorKeys(_ keys: [Int64], dbPool: DatabasePool) throws -> [Int64: (sourceTable: SearchResult.SourceTable, sourceId: Int64)] {
    guard !keys.isEmpty else { return [:] }
    return try dbPool.read { db in
        let maps = try VectorKeyMap
            .filter(keys.contains(Column("vectorKey")))
            .fetchAll(db)
        var result: [Int64: (sourceTable: SearchResult.SourceTable, sourceId: Int64)] = [:]
        for m in maps {
            if let st = m.toSourceTable() {
                result[m.vectorKey] = (sourceTable: st, sourceId: m.sourceId)
            }
        }
        return result
    }
}

private func resolveResults(_ ranked: [RankedResult], dbPool: DatabasePool) throws -> [SearchResult] {
    try dbPool.read { db in
        ranked.compactMap { result in
            resolveResult(db: db, result: result)
        }
    }
}

private func resolveResult(db: Database, result: RankedResult) -> SearchResult? {
    let ftsSnippet = result.snippet

    switch result.sourceTable {
    case .documents:
        guard let doc = try? Document.fetchOne(db, key: result.id) else { return nil }
        return SearchResult(
            id: result.id,
            sourceTable: .documents,
            title: doc.filename,
            snippet: ftsSnippet ?? doc.content.map { String($0.prefix(200)) },
            date: doc.modifiedAt,
            score: result.score,
            metadata: ["path": doc.path]
        )
    case .emailChunks:
        guard let email = try? EmailChunk.fetchOne(db, key: result.id) else { return nil }
        return SearchResult(
            id: result.id,
            sourceTable: .emailChunks,
            title: email.subject ?? "Email",
            snippet: ftsSnippet ?? email.chunkText.map { String($0.prefix(200)) },
            date: email.emailDate,
            score: result.score,
            metadata: [
                "from": email.fromName ?? "",
                "fromEmail": email.fromEmail ?? ""
            ]
        )
    case .slackChunks:
        guard let slack = try? SlackChunk.fetchOne(db, key: result.id) else { return nil }
        return SearchResult(
            id: result.id,
            sourceTable: .slackChunks,
            title: slack.channel ?? "Slack",
            snippet: ftsSnippet ?? slack.chunkText.map { String($0.prefix(200)) },
            date: slack.messageDate,
            score: result.score,
            metadata: ["channel": slack.channel ?? ""]
        )
    case .transcriptChunks:
        guard let chunk = try? TranscriptChunk.fetchOne(db, key: result.id) else { return nil }
        return SearchResult(
            id: result.id,
            sourceTable: .transcriptChunks,
            title: chunk.speakerName ?? "Transcript",
            snippet: ftsSnippet ?? chunk.chunkText.map { String($0.prefix(200)) },
            date: nil,
            score: result.score,
            metadata: ["meetingId": chunk.meetingId ?? ""]
        )
    case .financialTransactions:
        guard let txn = try? FinancialTransaction.fetchOne(db, key: result.id) else { return nil }
        return SearchResult(
            id: result.id,
            sourceTable: .financialTransactions,
            title: txn.payee ?? txn.description ?? "Transaction",
            snippet: ftsSnippet ?? txn.description,
            date: txn.transactionDate,
            score: result.score,
            metadata: [
                "amount": String(txn.amount),
                "category": txn.category ?? ""
            ]
        )
    case .contacts, .meetings:
        return nil
    }
}
