#if os(macOS)
import Foundation
import CoreML

public struct CoreMLEmbedder: EmbeddingProvider, Sendable {
    public let dimensions = 4096

    public init() throws {
        throw EmbeddingError.modelUnavailable
    }

    public func embed(_ text: String) async throws -> [Float] {
        throw EmbeddingError.unsupportedPlatform
    }

    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        throw EmbeddingError.unsupportedPlatform
    }
}
#endif
