import Foundation
import GRDB
import os

public struct SlackClient: Sendable {
    private let dbPool: DatabasePool
    private let basePath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "slack")

    public init(dbPool: DatabasePool, basePath: String = "/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack") {
        self.dbPool = dbPool
        self.basePath = basePath
    }

    public func sync() throws -> Int {
        guard FileManager.default.fileExists(atPath: basePath) else {
            logger.warning("Slack export path not found: \(basePath)")
            return 0
        }

        logger.info("Scanning Slack exports at \(basePath)")
        var count = 0

        let fm = FileManager.default
        guard let channels = try? fm.contentsOfDirectory(atPath: basePath) else { return 0 }

        for channel in channels {
            let channelPath = "\(basePath)/\(channel)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: channelPath, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(atPath: channelPath)
                .filter({ $0.hasSuffix(".json") })
                .sorted() else { continue }

            for file in files {
                let filePath = "\(channelPath)/\(file)"
                let dateStr = file.replacingOccurrences(of: ".json", with: "")

                guard let data = fm.contents(atPath: filePath),
                      let messages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }

                let chunkText = messages.compactMap { msg -> String? in
                    guard let text = msg["text"] as? String, !text.isEmpty else { return nil }
                    let user = msg["user"] as? String ?? "unknown"
                    return "[\(user)] \(text)"
                }.joined(separator: "\n")

                guard !chunkText.isEmpty else { continue }

                let calendar = Calendar.current
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                let date = dateFormatter.date(from: dateStr)
                let components = date.map { calendar.dateComponents([.year, .month], from: $0) }

                try dbPool.write { db in
                    let existing = try SlackChunk
                        .filter(Column("channel") == channel && Column("messageDate") == date)
                        .fetchOne(db)
                    guard existing == nil else { return }

                    var chunk = SlackChunk(
                        channel: channel,
                        channelType: "channel",
                        speakers: messages.compactMap { $0["user"] as? String }
                            .reduce(into: Set<String>()) { $0.insert($1) }
                            .joined(separator: ","),
                        chunkText: chunkText,
                        messageDate: date,
                        year: components?.year,
                        month: components?.month,
                        hasFiles: messages.contains { ($0["files"] as? [Any])?.isEmpty == false },
                        hasReactions: messages.contains { ($0["reactions"] as? [Any])?.isEmpty == false }
                    )
                    try chunk.insert(db)
                    count += 1
                }
            }
        }

        logger.info("Slack sync: \(count) new chunks indexed")

        try linkSpeakersToContacts()

        return count
    }

    private func linkSpeakersToContacts() throws {
        let allSpeakers = try dbPool.read { db -> Set<String> in
            let rows = try Row.fetchAll(db, sql: "SELECT DISTINCT speakers FROM slackChunks WHERE speakers IS NOT NULL")
            var names = Set<String>()
            for row in rows {
                let csv: String = row["speakers"]
                for name in csv.split(separator: ",") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { names.insert(trimmed) }
                }
            }
            return names
        }

        guard !allSpeakers.isEmpty else { return }

        try dbPool.write { db in
            for speaker in allSpeakers {
                let contact = try Contact
                    .filter(Column("name") == speaker || Column("slackUserId") == speaker)
                    .fetchOne(db)
                guard let contact, let contactId = contact.id else { continue }

                let chunkCount = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM slackChunks WHERE speakers LIKE ?",
                    arguments: ["%\(speaker)%"]
                ) ?? 0

                if chunkCount > contact.slackCount {
                    try db.execute(
                        sql: "UPDATE contacts SET slackCount = ?, lastSeenAt = ? WHERE id = ?",
                        arguments: [chunkCount, Date(), contactId]
                    )
                }
            }
        }

        logger.info("Linked Slack speakers to contacts")
    }
}
