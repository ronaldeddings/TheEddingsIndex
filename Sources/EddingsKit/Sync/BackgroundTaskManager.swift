#if os(iOS)
import BackgroundTasks
import GRDB
import os

public struct BackgroundTaskManager {
    private static let refreshIdentifier = "com.hackervalley.eddingsindex.refresh"
    private static let syncIdentifier = "com.hackervalley.eddingsindex.sync"
    private static let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "background")

    public static func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            handleRefresh(task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncIdentifier, using: nil) { task in
            handleProcessing(task as! BGProcessingTask)
        }
    }

    public static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch let error as BGTaskScheduler.Error {
            switch error.code {
            case .tooManyPendingTaskRequests:
                logger.warning("Too many pending refresh requests")
            case .notPermitted:
                logger.error("Background refresh not permitted — check UIBackgroundModes")
            case .unavailable:
                logger.warning("Background refresh unavailable on this device")
            @unknown default:
                logger.error("Failed to schedule refresh: \(error)")
            }
        } catch {
            logger.error("Failed to schedule refresh: \(error)")
        }
    }

    public static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: syncIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch let error as BGTaskScheduler.Error {
            switch error.code {
            case .tooManyPendingTaskRequests:
                logger.warning("Too many pending processing requests")
            case .notPermitted:
                logger.error("Background processing not permitted — check UIBackgroundModes")
            case .unavailable:
                logger.warning("Background processing unavailable on this device")
            @unknown default:
                logger.error("Failed to schedule processing: \(error)")
            }
        } catch {
            logger.error("Failed to schedule processing: \(error)")
        }
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        let operation = Task {
            logger.info("Background refresh starting — quick finance sync")
            var success = false
            do {
                if let dbPath = DatabaseManager.sharedDatabasePath {
                    let dbManager = try DatabaseManager(path: dbPath)
                    let stateDir = URL(filePath: dbPath).deletingLastPathComponent().appending(path: "state")
                    let stateManager = StateManager(directory: stateDir)
                    let merchantMap = MerchantMap()
                    let pipeline = FinanceSyncPipeline(
                        dbManager: dbManager,
                        stateManager: stateManager,
                        merchantMap: merchantMap
                    )
                    let result = try await pipeline.run()
                    logger.info("Background refresh: \(result.newTransactions) new transactions, velocity \(String(format: "%.0f", result.freedomVelocityPercent))%")
                    success = true
                }
            } catch {
                logger.error("Background refresh failed: \(error)")
            }
            task.setTaskCompleted(success: success)
            scheduleRefresh()
        }

        task.expirationHandler = {
            operation.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private static func handleProcessing(_ task: BGProcessingTask) {
        let operation = Task {
            logger.info("Background processing starting — full sync + embedding")
            var success = false
            do {
                if let dbPath = DatabaseManager.sharedDatabasePath {
                    let dbManager = try DatabaseManager(path: dbPath)
                    let dbDir = URL(filePath: dbPath).deletingLastPathComponent()
                    let stateDir = dbDir.appending(path: "state")
                    let stateManager = StateManager(directory: stateDir)
                    let merchantMap = MerchantMap()

                    let pipeline = FinanceSyncPipeline(
                        dbManager: dbManager,
                        stateManager: stateManager,
                        merchantMap: merchantMap
                    )
                    _ = try await pipeline.run()

                    guard !Task.isCancelled else {
                        logger.info("Processing cancelled after finance sync")
                        task.setTaskCompleted(success: false)
                        return
                    }

                    let vectorDir = dbDir.appending(path: "vectors")
                    try FileManager.default.createDirectory(at: vectorDir, withIntermediateDirectories: true)
                    let vectorIndex = try VectorIndex(directory: vectorDir)
                    let embedPipeline = EmbeddingPipeline(dbPool: dbManager.dbPool, vectorIndex: vectorIndex)
                    let stats = try await embedPipeline.run()
                    logger.info("Background processing: embedded \(stats.totalEmbedded) new records")

                    success = true
                }
            } catch {
                logger.error("Background processing failed: \(error)")
            }
            task.setTaskCompleted(success: success)
            scheduleProcessing()
        }

        task.expirationHandler = {
            operation.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
