import SwiftUI
import EddingsKit
import GRDB

@MainActor
@Observable
final class SettingsViewModel {
    var syncSources: [(name: String, status: String, statusColor: Color, lastSync: String)] = []
    var tableCounts: [(name: String, count: Int)] = []
    var embeddingCount: Int = 0
    var databaseSize: String = ""
    var databasePath: String = ""
    var isLoading = false

    @ObservationIgnored private let dataAccess: DataAccess?
    @ObservationIgnored private let stateManager: StateManager?
    @ObservationIgnored private let vectorIndex: VectorIndex?
    @ObservationIgnored private let dbPath: String

    init(dataAccess: DataAccess?, stateManager: StateManager?, vectorIndex: VectorIndex?, dbPath: String) {
        self.dataAccess = dataAccess
        self.stateManager = stateManager
        self.vectorIndex = vectorIndex
        self.dbPath = dbPath
        self.databasePath = dbPath
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        await loadSyncSources()
        loadTableCounts()
        await loadEmbeddingCount()
        loadDatabaseSize()
    }

    private func loadSyncSources() async {
        guard let sm = stateManager else {
            syncSources = defaultSources()
            return
        }

        let state = await sm.getState()
        let sourceNames = ["simplefin": "SimpleFin", "email": "Email (IMAP)", "slack": "Slack",
                           "fathom": "Fathom", "files": "VRAM Filesystem"]

        syncSources = sourceNames.map { key, name in
            if let ss = state.sources[key] {
                let status: String
                let color: Color
                switch ss.lastStatus {
                case .success:
                    status = "Connected"
                    color = EIColor.emerald
                case .partial:
                    status = "Partial"
                    color = EIColor.gold
                case .failed:
                    status = "Error"
                    color = EIColor.rose
                case .neverRun:
                    status = "Not Synced"
                    color = EIColor.textTertiary
                }
                let lastSync = ss.lastSyncAt.map { $0.formatted(.relative(presentation: .named)) } ?? "Never"
                return (name: name, status: status, statusColor: color, lastSync: lastSync)
            }
            return (name: name, status: "Not Configured", statusColor: EIColor.textTertiary, lastSync: "Never")
        }
    }

    private func loadTableCounts() {
        guard let da = dataAccess else { return }
        do {
            let counts = try da.tableCounts()
            let displayNames = [
                ("documents", "Documents"),
                ("emailChunks", "Email Chunks"),
                ("slackChunks", "Slack Chunks"),
                ("transcriptChunks", "Transcript Chunks"),
                ("meetings", "Meetings"),
                ("contacts", "Contacts"),
                ("financialTransactions", "Transactions"),
                ("financialSnapshots", "Snapshots"),
            ]
            tableCounts = displayNames.map { key, name in
                (name: name, count: counts[key] ?? 0)
            }
        } catch {
            tableCounts = []
        }
    }

    private func loadEmbeddingCount() async {
        guard let vi = vectorIndex else { return }
        do {
            embeddingCount = try await vi.count512
        } catch {
            embeddingCount = 0
        }
    }

    private func loadDatabaseSize() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath)
        if let size = attrs?[.size] as? Int64 {
            databaseSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    private func defaultSources() -> [(name: String, status: String, statusColor: Color, lastSync: String)] {
        [
            (name: "SimpleFin", status: "Not Configured", statusColor: EIColor.textTertiary, lastSync: "Never"),
            (name: "Email (IMAP)", status: "Not Configured", statusColor: EIColor.textTertiary, lastSync: "Never"),
            (name: "Slack", status: "Not Configured", statusColor: EIColor.textTertiary, lastSync: "Never"),
            (name: "Fathom", status: "Not Configured", statusColor: EIColor.textTertiary, lastSync: "Never"),
            (name: "VRAM Filesystem", status: "Not Configured", statusColor: EIColor.textTertiary, lastSync: "Never"),
        ]
    }
}
