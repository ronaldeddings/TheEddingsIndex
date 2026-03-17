# PRD-05: Production Readiness — Embedding Pipeline, Live UI & API Compliance

**Status:** ACTIVE
**Date:** 2026-03-16
**Author:** PAI
**Audit Method:** 10 parallel agents (5 codebase exploration, 5 Apple Developer Documentation cross-reference) auditing all 53 EddingsKit source files against `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/` across NaturalLanguage, CloudKit, BackgroundTasks, WidgetKit, Security, and CoreML frameworks
**Target:** Close the 3 critical gaps preventing TheEddingsIndex from being a functional product: (1) new data gets no embeddings, (2) SwiftUI views show hardcoded data, (3) Apple API misuse causes silent failures in Keychain, BackgroundTasks, WidgetKit, and CKSyncEngine

---

## Executive Summary

A comprehensive architecture audit of TheEddingsIndex (53 Swift files, 1.3M+ indexed records) against Apple Developer Documentation revealed that **the backend is solid but the system has three structural failures preventing production use:**

1. **The embedding pipeline is broken open-loop.** PostgresMigrator imported 345K+ vectors from PostgreSQL, but no code generates embeddings for new data. Every email, Slack message, and transcript added since migration has zero semantic representation. Hybrid search (RRF fusion with 60% semantic weight) returns increasingly degraded results as the unembedded data ratio grows. At current sync rates (~500 new records/day), semantic search will be irrelevant within 3 months.

2. **The SwiftUI app is a visual prototype.** ContactList, MeetingList, and FreedomDashboard display hardcoded data — "Emily Humphrey" with 127 emails, "$89,490" net worth, "November 2027" projection date. Only SearchView is wired to the database. The app looks correct but shows zero live information.

3. **Apple API misuse causes silent failures across 4 frameworks.** Keychain biometric protection uses conflicting flags (SecAccessControl + kSecAttrAccessible). BackgroundTasks expiration handler doesn't call `setTaskCompleted`. CKSyncEngine never verifies zone creation. WidgetKit opens a fresh DatabasePool on every timeline refresh in a 30MB-limited process.

**The fix:** Build a post-sync embedding job that closes the open loop, wire all SwiftUI views to GRDB queries, and correct 17 Apple API compliance issues identified by cross-referencing against the on-disk Apple Developer Documentation.

**Scope:**
- **In scope:** Embedding pipeline for new records, SwiftUI view data binding, Apple API compliance fixes (Keychain, BackgroundTasks, WidgetKit, CKSyncEngine), NLEmbedding revision pinning
- **Out of scope:** CoreML Qwen3 model conversion (requires external tooling), App Store submission, new UI features, new data sources

---

## Background & Evidence

### Audit Methodology

10 agents ran parallel audits:

| Domain | Agent Count | Focus |
|--------|------------|-------|
| EddingsKit core | 1 | Full 53-file architecture map — models, actors, services, storage |
| Embedding system | 1 | NLEmbedder, QwenClient, CoreMLEmbedder, VectorIndex, HybridRanker |
| Data flows | 1 | All 5 sync pipelines, search pipeline, PostgreSQL migration |
| Schema + gaps | 1 | SQLite tables, FTS5, PRD alignment, TODO/stub scan |
| CLI + app targets | 1 | Package.swift, commands, SwiftUI views, widgets |
| NaturalLanguage cross-ref | 1 | NLEmbedding API correctness, revision pinning, dimension verification |
| CKSyncEngine cross-ref | 1 | Delegate methods, state persistence, zone creation, conflict resolution |
| BackgroundTasks + WidgetKit cross-ref | 1 | Task scheduling, expiration handlers, timeline providers, memory limits |
| CoreML + Security cross-ref | 1 | MLModel requirements, Keychain API correctness, biometric flags |
| Code validation | 1 | Verified 80+ claims in architecture docs against source — 2 corrections applied |

### Finding 1: Embedding Pipeline Is Open-Loop

**Evidence (5 files examined):**

