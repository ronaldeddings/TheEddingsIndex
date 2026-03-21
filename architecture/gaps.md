# Gaps & Missing Implementations

Known gaps between the planned architecture and current implementation, categorized by severity.

---

## Critical Gaps

### 1. CoreMLEmbedder Is a Stub

**Status:** `Sources/EddingsKit/Embedding/CoreMLEmbedder.swift` throws `EmbeddingError.modelUnavailable` on all calls. The init itself throws, making the type unconstructible.

**Impact:** All 4096-dim embeddings require the external Qwen3 HTTP server at port 8081 to be running. If the server is down, search falls back to FTS-only with no semantic component on macOS.

**What's needed:** CoreML model compilation of Qwen3, or alternatively accept HTTP dependency as the production architecture and remove the stub.

---

## Moderate Gaps

### 2. iOS Background Tasks — Partially Implemented

**Status:** PRD-05 implemented real handlers: `handleRefresh` runs `FinanceSyncPipeline`, `handleProcessing` runs full sync + `EmbeddingPipeline`. Expiration handlers call `setTaskCompleted(success: false)`. Task submission errors are logged.

**Remaining:** `UIBackgroundModes` capability still requires Xcode project edit (fetch + processing). Without this capability, tasks are registered but never scheduled by the system.

### 3. CalDAV Calendar Sync Is a Stub

**Status:** `Sources/EddingsKit/Sync/CalDAVClient.swift` logs "CalDAV sync not yet implemented — Phase 5 stub" and returns 0.

**Impact:** Meeting data only comes from Fathom transcripts. Calendar events without transcripts (e.g., events not recorded by Fathom) are not captured.

### 4. Widget Snapshot Generation Only Runs During Finance Sync

**Status:** `widgetSnapshots` rows are only created by `FinanceSyncPipeline.run()`. If finance sync fails or is skipped, widget data goes stale.

**Impact:** Widgets show stale data. No independent refresh mechanism.

### 5. Financial Precision Uses Double Instead of Decimal

**Status:** `Sources/EddingsKit/Models/Transaction.swift:12` has a TODO:
```
// TODO: PRD-01 specifies Decimal — evaluate migration cost for financial precision
```

All financial amounts use `Double`, which has floating-point precision issues for currency calculations.

**Impact:** Potential rounding errors in financial aggregations, Freedom Tracker calculations, and net worth display. Unlikely to cause visible issues at current scale but violates PRD-01 specification.

---

### 6. Intelligence Stubs (RelationshipScorer, ActivityDigest)

**Status:** Two intelligence modules exist as files but have minimal or stub implementations:

- **RelationshipScorer** (`Sources/EddingsKit/Intelligence/RelationshipScorer.swift`) — Stubbed
- **ActivityDigest** (`Sources/EddingsKit/Intelligence/ActivityDigest.swift`) — Stubbed

Note: **AnomalyDetector** is actually fully implemented (unusual amounts via std deviation, duplicate charge detection, price increase detection) — not a stub.

**Impact:** No relationship depth scoring or activity summaries are generated.

### 7. Categorizer Missing Tier 3 (Heuristics) and Tier 4 (PAI Inference)

**Status:** The Categorizer implements Tier 1 (exact merchant lookup, 70+ entries) and Tier 2 (regex pattern matching, ~20 patterns). Tier 3 (amount-based heuristics) is partially implemented. Tier 4 (PAI inference via `Tools/Inference.ts`) is not implemented.

**Impact:** Transactions not matching known merchants or patterns remain uncategorized.

### 8. Test Coverage Very Low

**Status:** 5 test files with approximately 24 tests covering ~6,600+ lines of production code (<1% direct coverage).

**Tested:**
- FTS search, HybridRanker, Finance pipeline (Normalizer, Deduplicator, FreedomTracker), QBOReader, Semantic search, Vector migration

**Not tested:**
- EmbeddingPipeline, FileWatcher, DataAccess, all ViewModels
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

### 9. FileWatcher Missing `kFSEventStreamCreateFlagWatchRoot` Flag

**Status:** `FileWatcher.swift:27` checks `rootChanged` events and pauses indexing, but line 76-79 does not include `kFSEventStreamCreateFlagWatchRoot` in the stream creation flags. Without this flag, the kernel may never deliver `RootChanged` events.

**Apple doc:** `coreservices/kfseventstreamcreateflagwatchroot.md` — "Monitors changes to the path itself (renames, parent directory changes). Generates RootChanged events."

**Impact:** VRAM unmount detection via `rootChanged` may not work as intended. The `isUnmount` flag still works for volume unmount events.

---

## Minor Gaps

### 10. No Xcode Project File

