import Foundation

public struct TranscriptFrontmatter: Sendable {
    public let title: String?
    public let date: Date?
    public let meetingId: String?
}

public struct SpeakerTurn: Sendable {
    public let timestamp: String
    public let speaker: String
    public let text: String
}

public struct TranscriptParser: Sendable {

    private static let turnPattern = try! NSRegularExpression(
        pattern: #"\*\*\[(\d{1,2}:\d{2})\]\*\*\s*\*\*([^*]+)\*\*:\s*(.+)"#,
        options: []
    )

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parseFrontmatter(from content: String) -> TranscriptFrontmatter {
        guard content.hasPrefix("---") else {
            return TranscriptFrontmatter(title: nil, date: nil, meetingId: nil)
        }

        let lines = content.components(separatedBy: "\n")
        var title: String?
        var dateStr: String?
        var meetingId: String?
        var inFrontmatter = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                if inFrontmatter { break }
                inFrontmatter = true
                continue
            }
            guard inFrontmatter else { continue }

            if trimmed.hasPrefix("title:") {
                title = extractYAMLValue(trimmed, key: "title")
            } else if trimmed.hasPrefix("date:") {
                dateStr = extractYAMLValue(trimmed, key: "date")
            } else if trimmed.hasPrefix("meeting_id:") {
                meetingId = extractYAMLValue(trimmed, key: "meeting_id")
            }
        }

        var date: Date?
        if let dateStr {
            date = isoFormatter.date(from: dateStr)
        }

        return TranscriptFrontmatter(title: title, date: date, meetingId: meetingId)
    }

    private static func extractYAMLValue(_ line: String, key: String) -> String {
        let value = String(line.dropFirst(key.count + 1))
            .trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    public static func parseSpeakerTurns(from content: String) -> [SpeakerTurn] {
        let lines = content.components(separatedBy: "\n")
        var turns: [SpeakerTurn] = []

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = turnPattern.firstMatch(in: line, range: range) else { continue }

            guard let tsRange = Range(match.range(at: 1), in: line),
                  let speakerRange = Range(match.range(at: 2), in: line),
                  let textRange = Range(match.range(at: 3), in: line) else { continue }

            turns.append(SpeakerTurn(
                timestamp: String(line[tsRange]),
                speaker: String(line[speakerRange]).trimmingCharacters(in: .whitespaces),
                text: String(line[textRange]).trimmingCharacters(in: .whitespaces)
            ))
        }

        return turns
    }

    public static func chunkTurns(
        _ turns: [SpeakerTurn],
        targetSize: Int = 1800,
        overlap: Int = 400
    ) -> [(text: String, index: Int, speakers: [String], startTime: String?, endTime: String?)] {
        guard !turns.isEmpty else { return [] }

        var chunks: [(String, Int, [String], String?, String?)] = []
        var currentLines: [String] = []
        var currentSize = 0
        var currentSpeakers: Set<String> = []
        var currentStartTime: String?
        var chunkIndex = 0

        for turn in turns {
            let formatted = "[\(turn.timestamp)] \(turn.speaker): \(turn.text)"

            if currentStartTime == nil {
                currentStartTime = turn.timestamp
            }

            if currentSize + formatted.count > targetSize && !currentLines.isEmpty {
                let text = currentLines.joined(separator: "\n")
                chunks.append((
                    text,
                    chunkIndex,
                    Array(currentSpeakers),
                    currentStartTime,
                    turn.timestamp
                ))
                chunkIndex += 1

                let overlapTarget = overlap
                var overlapLines: [String] = []
                var overlapSize = 0
                for line in currentLines.reversed() {
                    if overlapSize + line.count > overlapTarget { break }
                    overlapLines.insert(line, at: 0)
                    overlapSize += line.count
                }

                currentLines = overlapLines
                currentSize = overlapSize
                currentSpeakers = Set(overlapLines.compactMap { extractSpeakerFromFormatted($0) })
                currentStartTime = turn.timestamp
            }

            currentLines.append(formatted)
            currentSize += formatted.count
            currentSpeakers.insert(turn.speaker)
        }

        if !currentLines.isEmpty {
            let text = currentLines.joined(separator: "\n")
            let lastTurn = turns.last
            chunks.append((
                text,
                chunkIndex,
                Array(currentSpeakers),
                currentStartTime,
                lastTurn?.timestamp
            ))
        }

        return chunks
    }

    private static func extractSpeakerFromFormatted(_ line: String) -> String? {
        guard let closeBracket = line.firstIndex(of: "]"),
              let colon = line[closeBracket...].firstIndex(of: ":") else { return nil }
        let start = line.index(after: closeBracket)
        let name = line[start..<colon].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    public static func toTranscriptChunks(
        content: String,
        filePath: String
    ) -> (frontmatter: TranscriptFrontmatter, chunks: [TranscriptChunk]) {
        let frontmatter = parseFrontmatter(from: content)
        let turns = parseSpeakerTurns(from: content)
        let chunked = chunkTurns(turns)

        let components: DateComponents? = frontmatter.date.map {
            Calendar.current.dateComponents([.year, .month], from: $0)
        }
        let year = components?.year
        let month = components?.month
        let quarter = month.map { (($0 - 1) / 3) + 1 }

        let meetingId = frontmatter.meetingId
            ?? URL(filePath: filePath).deletingPathExtension().lastPathComponent

        let transcriptChunks = chunked.map { (text, idx, speakers, start, end) in
            TranscriptChunk(
                filePath: filePath,
                chunkText: text,
                chunkIndex: idx,
                speakers: speakers.joined(separator: ", "),
                speakerName: speakers.first,
                meetingId: meetingId,
                year: year,
                month: month,
                quarter: quarter,
                startTime: start,
                endTime: end
            )
        }

        return (frontmatter, transcriptChunks)
    }
}
