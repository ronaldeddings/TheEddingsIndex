import Foundation
import GRDB
import os

public struct SlackClient: Sendable {
    private let dbPool: DatabasePool
    private let basePath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "slack")

    nonisolated(unsafe) private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public init(dbPool: DatabasePool, basePath: String = "/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack") {
        self.dbPool = dbPool
        self.basePath = basePath
    }

    public func sync() throws -> Int {
        let jsonPath = "\(basePath)/json"
        let searchPath = FileManager.default.fileExists(atPath: jsonPath) ? jsonPath : basePath

        guard FileManager.default.fileExists(atPath: searchPath) else {
            logger.warning("Slack export path not found: \(searchPath)")
            return 0
        }

        logger.info("Scanning Slack exports at \(searchPath)")
        var count = 0

        let fm = FileManager.default
        guard let channels = try? fm.contentsOfDirectory(atPath: searchPath) else { return 0 }

        let existingKeys = try getExistingKeys()

        for channel in channels.sorted() {
            let channelPath = "\(searchPath)/\(channel)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: channelPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let channelType = detectChannelType(channel)

            guard let files = try? fm.contentsOfDirectory(atPath: channelPath)
                .filter({ $0.hasSuffix(".json") })
                .sorted() else { continue }

            for file in files {
                let filePath = "\(channelPath)/\(file)"
                let dateStr = file.replacingOccurrences(of: ".json", with: "")

                guard let data = fm.contents(atPath: filePath) else { continue }

                let messages: [SlackMessage]
                do {
                    messages = try SlackParser.parseMessages(data: data)
                } catch {
                    logger.debug("Failed to parse \(file): \(error.localizedDescription)")
                    continue
                }

                guard !messages.isEmpty else { continue }

                let date = Self.dateFormatter.date(from: dateStr)
                if let date, date < DataPolicy.cutoffDate { continue }
                let components = date.map { Calendar.current.dateComponents([.year, .month], from: $0) }
                let year = components?.year ?? 0
                let month = components?.month ?? 0
                let quarter = ((month - 1) / 3) + 1

                let chunks = SlackParser.toSlackChunks(
                    messages: messages,
                    channel: channel,
                    channelType: channelType,
                    messageDate: date ?? Date(),
                    year: year,
                    month: month,
                    quarter: quarter
                )

                try dbPool.write { db in
                    for var chunk in chunks {
                        let key = "\(channel)|\(dateStr)|\(chunk.chunkIndex ?? 0)"
                        if existingKeys.contains(key) { continue }
                        try chunk.insert(db)
                        count += 1
                    }
                }
            }
        }

        logger.info("Slack sync: \(count) new chunks indexed")
        return count
    }

    private func getExistingKeys() throws -> Set<String> {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT channel, messageDate, chunkIndex FROM slackChunks
            """)
            var keys = Set<String>()
            for row in rows {
                let channel: String = row["channel"] ?? ""
                let date: Date? = row["messageDate"]
                let idx: Int = row["chunkIndex"] ?? 0
                if let date {
                    let dateStr = Self.dateFormatter.string(from: date)
                    keys.insert("\(channel)|\(dateStr)|\(idx)")
                }
            }
            return keys
        }
    }

    private func detectChannelType(_ channelName: String) -> String {
        if channelName.hasPrefix("dm-") || channelName.hasPrefix("direct-") {
            return "dm"
        }
        if channelName.hasPrefix("group-") || channelName.hasPrefix("mpdm-") {
            return "group_dm"
        }
        if channelName.hasPrefix("private-") {
            return "private"
        }
        return "public"
    }
}
