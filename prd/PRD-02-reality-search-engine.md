# PRD-02: TheEddingsIndex — Swift Multiplatform Personal Intelligence Platform

**Status:** DRAFT
**Date:** 2026-03-15
**Author:** PAI
**Target:** Build a native Swift multiplatform app (macOS + iOS) using SQLite FTS5, USearch HNSW, and iCloud sync — a new personal intelligence platform that reads existing VRAM data alongside new data sources
**Predecessor:** PRD-01 (VRAM Finance Pipeline — finance module becomes Phase 2 of this PRD)

---

## Executive Summary

Ron has built 30+ tools on VRAM, indexed 382K embeddings across 912K files, and runs 28 launch agents pulling from email, Slack, Fathom, QBO, CalDAV, and Mozilla. The VRAM Search Engine (TypeScript/Bun, PostgreSQL + pgvector, Qwen3-VL embedding server) proved the concept. Now it's time to ship the product.

**The gap:** The current search infrastructure is desktop-only — inaccessible from mobile, with no cross-device sync. Ron's 2TB iPhone sits idle while 665GB of meeting recordings, 282K email chunks, and $2.29M in business data live on a desktop volume with no mobile search experience.

**The fix:** Build a native Swift multiplatform app (`TheEddingsIndex`) using:
- **SQLite + FTS5** (via GRDB.swift) for full-text search with BM25 relevance ranking — better out-of-box relevance than PostgreSQL's tsvector (term saturation + document length normalization), though loses PostgreSQL's proximity operators (`<N>` tsquery)
- **USearch HNSW** for semantic vector search — 10-100x faster than pgvector, runs embedded
- **Dual embeddings** — 4096-dim CoreML Qwen3 on macOS, 512-dim NaturalLanguage on iOS
- **iCloud sync** via `CKSyncEngine` — SQLite metadata + 512-dim vectors sync across devices
- **SwiftUI** multiplatform app with `NavigationSplitView` (macOS) and `TabView` (iOS)
- **Three targets, one codebase** — `EddingsKit` (shared library), `ei-cli` (launch agent), `TheEddingsIndex.app` (SwiftUI)

**Existing tools are NOT modified.** The TypeScript search engine, PostgreSQL, launch agents, and all Bun scripts continue running unchanged. They write to VRAM disk — TheEddingsIndex reads from VRAM disk. No migration pressure. If TheEddingsIndex proves itself over time, existing tools can be retired at Ron's discretion. Until then, both systems coexist.

**Scope:**
- **In scope:** SQLite + FTS5 + USearch storage layer, data import from PostgreSQL (one-time copy), finance pipeline (SimpleFin + QBO), dual embedding strategy, SwiftUI app (macOS + iOS), iCloud sync, Conversift integration, WidgetKit + AppIntents, EddingsIndex launch agent (additive)
- **NOT in scope:** Modifying existing TypeScript/Bun scripts, stopping existing launch agents, shutting down PostgreSQL, changing the search engine API
- **Out of scope:** App Store distribution (Developer ID only for now), multi-user sharing, Android, web interface

**PAI owns the full implementation and test-iterate-fix cycle.**

---

## Background & Prior Art

### Current Architecture (Continues Running — Not Modified)

Existing TypeScript/Bun tools write data to VRAM disk. TheEddingsIndex reads from the same VRAM disk. No modification to existing scripts.

| Component | Tech | Status |
|-----------|------|--------|
| Search Engine API | TypeScript + Bun (`server.ts`) | Keeps running — PAI continues using `curl localhost:3000` |
| PostgreSQL | pgvector + tsvector | Keeps running — existing 382K embeddings preserved |
| Email sync | TypeScript (`email-indexer.ts`) | Keeps running — writes to VRAM, TheEddingsIndex reads from VRAM |
| Slack sync | TypeScript (`slack-indexer.ts`) | Keeps running — writes to VRAM, TheEddingsIndex reads from VRAM |
| File indexing | TypeScript (`pgvector-indexer.ts`) | Keeps running — writes to VRAM, TheEddingsIndex reads from VRAM |
| Transcript indexing | TypeScript (`transcript-indexer.ts`) | Keeps running — writes to VRAM, TheEddingsIndex reads from VRAM |
| QBO dump | Bun launch agent | Keeps running — writes CSVs, TheEddingsIndex reads CSVs |
| 28 launch agents | Various | All keep running unchanged |

### SimpleFin Bridge API

Per PRD-01: read-only access to 10,000+ financial institutions. Three-step auth: Setup Token (Base64 decoded via `Data(base64Encoded:)` per `.../Foundation/Data/README.md`) → Claim Exchange (POST via `URLSession` per `.../Foundation/URLSession/README.md`) → Access URL stored in Keychain (per `.../Security/SecItemAdd(____).md`). 90-day max history, ~24 requests/day, read-only.

### Conversift Integration Points

Conversift is a 13-module Swift package at `/Volumes/VRAM/00-09_System/01_Tools/conversift/cy-conversift/`:

| Module | Purpose | Integration |
|--------|---------|-------------|
| `CaptureKit` | Real-time audio capture (system + mic) | Transcript chunks flow to EddingsKit |
| `DiarizationKit` | Speaker identification via voice embeddings | Speaker → Contact linking |
| `AIKit` | CoreML inference providers | Shared embedding infrastructure |
| `DataKit` | Data models and persistence | Shared model layer |
| `Shared` | Common utilities | Shared between both packages |
| `IntelligenceKit` | AI-powered analysis | Query augmentation |

### Existing Data Volume

| Source | Records | Storage | Index Type |
|--------|---------|---------|-----------|
| Files (VRAM) | 912K indexed | 7.5GB metadata | FTS + embeddings |
| Emails | 282K chunks | 8.1GB raw JSON | FTS + embeddings |
| Slack | 13.5K chunks | Part of comms | FTS + embeddings |
| Meetings | 212 in Q1 2026 | 665GB recordings | Transcript FTS + embeddings |
| Transcripts | ~87K chunks | Part of meetings | FTS + embeddings |
| Finance | Not yet indexed | QBO CSVs exist | PRD-01 scope |

---

## Architecture

### Swift Package Structure

Per `.../PackageDescription/README.md` and `.../PackageDescription/Target/README.md`:

```
TheEddingsIndex/
├── Package.swift
├── Sources/
│   ├── EddingsKit/                    # Library target (macOS + iOS)
│   │   ├── Models/
│   │   │   ├── Document.swift         # Indexed file metadata
│   │   │   ├── EmailChunk.swift       # Email message chunk
│   │   │   ├── SlackChunk.swift       # Slack message chunk
│   │   │   ├── TranscriptChunk.swift  # Meeting transcript chunk
│   │   │   ├── Transaction.swift      # Financial transaction
│   │   │   ├── Contact.swift          # Person in the graph
│   │   │   ├── Company.swift          # Organization
│   │   │   ├── Meeting.swift          # Meeting metadata
│   │   │   ├── BalanceSnapshot.swift  # Daily financial snapshot
│   │   │   ├── MonthlySummary.swift   # Categorized monthly summary
│   │   │   ├── SearchResult.swift     # Unified search result
│   │   │   └── SyncState.swift        # Per-source sync state
│   │   ├── Storage/
│   │   │   ├── DatabaseManager.swift  # GRDB + FTS5 schema + migrations
│   │   │   ├── FTSIndex.swift         # FTS5 table management
│   │   │   ├── VectorIndex.swift      # USearch HNSW wrapper
│   │   │   ├── VRAMWriter.swift       # JSON/JSONL file persistence
│   │   │   └── StateManager.swift     # Sync state per source
│   │   ├── Search/
│   │   │   ├── QueryEngine.swift      # Unified search orchestrator
│   │   │   ├── FTSSearch.swift        # SQLite FTS5 BM25 queries
│   │   │   ├── SemanticSearch.swift   # USearch cosine similarity
│   │   │   └── HybridRanker.swift     # RRF fusion algorithm
│   │   ├── Embedding/
│   │   │   ├── EmbeddingProvider.swift # Protocol for embedding backends
│   │   │   ├── NLEmbedder.swift       # NaturalLanguage 512-dim (macOS + iOS)
│   │   │   └── CoreMLEmbedder.swift   # Qwen3 4096-dim (macOS only)
│   │   ├── Sync/
│   │   │   ├── SimpleFinClient.swift  # SimpleFin API client
│   │   │   ├── QBOReader.swift        # QBO CSV parser
│   │   │   ├── IMAPClient.swift       # Email sync via IMAP
│   │   │   ├── SlackClient.swift      # Slack export/API reader
│   │   │   ├── FathomClient.swift     # Fathom meeting sync
│   │   │   ├── CalDAVClient.swift     # Calendar sync
│   │   │   └── FileScanner.swift      # VRAM filesystem indexer
│   │   ├── Normalize/
│   │   │   ├── Normalizer.swift       # Unified data transformation
│   │   │   ├── Deduplicator.swift     # Cross-source dedup
│   │   │   ├── SmartChunker.swift     # Semantic text chunking
│   │   │   └── ContactExtractor.swift # Auto-extract contacts from content
│   │   ├── Categorize/
│   │   │   ├── Categorizer.swift      # Transaction categorization
│   │   │   └── MerchantMap.swift      # Merchant → category lookup
│   │   ├── Intelligence/
│   │   │   ├── FreedomTracker.swift   # $6,058/week velocity
│   │   │   ├── AnomalyDetector.swift  # Unusual transaction detection
│   │   │   ├── RelationshipScorer.swift # Contact interaction depth
│   │   │   └── ActivityDigest.swift   # Daily/weekly summaries
│   │   ├── CloudSync/
│   │   │   └── iCloudManager.swift    # CKSyncEngine wrapper
│   │   └── Auth/
│   │       └── KeychainManager.swift  # SecItem credential storage
│   │
│   ├── EddingsCLI/                    # Executable target (macOS only)
│   │   ├── EddingsCLI.swift           # @main ArgumentParser root
│   │   └── Commands/
│   │       ├── SyncCommand.swift      # Pull all data sources
│   │       ├── IndexCommand.swift     # Rebuild FTS5 + USearch indexes
│   │       ├── SearchCommand.swift    # CLI search query
│   │       ├── MigrateCommand.swift   # Import from PostgreSQL
│   │       └── StatusCommand.swift    # Health + stats
│   │
│   ├── EddingsApp/                    # SwiftUI app target (macOS + iOS)
│   │   ├── EddingsApp.swift           # @main App
│   │   ├── Navigation/
│   │   │   ├── AppSidebar.swift       # macOS NavigationSplitView
│   │   │   └── AppTabBar.swift        # iOS TabView
│   │   ├── Search/
│   │   │   ├── SearchView.swift
│   │   │   └── SearchResultRow.swift
│   │   ├── Finance/
│   │   │   ├── FreedomDashboard.swift
│   │   │   ├── TransactionList.swift
│   │   │   └── NetWorthView.swift
│   │   ├── Meetings/
│   │   │   ├── MeetingList.swift
│   │   │   └── TranscriptView.swift
│   │   ├── Contacts/
│   │   │   ├── ContactList.swift
│   │   │   └── ContactDetail.swift
│   │   └── Settings/
│   │       └── SettingsView.swift
│   │
│   └── EddingsWidgets/               # Widget extension target (iOS + macOS)
│       ├── FreedomVelocityWidget.swift
│       ├── NetWorthWidget.swift
│       └── UpcomingWidget.swift
│
├── Tests/
│   └── EddingsKitTests/
│       ├── FTSSearchTests.swift
│       ├── SemanticSearchTests.swift
│       ├── HybridRankerTests.swift
│       ├── NormalizerTests.swift
│       ├── DeduplicatorTests.swift
│       ├── SimpleFinClientTests.swift
│       └── CategorizerTests.swift
│
├── Models/                            # CoreML models (macOS)
│   └── Qwen3Embedding.mlmodel
├── com.vram.eddings-index.plist             # Launch agent
└── Resources/
    └── merchant-map.json              # Merchant → category seed data
```