| Sync Client | File | Embeds After Insert? | Evidence |
|-------------|------|---------------------|----------|
| IMAPClient | `Sync/IMAPClient.swift:64` | NO | `chunk.insert(db, onConflict: .ignore)` — no embedding step |
| SlackClient | `Sync/SlackClient.swift:82` | NO | `chunk.insert(db)` — no embedding step |
| FathomClient | `Sync/FathomClient.swift:98` | NO | `chunk.insert(db)` — no embedding step |
| FileScanner | `Sync/FileScanner.swift:47` | NO | `doc.insert(db)` — no embedding step |
| FinanceSyncPipeline | `Sync/FinanceSyncPipeline.swift:71` | NO | `txn.upsert(db)` — no embedding step |

**PostgresMigrator is the ONLY vector source** (`Sync/PostgresMigrator.swift:380-440`): It queries PostgreSQL for existing embeddings and imports them into USearch. No other code path writes to VectorIndex or vectorKeyMap.

**vectorKeyMap table confirms the gap:**
- Records with vectors: only those migrated from PostgreSQL (transcriptChunks, emailChunks, slackChunks)
- Records without vectors: all documents, all financialTransactions, all records added post-migration

**HybridRanker impact** (`Search/HybridRanker.swift:13`): Semantic search gets 60% weight in RRF fusion. As unembedded records accumulate, the 60% semantic component returns fewer relevant matches, degrading overall search quality.

### Finding 2: SwiftUI Views Show Hardcoded Data

**Evidence (3 files examined):**

**ContactList.swift:55-63** — Hardcoded contact rows:
```swift
ContactRow(name: "Emily Humphrey", role: "COO, Hacker Valley Media", initials: "EH", depth: .high, emails: 127, meetings: 84, slack: 1247)
ContactRow(name: "Marcus Webb", role: "Content Lead, Hacker Valley", initials: "MW", depth: .high, emails: 45, meetings: 32, slack: 892)
```

**FreedomDashboard.swift:5-6** — Hardcoded state:
```swift
@State private var velocityPercent: Double = 47
@State private var weeklyAmount: Double = 2847
```

**FreedomDashboard.swift:102-105** — Hardcoded stats grid:
```swift
metricCard(title: "NET WORTH", value: "$89,490", change: "▲ $1,435 today", color: EIColor.emerald)
metricCard(title: "TOTAL DEBT", value: "$13,105", change: "Debt-free by Sep 2026", color: EIColor.rose)
```

**MeetingList.swift:19-23** — Hardcoded meetings:
```swift
meetingRow(title: "CISO Roundtable Prep", date: "Yesterday · 2:00 PM", duration: "45 min", ...)
meetingRow(title: "Emily 1:1 — Content Calendar", date: "Mar 12 · 3:30 PM", duration: "28 min", ...)
```

**EddingsEngine** (`EddingsApp/EddingsApp.swift:62`) does initialize DatabaseManager and QueryEngine, but only SearchView uses them. All other views ignore the engine entirely.

### Finding 3: Apple API Compliance Issues (17 total)

Cross-referenced against `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/`:

#### Security/Keychain (4 issues)

| # | Issue | File:Line | Apple Doc | Impact |
|---|-------|-----------|-----------|--------|
| K-1 | SecAccessControl + kSecAttrAccessible used together when biometric=true | `Auth/KeychainManager.swift:28-35` | `.../Security/SecAccessControlCreateWithFlags(____).md`: "You can't combine these constraints" | Biometric protection may silently fail |
| K-2 | Missing `kSecUseDataProtectionKeychain` on macOS | `Auth/KeychainManager.swift:41` | `.../Security/kSecAttrAccessible.md`: Required for modern keychain on macOS 10.15+ | SimpleFin URL stored in legacy keychain without data protection |
| K-3 | No `kSecAttrAccessGroup` for widget extension | `Auth/KeychainManager.swift:41` | `.../Security/kSecAttrAccessGroup.md` | Widget can't access SimpleFin credentials |
| K-4 | Biometric denial returns nil instead of throwing | `Auth/KeychainManager.swift:73` | `.../Security/errSecInteractionNotAllowed.md` | UI can't distinguish "not found" from "user denied" |

#### BackgroundTasks (5 issues)

