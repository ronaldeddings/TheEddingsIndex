import ArgumentParser
import EddingsKit
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search across all indexed sources"
    )

    @Argument(help: "Search query")
    var query: String

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Option(name: .long, help: "Maximum results")
    var limit: Int = 20

    @Option(name: .long, help: "Filter by source (email, slack, meeting, file, finance)")
    var sources: String?

    @Option(name: .long, help: "Filter by year")
    var year: Int?

    @Option(name: .long, help: "Filter by month")
    var month: Int?

    @Option(name: .long, help: "Database path")
    var dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: "Library/Application Support/com.hackervalley.eddingsindex/eddings.sqlite").path()
    }()

    func run() async throws {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Database not found at \(dbPath). Run 'ei-cli sync --all' or 'ei-cli migrate --from-postgres' first.")
            throw ExitCode(1)
        }

        let dbManager = try DatabaseManager(path: dbPath)
        let fts = FTSIndex(dbPool: dbManager.dbPool)

        var tables = FTSIndex.FTSTable.allCases
        if let sourceFilter = sources {
            tables = sourceFilter.split(separator: ",").compactMap { src in
                switch String(src).trimmingCharacters(in: .whitespaces) {
                case "email": return .emailChunks
                case "slack": return .slackChunks
                case "meeting", "transcript": return .transcriptChunks
                case "file": return .documents
                case "finance": return .financialTransactions
                default: return nil
                }
            }
        }

        let results = try fts.search(query: query, tables: tables, limit: limit, year: year, month: month)

        if json {
            let output = results.map { result in
                [
                    "id": "\(result.id)",
                    "source": result.sourceTable.rawValue,
                    "score": String(format: "%.4f", result.score),
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            if results.isEmpty {
                print("No results for \"\(query)\"")
                return
            }
            print("\(results.count) results for \"\(query)\"")
            print("")
            for (i, result) in results.enumerated() {
                print("  \(i + 1). [\(result.sourceTable.rawValue)] id=\(result.id) score=\(String(format: "%.4f", result.score))")
            }
        }
    }
}
