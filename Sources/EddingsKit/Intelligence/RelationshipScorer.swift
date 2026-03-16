import Foundation
import GRDB
import os

public struct RelationshipScorer: Sendable {
    private let dbPool: DatabasePool
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "relationship")

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    public struct RelationshipScore: Sendable {
        public let contact: Contact
        public let totalInteractions: Int
        public let depth: Depth
        public let daysSinceLastSeen: Int?
        public let isFading: Bool

        public enum Depth: String, Sendable {
            case deep
            case growing
            case peripheral
            case fading
        }
    }

    public func scoreAll() throws -> [RelationshipScore] {
        let contacts = try dbPool.read { db in
            try Contact.fetchAll(db)
        }

        let now = Date()
        return contacts.map { contact in
            let total = contact.meetingCount * 5 + contact.emailCount * 2 + contact.slackCount
            let daysSince = contact.lastSeenAt.map { Int(now.timeIntervalSince($0) / 86400) }

            let fadingThreshold: Int
            if total > 200 {
                fadingThreshold = 60
            } else if total > 50 {
                fadingThreshold = 30
            } else {
                fadingThreshold = 14
            }

            let depth: RelationshipScore.Depth
            let isFading: Bool

            if let days = daysSince, days > fadingThreshold && total > 50 {
                depth = .fading
                isFading = true
            } else if total > 200 {
                depth = .deep
                isFading = false
            } else if total > 20 {
                depth = .growing
                isFading = false
            } else {
                depth = .peripheral
                isFading = false
            }

            return RelationshipScore(
                contact: contact,
                totalInteractions: total,
                depth: depth,
                daysSinceLastSeen: daysSince,
                isFading: isFading
            )
        }
        .sorted { $0.totalInteractions > $1.totalInteractions }
    }

    public func fadingConnections() throws -> [RelationshipScore] {
        try scoreAll().filter(\.isFading)
    }
}
