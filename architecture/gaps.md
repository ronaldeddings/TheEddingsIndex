# Gaps & Missing Implementations

Known gaps between the planned architecture and current implementation, categorized by severity.

---

## Critical Gaps

### 1. New Data Receives No Embeddings

**Status:** Records added via sync pipelines (new emails, Slack messages, transcripts) do NOT receive Qwen 4096-dim embeddings. Only the one-time PostgreSQL migration populates vectors. This means hybrid search quality degrades over time as the ratio of unembedded records grows.

**Files affected:**
- `Sources/EddingsKit/Sync/SyncCommand.swift` — no embedding step after data insertion
- `Sources/EddingsKit/Sync/IMAPClient.swift` — inserts to SQLite only
- `Sources/EddingsKit/Sync/SlackClient.swift` — inserts to SQLite only
- `Sources/EddingsKit/Sync/FathomClient.swift` — inserts to SQLite only

**What's needed:** A post-sync embedding job that:
1. Queries records missing from `vectorKeyMap`
2. Generates embeddings via QwenClient (or NLEmbedder for 512-dim)
3. Adds vectors to USearch
4. Records mappings in `vectorKeyMap`

### 2. CoreMLEmbedder Is a Stub

**Status:** `Sources/EddingsKit/Embedding/CoreMLEmbedder.swift` throws `EmbeddingError.modelUnavailable` on all calls. The init itself throws, making the type unconstructible.

**Impact:** All 4096-dim embeddings require the external Qwen3 HTTP server at port 8081 to be running. If the server is down, search falls back to FTS-only with no semantic component on macOS.

**What's needed:** CoreML model compilation of Qwen3, or alternatively accept HTTP dependency as the production architecture and remove the stub.

### 3. SwiftUI App Views Use Hardcoded Data

**Status:** All main app views display hardcoded/mock data instead of querying the database:

- **ContactList** (`Sources/EddingsApp/Contacts/ContactList.swift`) — Hardcoded contact rows: "Emily Humphrey", "Marcus Webb", "Sarah Chen", "Jess Park", "Chris Cochran". Not wired to SQLite contacts table.

- **MeetingList** (`Sources/EddingsApp/Meetings/MeetingList.swift`) — Hardcoded meeting rows: "CISO Roundtable Prep", "Emily 1:1", "Optro Kick-off". Not wired to SQLite meetings table.

- **FreedomDashboard** (`Sources/EddingsApp/Finance/FreedomDashboard.swift`) — Hardcoded `@State` values: `velocityPercent = 47`, `weeklyAmount = 2847`. Stats grid has hardcoded values ("$89,490", "$8,437", "$13,105", "$62,000"). Projection text is hardcoded ("November 2027", "CrowdStrike", "Optro"). Not wired to `widgetSnapshots` or `financialTransactions` tables.

**Impact:** The SwiftUI app is a visual prototype only. It demonstrates the design system correctly but shows zero live data. Only `SearchView` and `EddingsEngine` appear to be wired to the actual database.

**What's needed:** Replace hardcoded data in each view with GRDB queries to the database. Use `@Observable` patterns on `EddingsEngine` to expose live data.

---

## Moderate Gaps

### 4. iOS Background Tasks Are Stubs

**Status:** `Sources/EddingsKit/Sync/BackgroundTaskManager.swift` registers both task identifiers but the handlers are empty:

```swift
// TODO: Implement quick transaction check    (line 37)
// TODO: Implement full sync with checkpointing    (line 51)
```

Both `handleRefresh()` and `handleProcessing()` immediately call `task.setTaskCompleted(success: true)` without doing any work.

**Impact:** iOS app will never sync data in the background. Data is only current when the app is actively open.

### 5. CalDAV Calendar Sync Is a Stub

**Status:** `Sources/EddingsKit/Sync/CalDAVClient.swift` logs "CalDAV sync not yet implemented — Phase 5 stub" and returns 0.

**Impact:** Meeting data only comes from Fathom transcripts. Calendar events without transcripts (e.g., events not recorded by Fathom) are not captured.

### 6. pendingEmbeddings Table Has No Writers

**Status:** The `pendingEmbeddings` table exists in the schema (migration v1) but no sync code writes to it. It was designed for iOS crash recovery during background embedding generation.

**Impact:** No crash recovery for in-flight embedding operations. If the app terminates during embedding, work is lost.

### 7. Documents and Financial Transactions Have No Embeddings

**Status:** Only transcriptChunks, emailChunks, and slackChunks received 4096-dim vectors during PostgreSQL migration. The `documents` and `financialTransactions` tables have no entries in `vectorKeyMap`.

**Impact:** Document and financial transaction search is FTS-only. Semantic search (e.g., "operational expenses for cloud infrastructure") won't surface relevant transactions unless the exact keywords match.

### 8. Widget Snapshot Generation Only Runs During Finance Sync

**Status:** `widgetSnapshots` rows are only created by `FinanceSyncPipeline.run()`. If finance sync fails or is skipped, widget data goes stale.

**Impact:** Widgets show stale data. No independent refresh mechanism.

### 9. Financial Precision Uses Double Instead of Decimal

**Status:** `Sources/EddingsKit/Models/Transaction.swift:12` has a TODO:
```
// TODO: PRD-01 specifies Decimal — evaluate migration cost for financial precision
```

All financial amounts use `Double`, which has floating-point precision issues for currency calculations.

**Impact:** Potential rounding errors in financial aggregations, Freedom Tracker calculations, and net worth display. Unlikely to cause visible issues at current scale but violates PRD-01 specification.

---

