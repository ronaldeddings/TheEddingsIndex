import SwiftUI
import EddingsKit
import GRDB
import NaturalLanguage

@MainActor
@Observable
final class SearchViewModel {
    var query: String = ""
    var results: [SearchResult] = []
    var selectedResultId: Int64?
    var selectedSources: Set<EISource> = []
    var isSearching = false

    @ObservationIgnored private let queryEngine: QueryEngine?
    @ObservationIgnored private let dataAccess: DataAccess?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    init(queryEngine: QueryEngine?, dataAccess: DataAccess?) {
        self.queryEngine = queryEngine
        self.dataAccess = dataAccess
    }

    func search() {
        debounceTask?.cancel()
        let currentQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentQuery.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch(currentQuery)
        }
    }

    private func performSearch(_ text: String) async {
        guard let engine = queryEngine else {
            results = []
            isSearching = false
            return
        }

        do {
            var embedding: [Float]?
            let embedder = NLEmbedder()
            embedding = try? await embedder.embed(text)

            let sourceTables = selectedSources.isEmpty ? nil : selectedSources.map { mapSourceToTable($0) }

            let searchResults = try await engine.search(
                query: text,
                embedding: embedding,
                sources: sourceTables,
                limit: 30
            )
            guard !Task.isCancelled else { return }
            results = searchResults
        } catch {
            results = []
        }
        isSearching = false
    }

    func toggleSource(_ source: EISource) {
        if selectedSources.contains(source) {
            selectedSources.remove(source)
        } else {
            selectedSources.insert(source)
        }
        search()
    }

    func selectResult(_ id: Int64?) {
        selectedResultId = id
    }

    var selectedResult: SearchResult? {
        guard let id = selectedResultId else { return nil }
        return results.first { $0.id == id }
    }

    func resolveResult(_ result: SearchResult) -> (title: String, fullText: String, metadata: [String: String]) {
        guard let da = dataAccess else {
            return (title: result.title, fullText: result.fullContent ?? "", metadata: result.metadata ?? [:])
        }
        return (try? da.resolveSearchResult(result))
            ?? (title: result.title, fullText: result.fullContent ?? "", metadata: result.metadata ?? [:])
    }

    private func mapSourceToTable(_ source: EISource) -> FTSIndex.FTSTable {
        switch source {
        case .email: return .emailChunks
        case .slack: return .slackChunks
        case .meeting, .transcript: return .transcriptChunks
        case .file: return .documents
        case .finance: return .financialTransactions
        }
    }
}
