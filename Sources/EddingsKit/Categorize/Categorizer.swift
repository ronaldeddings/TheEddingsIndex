import Foundation
import os

public actor Categorizer {
    private let merchantMap: MerchantMap
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "categorize")

    public init(merchantMap: MerchantMap) {
        self.merchantMap = merchantMap
    }

    public struct CategorizationResult: Sendable {
        public let categorized: [FinancialTransaction]
        public let uncategorized: [FinancialTransaction]
        public let stats: Stats

        public struct Stats: Sendable {
            public let byExactMatch: Int
            public let byPattern: Int
            public let byHeuristic: Int
            public let uncategorized: Int
        }
    }

    public func categorize(_ transactions: [FinancialTransaction]) async -> CategorizationResult {
        var categorized: [FinancialTransaction] = []
        var uncategorized: [FinancialTransaction] = []
        var exactCount = 0
        var patternCount = 0
        var heuristicCount = 0

        for var txn in transactions {
            if txn.category != nil {
                categorized.append(txn)
                continue
            }

            if let payee = txn.payee, let mapping = await merchantMap.lookup(payee) {
                txn.category = mapping.category
                txn.subcategory = mapping.subcategory
                categorized.append(txn)
                exactCount += 1
                continue
            }

            if let result = patternMatch(txn) {
                txn.category = result.category
                txn.subcategory = result.subcategory
                categorized.append(txn)
                patternCount += 1
                continue
            }

            if let result = heuristicMatch(&txn) {
                txn.category = result.category
                txn.subcategory = result.subcategory
                categorized.append(txn)
                heuristicCount += 1
                continue
            }

            uncategorized.append(txn)
        }

        let total = transactions.count
        let catCount = categorized.count
        let pct = total > 0 ? (catCount * 100 / total) : 0
        logger.info("Categorized \(catCount)/\(total) (\(pct)%): exact=\(exactCount) pattern=\(patternCount) heuristic=\(heuristicCount) uncategorized=\(uncategorized.count)")

        return CategorizationResult(
            categorized: categorized,
            uncategorized: uncategorized,
            stats: .init(
                byExactMatch: exactCount,
                byPattern: patternCount,
                byHeuristic: heuristicCount,
                uncategorized: uncategorized.count
            )
        )
    }

    private func patternMatch(_ txn: FinancialTransaction) -> (category: String, subcategory: String?)? {
        let desc = (txn.description ?? "").lowercased()
        let payee = (txn.payee ?? "").lowercased()
        let text = "\(payee) \(desc)"

        let patterns: [(String, String, String?)] = [
            (#"spotify|hulu|netflix|disney|hbo|audible|paramount"#, "Lifestyle", "Entertainment Streaming"),
            (#"doordash|uber\s*eats|grubhub|postmates"#, "Lifestyle", "Dining & Delivery"),
            (#"h-?e-?b|costco|walmart|target|kroger|aldi"#, "Household", "Groceries"),
            (#"shell|exxon|chevron|valero|buc-?ee"#, "Household", "Transportation"),
            (#"state\s*farm|progressive|allstate|geico"#, "Household", "Insurance"),
            (#"adobe|canva|figma|notion|slack|zoom|riverside"#, "HVM Production", "Software"),
            (#"justworks|gusto|adp"#, "HVM Operations", "Payroll"),
            (#"aws|azure|vercel|railway|digital\s*ocean"#, "HVM Operations", "Infrastructure"),
            (#"claude|anthropic|openai|perplexity|chatgpt"#, "Lifestyle", "AI & Software"),
            (#"venmo|zelle|cash\s*app"#, "Transfer", nil),
        ]

        for (pattern, category, subcategory) in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return (category, subcategory)
            }
        }

        return nil
    }

    private func heuristicMatch(_ txn: inout FinancialTransaction) -> (category: String, subcategory: String?)? {
        if txn.amount > 0 && txn.amount > 1000 {
            return ("Income", nil)
        }

        let absAmount = abs(txn.amount)
        if absAmount > 1500 && absAmount < 3500 {
            let desc = (txn.description ?? "").lowercased()
            if desc.contains("mortgage") || desc.contains("home") || desc.contains("housing") {
                txn.isRecurring = true
                return ("Household", "Housing")
            }
        }

        return nil
    }
}