### 10. Contact and Meeting Search Returns Nil

**Status:** `Sources/EddingsKit/Search/QueryEngine.swift:178-180` — The `resolveResult()` function returns `nil` for `.contacts` and `.meetings` source tables:

```swift
case .contacts, .meetings:
    return nil
```

**Impact:** Even if contacts or meetings are returned by FTS or semantic search, they are silently dropped during result resolution. Only document, email, Slack, transcript, and financial results are surfaced.

### 11. Intelligence Stubs (RelationshipScorer, ActivityDigest)

**Status:** Two intelligence modules exist as files but have minimal or stub implementations:

- **RelationshipScorer** (`Sources/EddingsKit/Intelligence/RelationshipScorer.swift`) — Stubbed
- **ActivityDigest** (`Sources/EddingsKit/Intelligence/ActivityDigest.swift`) — Stubbed

Note: **AnomalyDetector** is actually fully implemented (unusual amounts via std deviation, duplicate charge detection, price increase detection) — not a stub.

**Impact:** No relationship depth scoring or activity summaries are generated. The ContactList view can't sort by "depth" or "fading" from real data.

### 12. Categorizer Missing Tier 3 (Heuristics) and Tier 4 (PAI Inference)

**Status:** The Categorizer implements Tier 1 (exact merchant lookup, 70+ entries) and Tier 2 (regex pattern matching, ~20 patterns). Tier 3 (amount-based heuristics) is partially implemented. Tier 4 (PAI inference via `Tools/Inference.ts`) is not implemented.

**Impact:** Transactions not matching known merchants or patterns remain uncategorized. The intelligent categorization fallback that would use AI inference is missing.

### 13. Test Coverage Very Low

**Status:** 5 test files with approximately 24 tests covering ~6,600 lines of production code (<1% direct coverage).

**Tested:**
- FTS search, HybridRanker, Finance pipeline (Normalizer, Deduplicator, FreedomTracker), QBOReader, Semantic search, Vector migration

**Not tested:**
- All embedding providers (NLEmbedder, QwenClient, CoreMLEmbedder)
- QueryEngine with real vectors
- iCloud sync logic
- All sync clients (IMAPClient, SlackClient, FathomClient, CalDAVClient)
- ContactExtractor, SmartChunker
- All parsers (EmailParser, SlackParser, TranscriptParser) edge cases
- VectorIndex (iOS mmap, generation swap, pending index merge)
- DatabaseManager migrations
- KeychainManager
- All intelligence modules

**Impact:** High regression risk on changes. No way to validate correctness of sync pipelines or cross-device behavior without manual testing.

---

## Minor Gaps

### 14. No Xcode Project File

**Status:** The project uses SPM-only builds. Widget extensions and app targets are declared in `Package.swift` but WidgetKit extensions typically require an Xcode project for proper provisioning, capabilities (App Groups, iCloud), and entitlements.

**Impact:** The SwiftUI app and widget extension likely can't be built and signed for device deployment without an `.xcodeproj` or `.xcworkspace`. CLI builds work fine.

### 15. SpotlightIndexer Exists But May Not Be Invoked

**Status:** `Sources/EddingsKit/Search/SpotlightIndexer.swift` has methods to index contacts and documents into Spotlight, but no caller was found in sync pipelines or app lifecycle.

**Impact:** Spotlight search integration exists as code but may not be active.

### 16. No 512-dim Embedding Pipeline

**Status:** NLEmbedder exists and works, but no code generates 512-dim embeddings during sync or migration. The `reality-512.usearch` index appears to exist for iOS compatibility but may be empty unless populated externally.

**Impact:** iOS vector search may have no data if 512-dim embeddings were never generated.

### 17. Search Default Temporal Window

**Status:** When no temporal filter is specified, FTSIndex defaults to the last 3 months (`Calendar.current.date(byAdding: .month, value: -3, to: Date())`). This is undocumented in the CLI help text.

**Impact:** Users may be confused when older results don't appear. The `--year` or `--since` flags must be explicitly used to search beyond 3 months.

---

## By Design (Not Gaps)

These are intentional architectural decisions, not missing features:

| Decision | Rationale |
|----------|-----------|
| PostgreSQL coexists with SQLite | No migration pressure; both systems serve different use cases |
| Embeddings optional for search | FTS-only fallback ensures search always works |
| USearch indices not synced via iCloud | Too large for CK; rebuilt locally per device |
| Meeting recordings not synced | 665GB; macOS-only local access |
| VRAM filesystem not synced | External volume; macOS-only |
| 4096-dim only on macOS | Qwen3 server dependency; iOS uses 512-dim NLEmbedding |

---

## PRD Alignment Summary

| PRD Feature | Status |
|-------------|--------|
| SimpleFin + QBO finance sync | Implemented |
| Freedom Tracker (velocity calc) | Implemented (backend); hardcoded in UI |
| Transaction categorization | Implemented |
| Transaction deduplication (exact + fuzzy) | Implemented |
| FTS5 full-text search | Implemented |
| Hybrid search (FTS + semantic) | Implemented |
| PostgreSQL migration | Implemented |
| iCloud CKSyncEngine sync | Implemented |
| SwiftUI 3-column layout | Implemented (visual only, hardcoded data) |
| iOS widgets | Implemented (read from widgetSnapshots) |
| CalDAV calendar sync | Stub only |
| iOS background sync | Stub only |
| CoreML in-process embeddings | Stub only |
| Real-time embedding generation | Not implemented |
| Decimal precision for finance | Not implemented (uses Double) |
| Spotlight indexing | Code exists, may not be wired |