| # | Issue | File:Line | Apple Doc | Impact |
|---|-------|-----------|-----------|--------|
| B-1 | Expiration handler doesn't call `setTaskCompleted(success: false)` | `Sync/BackgroundTaskManager.swift:41-42` | `.../BackgroundTasks/BGTask/setTaskCompleted(success_).md`: "Call this before expiration or system kills app" | App terminated on timeout |
| B-2 | Reschedule called before async work completes | `Sync/BackgroundTaskManager.swift:33` | `.../BackgroundTasks/BGTaskScheduler/submit(_).md`: "Replaces previous request" | Tight retry loop on failure |
| B-3 | `try? BGTaskScheduler.shared.submit()` silently discards errors | `Sync/BackgroundTaskManager.swift:22,29` | `.../BackgroundTasks/BGTaskScheduler/submit(_).md`: Throws `tooManyPendingTaskRequests`, `notPermitted` | Tasks never scheduled, no diagnosis |
| B-4 | Missing `UIBackgroundModes` capability | Xcode project (not in code) | `.../BackgroundTasks/refreshing-and-maintaining-your-app-using-background-tasks/README.md` | System won't schedule tasks without capability |
| B-5 | TODO stubs in both handlers | `Sync/BackgroundTaskManager.swift:37,51` | — | `handleRefresh` and `handleProcessing` do no work |

#### WidgetKit (4 issues)

| # | Issue | File:Line | Apple Doc | Impact |
|---|-------|-----------|-----------|--------|
| W-1 | `getSnapshot()` ignores `context.isPreview` | `EddingsWidgets/FreedomVelocityWidget.swift:43` | `.../WidgetKit/TimelineProvider/getSnapshot(in_completion_).md` | Widget gallery shows wrong data or times out |
| W-2 | Fresh `DatabasePool` created per timeline call | `EddingsWidgets/FreedomVelocityWidget.swift:20` | `.../WidgetKit/README.md`: 30MB RAM limit | High memory churn in constrained process |
| W-3 | Missing `TimelineEntry.relevance` | `EddingsWidgets/FreedomVelocityWidget.swift:5-10` | `.../WidgetKit/TimelineEntryRelevance/README.md` | No Smart Stack ranking on iOS 17+ |
| W-4 | 6-hour reload may exhaust daily budget | `EddingsWidgets/FreedomVelocityWidget.swift:55` | `.../WidgetKit/README.md`: Limited daily refresh budget | Two widgets × 4/day = 8 refreshes may exceed budget |

#### CloudKit/CKSyncEngine (3 issues)

| # | Issue | File:Line | Apple Doc | Impact |
|---|-------|-----------|-----------|--------|
| CK-1 | Zone `EddingsData` never explicitly created | `CloudSync/iCloudManager.swift:12` | `.../CloudKit/CKSyncEngine-5sie5/README.md` | First sync may fail if zone doesn't auto-create |
| CK-2 | 7+ delegate events ignored (willFetch, didFetch, etc.) | `CloudSync/iCloudManager.swift:530-547` | `.../CloudKit/CKSyncEngine-5sie5/Event/README.md` | No sync progress UI, no zone-level error handling |
| CK-3 | No batch size limits in `buildNextBatch` | `CloudSync/iCloudManager.swift:83-105` | `.../CloudKit/CKSyncEngine-5sie5/README.md` | Large pending sets may hit CloudKit limits |

#### NaturalLanguage (1 issue)

| # | Issue | File:Line | Apple Doc | Impact |
|---|-------|-----------|-----------|--------|
| NL-1 | No embedding revision pinning | `Embedding/NLEmbedder.swift:24` | `.../NaturalLanguage/NLEmbedding/currentSentenceEmbeddingRevision(for_).md` | OS update could change model, misaligning stored vectors |

---

## Architecture

### Design Principles

1. **Close the embedding loop.** Every record inserted during sync must have an embedding generated before the next search cycle. The pipeline should be: sync → insert → embed → index.
2. **Graceful degradation.** If the Qwen server is down, fall back to 512-dim NLEmbedding. If NLEmbedding fails for a record, log and skip — never block sync.
3. **Incremental, not bulk.** Embedding generation should process records missing from `vectorKeyMap`, not reprocess the entire corpus.
4. **Platform-aware.** macOS uses Qwen 4096-dim when available, NLEmbedding 512-dim always. iOS uses NLEmbedding 512-dim only. Both platforms populate their respective USearch indices.
5. **Fix APIs before adding features.** Correct Apple API misuse first — silent failures mask real bugs.

