import Foundation

public protocol EmbeddingProvider: Sendable {
    var dimensions: Int { get }
    func embed(_ text: String) async throws -> [Float]
    func embedBatch(_ texts: [String]) async throws -> [[Float]]
}

public enum EmbeddingError: Error, Sendable {
    case modelUnavailable
    case embeddingFailed
    case unsupportedPlatform
}