**Status:** The project uses SPM-only builds. Widget extensions and app targets are declared in `Package.swift` but WidgetKit extensions typically require an Xcode project for proper provisioning, capabilities (App Groups, iCloud), and entitlements.

**Impact:** The SwiftUI app and widget extension likely can't be built and signed for device deployment without an `.xcodeproj` or `.xcworkspace`. CLI builds work fine via `scripts/build.sh`.

### 11. SpotlightIndexer Exists But May Not Be Invoked

**Status:** `Sources/EddingsKit/Search/SpotlightIndexer.swift` has methods to index contacts and documents into Spotlight, but no caller was found in sync pipelines or app lifecycle.

**Impact:** Spotlight search integration exists as code but may not be active.

### 12. Search Default Temporal Window

**Status:** When no temporal filter is specified, FTSIndex defaults to the last 3 months (`Calendar.current.date(byAdding: .month, value: -3, to: Date())`). This is undocumented in the CLI help text.

**Impact:** Users may be confused when older results don't appear. The `--year` or `--since` flags must be explicitly used to search beyond 3 months.

### 13. FileWatcher Uses `Unmanaged.passUnretained(self)` in FSEvents Callback

**Status:** `FileWatcher.swift:70` passes actor reference to C callback without retaining. If the actor is deallocated before the callback fires, this is a use-after-free.

**Impact:** Low in practice (watcher lifetime = process lifetime due to `dispatchMain()`), but is an unsafe pattern. Apple doc (`coreservices/1443980-fseventstreamcreate.md`) leaves lifetime management to the developer.

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

## Resolved Gaps (PRD-05/06/07)

The following gaps were resolved in the last 96 hours:

| Former Gap | Resolution | PRD |
|-----------|-----------|-----|
| New data receives no embeddings | `EmbeddingPipeline` actor: batch `run()` + single-record `embedRecord()` | PRD-05 |
| SwiftUI views use hardcoded data | 5 ViewModels wired to `DataAccess` + GRDB; ContactList, MeetingList, FreedomDashboard all live | PRD-06 |
| pendingEmbeddings table has no writers | `EmbeddingPipeline` writes on failure; `retryPendingEmbeddings()` processes up to 500 | PRD-05 |
| Documents and financials have no embeddings | `EmbeddingPipeline.embeddableTables` includes both | PRD-05 |
| No 512-dim embedding pipeline | `EmbeddingPipeline` generates 512-dim via NLEmbedder for every record | PRD-05 |
| Contact and meeting search returns nil | `DataAccess.resolveSearchResult()` handles both `.contacts` and `.meetings` | PRD-06 |
| 12-hour polling latency | FSEvents watcher (`FileWatcher`) provides ~3-second ingestion; `ei-cli watch` replaces `sync --all` in launch agent | PRD-07 |
| iOS background tasks are stubs | `handleRefresh` runs `FinanceSyncPipeline`, `handleProcessing` runs full sync + embedding. Expiration handlers fixed. | PRD-05 |
| NLEmbedding revision not tracked | `NLEmbedder.currentRevision` stored in `vectorKeyMap.embeddingRevision` (v3 migration) | PRD-05 |
| Keychain/BackgroundTasks/Widget/CKSync API issues | 12 of 17 Apple API compliance issues fixed (see apple-api-compliance.md) | PRD-05 |

---

## PRD Alignment Summary

| PRD Feature | Status |
|-------------|--------|
| SimpleFin + QBO finance sync | Implemented |
| Freedom Tracker (velocity calc) | Implemented (backend + UI) |
| Transaction categorization | Implemented (Tier 1 + 2; Tier 3/4 missing) |
| Transaction deduplication (exact + fuzzy) | Implemented |
| FTS5 full-text search | Implemented |
| Hybrid search (FTS + semantic) | Implemented |
| PostgreSQL migration | Implemented |
| iCloud CKSyncEngine sync | Implemented (zone verified, all events handled, batch limits) |
| SwiftUI 3-column layout | Implemented (live data via ViewModels + DataAccess) |
| iOS widgets | Implemented (cached DB pool, isPreview check, relevance scoring) |
| Real-time embedding generation | Implemented (EmbeddingPipeline + FileWatcher) |
| FSEvents file watcher | Implemented (10 VRAM paths, 2s coalescing, route-to-client) |
| Data cutoff policy (Oct 2025) | Implemented (all sync clients enforce) |
| Build & distribution pipeline | Implemented (scripts/build.sh — sign, DMG, notarize) |
| iOS background sync | Partially implemented (handlers work; UIBackgroundModes capability missing) |
| CalDAV calendar sync | Stub only |
| CoreML in-process embeddings | Stub only |
| Decimal precision for finance | Not implemented (uses Double) |
| Spotlight indexing | Code exists, may not be wired |
