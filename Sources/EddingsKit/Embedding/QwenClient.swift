import Foundation

public struct QwenClient: Sendable {
    private let baseURL: String

    public init(baseURL: String = "http://localhost:8081") {
        self.baseURL = baseURL
    }

    public func embed(_ text: String) async throws -> [Float] {
        guard let url = URL(string: "\(baseURL)/v1/embeddings") else {
            throw EmbeddingError.embeddingFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = ["input": text, "model": "qwen"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.embeddingFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataArray = json?["data"] as? [[String: Any]],
              let first = dataArray.first,
              let embedding = first["embedding"] as? [Double] else {
            throw EmbeddingError.embeddingFailed
        }

        return embedding.map { Float($0) }
    }
}
