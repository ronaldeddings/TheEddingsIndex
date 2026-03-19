import Foundation
import GRDB
import os

public struct FileScanner: Sendable {
    private let dbPool: DatabasePool
    private let basePath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "filescan")

    private let scanAreas = [
        "10-19_Work", "20-29_Finance", "30-39_Personal",
        "40-49_Family", "50-59_Social", "60-69_Growth",
        "70-79_Lifestyle"
    ]

    private let indexableExtensions: Set<String> = ["md", "txt", "csv", "yml", "yaml", "toml"]

    public init(dbPool: DatabasePool, basePath: String = "/Volumes/VRAM") {
        self.dbPool = dbPool
        self.basePath = basePath
    }

    public func scan() throws -> Int {
        guard FileManager.default.fileExists(atPath: basePath) else {
            logger.error("VRAM not mounted at \(basePath)")
            return 0
        }

        var newCount = 0
        let existingPaths = try getExistingPaths()

        for area in scanAreas {
            let areaPath = "\(basePath)/\(area)"
            guard FileManager.default.fileExists(atPath: areaPath) else { continue }

            let files = try findIndexableFiles(in: areaPath)
            logger.info("Found \(files.count) indexable files in \(area)")

            for file in files {
                if existingPaths.contains(file.path) { continue }
                if let modified = file.modifiedDate, modified < DataPolicy.cutoffDate { continue }

                let content = try? String(contentsOfFile: file.path, encoding: .utf8)
                guard let content, !content.isEmpty else { continue }

                let jd = extractJohnnyDecimal(from: file.path)

                try dbPool.write { db in
                    var doc = Document(
                        path: file.path,
                        filename: file.lastPathComponent,
                        content: content,
                        extension: file.pathExtension,
                        fileSize: Int64(content.utf8.count),
                        modifiedAt: file.modifiedDate,
                        area: jd.area,
                        category: jd.category,
                        contentType: "file",
                        createdAt: file.createdDate,
                        indexedAt: Date()
                    )
                    try doc.insert(db)
                }
                newCount += 1
            }
        }

        logger.info("FileScanner indexed \(newCount) new files")
        return newCount
    }

    private func findIndexableFiles(in directory: String) throws -> [FileInfo] {
        var results: [FileInfo] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: URL(filePath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey]),
                  values.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            guard indexableExtensions.contains(ext) else { continue }

            let size = (try? fm.attributesOfItem(atPath: url.path())[.size] as? Int) ?? 0
            guard size < 1_000_000 else { continue }

            results.append(FileInfo(
                path: url.path(),
                lastPathComponent: url.lastPathComponent,
                pathExtension: ext,
                modifiedDate: values.contentModificationDate,
                createdDate: values.creationDate
            ))
        }

        return results
    }

    private func getExistingPaths() throws -> Set<String> {
        try dbPool.read { db in
            let paths = try String.fetchAll(db, sql: "SELECT path FROM documents")
            return Set(paths)
        }
    }

    private func extractJohnnyDecimal(from path: String) -> (area: String?, category: String?) {
        let components = path.replacingOccurrences(of: basePath + "/", with: "").split(separator: "/")
        guard let first = components.first else { return (nil, nil) }

        let area = String(first)
        let category = components.count > 1 ? String(components[1]) : nil
        return (area, category)
    }

    struct FileInfo: Sendable {
        let path: String
        let lastPathComponent: String
        let pathExtension: String
        let modifiedDate: Date?
        let createdDate: Date?
    }
}
