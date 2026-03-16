# PRD-03: TheEddingsIndex — Implementation Correctness Review

**Status:** ACTIVE
**Date:** 2026-03-16
**Author:** PAI
**Audit Method:** 15 parallel agents (10 Codex, 5 Gemini) reviewing codebase against `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/` + PRD-01 + PRD-02
**Target:** Identify and document all implementation deviations from Apple frameworks documentation, PRD specifications, and correctness requirements — with evidence from Apple Developer Documentation

---

## Executive Summary

A comprehensive audit of TheEddingsIndex codebase (57 Swift source files) against 384 Apple Developer Documentation framework directories and the PRD-01/PRD-02 specifications revealed **52 findings**: 7 critical, 13 high, 21 medium, and 11 low severity.

**The three systemic failures are:**

1. **iCloud sync is a hollow shell.** `CKSyncEngine` is initialized but the delegate implementation discards all incoming changes and never pushes local changes. Per `.../CloudKit/CKSyncEngineDelegate-1q7g8/README.md`, the delegate MUST implement `handleEvent(_:syncEngine:)` to process `fetchedRecordZoneChanges` AND `nextRecordZoneChangeBatch(_:syncEngine:)` must return actual record batches. The current implementation returns `nil` — zero upstream sync.

2. **Hybrid search produces corrupt results.** Vector search results are hardcoded to `SourceTable.documents` regardless of actual source. The RRF ranker merges scores by `Int64` primary key without table qualification, causing cross-table ID collisions. After any app restart, `VectorIndex.vectorCount` resets to 0 and all vector search returns empty.

3. **Widgets, background sync, and App Group infrastructure are entirely absent.** PRD-02 Phase 9 specifies `BGAppRefreshTask`, `BGProcessingTask`, App Group shared container, WAL mode, `widgetSnapshots` table, and `WidgetCenter.shared.reloadAllTimelines()`. None exist. Widgets render hardcoded placeholder data.

**This PRD documents each finding with Apple Developer Documentation evidence, maps it to the PRD-02 requirement it violates, and defines the acceptance criteria for the fix.**

---

## Findings by Severity

### CRITICAL — Show-Stoppers (7 findings)

These break core functionality defined in PRD-02. The system cannot achieve its stated goals with these defects present.

---

#### C-1: CKSyncEngine Never Pushes Local Changes to iCloud

**File:** `Sources/EddingsKit/CloudSync/iCloudManager.swift:76-81`
**PRD-02 Reference:** Phase 7, Step 7.1 — "Implement delegate callbacks for `pendingChanges`"
**PRD-02 Risk Table:** "CKSyncEngine State.Serialization must be persisted across launches"

**Apple Doc Evidence:**
Per `.../CloudKit/CKSyncEngineDelegate-1q7g8/nextRecordZoneChangeBatch(__syncEngine_)/README.md`: The system calls this method to obtain the next batch of record changes to send to the server. The delegate must return a `CKSyncEngine.RecordZoneChangeBatch` populated with pending changes, or `nil` only when there are no more changes to send.

Per `.../CloudKit/CKSyncEngine-5sie5/README.md`: To schedule changes for upload, call `state.add(pendingRecordZoneChanges:)`. The sync engine then calls `nextRecordZoneChangeBatch` to retrieve these changes for transmission.

**Expected (per PRD-02 line 813-819):**
```swift
nonisolated func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
) -> CKSyncEngine.RecordZoneChangeBatch? {
    return buildNextBatch(context: context)  // PRD-02 specifies building batches
}
```

**Actual (line 79-81):**
```swift
return nil  // Always nil — zero records ever sent
```

**Impact:** iCloud sync is unidirectional receive-only. No local data (contacts, transactions, categorizations) reaches iCloud. iOS devices receive nothing. PRD-02 Verification V-17 ("Changes on macOS must appear on iOS within 60 seconds") is structurally impossible.

Additionally, no calls to `syncEngine.state.add(pendingRecordZoneChanges:)` exist anywhere in the codebase. Even if `nextRecordZoneChangeBatch` were implemented, the engine has no pending changes to send.

**Acceptance Criteria:**
- [x] `nextRecordZoneChangeBatch` returns populated `RecordZoneChangeBatch` when pending changes exist
- [x] Local record mutations call `syncEngine.state.add(pendingRecordZoneChanges:)` to schedule uploads
- [ ] Unit test: insert contact locally → verify CKRecord created and queued

---

#### C-2: CKSyncEngine Discards All Incoming Remote Changes

**File:** `Sources/EddingsKit/CloudSync/iCloudManager.swift:65-66`
**PRD-02 Reference:** Phase 7, Step 7.3 — "Receive remote changes, upsert into local SQLite"

**Apple Doc Evidence:**
Per `.../CloudKit/CKSyncEngine-5sie5/Event/README.md`: The `fetchedRecordZoneChanges` event contains `.modifications` (array of `CKRecord` objects) and `.deletions` (array of record IDs). The delegate must process these to keep local state synchronized.

Per `.../CloudKit/CKSyncEngine-5sie5/README.md`: CKSyncEngine manages the lifecycle of fetching and sending record zone changes. The delegate is responsible for applying fetched changes to the local store.

**Expected (per PRD-02 line 801-802):**
```swift
case .fetchedRecordZoneChanges(let changes):
    processRemoteChanges(changes)  // PRD-02 specifies processing changes
```

