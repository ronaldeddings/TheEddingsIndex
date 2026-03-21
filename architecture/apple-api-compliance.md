# Apple API Compliance

Cross-reference of TheEddingsIndex implementation against Apple developer documentation. Identifies API misuse, missing patterns, and platform-specific concerns.

---

## NaturalLanguage Framework (NLEmbedding)

**File:** `Sources/EddingsKit/Embedding/NLEmbedder.swift`

### Correct Usage
- `NLEmbedding.sentenceEmbedding(for:)` used correctly (available iOS 14.0+, macOS 11.0+)
- `NLLanguageRecognizer` properly instantiated per call (not shared across threads — Apple docs say "Don't use an instance from more than one thread simultaneously")
- `vector(for:)` returns `[Double]`, correctly converted to `[Float]` for USearch
- Language detection with English fallback is a valid pattern

### Issues Found

**~~No Embedding Revision Pinning~~ — RESOLVED (PRD-05)**
- `NLEmbedder.swift` now exposes `currentRevision` via `NLEmbedding.currentSentenceEmbeddingRevision(for:)`
- Revision stored in `vectorKeyMap.embeddingRevision` column (v3 migration)
- Apple doc: `NaturalLanguage/NLEmbedding/currentSentenceEmbeddingRevision(for_)/README.md`

**512-Dim Claim Unverified**
- Apple documentation does NOT explicitly state the embedding dimension for sentence embeddings
- The code hardcodes `dimensions = 512` and throws if the actual dimension doesn't match
- Dimension could vary by language or model revision
- **Fix:** Add runtime verification, log actual dimension on first use

**Double → Float Precision Loss**
- `vector(for:)` returns `[Double]` (64-bit); code converts to `[Float]` (32-bit)
- Loses ~7 digits of precision per component
- Acceptable for cosine similarity but worth noting for documentation

**Unused Capabilities**
- `enumerateNeighbors` — NOT applicable (Apple docs confirm "nearest-neighbor search doesn't apply to sentence embeddings")
- Distance type parameterization — defaults to `.cosine`, which is correct for our use case

---

## CloudKit (CKSyncEngine)

**File:** `Sources/EddingsKit/CloudSync/iCloudManager.swift`

### Correct Usage
- CKSyncEngine configured with private database
- State serialized to disk on every `.stateUpdate` event (Apple requirement)
- SyncDelegate properly implements `CKSyncEngineDelegate`
- Record mapping uses clear `{tableName}/{rowId}` ID format
- Large text >50KB stored as CKAsset (correct pattern)

### Issues Found

**~~Missing Zone Creation Verification~~ — RESOLVED (PRD-05)**
- `start()` now async — checks zone existence, creates if `zoneNotFound`
- Apple doc: `CloudKit/CKSyncEngine-5sie5/README.md`

**~~7+ Delegate Events Ignored~~ — RESOLVED (PRD-05)**
- All CKSyncEngine event types now handled with logging: `willFetchChanges`, `willFetchRecordZoneChanges`, `fetchedDatabaseChanges`, `willSendChanges`, `didFetchChanges`, `didFetchRecordZoneChanges`, `didSendChanges`, `sentDatabaseChanges`, `sentRecordZoneChanges`
- Apple doc: `CloudKit/CKSyncEngine-5sie5/Event/README.md`

**~~No Batch Size Limits in buildNextBatch~~ — RESOLVED (PRD-05)**
- Capped at 400 pending changes per batch with overflow logging

**~~CKAsset Temp Files Not Cleaned Up~~ — RESOLVED (PRD-05)**
- `cleanupTempFiles()` called after `sentRecordZoneChanges`, deletes `ck-asset-*` temp files

**~~Incomplete Account Change Handling~~ — RESOLVED (PRD-05)**
- On `.switchAccounts`, WAL checkpoint flushes pending writes before clearing sync state

**Conflict Resolution Only for FinancialTransaction** (By Design)
- `categoryModifiedAt` timestamp comparison is correct for financial records
- All other record types use server record (last-write-wins) — documented in code
- All conflict events logged with record type and ID

**Missing `nextFetchChangesOptions` Delegate Method** (Acceptable)
- Not needed for single-zone setup — CKSyncEngine automatically fetches for all zones

---

## BackgroundTasks (iOS)

**File:** `Sources/EddingsKit/Sync/BackgroundTaskManager.swift`

### Issues Found — Mostly Resolved (PRD-05)

**~~Task Completion Called Before Async Work Finishes~~ — RESOLVED**
- Both `handleRefresh` (runs `FinanceSyncPipeline`) and `handleProcessing` (full sync + `EmbeddingPipeline`) now do real work with proper async completion.

**~~Expiration Handler Doesn't Call setTaskCompleted~~ — RESOLVED**
- `setTaskCompleted(success: false)` added to expiration handlers after `operation.cancel()`
- Apple doc: `BackgroundTasks/BGTask/setTaskCompleted(success_)/README.md`

