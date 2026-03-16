@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers
import os

public struct SpotlightIndexer: Sendable {
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "spotlight")

    public init() {}

    public func indexContacts(_ contacts: [Contact]) {
        let items = contacts.compactMap { contact -> CSSearchableItem? in
            guard let id = contact.id else { return nil }
            let attributes = CSSearchableItemAttributeSet(contentType: .contact)
            attributes.displayName = contact.name
            attributes.emailAddresses = contact.email.map { [$0] }
            attributes.title = contact.name
            return CSSearchableItem(
                uniqueIdentifier: "contact/\(id)",
                domainIdentifier: "com.hackervalley.eddingsindex.contacts",
                attributeSet: attributes
            )
        }

        let contactCount = items.count
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                logger.error("Failed to index contacts: \(error)")
            } else {
                logger.info("Indexed \(contactCount) contacts in Spotlight")
            }
        }
    }

    public func indexDocuments(_ documents: [Document]) {
        let items = documents.compactMap { doc -> CSSearchableItem? in
            guard let id = doc.id else { return nil }
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = doc.filename
            attributes.contentDescription = doc.content.map { String($0.prefix(500)) }
            attributes.path = doc.path
            return CSSearchableItem(
                uniqueIdentifier: "document/\(id)",
                domainIdentifier: "com.hackervalley.eddingsindex.documents",
                attributeSet: attributes
            )
        }

        let docCount = items.count
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                logger.error("Failed to index documents: \(error)")
            } else {
                logger.info("Indexed \(docCount) documents in Spotlight")
            }
        }
    }
}
