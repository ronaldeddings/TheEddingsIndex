import Foundation
import os

public struct VRAMWriter: Sendable {
    private let basePath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "vram")

    public init(basePath: String = "/Volumes/VRAM/20-29_Finance") {
        self.basePath = basePath
    }

    public var isVRAMMounted: Bool {
        FileManager.default.fileExists(atPath: "/Volumes/VRAM")
    }

    public func writeSnapshot(_ snapshots: [FinancialSnapshot], date: Date = Date()) throws {
        guard isVRAMMounted else {
            logger.error("VRAM not mounted — skipping snapshot write")
            throw VRAMError.notMounted
        }

        let dateStr = Self.dateFormatter.string(from: date)
        let dir = "\(basePath)/20_Banking/snapshots"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let path = "\(dir)/\(dateStr).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshots)
        try data.write(to: URL(filePath: path), options: .atomic)

        logger.info("Wrote snapshot to \(path) (\(snapshots.count) accounts)")
    }

    public func appendTransactions(_ transactions: [FinancialTransaction]) throws {
        guard isVRAMMounted else {
            logger.error("VRAM not mounted — skipping transaction write")
            throw VRAMError.notMounted
        }

        let calendar = Calendar.current
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var grouped: [String: [FinancialTransaction]] = [:]
        for txn in transactions {
            let components = calendar.dateComponents([.year, .month], from: txn.transactionDate)
            let yearMonth = String(format: "%04d-%02d", components.year ?? 2026, components.month ?? 1)
            let slug = accountSlug(txn.accountName ?? txn.accountId)
            let key = "\(yearMonth)/\(slug)"
            grouped[key, default: []].append(txn)
        }

        for (key, txns) in grouped {
            let dir = "\(basePath)/20_Banking/transactions/\(key.split(separator: "/").first ?? "")"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            let filename = String(key.split(separator: "/").last ?? "unknown")
            let path = "\(dir)/\(filename).jsonl"
            let fileURL = URL(filePath: path)

            var lines = ""
            for txn in txns {
                let jsonData = try encoder.encode(txn)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    lines += jsonString + "\n"
                }
            }

            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                if let data = lines.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try lines.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            logger.info("Wrote \(txns.count) transactions to \(path)")
        }
    }

    public func writeCategorizedSummary(_ summary: MonthlySummary) throws {
        guard isVRAMMounted else { throw VRAMError.notMounted }

        let dir = "\(basePath)/20_Banking/categorized"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let path = "\(dir)/\(summary.month).json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        try data.write(to: URL(filePath: path), options: .atomic)

        logger.info("Wrote categorized summary for \(summary.month)")
    }

    private func accountSlug(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: #"[^a-z0-9\-]"#, with: "", options: .regularExpression)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public enum VRAMError: Error, Sendable {
        case notMounted
    }
}