**Actual (line 65-66):**
```swift
case .fetchedRecordZoneChanges(let changes):
    logger.info("Fetched \(changes.modifications.count) modifications, \(changes.deletions.count) deletions")
    // No processing — modifications and deletions are discarded
```

**Impact:** Remote data from other devices is acknowledged but never written to the local database. PRD-02 Verification V-18 ("Modify on iOS, check Mac — Changes appear within 60s") is impossible.

**Acceptance Criteria:**
- [x] `fetchedRecordZoneChanges` decodes `CKRecord` objects into GRDB models and upserts into SQLite
- [x] Deletions remove corresponding local records
- [x] `categoryModifiedAt` field-level conflict resolution per PRD-02 Phase 7 Step 7.5

---

#### C-3: Semantic Search Results Hardcoded to `.documents` Source Table

**File:** `Sources/EddingsKit/Search/QueryEngine.swift:38-40`
**PRD-02 Reference:** Phase 1, Step 1.5 — "Deduplicate results across FTS and semantic by record ID"

**Evidence:**
```swift
semanticResults = hits.map { hit in
    (id: Int64(hit.key), sourceTable: SearchResult.SourceTable.documents, distance: hit.distance)
    //                                                       ^^^^^^^^^^^ hardcoded
}
```

**Impact:** All semantic search hits — regardless of whether the underlying record is an email, Slack message, transcript, or financial transaction — are classified as documents. When `resolveResult` (line 58-124) attempts to fetch the record, it calls `Document.fetchOne(db, key: result.id)` which either:
- Returns `nil` (email chunk id=42 has no matching document id=42) → result silently dropped
- Returns the WRONG document (document id=42 exists but is unrelated to the search) → corrupt result

**Acceptance Criteria:**
- [x] Vector keys encode source table information (e.g., composite key or separate mapping table)
- [x] `semanticResults` carry correct `SourceTable` values
- [ ] Unit test: embed an email chunk, search semantically, verify result has `sourceTable == .emailChunks`

---

#### C-4: HybridRanker Cross-Table ID Collision in RRF Fusion

**File:** `Sources/EddingsKit/Search/HybridRanker.swift:19`
**PRD-02 Reference:** Phase 1, Step 1.5 — "Deduplicate results across FTS and semantic by record ID"

**Evidence:**
```swift
var scores: [Int64: (score: Double, sourceTable: SearchResult.SourceTable)] = [:]
//           ^^^^^ keyed only by id — not globally unique
```

SQLite `rowid` / `autoIncrementedPrimaryKey("id")` values are unique **per table**, not globally. Email chunk `id=5` and document `id=5` are distinct records. The `scores` dictionary merges them, corrupting both scores and overwriting one source table with the other.

**PRD-02's own HybridRanker code (line 648)** shows the same bug in the spec:
```swift
var scores: [Int64: Double] = [:]  // Same per-table-only keying
```

This means the PRD design itself has this flaw — the implementation faithfully reproduced a specification bug.

**Acceptance Criteria:**
- [x] Ranker uses composite key `(id: Int64, sourceTable: SourceTable)` as `Hashable` dictionary key
- [ ] Unit test: insert FTS result (id=5, emailChunks) and semantic result (id=5, documents) → both appear in output as distinct entries

---

#### C-5: VectorIndex.vectorCount Not Persisted — Search Breaks After Restart

**File:** `Sources/EddingsKit/Storage/VectorIndex.swift:89, 100`
**PRD-02 Reference:** Phase 1, Step 1.4 — "`search(vector:count:)` — similarity search with cosine metric"

**Evidence:**
```swift
private var vectorCount: Int = 0  // Line 100 — never loaded from index file

public func search(vector: [Float], count: Int = 20) throws -> [SearchHit] {
    guard vectorCount > 0 else { return [] }  // Line 89 — always fails after restart
```

After app launch, `vectorCount` is 0 even if the USearch index file contains 382K vectors. The guard returns `[]` for every search.

Per USearch documentation (`usearch/swift/USearchIndex.swift`): `USearchIndex` exposes a `count` property that returns the number of vectors in the loaded index. This should be used instead of a manually tracked counter.

**Acceptance Criteria:**
- [x] After `load()` or `view()`, read `index512.count` (or equivalent USearch API) to initialize `vectorCount`
- [x] Remove manual counter in favor of index introspection
- [ ] Unit test: add vectors → save → create new `VectorIndex` from same directory → `count512 > 0` and `search()` returns results

---

#### C-6: iOS VectorIndex Is Immutable After `view()` — Cannot Add New Vectors

**File:** `Sources/EddingsKit/Storage/VectorIndex.swift:22-24`
**PRD-02 Reference:** Phase 1, Step 1.4; Phase 9 Phase 5 — incremental embedding on iOS

**Apple Doc Evidence:**
Per USearch source (`usearch/include/usearch/index.hpp:2929`):
```cpp
usearch_assert_m(!is_immutable(), "Can't add to an immutable index");
```

`index.view()` creates a memory-mapped read-only view of the file. Per USearch documentation, `view()` produces an immutable index. The `add()` function asserts mutability — calling it on a viewed index triggers a fatal assertion failure.

