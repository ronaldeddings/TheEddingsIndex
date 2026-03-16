import Foundation
import GRDB

public struct FTSIndex: Sendable {
    private let dbPool: DatabasePool

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    public enum FTSTable: String, Sendable {
        case documents
        case emailChunks
        case slackChunks
        case transcriptChunks
        case financialTransactions

        var ftsTableName: String { "\(rawValue)_fts" }

        var bm25Weights: String {
            switch self {
            case .documents:
                return "5.0, 1.0"
            case .emailChunks:
                return "3.0, 2.0, 1.0"
            case .slackChunks:
                return "2.0, 1.0"
            case .transcriptChunks:
                return "2.0, 1.0"
            case .financialTransactions:
                return "3.0, 2.0, 1.0"
            }
        }

        var sourceTable: SearchResult.SourceTable {
            switch self {
            case .documents: return .documents
            case .emailChunks: return .emailChunks
            case .slackChunks: return .slackChunks
            case .transcriptChunks: return .transcriptChunks
            case .financialTransactions: return .financialTransactions
            }
        }
    }

    public struct FTSResult: Sendable {
        public let id: Int64
        public let sourceTable: SearchResult.SourceTable
        public let score: Double
        public let snippet: String?
    }

    public func search(
        query: String,
        tables: [FTSTable] = FTSTable.allCases,
        limit: Int = 50,
        year: Int? = nil,
        month: Int? = nil
    ) throws -> [FTSResult] {
        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        var allResults: [FTSResult] = []

        try dbPool.read { db in
            for table in tables {
                let results = try searchTable(
                    db: db,
                    table: table,
                    query: sanitized,
                    limit: limit,
                    year: year,
                    month: month
                )
                allResults.append(contentsOf: results)
            }
        }

        allResults.sort { $0.score < $1.score }
        return Array(allResults.prefix(limit))
    }

    private func searchTable(
        db: Database,
        table: FTSTable,
        query: String,
        limit: Int,
        year: Int?,
        month: Int?
    ) throws -> [FTSResult] {
        var conditions: [String] = []
        var arguments: [DatabaseValue] = [query.databaseValue]

        if let year, table != .documents {
            conditions.append("\(table.rawValue).year = ?")
            arguments.append(year.databaseValue)
        }
        if let month, table != .documents {
            conditions.append("\(table.rawValue).month = ?")
            arguments.append(month.databaseValue)
        }

        let whereClause = conditions.isEmpty
            ? ""
            : "AND " + conditions.joined(separator: " AND ")

        let sql = """
            SELECT \(table.rawValue).rowid AS id,
                   bm25(\(table.ftsTableName), \(table.bm25Weights)) AS rank,
                   snippet(\(table.ftsTableName), 0, '<b>', '</b>', '...', 32) AS snippet
            FROM \(table.ftsTableName)
            JOIN \(table.rawValue) ON \(table.rawValue).rowid = \(table.ftsTableName).rowid
            WHERE \(table.ftsTableName) MATCH ?
            \(whereClause)
            ORDER BY rank
            LIMIT ?
            """

        arguments.append(limit.databaseValue)

        do {
            let rows = try Row.fetchAll(
                db,
                sql: sql,
                arguments: StatementArguments(arguments)
            )

            return rows.map { row in
                FTSResult(
                    id: row["id"],
                    sourceTable: table.sourceTable,
                    score: row["rank"],
                    snippet: row["snippet"]
                )
            }
        } catch {
            let tokenized = tokenizeQuery(query)
            guard !tokenized.isEmpty else { return [] }
            var fallbackArgs = arguments
            fallbackArgs[0] = tokenized.databaseValue
            let rows = try Row.fetchAll(
                db,
                sql: sql,
                arguments: StatementArguments(fallbackArgs)
            )
            return rows.map { row in
                FTSResult(
                    id: row["id"],
                    sourceTable: table.sourceTable,
                    score: row["rank"],
                    snippet: row["snippet"]
                )
            }
        }
    }

    private static let ftsOperatorPattern = try! NSRegularExpression(
        pattern: "\\b(AND|OR|NOT|NEAR)\\b"
    )

    private func sanitizeFTSQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            return trimmed
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let hasOperators = Self.ftsOperatorPattern.firstMatch(in: trimmed, range: range) != nil

        if hasOperators {
            return trimmed
        }

        return tokenizeQuery(trimmed)
    }

    private func tokenizeQuery(_ query: String) -> String {
        let tokens = query.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { token in
                let cleaned = token.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                return cleaned.isEmpty ? nil : cleaned
            }
            .compactMap { $0 }
        return tokens.joined(separator: " ")
    }
}

extension FTSIndex.FTSTable: CaseIterable {}
