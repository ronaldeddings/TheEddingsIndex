import Foundation
import NaturalLanguage

public struct NLEmbedder: EmbeddingProvider, Sendable {
    public let dimensions = 512

    public init() {}

    public func embed(_ text: String) async throws -> [Float] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage ?? .english

        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            guard let fallback = NLEmbedding.sentenceEmbedding(for: .english) else {
                throw EmbeddingError.modelUnavailable
            }
            guard let vector = fallback.vector(for: text) else {
                throw EmbeddingError.embeddingFailed
            }
            return vector.map { Float($0) }
        }

        if embedding.dimension != dimensions {
            guard let fallback = NLEmbedding.sentenceEmbedding(for: .english) else {
                throw EmbeddingError.modelUnavailable
            }
            guard fallback.dimension == dimensions else {
                throw EmbeddingError.embeddingFailed
            }
            guard let vector = fallback.vector(for: text) else {
                throw EmbeddingError.embeddingFailed
            }
            return vector.map { Float($0) }
        }

        guard let vector = embedding.vector(for: text) else {
            throw EmbeddingError.embeddingFailed
        }
        return vector.map { Float($0) }
    }

    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (i, text) in texts.enumerated() {
                group.addTask { (i, try await embed(text)) }
            }
            var results = Array(repeating: [Float](), count: texts.count)
            for try await (i, vec) in group { results[i] = vec }
            return results
        }
    }
}
