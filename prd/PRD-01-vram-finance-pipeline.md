# PRD-01: VRAM Finance Pipeline — Swift CLI for Automated Financial Awareness

**Status:** DRAFT
**Date:** 2026-03-15
**Author:** PAI
**Target:** Swift command-line tool that pulls personal + business financial data via SimpleFin Bridge API, persists to VRAM, and categorizes transactions — running twice daily as a launch agent
**Predecessor:** None (greenfield)

---

## Executive Summary

Ron operates two financial systems — personal (banking, investments, credit cards, mortgage) and business (HVM via QuickBooks Online) — and needs unified awareness across both to execute the Freedom Acceleration Plan. The critical blocker identified in Goal #7 (Family Money Dashboard) is measurement: *"What prevents me from doing that is not measuring and assessing progress."*

**The gap:** Financial data lives in 8+ institutions with no automated aggregation. QBO pulls exist (com.vram.qbo-dump, every 12 hours) but personal finances require manual checking. No unified view. No audit trail. No categorization pipeline. No Search Engine integration for financial queries.

**The fix:** Build a Swift command-line tool (`finance-pull`) as a Swift Package with an executable target. It connects to SimpleFin Bridge API via `URLSession` async/await, stores credentials in macOS Keychain via `SecItem` APIs, and persists structured data to VRAM's Johnny.Decimal finance hierarchy (20-29) using `FileManager` + `Codable` serialization.

**Why Swift:** Ron is standardizing on Swift for all new Mac/iOS tooling. This CLI becomes the first tool in a unified Swift toolchain. The binary runs natively on Apple Silicon with zero runtime dependencies (no Node, no Bun, no JVM). Foundation provides everything needed: `URLSession` for HTTP, `JSONDecoder`/`JSONEncoder` for Codable serialization, `FileManager` for filesystem, `SecItem` for Keychain, `Logger` for structured logging.