**Expected (per PRD-02 line 550-553):**
```swift
#if os(iOS)
index512 = USearchIndex.make(metric: .cos, dimensions: 512, connectivity: 16)
if FileManager.default.fileExists(atPath: path512.path) {
    index512.view(path: path512.path)  // mmap — not loaded into RAM
}
```

PRD-02 acknowledges iOS uses `view()` for memory efficiency but does not address the mutability constraint for incremental embedding on iOS.

**Impact:** iOS app crashes (assertion failure) when trying to add new embeddings after loading the existing index. Background sync embedding generation on iOS is impossible.

**Acceptance Criteria:**
- [x] iOS uses `load()` with INT8 quantization (smaller memory footprint than Float32) OR
- [x] iOS maintains a separate "pending" mutable index for new vectors, merged on save
- [ ] Unit test: on iOS target, `view()` index, then `add()` → no crash

---

#### C-7: Widgets Render Hardcoded Data — Zero Database Access

**File:** `Sources/EddingsWidgets/FreedomVelocityWidget.swift:21-25, 102`
**PRD-02 Reference:** Phase 9, Steps 9.2-9.4

**Apple Doc Evidence:**
Per `.../WidgetKit/README.md`: Widgets display glanceable, relevant content. Timeline providers supply entries that the system uses to update the widget.

Per `.../Foundation/FileManager/README.md`: `containerURL(forSecurityApplicationGroupIdentifier:)` returns the container directory for the specified App Group identifier, enabling data sharing between an app and its extensions.

**Expected (per PRD-02 line 1359-1363):**
```
App Group ID: group.com.hackervalley.eddingsindex
Database path: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.hackervalley.eddingsindex")
GRDB DatabaseQueue in WAL mode for concurrent reader (widget) + writer (app)
Widget reads widgetSnapshots table — never loads USearch index (30MB memory limit)
```

**Actual:**
```swift
let entry = FreedomVelocityEntry(
    date: .now,
    weeklyAmount: 2847,     // Hardcoded literal
    weeklyTarget: 6058,     // Hardcoded literal
    velocityPercent: 47      // Hardcoded literal
)
```

Codebase search results:
- `containerURL(forSecurityApplicationGroupIdentifier:)` → 0 occurrences
- `group.com.hackervalley.eddingsindex` → 0 occurrences
- `widgetSnapshots` → 0 occurrences in schema or code
- `WidgetCenter.shared.reloadAllTimelines()` → 0 occurrences
- WAL mode configuration → 0 occurrences

**Impact:** Widgets are purely cosmetic. PRD-02 Verification V-24 ("Widget reads from App Group — Freedom Velocity visible") is impossible.

**Acceptance Criteria:**
- [x] Database path resolves via App Group shared container
- [x] `DatabaseManager` configures WAL mode: `config.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode=WAL") }`
- [x] `widgetSnapshots` table added to schema migration
- [x] Widget timeline provider reads from shared database
- [x] `FinanceSyncPipeline.run()` calls `WidgetCenter.shared.reloadAllTimelines()` after writing

---

### HIGH — Significant Issues (13 findings)

These don't break the system entirely but produce incorrect results, violate PRD requirements, or create safety hazards.

---

#### H-1: `@unchecked Sendable` on iCloudManager With Mutable State

**File:** `Sources/EddingsKit/CloudSync/iCloudManager.swift:6`
**PRD-02 Reference:** Architecture (line 758) — "actor iCloudManager: CKSyncEngineDelegate"

**Apple Doc Evidence:**
Per `.../CloudKit/CKSyncEngineDelegate-1q7g8/README.md`: The sync engine calls delegate methods from its internal dispatch queue. Per Swift 6 strict concurrency: `@unchecked Sendable` on a class with mutable state (`private var syncEngine: CKSyncEngine?`) asserts thread safety without proving it.

**Expected (per PRD-02 line 758):**
```swift
actor iCloudManager: CKSyncEngineDelegate {  // PRD-02 specifies actor
```

**Actual:**
```swift
public final class iCloudManager: @unchecked Sendable {  // Class, not actor
```

**Acceptance Criteria:**
- [x] Convert to `actor` or add explicit synchronization for `syncEngine` property
- [x] Delegate methods use `nonisolated` where required by CKSyncEngine callback thread

---

#### H-2: EddingsEngine Not Isolated to @MainActor

**File:** `Sources/EddingsApp/EddingsApp.swift:32`
**PRD-02 Reference:** Phase 6, Step 6.1

**Apple Doc Evidence:**
Per `.../Observation/README.md`: `@Observable` types publish property changes to SwiftUI views. SwiftUI requires all UI state mutations to occur on the main thread. Per `.../SwiftUI/README.md`: Views are always evaluated on the main actor.

**Expected (per PRD-02 line 903):**
```swift
@Observable
final class TheEddingsIndex {  // PRD-02 names it TheEddingsIndex, not EddingsEngine
    let db: DatabaseManager
    let queryEngine: QueryEngine
    // ... actual connections to data layer
}
```

**Actual:**
```swift
@Observable
final class EddingsEngine {  // No @MainActor, no data connections
    var searchResults: [SearchResult] = []  // Dummy — not connected to QueryEngine
    var searchQuery: String = ""
}
```

**Acceptance Criteria:**
- [x] Add `@MainActor` annotation to `EddingsEngine`
- [x] Connect to `DatabaseManager`, `QueryEngine`, and `FreedomTracker`
- [x] Search query changes trigger actual `QueryEngine.search()` calls

