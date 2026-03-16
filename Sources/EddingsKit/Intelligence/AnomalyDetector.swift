import Foundation
import GRDB
import os

public struct AnomalyDetector: Sendable {
    private let dbPool: DatabasePool
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "anomaly")

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    public struct Anomaly: Sendable {
        public let type: AnomalyType
        public let transaction: FinancialTransaction
        public let detail: String
    }

    public enum AnomalyType: String, Sendable {
        case unusualAmount
        case newMerchant
        case duplicateCharge
        case priceIncrease
        case missingRecurring
    }

    public func detect(transactions: [FinancialTransaction], lookbackDays: Int = 90) -> [Anomaly] {
        var anomalies: [Anomaly] = []

        let amounts = transactions.map { abs($0.amount) }
        let mean = amounts.reduce(0, +) / Double(max(amounts.count, 1))
        let variance = amounts.map { pow($0 - mean, 2) }.reduce(0, +) / Double(max(amounts.count - 1, 1))
        let stddev = sqrt(variance)

        for txn in transactions {
            if abs(txn.amount) > mean + 3 * stddev {
                anomalies.append(Anomaly(
                    type: .unusualAmount,
                    transaction: txn,
                    detail: "Amount $\(String(format: "%.2f", abs(txn.amount))) is >3σ from mean $\(String(format: "%.2f", mean))"
                ))
            }
        }

        let payeeCounts = Dictionary(grouping: transactions, by: { $0.payee ?? "unknown" })
        for (payee, txns) in payeeCounts {
            guard txns.count >= 2 else { continue }
            let sorted = txns.sorted { $0.transactionDate < $1.transactionDate }
            for i in 1..<sorted.count {
                let prev = sorted[i - 1]
                let curr = sorted[i]
                let gap = curr.transactionDate.timeIntervalSince(prev.transactionDate)

                if gap < 24 * 3600 && abs(prev.amount - curr.amount) < 0.01 {
                    anomalies.append(Anomaly(
                        type: .duplicateCharge,
                        transaction: curr,
                        detail: "Duplicate: \(payee) charged $\(String(format: "%.2f", abs(curr.amount))) twice within 24h"
                    ))
                }

                if curr.amount < 0 && prev.amount < 0 {
                    let increase = (abs(curr.amount) - abs(prev.amount)) / abs(prev.amount)
                    if increase > 0.05 {
                        anomalies.append(Anomaly(
                            type: .priceIncrease,
                            transaction: curr,
                            detail: "\(payee) increased from $\(String(format: "%.2f", abs(prev.amount))) to $\(String(format: "%.2f", abs(curr.amount))) (+\(String(format: "%.0f", increase * 100))%)"
                        ))
                    }
                }
            }
        }

        logger.info("Detected \(anomalies.count) anomalies across \(transactions.count) transactions")
        return anomalies
    }
}
