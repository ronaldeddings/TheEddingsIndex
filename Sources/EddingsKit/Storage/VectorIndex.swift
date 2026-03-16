import Foundation
import USearch
import os

public actor VectorIndex {
    private var index512: USearchIndex
    private var index4096: USearchIndex?
    private var pendingIndex512: USearchIndex?
    private let directory: URL
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "vector")

    public init(directory: URL) throws {
        self.directory = directory
        let path512 = directory.appending(path: "reality-512.usearch").path

        #if os(iOS)
        index512 = try USearchIndex.make(
            metric: .cos,
            dimensions: 512,
            connectivity: 16,
            quantization: .i8
        )
        if FileManager.default.fileExists(atPath: path512) {
            try index512.view(path: path512)
        }
        pendingIndex512 = try USearchIndex.make(
            metric: .cos,
            dimensions: 512,
            connectivity: 16,
            quantization: .i8
        )
        index4096 = nil
        #else
        index512 = try USearchIndex.make(
            metric: .cos,
            dimensions: 512,
            connectivity: 16,
            quantization: .f32
        )
        if FileManager.default.fileExists(atPath: path512) {
            try index512.load(path: path512)
        }

        let idx4096 = try USearchIndex.make(
            metric: .cos,
            dimensions: 4096,
            connectivity: 16,
            quantization: .f32
        )
        let path4096 = directory.appending(path: "reality-4096.usearch").path
        if FileManager.default.fileExists(atPath: path4096) {
            try idx4096.load(path: path4096)
        }
        index4096 = idx4096
        #endif

        logger.info("VectorIndex loaded from \(directory.path)")
    }

    public init(inMemory: Bool) throws {
        self.directory = FileManager.default.temporaryDirectory
        index512 = try USearchIndex.make(
            metric: .cos,
            dimensions: 512,
            connectivity: 16,
            quantization: .f32
        )
        #if os(macOS)
        index4096 = try USearchIndex.make(
            metric: .cos,
            dimensions: 4096,
            connectivity: 16,
            quantization: .f32
        )
        #else
        index4096 = nil
        #endif
    }

    private var reserved4096: USearchKey = 0

    public func add4096(key: USearchKey, vector: [Float]) throws {
        #if os(macOS)
        guard let idx = index4096 else { return }
        if key >= reserved4096 {
            let newCap = max(key + 1, reserved4096 * 2)
            try idx.reserve(UInt32(newCap))
            reserved4096 = newCap
        }
        try idx.add(key: key, vector: vector)
        #endif
    }

    private var reserved512: USearchKey = 0

    public func add(key: USearchKey, vector512: [Float], vector4096: [Float]? = nil) throws {
        #if os(iOS)
        if let pending = pendingIndex512 {
            if key >= reserved512 {
                let newCap = max(key + 1, reserved512 * 2)
                try pending.reserve(UInt32(newCap))
                reserved512 = newCap
            }
            try pending.add(key: key, vector: vector512)
        }
        #else
        if key >= reserved512 {
            let newCap = max(key + 1, reserved512 * 2)
            try index512.reserve(UInt32(newCap))
            reserved512 = newCap
        }
        try index512.add(key: key, vector: vector512)
        if let v4096 = vector4096, let idx = index4096 {
            if key >= reserved4096 {
                let newCap = max(key + 1, reserved4096 * 2)
                try idx.reserve(UInt32(newCap))
                reserved4096 = newCap
            }
            try idx.add(key: key, vector: v4096)
        }
        #endif
    }

    public struct SearchHit: Sendable {
        public let key: USearchKey
        public let distance: Float
    }

    public func search(vector: [Float], count: Int = 20) throws -> [SearchHit] {
        #if os(iOS)
        var hits: [SearchHit] = []
        if try index512.count > 0 {
            let mainResults = try index512.search(vector: vector, count: count)
            hits.append(contentsOf: zip(mainResults.0, mainResults.1).map { SearchHit(key: $0.0, distance: $0.1) })
        }
        if let pending = pendingIndex512, try pending.count > 0 {
            let pendingResults = try pending.search(vector: vector, count: count)
            hits.append(contentsOf: zip(pendingResults.0, pendingResults.1).map { SearchHit(key: $0.0, distance: $0.1) })
        }
        return Array(hits.sorted { $0.distance < $1.distance }.prefix(count))
        #else
        if vector.count == 4096, let idx = index4096 {
            guard try idx.count > 0 else { return [] }
            let results = try idx.search(vector: vector, count: count)
            return zip(results.0, results.1).map { SearchHit(key: $0.0, distance: $0.1) }
        }
        guard try index512.count > 0 else { return [] }
        let results = try index512.search(vector: vector, count: count)
        return zip(results.0, results.1).map { SearchHit(key: $0.0, distance: $0.1) }
        #endif
    }

    public var count512: Int {
        get throws {
            #if os(iOS)
            try index512.count + (try pendingIndex512?.count ?? 0)
            #else
            try index512.count
            #endif
        }
    }

    public func save() throws {
        let gen = Int(Date().timeIntervalSince1970)

        #if os(iOS)
        let mergedIndex = try USearchIndex.make(
            metric: .cos,
            dimensions: 512,
            connectivity: 16,
            quantization: .i8
        )
        if try index512.count > 0 {
            let mainKeys = try index512.search(vector: [Float](repeating: 0, count: 512), count: try index512.count)
            for i in 0..<mainKeys.0.count {
                let key = mainKeys.0[i]
                guard let vecs = try index512.get(key: key), let vec = vecs.first else { continue }
                try mergedIndex.add(key: key, vector: vec)
            }
        }
        if let pending = pendingIndex512, try pending.count > 0 {
            let pendingKeys = try pending.search(vector: [Float](repeating: 0, count: 512), count: try pending.count)
            for i in 0..<pendingKeys.0.count {
                let key = pendingKeys.0[i]
                guard let vecs = try pending.get(key: key), let vec = vecs.first else { continue }
                try mergedIndex.add(key: key, vector: vec)
            }
        }

        let newPath512 = directory.appending(path: "reality-512-\(gen).usearch")
        try mergedIndex.save(path: newPath512.path)

        let viewedIndex = try USearchIndex.make(
            metric: .cos,
            dimensions: 512,
            connectivity: 16,
            quantization: .i8
        )
        try viewedIndex.view(path: newPath512.path)
        let oldPath = directory.appending(path: "reality-512.usearch")
        index512 = viewedIndex
        pendingIndex512 = try USearchIndex.make(
            metric: .cos,
            dimensions: 512,
            connectivity: 16,
            quantization: .i8
        )
        try? FileManager.default.removeItem(at: oldPath)
        try FileManager.default.moveItem(at: newPath512, to: oldPath)
        #else
        let newPath512 = directory.appending(path: "reality-512-\(gen).usearch")
        try index512.save(path: newPath512.path)
        let finalPath512 = directory.appending(path: "reality-512.usearch")
        _ = try FileManager.default.replaceItemAt(finalPath512, withItemAt: newPath512)
        #endif

        #if os(macOS)
        if let idx4096 = index4096 {
            let newPath4096 = directory.appending(path: "reality-4096-\(gen).usearch")
            try idx4096.save(path: newPath4096.path)
            let finalPath4096 = directory.appending(path: "reality-4096.usearch")
            _ = try FileManager.default.replaceItemAt(finalPath4096, withItemAt: newPath4096)
        }
        #endif

        excludeFromBackup(directory.appending(path: "reality-512.usearch"))
        excludeFromBackup(directory.appending(path: "reality-4096.usearch"))

        logger.info("VectorIndex saved (generation \(gen))")
    }

    private func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutableURL.setResourceValues(values)
        } catch {
            logger.debug("Failed to set isExcludedFromBackup on \(url.lastPathComponent): \(error)")
        }
    }
}
