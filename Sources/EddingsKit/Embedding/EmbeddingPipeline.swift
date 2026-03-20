import Foundation
import GRDB
import USearch
import os

public actor EmbeddingPipeline {
    private let dbPool: DatabasePool
    private let vectorIndex: VectorIndex
    private let nlEmbedder: NLEmbedder
    private let qwenClient: QwenClient
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "embedding-pipeline")

    private static let embeddableTables: [(table: String, textColumn: String, compositeColumns: [String]?)] = [
        ("emailChunks", "chunkText", nil),
        ("slackChunks", "chunkText", nil),
        ("transcriptChunks", "chunkText", nil),
        ("documents", "content", nil),
        ("financialTransactions", "", ["description", "payee"]),
    ]

    private static let batchSize = 100

    public struct Stats: Sendable {
        public var totalEmbedded: Int = 0
        public var totalFailed: Int = 0
        public var retriedPending: Int = 0
        public var byTable: [String: Int] = [:]
    }

    public init(dbPool: DatabasePool, vectorIndex: VectorIndex) {
        self.dbPool = dbPool
        self.vectorIndex = vectorIndex
        self.nlEmbedder = NLEmbedder()
        self.qwenClient = QwenClient()
    }

    public func run() async throws -> Stats {
        var stats = Stats()

        let retriedCount = try await retryPendingEmbeddings()
        stats.retriedPending = retriedCount

        for tableDef in Self.embeddableTables {
            let count = try await processTable(
                table: tableDef.table,
                textColumn: tableDef.textColumn,
                compositeColumns: tableDef.compositeColumns
            )
            stats.totalEmbedded += count
            if count > 0 {
                stats.byTable[tableDef.table] = count
            }
        }

        if stats.totalEmbedded > 0 || stats.retriedPending > 0 {
            try await vectorIndex.save()
            logger.info("VectorIndex saved after embedding \(stats.totalEmbedded) new + \(stats.retriedPending) retried records")
        }

        return stats
    }

    private func processTable(table: String, textColumn: String, compositeColumns: [String]?) async throws -> Int {
        let unembeddedIds = try Self.fetchUnembeddedIds(table: table, dbPool: dbPool)
        guard !unembeddedIds.isEmpty else { return 0 }

        logger.info("Found \(unembeddedIds.count) unembedded records in \(table)")
        var embedded = 0
        let startTime = Date()

        for batchStart in stride(from: 0, to: unembeddedIds.count, by: Self.batchSize) {
            let batchEnd = min(batchStart + Self.batchSize, unembeddedIds.count)
            let batchIds = Array(unembeddedIds[batchStart..<batchEnd])

            let texts = try Self.fetchTexts(table: table, ids: batchIds, textColumn: textColumn, compositeColumns: compositeColumns, dbPool: dbPool)

            let batchStartTime = Date()
            var batchEmbedded = 0

            for (id, text) in texts {
                guard !text.isEmpty else { continue }

                do {
                    let vector512 = try await nlEmbedder.embed(text)

                    var vector4096: [Float]? = nil
                    #if os(macOS)
                    do {
                        vector4096 = try await qwenClient.embed(text)
                    } catch {
                        logger.debug("Qwen unavailable for \(table)/\(id), using 512-dim only")
                    }
                    #endif

                    let nextKey = try Self.nextVectorKey(dbPool: dbPool)
                    try await vectorIndex.add(key: nextKey, vector512: vector512, vector4096: vector4096)

                    let revision = nlEmbedder.currentRevision
                    try Self.insertVectorKeyMap(
                        dbPool: dbPool,
                        vectorKey: Int64(nextKey),
                        sourceTable: table,
                        sourceId: id,
                        embeddingRevision: revision
                    )

                    batchEmbedded += 1
                } catch {
                    logger.warning("Embedding failed for \(table)/\(id): \(error)")
                    try Self.writePendingEmbedding(dbPool: dbPool, table: table, sourceId: id)
                }
            }

            embedded += batchEmbedded
            let batchDuration = Date().timeIntervalSince(batchStartTime)
            logger.info("Embedded \(embedded)/\(unembeddedIds.count) \(table) (\(batchEmbedded) in \(String(format: "%.1f", batchDuration))s)")
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        logger.info("Completed \(table): \(embedded) embeddings in \(String(format: "%.1f", totalDuration))s")
        return embedded
    }

    private nonisolated static func fetchUnembeddedIds(table: String, dbPool: DatabasePool) throws -> [Int64] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id FROM \(table)
                    WHERE id NOT IN (
                        SELECT sourceId FROM vectorKeyMap WHERE sourceTable = ?
                    )
                    ORDER BY id
                """,
                arguments: [table]
            )
            return rows.map { $0["id"] as Int64 }
        }
    }

    private nonisolated static func fetchTexts(table: String, ids: [Int64], textColumn: String, compositeColumns: [String]?, dbPool: DatabasePool) throws -> [(Int64, String)] {
        try dbPool.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")

            if let columns = compositeColumns {
                let selectExpr = columns.map { "COALESCE(\($0), '')" }.joined(separator: " || ' ' || ")
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT id, \(selectExpr) AS combinedText FROM \(table) WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(ids)
                )
                return rows.compactMap { row in
                    let id: Int64 = row["id"]
                    let text: String = row["combinedText"]
                    return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (id, text)
                }
            } else {
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT id, \(textColumn) FROM \(table) WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(ids)
                )
                return rows.compactMap { row in
                    let id: Int64 = row["id"]
                    guard let text: String = row[textColumn] else { return nil }
                    return text.isEmpty ? nil : (id, text)
                }
            }
        }
    }

    private nonisolated static func nextVectorKey(dbPool: DatabasePool) throws -> USearchKey {
        try dbPool.read { db in
            let maxKey = try Int64.fetchOne(db, sql: "SELECT MAX(vectorKey) FROM vectorKeyMap") ?? 0
            return USearchKey(maxKey + 1)
        }
    }

    private nonisolated static func insertVectorKeyMap(dbPool: DatabasePool, vectorKey: Int64, sourceTable: String, sourceId: Int64, embeddingRevision: Int) throws {
        try dbPool.write { db in
            let keyMap = VectorKeyMap(
                vectorKey: vectorKey,
                sourceTable: sourceTable,
                sourceId: sourceId,
                embeddingRevision: embeddingRevision
            )
            try keyMap.insert(db)
        }
    }

    private nonisolated static func writePendingEmbedding(dbPool: DatabasePool, table: String, sourceId: Int64) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "INSERT INTO pendingEmbeddings (sourceTable, sourceId) VALUES (?, ?)",
                arguments: [table, sourceId]
            )
        }
    }

    public func embedRecord(table: String, id: Int64) async throws {
        let textColumn = Self.textColumnFor(table)
        let compositeColumns = Self.compositeColumnsFor(table)

        let texts = try Self.fetchTexts(
            table: table,
            ids: [id],
            textColumn: textColumn,
            compositeColumns: compositeColumns,
            dbPool: dbPool
        )
        guard let (_, text) = texts.first, !text.isEmpty else { return }

        do {
            let vector512 = try await nlEmbedder.embed(text)

            var vector4096: [Float]? = nil
            #if os(macOS)
            do {
                vector4096 = try await qwenClient.embed(text)
            } catch {
                logger.debug("Qwen unavailable for \(table)/\(id), using 512-dim only")
            }
            #endif

            let nextKey = try Self.nextVectorKey(dbPool: dbPool)
            try await vectorIndex.add(key: nextKey, vector512: vector512, vector4096: vector4096)

            let revision = nlEmbedder.currentRevision
            try Self.insertVectorKeyMap(
                dbPool: dbPool,
                vectorKey: Int64(nextKey),
                sourceTable: table,
                sourceId: id,
                embeddingRevision: revision
            )
        } catch {
            logger.warning("Embedding failed for \(table)/\(id): \(error)")
            try Self.writePendingEmbedding(dbPool: dbPool, table: table, sourceId: id)
        }
    }

    public func saveIndex() async throws {
        try await vectorIndex.save()
    }

    private func retryPendingEmbeddings() async throws -> Int {
        let pending: [(id: Int64, table: String, sourceId: Int64)] = try Self.fetchPending(dbPool: dbPool)

        guard !pending.isEmpty else { return 0 }
        logger.info("Retrying \(pending.count) pending embeddings")

        var succeeded = 0

        for item in pending {
            let texts = try Self.fetchTexts(table: item.table, ids: [item.sourceId], textColumn: Self.textColumnFor(item.table), compositeColumns: Self.compositeColumnsFor(item.table), dbPool: dbPool)
            guard let (_, text) = texts.first, !text.isEmpty else {
                try Self.deletePending(dbPool: dbPool, id: item.id)
                continue
            }

            do {
                let vector512 = try await nlEmbedder.embed(text)
                var vector4096: [Float]? = nil
                #if os(macOS)
                vector4096 = try? await qwenClient.embed(text)
                #endif

                let nextKey = try Self.nextVectorKey(dbPool: dbPool)
                try await vectorIndex.add(key: nextKey, vector512: vector512, vector4096: vector4096)

                let revision = nlEmbedder.currentRevision
                try Self.insertVectorKeyMapAndDeletePending(
                    dbPool: dbPool,
                    vectorKey: Int64(nextKey),
                    sourceTable: item.table,
                    sourceId: item.sourceId,
                    embeddingRevision: revision,
                    pendingId: item.id
                )
                succeeded += 1
            } catch {
                logger.warning("Retry failed for \(item.table)/\(item.sourceId): \(error)")
            }
        }

        logger.info("Retried pending: \(succeeded)/\(pending.count) succeeded")
        return succeeded
    }

    private nonisolated static func fetchPending(dbPool: DatabasePool) throws -> [(id: Int64, table: String, sourceId: Int64)] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, sourceTable, sourceId FROM pendingEmbeddings ORDER BY id LIMIT 500")
            return rows.map { (id: $0["id"] as Int64, table: $0["sourceTable"] as String, sourceId: $0["sourceId"] as Int64) }
        }
    }

    private nonisolated static func insertVectorKeyMapAndDeletePending(dbPool: DatabasePool, vectorKey: Int64, sourceTable: String, sourceId: Int64, embeddingRevision: Int, pendingId: Int64) throws {
        try dbPool.write { db in
            let keyMap = VectorKeyMap(
                vectorKey: vectorKey,
                sourceTable: sourceTable,
                sourceId: sourceId,
                embeddingRevision: embeddingRevision
            )
            try keyMap.insert(db)
            try db.execute(sql: "DELETE FROM pendingEmbeddings WHERE id = ?", arguments: [pendingId])
        }
    }

    private nonisolated static func deletePending(dbPool: DatabasePool, id: Int64) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM pendingEmbeddings WHERE id = ?", arguments: [id])
        }
    }

    private nonisolated static func textColumnFor(_ table: String) -> String {
        switch table {
        case "emailChunks", "slackChunks", "transcriptChunks": return "chunkText"
        case "documents": return "content"
        default: return ""
        }
    }

    private nonisolated static func compositeColumnsFor(_ table: String) -> [String]? {
        table == "financialTransactions" ? ["description", "payee"] : nil
    }
}