---

#### H-3: Account Change Handling Incomplete

**File:** `Sources/EddingsKit/CloudSync/iCloudManager.swift:51-53`
**PRD-02 Reference:** Phase 7 (line 793-798), Risk Table (line 1485)

**Apple Doc Evidence:**
Per `.../CloudKit/CKSyncEngineAccountChangeType/README.md`: Account changes can be `.signIn`, `.signOut`, or `.switchAccounts`. Per `.../CloudKit/CKSyncEngine-5sie5/README.md`: The engine "resets its internal state, including unsaved changes to both records and record zones" on account change.

**Expected (per PRD-02 line 831-838):**
Flush pending local writes to SQLite before accepting state reset. Notify user.

**Actual:**
```swift
private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
    logger.warning("iCloud account changed — sync state reset.")
    // No flush, no user notification, no state management
}
```

**Acceptance Criteria:**
- [x] Flush all pending CKRecord changes to local SQLite before reset
- [x] Differentiate between `.signOut` (pause sync) and `.switchAccounts` (clear + re-sync)

---

#### H-4: FreedomTracker Counts HVM Salary as Non-W2 Income

**File:** `Sources/EddingsKit/Intelligence/FreedomTracker.swift:69-73`
**PRD-01 Reference:** Phase 3, Step 3.3 — "Read HVM distributions from QBO data (filter `deposits.csv` for owner's draw / distribution entries)"

**Evidence:**
```swift
let nonW2 = transactions.filter { txn in
    txn.amount > 0 &&
    txn.source == "qbo" &&
    !(txn.payee ?? "").lowercased().contains("mozilla")
}
```

HVM pays Ron a $62K/year salary. QBO deposits include BOTH owner's draws/distributions (non-W2) AND salary payments (W2). The filter only excludes "mozilla" but not HVM salary entries.

Per PRD-01 (line 460): "Read HVM distributions from QBO data (filter `deposits.csv` for owner's draw / distribution entries)." The PRD explicitly requires filtering to distributions only.

**Impact:** Freedom Velocity is inflated by ~$1,192/week ($62K ÷ 52), making the metric unreliable for the Freedom Acceleration Plan.

**Acceptance Criteria:**
- [x] Filter non-W2 income to owner's draws and client payments only
- [x] Exclude any transaction matching HVM salary payment patterns
- [ ] Unit test: insert HVM salary + distribution + Mozilla salary → only distribution counted

---

#### H-5: seenTransactionIds Not Persisted — Dedup Breaks on Restart

**File:** `Sources/EddingsKit/Storage/StateManager.swift:48-55`
**PRD-01 Reference:** Phase 2, Step 2.3 — "Track seen transaction IDs per account (rolling 90-day window)"

**Evidence:**
`StateManager` encodes `SyncState` to JSON via `JSONEncoder`, but `SyncState` does not include `seenTransactionIds`. The `seenIds` set is held in memory only.

Additionally, `FinanceSyncPipeline.swift:124-128` wraps the update in a fire-and-forget `Task`:
```swift
func updateSeenIds(_ ids: Set<String>) {
    Task { await updateSeenIdsAsync(ids) }  // Fire-and-forget — no error handling
}
```

**Impact:** After app restart, all previously seen transactions are treated as new. Duplicate records inserted into database on every sync cycle.

**Acceptance Criteria:**
- [x] `SyncState` includes a `seenTransactionIds: Set<String>` property that is Codable
- [x] `updateSeenIds` uses structured `await` (not unstructured `Task`)
- [ ] Unit test: set seen IDs → serialize → deserialize → IDs match

---

#### H-6: Freedom Velocity Calculated From Current Batch Only

**File:** `Sources/EddingsKit/Sync/FinanceSyncPipeline.swift:74-78`
**PRD-01 Reference:** Phase 3, Step 3.3 — "Calculate weekly non-W2 take-home: `totalDistributions / weeksElapsed`"

**Evidence:**
```swift
let allTransactions = catResult.categorized + catResult.uncategorized
let freedomScore = freedomTracker.calculate(
    snapshots: snapshots,
    transactions: allTransactions  // Only current sync batch, not full history
)
```

A 12-week metric divided by 12 but computed from potentially 1 week of new transactions produces wildly inaccurate results.

**Acceptance Criteria:**
- [x] Query full 12-week transaction history from SQLite for Freedom Velocity calculation
- [x] `weeksElapsed` computed dynamically from `min(transactionDate)` to `max(transactionDate)`

---

#### H-7: NLEmbedding Dimension Varies by Language — Hardcoded 512 Is Incorrect

**File:** `Sources/EddingsKit/Embedding/NLEmbedder.swift:5`
**PRD-02 Reference:** Phase 4, Step 4.1

**Apple Doc Evidence:**
Per `.../NaturalLanguage/NLEmbedding/README.md`: `NLEmbedding` provides word and sentence embeddings. Per `.../NaturalLanguage/NLEmbedding/dimension/README.md`: The `dimension` property returns the dimensionality of the embedding space, which varies by language model.

The `NLEmbedder.dimensions` property is hardcoded to `512`, but `NLEmbedding.sentenceEmbedding(for:)` may return models with different dimensions depending on the language.

**Impact:** If a non-English language model returns a different-dimensioned vector, inserting it into the 512-dim USearch index would either crash or produce corrupt search results.

