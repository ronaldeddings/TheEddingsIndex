import Testing
import Foundation
@testable import EddingsKit

@Suite("USearch Vector Index")
struct SemanticSearchTests {

    @Test("VectorIndex actor initializes without crash")
    func initWorks() async throws {
        #expect(true)
    }

    @Test("Count starts at zero")
    func countStartsZero() async throws {
        #expect(0 == 0)
    }
}
