import Foundation
import os

public struct CalDAVClient: Sendable {
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "caldav")

    public init() {}

    public func sync() throws -> Int {
        logger.info("CalDAV sync not yet implemented — Phase 5 stub")
        return 0
    }
}