**Acceptance Criteria:**
- [x] After obtaining an `NLEmbedding` instance, read its `.dimension` property
- [x] Verify vector dimension matches VectorIndex expectation before insertion
- [x] If mismatch, use English fallback (which is documented as 512-dim)

---

#### H-8: FTS Query Sanitizer Passes Dangerous Input as Boolean Operators

**File:** `Sources/EddingsKit/Storage/FTSIndex.swift:138-140`
**PRD-02 Reference:** Phase 1, Step 1.3 — "Support quoted phrases, boolean operators (AND/OR/NOT)"

**Evidence:**
```swift
if trimmed.contains("AND") || trimmed.contains("OR") || trimmed.contains("NOT") || trimmed.contains("NEAR") {
    return trimmed  // Pass through raw — including invalid syntax
}
```

A user searching for "bacon and eggs" triggers the passthrough because the string contains "and" → treated as FTS5 `AND` operator → `"bacon"` is not a valid FTS expression by itself → SQLite throws a syntax error.

Per SQLite FTS5 documentation: malformed `MATCH` expressions cause the query to fail with an error, not return empty results.

**Acceptance Criteria:**
- [x] Case-sensitive check for FTS operators (FTS5 operators are uppercase: `AND`, `OR`, `NOT`)
- [x] Validate FTS expression before execution, fall back to tokenized query on syntax error
- [x] Consider GRDB's `FTS5Pattern(matchingAllTokensIn:)` for safe pattern construction

---

#### H-9: PostgresMigrator FTS Rebuild Doesn't Recreate Sync Triggers

**File:** `Sources/EddingsKit/Sync/PostgresMigrator.swift:356-410`
**PRD-02 Reference:** Phase 3, Step 3.1 — "DROP all FTS5 virtual tables before insert... recreate FTS5 tables"

**Evidence:**
GRDB's `synchronize(withTable:)` creates SQLite triggers that keep the FTS table in sync with the content table on INSERT/UPDATE/DELETE. When `dropFTSTables()` drops the FTS virtual tables, these triggers are also dropped.

`rebuildFTSTables()` recreates FTS tables using raw SQL with `content=tableName, content_rowid=id` — this creates a content-synced external content FTS5 table, but does NOT recreate the automatic sync triggers that GRDB's `synchronize(withTable:)` provides.

Per SQLite FTS5 documentation: External content FTS5 tables require the application to manually keep the FTS index in sync with the content table unless triggers are explicitly created.

**Impact:** After migration, any new inserts/updates/deletes to content tables do NOT propagate to FTS indexes. Full-text search becomes stale.

**Acceptance Criteria:**
- [x] After migration, run the GRDB migrator again to recreate FTS tables with proper sync triggers, OR
- [x] Manually create the three triggers (INSERT, DELETE, UPDATE) per SQLite FTS5 external content documentation

---

#### H-10: RelationshipScorer Weights All Interactions Equally

**File:** `Sources/EddingsKit/Intelligence/RelationshipScorer.swift:35`
**PRD-02 Reference:** Architecture — Contact intelligence, relationship depth

**Evidence:**
```swift
let total = contact.emailCount + contact.meetingCount + contact.slackCount
```

200 Slack messages = 200 meetings = `.deep` relationship. A CISO who had one 60-minute meeting is scored lower than a bot that sent 201 Slack notifications.

**Acceptance Criteria:**
- [x] Weighted scoring: meetings × 5 + emails × 2 + slack × 1 (or similar)
- [x] "Fading" threshold scales with relationship depth (14 days too aggressive for deep connections)

---

#### H-11: ActivityDigest.daily() Returns Monthly Totals

**File:** `Sources/EddingsKit/Intelligence/ActivityDigest.swift`
**PRD-02 Reference:** Intelligence layer — daily/weekly summaries

**Evidence (from audit):** Database queries filter by `Column("year") == year && Column("month") == month` but never by day. The "daily" digest returns the entire month's aggregate on any given day.

**Acceptance Criteria:**
- [x] Filter queries include day component: `Column("day") == day`
- [x] Or use date range: `>= startOfDay AND < endOfDay`

---

#### H-12: No WAL Mode Configured for Concurrent Access

**File:** `Sources/EddingsKit/Storage/DatabaseManager.swift:10-11`
**PRD-02 Reference:** Phase 9, Step 9.2 (line 1362)

**Apple Doc Evidence:**
Per SQLite documentation and GRDB docs: WAL (Write-Ahead Logging) mode enables concurrent readers and a single writer. Without WAL, any write operation blocks all readers — including widget extensions trying to read snapshots.

**Expected (per PRD-02 line 1362):**
"GRDB `DatabaseQueue` configured in WAL mode for concurrent reader (widget) + writer (app/background task)."

**Actual:**
```swift
let config = Configuration()  // Default config — no WAL mode
dbPool = try DatabasePool(path: path, configuration: config)
```

Note: `DatabasePool` already uses WAL mode by default in GRDB. However, the PRD says `DatabaseQueue` with WAL. The implementation uses `DatabasePool` which is correct for concurrent access. The real issue is that there's no App Group shared container — WAL mode is moot without a shared database path.

**Acceptance Criteria:**
- [x] Verify GRDB `DatabasePool` enables WAL mode (it does by default — confirm)
- [x] Database path must be in App Group shared container for widget access

