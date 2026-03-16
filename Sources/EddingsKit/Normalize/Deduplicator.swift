import Foundation
import os

public struct Deduplicator: Sendable {
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "dedup")

    public init() {}

    public func deduplicate(
        _ transactions: [FinancialTransaction],
        seenIds: Set<String>
    ) -> (new: [FinancialTransaction], updatedSeenIds: Set<String>) {
        var newTransactions: [FinancialTransaction] = []
        var updatedSeen = seenIds

        for txn in transactions {
            if updatedSeen.contains(txn.transactionId) {
                continue
            }

            if fuzzyMatch(txn, against: newTransactions) {
                continue
            }

            newTransactions.append(txn)
            updatedSeen.insert(txn.transactionId)
        }

        logger.info("Dedup: \(transactions.count) input → \(newTransactions.count) new (\(transactions.count - newTransactions.count) duplicates)")
        return (newTransactions, updatedSeen)
    }

    private func fuzzyMatch(_ txn: FinancialTransaction, against existing: [FinancialTransaction]) -> Bool {
        for other in existing {
            let amountMatch = abs(txn.amount - other.amount) < 0.01
            let dateGap = abs(txn.transactionDate.timeIntervalSince(other.transactionDate))
            let withinDay = dateGap < 24 * 3600

            let payeeMatch: Bool
            if let p1 = txn.payee, let p2 = other.payee {
                payeeMatch = p1.lowercased() == p2.lowercased()
            } else {
                payeeMatch = txn.description == other.description
            }

            if amountMatch && withinDay && payeeMatch {
                return true
            }
        }
        return false
    }

    public func overlapStartDate(lastSync: Date, overlapDays: Int = 5) -> Date {
        Calendar.current.date(byAdding: .day, value: -overlapDays, to: lastSync) ?? lastSync
    }

    public func pruneSeenIds(_ seenIds: Set<String>, maxAge: Int = 90, currentIds: [String]) -> Set<String> {
        let recent = Set(currentIds)
        return seenIds.intersection(recent)
    }
}