### Package.swift

Per `.../PackageDescription/README.md`, `.../PackageDescription/SupportedPlatform/README.md`, `.../PackageDescription/SwiftLanguageMode/README.md`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheEddingsIndex",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "EddingsKit", targets: ["EddingsKit"]),
        .executable(name: "ei-cli", targets: ["EddingsCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/unum-cloud/usearch", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "EddingsKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "USearch", package: "usearch"),
            ]
        ),
        .executableTarget(
            name: "EddingsCLI",
            dependencies: [
                "EddingsKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "EddingsKitTests",
            dependencies: ["EddingsKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
```

**Xcode project required:** SwiftPM can only produce library targets (`EddingsKit`) and executable targets (`ei-cli`). SwiftUI app targets (`.app`) and WidgetKit extension targets cannot be declared in `Package.swift` — they require an Xcode project (`.xcodeproj` or workspace). The project imports `EddingsKit` as a local Swift package dependency. The `Package.swift` above defines the library and CLI; Xcode targets for `TheEddingsIndex.app` and `EddingsWidgets` are defined in the `.xcodeproj`.

**Platform choice:** macOS 15+ / iOS 18+ gives access to `Mutex` (per `.../Synchronization/Mutex/README.md`), `@Observable` (per `.../Observation/README.md`), `CKSyncEngine` (per `.../CloudKit/CKSyncEngine-5sie5/README.md`), `NavigationSplitView` (per `.../SwiftUI/NavigationSplitView/README.md`), modern `Logger` (per `.../os/Logger/README.md`), and Swift 6 strict concurrency.

**Three external dependencies:**

| Dependency | Purpose | Why not Apple SDK |
|------------|---------|-------------------|
| `GRDB.swift` 7.0+ | SQLite wrapper with FTS5, migrations, WAL mode, Codable record mapping | Apple's SQLite C API has no Swift wrapper. SwiftData doesn't expose FTS5. |
| `USearch` 2.0+ | HNSW vector index, 10-100x faster than pgvector, disk persistence + mmap | No Apple framework provides vector similarity search with HNSW indexing. |
| `swift-argument-parser` 1.5+ | CLI subcommands for launch agent binary | No Foundation equivalent for declarative CLI parsing. |

**Everything else is Apple SDK:** `URLSession`, `JSONDecoder`/`JSONEncoder`, `FileManager`, `SecItem`, `Logger`, `NLEmbedding`, `CoreML`, `CKSyncEngine`, `SwiftUI`, `WidgetKit`, `AppIntents`, `CoreSpotlight`.

### SQLite Schema

GRDB.swift uses Swift migrations (per GRDB documentation). Schema designed to mirror the current PostgreSQL tables but with FTS5 virtual tables for full-text search and separate USearch indexes for semantic search.

```swift
var migrator = DatabaseMigrator()

migrator.registerMigration("v1_core_tables") { db in

    // -- Documents (VRAM indexed files) --
    try db.create(table: "documents") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("path", .text).notNull().unique()
        t.column("filename", .text).notNull()
        t.column("content", .text)
        t.column("extension", .text)
        t.column("fileSize", .integer)
        t.column("modifiedAt", .datetime)
        t.column("area", .text)
        t.column("category", .text)
        t.column("contentType", .text)
    }

    // -- FTS5 virtual table for documents --
    try db.create(virtualTable: "documents_fts", using: FTS5()) { t in
        t.synchronize(withTable: "documents")
        t.tokenizer = .unicode61()
        t.column("filename").notNull() // BM25 weight applied at QUERY time via bm25() args, not schema time
        t.column("content")
    }

    // -- Email chunks --
    try db.create(table: "emailChunks") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("emailId", .text).notNull().unique()
        t.column("emailPath", .text)
        t.column("subject", .text)
        t.column("fromName", .text)
        t.column("fromEmail", .text)
        t.column("toEmails", .text) // JSON array
        t.column("ccEmails", .text) // JSON array
        t.column("chunkText", .text)
        t.column("chunkIndex", .integer)
        t.column("labels", .text) // JSON array
        t.column("emailDate", .datetime)
        t.column("year", .integer)
        t.column("month", .integer)
        t.column("quarter", .integer)
        t.column("isSentByMe", .boolean).defaults(to: false)
        t.column("hasAttachments", .boolean).defaults(to: false)
        t.column("isReply", .boolean).defaults(to: false)
        t.column("threadId", .text)
        t.column("fromContactId", .integer)
            .references("contacts", onDelete: .setNull)
    }

    try db.create(virtualTable: "emailChunks_fts", using: FTS5()) { t in
        t.synchronize(withTable: "emailChunks")
        t.tokenizer = .unicode61()
        t.column("subject").notNull() // BM25 weight applied at QUERY time via bm25() args, not schema time
        t.column("fromName").notNull() // BM25 weight applied at QUERY time via bm25() args, not schema time
        t.column("chunkText")
    }

    // -- Slack chunks --
    try db.create(table: "slackChunks") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("channel", .text)
        t.column("channelType", .text)
        t.column("speakers", .text) // JSON array
        t.column("chunkText", .text)
        t.column("messageDate", .datetime)
        t.column("year", .integer)
        t.column("month", .integer)
        t.column("hasFiles", .boolean).defaults(to: false)
        t.column("hasReactions", .boolean).defaults(to: false)
        t.column("threadTs", .text)
        t.column("isThreadReply", .boolean).defaults(to: false)
    }

    try db.create(virtualTable: "slackChunks_fts", using: FTS5()) { t in
        t.synchronize(withTable: "slackChunks")
        t.tokenizer = .unicode61()
        t.column("channel").notNull() // BM25 weight applied at QUERY time via bm25() args, not schema time
        t.column("chunkText")
    }

    // -- Transcript chunks --
    try db.create(table: "transcriptChunks") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("filePath", .text)
        t.column("chunkText", .text)
        t.column("chunkIndex", .integer)
        t.column("speakers", .text) // JSON array
        t.column("speakerName", .text)
        t.column("meetingId", .text)
        t.column("year", .integer)
        t.column("month", .integer)
    }

    try db.create(virtualTable: "transcriptChunks_fts", using: FTS5()) { t in
        t.synchronize(withTable: "transcriptChunks")
        t.tokenizer = .unicode61()
        t.column("speakerName").notNull() // BM25 weight applied at QUERY time via bm25() args, not schema time
        t.column("chunkText")
    }

    // -- Financial transactions --
    try db.create(table: "financialTransactions") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("transactionId", .text).notNull().unique()
        t.column("source", .text).notNull() // simplefin | qbo
        t.column("accountId", .text).notNull()
        t.column("accountName", .text)
        t.column("institution", .text)
        t.column("transactionDate", .datetime).notNull()
        t.column("amount", .double).notNull()
        t.column("description", .text)
        t.column("payee", .text)
        t.column("category", .text)
        t.column("subcategory", .text)
        t.column("isRecurring", .boolean).defaults(to: false)
        t.column("isTransfer", .boolean).defaults(to: false)
        t.column("tags", .text) // JSON array
        t.column("year", .integer)
        t.column("month", .integer)
        t.column("categoryModifiedAt", .datetime) // Field-level timestamp for conflict resolution
        // Prevents bulk import from overwriting manual user categorization on iOS.
        // CKSyncEngine conflict resolution: compare categoryModifiedAt, not record modifiedAt.
    }

    try db.create(virtualTable: "financialTransactions_fts", using: FTS5()) { t in
        t.synchronize(withTable: "financialTransactions")
        t.tokenizer = .unicode61()
        t.column("payee").notNull() // BM25 weight applied at QUERY time via bm25() args, not schema time
        t.column("description").notNull() // BM25 weight applied at QUERY time via bm25() args, not schema time
        t.column("category")
    }

    // -- Contacts --
    try db.create(table: "contacts") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("name", .text).notNull()
        t.column("email", .text)
        t.column("companyId", .integer).references("companies", onDelete: .setNull)
        t.column("slackUserId", .text)
        t.column("role", .text)
        t.column("isMe", .boolean).defaults(to: false)
        t.column("firstSeenAt", .datetime)
        t.column("lastSeenAt", .datetime)
        t.column("emailCount", .integer).defaults(to: 0)
        t.column("meetingCount", .integer).defaults(to: 0)
        t.column("slackCount", .integer).defaults(to: 0)
        t.column("tags", .text) // JSON array
        t.column("notes", .text)
    }

    // -- Companies --
    try db.create(table: "companies") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("name", .text).notNull()
        t.column("domain", .text).unique()
        t.column("aliases", .text) // JSON array
        t.column("industry", .text)
        t.column("isCustomer", .boolean).defaults(to: false)
        t.column("isPartner", .boolean).defaults(to: false)
        t.column("isProspect", .boolean).defaults(to: false)
        t.column("notes", .text)
    }

    // -- Meetings --
    try db.create(table: "meetings") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("meetingId", .text).notNull().unique()
        t.column("title", .text)
        t.column("startTime", .datetime)
        t.column("endTime", .datetime)
        t.column("durationMinutes", .integer)
        t.column("year", .integer)
        t.column("month", .integer)
        t.column("isInternal", .boolean).defaults(to: false)
        t.column("participantCount", .integer)
        t.column("videoUrl", .text)
        t.column("filePath", .text)
    }

    // -- Financial snapshots --
    try db.create(table: "financialSnapshots") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("snapshotDate", .date).notNull()
        t.column("accountId", .text).notNull()
        t.column("accountName", .text)
        t.column("institution", .text)
        t.column("accountType", .text)
        t.column("balance", .double).notNull()
        t.column("availableBalance", .double)
        t.column("currency", .text).defaults(to: "USD")
        t.column("source", .text).notNull()
        t.uniqueKey(["snapshotDate", "accountId", "source"])
    }

    // -- Pending embeddings (crash recovery for USearch consistency) --
    // USearch add() is NOT transactional. If app crashes after adding vectors
    // but before save(), those vectors are lost but SQLite still shows records
    // as "indexed." This table tracks which records have been committed to the
    // USearch index file via a successful save().
    try db.create(table: "pendingEmbeddings") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("sourceTable", .text).notNull() // e.g., "emailChunks"
        t.column("sourceId", .integer).notNull()
        t.column("vector512", .blob)              // Raw Float array as Data
        t.column("vector4096", .blob)             // macOS only, nil on iOS
        t.column("createdAt", .datetime).defaults(to: "CURRENT_TIMESTAMP")
    }
    // Workflow: insert into pendingEmbeddings → add to USearch in-memory →
    // save() USearch to disk → DELETE from pendingEmbeddings.
    // On startup: any rows still in pendingEmbeddings = crash recovery needed.
    // Re-add those vectors to USearch and save again.

    // -- Indexes --
    try db.create(index: "idx_email_date", on: "emailChunks", columns: ["emailDate"])
    try db.create(index: "idx_email_contact", on: "emailChunks", columns: ["fromContactId"])
    try db.create(index: "idx_slack_date", on: "slackChunks", columns: ["messageDate"])
    try db.create(index: "idx_transcript_meeting", on: "transcriptChunks", columns: ["meetingId"])
    try db.create(index: "idx_txn_date", on: "financialTransactions", columns: ["transactionDate"])
    try db.create(index: "idx_txn_category", on: "financialTransactions", columns: ["category"])
    try db.create(index: "idx_meeting_date", on: "meetings", columns: ["startTime"])
    try db.create(index: "idx_contact_email", on: "contacts", columns: ["email"])
    try db.create(index: "idx_snap_date", on: "financialSnapshots", columns: ["snapshotDate"])
}
```

FTS5 with `synchronize(withTable:)` automatically keeps the FTS index in sync with the content table — inserts, updates, and deletes propagate without manual triggers.

**BM25 column weighting is applied at QUERY time, not schema time.** GRDB does not expose a `columnWeight` API — this is a raw SQLite FTS5 feature. Weights are passed as arguments to the `bm25()` ranking function in the ORDER BY clause:

```swift
// FTSSearch.swift — query-time BM25 column weights
// For emailChunks_fts: subject=3x, fromName=2x, chunkText=1x
let sql = """
    SELECT emailChunks.*, bm25(emailChunks_fts, 3.0, 2.0, 1.0) AS rank
    FROM emailChunks_fts
    JOIN emailChunks ON emailChunks.rowid = emailChunks_fts.rowid
    WHERE emailChunks_fts MATCH ?
    ORDER BY rank
    LIMIT ?
    """