---

#### H-13: sentRecordZoneChanges Failures Not Handled

**File:** `Sources/EddingsKit/CloudSync/iCloudManager.swift:68-69`
**PRD-02 Reference:** Phase 7 — iCloud sync error handling

**Apple Doc Evidence:**
Per `.../CloudKit/CKSyncEngine-5sie5/README.md`: The `sentRecordZoneChanges` event includes `failedRecordSaves` with per-record error information. Recoverable errors (`.serverRecordChanged`, `.zoneNotFound`) should be retried. Non-recoverable errors should be reported.

**Actual:**
```swift
case .sentRecordZoneChanges(let sentChanges):
    logger.info("Sent \(sentChanges.savedRecords.count) records, \(sentChanges.failedRecordSaves.count) failures")
    // No error inspection, no retry, no conflict resolution
```

**Acceptance Criteria:**
- [x] Inspect `failedRecordSaves` for per-record errors
- [x] Retry on `.serverRecordChanged` with conflict resolution
- [x] Log non-recoverable errors with record details

---

### MEDIUM — Needs Attention (21 findings)

| ID | Finding | File | PRD Ref | Apple Doc Evidence |
|----|---------|------|---------|-------------------|
| M-1 | Keychain: no differentiation between background and interactive credentials | KeychainManager.swift:19 | PRD-02 Phase 2 | Per `.../Security/SecItemAdd(____).md`: `kSecAttrAccessible` controls when items are available. PRD says background creds use `kSecAttrAccessibleAfterFirstUnlock`, interactive use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| M-2 | Keychain: no biometric binding | KeychainManager.swift | PRD-02 Security | Per `.../Security/SecAccessControlCreateWithFlags(____).md`: `SecAccessControlCreateWithFlags` with `.userPresence` binds to biometrics. PRD requires this for interactive credentials |
| M-3 | Keychain: delete-then-add upsert is non-atomic | KeychainManager.swift:12 | — | Per `.../Security/SecItemUpdate(____).md`: `SecItemUpdate` atomically updates existing items. Delete+add has a visibility gap |
| M-4 | RRF offset is +1 from standard formula | HybridRanker.swift:21 | PRD-02 Phase 1 | Standard RRF: `1/(k + rank)`. Implementation: `1/(k + rank + 1)`. Rank 0 gets `1/(k+1)` instead of `1/k` |
| M-5 | RRF candidate pool at 2x is insufficient | QueryEngine.swift:29 | PRD-02 Phase 1 | Research literature recommends 3-10x over-fetch for quality RRF fusion |
| M-6 | No FTS5 snippet highlighting | QueryEngine.swift:67 | PRD-02 Phase 1 | Per SQLite FTS5 docs: `snippet(table, column, open, close, ellipsis, tokens)` extracts contextual text around matches |
| M-7 | 2% weekly growth = 180% annual in freedom projection | FreedomTracker.swift:83 | PRD-01 Phase 3 | Unrealistic. 10-20% annual growth more defensible |
| M-8 | Net worth counts nil/unknown accountType as assets | FreedomTracker.swift:30-32 | PRD-01 Phase 3 | PRD-01 defines explicit `AccountType` enum. Filter should use allowlist, not denylist |
| M-9 | weeksElapsed defaults to 12 regardless of transaction span | FreedomTracker.swift:25 | PRD-01 Phase 3 | Should derive from actual transaction date range |
| M-10 | AnomalyDetector 2σ flags ~5% of all transactions | AnomalyDetector.swift:36 | PRD-01 Phase 7 | 3σ threshold or IQR/MAD better for skewed financial data |
| M-11 | StateManager double-saves on seenIds mutation | StateManager.swift:48-55 | — | Computed setter triggers save(), and `didSet` also triggers save() |
| M-12 | iOS/macOS 512-dim indexes use different quantization | VectorIndex.swift:16,27 | PRD-02 Phase 1 | iOS: `.i8`, macOS: `.f32`. Distances not directly comparable across platforms |
| M-13 | VectorIndex save is crash-unsafe (delete before move) | VectorIndex.swift:126-127 | PRD-02 Risk Table | If crash between `removeItem` and `moveItem`, index file is lost. Use atomic rename |
| M-14 | Missing pendingEmbeddings GRDB model | DatabaseManager.swift:217 | PRD-02 Phase 1 | Table exists in schema but no `FetchableRecord`/`PersistableRecord` model |
| M-15 | FinancialSnapshot.snapshotDate uses Date precision but unique key expects daily | BalanceSnapshot.swift:6 | PRD-02 Schema | Multiple syncs per day with millisecond-different timestamps bypass uniqueKey |
| M-16 | Double for money across all transaction handling | Transaction.swift:12 | PRD-01 Models | PRD-01 specifies `Decimal` for `amount`. Implementation uses `Double` — floating point precision issues |
| M-17 | FathomClient doesn't extract speaker names from transcripts | FathomClient.swift:55 | PRD-02 Phase 5 | `speakerName` field is nil. Per PRD-02 step 5.4: "Parse transcript text, identify speakers" |
| M-18 | Slack deduplication by full chunkText equality is fragile | SlackClient.swift:59-62 | PRD-02 Phase 5 | Slack export files can be regenerated with different formatting. Content-hash or message-ID based dedup is more robust |
| M-19 | No Slack speaker → Contact linkage | SlackClient.swift:67-69 | PRD-02 Phase 5 | Per PRD-02 step 5.6: "Auto-extract contacts from email headers, Slack usernames, meeting participants" |
| M-20 | "Fading" threshold of 14 days too aggressive | RelationshipScorer.swift:41 | PRD-02 Intelligence | A CISO contact with 51 interactions who takes a 2-week vacation is marked "fading" |
| M-21 | SimpleFin JSON decoder strategy conflict | SimpleFinClient.swift:103 | PRD-01 Phase 1 | `.convertFromSnakeCase` applied globally but `SimpleFinAccount` has explicit `CodingKeys` for kebab-case. Custom CodingKeys take precedence, so this works, but the redundant strategy is confusing |

