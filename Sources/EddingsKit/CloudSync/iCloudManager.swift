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

    public func start() async throws {
        let container = CKContainer(identifier: self.containerID)
        let database = container.privateCloudDatabase

        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await database.recordZone(for: zoneID)
            logger.info("Zone \(self.zoneID.zoneName) exists")
        } catch let error as CKError where error.code == .zoneNotFound {
            _ = try await database.save(zone)
            logger.info("Created zone \(self.zoneID.zoneName)")
        }

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

        let batchLimit = 400
        let batchChanges = Array(pendingChanges.prefix(batchLimit))
        if pendingChanges.count > batchLimit {
            logger.info("Batching \(batchChanges.count) of \(pendingChanges.count) pending changes")
        }

        let pool = self.dbPool
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batchChanges) { recordID in
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
            logger.warning("iCloud account switched — flushing pending writes before clearing state")
            do {
                try dbPool.write { db in
                    try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
                }
                logger.info("WAL checkpoint completed before account switch")
            } catch {
                logger.error("Failed to flush WAL before account switch: \(error)")
            }
            try? FileManager.default.removeItem(at: stateURL)
            logger.info("Sync state cleared for new account")
        case .signIn:
            logger.info("iCloud account signed in")
        @unknown default:
            logger.warning("Unknown iCloud account change type")
        }
    }

    // MARK: - Record Mapping

    private static let syncableRecordTypes: Set<String> = [
        "Contact", "Company", "FinancialTransaction", "FinancialSnapshot",
        "Meeting", "MonthlySummary", "MeetingParticipant",
        "TranscriptChunk", "EmailChunk", "SlackChunk"
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
        case "TranscriptChunk":
            upsertTranscriptChunk(record, into: db)
        case "EmailChunk":
            upsertEmailChunk(record, into: db)
        case "SlackChunk":
            upsertSlackChunk(record, into: db)
        case "Meeting":
            upsertMeeting(record, into: db)
        case "MeetingParticipant":
            upsertMeetingParticipant(record, into: db)
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
        case "transcriptChunks":
            _ = try? db.execute(sql: "DELETE FROM transcriptChunks WHERE id = ?", arguments: [id])
        case "emailChunks":
            _ = try? db.execute(sql: "DELETE FROM emailChunks WHERE id = ?", arguments: [id])
        case "slackChunks":
            _ = try? db.execute(sql: "DELETE FROM slackChunks WHERE id = ?", arguments: [id])
        case "meetings":
            _ = try? db.execute(sql: "DELETE FROM meetings WHERE id = ?", arguments: [id])
        case "meetingParticipants":
            _ = try? db.execute(sql: "DELETE FROM meetingParticipants WHERE id = ?", arguments: [id])
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
            case "transcriptChunks":
                guard let chunk = try? TranscriptChunk.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "TranscriptChunk", recordID: recordID)
                record["filePath"] = chunk.filePath
                record["chunkIndex"] = chunk.chunkIndex
                record["speakerName"] = chunk.speakerName
                record["speakers"] = chunk.speakers
                record["meetingId"] = chunk.meetingId
                record["year"] = chunk.year
                record["month"] = chunk.month
                record["quarter"] = chunk.quarter
                record["startTime"] = chunk.startTime
                record["endTime"] = chunk.endTime
                attachContentAsAssetIfNeeded(record: record, field: "chunkText", text: chunk.chunkText)
                return record
            case "emailChunks":
                guard let email = try? EmailChunk.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "EmailChunk", recordID: recordID)
                record["emailId"] = email.emailId
                record["subject"] = email.subject
                record["fromName"] = email.fromName
                record["fromEmail"] = email.fromEmail
                record["chunkIndex"] = email.chunkIndex
                record["year"] = email.year
                record["month"] = email.month
                record["quarter"] = email.quarter
                record["isSentByMe"] = email.isSentByMe
                record["hasAttachments"] = email.hasAttachments
                attachContentAsAssetIfNeeded(record: record, field: "chunkText", text: email.chunkText)
                return record
            case "slackChunks":
                guard let slack = try? SlackChunk.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "SlackChunk", recordID: recordID)
                record["channel"] = slack.channel
                record["speakers"] = slack.speakers
                record["messageDate"] = slack.messageDate
                record["year"] = slack.year
                record["month"] = slack.month
                record["quarter"] = slack.quarter
                record["chunkIndex"] = slack.chunkIndex
                attachContentAsAssetIfNeeded(record: record, field: "chunkText", text: slack.chunkText)
                return record
            case "meetings":
                guard let meeting = try? Meeting.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "Meeting", recordID: recordID)
                record["meetingId"] = meeting.meetingId
                record["title"] = meeting.title
                record["startTime"] = meeting.startTime
                record["year"] = meeting.year
                record["month"] = meeting.month
                record["quarter"] = meeting.quarter
                record["isInternal"] = meeting.isInternal
                record["filePath"] = meeting.filePath
                return record
            case "meetingParticipants":
                guard let mp = try? MeetingParticipant.fetchOne(db, key: id) else { return nil }
                let record = CKRecord(recordType: "MeetingParticipant", recordID: recordID)
                record["meetingId"] = mp.meetingId
                record["contactId"] = mp.contactId
                record["role"] = mp.role
                return record
            default:
                return nil
            }
        }
    }

    private static func attachContentAsAssetIfNeeded(record: CKRecord, field: String, text: String?) {
        guard let text, !text.isEmpty else { return }
        if text.utf8.count < 50_000 {
            record[field] = text
        } else {
            let tempURL = FileManager.default.temporaryDirectory
                .appending(path: "ck-asset-\(UUID().uuidString).txt")
            try? text.write(to: tempURL, atomically: true, encoding: .utf8)
            record["\(field)Asset"] = CKAsset(fileURL: tempURL)
        }
    }

    private static func readContentFromAssetOrInline(record: CKRecord, field: String) -> String? {
        if let asset = record["\(field)Asset"] as? CKAsset,
           let url = asset.fileURL {
            let appContainer = FileManager.default.temporaryDirectory
                .appending(path: "ck-fetched-\(UUID().uuidString).txt")
            try? FileManager.default.copyItem(at: url, to: appContainer)
            return try? String(contentsOf: appContainer, encoding: .utf8)
        }
        return record[field] as? String
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

    private nonisolated func upsertTranscriptChunk(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        let text = Self.readContentFromAssetOrInline(record: record, field: "chunkText")

        var chunk = (try? TranscriptChunk.fetchOne(db, key: id)) ?? TranscriptChunk(
            filePath: record["filePath"] as? String,
            chunkText: text,
            chunkIndex: record["chunkIndex"] as? Int,
            speakers: record["speakers"] as? String,
            speakerName: record["speakerName"] as? String,
            meetingId: record["meetingId"] as? String,
            year: record["year"] as? Int,
            month: record["month"] as? Int,
            quarter: record["quarter"] as? Int,
            startTime: record["startTime"] as? String,
            endTime: record["endTime"] as? String
        )
        chunk.id = id
        chunk.chunkText = text ?? chunk.chunkText
        try? chunk.save(db)
    }

    private nonisolated func upsertEmailChunk(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        let text = Self.readContentFromAssetOrInline(record: record, field: "chunkText")

        var chunk = (try? EmailChunk.fetchOne(db, key: id)) ?? EmailChunk(
            emailId: record["emailId"] as? String ?? "unknown"
        )
        chunk.id = id
        chunk.subject = record["subject"] as? String ?? chunk.subject
        chunk.fromName = record["fromName"] as? String ?? chunk.fromName
        chunk.fromEmail = record["fromEmail"] as? String ?? chunk.fromEmail
        chunk.chunkText = text ?? chunk.chunkText
        chunk.chunkIndex = record["chunkIndex"] as? Int ?? chunk.chunkIndex
        chunk.year = record["year"] as? Int ?? chunk.year
        chunk.month = record["month"] as? Int ?? chunk.month
        chunk.quarter = record["quarter"] as? Int ?? chunk.quarter
        chunk.isSentByMe = record["isSentByMe"] as? Bool ?? chunk.isSentByMe
        chunk.hasAttachments = record["hasAttachments"] as? Bool ?? chunk.hasAttachments
        try? chunk.save(db)
    }

    private nonisolated func upsertSlackChunk(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        let text = Self.readContentFromAssetOrInline(record: record, field: "chunkText")

        var chunk = (try? SlackChunk.fetchOne(db, key: id)) ?? SlackChunk(
            channel: record["channel"] as? String
        )
        chunk.id = id
        chunk.speakers = record["speakers"] as? String ?? chunk.speakers
        chunk.chunkText = text ?? chunk.chunkText
        chunk.messageDate = record["messageDate"] as? Date ?? chunk.messageDate
        chunk.year = record["year"] as? Int ?? chunk.year
        chunk.month = record["month"] as? Int ?? chunk.month
        chunk.quarter = record["quarter"] as? Int ?? chunk.quarter
        chunk.chunkIndex = record["chunkIndex"] as? Int ?? chunk.chunkIndex
        try? chunk.save(db)
    }

    private nonisolated func upsertMeeting(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        var meeting = (try? Meeting.fetchOne(db, key: id)) ?? Meeting(
            meetingId: record["meetingId"] as? String ?? "unknown"
        )
        meeting.id = id
        meeting.title = record["title"] as? String ?? meeting.title
        meeting.startTime = record["startTime"] as? Date ?? meeting.startTime
        meeting.year = record["year"] as? Int ?? meeting.year
        meeting.month = record["month"] as? Int ?? meeting.month
        meeting.quarter = record["quarter"] as? Int ?? meeting.quarter
        meeting.isInternal = record["isInternal"] as? Bool ?? meeting.isInternal
        meeting.filePath = record["filePath"] as? String ?? meeting.filePath
        try? meeting.save(db)
    }

    private nonisolated func upsertMeetingParticipant(_ record: CKRecord, into db: Database) {
        let parts = record.recordID.recordName.split(separator: "/")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }

        var mp = (try? MeetingParticipant.fetchOne(db, key: id)) ?? MeetingParticipant(
            meetingId: record["meetingId"] as? Int64 ?? 0,
            contactId: record["contactId"] as? Int64 ?? 0
        )
        mp.id = id
        mp.role = record["role"] as? String ?? mp.role
        try? mp.save(db)
    }

    private nonisolated func resolveConflict(local: CKRecord, server: CKRecord, in db: Database) {
        if local.recordType == "FinancialTransaction" {
            let localModified = local["categoryModifiedAt"] as? Date ?? .distantPast
            let serverModified = server["categoryModifiedAt"] as? Date ?? .distantPast

            if localModified > serverModified {
                server["category"] = local["category"]
                server["categoryModifiedAt"] = local["categoryModifiedAt"]
                logger.info("Conflict resolved: local category wins for \(local.recordID)")
            } else {
                logger.info("Conflict resolved: server category wins for \(local.recordID)")
            }
        } else {
            logger.info("Conflict resolved: last-write-wins (server) for \(local.recordType)/\(local.recordID)")
        }

        upsertRecord(server, into: db)
    }

    nonisolated func cleanupTempFiles(for savedRecords: [CKRecord]) {
        for record in savedRecords {
            for key in record.allKeys() {
                if let asset = record[key] as? CKAsset, let url = asset.fileURL {
                    if url.path.contains("ck-asset-") {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }
}

final class SyncDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    private let manager: iCloudManager
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "ck-delegate")

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
            manager.cleanupTempFiles(for: sentChanges.savedRecords)

        case .willFetchChanges:
            logger.info("Will fetch changes from iCloud")

        case .didFetchChanges:
            logger.info("Did fetch changes from iCloud")

        case .willFetchRecordZoneChanges:
            logger.debug("Will fetch record zone changes")

        case .didFetchRecordZoneChanges(let zoneChanges):
            logger.debug("Did fetch record zone changes for zone \(zoneChanges.zoneID.zoneName)")

        case .willSendChanges:
            logger.debug("Will send changes to iCloud")

        case .didSendChanges:
            logger.debug("Did send changes to iCloud")

        case .fetchedDatabaseChanges(let dbChanges):
            logger.info("Fetched database changes: \(dbChanges.modifications.count) mods, \(dbChanges.deletions.count) deletes")

        case .sentDatabaseChanges:
            logger.debug("Sent database changes")

        @unknown default:
            logger.debug("Unknown CKSyncEngine event")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await manager.buildNextBatch(context, syncEngine: syncEngine)
    }
}
