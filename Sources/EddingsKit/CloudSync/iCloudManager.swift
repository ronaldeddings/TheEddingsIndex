import Foundation
import CloudKit
import GRDB
import os

public actor iCloudManager {
    private var syncEngine: CKSyncEngine?
    private let dbPool: DatabasePool
    private let stateURL: URL
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "icloud")
    private let containerID = "iCloud.com.hackervalley.eddingsindex"
    private let zoneID = CKRecordZone.ID(zoneName: "EddingsData", ownerName: CKCurrentUserDefaultName)

    public init(dbPool: DatabasePool, stateDirectory: URL) {
        self.dbPool = dbPool
        self.stateURL = stateDirectory.appending(path: "ck-sync-state.dat")
    }

    public func start() throws {
        let container = CKContainer(identifier: self.containerID)
        let database = container.privateCloudDatabase

        let savedState: CKSyncEngine.State.Serialization?
        if let data = try? Data(contentsOf: stateURL) {
            savedState = try? JSONDecoder().decode(
                CKSyncEngine.State.Serialization.self, from: data
            )
        } else {
            savedState = nil
        }

        let delegate = SyncDelegate(manager: self)
        let config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: savedState,
            delegate: delegate
        )
        self.syncEngine = CKSyncEngine(config)
        logger.info("CKSyncEngine started with container \(self.containerID)")
    }

    public func schedulePendingChange(for recordID: CKRecord.ID) {
        guard let engine = syncEngine else { return }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    public func schedulePendingDeletion(for recordID: CKRecord.ID) {
        guard let engine = syncEngine else { return }
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
    }

    nonisolated func persistState(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            let dir = stateURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(serialization)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            logger.error("Failed to persist CKSyncEngine state: \(error)")
        }
    }

    nonisolated func handleFetchedChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        do {
            try dbPool.write { db in
                for modification in changes.modifications {
                    let record = modification.record
                    self.upsertRecord(record, into: db)
                }
                for deletion in changes.deletions {
                    self.deleteRecord(deletion.recordID, from: db)
                }
            }
            logger.info("Applied \(changes.modifications.count) modifications, \(changes.deletions.count) deletions from iCloud")
        } catch {
            logger.error("Failed to apply remote changes: \(error)")
        }
    }

    nonisolated func buildNextBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pendingChanges: [CKSyncEngine.PendingRecordZoneChange]
        switch scope {
        case .zoneIDs(let zoneIDs):
            pendingChanges = syncEngine.state.pendingRecordZoneChanges.filter { change in
                switch change {
                case .saveRecord(let id): return zoneIDs.contains(id.zoneID)
                case .deleteRecord(let id): return zoneIDs.contains(id.zoneID)
                @unknown default: return true
                }
            }
        default:
            pendingChanges = Array(syncEngine.state.pendingRecordZoneChanges)
        }

        guard !pendingChanges.isEmpty else { return nil }

        let pool = self.dbPool
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pendingChanges) { recordID in
            Self.buildCKRecord(for: recordID, dbPool: pool)
        }
    }

    nonisolated func handleSentChanges(_ sentChanges: CKSyncEngine.Event.SentRecordZoneChanges) {
        for failure in sentChanges.failedRecordSaves {
            switch failure.error.code {
            case .serverRecordChanged:
                if let serverRecord = failure.error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                    do {
                        try dbPool.write { db in
                            self.resolveConflict(
                                local: failure.record,
                                server: serverRecord,
                                in: db
                            )
                        }
                    } catch {
                        logger.error("Failed to resolve conflict for \(failure.record.recordID): \(error)")
                    }
                }
            default:
                logger.error("Failed to save record \(failure.record.recordID): \(failure.error)")
            }
        }

        if !sentChanges.savedRecords.isEmpty {
            logger.info("Successfully sent \(sentChanges.savedRecords.count) records to iCloud")
        }
        if !sentChanges.failedRecordSaves.isEmpty {
            logger.warning("\(sentChanges.failedRecordSaves.count) records failed to save")
        }
    }

    nonisolated func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signOut:
            logger.warning("iCloud account signed out — pausing sync")
        case .switchAccounts:
            logger.warning("iCloud account switched — clearing local sync state")
            try? FileManager.default.removeItem(at: stateURL)
        case .signIn:
            logger.info("iCloud account signed in")
        @unknown default:
            logger.warning("Unknown iCloud account change type")
        }
    }

    // MARK: - Record Mapping

    private static let syncableRecordTypes: Set<String> = [
        "Contact", "Company", "FinancialTransaction", "FinancialSnapshot",
        "Meeting", "MonthlySummary"
    ]

    private nonisolated func upsertRecord(_ record: CKRecord, into db: Database) {
        let recordType = record.recordType
        switch recordType {
        case "Contact":
            upsertContact(record, into: db)
        case "Company":
            upsertCompany(record, into: db)
        case "FinancialTransaction":
            upsertTransaction(record, into: db)
        case "FinancialSnapshot":
            upsertSnapshot(record, into: db)
        default:
            logger.info("Skipping unknown record type: \(recordType)")
        }
    }

    private nonisolated func deleteRecord(_ recordID: CKRecord.ID, from db: Database) {
        let parts = recordID.recordName.split(separator: "/")
        guard parts.count == 2,
              let id = Int64(parts[1]) else { return }
        let table = String(parts[0])

        switch table {
        case "contacts":
            _ = try? db.execute(sql: "DELETE FROM contacts WHERE id = ?", arguments: [id])
        case "companies":
            _ = try? db.execute(sql: "DELETE FROM companies WHERE id = ?", arguments: [id])
        case "financialTransactions":
            _ = try? db.execute(sql: "DELETE FROM financialTransactions WHERE id = ?", arguments: [id])
        case "financialSnapshots":
            _ = try? db.execute(sql: "DELETE FROM financialSnapshots WHERE id = ?", arguments: [id])
        default:
            break
        }
    }

    private static func buildCKRecord(for recordID: CKRecord.ID, dbPool: DatabasePool) -> CKRecord? {
        let parts = recordID.recordName.split(separator: "/")
        guard parts.count == 2,
              let id = Int64(parts[1]) else { return nil }
        let table = String(parts[0])

        return try? dbPool.read { db in
            switch table {
            case "contacts":
                guard let contact = try? Contact.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "Contact", recordID: recordID)
                record["name"] = contact.name
                record["email"] = contact.email
                record["role"] = contact.role
                record["emailCount"] = contact.emailCount
                record["meetingCount"] = contact.meetingCount
                record["slackCount"] = contact.slackCount
                return record
            case "companies":
                guard let company = try? Company.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "Company", recordID: recordID)
                record["name"] = company.name
                record["domain"] = company.domain
                return record
            case "financialTransactions":
                guard let txn = try? FinancialTransaction.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "FinancialTransaction", recordID: recordID)
                record["transactionId"] = txn.transactionId
                record["source"] = txn.source
                record["accountId"] = txn.accountId
                record["amount"] = txn.amount
                record["payee"] = txn.payee
                record["category"] = txn.category
                record["transactionDate"] = txn.transactionDate
                record["categoryModifiedAt"] = txn.categoryModifiedAt
                return record
            default:
                return nil
            }
        }
    }

    private nonisolated func upsertContact(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        var contact = (try? Contact.fetchOne(db, key: id)) ?? Contact(
            name: record["name"] as? String ?? "Unknown"
        )
        contact.id = id
        contact.name = record["name"] as? String ?? contact.name
        contact.email = record["email"] as? String ?? contact.email
        contact.role = record["role"] as? String ?? contact.role
        contact.emailCount = record["emailCount"] as? Int ?? contact.emailCount
        contact.meetingCount = record["meetingCount"] as? Int ?? contact.meetingCount
        contact.slackCount = record["slackCount"] as? Int ?? contact.slackCount
        try? contact.save(db)
    }

    private nonisolated func upsertCompany(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        var company = (try? Company.fetchOne(db, key: id)) ?? Company(
            name: record["name"] as? String ?? "Unknown"
        )
        company.id = id
        company.name = record["name"] as? String ?? company.name
        company.domain = record["domain"] as? String ?? company.domain
        try? company.save(db)
    }

    private nonisolated func upsertTransaction(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        if var existing = try? FinancialTransaction.fetchOne(db, key: id) {
            let remoteModified = record["categoryModifiedAt"] as? Date
            let localModified = existing.categoryModifiedAt

            if let remote = remoteModified, let local = localModified {
                if remote > local {
                    existing.category = record["category"] as? String ?? existing.category
                    existing.categoryModifiedAt = remote
                }
            } else if remoteModified != nil {
                existing.category = record["category"] as? String ?? existing.category
                existing.categoryModifiedAt = remoteModified
            }

            existing.payee = record["payee"] as? String ?? existing.payee
            try? existing.update(db)
        }
    }

    private nonisolated func upsertSnapshot(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        var snapshot = (try? FinancialSnapshot.fetchOne(db, key: id)) ?? FinancialSnapshot(
            snapshotDate: record["snapshotDate"] as? Date ?? Date(),
            accountId: record["accountId"] as? String ?? "",
            balance: record["balance"] as? Double ?? 0,
            source: record["source"] as? String ?? "icloud"
        )
        snapshot.id = id
        snapshot.balance = record["balance"] as? Double ?? snapshot.balance
        snapshot.accountName = record["accountName"] as? String ?? snapshot.accountName
        try? snapshot.save(db)
    }

    private nonisolated func resolveConflict(local: CKRecord, server: CKRecord, in db: Database) {
        if local.recordType == "FinancialTransaction" {
            let localModified = local["categoryModifiedAt"] as? Date ?? .distantPast
            let serverModified = server["categoryModifiedAt"] as? Date ?? .distantPast

            if localModified > serverModified {
                server["category"] = local["category"]
                server["categoryModifiedAt"] = local["categoryModifiedAt"]
            }
        }

        upsertRecord(server, into: db)
    }
}

final class SyncDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    private let manager: iCloudManager

    init(manager: iCloudManager) {
        self.manager = manager
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let stateUpdate):
            manager.persistState(stateUpdate.stateSerialization)

        case .accountChange(let accountChange):
            manager.handleAccountChange(accountChange)

        case .fetchedRecordZoneChanges(let changes):
            manager.handleFetchedChanges(changes)

        case .sentRecordZoneChanges(let sentChanges):
            manager.handleSentChanges(sentChanges)

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await manager.buildNextBatch(context, syncEngine: syncEngine)
    }
}
