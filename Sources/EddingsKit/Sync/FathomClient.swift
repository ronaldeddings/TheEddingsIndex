import Foundation
import GRDB
import os

public struct FathomClient: Sendable {
    private let dbPool: DatabasePool
    private let transcriptPath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "fathom")
    private let chunker = SmartChunker()

    public init(
        dbPool: DatabasePool,
        transcriptPath: String = "/Volumes/VRAM/10-19_Work/13_Meetings/13.01_transcripts"
    ) {
        self.dbPool = dbPool
        self.transcriptPath = transcriptPath
    }

    public func sync() throws -> Int {
        guard FileManager.default.fileExists(atPath: transcriptPath) else {
            logger.warning("Transcript path not found: \(transcriptPath)")
            return 0
        }

        logger.info("Scanning transcripts at \(transcriptPath)")
        var count = 0

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(filePath: transcriptPath),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let existingPaths = try dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT filePath FROM transcriptChunks")
        }
        let existingSet = Set(existingPaths)

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "txt" || ext == "md" || ext == "vtt" || ext == "srt" else { continue }

            let path = url.path()
            guard !existingSet.contains(path) else { continue }

            guard let content = try? String(contentsOfFile: path, encoding: .utf8),
                  !content.isEmpty else { continue }

            let meetingId = url.deletingPathExtension().lastPathComponent
            let chunks = chunker.chunk(content)

            try dbPool.write { db in
                for chunk in chunks {
                    let speaker = extractSpeaker(from: chunk.text)
                    var tc = TranscriptChunk(
                        filePath: path,
                        chunkText: chunk.text,
                        chunkIndex: chunk.index,
                        speakerName: speaker,
                        meetingId: meetingId
                    )
                    try tc.insert(db)
                    count += 1
                }
            }
        }

        logger.info("Fathom sync: \(count) new transcript chunks indexed")
        return count
    }

    private static let colonPattern = try! NSRegularExpression(
        pattern: #"^([A-Z][A-Za-z\s\-'.]{1,40}):\s"#, options: []
    )
    private static let bracketPattern = try! NSRegularExpression(
        pattern: #"^\[([A-Za-z\s\-'.]{2,40})\]\s"#, options: []
    )
    private static let timestampPattern = try! NSRegularExpression(
        pattern: #"^([A-Z][A-Za-z\s\-'.]{1,40})\s+\d{1,2}:\d{2}(:\d{2})?"#, options: []
    )

    private func extractSpeaker(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        let scanLines = lines.prefix(5)

        for line in scanLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            if let match = Self.colonPattern.firstMatch(in: trimmed, range: range),
               let nameRange = Range(match.range(at: 1), in: trimmed) {
                return String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces)
            }

            if let match = Self.bracketPattern.firstMatch(in: trimmed, range: range),
               let nameRange = Range(match.range(at: 1), in: trimmed) {
                return String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces)
            }

            if let match = Self.timestampPattern.firstMatch(in: trimmed, range: range),
               let nameRange = Range(match.range(at: 1), in: trimmed) {
                return String(trimmed[nameRange]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }
}