**Why not Actual Budget:** ActualBudget is an unnecessary attack surface. SimpleFin provides the same bank connectivity that Actual uses under the hood (confirmed in Actual's open-source `simplefin-batch-sync` implementation). Going direct eliminates a self-hosted Railway dependency, reduces maintenance, and keeps all data on VRAM.

**Scope:**
- **In scope:** SimpleFin API integration, Keychain credential storage, VRAM file persistence, categorization engine, launch agent automation, QBO data correlation
- **Out of scope:** GUI app (CLI workflow only for now), Search Engine PostgreSQL ingestion (future phase), investment portfolio analysis (future phase), tax document generation, bill pay/mutations (SimpleFin is read-only)

**PAI owns the full implementation and test-iterate-fix cycle.**

---

## Background & Prior Art

### SimpleFin Bridge API

SimpleFin provides read-only access to 10,000+ financial institutions via a three-step auth flow:

1. **Setup Token** (one-time): Base64-encoded claim URL obtained from SimpleFin Bridge UI. Decoded via `Data(base64Encoded:)` per `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/Foundation/Data/README.md`
2. **Claim Exchange**: HTTP POST to claim URL via `URLSession.shared.data(for:)` → returns Access URL with embedded Basic Auth credentials
3. **Access URL** (long-lived): `https://user:pass@bridge.simplefin.org/simplefin/accounts` — stored in macOS Keychain via `SecItemAdd(_:_:)`

**Key constraints:**
- 90-day max transaction history per request
- ~24 requests/day rate limit
- Data refreshes approximately once daily per institution
- Read-only (no mutations)

**Response structure (GET /accounts):**
```json
{
  "errors": [],
  "accounts": [
    {
      "id": "unique_account_id",
      "name": "Checking Account",
      "currency": "USD",
      "balance": 5000.00,
      "available-balance": 4950.00,
      "balance-date": 1234567890,
      "transactions": [
        { "id": "txn_12345", "posted": 1234567800, "amount": -50.00, "description": "Coffee shop" }
      ],
      "org": { "domain": "bank.example.com", "name": "Example Bank" }
    }
  ]
}
```

### Actual Budget SimpleFin Patterns (Inspiration)

From Actual Budget's open-source implementation (github.com/actualbudget/actual, PR #3581, #3821):
- **Deduplication:** `imported_id` field matching (primary), fuzzy match on amount + date + payee (secondary)
- **Date window overlap:** 5-day overlap on subsequent syncs to catch delayed postings
- **Batch sync:** Single request for all accounts, error aggregation (don't fail entire sync on one account error)
- **Transform:** SimpleFin `description` → payee name, Unix timestamps → dates

### Copilot Money Patterns (Inspiration)

From the CopilotApp reverse-engineering audit (`/Volumes/VRAM/80-89_Resources/80_Reference/research/CopilotApp/`):
- 602-category taxonomy with 13 top-level groups and 3-level hierarchy
- Multi-source financial connectivity with adapters under one domain layer
- Local-first with conflict resolution
- Recurring transaction recognition and internal transfer matching

### Existing Infrastructure

| Component | Status | Integration Point |
|-----------|--------|-------------------|
| QBO Dump Agent | Running (`com.vram.qbo-dump`, every 12h) | HVM business data in `/Volumes/VRAM/10-19_Work/10_Hacker_Valley_Media/10.06_finance/QuickBooksOnline/` |
| VRAM 20-29_Finance | Exists (Banking, Investments, Taxes, Insurance, Real Estate, Archive) | Target for file persistence |
| SimpleFin API Key | Already obtained | Credential for bank connectivity |
| Eddings Wealth Categories | Exists (`20_Banking/Eddings-Wealth-Categories.csv`) | Categorization reference |

---

## Architecture

### Swift Package Structure

```
finance-pull/
├── Package.swift                      # Swift Package manifest
├── Sources/
│   ├── FinancePull/                   # Executable target (CLI)
│   │   ├── FinancePull.swift          # @main entry, ArgumentParser command
│   │   └── Commands/
│   │       ├── PullCommand.swift      # --pull: fetch from SimpleFin
│   │       ├── CategorizeCommand.swift # --categorize: classify transactions
│   │       ├── SummaryCommand.swift   # --summary: generate monthly report
│   │       └── SetupCommand.swift     # --setup: exchange SimpleFin token
│   └── FinanceKit/                    # Library target (shared logic)
│       ├── API/
│       │   └── SimpleFinClient.swift  # URLSession-based API client
│       ├── Auth/
│       │   └── KeychainManager.swift  # SecItem credential storage
│       ├── Models/
│       │   ├── Account.swift          # Codable account model
│       │   ├── Transaction.swift      # Codable transaction model
│       │   ├── BalanceSnapshot.swift   # Codable snapshot model
│       │   └── MonthlySummary.swift   # Codable summary model
│       ├── Normalize/
│       │   ├── Normalizer.swift       # Transform SimpleFin → unified format
│       │   ├── Deduplicator.swift     # Transaction dedup engine
│       │   └── QBOReader.swift        # Parse QBO CSV exports
│       ├── Categorize/
│       │   ├── Categorizer.swift      # Rule-based categorization
│       │   └── MerchantMap.swift      # Merchant → category lookup
│       ├── Persist/
│       │   ├── VRAMWriter.swift       # FileManager-based VRAM persistence
│       │   └── StateManager.swift     # Sync state tracking
│       └── Audit/
│           ├── AnomalyDetector.swift  # Unusual transaction detection
│           └── FreedomTracker.swift   # $6,058/week velocity tracker
├── Tests/
│   └── FinanceKitTests/
│       ├── SimpleFinClientTests.swift
│       ├── NormalizerTests.swift
│       ├── DeduplicatorTests.swift
│       └── CategorizerTests.swift
├── com.vram.finance-pull.plist        # Launch agent definition
└── state/                             # Runtime state (gitignored)
    └── sync-state.json                # Last sync timestamps per account
```

### Package.swift Manifest

Per `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/PackageDescription/README.md`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "finance-pull",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "finance-pull", targets: ["FinancePull"]),
        .library(name: "FinanceKit", targets: ["FinanceKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "FinancePull",
            dependencies: [
                "FinanceKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "FinanceKit"
        ),
        .testTarget(
            name: "FinanceKitTests",
            dependencies: ["FinanceKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

**Platform choice:** macOS 15+ gives access to `Mutex` (Synchronization framework per `.../Synchronization/Mutex/README.md`), `@Observable` (per `.../Observation/README.md`), modern `Logger` APIs, and Swift 6 concurrency. Per `.../PackageDescription/SupportedPlatform/README.md`, platform is declared via `.macOS(.v15)`.

**Dependencies (1 only):**
- `swift-argument-parser` — Apple's official CLI framework. Provides `@main`, `@Argument`, `@Option`, `@Flag`, subcommands. No Foundation alternative exists.

**Everything else is Foundation/stdlib:** `URLSession` for HTTP, `JSONDecoder`/`JSONEncoder` for JSON, `FileManager` for filesystem, `SecItem` for Keychain, `Logger` for logging, `Data` for Base64.

### Data Flow

```
SimpleFin Bridge API                    QBO CSVs (existing)
        │                                      │
        ▼                                      ▼
┌───────────────┐                    ┌──────────────────┐
│ SimpleFinClient│                    │ QBOReader         │
│ (URLSession)  │                    │ (String parsing)  │
│               │                    │                   │
│ async/await   │                    │ Parse CSV → model │
│ data(for:)    │                    │                   │
└───────┬───────┘                    └────────┬──────────┘
        │                                      │
        ▼                                      ▼
┌──────────────────────────────────────────────────────┐
│                  Normalizer.swift                      │
│                                                        │
│  SimpleFin response → [Transaction]                    │
│  QBO CSV rows → [Transaction]                          │
│  Deduplicator filters seen IDs (StateManager)          │
│  JSONDecoder with .convertFromSnakeCase strategy       │
└───────────────────┬───────────────────────────────────┘
                    │
          ┌─────────┴─────────┐
          ▼                   ▼
┌──────────────┐    ┌──────────────┐
│ VRAMWriter   │    │ Categorizer  │
│ (FileManager)│    │              │
│              │    │ Rules →      │
│ snapshots/   │    │ merchant     │
│ transactions/│    │ map →        │
│ .json/.jsonl │    │ PAI          │
│              │    │ fallback     │
│ Data.write() │    │              │
└──────────────┘    └──────────────┘
```

### VRAM File Structure

```
/Volumes/VRAM/20-29_Finance/
├── 20_Banking/
│   ├── snapshots/
│   │   └── 2026-03-15.json          # Daily balance snapshot (all accounts)
│   ├── transactions/
│   │   ├── 2026-03/                  # Monthly transaction files
│   │   │   ├── checking-9746.jsonl   # Per-account JSONL
│   │   │   ├── amex-1006.jsonl
│   │   │   └── chase-freedom.jsonl
│   │   └── 2026-02/
│   ├── categorized/
│   │   ├── 2026-03.json              # Monthly categorized summary
│   │   └── uncategorized.json        # Queue for review
│   ├── All-Accounts.csv              # (existing)
│   ├── Eddings-Wealth-Categories.csv # (existing — categorization reference)
│   └── Eddings-Expense-Mapping.csv   # (existing)
├── 21_Investments/
│   ├── snapshots/
│   │   └── 2026-03-15.json          # Investment balance snapshot
│   └── holdings/
│       └── 2026-03.json             # Monthly holdings detail
├── 22_Taxes/                         # (existing, unchanged)
├── 23_Insurance/                     # (existing, unchanged)
├── 24_Real_Estate/                   # (existing, unchanged)
└── 25_Archive/                       # (existing, unchanged)
```

### Codable Data Models

**Transaction:**

```swift
struct Transaction: Codable, Identifiable {
    let id: String
    let source: Source
    let accountID: String
    let accountName: String
    let institution: String
    var date: Date
    let postedAt: TimeInterval
    let amount: Decimal
    let description: String
    var payee: String
    var category: String?
    var subcategory: String?
    var isRecurring: Bool
    var isTransfer: Bool
    var transferPairID: String?
    var tags: [String]

    enum Source: String, Codable {
        case simplefin, qbo
    }
}
```

Per `.../Foundation/JSONDecoder/README.md`, use `dateDecodingStrategy: .secondsSince1970` for SimpleFin Unix timestamps and `keyDecodingStrategy: .convertFromSnakeCase` for JSON field mapping.

**BalanceSnapshot:**

```swift
struct BalanceSnapshot: Codable {
    let date: Date
    let accounts: [AccountBalance]
    let totals: Totals

    struct Totals: Codable {
        let assets: Decimal
        let liabilities: Decimal
        let netWorth: Decimal
        let availableCash: Decimal
    }
}

struct AccountBalance: Codable, Identifiable {
    let id: String
    let name: String
    let institution: String
    let type: AccountType
    let balance: Decimal
    let availableBalance: Decimal?
    let currency: String
    let lastUpdated: TimeInterval

    enum AccountType: String, Codable {
        case checking, savings, creditCard, investment, mortgage, loan, other
    }
}
```

**MonthlySummary:**

```swift
struct MonthlySummary: Codable {
    let month: String
    let income: Decimal
    let expenses: Decimal
    let net: Decimal
    let savingsRate: Decimal
    let categories: [CategoryBreakdown]
    let freedomVelocity: FreedomVelocity

    struct FreedomVelocity: Codable {
        let weeklyNonW2TakeHome: Decimal
        let target: Decimal   // $6,058
        let onTrack: Bool
    }
}

struct CategoryBreakdown: Codable {
    let category: String
    let amount: Decimal
    let transactionCount: Int
    let percentageOfTotal: Decimal
}
```

---

## Implementation Plan

### Phase 1 (P0): Swift Package Scaffold + SimpleFin API Client

**Goal:** Establish the Swift package, authenticate with SimpleFin, and pull raw account + transaction data.

**Steps:**
- [ ] 1.1 — Create Swift package with `swift package init --type executable --name finance-pull`. Define `Package.swift` with macOS 15+ platform, `swift-argument-parser` and `postgres-nio` dependencies, executable + library targets. Per `.../PackageDescription/Package/README.md` and `.../PackageDescription/Target/README.md`.
- [ ] 1.2 — Implement `KeychainManager.swift` using Security framework `SecItem` APIs:
  - `store(accessURL:)` → `SecItemAdd(_:_:)` with `kSecClassGenericPassword`, service name `"com.vram.finance-pull"`, account `"simplefin-access-url"`. Per `.../Security/SecItemAdd(____).md`.
  - `retrieve()` → `SecItemCopyMatching(_:_:)` with `kSecReturnData: true`. Per `.../Security/SecItemCopyMatching(____).md`.
  - `delete()` → `SecItemDelete(_:)`. Per `.../Security/SecItemDelete(__).md`.
  - `exchangeSetupToken(_:)` → Decode Base64 setup token via `Data(base64Encoded:)` (per `.../Foundation/Data/README.md`), POST to claim URL via `URLSession`, store resulting Access URL in Keychain.
- [ ] 1.3 — Implement `SimpleFinClient.swift` using Foundation networking:
  - Create `URLRequest` with Access URL + query parameters (`start-date`, `end-date`). Per `.../Foundation/URLRequest/README.md`.
  - Execute via `let (data, response) = try await URLSession.shared.data(for: request)`. Per `.../Foundation/URLSession/README.md`.
  - Validate `HTTPURLResponse.statusCode` (200 OK, 403 = re-auth needed). Per `.../Foundation/HTTPURLResponse/README.md`.
  - Decode JSON response using `JSONDecoder` with `.convertFromSnakeCase` key strategy and `.secondsSince1970` date strategy. Per `.../Foundation/JSONDecoder/README.md`.
  - Check `errors` array in response — surface warnings, fail on auth errors.
  - Rate limiting: track request count, exponential backoff on 429 (max 3 retries).
- [ ] 1.4 — Implement `SetupCommand.swift` using ArgumentParser:
  - `finance-pull setup --token <base64-setup-token>` → exchange token, store Access URL in Keychain, verify by pulling account list.
- [ ] 1.5 — Implement account type classifier in `Account.swift`:
  - Detect type from name patterns + balance sign (negative balance on "credit"/"card" → `.creditCard`, "mortgage"/"loan" → `.mortgage`/`.loan`, etc.)
- [ ] 1.6 — Build and run: `swift build && .build/debug/finance-pull setup --token <token>` — verify accounts returned.

**Guard:** `finance-pull setup` must successfully store credentials in Keychain and return at least one account.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| Foundation | `.../Foundation/URLSession/README.md` | `URLSession.shared.data(for:)` | Async HTTP requests to SimpleFin |
| Foundation | `.../Foundation/URLRequest/README.md` | `URLRequest` | Build HTTP request with method, headers |
| Foundation | `.../Foundation/HTTPURLResponse/README.md` | `statusCode` | Validate HTTP response status |
| Foundation | `.../Foundation/JSONDecoder/README.md` | `JSONDecoder.decode(_:from:)` | Parse SimpleFin JSON → Codable models |
| Foundation | `.../Foundation/Data/README.md` | `Data(base64Encoded:)` | Decode SimpleFin setup token |
| Foundation | `.../Foundation/URL/README.md` | `URL(string:)` | Construct API endpoint URLs |
| Security | `.../Security/SecItemAdd(____).md` | `SecItemAdd(_:_:)` | Store Access URL in Keychain |
| Security | `.../Security/SecItemCopyMatching(____).md` | `SecItemCopyMatching(_:_:)` | Retrieve Access URL from Keychain |
| Security | `.../Security/SecItemDelete(__).md` | `SecItemDelete(_:)` | Remove stale credentials |
| Security | `.../Security/keychain-services/README.md` | Keychain Services overview | Credential storage architecture |
| PackageDescription | `.../PackageDescription/README.md` | `Package` manifest | Swift Package definition |
| PackageDescription | `.../PackageDescription/Target/README.md` | `.executableTarget()` | CLI executable target |
| PackageDescription | `.../PackageDescription/SupportedPlatform/README.md` | `.macOS(.v15)` | Platform requirement |

---

### Phase 2 (P0): Transaction Normalization + Deduplication

**Goal:** Transform SimpleFin raw data into unified `Transaction` model with robust deduplication.

**Steps:**
- [ ] 2.1 — Implement `Normalizer.swift`:
  - Map SimpleFin account response fields → `AccountBalance` and `Transaction` Codable structs.
  - Convert Unix timestamps → `Date` via `Date(timeIntervalSince1970:)`.
  - Extract year/month/quarter using `Calendar.current.dateComponents([.year, .month], from: date)`. Per `.../Foundation/Calendar/README.md` and `.../Foundation/DateComponents/README.md`.
  - Normalize payee names: trim whitespace, title-case, strip trailing reference numbers.
  - Detect internal transfers: matching amount (opposite sign) within 2-day window across different accounts.
- [ ] 2.2 — Implement `Deduplicator.swift`:
  - Primary: match on `transaction.id` (SimpleFin's unique ID per account).
  - Secondary: fuzzy match on `|amount| + date ± 1 day + payee Levenshtein distance < 3`.
  - Load/save seen IDs from `state/sync-state.json` via `FileManager` + `JSONDecoder`/`JSONEncoder`. Per `.../Foundation/FileManager/README.md`.
  - 5-day overlap window: on subsequent pulls, request `start-date = lastSync - 5 days` to catch delayed postings (Actual Budget pattern).
- [ ] 2.3 — Implement `StateManager.swift`:
  - Track per-account last sync timestamp in `state/sync-state.json`.
  - Track seen transaction IDs per account (rolling 90-day window to prevent unbounded growth).
  - Use `Data.write(to:options: .atomic)` for crash-safe state persistence. Per `.../Foundation/Data/README.md`.
- [ ] 2.4 — Implement `QBOReader.swift`:
  - Read QBO CSV files from `/Volumes/VRAM/10-19_Work/10_Hacker_Valley_Media/10.06_finance/QuickBooksOnline/`.
  - Parse `purchases.csv`, `payments.csv`, `deposits.csv` using `String` splitting (no external CSV library — these are simple CSVs).
  - Map to `Transaction` with `source: .qbo`.
  - Cross-reference by institution + account name to avoid double-counting if HVM business account appears in SimpleFin.
- [ ] 2.5 — Write tests: normalization edge cases (negative amounts, pending transactions, multi-currency), dedup correctness (run twice = 0 new), QBO parsing.

**Guard:** Normalized transactions must round-trip through `JSONEncoder` → `JSONDecoder` without data loss.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| Foundation | `.../Foundation/Calendar/README.md` | `Calendar.current.dateComponents(_:from:)` | Extract year/month/quarter from dates |
| Foundation | `.../Foundation/DateComponents/README.md` | `DateComponents` | Date component access |
| Foundation | `.../Foundation/FileManager/README.md` | `FileManager.default.contents(atPath:)` | Read state files |
| Foundation | `.../Foundation/Data/README.md` | `Data.write(to:options: .atomic)` | Atomic state file writes |
| Foundation | `.../Foundation/JSONEncoder/README.md` | `JSONEncoder` with `.prettyPrinted` | Serialize state to JSON |
| Swift | `.../Swift/Codable/README.md` | `Codable` protocol | Transaction/Account model conformance |

---

### Phase 3 (P0): VRAM File Persistence

**Goal:** Persist financial data to VRAM's Johnny.Decimal structure as structured JSON/JSONL files.

**Steps:**
- [ ] 3.1 — Implement `VRAMWriter.swift`:
  - Verify VRAM volume mounted: `FileManager.default.fileExists(atPath: "/Volumes/VRAM")`. Per `.../Foundation/FileManager/README.md`.
  - Create directories as needed: `FileManager.default.createDirectory(at:withIntermediateDirectories: true)`.
  - Write daily balance snapshot: encode `BalanceSnapshot` via `JSONEncoder` with `.prettyPrinted` and `.sortedKeys` output formatting (per `.../Foundation/JSONEncoder/README.md`), write to `20_Banking/snapshots/{yyyy-MM-dd}.json`.
  - Append transactions: encode each `Transaction` as single JSON line, append to `20_Banking/transactions/{yyyy-MM}/{account-slug}.jsonl` using `FileHandle.seekToEndOfFile()` + `FileHandle.write()`. Per `.../Foundation/FileHandle/README.md`.
  - Write investment snapshots to `21_Investments/snapshots/{date}.json` when investment accounts detected.
  - Format dates for filenames using `ISO8601DateFormatter` with `.withFullDate` option. Per `.../Foundation/ISO8601DateFormatter/README.md`.
- [ ] 3.2 — Implement snapshot aggregation in `BalanceSnapshot.Totals`:
  - Sum assets (positive-balance accounts: checking, savings, investment).
  - Sum liabilities (negative-balance accounts: credit cards, loans, mortgages — stored as positive liability amounts).
  - Calculate `netWorth = assets - liabilities`.
  - Compare to previous snapshot (read prior day's file) → compute delta.
- [ ] 3.3 — Implement `FreedomTracker.swift`:
  - Read HVM distributions from QBO data (filter `deposits.csv` for owner's draw / distribution entries).
  - Calculate weekly non-W2 take-home: `totalDistributions / weeksElapsed`.
  - Compare to $6,058 target.
  - Attach `FreedomVelocity` struct to `BalanceSnapshot`.
- [ ] 3.4 — Implement `PullCommand.swift`:
  - `finance-pull pull` → fetch SimpleFin, normalize, dedup, write to VRAM.
  - Log results via `Logger`. Per `.../os/Logger/README.md`.
- [ ] 3.5 — Verify: `swift build && .build/debug/finance-pull pull` → check files written, read back with `cat`, validate JSON.

**Guard:** All written files must be valid JSON/JSONL. Verify by reading back with `JSONDecoder`.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| Foundation | `.../Foundation/FileManager/README.md` | `createDirectory(at:withIntermediateDirectories:)` | Create VRAM subdirectories |
| Foundation | `.../Foundation/FileHandle/README.md` | `seekToEndOfFile()`, `write(contentsOf:)` | Append JSONL transaction lines |
| Foundation | `.../Foundation/JSONEncoder/README.md` | `.outputFormatting: [.prettyPrinted, .sortedKeys]` | Human-readable snapshot JSON |
| Foundation | `.../Foundation/ISO8601DateFormatter/README.md` | `string(from:)` | Date strings for filenames |
| os | `.../os/Logger/README.md` | `Logger(subsystem:category:)` | Structured logging per operation |

---

### Phase 4 (P1): Categorization Engine

**Goal:** Automatically categorize transactions using rule-based matching first, then PAI inference for unknowns.

**Steps:**
- [ ] 4.1 — Parse existing Eddings Wealth Categories from `20_Banking/Eddings-Wealth-Categories.csv` and `Eddings-Expense-Mapping.csv` into `MerchantMap.swift` (Codable dictionary loaded at startup).
- [ ] 4.2 — Implement `Categorizer.swift`:
  - **Tier 1 — Exact match:** Lookup `payee` in merchant map → category.
  - **Tier 2 — Pattern match:** Regex rules for common merchants (e.g., `/spotify/i` → "Subscriptions", `/heb|h-e-b/i` → "Groceries", `/shell|exxon|chevron/i` → "Gas").
  - **Tier 3 — Amount heuristics:** Large monthly debit to mortgage servicer → "Mortgage". Same amount ± 10% at 25-35 day intervals → flag `isRecurring`.
  - **Tier 4 — PAI inference:** Batch uncategorized transactions (max 20), shell out to `Tools/Inference.ts fast` with prompt containing description + amount + payee → category. Parse response. Cache new merchant→category mappings.
  - Write uncategorized queue to `20_Banking/categorized/uncategorized.json`.
- [ ] 4.3 — Implement `SummaryCommand.swift` (`finance-pull summary --month 2026-03`):
  - Group categorized transactions by Eddings Wealth Category.
  - Calculate income vs expenses, savings rate.
  - Generate `20_Banking/categorized/{yyyy-MM}.json` with `MonthlySummary`.
  - Include `FreedomVelocity` in summary.
- [ ] 4.4 — Implement `CategorizeCommand.swift` (`finance-pull categorize`):
  - Load uncategorized transactions from VRAM.
  - Run through categorizer tiers.
  - Update transaction files in-place with assigned categories.
  - Report: `X categorized by rules, Y by PAI, Z still uncategorized`.
- [ ] 4.5 — Write tests for categorization against known transaction samples from existing bank data.

**Guard:** At least 70% of transactions must be auto-categorized by rules before PAI inference runs.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| Foundation | `.../Foundation/Process/README.md` | `Process.run()` | Shell out to `Tools/Inference.ts` for PAI categorization |
| Foundation | `.../Foundation/JSONDecoder/README.md` | `JSONDecoder` | Parse merchant map and category config |
| Swift | `.../Swift/Result/README.md` | `Result<Success, Failure>` | Categorization result handling |

---

### Phase 5 (P1): Launch Agent + CLI Orchestration

**Goal:** Automate the pipeline to run twice daily via macOS launch agent.

**Steps:**
- [ ] 5.1 — Implement full CLI in `FinancePull.swift` using ArgumentParser:
  - `finance-pull pull` — Fetch SimpleFin, normalize, dedup, write to VRAM.
  - `finance-pull categorize` — Run categorization on uncategorized transactions.
  - `finance-pull summary --month <YYYY-MM>` — Generate monthly summary.
  - `finance-pull setup --token <base64>` — Exchange SimpleFin token.
  - `finance-pull full` — Run pull → categorize → summary (default for launch agent).
  - `finance-pull audit` — Run anomaly detection.
  - Exit codes: 0 = success, 1 = partial failure, 2 = total failure.
- [ ] 5.2 — Implement structured logging throughout using `Logger`:
  - `Logger(subsystem: "com.vram.finance-pull", category: "sync")`. Per `.../os/Logger/README.md`.
  - Log levels: `.info` for operations, `.error` for failures, `.debug` for verbose output.
  - Log: accounts pulled, transactions found, new (after dedup), categorized, uncategorized, errors, duration.
- [ ] 5.3 — Create `com.vram.finance-pull.plist` launch agent:
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
  <plist version="1.0">
  <dict>
      <key>Label</key>
      <string>com.vram.finance-pull</string>
      <key>ProgramArguments</key>
      <array>
          <string>/Volumes/VRAM/00-09_System/01_Tools/actual_puller/.build/release/finance-pull</string>
          <string>full</string>
      </array>
      <key>StartInterval</key>
      <integer>43200</integer>
      <key>RunAtLoad</key>
      <true/>
      <key>WorkingDirectory</key>
      <string>/Volumes/VRAM/00-09_System/01_Tools/actual_puller</string>
      <key>StandardOutPath</key>
      <string>/Users/ronaldeddings/Library/Logs/vram/finance-pull/pull.log</string>
      <key>StandardErrorPath</key>
      <string>/Users/ronaldeddings/Library/Logs/vram/finance-pull/error.log</string>
      <key>KeepAlive</key>
      <false/>
  </dict>
  </plist>
  ```
  Per `.../ServiceManagement/SMAppService/README.md`, launch agents can also be registered programmatically via `SMAppService.agent(plistName:).register()` on macOS 13+.
- [ ] 5.4 — Add voice notification on completion:
  - On success: `URLSession` POST to `http://localhost:8888/notify` with summary JSON.
  - On failure: notify with error message.
- [ ] 5.5 — Build release: `swift build -c release`. Copy binary. Install launch agent: `cp com.vram.finance-pull.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/com.vram.finance-pull.plist`.
- [ ] 5.6 — Verify first automated run via log file.

**Guard:** Launch agent must complete a full cycle without errors.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| os | `.../os/Logger/README.md` | `Logger(subsystem:category:)` | Structured logging with levels |
| ServiceManagement | `.../ServiceManagement/SMAppService/README.md` | `SMAppService.agent(plistName:)` | Programmatic launch agent registration |
| Foundation | `.../Foundation/ProcessInfo/README.md` | `ProcessInfo.processInfo.environment` | Read environment variables |

---

### Phase 6 (P2): QBO Correlation + Business Finance Awareness

**Goal:** Correlate personal SimpleFin data with HVM QBO data for unified financial picture.

**Steps:**
- [ ] 7.1 — Implement QBO-SimpleFin correlator:
  - Match HVM business checking account in SimpleFin with QBO deposits/payments.
  - Flag discrepancies (amount in SimpleFin but not in QBO, or vice versa).
  - Detect owner's draws/distributions flowing from HVM → personal accounts.
- [ ] 7.2 — Implement A/R + pipeline tracker:
  - Read QBO `invoices.csv` for outstanding receivables.
  - Calculate days outstanding per invoice.
  - Flag overdue invoices (> Net 30 or Net 60).
  - Write A/R summary to `20_Banking/categorized/ar-summary.json`.
- [ ] 7.3 — Implement debt elimination tracker:
  - Track credit card balances over time from snapshots.
  - Calculate paydown velocity ($/week).
  - Project zero-balance date for each card (linear extrapolation).
  - Compare to plan targets (Chase: month 1, United: month 1-2, auto loan: month 3-6).
- [ ] 7.4 — Implement wealth building tracker:
  - Track monthly contributions vs targets ($12,395/mo across all accounts).
  - Calculate savings rate: `(income - expenses) / income`.
  - Track FI progress: liquid assets toward $3.3M target.

**Guard:** Correlation must not create duplicate transactions in Search Engine.

---

### Phase 7 (P2): Audit + Alerting

**Goal:** Enable PAI to proactively identify financial anomalies and generate audit reports.

**Steps:**
- [ ] 8.1 — Implement `AnomalyDetector.swift`:
  - Unusual transaction amounts (> 2σ from account mean).
  - New merchants not seen in prior 90 days.
  - Duplicate charges (same merchant + amount within 24 hours).
  - Subscription price increases (recurring transaction amount increased > 5%).
  - Missing expected recurring transactions (e.g., no mortgage payment this month).
- [ ] 8.2 — Implement weekly audit report:
  - Summarize anomalies for the week.
  - Write to `20_Banking/audits/{yyyy-Www}.json`.
  - Ingest into Search Engine for natural language queries.
- [ ] 8.3 — Implement Freedom Acceleration scorecard:
  - Weekly Freedom Velocity Score (5 metrics from 12WY plan).
  - Monthly wealth building progress vs targets.
  - War chest accumulation tracking (target: $30K/mo starting April 2026).
  - Write to `20_Banking/scorecards/{yyyy-MM}.json`.

**Guard:** Validate anomaly detection against 30 days of historical data before enabling alerts (no false positives).

---

## Testing & Verification Protocol

### Execution Loop (Per Phase)

```
1. Implement phase code changes
2. swift build — verify compilation (zero warnings in Swift 6 strict concurrency)
3. swift test — run unit tests
4. .build/debug/finance-pull <command> --dry-run — verify against live data
5. .build/debug/finance-pull <command> — write to VRAM, verify files
6. Read written files — validate JSON structure
7. If any check fails → fix → restart from step 2
```

### Verification Checklist

| ID | Phase | Check | Method | Pass Criteria |
|----|-------|-------|--------|---------------|
| V-1 | 1 | Swift package builds | `swift build` | Exit code 0, zero errors |
| V-2 | 1 | Keychain store/retrieve | Unit test | Store → retrieve → values match |
| V-3 | 1 | SimpleFin auth succeeds | `finance-pull setup --token <token>` | Returns account list with balances |
| V-4 | 1 | Account types classified | Manual review | Checking, savings, credit cards, mortgages identified |
| V-5 | 2 | Transactions normalized | Read output JSON | All fields populated, dates valid, amounts Decimal |
| V-6 | 2 | Dedup prevents duplicates | Run pull twice | Second run reports 0 new transactions |
| V-7 | 2 | QBO transactions parsed | `finance-pull pull` | Invoices, purchases, payments mapped correctly |
| V-8 | 3 | Snapshot file written | `ls -la .../20_Banking/snapshots/` | Today's file exists, valid JSON |
| V-9 | 3 | Transaction JSONL written | `ls -la .../20_Banking/transactions/2026-03/` | Per-account files exist, valid JSONL |
| V-10 | 3 | Net worth calculated | Read snapshot | `totals.netWorth` matches manual calculation |
| V-11 | 4 | Categorization runs | `finance-pull categorize` | >70% transactions have category |
| V-12 | 4 | Monthly summary accurate | Cross-check vs bank statement | Income/expense within $10 of bank |
| V-13 | 5 | Release binary builds | `swift build -c release` | Exit code 0, binary at `.build/release/finance-pull` |
| V-14 | 5 | Launch agent loads | `launchctl list \| grep finance-pull` | Agent listed |
| V-15 | 5 | Automated run completes | Check `~/Library/Logs/vram/finance-pull/pull.log` | Success entry with timestamp |
| V-16 | 6 | QBO correlation | Read output | HVM distributions tracked, discrepancies flagged |
| V-17 | 7 | Anomaly detection | Inject test anomaly | Anomaly detected and reported |

---

## Files to Modify

| File | Phase | Change |
|------|-------|--------|
| `Package.swift` | 1 | Swift package manifest |
| `Sources/FinancePull/FinancePull.swift` | 1, 6 | @main entry, ArgumentParser root command |
| `Sources/FinancePull/Commands/SetupCommand.swift` | 1 | SimpleFin token exchange |
| `Sources/FinancePull/Commands/PullCommand.swift` | 3 | Fetch + normalize + dedup + write |
| `Sources/FinancePull/Commands/CategorizeCommand.swift` | 4 | Run categorization |
| `Sources/FinancePull/Commands/SummaryCommand.swift` | 4 | Generate monthly summary |
| `Sources/FinanceKit/API/SimpleFinClient.swift` | 1 | URLSession-based API client |
| `Sources/FinanceKit/Auth/KeychainManager.swift` | 1 | SecItem credential storage |
| `Sources/FinanceKit/Models/Account.swift` | 1 | Codable account model |
| `Sources/FinanceKit/Models/Transaction.swift` | 1, 2 | Codable transaction model |
| `Sources/FinanceKit/Models/BalanceSnapshot.swift` | 3 | Codable snapshot model |
| `Sources/FinanceKit/Models/MonthlySummary.swift` | 4 | Codable summary model |
| `Sources/FinanceKit/Normalize/Normalizer.swift` | 2 | SimpleFin → unified format |
| `Sources/FinanceKit/Normalize/Deduplicator.swift` | 2 | Transaction dedup engine |
| `Sources/FinanceKit/Normalize/QBOReader.swift` | 2 | QBO CSV parser |
| `Sources/FinanceKit/Categorize/Categorizer.swift` | 4 | Rule-based + PAI categorization |
| `Sources/FinanceKit/Categorize/MerchantMap.swift` | 4 | Merchant → category lookup |
| `Sources/FinanceKit/Persist/VRAMWriter.swift` | 3 | FileManager-based persistence |
| `Sources/FinanceKit/Persist/StateManager.swift` | 2 | Sync state tracking |
| `Sources/FinanceKit/Audit/AnomalyDetector.swift` | 7 | Anomaly detection |
| `Sources/FinanceKit/Audit/FreedomTracker.swift` | 3, 6 | $6,058/week velocity tracker |
| `com.vram.finance-pull.plist` | 5 | Launch agent definition |
| `.gitignore` | 1 | Exclude state/, .build/, credentials |

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| SimpleFin rate limit exceeded (token disabled) | HIGH | Run only 2x/day (well within 24/day limit). Track quota. Alert on warning-level errors. |
| SimpleFin Access URL revoked | MEDIUM | Detect 403 → `KeychainManager.delete()` → log error → voice notify. Keep `setup` command ready for re-auth. |
| Transaction dedup fails (duplicates) | MEDIUM | Primary dedup on `transaction.id` (unique per SimpleFin). Secondary fuzzy match. State file tracks all seen IDs. |
| QBO and SimpleFin show same HVM account | HIGH | Cross-reference by institution + last-4 digits. Tag `source` on every transaction. Never merge — keep both for audit trail. |
| Swift 6 strict concurrency violations | MEDIUM | Design with actors + Sendable from day one. `URLSession` is already Sendable. All models are structs (value types = Sendable). |
| VRAM volume unmounted during write | MEDIUM | Check `FileManager.default.fileExists(atPath: "/Volumes/VRAM")` before write. Exit code 2 if missing. Launch agent retries on next scheduled run. |
| Credential leak (Access URL committed to git) | HIGH | Credentials stored in macOS Keychain (encrypted, per-user), never on disk. `.gitignore` excludes `state/`, `.build/`. |
| Large JSONL files over months | LOW | Monthly partitioning (~500-1000 txns/month). JSONL is append-friendly and grep-friendly. |

---

## Security Considerations

- **Credentials:** SimpleFin Access URL stored in macOS Keychain via `SecItemAdd` — encrypted at rest by the OS, per-user access, never on filesystem. Per `.../Security/using-the-keychain-to-manage-user-secrets/README.md`.
- **Data at rest:** VRAM is encrypted APFS. No additional encryption needed.
- **Data in transit:** `URLSession` enforces HTTPS by default (App Transport Security). Per `.../Foundation/URLSession/README.md`.
- **No mutations:** SimpleFin is read-only. This tool cannot move money.
- **QBO data:** Read-only consumption of existing CSV exports. Never writes to QBO.

---

## Relationship to Existing Systems

| System | Relationship |
|--------|-------------|
| **Search Engine** (`/Volumes/VRAM/00-09_System/01_Tools/search_engine/`) | Future phase: financial data can be ingested as a new source alongside files, email, Slack, transcripts. Not in scope for this PRD. |
| **QBO Dump** (`/Volumes/VRAM/00-09_System/01_Tools/qbo-dump/`) | Continues running independently. This tool reads its CSV output. No modification to QBO dump. |
| **12WY Goals** (`/Volumes/VRAM/30-39_Personal/34_Goals/12WY-Q1-2026/plan/`) | Freedom Velocity Score and wealth building metrics feed directly from this tool's output. Goal #7 (Family Money Dashboard) is the primary consumer. |
| **Actual Budget** (Railway instance) | Can be decommissioned once this pipeline is verified. Attack surface eliminated. |
| **Existing Launch Agents** | Joins `com.vram.qbo-dump`, `com.vram.email-sync`, `com.vram.slack-sync`, `com.vram.fathom-sync` in the VRAM automation fleet. Same pattern: twice daily, log to `~/Library/Logs/vram/`, `RunAtLoad: true`. |

---

## Dependencies

| Dependency | Source | Purpose |
|------------|--------|---------|
| `swift-argument-parser` 1.5+ | github.com/apple/swift-argument-parser | CLI subcommands, flags, options |
| Foundation (stdlib) | Apple SDK | URLSession, JSONCoder, FileManager, Data, Calendar, ISO8601DateFormatter |
| Security (stdlib) | Apple SDK | SecItem Keychain APIs |
| os (stdlib) | Apple SDK | Logger structured logging |

One external dependency. Everything else is Apple platform SDK.

---

## Success Criteria

When all phases are complete, Ron can:

1. **Ask PAI:** "How much did I spend on food this month?" → PAI reads VRAM categorized summary JSON, returns breakdown
2. **Ask PAI:** "What's my Freedom Velocity score?" → PAI reads latest snapshot, returns weekly non-W2 take-home vs $6,058 target
3. **Ask PAI:** "Any unusual charges this week?" → PAI reads audit report JSON, surfaces anomalies
4. **Ask PAI:** "What's my net worth?" → PAI reads latest snapshot, returns assets, liabilities, and trend
5. **Ask PAI:** "How's the debt paydown going?" → PAI reads snapshot history, returns credit card trajectory with projected zero dates
6. **Ask PAI:** "Show me HVM outstanding invoices" → PAI reads QBO correlation output, surfaces A/R with aging

All automated. Twice daily. Native Swift binary on Apple Silicon. One external dependency. No runtime to install. No ActualBudget. No database to maintain. Just VRAM files + SimpleFin + Keychain.