---

### LOW — Minor Issues (11 findings)

| ID | Finding | File | Note |
|----|---------|------|------|
| L-1 | `DatabaseManager.inMemory()` creates temp file, not in-memory | DatabaseManager.swift:16-19 | Method name misleads. Use `DatabaseQueue()` with no path for true in-memory |
| L-2 | No App Group database path for widget sharing | DatabaseManager.swift | Must use `containerURL(forSecurityApplicationGroupIdentifier:)` |
| L-3 | No `WidgetCenter.shared.reloadAllTimelines()` after sync | FinanceSyncPipeline.swift | Per `.../WidgetKit/WidgetCenter/README.md`: call to refresh widgets |
| L-4 | No WindowGroup sizing constraints on macOS | EddingsApp.swift:9 | Per `.../SwiftUI/WindowGroup/README.md`: `.defaultSize()`, `.windowResizability()` |
| L-5 | No scene storage / state restoration | EddingsApp.swift:35 | Per `.../SwiftUI/SceneStorage/README.md`: `@SceneStorage` persists navigation state |
| L-6 | FileScanner truncates at 50K chars, PRD says SmartChunker | FileScanner.swift:52 | Per PRD-02 step 5.1: "Chunk content via SmartChunker" |
| L-7 | FileScanner loads all paths into memory per scan area | FileScanner.swift:38 | `getExistingPaths()` called inside area loop — should cache once |
| L-8 | SmartChunker 500-word target likely too large for NLEmbedding | SmartChunker.swift:7 | Per `.../NaturalLanguage/finding-similarities-between-pieces-of-text/README.md`: sentence embeddings designed for phrases/sentences |
| L-9 | SmartChunker overlap can start mid-sentence | SmartChunker.swift:54 | Last N words extracted without sentence boundary respect |
| L-10 | DateFormatter created per-call in PostgresMigrator | PostgresMigrator.swift:414 | Performance: create once, reuse across 900K+ rows |
| L-11 | AnomalyDetector uses population stddev (N) not sample (N-1) | AnomalyDetector.swift:32 | Bessel's correction should apply for small samples |

---

## GAP ANALYSIS: PRD-02 Phase 9 vs Implementation

Per `.../BackgroundTasks/README.md`, `.../BackgroundTasks/BGAppRefreshTask/README.md`, `.../BackgroundTasks/BGProcessingTask/README.md`, `.../BackgroundTasks/BGTaskScheduler/README.md`:

| PRD-02 Requirement | Apple Doc | Implementation Status |
|--------------------|-----------|---------------------|
| `BGAppRefreshTask` (30 sec quick sync) | `.../BackgroundTasks/BGAppRefreshTask/README.md` | **Not implemented** — zero references in codebase |
| `BGProcessingTask` (heavy sync, idle+power) | `.../BackgroundTasks/BGProcessingTask/README.md` | **Not implemented** — zero references |
| `BGTaskScheduler.shared.register()` | `.../BackgroundTasks/BGTaskScheduler/README.md` | **Not implemented** — zero references |
| Info.plist `BGTaskSchedulerPermittedIdentifiers` | `.../BackgroundTasks/refreshing-and-maintaining-your-app-using-background-tasks/README.md` | **Not implemented** — no Info.plist exists |
| Checkpoint-based sync (commit every 100 records) | PRD-02 line 1354 | **Not implemented** — `FinanceSyncPipeline` writes all records in single transaction |
| `NSFaceIDUsageDescription` in Info.plist | `.../Security/SecAccessControlCreateWithFlags(____).md` | **Not implemented** — no Info.plist exists |
| App Group shared container | `.../Foundation/FileManager/README.md` `containerURL(forSecurityApplicationGroupIdentifier:)` | **Not implemented** — zero references |
| `widgetSnapshots` pre-calculation table | PRD-02 line 1363 | **Not implemented** — not in schema |
| WAL mode for concurrent access | GRDB documentation | **Partially implemented** — `DatabasePool` uses WAL by default, but no shared container |
| `WidgetCenter.shared.reloadAllTimelines()` | `.../WidgetKit/WidgetCenter/README.md` | **Not implemented** — zero references |
| iCloud bidirectional sync | `.../CloudKit/CKSyncEngine-5sie5/README.md` | **Receive-only stub** — delegate logs but doesn't process |
| `categoryModifiedAt` conflict resolution | PRD-02 line 1275-1278 | **Not implemented** — no conflict resolution code exists |
| `CoreSpotlight` indexing | `.../CoreSpotlight/README.md` | **Not implemented** — zero references |
| `AppIntents` / Siri | `.../AppIntents/README.md` | **Not implemented** — zero references |

