import Testing
import Foundation
@testable import EddingsKit

@Suite("Finance Pipeline")
struct FinancePipelineTests {

    func makeDB() throws -> DatabaseManager {
        try DatabaseManager.temporary()
    }

    @Test("Normalizer converts SimpleFin account to snapshot")
    func normalizeAccounts() {
        let normalizer = Normalizer()
        let account = SimpleFinClient.SimpleFinAccount(
            id: "acct-1",
            name: "Chase Checking",
            currency: "USD",
            balance: 5000.0,
            availableBalance: 4900.0,
            balanceDate: Date().timeIntervalSince1970,
            transactions: nil,
            org: SimpleFinClient.SimpleFinOrg(domain: "chase.com", name: "JPMorgan Chase")
        )

        let snapshots = normalizer.normalizeAccounts([account])
        #expect(snapshots.count == 1)
        #expect(snapshots[0].accountId == "acct-1")
        #expect(snapshots[0].balance == 5000.0)
        #expect(snapshots[0].accountType == "checking")
        #expect(snapshots[0].institution == "JPMorgan Chase")
    }

    @Test("Normalizer classifies credit card by name")
    func classifyCreditCard() {
        let normalizer = Normalizer()
        let account = SimpleFinClient.SimpleFinAccount(
            id: "cc-1",
            name: "Chase Sapphire Credit Card",
            currency: "USD",
            balance: -2500.0,
            availableBalance: nil,
            balanceDate: nil,
            transactions: nil,
            org: nil
        )

        let snapshots = normalizer.normalizeAccounts([account])
        #expect(snapshots[0].accountType == "creditCard")
    }

    @Test("Normalizer converts transactions with correct date components")
    func normalizeTransactions() {
        let normalizer = Normalizer()
        let march15 = TimeInterval(1742022000)

        let account = SimpleFinClient.SimpleFinAccount(
            id: "acct-1",
            name: "Checking",
            currency: "USD",
            balance: 5000,
            availableBalance: nil,
            balanceDate: nil,
            transactions: [
                SimpleFinClient.SimpleFinTransaction(
                    id: "txn-1",
                    posted: march15,
                    amount: "-59.99",
                    description: "ADOBE CREATIVE CLOUD",
                    payee: nil,
                    memo: nil,
                    pending: false
                )
            ],
            org: SimpleFinClient.SimpleFinOrg(domain: "chase.com", name: "Chase")
        )

        let txns = normalizer.normalizeTransactions([account])
        #expect(txns.count == 1)
        #expect(txns[0].amount == -59.99)
        #expect(txns[0].source == "simplefin")
    }

    @Test("Deduplicator removes seen IDs")
    func deduplicateSeenIds() {
        let dedup = Deduplicator()
        let txns = [
            FinancialTransaction(
                transactionId: "txn-1",
                source: "simplefin",
                accountId: "acct-1",
                transactionDate: Date(),
                amount: -50
            ),
            FinancialTransaction(
                transactionId: "txn-2",
                source: "simplefin",
                accountId: "acct-1",
                transactionDate: Date(),
                amount: -30
            ),
        ]

        let result = dedup.deduplicate(txns, seenIds: Set(["txn-1"]))
        #expect(result.new.count == 1)
        #expect(result.new[0].transactionId == "txn-2")
        #expect(result.updatedSeenIds.contains("txn-1"))
        #expect(result.updatedSeenIds.contains("txn-2"))
    }

    @Test("Deduplicator fuzzy matches same amount + date + payee")
    func deduplicateFuzzy() {
        let dedup = Deduplicator()
        let now = Date()
        let txns = [
            FinancialTransaction(
                transactionId: "txn-a",
                source: "simplefin",
                accountId: "acct-1",
                transactionDate: now,
                amount: -59.99,
                payee: "Adobe"
            ),
            FinancialTransaction(
                transactionId: "txn-b",
                source: "simplefin",
                accountId: "acct-1",
                transactionDate: now,
                amount: -59.99,
                payee: "Adobe"
            ),
        ]

        let result = dedup.deduplicate(txns, seenIds: Set())
        #expect(result.new.count == 1)
    }

    @Test("FreedomTracker calculates velocity percentage")
    func freedomVelocity() {
        let tracker = FreedomTracker()
        let snapshots = [
            FinancialSnapshot(
                snapshotDate: Date(),
                accountId: "checking",
                accountType: "checking",
                balance: 10000,
                source: "simplefin"
            ),
            FinancialSnapshot(
                snapshotDate: Date(),
                accountId: "cc",
                accountType: "creditCard",
                balance: -2000,
                source: "simplefin"
            ),
        ]

        let transactions = [
            FinancialTransaction(
                transactionId: "dep-1",
                source: "qbo",
                accountId: "biz",
                transactionDate: Date(),
                amount: 12000,
                payee: "Optro",
                category: "Client Payment"
            ),
        ]

        let score = tracker.calculate(snapshots: snapshots, transactions: transactions, weeksElapsed: 12)
        #expect(score.weeklyTarget == 6058.0)
        #expect(score.totalDebt == 2000.0)
        #expect(score.weeklyNonW2TakeHome == 1000.0)
    }

    @Test("Financial transactions insert and search via FTS5")
    func financialFTSSearch() throws {
        let db = try makeDB()
        try db.dbPool.write { db in
            var txn = FinancialTransaction(
                transactionId: "txn-adobe-1",
                source: "simplefin",
                accountId: "acct-1",
                transactionDate: Date(),
                amount: -59.99,
                description: "Monthly subscription renewal",
                payee: "Adobe Creative Cloud",
                category: "HVM Production",
                year: 2026,
                month: 3
            )
            try txn.insert(db)
        }

        let fts = FTSIndex(dbPool: db.dbPool)
        let results = try fts.search(query: "Adobe", tables: [.financialTransactions])
        #expect(!results.isEmpty)
    }

    @Test("QBOReader parses deposits CSV from live VRAM data")
    func qboReaderDeposits() throws {
        let reader = QBOReader()
        let deposits = try reader.readDeposits()
        #expect(deposits.count > 0)
        #expect(deposits.allSatisfy { $0.source == "qbo" })
        #expect(deposits.allSatisfy { $0.amount > 0 })
    }
}
