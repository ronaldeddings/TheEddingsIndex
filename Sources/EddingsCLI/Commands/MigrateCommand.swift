import ArgumentParser
import EddingsKit
import Foundation

struct MigrateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate",
        abstract: "Import data from PostgreSQL"
    )

    @Flag(name: .long, help: "Import from PostgreSQL at localhost:4432")
    var fromPostgres = false

    @Option(name: .long, help: "Database path")
    var dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: "Library/Application Support/com.hackervalley.eddingsindex/eddings.sqlite").path()
    }()

    func run() throws {
        guard fromPostgres else {
            print("Specify --from-postgres to import from PostgreSQL.")
            return
        }

        let dir = URL(filePath: dbPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbManager = try DatabaseManager(path: dbPath)
        let migrator = PostgresMigrator(dbManager: dbManager)

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
        print("")
        print("FTS5 indexes rebuilt. PostgreSQL was NOT modified.")
    }
}
