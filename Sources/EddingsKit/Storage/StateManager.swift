import Foundation
import os

public actor StateManager {
    private var state: SyncState
    private let stateURL: URL
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "state")

    public init(directory: URL) {
        self.stateURL = directory.appending(path: "sync-state.json")

        if let data = try? Data(contentsOf: stateURL),
           let loaded = try? JSONDecoder().decode(SyncState.self, from: data) {
            self.state = loaded
        } else {
            self.state = .empty
        }
    }

    public func getState() -> SyncState {
        state
    }

    public func sourceState(for source: String) -> SyncState.SourceState {
        state.sources[source] ?? SyncState.SourceState(
            lastSyncAt: nil,
            lastStatus: .neverRun,
            recordsSynced: 0,
            error: nil
        )
    }

    public func updateSource(
        _ source: String,
        status: SyncState.SourceState.Status,
        recordsSynced: Int,
        error: String? = nil
    ) {
        state.sources[source] = SyncState.SourceState(
            lastSyncAt: Date(),
            lastStatus: status,
            recordsSynced: recordsSynced,
            error: error
        )
        save()
    }

    public var seenTransactionIds: Set<String> {
        get { state.seenTransactionIds }
    }

    public func updateSeenIds(_ ids: Set<String>) {
        state.seenTransactionIds = ids
        save()
    }

    private func save() {
        do {
            let dir = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            logger.error("Failed to save sync state: \(error.localizedDescription)")
        }
    }
}
