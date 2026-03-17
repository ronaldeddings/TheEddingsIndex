import SwiftUI
import EddingsKit
import GRDB

#if DEBUG && canImport(SwiftUIDebugKit)
import SwiftUIDebugKit
#endif

private func log(_ msg: String) {
    let path = "/tmp/ei-diag.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

@main
struct EddingsApp: App {
    @State private var engine = EddingsEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .environment(engine.searchVM)
                .environment(engine.freedomVM)
                .environment(engine.peopleVM)
                .environment(engine.meetingsVM)
                .environment(engine.settingsVM)
                #if DEBUG && canImport(SwiftUIDebugKit)
                .debugInspectable()
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(engine)
                .environment(engine.settingsVM)
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
    var selectedSection: SidebarSection = .search

    let dbManager: DatabaseManager?
    let queryEngine: QueryEngine?
    let vectorIndex: VectorIndex?
    let dataAccess: DataAccess?
    let stateManager: StateManager?

    let searchVM: SearchViewModel
    let freedomVM: FreedomViewModel
    let peopleVM: PeopleViewModel
    let meetingsVM: MeetingsViewModel
    let settingsVM: SettingsViewModel

    private let dbPath: String

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("com.hackervalley.eddingsindex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let path = dbDir.appendingPathComponent("eddings.sqlite").path
        self.dbPath = path

        var mgr: DatabaseManager?
        var eng: QueryEngine?
        var vi: VectorIndex?
        var da: DataAccess?
        var sm: StateManager?

        do {
            let manager = try DatabaseManager(path: path)
            mgr = manager
            da = DataAccess(dbPool: manager.dbPool)

            let vectorDir = dbDir.appendingPathComponent("vectors", isDirectory: true)
            try? FileManager.default.createDirectory(at: vectorDir, withIntermediateDirectories: true)
            let vectorIdx = try VectorIndex(directory: vectorDir)
            vi = vectorIdx
            eng = QueryEngine(dbPool: manager.dbPool, vectorIndex: vectorIdx)

            let stateDir = dbDir.appendingPathComponent("state", isDirectory: true)
            try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
            sm = StateManager(directory: stateDir)
        } catch {
            log("[EI] ERROR: Database init failed: \(error)")
            mgr = nil
            eng = nil
            vi = nil
            da = nil
            sm = nil
        }

        if let da {
            log("[EI] Database connected at: \(path)")
            if let counts = try? da.tableCounts() {
                log("[EI] Table counts: \(counts)")
            }
        } else {
            log("[EI] WARNING: No database connection")
        }

        self.dbManager = mgr
        self.queryEngine = eng
        self.vectorIndex = vi
        self.dataAccess = da
        self.stateManager = sm

        self.searchVM = SearchViewModel(queryEngine: eng, dataAccess: da)
        self.freedomVM = FreedomViewModel(dataAccess: da)
        self.peopleVM = PeopleViewModel(dataAccess: da, dbPool: mgr?.dbPool)
        self.meetingsVM = MeetingsViewModel(dataAccess: da)
        self.settingsVM = SettingsViewModel(dataAccess: da, stateManager: sm, vectorIndex: vi, dbPath: path)

        Task {
            log("[EI] Loading data...")
            await freedomVM.load()
            log("[EI] Freedom loaded: score=\(String(describing: freedomVM.freedomScore))")
            await peopleVM.load()
            log("[EI] People loaded: \(peopleVM.scoredContacts.count) contacts")
            await meetingsVM.load()
            log("[EI] Meetings loaded: \(meetingsVM.meetings.count) meetings")
            await settingsVM.load()
            log("[EI] Settings loaded: \(settingsVM.tableCounts.count) tables")
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
