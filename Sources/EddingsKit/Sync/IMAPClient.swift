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
        let indexedPaths = try getIndexedPaths()
        var newCount = 0
        let fm = FileManager.default

        let cutoffYear = Calendar.current.component(.year, from: DataPolicy.cutoffDate)
        let yearDirs = try fm.contentsOfDirectory(atPath: emailPath)
            .filter { $0.first?.isNumber == true }
            .filter { Int($0) ?? 0 >= cutoffYear }
            .sorted()

        for yearDir in yearDirs {
            let yearPath = "\(emailPath)/\(yearDir)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: yearPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let files = try fm.contentsOfDirectory(atPath: yearPath)
                .filter { $0.hasSuffix(".json") }
                .sorted()

            logger.info("Processing \(files.count) emails in \(yearDir)")

            let cutoffPrefix = {
                let cal = Calendar.current
                let y = cal.component(.year, from: DataPolicy.cutoffDate)
                let m = cal.component(.month, from: DataPolicy.cutoffDate)
                return String(format: "%04d-%02d", y, m)
            }()

            for file in files {
                if file.count >= 7 {
                    let prefix = String(file.prefix(7))
                    if prefix < cutoffPrefix { continue }
                }

                let filePath = "\(yearPath)/\(file)"
                if indexedPaths.contains(filePath) { continue }

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
                    .filter { ($0.emailDate ?? .distantPast) >= DataPolicy.cutoffDate }
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

    public func indexSingleFile(path: String) throws -> [Int64] {
        guard path.hasSuffix(".json") else { return [] }
        let fm = FileManager.default
        guard let data = fm.contents(atPath: path) else { return [] }

        let cutoffPrefix: String = {
            let cal = Calendar.current
            let y = cal.component(.year, from: DataPolicy.cutoffDate)
            let m = cal.component(.month, from: DataPolicy.cutoffDate)
            return String(format: "%04d-%02d", y, m)
        }()

        let filename = URL(filePath: path).lastPathComponent
        if filename.count >= 7 {
            let prefix = String(filename.prefix(7))
            if prefix < cutoffPrefix { return [] }
        }

        let email: EmailJSON
        do {
            email = try EmailParser.parse(data: data)
        } catch {
            logger.debug("Failed to parse \(filename): \(error.localizedDescription)")
            return []
        }

        if EmailParser.isSpam(email) { return [] }

        let chunks = EmailParser.toEmailChunks(email: email, filePath: path)
            .filter { ($0.emailDate ?? .distantPast) >= DataPolicy.cutoffDate }
        guard !chunks.isEmpty else { return [] }

        let existingIds = try getExistingEmailIds()
        let allExist = chunks.allSatisfy { existingIds.contains($0.emailId) }
        if allExist { return [] }

        var insertedIds: [Int64] = []
        try dbPool.write { db in
            for var chunk in chunks {
                if existingIds.contains(chunk.emailId) { continue }
                try chunk.insert(db, onConflict: .ignore)
                if let id = chunk.id {
                    insertedIds.append(id)
                }
            }
        }

        logger.info("IMAPClient indexed \(insertedIds.count) chunks from \(filename)")
        return insertedIds
    }

    private func getExistingEmailIds() throws -> Set<String> {
        try dbPool.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT emailId FROM emailChunks")
            return Set(ids)
        }
    }

    private func getIndexedPaths() throws -> Set<String> {
        try dbPool.read { db in
            let paths = try String.fetchAll(db, sql: "SELECT DISTINCT emailPath FROM emailChunks WHERE emailPath IS NOT NULL")
            return Set(paths)
        }
    }
}
