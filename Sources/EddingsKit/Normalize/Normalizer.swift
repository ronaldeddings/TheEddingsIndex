import Foundation

public struct Normalizer: Sendable {
    private let calendar = Calendar.current

    public init() {}

    public func normalizeAccounts(_ accounts: [SimpleFinClient.SimpleFinAccount]) -> [FinancialSnapshot] {
        let today = Date()
        return accounts.map { account in
            FinancialSnapshot(
                snapshotDate: today,
                accountId: account.id,
                accountName: account.name,
                institution: account.org?.name,
                accountType: classifyAccountType(name: account.name, balance: account.balance),
                balance: account.balance,
                availableBalance: account.availableBalance,
                currency: account.currency,
                source: "simplefin"
            )
        }
    }

    public func normalizeTransactions(
        _ accounts: [SimpleFinClient.SimpleFinAccount]
    ) -> [FinancialTransaction] {
        var transactions: [FinancialTransaction] = []

        for account in accounts {
            guard let rawTxns = account.transactions else { continue }

            for raw in rawTxns {
                let amount = Double(raw.amount) ?? 0
                let date = Date(timeIntervalSince1970: raw.posted)
                let components = calendar.dateComponents([.year, .month], from: date)

                let payee = normalizePayee(raw.payee ?? raw.description)

                let txn = FinancialTransaction(
                    transactionId: "\(account.id)-\(raw.id)",
                    source: "simplefin",
                    accountId: account.id,
                    accountName: account.name,
                    institution: account.org?.name,
                    transactionDate: date,
                    amount: amount,
                    description: raw.description,
                    payee: payee,
                    year: components.year,
                    month: components.month
                )
                transactions.append(txn)
            }
        }

        return transactions
    }

    public func detectTransfers(_ transactions: inout [FinancialTransaction]) {
        for i in 0..<transactions.count {
            guard !transactions[i].isTransfer else { continue }

            for j in (i + 1)..<transactions.count {
                guard !transactions[j].isTransfer else { continue }
                guard transactions[i].accountId != transactions[j].accountId else { continue }

                let amountMatch = abs(transactions[i].amount + transactions[j].amount) < 0.01
                let dateGap = abs(transactions[i].transactionDate.timeIntervalSince(transactions[j].transactionDate))
                let withinWindow = dateGap < 2 * 24 * 3600

                if amountMatch && withinWindow {
                    let pairId = UUID().uuidString
                    transactions[i].isTransfer = true
                    transactions[i].tags = "[\"transfer\"]"
                    transactions[j].isTransfer = true
                    transactions[j].tags = "[\"transfer\"]"
                    _ = pairId
                }
            }
        }
    }

    private func normalizePayee(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*#\d+$"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*\d{4,}$"#,
            with: "",
            options: .regularExpression
        )

        let words = cleaned.lowercased().split(separator: " ")
        return words.map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private func classifyAccountType(name: String, balance: Double) -> String {
        let lower = name.lowercased()
        if lower.contains("credit") || lower.contains("card") {
            return "creditCard"
        } else if lower.contains("mortgage") {
            return "mortgage"
        } else if lower.contains("loan") || lower.contains("auto") {
            return "loan"
        } else if lower.contains("saving") || lower.contains("hysa") {
            return "savings"
        } else if lower.contains("invest") || lower.contains("brokerage") || lower.contains("401k") || lower.contains("ira") {
            return "investment"
        } else if lower.contains("checking") {
            return "checking"
        }

        if balance < 0 { return "creditCard" }
        return "checking"
    }
}