let results = try db.execute(sql: sql, arguments: [query, limit])
```

FTS5 also supports `NEAR(term1 term2, N)` for proximity search, partially replacing PostgreSQL's `<N>` tsquery operator. Per SQLite FTS5 documentation.

### USearch Vector Index Architecture

Two separate USearch indexes, persisted to disk:

| Index | Dimensions | Platform | Sync | Purpose |
|-------|-----------|----------|------|---------|
| `reality-4096.usearch` | 4096 | macOS only | No | Deep semantic search with Qwen3 CoreML embeddings |
| `reality-512.usearch` | 512 | macOS + iOS | Yes (iCloud) | Mobile-compatible semantic search with NaturalLanguage embeddings |

**Memory footprint at 382K vectors (Float32):**

| Index | Per Vector | Total Raw | HNSW Overhead (M=16) | Total RAM |
|-------|-----------|----------|---------------------|-----------|
| 512-dim (Float32) | 2KB | 764MB | ~24MB | ~788MB |
| 512-dim (INT8 quantized) | 512B | 196MB | ~24MB | **~220MB** |
| 4096-dim (Float32) | 16KB | 6.1GB | ~24MB | ~6.1GB |

**CRITICAL:** On iOS, widget extensions are limited to 30MB RAM. Even the main app should stay under 1GB. INT8 quantization is **mandatory** for iOS. On macOS, Float32 is acceptable for both indexes.

Per `.../Foundation/FileManager/README.md`: use `replaceItemAt(_:withItemAt:)` for atomic file swapping to prevent corruption during saves.

```swift
// VectorIndex.swift
import USearch

actor VectorIndex {
    private let index4096: USearchIndex?  // nil on iOS
    private var index512: USearchIndex   // var: generation-swapped on save (iOS mmap)
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        let path512 = directory.appending(path: "reality-512.usearch")

        #if os(iOS)
        // iOS: use mmap (view) to avoid loading entire index into RAM
        // Per USearch docs: view() maps from disk, OS pages in on demand
        index512 = USearchIndex.make(metric: .cos, dimensions: 512, connectivity: 16)
        if FileManager.default.fileExists(atPath: path512.path) {
            index512.view(path: path512.path)  // mmap — not loaded into RAM
        }
        index4096 = nil
        #else
        // macOS: load fully into RAM (plenty of memory)
        index512 = USearchIndex.make(metric: .cos, dimensions: 512, connectivity: 16)
        if FileManager.default.fileExists(atPath: path512.path) {
            index512.load(path: path512.path)
        }
        index4096 = USearchIndex.make(metric: .cos, dimensions: 4096, connectivity: 16)
        let path4096 = directory.appending(path: "reality-4096.usearch")
        if FileManager.default.fileExists(atPath: path4096.path) {
            index4096!.load(path: path4096.path)
        }
        #endif
    }

    func add(key: UInt64, vector512: [Float], vector4096: [Float]? = nil) {
        index512.add(key: key, vector: vector512)
        #if os(macOS)
        if let v4096 = vector4096 {
            index4096?.add(key: key, vector: v4096)
        }
        #endif
    }

    func search(vector: [Float], count: Int = 20) -> [(key: UInt64, distance: Float)] {
        #if os(macOS)
        if vector.count == 4096, let idx = index4096 {
            return idx.search(vector: vector, count: count)
        }
        #endif
        return index512.search(vector: vector, count: count)
    }

    /// Generation-swapping save: write to new file, create new mmap view,
    /// swap reference, let old instance deallocate (safe munmap).
    ///
    /// WARNING: Do NOT use FileManager.replaceItemAt() with an active mmap view!
    /// replaceItemAt() unlinks the old inode while mmap still references it.
    /// Any subsequent access to the old mmap triggers SIGBUS (bus error).
    /// Generation swapping avoids this by creating a new USearchIndex instance
    /// that views the new file before releasing the old one.
    func save() throws {
        // 1. Save current index to a new generation file
        let gen = Int(Date().timeIntervalSince1970)
        let newPath512 = directory.appending(path: "reality-512-\(gen).usearch")
        index512.save(path: newPath512.path)

        #if os(iOS)
        // 2. Create new index instance with mmap view of the new file
        let newIndex512 = USearchIndex.make(metric: .cos, dimensions: 512, connectivity: 16)
        newIndex512.view(path: newPath512.path)

        // 3. Swap reference (old instance deallocates, safely munmaps)
        let oldPath = directory.appending(path: "reality-512.usearch")
        index512 = newIndex512

        // 4. Clean up old generation file
        try? FileManager.default.removeItem(at: oldPath)
        try FileManager.default.moveItem(at: newPath512, to: oldPath)
        #else
        // macOS: not mmap'd, safe to use simple rename
        let finalPath512 = directory.appending(path: "reality-512.usearch")
        try? FileManager.default.removeItem(at: finalPath512)
        try FileManager.default.moveItem(at: newPath512, to: finalPath512)
        #endif

        #if os(macOS)
        if let idx4096 = index4096 {
            let newPath4096 = directory.appending(path: "reality-4096-\(gen).usearch")
            idx4096.save(path: newPath4096.path)
            let finalPath4096 = directory.appending(path: "reality-4096.usearch")
            try? FileManager.default.removeItem(at: finalPath4096)
            try FileManager.default.moveItem(at: newPath4096, to: finalPath4096)
        }
        #endif
    }
}
```

### Hybrid Search (RRF Fusion)

Same Reciprocal Rank Fusion algorithm currently in `hybrid-search.ts`, ported to Swift:

```swift
// HybridRanker.swift
struct HybridRanker {
    let ftsWeight: Double = 0.4
    let semanticWeight: Double = 0.6
    let k: Double = 60  // RRF constant

    func rank(
        ftsResults: [(id: Int64, score: Double)],
        semanticResults: [(id: Int64, distance: Float)]
    ) -> [RankedResult] {
        var scores: [Int64: Double] = [:]

        for (rank, result) in ftsResults.enumerated() {
            scores[result.id, default: 0] += ftsWeight * (1.0 / (k + Double(rank + 1)))
        }

        for (rank, result) in semanticResults.enumerated() {
            scores[result.id, default: 0] += semanticWeight * (1.0 / (k + Double(rank + 1)))
        }

        return scores
            .sorted { $0.value > $1.value }
            .map { RankedResult(id: $0.key, score: $0.value) }
    }
}
```

### Embedding Provider Protocol

```swift
// EmbeddingProvider.swift
protocol EmbeddingProvider: Sendable {
    var dimensions: Int { get }
    func embed(_ text: String) async throws -> [Float]
    func embedBatch(_ texts: [String]) async throws -> [[Float]]
}
```

Per `.../NaturalLanguage/README.md` — `NLEmbedding` provides sentence embeddings on iOS 13+ and macOS 10.15+:

```swift
// NLEmbedder.swift (iOS + macOS)
import NaturalLanguage

struct NLEmbedder: EmbeddingProvider {
    let dimensions = 512

    /// Embeds text using NLEmbedding with automatic language detection.
    /// Per .../NaturalLanguage/README.md: NLEmbedding.sentenceEmbedding(for:) requires
    /// an explicit NLLanguage. Hardcoding .english produces garbage vectors for
    /// non-English content. Use NLLanguageRecognizer to detect language first.
    func embed(_ text: String) async throws -> [Float] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let language = recognizer.dominantLanguage ?? .english

        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            // Language not supported for sentence embeddings — fall back to English
            guard let fallback = NLEmbedding.sentenceEmbedding(for: .english) else {
                throw EmbeddingError.modelUnavailable
            }
            guard let vector = fallback.vector(for: text) else {
                throw EmbeddingError.embeddingFailed
            }
            return vector.map { Float($0) }
        }
        guard let vector = embedding.vector(for: text) else {
            throw EmbeddingError.embeddingFailed
        }
        return vector.map { Float($0) }
    }

    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for (i, text) in texts.enumerated() {
                group.addTask { (i, try await embed(text)) }
            }
            var results = Array(repeating: [Float](), count: texts.count)
            for try await (i, vec) in group { results[i] = vec }
            return results
        }
    }
}
```

Per `.../CoreML/README.md` — CoreML runs trained models on CPU/GPU/Neural Engine (iOS 11+, macOS 10.13+):

```swift
// CoreMLEmbedder.swift (macOS only)
#if os(macOS)
import CoreML

struct CoreMLEmbedder: EmbeddingProvider {
    let dimensions = 4096
    private let model: MLModel

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all  // Use Neural Engine when available
        model = try Qwen3Embedding(configuration: config).model
    }

    func embed(_ text: String) async throws -> [Float] {
        // Tokenize and run inference via CoreML
        // Implementation depends on converted model's input/output spec
    }
}
#endif
```

### iCloud Sync Architecture

Per `.../CloudKit/CKSyncEngine-5sie5/README.md` (iOS 17+, macOS 14+):

Per `.../CloudKit/CKSyncEngine-5sie5/README.md`: `CKSyncEngine` takes `(database: CKDatabase, stateSerialization: CKSyncEngine.State.Serialization?, delegate: CKSyncEngineDelegate)`. The delegate method is `handleEvent(_:syncEngine:)` which dispatches typed events (`fetchedRecordZoneChanges`, `sentRecordZoneChanges`, `stateUpdate`, `accountChange`).

```swift
// iCloudManager.swift
import CloudKit

