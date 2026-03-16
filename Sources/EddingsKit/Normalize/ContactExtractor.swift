import Foundation
import GRDB
import os

public struct ContactExtractor: Sendable {
    private let dbPool: DatabasePool
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "contacts")

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    public func extractFromEmail(_ email: EmailChunk) throws {
        guard let fromEmail = email.fromEmail, !fromEmail.isEmpty else { return }

        try dbPool.write { db in
            if let existing = try Contact.filter(Column("email") == fromEmail).fetchOne(db) {
                var updated = existing
                updated.emailCount += 1
                updated.lastSeenAt = email.emailDate ?? Date()
                try updated.update(db)
            } else {
                let domain = extractDomain(from: fromEmail)
                let companyId = try findOrCreateCompany(db: db, domain: domain)

                var contact = Contact(
                    name: email.fromName ?? fromEmail,
                    email: fromEmail,
                    companyId: companyId,
                    firstSeenAt: email.emailDate ?? Date(),
                    lastSeenAt: email.emailDate ?? Date(),
                    emailCount: 1
                )
                try contact.insert(db)
            }
        }
    }

    public func extractFromSlack(speakerName: String, channel: String) throws {
        try dbPool.write { db in
            if let existing = try Contact.filter(Column("name") == speakerName).fetchOne(db) {
                var updated = existing
                updated.slackCount += 1
                updated.lastSeenAt = Date()
                try updated.update(db)
            } else {
                var contact = Contact(
                    name: speakerName,
                    firstSeenAt: Date(),
                    lastSeenAt: Date(),
                    slackCount: 1
                )
                try contact.insert(db)
            }
        }
    }

    public func extractFromMeeting(participantName: String, meetingDate: Date) throws {
        try dbPool.write { db in
            if let existing = try Contact.filter(Column("name") == participantName).fetchOne(db) {
                var updated = existing
                updated.meetingCount += 1
                updated.lastSeenAt = meetingDate
                try updated.update(db)
            } else {
                var contact = Contact(
                    name: participantName,
                    firstSeenAt: meetingDate,
                    lastSeenAt: meetingDate,
                    meetingCount: 1
                )
                try contact.insert(db)
            }
        }
    }

    private func extractDomain(from email: String) -> String? {
        let parts = email.split(separator: "@")
        guard parts.count == 2 else { return nil }
        let domain = String(parts[1]).lowercased()
        let freeProviders: Set<String> = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com", "icloud.com", "me.com"]
        return freeProviders.contains(domain) ? nil : domain
    }

    private func findOrCreateCompany(db: Database, domain: String?) throws -> Int64? {
        guard let domain else { return nil }

        if let existing = try Company.filter(Column("domain") == domain).fetchOne(db) {
            return existing.id
        }

        let companyName = domain.split(separator: ".").first.map { String($0).capitalized } ?? domain
        var company = Company(name: companyName, domain: domain)
        try company.insert(db)
        return company.id
    }
}
