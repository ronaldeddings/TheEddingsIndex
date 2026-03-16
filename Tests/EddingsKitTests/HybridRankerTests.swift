import Testing
import Foundation
@testable import EddingsKit

@Suite("Hybrid Ranker RRF")
struct HybridRankerTests {

    @Test("RRF combines FTS and semantic results")
    func rrfCombinesResults() {
        let ranker = HybridRanker()

        let ftsResults: [FTSIndex.FTSResult] = [
            .init(id: 1, sourceTable: .emailChunks, score: -5.0, snippet: nil),
            .init(id: 2, sourceTable: .emailChunks, score: -3.0, snippet: nil),
            .init(id: 3, sourceTable: .documents, score: -1.0, snippet: nil),
        ]

        let semanticResults: [(id: Int64, sourceTable: SearchResult.SourceTable, distance: Float)] = [
            (id: 2, sourceTable: .emailChunks, distance: 0.1),
            (id: 4, sourceTable: .slackChunks, distance: 0.2),
            (id: 1, sourceTable: .emailChunks, distance: 0.3),
        ]

        let ranked = ranker.rank(ftsResults: ftsResults, semanticResults: semanticResults)

        #expect(!ranked.isEmpty)

        let ids = ranked.map(\.id)
        #expect(ids.contains(1))
        #expect(ids.contains(2))
        #expect(ids.contains(3))
        #expect(ids.contains(4))
    }

    @Test("Dedup: same ID appearing in both lists gets combined score")
    func dedupCombinesScores() {
        let ranker = HybridRanker()

        let ftsResults: [FTSIndex.FTSResult] = [
            .init(id: 42, sourceTable: .emailChunks, score: -10.0, snippet: nil),
        ]

        let semanticResults: [(id: Int64, sourceTable: SearchResult.SourceTable, distance: Float)] = [
            (id: 42, sourceTable: .emailChunks, distance: 0.05),
        ]

        let ranked = ranker.rank(ftsResults: ftsResults, semanticResults: semanticResults)

        #expect(ranked.count == 1)
        #expect(ranked[0].id == 42)

        let ftsOnly = ranker.rank(ftsResults: ftsResults, semanticResults: [])
        #expect(ranked[0].score > ftsOnly[0].score)
    }

    @Test("Results sorted by score descending")
    func sortedByScoreDescending() {
        let ranker = HybridRanker()

        let ftsResults: [FTSIndex.FTSResult] = (1...10).map {
            .init(id: Int64($0), sourceTable: .documents, score: Double(-$0), snippet: nil)
        }

        let ranked = ranker.rank(ftsResults: ftsResults, semanticResults: [])

        for i in 1..<ranked.count {
            #expect(ranked[i - 1].score >= ranked[i].score)
        }
    }

    @Test("Empty inputs produce empty output")
    func emptyInputs() {
        let ranker = HybridRanker()
        let ranked = ranker.rank(ftsResults: [], semanticResults: [])
        #expect(ranked.isEmpty)
    }

    @Test("Semantic weight (0.6) outweighs FTS weight (0.4)")
    func semanticOutweighsFTS() {
        let ranker = HybridRanker()

        let ftsResults: [FTSIndex.FTSResult] = [
            .init(id: 1, sourceTable: .documents, score: -10.0, snippet: nil),
        ]

        let semanticResults: [(id: Int64, sourceTable: SearchResult.SourceTable, distance: Float)] = [
            (id: 2, sourceTable: .documents, distance: 0.01),
        ]

        let ranked = ranker.rank(ftsResults: ftsResults, semanticResults: semanticResults)
        #expect(ranked.count == 2)
        #expect(ranked[0].id == 2)
    }
}