### Embedding Pipeline Architecture

```
                   ┌──────────────────────────────────────────┐
                   │            Sync Pipeline (existing)       │
                   │  IMAPClient → SlackClient → FathomClient  │
                   │  FileScanner → FinanceSyncPipeline        │
                   └───────────────────┬──────────────────────┘
                                       │ records inserted
                                       ▼
                   ┌──────────────────────────────────────────┐
                   │       EmbeddingPipeline (NEW)             │
                   │                                           │
                   │  1. Query records missing from vectorKeyMap│
                   │  2. Batch text extraction (100 at a time)  │
                   │  3. Generate embeddings:                   │
                   │     macOS: QwenClient(4096) → NLEmbedder(512)│
                   │     iOS:   NLEmbedder(512) only            │
                   │  4. Add to VectorIndex                     │
                   │  5. Record in vectorKeyMap                 │
                   │  6. Write to pendingEmbeddings on failure  │
                   └──────────────────────────────────────────┘
```

### SwiftUI Data Binding Architecture

```
                   ┌──────────────────────────────────────────┐
                   │          EddingsEngine (@Observable)      │
                   │          @MainActor                        │
                   │                                           │
                   │  DatabaseManager ──→ GRDB DatabasePool    │
                   │  QueryEngine    ──→ search()              │
                   │  VectorIndex    ──→ semantic search        │
                   │                                           │
                   │  Published Properties:                     │
                   │  • contacts: [Contact]                    │
                   │  • meetings: [Meeting]                    │
                   │  • freedomScore: FreedomScore             │
                   │  • searchResults: [SearchResult]          │
                   └───────────────────┬──────────────────────┘
                                       │ observed by
                         ┌─────────────┼─────────────┐
                         │             │             │
                    ContactList   MeetingList   FreedomDashboard
                    (live query)  (live query)  (live query)
```

---

## Implementation Phases

### Phase 1 (P0): Apple API Compliance Fixes

**Goal:** Correct silent failures before building new features on top of broken APIs.

- [ ] 1.1 — **Keychain: Fix SecAccessControl conflict** (`Auth/KeychainManager.swift:28-35`). When `biometric: true`, use ONLY `kSecAttrAccessControl` — remove separate `kSecAttrAccessible`. Per `.../Security/SecAccessControlCreateWithFlags(____).md`.
- [ ] 1.2 — **Keychain: Add kSecUseDataProtectionKeychain on macOS** (`Auth/KeychainManager.swift:41`). Add `kSecUseDataProtectionKeychain: true` to all query dictionaries when `#if os(macOS)`. Per `.../Security/kSecAttrAccessible.md`.
- [ ] 1.3 — **Keychain: Add kSecAttrAccessGroup for widget sharing** (`Auth/KeychainManager.swift`). Set `kSecAttrAccessGroup: "group.com.hackervalley.eddingsindex"` on iOS queries. Per `.../Security/kSecAttrAccessGroup.md`.
- [ ] 1.4 — **Keychain: Differentiate biometric denial from not-found** (`Auth/KeychainManager.swift:73`). Check for `errSecInteractionNotAllowed` and throw `KeychainError.biometricDenied` instead of returning nil.
- [ ] 1.5 — **BackgroundTasks: Fix expiration handler** (`Sync/BackgroundTaskManager.swift:41-42,55-56`). Add `task.setTaskCompleted(success: false)` after `operation.cancel()`. Per `.../BackgroundTasks/BGTask/setTaskCompleted(success_).md`.
- [ ] 1.6 — **BackgroundTasks: Move reschedule after work** (`Sync/BackgroundTaskManager.swift:33,47`). Move `scheduleRefresh()`/`scheduleProcessing()` calls inside the async Task block, after work completes.
- [ ] 1.7 — **BackgroundTasks: Log submission errors** (`Sync/BackgroundTaskManager.swift:22,29`). Replace `try?` with `do/try/catch` and log specific error types.
- [ ] 1.8 — **Widget: Check context.isPreview in getSnapshot()** (`EddingsWidgets/FreedomVelocityWidget.swift:43`). Load real data for non-preview; return placeholder for preview. Per `.../WidgetKit/TimelineProvider/getSnapshot(in_completion_).md`.
- [ ] 1.9 — **Widget: Cache DatabasePool** (`EddingsWidgets/FreedomVelocityWidget.swift:20`). Use static shared pool instead of creating fresh per call. Stay within 30MB widget RAM limit.
- [ ] 1.10 — **CKSyncEngine: Verify zone creation** (`CloudSync/iCloudManager.swift:19`). In `start()`, check for zone existence and create if needed before starting sync.
- [ ] 1.11 — **NLEmbedding: Add revision tracking** (`Embedding/NLEmbedder.swift`). After obtaining embedding, log `NLEmbedding.currentSentenceEmbeddingRevision(for: language)`. Store revision in vectorKeyMap or a new column. Per `.../NaturalLanguage/NLEmbedding/currentSentenceEmbeddingRevision(for_).md`.
- [ ] 1.12 — **Build + test** — `swift build && swift test`

