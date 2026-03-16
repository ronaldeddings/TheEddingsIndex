import Foundation

public struct EmailJSON: Codable, Sendable {
    public let id: EmailId
    public let headers: EmailHeaders
    public let content: EmailContent
    public let attachments: EmailAttachments
    public let metadata: EmailMetadata
    public let threading: EmailThreading

    public struct EmailId: Codable, Sendable {
        public let message_id: String?
        public let index: Int?
        public let hash: String
    }

    public struct EmailHeaders: Codable, Sendable {
        public let subject: String?
        public let date: EmailDate
        public let from: EmailAddress
        public let to: [EmailAddress]?
        public let cc: [EmailAddress]?
        public let bcc: [EmailAddress]?
        public let reply_to: EmailAddress?
        public let in_reply_to: String?
        public let references: [String]?
    }

    public struct EmailDate: Codable, Sendable {
        public let raw: String?
        public let iso: String?
        public let timestamp: Int?
    }

    public struct EmailAddress: Codable, Sendable {
        public let raw: String?
        public let name: String?
        public let email: String?
    }

    public struct EmailContent: Codable, Sendable {
        public let body: String?
        public let body_html: String?
        public let has_html_version: Bool?
        public let has_plain_version: Bool?
    }

    public struct EmailAttachments: Codable, Sendable {
        public let count: Int?
        public let files: [AttachmentFile]?
    }

    public struct AttachmentFile: Codable, Sendable {
        public let filename: String?
        public let size: Int?
        public let content_type: String?
    }

    public struct EmailMetadata: Codable, Sendable {
        public let labels: [String]?
        public let content_type: String?
        public let is_multipart: Bool?
        public let spam_score: String?
        public let importance: String?
        public let user_agent: String?
    }

    public struct EmailThreading: Codable, Sendable {
        public let thread_topic: String?
        public let thread_index: String?
        public let in_reply_to: String?
        public let references_count: Int?
    }
}

public struct EmailParser: Sendable {

    private static let spamPattern = try! NSRegularExpression(
        pattern: #"(^|[^a-z])(spam|junk|trash)([^a-z]|$)"#,
        options: .caseInsensitive
    )

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoFormatterBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(data: Data) throws -> EmailJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(EmailJSON.self, from: data)
    }

    public static func isSpam(_ email: EmailJSON) -> Bool {
        guard let labels = email.metadata.labels else { return false }
        for label in labels {
            let range = NSRange(label.startIndex..., in: label)
            if spamPattern.firstMatch(in: label, range: range) != nil {
                return true
            }
        }
        return false
    }

    public static func parseDate(_ emailDate: EmailJSON.EmailDate) -> Date? {
        if let iso = emailDate.iso, !iso.isEmpty {
            if let d = isoFormatter.date(from: iso) { return d }
            if let d = isoFormatterBasic.date(from: iso) { return d }
        }
        if let ts = emailDate.timestamp, ts > 0 {
            return Date(timeIntervalSince1970: Double(ts))
        }
        return nil
    }

    public static func isSentByMe(_ email: EmailJSON) -> Bool {
        guard let addr = email.headers.from.email?.lowercased() else { return false }
        return addr.hasPrefix("ron") && addr.contains("@hackervalley.com")
    }

    public static func stripHTML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        let lines = result.components(separatedBy: "\n")
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        result = trimmed.joined(separator: "\n")
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func chunkEmail(_ body: String, targetSize: Int = 2000, overlap: Int = 300) -> [(text: String, index: Int)] {
        let cleanBody = stripHTML(body)
        if cleanBody.count <= targetSize {
            return [(cleanBody, 0)]
        }

        var chunks: [(String, Int)] = []
        let paragraphs = cleanBody.components(separatedBy: "\n\n")
        var current = ""
        var chunkIndex = 0

        for para in paragraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if current.isEmpty {
                current = trimmed
            } else if (current.count + trimmed.count + 2) <= targetSize {
                current += "\n\n" + trimmed
            } else {
                chunks.append((current, chunkIndex))
                chunkIndex += 1
                let overlapText = String(current.suffix(overlap))
                current = overlapText + "\n\n" + trimmed
            }
        }

        if !current.isEmpty {
            chunks.append((current, chunkIndex))
        }

        return chunks
    }

    public static func toEmailChunks(
        email: EmailJSON,
        filePath: String
    ) -> [EmailChunk] {
        guard let body = email.content.body, !body.isEmpty else { return [] }

        let date = parseDate(email.headers.date)
        let components: DateComponents? = date.map {
            Calendar.current.dateComponents([.year, .month], from: $0)
        }
        let year = components?.year
        let month = components?.month
        let quarter = month.map { (($0 - 1) / 3) + 1 }

        let sentByMe = isSentByMe(email)
        let isReply = !(email.headers.in_reply_to ?? "").isEmpty
        let hasAttachments = (email.attachments.count ?? 0) > 0

        let toEmails = email.headers.to?.compactMap(\.email).joined(separator: ", ")
        let ccEmails = email.headers.cc?.compactMap(\.email).joined(separator: ", ")
        let bccEmails = email.headers.bcc?.compactMap(\.email).joined(separator: ", ")
        let labels = email.metadata.labels.map { items in
            let data = try? JSONEncoder().encode(items)
            return data.flatMap { String(data: $0, encoding: .utf8) }
        } ?? nil
        let attachmentNames: String? = email.attachments.files.flatMap { files in
            let names = files.compactMap(\.filename)
            guard !names.isEmpty else { return nil }
            let data = try? JSONEncoder().encode(names)
            return data.flatMap { String(data: $0, encoding: .utf8) }
        }
        let threadId = email.threading.thread_topic?.isEmpty == false
            ? email.threading.thread_topic : nil

        let chunks = chunkEmail(body)

        return chunks.map { (text, idx) in
            let chunkSuffix = chunks.count > 1 ? "_chunk\(idx)" : ""
            return EmailChunk(
                emailId: email.id.hash + chunkSuffix,
                emailPath: filePath,
                subject: email.headers.subject,
                fromName: email.headers.from.name,
                fromEmail: email.headers.from.email,
                toEmails: toEmails,
                ccEmails: ccEmails,
                chunkText: text,
                chunkIndex: idx,
                labels: labels,
                emailDate: date,
                year: year,
                month: month,
                quarter: quarter,
                isSentByMe: sentByMe,
                hasAttachments: hasAttachments,
                isReply: isReply,
                threadId: threadId,
                attachmentCount: email.attachments.count ?? 0,
                attachmentNames: attachmentNames,
                bccEmails: bccEmails,
                importance: email.metadata.importance?.isEmpty == false
                    ? email.metadata.importance : nil
            )
        }
    }
}