**~~Race Condition in Reschedule Timing~~ — RESOLVED**
- `scheduleRefresh()`/`scheduleProcessing()` moved inside async Task block, after work completes

**~~Silent Failure on Task Submission~~ — RESOLVED**
- `try?` replaced with `do/try/catch` logging specific `BGTaskScheduler.Error` codes

**Missing UIBackgroundModes Capability — STILL OPEN**
- `Info.plist` correctly lists `BGTaskSchedulerPermittedIdentifiers`
- But the Xcode project must also declare `UIBackgroundModes` capability with `fetch` and `processing`
- Without this capability, tasks are registered but never scheduled by the system
- **Requires Xcode project edit** — cannot be done via SPM

---

## WidgetKit

**File:** `Sources/EddingsWidgets/FreedomVelocityWidget.swift`

### Issues Found — All Resolved (PRD-05)

**~~getSnapshot() Doesn't Check context.isPreview~~ — RESOLVED**
- Both providers now check `context.isPreview` — return placeholder for preview, real data otherwise
- Apple doc: `WidgetKit/TimelineProviderContext/README.md` — `isPreview` is true in widget gallery

**~~Fresh DatabasePool on Every Call~~ — RESOLVED**
- Created `WidgetDatabase` enum with static `pool` — shared across all timeline calls

**~~Missing TimelineEntry.relevance~~ — RESOLVED**
- `FreedomVelocityEntry` scores by velocity %, `NetWorthEntry` by |dailyChange|/5000
- Apple doc: `WidgetKit/TimelineEntryRelevance/README.md`

**~~6-Hour Reload Policy May Be Too Aggressive~~ — RESOLVED**
- Changed to `.atEnd` reload policy for both widgets

---

## Security (Keychain)

**File:** `Sources/EddingsKit/Auth/KeychainManager.swift`

### Correct Usage
- Uses `kSecAttrAccessibleAfterFirstUnlock` for background sync credentials (correct for background access)
- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for interactive credentials
- Service identifier consistent: `com.hackervalley.eddingsindex`

### Issues Found — Mostly Resolved (PRD-05)

**~~SecAccessControl + kSecAttrAccessible Conflict~~ — VERIFIED NOT AN ISSUE**
- Code already uses if/else — `kSecAttrAccessControl` and `kSecAttrAccessible` are never combined
- Apple doc: `Security/SecAccessControlCreateWithFlags(________).md`

**~~Missing kSecUseDataProtectionKeychain on macOS~~ — RESOLVED**
- Added via `baseQuery()` helper with `#if os(macOS)`
- Apple doc: `Security/kSecUseDataProtectionKeychain.md` — required for modern keychain on macOS 10.15+

**~~No kSecAttrAccessGroup for Widget Extension Sharing~~ — RESOLVED**
- Added via `baseQuery()` helper with `#if os(iOS)`

**~~Biometric Error Indistinguishable from "Not Found"~~ — RESOLVED**
- Added `errSecInteractionNotAllowed` check throwing `KeychainError.biometricDenied`

**Update-Before-Add May Trigger Auth Prompts** (Remaining)
- Pattern tries `SecItemUpdate` first, which on biometric-protected items prompts the user even if the intent is to add a new item
- **Fix:** Use `SecItemCopyMatching` (no data fetch) to check existence first

---

## CoreML (Stub)

**File:** `Sources/EddingsKit/Embedding/CoreMLEmbedder.swift`

### What Would Be Needed for Full Implementation

1. **Model Conversion:** Qwen3 ONNX → CoreML `.mlmodelc` via `coremltools` Python package
2. **MLModel Loading:** `MLModel(contentsOf: url, configuration: config)` — must be deferred (not in `init`) to avoid crashing app startup if model file is missing
3. **MLModelConfiguration:** Set `.computeUnits` — `.all` for auto GPU/ANE, `.cpuAndNeuralEngine` to avoid GPU contention with SwiftUI rendering
4. **MLFeatureProvider:** Custom implementation wrapping input text as `MLDictionaryFeatureProvider`; text → `MLMultiArray` with shape `[1, maxTokens, embeddingDim]`
5. **MLMultiArray Output:** Use `withUnsafeMutableBufferPointer(ofType:_:)` to extract embeddings into `[Float]` array
6. **Batch Support:** Implement `MLBatchProvider` for `embedBatch()`, handle variable-length input padding
7. **Thread Safety:** `MLModel` is NOT thread-safe — the actor wrapper is correct but must also dispatch blocking prediction calls off the main thread via `Task.detached`
8. **Model Size:** CoreML models for 4096-dim embeddings could be 500MB+ — needs lazy loading and disk management, stored in `~/Library/Application Support/`
9. **Platform Check:** Only available on macOS (ANE/GPU); iOS needs smaller model or server fallback; use `MLModel.availableComputeDevices` to verify hardware
10. **Error Differentiation:** Map `NSError` from CoreML to specific `EmbeddingError` cases (model not found, invalid shape, OOM, prediction failed)

