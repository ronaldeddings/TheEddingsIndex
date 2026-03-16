import Testing
import Foundation
@testable import EddingsKit

@Suite("Vector Migration")
struct VectorMigrationTests {

    @Test("Add 4096-dim vector to USearch index")
    func add4096Vector() async throws {
        let vectorIndex = try VectorIndex(inMemory: true)
        let vec = [Float](repeating: 0.01, count: 4096)
        try await vectorIndex.add4096(key: 1, vector: vec)
        try await vectorIndex.add4096(key: 2, vector: vec)
        let count = try await vectorIndex.count512
        #expect(count == 0)
    }

    @Test("Parse pgvector text format")
    func parsePgvectorText() {
        let raw = "[0.00805201,0.023793766,0.025325865,-0.03473185]"
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let floats = cleaned.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        #expect(floats.count == 4)
        #expect(abs(floats[0] - 0.00805201) < 0.0001)
    }
}
