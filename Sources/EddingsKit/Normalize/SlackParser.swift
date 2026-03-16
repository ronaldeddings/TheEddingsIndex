import Foundation

public struct SlackMessage: Codable, Sendable {
    public let user: String?
    public let text: String?
    public let ts: String?
    public let type: String?
    public let thread_ts: String?
    public let reply_count: Int?
    public let user_profile: SlackUserProfile?
    public let reactions: [SlackReaction]?
    public let files: [SlackFile]?
    public let edited: SlackEdited?

    public struct SlackUserProfile: Codable, Sendable {
        public let real_name: String?
        public let display_name: String?
        public let name: String?
        public let first_name: String?
    }

    public struct SlackReaction: Codable, Sendable {
        public let name: String?
        public let count: Int?
        public let users: [String]?
    }

    public struct SlackFile: Codable, Sendable {
        public let name: String?
        public let size: Int?
        public let filetype: String?
    }

    public struct SlackEdited: Codable, Sendable {
        public let user: String?
        public let ts: String?
    }
}

public struct SlackParser: Sendable {

    public static func parseMessages(data: Data) throws -> [SlackMessage] {
        let decoder = JSONDecoder()
        return try decoder.decode([SlackMessage].self, from: data)
    }

    public static func displayName(for message: SlackMessage) -> String {
        let profile = message.user_profile
        if let dn = profile?.display_name, !dn.isEmpty { return dn }
        if let rn = profile?.real_name, !rn.isEmpty { return rn }
        if let n = profile?.name, !n.isEmpty { return n }
        return message.user ?? "Unknown"
    }

