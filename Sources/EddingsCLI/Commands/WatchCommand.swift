import ArgumentParser
import EddingsKit
import Foundation

struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch VRAM for changes and index in real-time"
    )

    @Option(name: .long, help: "Database path")
    var dbPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.hackervalley.eddingsindex/eddings.sqlite").path
    }()

    func run() async throws {
        let dir = URL(filePath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbManager = try DatabaseManager(path: dbPath)

        let vectorDir = dir.appending(path: "vectors")
        try FileManager.default.createDirectory(at: vectorDir, withIntermediateDirectories: true)
        let vectorIndex = try VectorIndex(directory: vectorDir)
        let pipeline = EmbeddingPipeline(dbPool: dbManager.dbPool, vectorIndex: vectorIndex)

        print("Running catchup sync...")
        let stateDir = dir.appending(path: "state")
        let stateManager = StateManager(directory: stateDir)
        let merchantMap = MerchantMap()

        var errors: [(String, Error)] = []

        do {
            let financePipeline = FinanceSyncPipeline(
                dbManager: dbManager,
                stateManager: stateManager,
                merchantMap: merchantMap
            )
            let result = try await financePipeline.run()
            print("  Finance: \(result.newTransactions) new transactions")
        } catch {
            print("  Finance: FAILED — \(error)")
            errors.append(("finance", error))
        }

        do {
            let scanner = FileScanner(dbPool: dbManager.dbPool)
            let count = try scanner.scan()
            print("  Files: \(count) new files indexed")
        } catch {
            print("  Files: FAILED — \(error)")
            errors.append(("files", error))
        }

        do {
            let client = SlackClient(dbPool: dbManager.dbPool)
            let count = try client.sync()
            print("  Slack: \(count) new chunks indexed")
        } catch {
            print("  Slack: FAILED — \(error)")
            errors.append(("slack", error))
        }

        do {
            let client = IMAPClient(dbPool: dbManager.dbPool)
            let count = try client.sync()
            print("  Emails: \(count) new email chunks")
        } catch {
            print("  Emails: FAILED — \(error)")
            errors.append(("emails", error))
        }

        do {
            let client = FathomClient(dbPool: dbManager.dbPool)
            let count = try client.sync()
            print("  Meetings: \(count) new transcript chunks")
        } catch {
            print("  Meetings: FAILED — \(error)")
            errors.append(("meetings", error))
        }

        do {
            let stats = try await pipeline.run()
            if stats.totalEmbedded > 0 || stats.retriedPending > 0 {
                print("  Embeddings: \(stats.totalEmbedded) new, \(stats.retriedPending) retried")
            } else {
                print("  Embeddings: all records already embedded")
            }
        } catch {
            print("  Embeddings: FAILED — \(error)")
            errors.append(("embeddings", error))
        }

        if !errors.isEmpty {
            print("Catchup completed with \(errors.count) error(s)")
        } else {
            print("Catchup sync complete.")
        }

        print("Starting file watcher...")
        let watcher = FileWatcher(dbPool: dbManager.dbPool, embeddingPipeline: pipeline)
        await watcher.start()

        print("Watching VRAM for changes. Press Ctrl+C to stop.")
        dispatchMain()
    }
}
