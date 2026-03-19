import Foundation
import GRDB
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

public actor FinanceSyncPipeline {
    private let dbManager: DatabaseManager
    private let simpleFinClient: SimpleFinClient
    private let qboReader: QBOReader
    private let normalizer: Normalizer
    private let deduplicator: Deduplicator
    private let categorizer: Categorizer
    private let freedomTracker: FreedomTracker
    private let vramWriter: VRAMWriter
    private let stateManager: StateManager
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "finance-sync")

    public init(
        dbManager: DatabaseManager,
        stateManager: StateManager,
        merchantMap: MerchantMap
    ) {
        self.dbManager = dbManager
        self.simpleFinClient = SimpleFinClient()
        self.qboReader = QBOReader()
        self.normalizer = Normalizer()
        self.deduplicator = Deduplicator()
        self.categorizer = Categorizer(merchantMap: merchantMap)
        self.freedomTracker = FreedomTracker()
        self.vramWriter = VRAMWriter()
        self.stateManager = stateManager
    }

    public struct SyncResult: Sendable {
        public let accountCount: Int
        public let newTransactions: Int
        public let categorized: Int
        public let uncategorized: Int
        public let freedomVelocityPercent: Double
    }

    public func run() async throws -> SyncResult {
        logger.info("Starting finance sync pipeline")

        let simpleFinState = await stateManager.sourceState(for: "simplefin")
        let startDate: Date
        if let lastSync = simpleFinState.lastSyncAt {
            startDate = deduplicator.overlapStartDate(lastSync: lastSync)
        } else {
            startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        }

        let response = try await simpleFinClient.fetchAccounts(startDate: startDate)

        let snapshots = normalizer.normalizeAccounts(response.accounts)
        var transactions = normalizer.normalizeTransactions(response.accounts)
        normalizer.detectTransfers(&transactions)

        let qboTransactions = try qboReader.readAll()
        transactions.append(contentsOf: qboTransactions)

        transactions = transactions.filter { $0.transactionDate >= DataPolicy.cutoffDate }

        let seenIds = await stateManager.seenTransactionIds
        let dedupResult = deduplicator.deduplicate(transactions, seenIds: seenIds)
        await stateManager.updateSeenIds(dedupResult.updatedSeenIds)


        let catResult = await categorizer.categorize(dedupResult.new)

        try insertIntoDatabase(snapshots: snapshots, transactions: catResult.categorized + catResult.uncategorized)

        if vramWriter.isVRAMMounted {
            try vramWriter.writeSnapshot(snapshots)
            try vramWriter.appendTransactions(catResult.categorized + catResult.uncategorized)
        }

        let twelveWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date()) ?? Date()
        let historicalTransactions = try await dbManager.dbPool.read { db in
            try FinancialTransaction
                .filter(Column("transactionDate") >= twelveWeeksAgo)
                .fetchAll(db)
        }
        let historicalSnapshots = try await dbManager.dbPool.read { db in
            try FinancialSnapshot.fetchAll(db)
        }
        let freedomScore = freedomTracker.calculate(
            snapshots: historicalSnapshots,
            transactions: historicalTransactions
        )

        let previousNetWorth = try await dbManager.dbPool.read { db -> Double? in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT netWorth FROM widgetSnapshots ORDER BY date DESC LIMIT 1"
            )
            return row?["netWorth"] as? Double
        }
        let currentNetWorth = freedomScore.netWorth ?? 0
        let dailyChange = previousNetWorth.map { currentNetWorth - $0 } ?? 0

        try await dbManager.dbPool.write { db in
            var widgetSnap = WidgetSnapshot(
                weeklyAmount: freedomScore.weeklyNonW2TakeHome,
                weeklyTarget: freedomScore.weeklyTarget,
                velocityPercent: freedomScore.velocityPercent,
                netWorth: currentNetWorth,
                dailyChange: dailyChange
            )
            try widgetSnap.insert(db)
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif

        await stateManager.updateSource(
            "simplefin",
            status: .success,
            recordsSynced: dedupResult.new.count
        )

        await stateManager.updateSource(
            "qbo",
            status: .success,
            recordsSynced: qboTransactions.count
        )

        logger.info("Finance sync complete: \(dedupResult.new.count) new transactions, Freedom Velocity \(String(format: "%.0f", freedomScore.velocityPercent))%")

        return SyncResult(
            accountCount: response.accounts.count,
            newTransactions: dedupResult.new.count,
            categorized: catResult.categorized.count,
            uncategorized: catResult.uncategorized.count,
            freedomVelocityPercent: freedomScore.velocityPercent
        )
    }

    private func insertIntoDatabase(snapshots: [FinancialSnapshot], transactions: [FinancialTransaction]) throws {
        try dbManager.dbPool.write { db in
            for var snapshot in snapshots {
                try snapshot.upsert(db)
            }
        }

        let batchSize = 100
        for batch in stride(from: 0, to: transactions.count, by: batchSize) {
            let end = min(batch + batchSize, transactions.count)
            try dbManager.dbPool.write { db in
                for i in batch..<end {
                    var txn = transactions[i]
                    try txn.upsert(db)
                }
            }
        }
    }
}

extension FinancialSnapshot {
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace
    )
}

