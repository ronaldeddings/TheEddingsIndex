import Foundation
import os

public struct QBOReader: Sendable {
    private let basePath: String
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "qbo")

    public init(basePath: String = "/Volumes/VRAM/10-19_Work/10_Hacker_Valley_Media/10.06_finance/QuickBooksOnline") {
        self.basePath = basePath
    }

    public func readDeposits() throws -> [FinancialTransaction] {
        let path = "\(basePath)/deposits.csv"
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("deposits.csv not found at \(path)")
            return []
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let rows = parseCSV(content)
        guard !rows.isEmpty else { return [] }

        let headers = rows[0]
        let idIdx = headers.firstIndex(of: "Id")
        let amountIdx = headers.firstIndex(of: "TotalAmt")
        let dateIdx = headers.firstIndex(of: "TxnDate")
        let noteIdx = headers.firstIndex(of: "PrivateNote")
        let accountIdx = headers.firstIndex(of: "DepositToAccountRef.name")

        var transactions: [FinancialTransaction] = []
        let calendar = Calendar.current

        for row in rows.dropFirst() {
            guard let idIdx, let amountIdx, let dateIdx,
                  idIdx < row.count, amountIdx < row.count, dateIdx < row.count else { continue }

            let id = row[idIdx]
            let amount = Double(row[amountIdx]) ?? 0
            let dateStr = row[dateIdx]
            let note = noteIdx.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            let account = accountIdx.flatMap { $0 < row.count ? row[$0] : nil } ?? "HVM"

            guard let date = parseQBODate(dateStr) else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)

            let description = cleanDescription(note)

            let txn = FinancialTransaction(
                transactionId: "qbo-deposit-\(id)",
                source: "qbo",
                accountId: "qbo-\(account.lowercased().replacingOccurrences(of: " ", with: "-"))",
                accountName: account,
                institution: "QuickBooks Online",
                transactionDate: date,
                amount: amount,
                description: description,
                payee: extractPayee(from: description),
                year: components.year,
                month: components.month
            )
            transactions.append(txn)
        }

        logger.info("Read \(transactions.count) deposits from QBO")
        return transactions
    }

    public func readPurchases() throws -> [FinancialTransaction] {
        let path = "\(basePath)/purchases.csv"
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("purchases.csv not found at \(path)")
            return []
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let rows = parseCSV(content)
        guard !rows.isEmpty else { return [] }

        let headers = rows[0]
        let idIdx = headers.firstIndex(of: "Id")
        let amountIdx = headers.firstIndex(of: "TotalAmt")
        let dateIdx = headers.firstIndex(of: "TxnDate")
        let noteIdx = headers.firstIndex(of: "PrivateNote")
        let accountIdx = headers.firstIndex(of: "AccountRef.name")

        var transactions: [FinancialTransaction] = []
        let calendar = Calendar.current

        for row in rows.dropFirst() {
            guard let idIdx, let amountIdx, let dateIdx,
                  idIdx < row.count, amountIdx < row.count, dateIdx < row.count else { continue }

            let id = row[idIdx]
            let amount = -(Double(row[amountIdx]) ?? 0)
            let dateStr = row[dateIdx]
            let note = noteIdx.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
            let account = accountIdx.flatMap { $0 < row.count ? row[$0] : nil } ?? "HVM"

            guard let date = parseQBODate(dateStr) else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)

            let description = cleanDescription(note)

            let txn = FinancialTransaction(
                transactionId: "qbo-purchase-\(id)",
                source: "qbo",
                accountId: "qbo-\(account.lowercased().replacingOccurrences(of: " ", with: "-"))",
                accountName: account,
                institution: "QuickBooks Online",
                transactionDate: date,
                amount: amount,
                description: description,
                payee: extractPayee(from: description),
                year: components.year,
                month: components.month
            )
            transactions.append(txn)
        }

        logger.info("Read \(transactions.count) purchases from QBO")
        return transactions
    }

    public func readPayments() throws -> [FinancialTransaction] {
        let path = "\(basePath)/payments.csv"
        guard FileManager.default.fileExists(atPath: path) else {
            logger.warning("payments.csv not found at \(path)")
            return []
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let rows = parseCSV(content)
        guard !rows.isEmpty else { return [] }

        let headers = rows[0]
        let idIdx = headers.firstIndex(of: "Id")
        let amountIdx = headers.firstIndex(of: "TotalAmt")
        let dateIdx = headers.firstIndex(of: "TxnDate")
        let customerIdx = headers.firstIndex(of: "CustomerRef.name")

        var transactions: [FinancialTransaction] = []
        let calendar = Calendar.current

        for row in rows.dropFirst() {
            guard let idIdx, let amountIdx, let dateIdx,
                  idIdx < row.count, amountIdx < row.count, dateIdx < row.count else { continue }

            let id = row[idIdx]
            let amount = Double(row[amountIdx]) ?? 0
            let dateStr = row[dateIdx]
            let customer = customerIdx.flatMap { $0 < row.count ? row[$0] : nil } ?? "Client"

            guard let date = parseQBODate(dateStr) else { continue }
            let components = calendar.dateComponents([.year, .month], from: date)

            let txn = FinancialTransaction(
                transactionId: "qbo-payment-\(id)",
                source: "qbo",
                accountId: "qbo-receivables",
                accountName: "Accounts Receivable",
                institution: "QuickBooks Online",
                transactionDate: date,
                amount: amount,
                description: "Payment from \(customer)",
                payee: customer,
                year: components.year,
                month: components.month
            )
            transactions.append(txn)
        }

        logger.info("Read \(transactions.count) payments from QBO")
        return transactions
    }

    public func readAll() throws -> [FinancialTransaction] {
        var all: [FinancialTransaction] = []
        all.append(contentsOf: try readDeposits())
        all.append(contentsOf: try readPurchases())
        all.append(contentsOf: try readPayments())
        return all
    }

    private func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = content.startIndex

        while i < content.endIndex {
            let char = content[i]

            if inQuotes {
                if char == "\"" {
                    let next = content.index(after: i)
                    if next < content.endIndex && content[next] == "\"" {
                        currentField.append("\"")
                        i = content.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == "," {
                    currentRow.append(currentField)
                    currentField = ""
                } else if char == "\n" || char == "\r" {
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    if char == "\r" {
                        let next = content.index(after: i)
                        if next < content.endIndex && content[next] == "\n" {
                            i = next
                        }
                    }
                } else {
                    currentField.append(char)
                }
            }

            i = content.index(after: i)
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }

    private func parseQBODate(_ dateStr: String) -> Date? {
        let trimmed = String(dateStr.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: trimmed)
    }

    private func cleanDescription(_ raw: String) -> String {
        var cleaned = raw
        cleaned = cleaned.replacingOccurrences(
            of: #"DES:\S+\s+"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"ID:\S+\s+"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"INDN:\S+\s+"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"CO ID:\S+\s*\S*"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractPayee(from description: String) -> String {
        let cleaned = cleanDescription(description)
        let words = cleaned.split(separator: " ")
        if words.count > 3 {
            return words.prefix(3).joined(separator: " ")
        }
        return cleaned.isEmpty ? "Unknown" : cleaned
    }
}
