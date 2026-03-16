import Foundation
import os

public actor MerchantMap {
    private var map: [String: CategoryMapping] = [:]
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "merchant")

    public struct CategoryMapping: Codable, Sendable {
        public let category: String
        public let subcategory: String?
        public let code: String?
    }

    public init() {
        let defaults: [(String, String, String?)] = [
            ("spotify", "Lifestyle", "Entertainment Streaming"),
            ("hulu", "Lifestyle", "Entertainment Streaming"),
            ("netflix", "Lifestyle", "Entertainment Streaming"),
            ("disney+", "Lifestyle", "Entertainment Streaming"),
            ("hbo", "Lifestyle", "Entertainment Streaming"),
            ("audible", "Lifestyle", "Entertainment Streaming"),
            ("kindle", "Lifestyle", "Entertainment Streaming"),
            ("discord", "Lifestyle", "Entertainment Streaming"),
            ("doordash", "Lifestyle", "Dining & Delivery"),
            ("uber eats", "Lifestyle", "Dining & Delivery"),
            ("grubhub", "Lifestyle", "Dining & Delivery"),
            ("mcdonald", "Lifestyle", "Dining & Delivery"),
            ("starbucks", "Lifestyle", "Dining & Delivery"),
            ("chick-fil-a", "Lifestyle", "Dining & Delivery"),
            ("whataburger", "Lifestyle", "Dining & Delivery"),
            ("chipotle", "Lifestyle", "Dining & Delivery"),
            ("h-e-b", "Household", "Groceries"),
            ("heb", "Household", "Groceries"),
            ("costco", "Household", "Groceries"),
            ("walmart", "Household", "Groceries"),
            ("target", "Household", "Groceries"),
            ("amazon", "Lifestyle", "Shopping & Personal"),
            ("apple.com", "True Expenses", "Technology Replacement"),
            ("shell", "Household", "Transportation"),
            ("exxon", "Household", "Transportation"),
            ("chevron", "Household", "Transportation"),
            ("valero", "Household", "Transportation"),
            ("ymca", "Lifestyle", "Wellness & Fitness"),
            ("claude", "Lifestyle", "AI & Software Subscriptions"),
            ("anthropic", "Lifestyle", "AI & Software Subscriptions"),
            ("openai", "Lifestyle", "AI & Software Subscriptions"),
            ("perplexity", "Lifestyle", "AI & Software Subscriptions"),
            ("google one", "Lifestyle", "AI & Software Subscriptions"),
            ("adobe", "HVM Production", "Software"),
            ("riverside", "HVM Production", "Software"),
            ("canva", "HVM Production", "Software"),
            ("descript", "HVM Production", "Software"),
            ("justworks", "HVM Operations", "Payroll"),
            ("wise", "HVM Operations", "Contractor"),
            ("patreon", "Income", "Passive Income"),
            ("shopify", "Income", "Passive Income"),
            ("mozilla", "Income", "W-2 Salary"),
            ("att", "Household", "Insurance & Utilities"),
            ("at&t", "Household", "Insurance & Utilities"),
            ("austin energy", "Household", "Insurance & Utilities"),
            ("state farm", "Household", "Insurance & Utilities"),
            ("progressive", "Household", "Insurance & Utilities"),
            ("mortgage", "Household", "Housing"),
            ("ally", "Wealth Building", "Emergency Fund"),
            ("fidelity", "Wealth Building", "Investments"),
            ("vanguard", "Wealth Building", "Investments"),
            ("m1 finance", "Wealth Building", "Investments"),
        ]

        for (merchant, category, subcategory) in defaults {
            map[merchant] = CategoryMapping(
                category: category,
                subcategory: subcategory,
                code: nil
            )
        }
    }

    public func lookup(_ payee: String) -> CategoryMapping? {
        let lower = payee.lowercased()
        if let exact = map[lower] { return exact }
        for (key, value) in map {
            if lower.contains(key) { return value }
        }
        return nil
    }

    public func add(_ payee: String, mapping: CategoryMapping) {
        map[payee.lowercased()] = mapping
    }

    public var count: Int { map.count }

    public func loadFromCSV(path: String) throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let fields = line.components(separatedBy: ",")
            guard fields.count >= 3 else { continue }
            let section = fields[0].trimmingCharacters(in: .whitespaces)
            let code = fields[1].trimmingCharacters(in: .whitespaces)
            let name = fields[2].trimmingCharacters(in: .whitespaces)

            guard !section.isEmpty, !section.hasPrefix("==="),
                  !section.hasPrefix("Summary"), !name.isEmpty,
                  !name.hasPrefix("TOTAL"), !name.hasPrefix("SUBTOTAL") else { continue }
        }

        logger.info("Loaded merchant map with \(self.map.count) entries")
    }
}