actor iCloudManager: CKSyncEngineDelegate {
    private let syncEngine: CKSyncEngine
    private let db: DatabasePool  // GRDB — DatabasePool for concurrent access
    private let stateURL: URL     // Persisted CKSyncEngine.State.Serialization

    init(db: DatabasePool, stateDirectory: URL) throws {
        self.db = db
        self.stateURL = stateDirectory.appending(path: "ck-sync-state.dat")

        let container = CKContainer(identifier: "iCloud.com.hackervalley.eddingsindex")
        let database = container.privateCloudDatabase

        // Restore persisted state (CRITICAL: losing this = full re-fetch)
        let savedState: CKSyncEngine.State.Serialization?
        if let data = try? Data(contentsOf: stateURL) {
            savedState = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKSyncEngine.State.Serialization.self, from: data
            )
        } else {
            savedState = nil
        }

        let config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: savedState,
            delegate: self
        )
        self.syncEngine = CKSyncEngine(config)
    }

    // Per CKSyncEngineDelegate — single event handler dispatches all sync events
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let stateUpdate):
            // MUST persist state to disk — losing this forces full re-fetch
            persistState(stateUpdate.stateSerialization)

        case .accountChange(let accountChange):
            // CRITICAL: account change resets all internal state including
            // unsaved changes. Must flush pending writes to SQLite BEFORE
            // this happens. Log + notify on account switch.
            handleAccountChange(accountChange)

        case .fetchedRecordZoneChanges(let changes):
            processRemoteChanges(changes)

        case .sentRecordZoneChanges(let sentChanges):
            processSentChanges(sentChanges)

        default:
            break
        }
    }

    // Per CKSyncEngineDelegate — provide next batch of local changes to send
    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) -> CKSyncEngine.RecordZoneChangeBatch? {
        // Return batches of ~400 records max (CloudKit write limit)
        // Use CKOperationGroup with expectedSendSize = .hundredsOfMegabytes
        // during initial migration to reduce rate limiting
        return buildNextBatch(context: context)
    }

    private func persistState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: serialization, requiringSecureCoding: true
        ) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        // Per Apple docs: CKSyncEngine "resets its internal state, including
        // unsaved changes to both records and record zones" on account change.
        // Flush any pending local changes to SQLite before accepting reset.
        // Notify user that sync state was reset.
        Logger(subsystem: "com.hackervalley.eddingsindex", category: "sync")
            .warning("iCloud account changed — sync state reset. Pending changes flushed to local SQLite.")
    }
}
```

**Synced record types:** Contact, Company, FinancialTransaction, FinancialSnapshot, MonthlySummary, MerchantMapping. Search chunks (email, Slack, transcript) sync metadata only — full content stays on Mac.

**What syncs:**
- Contacts + Companies (relationship graph)
- Financial transactions + snapshots + summaries
- Categorization rules (merchant map)
- Meeting metadata (not recordings)
- Transcript text (not audio/video)
- 512-dim embedding vectors (synced as CKRecord Data blobs; USearch index rebuilt locally on each device)
- SQLite database file (metadata + FTS5)

**What stays on Mac:**
- 4096-dim USearch index
- Meeting MP4 recordings (665GB)
- Raw email JSON archives (8GB)
- Raw Slack export files
- VRAM filesystem

Per `.../CloudKit/CKContainer/README.md`: private database for user's own data. Per `.../CloudKit/CKRecord/README.md`: 1MB per record limit — all records are metadata (well under limit). Large files (recordings) never touch CloudKit.

### SwiftUI App Architecture

Per `.../SwiftUI/README.md`, `.../SwiftUI/App/README.md`, `.../SwiftUI/NavigationSplitView/README.md`:

```swift
// EddingsApp.swift
import SwiftUI

@main
struct EddingsApp: App {
    @State private var engine = TheEddingsIndex()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(engine)
        }
        #endif
    }
}

// ContentView — adapts per platform
struct ContentView: View {
    var body: some View {
        #if os(macOS)
        AppSidebar()  // NavigationSplitView
        #else
        AppTabBar()   // TabView
        #endif
    }
}
```

Per `.../Observation/README.md` — `@Observable` (iOS 17+, macOS 14+):

```swift
@Observable
final class TheEddingsIndex {
    let db: DatabaseManager
    let vectorIndex: VectorIndex
    let queryEngine: QueryEngine
    let freedomTracker: FreedomTracker