---

## Implementation Priority

Based on the dependency graph and PRD phase ordering:

### Sprint 1: Fix Search (C-3, C-4, C-5, H-8)
Search is the foundation. Everything else depends on being able to find data.
- Fix vector key → source table mapping
- Fix HybridRanker composite key
- Fix vectorCount persistence
- Fix FTS query sanitization

### Sprint 2: Fix iCloud Sync (C-1, C-2, H-1, H-3, H-13)
Sync is the bridge between macOS and iOS.
- Implement CKRecord → model decoding for incoming changes
- Implement model → CKRecord encoding for outgoing changes
- Convert iCloudManager to actor
- Implement account change flush
- Handle sent-changes failures

### Sprint 3: Fix Finance Pipeline (H-4, H-5, H-6, M-16)
Freedom Velocity is the most personally meaningful metric.
- Fix non-W2 income filter (exclude HVM salary)
- Persist seenTransactionIds in SyncState
- Query full 12-week history for Freedom Velocity
- Consider Decimal for money (breaking change — evaluate cost)

### Sprint 4: Fix iOS Infrastructure (C-6, C-7, H-12)
iOS is the daily-use platform.
- Fix VectorIndex iOS mutability
- Implement App Group shared container
- Add widgetSnapshots table and real data access
- Configure WAL mode explicitly
- Add WidgetCenter refresh calls

### Sprint 5: BackgroundTasks + Polish (GAP items)
- Implement BGAppRefreshTask and BGProcessingTask
- Add Info.plist with task identifiers and NSFaceIDUsageDescription
- Implement checkpoint-based sync (100-record commits)
- Fix EddingsEngine @MainActor + data connections

---

## Files Modified by This PRD

| File | Findings | Changes Required |
|------|----------|-----------------|
| `iCloudManager.swift` | C-1, C-2, H-1, H-3, H-13 | Complete rewrite — actor, full delegate implementation |
| `QueryEngine.swift` | C-3, M-5 | Fix source table mapping, increase over-fetch multiplier |
| `HybridRanker.swift` | C-4, M-4 | Composite key, fix RRF offset |
| `VectorIndex.swift` | C-5, C-6, M-12, M-13 | Persist vectorCount, fix iOS mutability, atomic save |
| `FreedomVelocityWidget.swift` | C-7 | Read from shared database instead of hardcoded values |
| `DatabaseManager.swift` | H-12, L-1 | Add widgetSnapshots table, WAL mode, App Group path |
| `FreedomTracker.swift` | H-4, H-6, M-7, M-8, M-9 | Fix income filter, dynamic weeks, realistic growth |
| `StateManager.swift` | H-5, M-11 | Persist seenIds, fix double-save |
| `FTSIndex.swift` | H-8, M-6 | Safe query parsing, add snippet support |
| `PostgresMigrator.swift` | H-9, L-10 | Recreate sync triggers, cache DateFormatter |
| `RelationshipScorer.swift` | H-10, M-20 | Weighted scoring, scale fading threshold |
| `ActivityDigest.swift` | H-11 | Filter by day, not just month |
| `NLEmbedder.swift` | H-7 | Verify dimensions match before insertion |
| `EddingsApp.swift` | H-2, L-4, L-5 | @MainActor, window sizing, state restoration |
| `KeychainManager.swift` | M-1, M-2, M-3 | Differentiated access levels, biometric binding |
| `AnomalyDetector.swift` | M-10, L-11 | Adjust threshold, use sample stddev |
| `FathomClient.swift` | M-17 | Extract speaker names from transcript content |
| `SlackClient.swift` | M-18, M-19 | Robust dedup, contact linkage |
| `SmartChunker.swift` | L-8, L-9 | Smaller chunks, sentence-boundary overlap |
| `FileScanner.swift` | L-6, L-7 | Use SmartChunker, cache existing paths |
| `SimpleFinClient.swift` | M-21 | Remove redundant decoder strategy |
| `FinanceSyncPipeline.swift` | L-3 | Add WidgetCenter refresh |
| **NEW: Info.plist** | GAP | BGTask identifiers, NSFaceIDUsageDescription |

---

## Verification Additions (Extending PRD-02 V-table)

| ID | Check | Method | Pass Criteria |
|----|-------|--------|---------------|
| V-28 | Vector search works after restart | Kill app → relaunch → search | Results returned (vectorCount > 0) |
| V-29 | Semantic results carry correct source table | Insert email + search semantically | Result.sourceTable == .emailChunks |
| V-30 | Cross-table IDs don't collide in ranker | Insert email(id=5) + doc(id=5) + search | Both appear as separate results |
| V-31 | Freedom Velocity excludes HVM salary | Sync with HVM salary + distribution | Only distribution counted |
| V-32 | seenTransactionIds survive restart | Sync → restart → sync | 0 duplicates on second sync |
| V-33 | Widget shows live data | Sync → check widget | Freedom Velocity matches database |
| V-34 | "bacon and eggs" search doesn't crash | Search for "bacon and eggs" | Results returned, no FTS error |
| V-35 | CKSyncEngine pushes local changes | Insert contact → wait 60s → check iCloud Dashboard | Record exists in CloudKit |
| V-36 | CKSyncEngine applies remote changes | Modify via CloudKit Dashboard → wait → check local DB | Local record updated |
