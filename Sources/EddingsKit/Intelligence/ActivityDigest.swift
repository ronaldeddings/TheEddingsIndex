import Foundation
import GRDB
import os

public struct ActivityDigest: Sendable {
    private let dbPool: DatabasePool
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "digest")

    public init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    public struct DailyDigest: Sendable {
        public let date: Date
        public let emailsReceived: Int
        public let emailsSent: Int
        public let meetingsAttended: Int
        public let slackMessages: Int
        public let transactionCount: Int
        public let totalSpending: Double
    }

    public func daily(for date: Date = Date()) throws -> DailyDigest {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try dbPool.read { db in
            let emailsReceived = try EmailChunk
                .filter(Column("emailDate") >= startOfDay && Column("emailDate") < endOfDay && Column("isSentByMe") == false)
                .fetchCount(db)

            let emailsSent = try EmailChunk
                .filter(Column("emailDate") >= startOfDay && Column("emailDate") < endOfDay && Column("isSentByMe") == true)
                .fetchCount(db)

            let meetings = try Meeting
                .filter(Column("startTime") >= startOfDay && Column("startTime") < endOfDay)
                .fetchCount(db)

            let slack = try SlackChunk
                .filter(Column("messageDate") >= startOfDay && Column("messageDate") < endOfDay)
                .fetchCount(db)

            let txnCount = try FinancialTransaction
                .filter(Column("transactionDate") >= startOfDay && Column("transactionDate") < endOfDay)
                .fetchCount(db)

            let spending = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(ABS(amount)), 0) FROM financialTransactions
                WHERE transactionDate >= ? AND transactionDate < ? AND amount < 0
                """, arguments: [startOfDay, endOfDay]) ?? 0

            return DailyDigest(
                date: date,
                emailsReceived: emailsReceived,
                emailsSent: emailsSent,
                meetingsAttended: meetings,
                slackMessages: slack,
                transactionCount: txnCount,
                totalSpending: spending
            )
        }
    }
}
