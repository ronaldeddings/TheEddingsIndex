import SwiftUI
import EddingsKit

@main
struct EddingsApp: App {
    @State private var engine = EddingsEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(engine)
        }
        #endif
    }
}

struct ContentView: View {
    @Environment(EddingsEngine.self) private var engine
    @SceneStorage("selectedSection") private var savedSection: String?

    var body: some View {
        #if os(macOS)
        AppSidebar()
            .onAppear { restoreSection() }
            .onChange(of: engine.selectedSection) { _, newValue in
                savedSection = newValue.rawValue
            }
        #else
        AppTabBar()
        #endif
    }

    private func restoreSection() {
        if let saved = savedSection,
           let section = EddingsEngine.SidebarSection(rawValue: saved) {
            engine.selectedSection = section
        }
    }
}

@MainActor
@Observable
final class EddingsEngine {
    var searchResults: [SearchResult] = []
    var searchQuery: String = ""
    var selectedSection: SidebarSection = .search
    var isSearching: Bool = false

    let dbManager: DatabaseManager?
    private let queryEngine: QueryEngine?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("com.hackervalley.eddingsindex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("eddingsindex.sqlite").path

        var mgr: DatabaseManager?
        var eng: QueryEngine?
        do {
            let manager = try DatabaseManager(path: dbPath)
            mgr = manager
            let vectorDir = dbDir.appendingPathComponent("vectors", isDirectory: true)
            try? FileManager.default.createDirectory(at: vectorDir, withIntermediateDirectories: true)
            let vectorIndex = try VectorIndex(directory: vectorDir)
            eng = QueryEngine(dbPool: manager.dbPool, vectorIndex: vectorIndex)
        } catch {
            mgr = nil
            eng = nil
        }
        self.dbManager = mgr
        self.queryEngine = eng
    }

    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let engine = queryEngine else {
            searchResults = []
            return
        }

        isSearching = true
        Task {
            do {
                let results = try await engine.search(query: query)
                self.searchResults = results
            } catch {
                self.searchResults = []
            }
            self.isSearching = false
        }
    }

    enum SidebarSection: String, CaseIterable, Identifiable {
        case search = "Search"
        case freedom = "Freedom"
        case meetings = "Meetings"
        case people = "People"
        case settings = "Settings"

        var id: String { rawValue }

        var sfSymbol: String {
            switch self {
            case .search: return "magnifyingglass"
            case .freedom: return "dollarsign.circle"
            case .meetings: return "video"
            case .people: return "person.2"
            case .settings: return "gear"
            }
        }
    }
}
