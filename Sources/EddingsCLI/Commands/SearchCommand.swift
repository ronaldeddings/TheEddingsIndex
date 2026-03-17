import ArgumentParser
import EddingsKit
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search across all indexed sources (FTS + semantic)"
    )

    @Argument(help: "Search query")
    var query: String

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Flag(name: .long, help: "FTS only — skip semantic search")
    var ftsOnly = false

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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.hackervalley.eddingsindex/eddings.sqlite").path
    }()

    func run() async throws {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            print("Database not found at \(dbPath). Run 'ei-cli sync --all' or 'ei-cli migrate --from-postgres' first.")
            throw ExitCode(1)
        }

        let dbManager = try DatabaseManager(path: dbPath)
        let dbDir = URL(filePath: dbPath).deletingLastPathComponent()
        let vectorDir = dbDir.appending(path: "vectors")
        let vectorIndex = try VectorIndex(directory: vectorDir)
        let queryEngine = QueryEngine(dbPool: dbManager.dbPool, vectorIndex: vectorIndex)

        var tables: [FTSIndex.FTSTable]?
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

        var embedding: [Float]?
        if !ftsOnly {
            do {
                let nl = NLEmbedder()
                embedding = try await nl.embed(query)
            } catch {
                // NLEmbedder failed — FTS only
            }
        }

        let results = try await queryEngine.search(
            query: query,
            embedding: embedding,
            sources: tables,
            year: year,
            month: month,
            limit: limit
        )

        let mode = embedding != nil ? "hybrid" : "fts"

        if json {
            let output = results.map { result in
                var entry: [String: String] = [
                    "id": "\(result.id)",
                    "source": result.sourceTable.rawValue,
                    "title": result.title,
                    "score": String(format: "%.4f", result.score),
                ]
                if let snippet = result.snippet {
                    entry["snippet"] = String(snippet.prefix(200))
                }
                if let fullContent = result.fullContent {
                    entry["fullContent"] = fullContent
                }
                if let date = result.date {
                    let f = ISO8601DateFormatter()
                    entry["date"] = f.string(from: date)
                }
                if let sourceLocator = result.sourceLocator {
                    entry["sourceLocator"] = sourceLocator
                }
                if let speakers = result.speakers, !speakers.isEmpty {
                    entry["speakers"] = speakers.joined(separator: ", ")
                }
                if let meta = result.metadata {
                    for (k, v) in meta where !v.isEmpty {
                        entry[k] = v
                    }
                }
                return entry
            }
            let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            if results.isEmpty {
                print("No results for \"\(query)\" (\(mode))")
                return
            }
            print("\(results.count) results for \"\(query)\" (\(mode))")
            print("")
            for (i, result) in results.enumerated() {
                let dateStr: String
                if let date = result.date {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    dateStr = " \(f.string(from: date))"
                } else {
                    dateStr = ""
                }
                print("  \(i + 1). [\(result.sourceTable.rawValue)]\(dateStr) \(result.title)")
                if let snippet = result.snippet {
                    let clean = snippet
                        .replacingOccurrences(of: "<b>", with: "\u{1b}[1m")
                        .replacingOccurrences(of: "</b>", with: "\u{1b}[0m")
                    print("     \(String(clean.prefix(120)))")
                }
                print("     score=\(String(format: "%.4f", result.score))")
                print("")
            }
        }
    }
}