    var searchResults: [SearchResult] = []
    var freedomVelocity: FreedomVelocity?
    var netWorth: Decimal?
}
```

---

## Implementation Plan

### Phase 1 (P0): Swift Package + Storage Layer

**Goal:** Establish Swift package with GRDB + FTS5 + USearch. Prove that SQLite FTS5 BM25 matches or exceeds PostgreSQL tsvector quality.

**Steps:**
- [ ] 1.1 — Create Swift package: `swift package init --type library --name TheEddingsIndex`. Define `Package.swift` with macOS 15+ / iOS 18+ platforms, three dependencies (`GRDB.swift`, `usearch`, `swift-argument-parser`), four targets (`EddingsKit`, `EddingsCLI`, `EddingsApp`, `EddingsKitTests`). Per `.../PackageDescription/README.md`.
- [ ] 1.2 — Implement `DatabaseManager.swift` with GRDB:
  - Create `DatabaseQueue` with WAL mode for concurrent reads.
  - Register migration `v1_core_tables` with all table schemas defined above.
  - Create FTS5 virtual tables with `synchronize(withTable:)` for auto-sync.
  - Configure `unicode61()` tokenizer for international text support.
  - Set column weights for BM25 relevance (subject 3x, sender 2x, body 1x).
- [ ] 1.3 — Implement `FTSIndex.swift`:
  - `search(query: String, table: FTSTable, limit: Int) -> [(id: Int64, score: Double)]`
  - Use FTS5 `bm25()` ranking function for relevance scoring.
  - Support quoted phrases, boolean operators (AND/OR/NOT).
  - Support source filtering (email, slack, transcript, file, financial).
  - Support temporal filtering (year, month, date range).
- [ ] 1.4 — Implement `VectorIndex.swift` with USearch:
  - Initialize 512-dim and 4096-dim HNSW indexes.
  - `add(key:vector512:vector4096:)` — insert vectors.
  - `search(vector:count:)` — similarity search with cosine metric.
  - `save(directory:)` / `load(directory:)` — disk persistence.
  - Use `actor` isolation for thread safety (Swift 6 concurrency).
- [ ] 1.5 — Implement `HybridRanker.swift`:
  - RRF fusion with k=60, weights 40% FTS / 60% semantic.
  - Deduplicate results across FTS and semantic by record ID.
  - Return `[SearchResult]` with unified score.
- [ ] 1.6 — Implement `QueryEngine.swift`:
  - Orchestrate FTS5 query → semantic query → RRF fusion.
  - Accept source filter, date filter, limit.
  - Dispatch FTS and semantic searches concurrently using `async let`.
- [ ] 1.7 — Write tests: FTS5 BM25 ranking quality, USearch add/search round-trip, hybrid ranker dedup, concurrent access safety.
- [ ] 1.8 — Benchmark: compare FTS5 BM25 results vs current PostgreSQL tsvector on same query set.

**Guard:** FTS5 BM25 must return relevant results for 10 test queries that currently work in the PostgreSQL search engine.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| PackageDescription | `.../PackageDescription/README.md` | `Package` | Swift package manifest |
| PackageDescription | `.../PackageDescription/Target/README.md` | `.target()`, `.executableTarget()` | Define library + CLI targets |
| PackageDescription | `.../PackageDescription/SupportedPlatform/README.md` | `.macOS(.v15)`, `.iOS(.v18)` | Platform requirements |
| PackageDescription | `.../PackageDescription/SwiftLanguageMode/README.md` | `.v6` | Swift 6 strict concurrency |
| Synchronization | `.../Synchronization/Mutex/README.md` | `Mutex<Value>` | Thread-safe state in VectorIndex |
| os | `.../os/Logger/README.md` | `Logger(subsystem:category:)` | Structured logging |

---

### Phase 2 (P0): Finance Pipeline (PRD-01 Integrated)

**Goal:** SimpleFin API client, Keychain credential management, transaction normalization, categorization, VRAM file persistence. Identical to PRD-01 Phases 1-4 but built inside EddingsKit.

**Steps:**
- [ ] 2.1 — Implement `KeychainManager.swift`:
  - `store(key:data:)` → `SecItemAdd(_:_:)` with `kSecClassGenericPassword`. Per `.../Security/SecItemAdd(____).md`.
  - `retrieve(key:)` → `SecItemCopyMatching(_:_:)`. Per `.../Security/SecItemCopyMatching(____).md`.
  - `delete(key:)` → `SecItemDelete(_:)`. Per `.../Security/SecItemDelete(__).md`.
  - Service name: `"com.hackervalley.eddingsindex"`.
- [ ] 2.2 — Implement `SimpleFinClient.swift`:
  - Exchange setup token: decode Base64 via `Data(base64Encoded:)` (per `.../Foundation/Data/README.md`), POST to claim URL via `URLSession.shared.data(for:)` (per `.../Foundation/URLSession/README.md`).
  - Fetch accounts: GET with date params, validate `HTTPURLResponse.statusCode` (per `.../Foundation/HTTPURLResponse/README.md`).
  - Decode JSON via `JSONDecoder` with `.convertFromSnakeCase` and `.secondsSince1970`. Per `.../Foundation/JSONDecoder/README.md`.
  - Rate limiting: exponential backoff, max 3 retries.
- [ ] 2.3 — Implement `Normalizer.swift` + `Deduplicator.swift`:
  - Transform SimpleFin → `Transaction` Codable model.
  - Date extraction via `Calendar.current.dateComponents([.year, .month], from:)`. Per `.../Foundation/Calendar/README.md`.
  - Dedup on `transactionId` (primary), fuzzy match (secondary).
  - 5-day overlap window on subsequent syncs.
- [ ] 2.4 — Implement `QBOReader.swift`:
  - Parse CSV files from `/Volumes/VRAM/10-19_Work/10_Hacker_Valley_Media/10.06_finance/QuickBooksOnline/`.
  - Map to `Transaction` with `source: .qbo`.
- [ ] 2.5 — Implement `VRAMWriter.swift`:
  - Write snapshots to `20_Banking/snapshots/{date}.json` via `JSONEncoder` with `.prettyPrinted` + `.sortedKeys` (per `.../Foundation/JSONEncoder/README.md`).
  - Append transactions to `20_Banking/transactions/{yyyy-MM}/{account}.jsonl` via `FileHandle` (per `.../Foundation/FileHandle/README.md`).
  - Create directories via `FileManager.default.createDirectory(at:withIntermediateDirectories:true)` (per `.../Foundation/FileManager/README.md`).
- [ ] 2.6 — Implement `Categorizer.swift` + `MerchantMap.swift`:
  - Tier 1: exact merchant match. Tier 2: regex patterns. Tier 3: amount heuristics. Tier 4: PAI inference via `Process` (per `.../Foundation/Process/README.md`).
- [ ] 2.7 — Implement `FreedomTracker.swift`:
  - Calculate weekly non-W2 take-home vs $6,058 target.
  - Track debt paydown velocity, net worth, savings rate.
- [ ] 2.8 — Insert all financial data into SQLite tables + FTS5 indexes.
- [ ] 2.9 — Write tests for SimpleFin client, normalization, dedup, categorization.

**Guard:** `ei-cli sync --finance` must pull live SimpleFin data, write to VRAM, and insert into SQLite.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| Security | `.../Security/SecItemAdd(____).md` | `SecItemAdd(_:_:)` | Store SimpleFin credentials |
| Security | `.../Security/SecItemCopyMatching(____).md` | `SecItemCopyMatching(_:_:)` | Retrieve credentials |
| Security | `.../Security/using-the-keychain-to-manage-user-secrets/README.md` | Keychain best practices | Credential architecture |
| Foundation | `.../Foundation/URLSession/README.md` | `URLSession.shared.data(for:)` | SimpleFin HTTP requests |
| Foundation | `.../Foundation/URLRequest/README.md` | `URLRequest` | Build HTTP requests |
| Foundation | `.../Foundation/HTTPURLResponse/README.md` | `statusCode` | Validate responses |
| Foundation | `.../Foundation/JSONDecoder/README.md` | `JSONDecoder` | Parse SimpleFin JSON |
| Foundation | `.../Foundation/JSONEncoder/README.md` | `JSONEncoder` | Serialize snapshots |
| Foundation | `.../Foundation/Data/README.md` | `Data(base64Encoded:)` | Decode setup token |
| Foundation | `.../Foundation/FileManager/README.md` | `createDirectory`, `fileExists` | VRAM directory management |
| Foundation | `.../Foundation/FileHandle/README.md` | `seekToEndOfFile`, `write` | JSONL append |
| Foundation | `.../Foundation/Calendar/README.md` | `dateComponents(_:from:)` | Date extraction |
| Foundation | `.../Foundation/ISO8601DateFormatter/README.md` | `string(from:)` | Date formatting |
| Foundation | `.../Foundation/Process/README.md` | `Process.run()` | Shell to PAI inference |

---

### Phase 3 (P0): Data Import from PostgreSQL

**Goal:** One-time import of existing data from the PostgreSQL search engine into TheEddingsIndex's SQLite + USearch. PostgreSQL continues running unchanged — this is a copy, not a migration.

**Steps:**
- [ ] 3.1 — Implement `MigrateCommand.swift` (`ei-cli migrate --from-postgres`):
  - Export from PostgreSQL at `localhost:4432` via `Process` running `pg_dump --format=plain --data-only --table=<table>` per table (per `.../Foundation/Process/README.md`). Use JSON format (`\copy ... TO STDOUT WITH (FORMAT csv, HEADER)`) to avoid newline/quote parsing issues in email and transcript content that break CSV parsing.
  - Parse exported data in Swift, insert into SQLite via GRDB batch inserts (1000 records per transaction for speed).
  - **FTS5 optimization:** During bulk migration, DROP all FTS5 virtual tables before insert. After all records are inserted into base tables, recreate FTS5 tables and run `INSERT INTO fts_table(fts_table) VALUES('rebuild')` to build the full-text index in a single linear scan. This is orders of magnitude faster than synchronize-on-insert for 900K+ records.
- [ ] 3.2 — Migrate `documents` table (912K records):
  - Read from PostgreSQL `documents` table.
  - Insert into SQLite `documents` table.
  - FTS5 auto-populates via `synchronize(withTable:)`.
- [ ] 3.3 — Migrate `email_chunks` table (282K records):
  - Map PostgreSQL column names to Swift Codable model.
  - Batch insert into SQLite `emailChunks` (1000 records per transaction for speed).
- [ ] 3.4 — Migrate `slack_chunks` table (13.5K records):
  - Same pattern as email migration.
- [ ] 3.5 — Migrate `chunks` table (87K transcript chunks):
  - Filter by `content_type = 'transcript'`.
  - Insert into SQLite `transcriptChunks`.
- [ ] 3.6 — Migrate `contacts` + `companies` + `transcript_meetings` tables.
- [ ] 3.7 — Generate 512-dim embeddings for all migrated chunks:
  - Use `NLEmbedder` to generate `NLEmbedding.sentenceEmbedding` vectors.
  - Batch process (500 chunks at a time) with progress logging.
  - Insert into 512-dim USearch index.
  - Per `.../NaturalLanguage/README.md`: `NLEmbedding.sentenceEmbedding(for: .english)`.
- [ ] 3.8 — Generate 4096-dim embeddings (macOS only):
  - Use `CoreMLEmbedder` with converted Qwen3 model.
  - Batch process with Neural Engine acceleration.
  - Insert into 4096-dim USearch index.
  - Per `.../CoreML/README.md`: `MLModelConfiguration.computeUnits = .all`.
- [ ] 3.9 — Verify migration:
  - Compare record counts: PostgreSQL vs SQLite (must match exactly).
  - Run 20 test queries against both systems — results must be equivalent.
  - Verify FTS5 BM25 ranking quality against PostgreSQL tsvector.

**Guard:** Record counts in TheEddingsIndex's SQLite must match PostgreSQL source counts. 20/20 test queries must return equivalent results. PostgreSQL is NOT modified or stopped.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| NaturalLanguage | `.../NaturalLanguage/README.md` | `NLEmbedding.sentenceEmbedding(for:)` | 512-dim embeddings |
| CoreML | `.../CoreML/README.md` | `MLModel`, `MLModelConfiguration` | 4096-dim Qwen3 embeddings |
| Foundation | `.../Foundation/Process/README.md` | `Process` | Shell to psql for export |
| os | `.../os/Logger/README.md` | `Logger` | Migration progress logging |
| os | `.../os/OSSignposter/README.md` | `OSSignposter` | Performance measurement |

---

### Phase 4 (P1): Embedding Infrastructure

**Goal:** Production-ready dual embedding system with NaturalLanguage (512-dim, iOS+macOS) and CoreML Qwen3 (4096-dim, macOS only).

**Steps:**
- [ ] 4.1 — Implement `EmbeddingProvider` protocol and `NLEmbedder`:
  - Per `.../NaturalLanguage/README.md`: use `NLEmbedding.sentenceEmbedding(for: .english)` for 512-dim vectors.
  - Handle missing model gracefully (return error, don't crash).
  - Implement `embedBatch` with `TaskGroup` for parallel embedding generation.
- [ ] 4.2 — Convert Qwen3-VL embedding model to CoreML format:
  - Use `coremltools` Python package to convert ONNX → `.mlmodel`.
  - Validate output dimensions match (4096).
  - Per `.../CoreML/README.md`: test with `.cpuAndGPU` and `.all` compute units.
  - **Size caveat:** Qwen3 7B+ is ~15GB FP16. Must use 4-bit quantization (~1.5-2GB). Neural Engine practical limit is ~1GB for ANE models. If CoreML conversion fails or model exceeds ANE limits, fallback to NLEmbedding 512-dim on macOS too — CoreML Qwen3 is an enhancement, not a requirement. The PRD works with 512-dim only across both platforms.
- [ ] 4.3 — Implement `CoreMLEmbedder` (macOS only):
  - Load `.mlmodel` via auto-generated Swift class.
  - Tokenize input text (match Qwen3 tokenizer).
  - Run inference, extract embedding vector.
  - Gate behind `#if os(macOS)`.
- [ ] 4.4 — Implement dual-index write path:
  - On macOS: every chunk gets both 512-dim AND 4096-dim embeddings.
  - On iOS: every chunk gets only 512-dim embedding.
  - `VectorIndex.add(key:vector512:vector4096:)` handles both.
- [ ] 4.5 — Implement incremental embedding:
  - Track which chunks have embeddings via `embeddingStatus` column.
  - On sync: only generate embeddings for new/modified chunks.
  - Background task: re-embed chunks when a better model is available.
- [ ] 4.6 — Benchmark embedding throughput:
  - NLEmbedder: target 100+ chunks/second on M-series.
  - CoreMLEmbedder: target 20+ chunks/second with Neural Engine.

**Guard:** Both embedders must produce consistent vectors (same input → same output). Semantic search must return relevant results for 10 test queries.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| NaturalLanguage | `.../NaturalLanguage/README.md` | `NLEmbedding` | Sentence embeddings (iOS+macOS) |
| CoreML | `.../CoreML/README.md` | `MLModel`, `MLModelConfiguration` | Qwen3 inference (macOS) |
| os | `.../os/OSSignposter/README.md` | `OSSignposter` | Embedding performance profiling |

---

### Phase 5 (P1): TheEddingsIndex's Own Data Sync Sources

**Goal:** Build TheEddingsIndex's own sync engine that reads from VRAM (where existing scripts already write) and pulls directly from new sources (SimpleFin, IMAP). Existing launch agents continue running unchanged — TheEddingsIndex reads from the files they produce.

**Steps:**
- [ ] 5.1 — Implement `FileScanner.swift`:
  - Scan VRAM directories (areas 10-79) for `.md` and `.txt` files.
  - Use `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:)` (per `.../Foundation/FileManager/README.md`).
  - Extract area/category from path (Johnny.Decimal pattern).
  - Detect new/modified files via `modifiedAt` comparison with SQLite records.
  - Chunk content via `SmartChunker` (semantic paragraph boundaries).
  - Insert into `documents` + FTS5 + embeddings.
- [ ] 5.2 — Implement `IMAPClient.swift`:
  - Connect to Gmail IMAP via `URLSession` or Network framework (per `.../Network/README.md`).
  - Fetch new emails since last sync timestamp.
  - Parse email headers + body.
  - Chunk, extract contacts, insert into `emailChunks` + FTS5 + embeddings.
- [ ] 5.3 — Implement `SlackClient.swift`:
  - Read Slack export JSON files from `/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack/`.
  - For incremental: detect new files since last scan.
  - Parse message JSON, chunk, insert into `slackChunks` + FTS5 + embeddings.
- [ ] 5.4 — Implement `FathomClient.swift`:
  - Sync meeting recordings and transcripts from Fathom.
  - Parse transcript text, identify speakers.
  - Insert into `meetings` + `transcriptChunks` + FTS5 + embeddings.
  - Link speakers to contacts via name matching.
- [ ] 5.5 — Implement `CalDAVClient.swift`:
  - Sync calendar events via CalDAV protocol over `URLSession`.
  - Extract meeting metadata (title, time, participants).
  - Cross-reference with Fathom meetings by timestamp.
- [ ] 5.6 — Implement `ContactExtractor.swift`:
  - Auto-extract contacts from email headers, Slack usernames, meeting participants.
  - Get-or-create pattern: match by email → create if new.
  - Auto-extract companies from email domains.
  - Update interaction counts (emailCount, meetingCount, slackCount).
- [ ] 5.7 — Implement `SyncCommand.swift` (`ei-cli sync`):
  - `--all` — sync all sources in parallel via `TaskGroup` (default for launch agent).
  - `--finance` — SimpleFin + QBO only.
  - `--email` — IMAP only.
  - `--files` — VRAM filesystem only.
  - `--meetings` — Fathom only.
  - **Per-source isolation:** Each source syncs inside its own `Task` within a `TaskGroup`. A failure in IMAP sync does NOT block SimpleFin sync. Per-source timeout of 5 minutes. Errors collected and reported at end, not thrown mid-sync. This prevents the "Big Stall" — one hung source cannot block others.
  - Structured logging via `Logger` (per `.../os/Logger/README.md`).
  - Voice notification on completion via `URLSession` POST to `localhost:8888/notify`.
