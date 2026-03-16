import Foundation

public struct SearchResult: Codable, Sendable, Identifiable {
    public let id: Int64
    public let sourceTable: SourceTable
    public let title: String
    public let snippet: String?
    public let date: Date?
    public let score: Double
    public let metadata: [String: String]?

    public enum SourceTable: String, Codable, Sendable {
        case documents
        case emailChunks
        case slackChunks
        case transcriptChunks
        case financialTransactions
        case contacts
        case meetings
    }
}

public struct RankedResult: Sendable {
    public let id: Int64
    public let sourceTable: SearchResult.SourceTable
    public let score: Double
    public let snippet: String?
}
