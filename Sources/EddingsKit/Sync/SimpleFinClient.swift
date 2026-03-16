import Foundation
import os

public actor SimpleFinClient {
    private let keychain: KeychainManager
    private let logger = Logger(subsystem: "com.hackervalley.eddingsindex", category: "simplefin")
    private let maxRetries = 3

    public init(keychain: KeychainManager = KeychainManager()) {
        self.keychain = keychain
    }

    public struct SimpleFinResponse: Codable, Sendable {
        public let errors: [String]
        public let accounts: [SimpleFinAccount]
    }

    public struct SimpleFinAccount: Codable, Sendable {
        public let id: String
        public let name: String
        public let currency: String
        public let balance: Double
        public let availableBalance: Double?
        public let balanceDate: TimeInterval?
        public let transactions: [SimpleFinTransaction]?
        public let org: SimpleFinOrg?

        enum CodingKeys: String, CodingKey {
            case id, name, currency, balance
            case availableBalance = "available-balance"
            case balanceDate = "balance-date"
            case transactions, org
        }
    }

    public struct SimpleFinTransaction: Codable, Sendable {
        public let id: String
        public let posted: TimeInterval
        public let amount: String
        public let description: String
        public let payee: String?
        public let memo: String?
        public let pending: Bool?
    }

    public struct SimpleFinOrg: Codable, Sendable {
        public let domain: String?
        public let name: String?
    }

    public func exchangeSetupToken(_ base64Token: String) async throws -> String {
        guard let tokenData = Data(base64Encoded: base64Token),
              let claimURLString = String(data: tokenData, encoding: .utf8),
              let claimURL = URL(string: claimURLString) else {
            throw SimpleFinError.invalidSetupToken
        }

        var request = URLRequest(url: claimURL)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SimpleFinError.claimFailed
        }

        guard let accessURL = String(data: data, encoding: .utf8),
              !accessURL.isEmpty else {
            throw SimpleFinError.emptyAccessURL
        }

        try keychain.storeSimpleFinAccessURL(accessURL)
        logger.info("SimpleFin Access URL stored in Keychain")
        return accessURL
    }

    public func fetchAccounts(startDate: Date? = nil, endDate: Date? = nil) async throws -> SimpleFinResponse {
        guard let accessURLString = try keychain.retrieveSimpleFinAccessURL(),
              var components = URLComponents(string: accessURLString + "/accounts") else {
            throw SimpleFinError.noAccessURL
        }

        var queryItems: [URLQueryItem] = []
        if let start = startDate {
            queryItems.append(URLQueryItem(name: "start-date", value: String(Int(start.timeIntervalSince1970))))
        }
        if let end = endDate {
            queryItems.append(URLQueryItem(name: "end-date", value: String(Int(end.timeIntervalSince1970))))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw SimpleFinError.invalidURL
        }

        let request = URLRequest(url: url)
        let data = try await fetchWithRetry(request: request)

        let decoder = JSONDecoder()
        let response = try decoder.decode(SimpleFinResponse.self, from: data)

        if !response.errors.isEmpty {
            logger.warning("SimpleFin returned errors: \(response.errors)")
        }

        logger.info("Fetched \(response.accounts.count) accounts from SimpleFin")
        return response
    }

    private func fetchWithRetry(request: URLRequest) async throws -> Data {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw SimpleFinError.invalidResponse
                }

                switch httpResponse.statusCode {
                case 200:
                    return data
                case 403:
                    try keychain.deleteSimpleFinAccessURL()
                    throw SimpleFinError.authExpired
                case 429:
                    let delay = pow(2.0, Double(attempt))
                    logger.warning("Rate limited, retrying in \(delay)s (attempt \(attempt)/\(self.maxRetries))")
                    try await Task.sleep(for: .seconds(delay))
                    continue
                default:
                    throw SimpleFinError.httpError(httpResponse.statusCode)
                }
            } catch let error as SimpleFinError {
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let delay = pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw lastError ?? SimpleFinError.maxRetriesExceeded
    }

    public enum SimpleFinError: Error, Sendable {
        case invalidSetupToken
        case claimFailed
        case emptyAccessURL
        case noAccessURL
        case invalidURL
        case invalidResponse
        case authExpired
        case httpError(Int)
        case maxRetriesExceeded
    }
}
