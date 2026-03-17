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
        month: Int? = nil,
        quarter: Int? = nil,
        since: Date? = nil,
        person: String? = nil,
        speaker: String? = nil,
        sentByMe: Bool? = nil,
        hasAttachments: Bool? = nil,
        isInternal: Bool? = nil,
        includeSpam: Bool = false
    ) throws -> [FTSResult] {
        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        let hasTemporalFilter = year != nil || month != nil || quarter != nil || since != nil
        let effectiveSince: Date?
        if !hasTemporalFilter {
            effectiveSince = Calendar.current.date(byAdding: .month, value: -3, to: Date())
        } else {
            effectiveSince = since
        }

        var allResults: [FTSResult] = []

        try dbPool.read { db in
            for table in tables {
                let results = try searchTable(
                    db: db,
                    table: table,
                    query: sanitized,
                    limit: limit,
                    year: year,
                    month: month,
                    quarter: quarter,
                    since: effectiveSince,
                    person: person,
                    speaker: speaker,
                    sentByMe: sentByMe,
                    hasAttachments: hasAttachments,
                    isInternal: isInternal,
                    includeSpam: includeSpam
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
        month: Int?,
        quarter: Int?,
        since: Date?,
        person: String?,
        speaker: String?,
        sentByMe: Bool?,
        hasAttachments: Bool?,
        isInternal: Bool?,
        includeSpam: Bool
    ) throws -> [FTSResult] {
        var conditions: [String] = []
        var arguments: [DatabaseValue] = [query.databaseValue]

        if table != .documents {
            if let year {
                conditions.append("\(table.rawValue).year = ?")
                arguments.append(year.databaseValue)
            }
            if let month {
                conditions.append("\(table.rawValue).month = ?")
                arguments.append(month.databaseValue)
            }
            if let quarter {
                conditions.append("\(table.rawValue).quarter = ?")
                arguments.append(quarter.databaseValue)
            }
        }

        if let since, table != .documents {
            switch table {
            case .emailChunks:
                conditions.append("(\(table.rawValue).emailDate >= ? OR \(table.rawValue).emailDate IS NULL)")
                arguments.append(since.databaseValue)
            case .slackChunks:
                conditions.append("(\(table.rawValue).messageDate >= ? OR \(table.rawValue).messageDate IS NULL)")
                arguments.append(since.databaseValue)
            case .financialTransactions:
                conditions.append("(\(table.rawValue).transactionDate >= ? OR \(table.rawValue).transactionDate IS NULL)")
                arguments.append(since.databaseValue)
            default:
                break
            }
        }

        if let person {
            let likePattern = "%\(person)%"
            switch table {
            case .emailChunks:
                conditions.append("(\(table.rawValue).fromName LIKE ? OR \(table.rawValue).fromEmail LIKE ? OR \(table.rawValue).toEmails LIKE ?)")
                arguments.append(contentsOf: [likePattern.databaseValue, likePattern.databaseValue, likePattern.databaseValue])
            case .slackChunks:
                conditions.append("(\(table.rawValue).speakers LIKE ? OR \(table.rawValue).realNames LIKE ?)")
                arguments.append(contentsOf: [likePattern.databaseValue, likePattern.databaseValue])
            case .transcriptChunks:
                conditions.append("\(table.rawValue).speakers LIKE ?")
                arguments.append(likePattern.databaseValue)
            default:
                break
            }
        }

        if let speaker {
            let likePattern = "%\(speaker)%"
            switch table {
            case .slackChunks:
                conditions.append("(\(table.rawValue).speakers LIKE ? OR \(table.rawValue).realNames LIKE ?)")
                arguments.append(contentsOf: [likePattern.databaseValue, likePattern.databaseValue])
            case .transcriptChunks:
                conditions.append("\(table.rawValue).speakers LIKE ?")
                arguments.append(likePattern.databaseValue)
            default:
                break
            }
        }

        if let sentByMe, table == .emailChunks {
            conditions.append("\(table.rawValue).isSentByMe = ?")
            arguments.append(sentByMe.databaseValue)
        }

        if let hasAttachments, table == .emailChunks {
            conditions.append("\(table.rawValue).hasAttachments = ?")
            arguments.append(hasAttachments.databaseValue)
        }

        if let isInternal, table == .transcriptChunks {
            conditions.append("""
                \(table.rawValue).meetingId IN (
                    SELECT meetingId FROM meetings WHERE isInternal = ?
                )
            """)
            arguments.append(isInternal.databaseValue)
        }

        let whereClause = conditions.isEmpty
            ? ""
            : "AND " + conditions.joined(separator: " AND ")

        let sql = """
            SELECT \(table.rawValue).rowid AS id,
                   bm25(\(table.ftsTableName), \(table.bm25Weights)) AS rank,
                   snippet(\(table.ftsTableName), -1, '<b>', '</b>', '...', 64) AS snippet
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
                return cleaned.isEmpty ? nil : "\(cleaned)*"
            }
            .compactMap { $0 }
        guard !tokens.isEmpty else { return "" }
        return tokens.joined(separator: " OR ")
    }
}

extension FTSIndex.FTSTable: CaseIterable {}
