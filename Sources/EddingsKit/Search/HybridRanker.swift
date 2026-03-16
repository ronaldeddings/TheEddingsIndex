import Foundation

private struct CompositeKey: Hashable {
    let id: Int64
    let sourceTable: SearchResult.SourceTable
}

public struct HybridRanker: Sendable {
    public let ftsWeight: Double
    public let semanticWeight: Double
    public let k: Double

    public init(ftsWeight: Double = 0.4, semanticWeight: Double = 0.6, k: Double = 60) {
        self.ftsWeight = ftsWeight
        self.semanticWeight = semanticWeight
        self.k = k
    }

    public func rank(
        ftsResults: [FTSIndex.FTSResult],
        semanticResults: [(id: Int64, sourceTable: SearchResult.SourceTable, distance: Float)]
    ) -> [RankedResult] {
        var scores: [CompositeKey: Double] = [:]
        var snippets: [CompositeKey: String] = [:]

        for (rank, result) in ftsResults.enumerated() {
            let key = CompositeKey(id: result.id, sourceTable: result.sourceTable)
            let rrf = ftsWeight * (1.0 / (k + Double(rank + 1)))
            scores[key, default: 0] += rrf
            if let s = result.snippet, snippets[key] == nil {
                snippets[key] = s
            }
        }

        for (rank, result) in semanticResults.enumerated() {
            let key = CompositeKey(id: result.id, sourceTable: result.sourceTable)
            let rrf = semanticWeight * (1.0 / (k + Double(rank + 1)))
            scores[key, default: 0] += rrf
        }

        return scores
            .map { RankedResult(id: $0.key.id, sourceTable: $0.key.sourceTable, score: $0.value, snippet: snippets[$0.key]) }
            .sorted { $0.score > $1.score }
    }
}
