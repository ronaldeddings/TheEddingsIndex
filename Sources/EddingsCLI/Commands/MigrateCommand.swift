import ArgumentParser
import EddingsKit
import Foundation

struct MigrateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Import data from PostgreSQL"
    )

    @Flag(name: .long, help: "Import from PostgreSQL at localhost:4432")
    var fromPostgres = false

    @Flag(name: .long, help: "Also migrate 4096-dim Qwen embeddings into USearch")
    var withVectors = false

    @Flag(name: .long, help: "Only migrate vectors (skip text data)")
    var vectorsOnly = false

    @Option(name: .long, help: "Database path")
    var dbPath: String = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("com.hackervalley.eddingsindex/eddings.sqlite").path
    }()

    func run() async throws {
        guard fromPostgres else {
            print("Specify --from-postgres to import from PostgreSQL.")
            return
        }

        let dir = URL(filePath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbManager = try DatabaseManager(path: dbPath, foreignKeysEnabled: false)
        let migrator = PostgresMigrator(dbManager: dbManager)

        if !vectorsOnly {
            print("Starting PostgreSQL → SQLite migration...")
            print("This may take several minutes for 1.3M+ records.")
            print("")

            let result = try migrator.migrate()

            print("")
            print("Migration complete:")
            print("  Documents:         \(result.documents)")
            print("  Email chunks:      \(result.emailChunks)")
            print("  Slack chunks:      \(result.slackChunks)")
            print("  Transcript chunks: \(result.transcriptChunks)")
            print("  Contacts:          \(result.contacts)")
            print("  Companies:         \(result.companies)")
            print("  Meetings:          \(result.meetings)")
        }

        if withVectors || vectorsOnly {
            print("")
            print("Migrating 4096-dim Qwen embeddings into USearch...")
            let vectorDir = dir.appending(path: "vectors")
            try FileManager.default.createDirectory(at: vectorDir, withIntermediateDirectories: true)
            let vectorIndex = try VectorIndex(directory: vectorDir)
            let vectorCount = try await migrator.migrateVectors(vectorIndex: vectorIndex)
            print("  Vectors (4096d):   \(vectorCount)")
        }

        print("")
        print("FTS5 indexes rebuilt. PostgreSQL was NOT modified.")
    }
}
