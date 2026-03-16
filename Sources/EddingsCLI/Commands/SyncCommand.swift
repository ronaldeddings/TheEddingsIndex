import ArgumentParser
import EddingsKit
import Foundation

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Pull data from all sources"
    )

    @Flag(name: .long, help: "Sync all data sources")
    var all = false

    @Flag(name: .long, help: "SimpleFin + QBO only")
    var finance = false

    @Flag(name: .long, help: "VRAM filesystem only")
    var files = false

    @Flag(name: .long, help: "Slack exports only")
    var slack = false

    @Flag(name: .long, help: "Meeting transcripts only")
    var meetings = false

    @Option(name: .long, help: "Database path")
    var dbPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.hackervalley.eddingsindex/eddings.sqlite").path
    }()

    func run() async throws {
        let dir = URL(filePath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbManager = try DatabaseManager(path: dbPath)
        let stateDir = dir.appending(path: "state")
        let stateManager = StateManager(directory: stateDir)
        let merchantMap = MerchantMap()

        if !finance && !all && !files && !slack && !meetings {
            print("Specify a sync target:")
            print("  --finance    SimpleFin + QBO only")
            print("  --files      VRAM filesystem")
            print("  --slack      Slack exports")
            print("  --meetings   Meeting transcripts")
            print("  --all        All data sources")
            return
        }

        var errors: [(String, Error)] = []

        if finance || all {
            print("Syncing financial data...")
            do {
                let pipeline = FinanceSyncPipeline(
                    dbManager: dbManager,
                    stateManager: stateManager,
                    merchantMap: merchantMap
                )
                let result = try await pipeline.run()
                print("  Finance: \(result.newTransactions) new transactions, Freedom Velocity \(String(format: "%.0f", result.freedomVelocityPercent))%")
            } catch {
                print("  Finance: FAILED — \(error)")
                errors.append(("finance", error))
            }
        }

        if files || all {
            print("Scanning VRAM filesystem...")
            do {
                let scanner = FileScanner(dbPool: dbManager.dbPool)
                let count = try scanner.scan()
                print("  Files: \(count) new files indexed")
            } catch {
                print("  Files: FAILED — \(error)")
                errors.append(("files", error))
            }
        }

        if slack || all {
            print("Syncing Slack exports...")
            do {
                let client = SlackClient(dbPool: dbManager.dbPool)
                let count = try client.sync()
                print("  Slack: \(count) new chunks indexed")
            } catch {
                print("  Slack: FAILED — \(error)")
                errors.append(("slack", error))
            }
        }

        if meetings || all {
            print("Syncing meeting transcripts...")
            do {
                let client = FathomClient(dbPool: dbManager.dbPool)
                let count = try client.sync()
                print("  Meetings: \(count) new transcript chunks")
            } catch {
                print("  Meetings: FAILED — \(error)")
                errors.append(("meetings", error))
            }
        }

        if errors.isEmpty {
            print("\nSync complete.")
        } else {
            print("\nSync completed with \(errors.count) error(s):")
            for (source, error) in errors {
                print("  \(source): \(error)")
            }
            throw ExitCode(1)
        }
    }
}
