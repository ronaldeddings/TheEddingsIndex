import Foundation
import GRDB
import os

public struct FathomClient: Sendable {
    private let dbPool: DatabasePool
    private let transcriptPath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "fathom")

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
            let paths = try String.fetchAll(db, sql: "SELECT DISTINCT filePath FROM transcriptChunks")
            return Set(paths)
        }

        let contactExtractor = ContactExtractor(dbPool: dbPool)

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "txt" else { continue }

            let path = url.path()
            guard !existingPaths.contains(path) else { continue }

            guard let content = try? String(contentsOfFile: path, encoding: .utf8),
                  !content.isEmpty else { continue }

            let (frontmatter, chunks) = TranscriptParser.toTranscriptChunks(
                content: content,
                filePath: path
            )

            guard !chunks.isEmpty else { continue }

            try dbPool.write { db in
                let meetingId = frontmatter.meetingId
                    ?? URL(filePath: path).deletingPathExtension().lastPathComponent

                var meeting = try Meeting
                    .filter(Column("meetingId") == meetingId)
                    .fetchOne(db)

                if meeting == nil {
                    let components: DateComponents? = frontmatter.date.map {
                        Calendar.current.dateComponents([.year, .month], from: $0)
                    }
                    let year = components?.year
                    let month = components?.month
                    let quarter = month.map { (($0 - 1) / 3) + 1 }

                    meeting = Meeting(
                        meetingId: meetingId,
                        title: frontmatter.title,
                        startTime: frontmatter.date,
                        year: year,
                        month: month,
                        filePath: path,
                        quarter: quarter
                    )
                    try meeting?.insert(db)
                } else {
                    if meeting?.title == nil, let title = frontmatter.title {
                        meeting?.title = title
                    }
                    if meeting?.filePath == nil {
                        meeting?.filePath = path
                    }
                    if meeting?.quarter == nil, let month = meeting?.month {
                        meeting?.quarter = ((month - 1) / 3) + 1
                    }
                    try meeting?.update(db)
                }

                for var chunk in chunks {
                    try chunk.insert(db)
                    count += 1
                }

                if let meetingDbId = meeting?.id {
                    let allSpeakers = Set(chunks.flatMap {
                        ($0.speakers ?? "").split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }
                    })

                    for speaker in allSpeakers where !speaker.isEmpty {
                        let contact = try Contact
                            .filter(Column("name") == speaker)
                            .fetchOne(db)

                        let contactId: Int64?
                        if let existing = contact {
                            var updated = existing
                            updated.meetingCount += 1
                            updated.lastSeenAt = frontmatter.date ?? Date()
                            try updated.update(db)
                            contactId = existing.id
                        } else {
                            var newContact = Contact(
                                name: speaker,
                                firstSeenAt: frontmatter.date ?? Date(),
                                lastSeenAt: frontmatter.date ?? Date(),
                                meetingCount: 1
                            )
                            try newContact.insert(db)
                            contactId = newContact.id ?? db.lastInsertedRowID
                        }

                        if let contactId {
                            var participant = MeetingParticipant(
                                meetingId: meetingDbId,
                                contactId: contactId
                            )
                            try participant.insert(db, onConflict: .ignore)
                        }
                    }
                }
            }
        }

        logger.info("Fathom sync: \(count) new transcript chunks indexed")
        return count
    }
}