- [ ] 5.8 — Implement `SearchCommand.swift` (`ei-cli search --json "query"`):
  - **PAI integration.** Gives PAI a native Swift search path alongside the existing `curl localhost:3000/search`. Both work simultaneously — PAI can use whichever is available.
  - Accepts query string, optional `--sources`, `--limit`, `--year`, `--month` flags.
  - Outputs structured JSON to stdout (same schema as current API for PAI compatibility).
  - PAI calls: `ei-cli search --json "Optro" --limit 10` → JSON array of SearchResult objects.
- [ ] 5.8 — Implement `StateManager.swift`:
  - Track last sync timestamp per source.
  - Track sync status (success/failure/partial).
  - Persist to `state/sync-state.json` via `JSONEncoder` + `Data.write(to:options:.atomic)`.

**Guard:** `ei-cli sync --all` must complete without errors, indexing new content from all sources.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| Foundation | `.../Foundation/FileManager/README.md` | `contentsOfDirectory(at:)` | VRAM file scanning |
| Foundation | `.../Foundation/URLSession/README.md` | `URLSession` | IMAP, CalDAV, Fathom HTTP |
| Foundation | `.../Foundation/JSONDecoder/README.md` | `JSONDecoder` | Parse Slack/Fathom JSON |
| Foundation | `.../Foundation/Data/README.md` | `Data.write(to:options:.atomic)` | Atomic state writes |
| Network | `.../Network/README.md` | `NWConnection` | IMAP socket connection |
| os | `.../os/Logger/README.md` | `Logger` | Sync operation logging |
| Foundation | `.../Foundation/ProcessInfo/README.md` | `ProcessInfo.processInfo.environment` | Read env vars |

---

### Phase 6 (P1): SwiftUI App — macOS + iOS

**Goal:** Build the SwiftUI multiplatform app with search, finance dashboard, meeting browser, and contact intelligence.

**Steps:**
- [ ] 6.1 — Implement `EddingsApp.swift` (`@main`):
  - Per `.../SwiftUI/App/README.md`: declare `App` with `body: some Scene`.
  - `WindowGroup` for main content.
  - `Settings` scene for macOS (per `.../SwiftUI/README.md`).
  - Initialize `TheEddingsIndex` as `@State` with `@Observable`.
- [ ] 6.2 — Implement `AppSidebar.swift` (macOS):
  - `NavigationSplitView` with sidebar sections: Search, Finance, Meetings, Contacts, Settings.
  - Per `.../SwiftUI/NavigationSplitView/README.md`.
- [ ] 6.3 — Implement `AppTabBar.swift` (iOS):
  - `TabView` with same sections.
  - Per `.../SwiftUI/README.md`.
- [ ] 6.4 — Implement `SearchView.swift`:
  - Text field with real-time search.
  - Source filter chips (email, slack, transcript, file, financial).
  - Date range picker.
  - Results list with `SearchResultRow` showing source icon, title, snippet, date, relevance score.
- [ ] 6.5 — Implement `FreedomDashboard.swift`:
  - Freedom Velocity gauge: current weekly non-W2 take-home vs $6,058 target.
  - Net worth card: assets, liabilities, net.
  - Debt paydown tracker: per-card balance trajectory.
  - Monthly spending by category (Charts framework).
  - Per `.../SwiftUI/README.md`: use `Charts` for data visualization.
- [ ] 6.6 — Implement `TransactionList.swift`:
  - Categorized transaction list with search.
  - Group by category or date.
  - Uncategorized queue with manual assignment.
- [ ] 6.7 — Implement `MeetingList.swift` + `TranscriptView.swift`:
  - Meeting list sorted by date, filterable by internal/external.
  - Transcript view with speaker labels and full-text search within transcript.
  - Tap speaker name → navigate to contact detail.
- [ ] 6.8 — Implement `ContactList.swift` + `ContactDetail.swift`:
  - Contact list sorted by interaction depth (email + meeting + Slack counts).
  - Contact detail: all interactions across all sources, timeline view.
  - Company association.
- [ ] 6.9 — Implement `SettingsView.swift`:
  - Sync source configuration (enable/disable per source).
  - SimpleFin account setup.
  - iCloud sync status.
  - Data statistics (record counts, index sizes).

**Guard:** App must build and run on both macOS and iOS simulator. Search must return results from all indexed sources.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| SwiftUI | `.../SwiftUI/README.md` | SwiftUI framework | UI framework |
| SwiftUI | `.../SwiftUI/App/README.md` | `App` protocol | App entry point |
| SwiftUI | `.../SwiftUI/NavigationSplitView/README.md` | `NavigationSplitView` | macOS sidebar layout |
| Observation | `.../Observation/README.md` | `@Observable` | State management |
| Charts | `.../Charts/README.md` | `Chart` | Financial visualizations |
| Foundation | `.../Foundation/Timer/README.md` | `Timer` | Periodic search refresh |

---

### Phase 7 (P1): iCloud Sync

**Goal:** Sync SQLite records + 512-dim embedding vectors between macOS and iOS via iCloud. USearch index is rebuilt locally on each device from synced data (never synced as a binary file).

**Steps:**
- [ ] 7.1 — Implement `iCloudManager.swift`:
  - Initialize `CKSyncEngine` with private database container.
  - Per `.../CloudKit/CKSyncEngine-5sie5/README.md` (iOS 17+, macOS 14+).
  - Define record types for each syncable table.
  - Implement delegate callbacks for `didReceiveChanges` and `pendingChanges`.
- [ ] 7.2 — Implement SQLite → CKRecord mapping:
  - Convert GRDB records to `CKRecord` instances.
  - Per `.../CloudKit/CKRecord/README.md`: map Swift types to CKRecord fields.
  - Handle JSON array fields (tags, speakers) as CKRecord string lists.
- [ ] 7.3 — Implement CKRecord → SQLite mapping:
  - Receive remote changes, upsert into local SQLite.
  - Conflict resolution: last-writer-wins by `modifiedAt` timestamp.
- [ ] 7.4 — Implement USearch index rebuild on iOS (NOT binary sync):
  - **Do NOT sync the binary USearch index file via iCloud Drive.** iCloud Drive files can stay as "placeholder" stubs on iOS indefinitely. File coordination risks corruption during partial writes.
  - Instead: sync 512-dim embedding vectors as `Data` blobs in CKRecords alongside chunk metadata.
  - On iOS first launch / after sync: rebuild USearch index locally from synced embedding data. USearch can index 382K 512-dim vectors in minutes on A18 Pro.
  - On macOS: USearch indexes are local only (both 512 and 4096-dim). Never uploaded.
  - This ensures the vector index is always consistent with the synced SQLite data.
- [ ] 7.5 — Implement field-level conflict resolution for financial data:
  - **Last-writer-wins by record is dangerous for financial data.** If Ron categorizes a transaction on iOS while Mac does a bulk import, LWW could revert manual categorization.
  - Use `categoryModifiedAt` field: during conflict resolution, compare field-level timestamps. A newer `categoryModifiedAt` on iOS overrides an older one from Mac bulk import, even if the Mac's record `modifiedAt` is newer overall.
  - Search metadata (emails, Slack, transcripts): standard LWW by record `modifiedAt` is acceptable — these are append-only.
- [ ] 7.6 — Implement selective sync:
  - Meeting MP4s: never sync (too large).
  - Transcript text: sync (small, searchable).
  - Email archives: sync metadata only (subject, from, date), not full body.
  - Financial data: full sync (small, critical for mobile).
- [ ] 7.7 — Test sync round-trip: modify on Mac → verify on iOS simulator → modify on iOS → verify on Mac. Specifically test: categorize a transaction on iOS, then run bulk import on Mac — iOS categorization must survive.

**Guard:** Changes on macOS must appear on iOS within 60 seconds. Search on iOS must return synced results.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| CloudKit | `.../CloudKit/README.md` | CloudKit framework | iCloud sync |
| CloudKit | `.../CloudKit/CKSyncEngine-5sie5/README.md` | `CKSyncEngine` | Modern sync engine |
| CloudKit | `.../CloudKit/CKContainer/README.md` | `CKContainer` | Database container |
| CloudKit | `.../CloudKit/CKRecord/README.md` | `CKRecord` | Record mapping |

---

### Phase 8 (P1): Launch Agent for EddingsIndex Sync

**Goal:** Add a `ei-cli sync` launch agent that runs twice daily alongside existing agents. Existing agents are NOT modified or disabled.

**Steps:**
- [ ] 8.1 — Build release binary: `swift build -c release`.
- [ ] 8.2 — Create `com.vram.eddings-index.plist`:
  ```xml
  <dict>
      <key>Label</key>
      <string>com.vram.eddings-index</string>
      <key>ProgramArguments</key>
      <array>
          <string>/Volumes/VRAM/00-09_System/01_Tools/TheEddingsIndex/.build/release/ei-cli</string>
          <string>sync</string>
          <string>--all</string>
      </array>
      <key>StartInterval</key>
      <integer>43200</integer>
      <key>RunAtLoad</key>
      <true/>
      <key>WorkingDirectory</key>
      <string>/Volumes/VRAM/00-09_System/01_Tools/TheEddingsIndex</string>
      <key>StandardOutPath</key>
      <string>/Users/ronaldeddings/Library/Logs/vram/reality/sync.log</string>
      <key>StandardErrorPath</key>
      <string>/Users/ronaldeddings/Library/Logs/vram/reality/error.log</string>
  </dict>
  ```
  Per `.../ServiceManagement/SMAppService/README.md`: can also register programmatically via `SMAppService.agent(plistName:).register()`.
- [ ] 8.3 — Install launch agent, verify first automated run.
- [ ] 8.4 — Voice notification on completion via `URLSession` POST to `localhost:8888/notify`.

**Note:** Existing launch agents (email-sync, slack-sync, fathom-sync, qbo-dump, search-server, embedding-server) all continue running. They write to VRAM. TheEddingsIndex reads from VRAM. No conflicts — TheEddingsIndex's launch agent is additive, not a replacement.

**Guard:** `ei-cli sync --all` must complete within 10 minutes and produce equivalent data to all replaced agents.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| ServiceManagement | `.../ServiceManagement/SMAppService/README.md` | `SMAppService.agent(plistName:)` | Programmatic agent registration |
| Foundation | `.../Foundation/ProcessInfo/README.md` | `ProcessInfo` | Process environment |

---

### Phase 9 (P2): iOS Background Sync + App Groups + Widgets + Siri

**Goal:** iOS-native background data refresh, shared App Group storage for widgets, home screen widgets, and Siri voice queries.

