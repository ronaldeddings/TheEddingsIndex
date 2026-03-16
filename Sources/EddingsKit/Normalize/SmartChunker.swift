import Foundation

public struct SmartChunker: Sendable {
    public let targetSize: Int
    public let overlap: Int

    public init(targetSize: Int = 200, overlap: Int = 50) {
        self.targetSize = targetSize
        self.overlap = overlap
    }

    public struct Chunk: Sendable {
        public let text: String
        public let index: Int
    }

    public func chunk(_ text: String) -> [Chunk] {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return [] }

        var chunks: [Chunk] = []
        var currentChunk = ""
        var currentWordCount = 0
        var chunkIndex = 0

        for paragraph in paragraphs {
            let words = paragraph.split(separator: " ").count

            if currentWordCount + words > targetSize && !currentChunk.isEmpty {
                chunks.append(Chunk(text: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), index: chunkIndex))
                chunkIndex += 1

                let overlapText = extractOverlap(from: currentChunk)
                currentChunk = overlapText + "\n\n" + paragraph
                currentWordCount = overlapText.split(separator: " ").count + words
            } else {
                if !currentChunk.isEmpty { currentChunk += "\n\n" }
                currentChunk += paragraph
                currentWordCount += words
            }
        }

        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(Chunk(text: currentChunk.trimmingCharacters(in: .whitespacesAndNewlines), index: chunkIndex))
        }

        return chunks
    }

    private func extractOverlap(from text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count > overlap else { return "" }
        let candidateWords = words.suffix(overlap)
        let candidate = candidateWords.joined(separator: " ")

        let sentenceEnders: [Character] = [".", "!", "?"]
        var lastBoundary: String.Index?
        var i = candidate.startIndex
        while i < candidate.endIndex {
            let c = candidate[i]
            let next = candidate.index(after: i)
            if sentenceEnders.contains(c) && next < candidate.endIndex && candidate[next] == " " {
                lastBoundary = next
            }
            i = next
        }

        if let boundary = lastBoundary {
            let afterBoundary = candidate.index(after: boundary)
            if afterBoundary < candidate.endIndex {
                return String(candidate[afterBoundary...])
            }
        }

        return candidate
    }
}
