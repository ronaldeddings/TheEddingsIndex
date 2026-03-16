import Foundation
import GRDB
import os

public struct IMAPClient: Sendable {
    private let dbPool: DatabasePool
    private let emailPath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "imap")

    public init(
        dbPool: DatabasePool,
        emailPath: String = "/Volumes/VRAM/10-19_Work/14_Communications/14.01b_emails_json"
    ) {
        self.dbPool = dbPool
        self.emailPath = emailPath
    }

    public func sync() throws -> Int {
        guard FileManager.default.fileExists(atPath: emailPath) else {
            logger.warning("Email JSON path not found: \(emailPath)")
            return 0
        }

        let existingIds = try getExistingEmailIds()
        var newCount = 0
        let fm = FileManager.default

        let yearDirs = try fm.contentsOfDirectory(atPath: emailPath)
            .filter { $0.first?.isNumber == true }
            .sorted()

        for yearDir in yearDirs {
            let yearPath = "\(emailPath)/\(yearDir)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: yearPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let files = try fm.contentsOfDirectory(atPath: yearPath)
                .filter { $0.hasSuffix(".json") }
                .sorted()

            logger.info("Processing \(files.count) emails in \(yearDir)")

            for file in files {
                let filePath = "\(yearPath)/\(file)"

                guard let data = fm.contents(atPath: filePath) else { continue }

                let email: EmailJSON
                do {
                    email = try EmailParser.parse(data: data)
                } catch {
                    logger.debug("Failed to parse \(file): \(error.localizedDescription)")
                    continue
                }

                if EmailParser.isSpam(email) { continue }

                let chunks = EmailParser.toEmailChunks(email: email, filePath: filePath)
                guard !chunks.isEmpty else { continue }

                let allExist = chunks.allSatisfy { existingIds.contains($0.emailId) }
                if allExist { continue }

                try dbPool.write { db in
                    for var chunk in chunks {
                        if existingIds.contains(chunk.emailId) { continue }
                        try chunk.insert(db, onConflict: .ignore)
                    }
                }
                newCount += chunks.count
            }
        }

        logger.info("IMAPClient indexed \(newCount) new email chunks")
        return newCount
    }

    private func getExistingEmailIds() throws -> Set<String> {
        try dbPool.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT emailId FROM emailChunks")
            return Set(ids)
        }
    }
}