    public static func timestamp(from ts: String?) -> Date? {
        guard let ts, let seconds = Double(ts.split(separator: ".").first ?? "") else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func formatTime(from ts: String?) -> String {
        guard let date = timestamp(from: ts) else { return "??:??" }
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }

    public static func groupByTimeWindow(
        _ messages: [SlackMessage],
        windowMinutes: Int = 15
    ) -> [[SlackMessage]] {
        guard !messages.isEmpty else { return [] }

        let sorted = messages.sorted { ($0.ts ?? "") < ($1.ts ?? "") }
        var groups: [[SlackMessage]] = []
        var currentGroup: [SlackMessage] = []
        var windowStart: Double?

        for msg in sorted {
            guard let ts = msg.ts, let seconds = Double(ts.split(separator: ".").first ?? "") else {
                if !currentGroup.isEmpty {
                    currentGroup.append(msg)
                }
                continue
            }

            if let start = windowStart {
                if (seconds - start) > Double(windowMinutes * 60) {
                    if !currentGroup.isEmpty {
                        groups.append(currentGroup)
                    }
                    currentGroup = [msg]
                    windowStart = seconds
                } else {
                    currentGroup.append(msg)
                }
            } else {
                currentGroup = [msg]
                windowStart = seconds
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    public static func formatGroup(_ messages: [SlackMessage]) -> String {
        var lines: [String] = []
        for msg in messages {
            let time = formatTime(from: msg.ts)
            let name = displayName(for: msg)
            let text = msg.text ?? ""
            lines.append("[\(time)] \(name): \(text)")

            if let files = msg.files, !files.isEmpty {
                let names = files.compactMap(\.name).joined(separator: ", ")
                if !names.isEmpty {
                    lines.append("  [files: \(names)]")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func chunkFormattedText(
        _ text: String,
        messages: [SlackMessage],
        targetSize: Int = 1800,
        overlap: Int = 300
    ) -> [(text: String, index: Int)] {
        if text.count <= targetSize {
            return [(text, 0)]
        }

        let lines = text.components(separatedBy: "\n")
        var chunks: [(String, Int)] = []
        var currentLines: [String] = []
        var currentSize = 0
        var chunkIndex = 0

        for line in lines {
            if currentSize + line.count > targetSize && !currentLines.isEmpty {
                chunks.append((currentLines.joined(separator: "\n"), chunkIndex))
                chunkIndex += 1

                var overlapLines: [String] = []
                var overlapSize = 0
                for l in currentLines.reversed() {
                    if overlapSize + l.count > overlap { break }
                    overlapLines.insert(l, at: 0)
                    overlapSize += l.count
                }
                currentLines = overlapLines
                currentSize = overlapSize
            }

            currentLines.append(line)
            currentSize += line.count
        }

        if !currentLines.isEmpty {
            chunks.append((currentLines.joined(separator: "\n"), chunkIndex))
        }

        return chunks
    }

    public static func extractMetadata(from messages: [SlackMessage]) -> (
        userIds: [String],
        realNames: [String],
        speakers: String,
        messageCount: Int,
        hasFiles: Bool,
        hasReactions: Bool,
        isEdited: Bool,
        replyCount: Int,
        emojiReactions: String?,
        threadTs: String?,
        isThreadReply: Bool
    ) {
        var userIdSet: [String: Bool] = [:]
        var nameSet: [String: Bool] = [:]
        var hasFiles = false
        var hasReactions = false
        var isEdited = false
        var totalReplyCount = 0
        var allReactions: [String] = []
        var threadTs: String?
        var isThreadReply = false

        for msg in messages {
            if let uid = msg.user {
                userIdSet[uid] = true
            }
            let name = displayName(for: msg)
            nameSet[name] = true

            if let files = msg.files, !files.isEmpty { hasFiles = true }
            if let reactions = msg.reactions, !reactions.isEmpty {
                hasReactions = true
                for r in reactions {
                    if let name = r.name {
                        allReactions.append(name)
                    }
                }
            }
            if msg.edited != nil { isEdited = true }
            if let rc = msg.reply_count { totalReplyCount += rc }
            if let tts = msg.thread_ts {
                if tts != msg.ts {
                    isThreadReply = true
                }
                threadTs = tts
            }
        }

        let userIds = Array(userIdSet.keys).sorted()
        let realNames = Array(nameSet.keys).sorted()
        let speakers = realNames.joined(separator: ", ")

        let reactionsJSON: String?
        if allReactions.isEmpty {
            reactionsJSON = nil
        } else {
            let data = try? JSONEncoder().encode(allReactions)
            reactionsJSON = data.flatMap { String(data: $0, encoding: .utf8) }
        }

        return (
            userIds: userIds,
            realNames: realNames,
            speakers: speakers,
            messageCount: messages.count,
            hasFiles: hasFiles,
            hasReactions: hasReactions,
            isEdited: isEdited,
            replyCount: totalReplyCount,
            emojiReactions: reactionsJSON,
            threadTs: threadTs,
            isThreadReply: isThreadReply
        )
    }

    public static func toSlackChunks(
        messages: [SlackMessage],
        channel: String,
        channelType: String?,
        messageDate: Date,
        year: Int,
        month: Int,
        quarter: Int
    ) -> [SlackChunk] {
        let groups = groupByTimeWindow(messages)
        var allChunks: [SlackChunk] = []

        for group in groups {
            let formatted = formatGroup(group)
            let meta = extractMetadata(from: group)
            let textChunks = chunkFormattedText(formatted, messages: group)

            let userIdsJSON = (try? JSONEncoder().encode(meta.userIds))
                .flatMap { String(data: $0, encoding: .utf8) }
            let realNamesJSON = (try? JSONEncoder().encode(meta.realNames))
                .flatMap { String(data: $0, encoding: .utf8) }

            for (text, idx) in textChunks {
                allChunks.append(SlackChunk(
                    channel: channel,
                    channelType: channelType,
                    speakers: meta.speakers,
                    chunkText: text,
                    messageDate: messageDate,
                    year: year,
                    month: month,
                    hasFiles: meta.hasFiles,
                    hasReactions: meta.hasReactions,
                    threadTs: meta.threadTs,
                    isThreadReply: meta.isThreadReply,
                    userIds: userIdsJSON,
                    realNames: realNamesJSON,
                    quarter: quarter,
                    messageCount: meta.messageCount,
                    isEdited: meta.isEdited,
                    replyCount: meta.replyCount,
                    emojiReactions: meta.emojiReactions,
                    chunkIndex: idx
                ))
            }
        }

        return allChunks
    }
}
