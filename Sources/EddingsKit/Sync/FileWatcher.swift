#if os(macOS)
import CoreServices
import Foundation
import GRDB
import os

public actor FileWatcher {
    private var stream: FSEventStreamRef?
    private let dbPool: DatabasePool
    private let embeddingPipeline: EmbeddingPipeline
    private let queue: DispatchQueue
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "filewatcher")
    private var isWatching = false
    private var isPaused = false

    public struct FileEvent: Sendable {
        public let path: String
        public let flags: FSEventStreamEventFlags

        public var isCreated: Bool { flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 }
        public var isModified: Bool { flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 }
        public var isRemoved: Bool { flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 }
        public var isRenamed: Bool { flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 }
        public var isFile: Bool { flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 }
        public var isDir: Bool { flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 }
        public var mustScanSubDirs: Bool { flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
        public var rootChanged: Bool { flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 }
        public var isMount: Bool { flags & UInt32(kFSEventStreamEventFlagMount) != 0 }
        public var isUnmount: Bool { flags & UInt32(kFSEventStreamEventFlagUnmount) != 0 }
    }

    private static let watchPaths: [String] = [
        "/Volumes/VRAM/10-19_Work/14_Communications/14.01b_emails_json",
        "/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack",
        "/Volumes/VRAM/10-19_Work/13_Meetings/13.01_transcripts",
        "/Volumes/VRAM/10-19_Work",
        "/Volumes/VRAM/20-29_Finance",
        "/Volumes/VRAM/30-39_Personal",
        "/Volumes/VRAM/40-49_Family",
        "/Volumes/VRAM/50-59_Social",
        "/Volumes/VRAM/60-69_Growth",
        "/Volumes/VRAM/70-79_Lifestyle",
    ]

    public init(dbPool: DatabasePool, embeddingPipeline: EmbeddingPipeline) {
        self.dbPool = dbPool
        self.embeddingPipeline = embeddingPipeline
        self.queue = DispatchQueue(label: "com.hackervalley.eddingsindex.filewatcher", qos: .utility)
    }

    public func start() {
        guard !isWatching else {
            logger.warning("FileWatcher already running")
            return
        }

        let existingPaths = Self.watchPaths.filter {
            FileManager.default.fileExists(atPath: $0)
        }

        guard !existingPaths.isEmpty else {
            logger.error("No watch paths exist — VRAM may not be mounted")
            return
        }

        let cfPaths = existingPaths as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer) |
            UInt32(kFSEventStreamCreateFlagIgnoreSelf)

        guard let newStream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            flags
        ) else {
            logger.error("Failed to create FSEventStream")
            return
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, queue)

        if FSEventStreamStart(newStream) {
            isWatching = true
            logger.info("FileWatcher started — monitoring \(existingPaths.count) paths")
        } else {
            logger.error("FSEventStreamStart failed")
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            stream = nil
        }
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isWatching = false
        logger.info("FileWatcher stopped")
    }

    nonisolated func handleEvents(_ events: [FileEvent]) {
        Task {
            await processEvents(events)
        }
    }

    private func processEvents(_ events: [FileEvent]) async {
        for event in events {
            if event.isMount {
                logger.info("Volume mounted — resuming watch")
                isPaused = false
                continue
            }
            if event.isUnmount || event.rootChanged {
                logger.warning("Volume unmounted or root changed — pausing indexing")
                isPaused = true
                continue
            }

            guard !isPaused else { continue }
            guard event.isFile else { continue }
            guard event.isCreated || event.isModified else { continue }

            await indexAndEmbed(path: event.path)
        }

        if !isPaused {
            do {
                try await embeddingPipeline.saveIndex()
            } catch {
                logger.warning("Failed to save vector index after batch: \(error)")
            }
        }
    }

    private func indexAndEmbed(path: String) async {
        do {
            if path.contains("/14.01b_emails_json/") && path.hasSuffix(".json") {
                let client = IMAPClient(dbPool: dbPool)
                let ids = try client.indexSingleFile(path: path)
                for id in ids {
                    try await embeddingPipeline.embedRecord(table: "emailChunks", id: id)
                }
            } else if path.contains("/14.02_slack/") && path.hasSuffix(".json") {
                let client = SlackClient(dbPool: dbPool)
                let ids = try client.indexSingleFile(path: path)
                for id in ids {
                    try await embeddingPipeline.embedRecord(table: "slackChunks", id: id)
                }
            } else if path.contains("/13.01_transcripts/") {
                let ext = URL(filePath: path).pathExtension.lowercased()
                guard ext == "md" || ext == "txt" else { return }
                let client = FathomClient(dbPool: dbPool)
                let ids = try client.indexSingleFile(path: path)
                for id in ids {
                    try await embeddingPipeline.embedRecord(table: "transcriptChunks", id: id)
                }
            } else {
                let scanner = FileScanner(dbPool: dbPool)
                if let id = try scanner.indexSingleFile(path: path) {
                    try await embeddingPipeline.embedRecord(table: "documents", id: id)
                }
            }
        } catch {
            logger.warning("Failed to index \(path): \(error)")
        }
    }
}

private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(clientInfo).takeUnretainedValue()

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var events: [FileWatcher.FileEvent] = []

    for i in 0..<numEvents {
        guard let cfPath = CFArrayGetValueAtIndex(paths, i) else { continue }
        let pathStr = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String
        events.append(FileWatcher.FileEvent(path: pathStr, flags: eventFlags[i]))
    }

    watcher.handleEvents(events)
}
#endif