**Steps:**
- [ ] 9.1 — Implement iOS background sync via BackgroundTasks framework:
  - Per `.../BackgroundTasks/README.md` (iOS 13+).
  - **`BGAppRefreshTask`** (30 sec, 20MB limit): Quick check — ping SimpleFin API for new transactions. If new data exists, schedule a processing task.
  - **`BGProcessingTask`** (several minutes, ~250MB limit): Heavy sync — run IMAP, Slack parsing, SQLite indexing, USearch vector generation. Requires device on Wi-Fi and power.
  - **Checkpoint-based execution:** iOS can kill background tasks at any moment. The sync engine must commit progress to SQLite every 100 records. On next run, resume from last checkpoint via `StateManager`.
  - Register tasks in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`:
    - `com.hackervalley.eddingsindex.refresh`
    - `com.hackervalley.eddingsindex.sync`
- [ ] 9.2 — Implement App Group shared storage:
  - **CRITICAL for WidgetKit.** Widget extensions run in a separate process. They CANNOT access the main app's SQLite database without a shared App Group container.
  - App Group ID: `group.com.hackervalley.eddingsindex`
  - Database path: `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.hackervalley.eddingsindex")` per `.../Foundation/FileManager/README.md`.
  - GRDB `DatabaseQueue` configured in WAL mode for concurrent reader (widget) + writer (app/background task).
  - **Widget data strategy:** The main app pre-calculates widget data (Freedom Velocity, net worth, upcoming meetings) into a dedicated `widgetSnapshots` table. Widget reads this single table — never loads USearch index (30MB memory limit).
- [ ] 9.3 — Implement `FreedomVelocityWidget.swift`:
  - Per `.../WidgetKit/README.md` (iOS 14+, macOS 11+).
  - Display current weekly non-W2 take-home vs $6,058 target.
  - Update on timeline (every 6 hours).
  - Small, medium, large sizes.
  - Read from `widgetSnapshots` table in shared App Group container.
- [ ] 9.4 — Implement `NetWorthWidget.swift`:
  - Display assets, liabilities, net worth, and daily delta.
- [ ] 9.5 — Implement `UpcomingWidget.swift`:
  - Display next 3 meetings from calendar sync.
- [ ] 9.6 — Implement Siri intents via AppIntents:
  - Per `.../AppIntents/README.md` (iOS 16+, macOS 13+).
  - "What's my Freedom Velocity?" → return current score.
  - "Search TheEddingsIndex for [query]" → return top 3 results.
  - "How much did I spend on [category] this month?" → return total.
- [ ] 9.7 — Implement CoreSpotlight indexing:
  - Per `.../CoreSpotlight/README.md` (iOS 9+, macOS 10.13+).
  - Index contacts, meetings, and financial summaries for system-wide Spotlight search.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| WidgetKit | `.../WidgetKit/README.md` | `Widget`, `TimelineProvider` | Home screen widgets |
| AppIntents | `.../AppIntents/README.md` | `AppIntent`, `AppShortcut` | Siri voice commands |
| CoreSpotlight | `.../CoreSpotlight/README.md` | `CSSearchableItem` | System Spotlight indexing |

---

### Phase 10 (P2): Conversift Integration

**Goal:** Connect Conversift's real-time transcription to TheEddingsIndex's search index for live meeting indexing.

**Steps:**
- [ ] 10.1 — Add `EddingsKit` as a local SPM dependency in Conversift's `Package.swift`:
  - `.package(path: "../TheEddingsIndex")` per `.../PackageDescription/Package/Dependency/README.md`.
  - **Model naming collision:** Conversift has `DataKit.Meeting` and `DataKit.TranscriptSegment`. EddingsKit has `Meeting` and `TranscriptChunk`. To avoid conflicts, EddingsKit models should be accessed via module-qualified names (`EddingsKit.Meeting`) or the shared types should be extracted into a common `EddingsModels` target that both packages depend on. No circular dependency — Conversift depends on EddingsKit, never the reverse.
- [ ] 10.2 — Implement transcript chunk forwarding:
  - Conversift's `DataKit` sends completed transcript chunks to `EddingsKit.DatabaseManager`.
  - Insert into `transcriptChunks` + FTS5 index in real time.
  - Generate 512-dim embedding via `NLEmbedder` (instant on M-series).
  - **GRDB concurrency:** Use WAL mode + `DatabasePool` (not `DatabaseQueue`) for real-time inserts. WAL allows concurrent reads from the search UI while Conversift writes transcript chunks. Audio capture runs on a separate `DispatchQueue` — GRDB writes must not block the audio processing chain.
- [ ] 10.3 — Implement speaker → contact bridging:
  - **The gap:** DiarizationKit identifies speakers by biometric voice embeddings (`eres2net`, `wsi_resnet34` via `SpeakerCluster`). EddingsKit contacts are matched by name/email. These are different identity systems.
  - **Bridge strategy:** Add a `voiceClusterId` column to the `contacts` table. When Conversift identifies a speaker by voice AND a human labels that cluster (e.g., "Emily Humphrey"), store the mapping. On subsequent meetings, DiarizationKit recognizes the voice → looks up `voiceClusterId` → resolves to contact. First encounter with an unknown voice creates an "unlinked" contact with `name = "Unknown Speaker {clusterId}"` for later manual linking.
  - Update `meetingCount` and `lastSeenAt` on resolved contacts.
- [ ] 10.4 — Implement live meeting creation:
  - When Conversift starts capturing, create a `Meeting` record in SQLite.
  - Link transcript chunks to meeting via `meetingId`.
  - Update duration and participant count in real time.

**Guard:** During a live Conversift capture, search for a phrase spoken 30 seconds ago — it must appear in search results.

**Apple Developer Doc References:**

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| PackageDescription | `.../PackageDescription/Package/Dependency/README.md` | `.package(path:)` | Local SPM dependency |
| NaturalLanguage | `.../NaturalLanguage/README.md` | `NLEmbedding` | Real-time embedding generation |

---

## Testing & Verification Protocol

### Execution Loop (Per Phase)

```
1. Implement phase code changes
2. swift build — verify compilation (zero warnings, Swift 6 strict concurrency)
3. swift test — run unit tests
4. .build/debug/ei-cli <command> — verify against live data
5. Read output files — validate JSON structure
6. If app phase: launch on macOS + iOS simulator — verify UI
7. If any check fails → fix → restart from step 2
```

### Verification Checklist

| ID | Phase | Check | Method | Pass Criteria |
|----|-------|-------|--------|---------------|
| V-1 | 1 | FTS5 BM25 returns relevant results | 10 test queries | Results equivalent to PostgreSQL |
| V-2 | 1 | USearch add/search round-trip | Unit test | Insert 1000 vectors, search returns correct top-K |
| V-3 | 1 | Hybrid RRF ranking | Unit test | Combined results outperform FTS-only or semantic-only |
| V-4 | 2 | SimpleFin auth | `ei-cli sync --finance` | Accounts + balances returned |
| V-5 | 2 | Transactions deduplicated | Run sync twice | Second run = 0 new transactions |
| V-6 | 2 | VRAM files written | `ls .../20_Banking/snapshots/` | Today's snapshot exists, valid JSON |
| V-7 | 2 | Freedom Velocity calculated | Read snapshot | Non-W2 take-home vs $6,058 |
| V-8 | 3 | Record counts match | Compare PostgreSQL vs SQLite | Exact match for all tables |
| V-9 | 3 | Search quality equivalent | 20 test queries on both systems | Equivalent result sets |
| V-10 | 4 | NLEmbedder produces vectors | Unit test | 512-dim float array, non-zero |
| V-11 | 4 | CoreMLEmbedder produces vectors | Unit test (macOS) | 4096-dim float array, non-zero |
| V-12 | 4 | Semantic search returns relevant results | 10 queries | Top-5 contain expected documents |
| V-13 | 5 | File scanner indexes new files | Add test file to VRAM, sync | File appears in search results |
| V-14 | 5 | Email sync pulls new messages | `ei-cli sync --email` | New emails indexed |
| V-15 | 6 | App builds on macOS | `swift build` + `open TheEddingsIndex.app` | App launches, search works |
| V-16 | 6 | App builds on iOS | Xcode → iOS Simulator | App launches, search works |
| V-17 | 7 | iCloud sync Mac→iOS | Modify on Mac, check iOS | Changes appear within 60s |
| V-18 | 7 | iCloud sync iOS→Mac | Modify on iOS, check Mac | Changes appear within 60s |
| V-19 | 7 | Field-level conflict resolution | Categorize on iOS, bulk import on Mac | iOS categorization survives |
| V-20 | 8 | Launch agent completes | Check `~/Library/Logs/vram/reality/sync.log` | Success entry |
| V-21 | 8 | PAI can search via CLI | `ei-cli search --json "Optro"` | Returns JSON results |
| V-22 | 8 | One source failure doesn't block others | Kill IMAP during sync | SimpleFin sync still completes |
| V-23 | 9 | iOS background sync runs | Check BGTaskScheduler logs | BGProcessingTask completes |
| V-24 | 9 | Widget reads from App Group | iOS Home Screen | Freedom Velocity visible |
| V-25 | 9 | Siri responds | "What's my Freedom Velocity?" | Returns current score |
| V-26 | 10 | Live transcript indexed | Speak during Conversift, search | Phrase found within 30 seconds |
| V-27 | 10 | Speaker→contact bridging | Identified speaker linked to contact | voiceClusterId resolves to name |

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| GRDB.swift FTS5 reliability on iOS | MEDIUM | GRDB bundles its own SQLite (with FTS5 compiled in), bypassing iOS system SQLite reliability issues. Verified in GRDB docs. |
| USearch Swift bindings stability | MEDIUM | USearch 2.0+ is stable, used in production (YugabyteDB). Pin version. Test thoroughly on both platforms. |
| USearch save() is not atomic — crash = corruption | HIGH | **Generation-swapping save:** write to new generation file, create new mmap view (iOS), swap reference atomically, let old instance deallocate (safe munmap). Do NOT use `FileManager.replaceItemAt()` with active mmap — unlinks inode → SIGBUS crash. Implemented in `VectorIndex.save()`. |
| USearch add() not transactional — crash before save() loses vectors | HIGH | **Pending embeddings table:** `pendingEmbeddings` in SQLite tracks vectors added but not yet committed to USearch file. On startup, re-add any pending vectors and save. Ensures SQLite and USearch stay consistent after crashes. |
| USearch memory on iOS (382K × 512-dim Float32 = ~788MB) | HIGH | **Mandatory:** Use `index.view()` (mmap) on iOS — OS pages data from disk on demand, not loaded into RAM. Widget extensions (30MB limit) must NEVER load USearch — read pre-calculated widget data from SQLite instead. |
| CoreML Qwen3 conversion fails (7B+ model = 15GB FP16) | HIGH | Fallback: use NaturalLanguage 512-dim on macOS too. Qwen3 CoreML is an enhancement, not a requirement. Even with 4-bit quantization (~1.5-2GB), may exceed Neural Engine's practical ~1GB limit. |
| iCloud sync latency > 60 seconds | MEDIUM | CKSyncEngine handles background sync. Acceptable for non-real-time data. Financial data is daily anyway. |
| CKSyncEngine account change silently drops pending data | HIGH | Per Apple docs: account change resets all internal state including unsaved changes. `handleEvent(.accountChange)` must flush pending local writes to SQLite before accepting reset. Implemented in `iCloudManager.handleAccountChange()`. |
| CKSyncEngine State.Serialization must be persisted across launches | HIGH | Losing serialized state forces full re-fetch of all records. `persistState()` writes to `ck-sync-state.dat` via `Data.write(to:options:.atomic)` on every `.stateUpdate` event. Per `.../Foundation/Data/README.md`. |
| iCloud sync conflict overwrites manual categorization | HIGH | **Field-level timestamps:** `categoryModifiedAt` on financial transactions. CKSyncEngine conflict handler compares field timestamps, not record timestamps. Manual iOS categorization survives Mac bulk imports. |
| Binary USearch index sync via iCloud corrupts | HIGH | **Do not sync binary index files.** Sync embedding vectors as CKRecord Data fields. Rebuild USearch index locally on iOS from synced data. Ensures consistency. |
| CloudKit initial sync (382K records) takes hours | MEDIUM | **Prioritized sync:** Sync finance + contacts first (P0 value). Background-batch search chunks. ~955 CloudKit requests needed at 400 records/request. Checkpoint-based — resumes after interruption. |
| CloudKit storage quota exceeded | LOW | Only metadata syncs (not recordings or archives). Estimated sync size < 500MB. Private DB uses user's iCloud quota (5-200GB). |
| iOS background sync killed by OS | MEDIUM | Per `.../BackgroundTasks/README.md`: `BGProcessingTask` can be terminated at any time. Sync engine is checkpoint-based — commits every 100 records. Resumes from last checkpoint on next `BGProcessingTask` execution. |
| Widget can't access main app's SQLite | HIGH | **App Group required.** Database stored in `group.com.hackervalley.eddingsindex` shared container. Widget reads pre-calculated `widgetSnapshots` table — never loads USearch index. |
| PAI needs native search alongside existing API | LOW | **`ei-cli search --json "query"` command.** Gives PAI a second search path. Existing `curl localhost:3000/search` continues working. Both coexist. |
| EddingsIndex sync engine failure | MEDIUM | **Per-source `TaskGroup` isolation.** Each source syncs in its own Task with 5-minute timeout. Existing launch agents continue independently — EddingsIndex failure doesn't affect existing data pipeline. |
| NLEmbedding hardcoded to .english — garbage vectors for multilingual content | MEDIUM | **`NLLanguageRecognizer` detects language per chunk.** Embeds with detected language. Falls back to .english for unsupported languages. Per `.../NaturalLanguage/README.md`. |
| FTS5 bulk insert during migration is slow with synchronize(withTable:) | HIGH | **Drop FTS5 tables before bulk insert, rebuild after.** `INSERT INTO fts(fts) VALUES('rebuild')` builds index in single linear scan. Orders of magnitude faster than row-by-row sync. |
| Conversift Meeting model name collides with EddingsKit Meeting | MEDIUM | Use module-qualified names (`EddingsKit.Meeting`) or extract shared types into `EddingsModels` target. No circular dependency — Conversift depends on EddingsKit, never reverse. |
| Speaker voice identity ≠ Contact name identity | MEDIUM | Bridge via `voiceClusterId` column on contacts table. DiarizationKit voice → cluster ID → contact lookup. First encounter = "Unknown Speaker" for manual linking. |
| Swift 6 strict concurrency violations | MEDIUM | Design with actors + Sendable from day one. GRDB supports `DatabasePool` for concurrent reads/writes. USearch wrapped in actor. |
| Data import from PostgreSQL | MEDIUM | One-time import to seed TheEddingsIndex's SQLite. PostgreSQL continues running — no migration pressure. Use `pg_dump --json` for clean export. |
| 382K embeddings regeneration time | MEDIUM | NLEmbedder at 100+ chunks/sec = ~1 hour for 382K. CoreMLEmbedder at 20/sec = ~5 hours. Run as background task. |
| VRAM volume unmounted during sync | MEDIUM | Check `FileManager.default.fileExists(atPath: "/Volumes/VRAM")` before write. Exit with code 2 if missing. |
| SimpleFin rate limit (token disabled) | HIGH | 2x/day sync well within 24/day limit. Track quota. Alert on warnings. |