**Guard:** Zero `try?` on BGTaskScheduler submissions. Keychain biometric denial throws distinct error. Widget uses cached DB pool.

### Phase 2 (P0): Embedding Pipeline

**Goal:** Every new record gets an embedding. Hybrid search quality stops degrading.

- [ ] 2.1 — **Create `EmbeddingPipeline.swift`** (`Sources/EddingsKit/Embedding/EmbeddingPipeline.swift`). New actor that orchestrates post-sync embedding generation.
- [ ] 2.2 — **Query unembedded records.** SQL: `SELECT id FROM {table} WHERE id NOT IN (SELECT sourceId FROM vectorKeyMap WHERE sourceTable = '{table}')` for each content table (emailChunks, slackChunks, transcriptChunks, documents).
- [ ] 2.3 — **Extract text for embedding.** For each unembedded record, extract the text field to embed: `chunkText` for chunks, `content` for documents, `description || ' ' || payee` for financial transactions.
- [ ] 2.4 — **Batch embedding generation.** Process in batches of 100. For each batch:
  - Try QwenClient (4096-dim) if available and on macOS
  - Always generate NLEmbedder (512-dim) as baseline
  - On QwenClient failure, log and continue with 512-dim only
- [ ] 2.5 — **Add vectors to VectorIndex.** Call `vectorIndex.add(key: nextKey, vector512: nlVector, vector4096: qwenVector)` for each successful embedding.
- [ ] 2.6 — **Record in vectorKeyMap.** Insert `(vectorKey, sourceTable, sourceId)` for each embedded record.
- [ ] 2.7 — **Write failures to pendingEmbeddings.** If embedding fails (server timeout, NLEmbedding returns nil), write to `pendingEmbeddings` table for retry on next cycle. This activates the crash recovery table that currently has no writers (architecture/gaps.md, gap #6).
- [ ] 2.8 — **Retry pending embeddings.** At pipeline start, check `pendingEmbeddings` table and retry before processing new records.
- [ ] 2.9 — **Wire into SyncCommand.** After all sync clients complete in `SyncCommand.swift`, call `EmbeddingPipeline.run()`. This closes the open loop.
- [ ] 2.10 — **Save VectorIndex after embedding.** Call `vectorIndex.save()` after all batches complete (generation-swapped atomic save).
- [ ] 2.11 — **Progress logging.** Log at every 100 records: `"Embedded 100/4,521 emailChunks (22 in 4.2s)"`.
- [ ] 2.12 — **Test: Run sync + embed pipeline.** `ei-cli sync --all` should show embedding stats.
- [ ] 2.13 — **Test: Search quality.** Search for a recently synced email — should appear in hybrid results, not FTS-only.
- [ ] 2.14 — **Test: Graceful degradation.** Stop Qwen server → run embed → verify 512-dim embeddings generated, no crashes.

**Guard:** `ei-cli sync --all` prints embedding statistics. `ei-cli search --json "recent topic"` returns hybrid results for recently synced content.

### Phase 3 (P1): Wire SwiftUI Views to Live Data

**Goal:** Every view shows real data from the database.

- [ ] 3.1 — **Extend EddingsEngine** (`EddingsApp/EddingsApp.swift`). Add `@MainActor` annotation. Add published properties: `contacts: [Contact]`, `meetings: [Meeting]`, `freedomScore: FreedomScore`, `widgetSnapshot: WidgetSnapshot?`.
- [ ] 3.2 — **Add data loading methods to EddingsEngine.** `loadContacts()` queries contacts table sorted by relationship depth. `loadMeetings()` queries meetings with participants. `loadFreedomScore()` runs FreedomTracker on last 12 weeks.
- [ ] 3.3 — **Wire ContactList to EddingsEngine.** Replace hardcoded rows with `@Environment(EddingsEngine.self)` observation. Query contacts with email/meeting/slack counts. Group into Inner Circle / Growing / Fading based on RelationshipScorer.
- [ ] 3.4 — **Wire MeetingList to EddingsEngine.** Replace hardcoded rows with live meeting query. Show title, startTime, durationMinutes, participantCount, isInternal from meetings table joined with meetingParticipants.
- [ ] 3.5 — **Wire FreedomDashboard to EddingsEngine.** Replace hardcoded `@State` values with observed `freedomScore`. Calculate velocityPercent, weeklyAmount, netWorth, totalDebt, projection date from live data. Remove hardcoded stats grid values.
- [ ] 3.6 — **Wire FreedomDashboard projection.** Calculate projection date dynamically from FreedomTracker.projectedFreedomDate instead of hardcoded "November 2027".
- [ ] 3.7 — **Fix Contact/Meeting search resolution.** (`Search/QueryEngine.swift:178-180`). Replace `return nil` for `.contacts` and `.meetings` with actual record fetching and SearchResult construction.
- [ ] 3.8 — **Test: Launch app, verify ContactList.** Shows real contacts from database with real email/meeting/slack counts.
- [ ] 3.9 — **Test: Launch app, verify MeetingList.** Shows real meetings with dates, durations, participants.
- [ ] 3.10 — **Test: Launch app, verify FreedomDashboard.** Shows real velocity percentage, weekly amount, net worth from latest widgetSnapshot.

**Guard:** Every view displays data from SQLite. Zero hardcoded values remain in UI views.

### Phase 4 (P1): CKSyncEngine Hardening

**Goal:** iCloud sync handles edge cases per Apple documentation.

- [ ] 4.1 — **Handle missing delegate events.** Add handlers for `.willFetchChanges`, `.didFetchChanges`, `.didFetchRecordZoneChanges`, `.didSendChanges`. Log sync progress for debugging. Per `.../CloudKit/CKSyncEngine-5sie5/Event/README.md`.
- [ ] 4.2 — **Implement `nextFetchChangesOptions`.** Return zone-specific fetch options for prioritizing EddingsData zone. Per `.../CloudKit/CKSyncEngineDelegate-1q7g8/nextFetchChangesOptions(__syncEngine_).md`.
- [ ] 4.3 — **Add batch size limits to `buildNextBatch`.** Chunk pending changes into batches of 400 to avoid CloudKit limits. Per `.../CloudKit/CKSyncEngine-5sie5/README.md`.
- [ ] 4.4 — **Clean up CKAsset temp files.** Track temp file URLs in `sentRecordZoneChanges` handler. Delete after successful send. Per `.../CloudKit/CKAsset/README.md`.
- [ ] 4.5 — **Improve account change handling.** On `.switchAccounts`, flush pending writes to SQLite before clearing sync state. Notify user via logger. Per `.../CloudKit/CKSyncEngineAccountChangeType/README.md`.
- [ ] 4.6 — **Add conflict resolution for non-financial types.** Document last-write-wins as explicit strategy. Add logging for conflict events.

**Guard:** CKSyncEngine delegate handles all documented event types. Temp files cleaned up. Account changes don't lose data.

### Phase 5 (P2): iOS Background Sync Implementation

**Goal:** iOS app syncs data in the background.

- [ ] 5.1 — **Implement `handleRefresh` (30 sec).** Quick check: run `FinanceSyncPipeline.run()` with SimpleFin only. Call `task.setTaskCompleted(success:)` based on result.
- [ ] 5.2 — **Implement `handleProcessing` (minutes).** Full sync: run all sync clients + EmbeddingPipeline. Checkpoint every 100 records (commit to SQLite, check `task.expirationHandler` was not called).
- [ ] 5.3 — **Add `UIBackgroundModes` capability** to Xcode project (fetch + processing).
- [ ] 5.4 — **Add `TimelineEntry.relevance`** to FreedomVelocityEntry and NetWorthEntry for Smart Stack ranking.
- [ ] 5.5 — **Adjust widget reload policy.** Change from 6-hour fixed to `.atEnd` — only request new timeline when last entry expires.
- [ ] 5.6 — **Test: Background refresh triggers finance sync.** Simulate background refresh in Xcode debugger.
- [ ] 5.7 — **Test: Background processing runs full sync + embedding.** Simulate processing task.

**Guard:** Background tasks do real work. Expiration handler cleanly stops work. Widget data refreshes after background sync.

---

## Files to Modify

| File | Phase | Change |
|------|-------|--------|
| `Sources/EddingsKit/Auth/KeychainManager.swift` | 1 | Fix biometric flags, add macOS data protection, add access group |
| `Sources/EddingsKit/Sync/BackgroundTaskManager.swift` | 1, 5 | Fix expiration, reschedule timing, log errors, implement handlers |
| `Sources/EddingsWidgets/FreedomVelocityWidget.swift` | 1 | Check isPreview, cache DB pool, add relevance |
| `Sources/EddingsKit/CloudSync/iCloudManager.swift` | 1, 4 | Zone creation, event handlers, batch limits, cleanup |
| `Sources/EddingsKit/Embedding/NLEmbedder.swift` | 1 | Revision tracking |
| `Sources/EddingsKit/Search/QueryEngine.swift` | 3 | Fix contact/meeting resolution (lines 178-180) |
| `Sources/EddingsApp/EddingsApp.swift` | 3 | @MainActor on EddingsEngine, add data properties |
| `Sources/EddingsApp/Contacts/ContactList.swift` | 3 | Replace hardcoded data with GRDB queries |
| `Sources/EddingsApp/Meetings/MeetingList.swift` | 3 | Replace hardcoded data with GRDB queries |
| `Sources/EddingsApp/Finance/FreedomDashboard.swift` | 3 | Replace hardcoded data with live FreedomTracker |

**New files:**

| File | Phase | Purpose |
|------|-------|---------|
| `Sources/EddingsKit/Embedding/EmbeddingPipeline.swift` | 2 | Post-sync embedding orchestrator |

---

## Verification Protocol

| ID | Phase | Check | Method | Pass Criteria |
|----|-------|-------|--------|---------------|
| V-1 | 1 | Keychain biometric denial throws distinct error | Mock biometric denial | `KeychainError.biometricDenied` thrown, not nil |
| V-2 | 1 | BackgroundTask expiration calls setTaskCompleted | Trigger expiration | `setTaskCompleted(success: false)` called |
| V-3 | 1 | Widget getSnapshot() uses real data | Install widget | Shows actual velocity %, not 47% |
| V-4 | 1 | CKSyncEngine zone verified on start | Check CloudKit Dashboard | EddingsData zone exists |
| V-5 | 2 | New emails get embeddings | `sync --emails` → check vectorKeyMap | New emailChunk IDs appear in vectorKeyMap |
| V-6 | 2 | Qwen failure falls back to NLEmbedder | Stop Qwen server → sync | 512-dim embeddings generated, no errors |
| V-7 | 2 | pendingEmbeddings table activated | Force timeout mid-embed | Failed records written to pendingEmbeddings |
| V-8 | 2 | Hybrid search finds new content | Search for recently synced topic | Result appears with hybrid (not FTS-only) score |
| V-9 | 3 | ContactList shows live contacts | Launch app | Real names, real counts from DB |
| V-10 | 3 | MeetingList shows live meetings | Launch app | Real titles, dates, participants from DB |
| V-11 | 3 | FreedomDashboard shows live data | Launch app | Velocity % matches widgetSnapshots table |
| V-12 | 3 | Contact/meeting search works | `search --json "Emily"` | Result with sourceTable=contacts returned |
| V-13 | 4 | CKSyncEngine handles all event types | Monitor sync log | All event types logged |
| V-14 | 4 | CKAsset temp files cleaned up | Sync 1000 records | No orphaned temp files |
| V-15 | 5 | Background refresh runs finance sync | Xcode debugger | New transactions in DB after refresh |
| V-16 | 5 | Background processing runs full sync + embed | Xcode debugger | New embeddings after processing |

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Embedding pipeline slows sync cycle | MEDIUM | Run embedding async after sync completes. Don't block sync output. Batch in 100s with progress logging. |
| Qwen server unavailable during embedding | LOW | Graceful fallback to NLEmbedder (512-dim). Log warning. Always generate 512-dim baseline. |
| Widget DB pool caching causes stale reads | LOW | GRDB DatabasePool in WAL mode serves fresh reads. Pool is lightweight — caching is standard practice. |
| CKSyncEngine zone creation race condition | LOW | Create zone in `start()` before any sync operations. Zone creation is idempotent. |
| SwiftUI view binding causes main thread pressure | MEDIUM | GRDB queries run on background thread. Only publish results to @MainActor. Use `withCheckedContinuation` if needed. |
| NLEmbedding revision changes on OS update | MEDIUM | Track revision per vector. On mismatch, flag for re-embedding. Batch re-embed overnight via BGProcessingTask. |
| Large embedding backlog (300K+ unembedded records) | HIGH | First run processes existing backlog. Estimate: 512-dim at ~1ms/record = 300 seconds. 4096-dim at ~50ms/record = 4+ hours (Qwen). Process 4096-dim in background only. |

---

## Success Criteria

When all phases are complete:

1. `ei-cli sync --all` prints embedding statistics — every new record gets at least 512-dim embedding
2. `ei-cli search --json "topic"` returns hybrid results for content added after PostgreSQL migration
3. SwiftUI app shows zero hardcoded values — all data from SQLite
4. Keychain biometric protection works per Apple documentation
5. BackgroundTasks handlers do real work with proper expiration handling
6. Widget shows live Freedom Velocity from widgetSnapshots table
7. CKSyncEngine verifies zone creation and handles all event types
8. NLEmbedding revision tracked alongside vectors

---

## References

### Architecture Documentation (This Repository)
- `architecture/overview.md` — System architecture, tech stack, subsystems
- `architecture/embeddings.md` — Embedding system deep dive, current gaps
- `architecture/gaps.md` — 17 verified gaps with severity ratings
- `architecture/apple-api-compliance.md` — 17 API compliance issues with Apple doc citations
- `architecture/storage.md` — Full SQLite schema, FTS5 configuration
- `architecture/data-flows.md` — All sync pipelines, search pipeline

### Apple Developer Documentation (On-Disk)
| Framework | Path | Key APIs |
|-----------|------|----------|
| NaturalLanguage | `.../NaturalLanguage/NLEmbedding/` | `sentenceEmbedding(for:)`, `currentSentenceEmbeddingRevision(for:)`, `vector(for:)` |
| CloudKit | `.../CloudKit/CKSyncEngine-5sie5/` | `handleEvent`, `nextRecordZoneChangeBatch`, `State.Serialization` |
| BackgroundTasks | `.../BackgroundTasks/` | `BGAppRefreshTask`, `BGProcessingTask`, `setTaskCompleted(success:)` |
| WidgetKit | `.../WidgetKit/` | `TimelineProvider`, `TimelineEntryRelevance`, `getSnapshot(in:completion:)` |
| Security | `.../Security/` | `SecAccessControlCreateWithFlags`, `kSecAttrAccessible`, `kSecUseDataProtectionKeychain` |
| CoreML | `.../CoreML/` | `MLModel`, `MLModelConfiguration`, `MLMultiArray` |

### Prior PRDs
- **PRD-03:** Implementation correctness review — 52 findings, most now resolved (marked [x])
- **PRD-04:** Full content storage & native data pipeline — all 6 phases implemented
