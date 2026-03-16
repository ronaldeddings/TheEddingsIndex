#if os(iOS)
import BackgroundTasks
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
        try? BGTaskScheduler.shared.submit(request)
    }

    public static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: syncIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()

        let operation = Task {
            logger.info("Background refresh starting")
            // TODO: Implement quick transaction check
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }

    private static func handleProcessing(_ task: BGProcessingTask) {
        scheduleProcessing()

        let operation = Task {
            logger.info("Background processing starting")
            // TODO: Implement full sync with checkpointing
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            operation.cancel()
        }
    }
}
#endif