---

## Files Created

| File | Phase | Purpose |
|------|-------|---------|
| `Package.swift` | 1 | Swift package manifest |
| `Sources/EddingsKit/Storage/DatabaseManager.swift` | 1 | GRDB + FTS5 schema |
| `Sources/EddingsKit/Storage/FTSIndex.swift` | 1 | FTS5 BM25 search |
| `Sources/EddingsKit/Storage/VectorIndex.swift` | 1 | USearch HNSW wrapper |
| `Sources/EddingsKit/Search/QueryEngine.swift` | 1 | Unified search orchestrator |
| `Sources/EddingsKit/Search/FTSSearch.swift` | 1 | FTS5 query builder |
| `Sources/EddingsKit/Search/SemanticSearch.swift` | 1 | USearch query wrapper |
| `Sources/EddingsKit/Search/HybridRanker.swift` | 1 | RRF fusion algorithm |
| `Sources/EddingsKit/Models/*.swift` | 1, 2 | All Codable data models |
| `Sources/EddingsKit/Auth/KeychainManager.swift` | 2 | SecItem credential storage |
| `Sources/EddingsKit/Sync/SimpleFinClient.swift` | 2 | SimpleFin API client |
| `Sources/EddingsKit/Normalize/Normalizer.swift` | 2 | Data transformation |
| `Sources/EddingsKit/Normalize/Deduplicator.swift` | 2 | Transaction dedup |
| `Sources/EddingsKit/Sync/QBOReader.swift` | 2 | QBO CSV parser |
| `Sources/EddingsKit/Storage/VRAMWriter.swift` | 2 | JSON/JSONL persistence |
| `Sources/EddingsKit/Categorize/Categorizer.swift` | 2 | Transaction categorization |
| `Sources/EddingsKit/Intelligence/FreedomTracker.swift` | 2 | $6,058/week velocity |
| `Sources/EddingsCLI/Commands/MigrateCommand.swift` | 3 | PostgreSQL → SQLite migration |
| `Sources/EddingsKit/Embedding/EmbeddingProvider.swift` | 4 | Embedding protocol |
| `Sources/EddingsKit/Embedding/NLEmbedder.swift` | 4 | NaturalLanguage 512-dim |
| `Sources/EddingsKit/Embedding/CoreMLEmbedder.swift` | 4 | Qwen3 CoreML 4096-dim |
| `Sources/EddingsKit/Sync/FileScanner.swift` | 5 | VRAM filesystem indexer |
| `Sources/EddingsKit/Sync/IMAPClient.swift` | 5 | Email sync |
| `Sources/EddingsKit/Sync/SlackClient.swift` | 5 | Slack sync |
| `Sources/EddingsKit/Sync/FathomClient.swift` | 5 | Meeting sync |
| `Sources/EddingsKit/Sync/CalDAVClient.swift` | 5 | Calendar sync |
| `Sources/EddingsKit/Normalize/ContactExtractor.swift` | 5 | Auto contact extraction |
| `Sources/EddingsCLI/Commands/SyncCommand.swift` | 5 | CLI sync orchestrator |
| `Sources/EddingsApp/EddingsApp.swift` | 6 | @main SwiftUI app |
| `Sources/EddingsApp/Navigation/AppSidebar.swift` | 6 | macOS NavigationSplitView |
| `Sources/EddingsApp/Navigation/AppTabBar.swift` | 6 | iOS TabView |
| `Sources/EddingsApp/Search/SearchView.swift` | 6 | Search interface |
| `Sources/EddingsApp/Finance/FreedomDashboard.swift` | 6 | Freedom Velocity dashboard |
| `Sources/EddingsApp/Meetings/MeetingList.swift` | 6 | Meeting browser |
| `Sources/EddingsApp/Contacts/ContactList.swift` | 6 | Contact intelligence |
| `Sources/EddingsKit/CloudSync/iCloudManager.swift` | 7 | CKSyncEngine wrapper |
| `com.vram.eddings-index.plist` | 8 | Launch agent definition |
| `Sources/EddingsWidgets/FreedomVelocityWidget.swift` | 9 | Home screen widget |
| `Sources/EddingsWidgets/NetWorthWidget.swift` | 9 | Net worth widget |

---

## Dependencies

| Dependency | Source | Purpose | iOS | macOS |
|------------|--------|---------|-----|-------|
| `GRDB.swift` 7.0+ | github.com/groue/GRDB.swift | SQLite + FTS5 + migrations | Yes | Yes |
| `USearch` 2.0+ | github.com/unum-cloud/usearch | HNSW vector similarity search | Yes | Yes |
| `swift-argument-parser` 1.5+ | github.com/apple/swift-argument-parser | CLI subcommands | No (CLI only) | Yes |
| Foundation | Apple SDK | URLSession, FileManager, JSONCoder, Keychain | Yes | Yes |
| NaturalLanguage | Apple SDK | 512-dim sentence embeddings | Yes (13+) | Yes (10.15+) |
| CoreML | Apple SDK | 4096-dim Qwen3 embeddings | Yes (11+) | Yes (10.13+) |
| CloudKit | Apple SDK | CKSyncEngine iCloud sync | Yes (17+) | Yes (14+) |
| SwiftUI | Apple SDK | Multiplatform UI | Yes (13+) | Yes (10.15+) |
| WidgetKit | Apple SDK | Home screen widgets | Yes (14+) | Yes (11+) |
| AppIntents | Apple SDK | Siri integration | Yes (16+) | Yes (13+) |
| CoreSpotlight | Apple SDK | System Spotlight indexing | Yes (9+) | Yes (10.13+) |
| os (Logger) | Apple SDK | Structured logging | Yes (14+) | Yes (11+) |
| Security | Apple SDK | Keychain SecItem APIs | Yes (2+) | Yes (10.0+) |
| Observation | Apple SDK | @Observable macro | Yes (17+) | Yes (14+) |
| Charts | Apple SDK | Financial data visualization | Yes (16+) | Yes (13+) |
| BackgroundTasks | Apple SDK | iOS background sync (BGAppRefreshTask, BGProcessingTask) | Yes (13+) | N/A |
| LocalAuthentication | Apple SDK | Face ID / Touch ID for financial data protection | Yes (8+) | Yes (10.12.1+) |

Three external dependencies. Fourteen Apple SDK frameworks. Zero servers. Zero runtimes.

---

## Success Criteria

When all phases are complete:

1. **TheEddingsIndex syncs alongside existing tools** — `ei-cli sync --all` pulls from SimpleFin, reads QBO CSVs, reads VRAM filesystem data written by existing agents — no existing scripts modified
2. **Search your reality from your phone** — type "Optro" on iOS and see the kick-off meeting, emails, Slack messages, and invoice across five data sources
3. **Freedom Velocity on your home screen** — glance at the widget, see $X,XXX / $6,058 without opening an app
4. **Native search on-device** — SQLite FTS5 + USearch HNSW provides BM25-ranked search on Mac and iPhone without a server roundtrip
5. **Live meeting indexing** — Conversift feeds transcripts to TheEddingsIndex in real time, searchable within 30 seconds
6. **"What's my net worth?" via Siri** — AppIntents surfaces financial data through voice
7. **Additive, not destructive** — existing TypeScript search engine, PostgreSQL, and all launch agents continue running. TheEddingsIndex coexists until Ron decides otherwise