---

---

## CoreServices (FSEvents) — New in PRD-07

**File:** `Sources/EddingsKit/Sync/FileWatcher.swift`

### Correct Usage
- `FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents` | `kFSEventStreamCreateFlagNoDefer` | `kFSEventStreamCreateFlagIgnoreSelf`
- Apple doc: `coreservices/1443980-fseventstreamcreate.md`
- `FSEventStreamSetDispatchQueue` used (preferred over run loop per Apple guidance)
- Latency of 2.0 seconds for temporal coalescing — appropriate for daemon use
- Proper cleanup: `FSEventStreamStop` → `FSEventStreamInvalidate` → `FSEventStreamRelease`

### Issues Found

**Missing `kFSEventStreamCreateFlagWatchRoot` Flag**
- `FileWatcher.swift:27` checks `rootChanged` events (pauses indexing on root change)
- But `kFSEventStreamCreateFlagWatchRoot` is NOT set in stream creation flags (line 76-79)
- Without this flag, the kernel may never deliver `kFSEventStreamEventFlagRootChanged` events
- Apple doc: `coreservices/kfseventstreamcreateflagwatchroot.md` — "Monitors changes to the path itself"
- **Impact:** VRAM path rename/move detection may not work. Volume unmount (`isUnmount`) still works independently.

**`kFSEventStreamCreateFlagNoDefer` in Daemon Context**
- Apple doc (`coreservices/kfseventstreamcreateflagnodefer.md`): "For interactive apps wanting immediate reaction"
- Without this flag, events batch during the full latency window (default, more appropriate for daemons)
- With it: first event fires immediately (0 latency), then subsequent events within 2s are coalesced
- **Impact:** Deliberate choice for low-latency indexing. Documented here as intentional.

**`Unmanaged.passUnretained(self)` Lifetime Risk**
- `FileWatcher.swift:70`: passes actor reference to C callback without retaining
- If the actor is deallocated before the callback fires, use-after-free occurs
- **Impact:** Low — watcher lifetime = process lifetime (blocked by `dispatchMain()` in WatchCommand)
- **Mitigation:** Consider `passRetained`/`takeRetainedValue` for safety, or document the lifetime guarantee

---

## Summary of Compliance Issues

| Framework | Severity | Issue | Status |
|-----------|----------|-------|--------|
| NaturalLanguage | ~~MODERATE~~ | ~~No embedding revision pinning~~ | **RESOLVED** — revision tracked in vectorKeyMap |
| NaturalLanguage | LOW | 512-dim hardcoded without Apple docs confirming value | Open |
| CloudKit | ~~HIGH~~ | ~~Zone creation never verified~~ | **RESOLVED** — start() verifies zone |
| CloudKit | ~~HIGH~~ | ~~7+ delegate events silently ignored~~ | **RESOLVED** — all events handled |
| CloudKit | ~~MODERATE~~ | ~~No batch size limits~~ | **RESOLVED** — capped at 400 |
| CloudKit | ~~MODERATE~~ | ~~Account change handling incomplete~~ | **RESOLVED** — WAL checkpoint on switchAccounts |
| BackgroundTasks | ~~CRITICAL~~ | ~~Expiration handler doesn't call setTaskCompleted~~ | **RESOLVED** |
| BackgroundTasks | CRITICAL | Missing UIBackgroundModes capability | **OPEN** — requires Xcode project edit |
| BackgroundTasks | ~~HIGH~~ | ~~Task submission errors silently discarded~~ | **RESOLVED** — do/try/catch with logging |
| WidgetKit | ~~HIGH~~ | ~~getSnapshot() ignores context.isPreview~~ | **RESOLVED** |
| WidgetKit | ~~MODERATE~~ | ~~Fresh DatabasePool per call~~ | **RESOLVED** — static cached pool |
| WidgetKit | ~~LOW~~ | ~~Missing TimelineEntry.relevance~~ | **RESOLVED** — scoring implemented |
| Security | ~~HIGH~~ | ~~SecAccessControl + kSecAttrAccessible conflict~~ | **NOT AN ISSUE** — verified if/else |
| Security | ~~HIGH~~ | ~~Missing kSecUseDataProtectionKeychain~~ | **RESOLVED** |
| Security | ~~MODERATE~~ | ~~No kSecAttrAccessGroup~~ | **RESOLVED** |
| Security | ~~MODERATE~~ | ~~Biometric denial returns nil~~ | **RESOLVED** — distinct error |
| Security | LOW | Update-before-add may trigger auth prompts | Open |
| CoreServices | LOW | Missing kFSEventStreamCreateFlagWatchRoot | **NEW** — rootChanged events may not fire |
| CoreServices | INFO | Unmanaged.passUnretained lifetime risk | **NEW** — low risk, document only |
