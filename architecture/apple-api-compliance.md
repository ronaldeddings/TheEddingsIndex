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

**No Embedding Revision Pinning**
- Apple provides `NLEmbedding.currentSentenceEmbeddingRevision(for:)` and `sentenceEmbedding(for:revision:)` to pin specific model versions
- Current code uses whatever the system provides. If Apple updates the embedding model, stored vectors will be misaligned with new query vectors
- **Impact:** Potential silent search quality degradation after OS updates
- **Fix:** Store revision alongside vectors; verify consistency on app launch

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

**Missing Zone Creation Verification**
- Zone ID `EddingsData` is hardcoded but never explicitly created
- CKSyncEngine may auto-create zones on first send, but this isn't guaranteed
- **Fix:** Add explicit zone creation in `start()` method, or verify zone exists

**7+ Delegate Events Ignored**
- `default` case in `handleEvent` swallows: `.willFetchChanges`, `.willFetchRecordZoneChanges`, `.fetchedDatabaseChanges`, `.willSendChanges`, `.didFetchChanges`, `.didFetchRecordZoneChanges`, `.didSendChanges`
- These events are needed for: UI sync indicators, progress tracking, error recovery, batch completion signals
- **Impact:** No way to show sync progress or handle zone-level errors

**Missing `nextFetchChangesOptions` Delegate Method**
- Apple docs document this method for customizing fetch behavior per zone
- Not implemented — sync engine uses default fetch behavior uniformly

**Incomplete Account Change Handling**
- On `.switchAccounts`: only deletes state file
- Apple docs state: "When a sync engine detects a change, it resets its internal state including unsaved changes"
- Should also flush pending writes, notify app, and clear in-memory caches

**Conflict Resolution Only for FinancialTransaction**
- `categoryModifiedAt` timestamp comparison is correct for financial records
- All other record types silently use server record (last-write-wins)
- No explicit documentation of this strategy for other types

**No Batch Size Limits in buildNextBatch**
- Creates `RecordZoneChangeBatch` with ALL pending changes at once
- Could hit CloudKit limits or cause timeouts with large pending sets
- **Fix:** Chunk pending changes into manageable batches

**CKAsset Temp Files Not Cleaned Up**
- `attachContentAsAssetIfNeeded` creates temp files in `/tmp`
- No cleanup mechanism after successful send
- Files persist until system cleanup

---

## BackgroundTasks (iOS)

**File:** `Sources/EddingsKit/Sync/BackgroundTaskManager.swift`

### Critical Issues

**Task Completion Called Before Async Work Finishes**
```swift
let operation = Task {
    // TODO: Implement quick transaction check
    task.setTaskCompleted(success: true)  // ← Inside async task
}
```
The actual issue is that the TODO stubs call `setTaskCompleted(success: true)` immediately — when real async work is added, the `Task { }` block needs to properly await completion before calling `setTaskCompleted`.

**Expiration Handler Doesn't Call setTaskCompleted**
```swift
task.expirationHandler = {
    operation.cancel()
    // Missing: task.setTaskCompleted(success: false)
}
```
Apple docs: "If you don't set an expiration handler, the system marks your task as complete and unsuccessful." The expiration handler MUST call `setTaskCompleted(success: false)` after cancellation or the system terminates the app.

**Race Condition in Reschedule Timing**
- Both `handleRefresh` and `handleProcessing` call `scheduleRefresh()`/`scheduleProcessing()` BEFORE async work starts
- Apple docs: "Submitting a task request for an unexecuted task already in the queue replaces the previous request"
- On repeated failures, creates a tight loop of failed rescheduling
- **Fix:** Reschedule AFTER async work completes, with backoff on failure

**Silent Failure on Task Submission**
- `try? BGTaskScheduler.shared.submit(request)` silently discards errors
- Can fail with: `tooManyPendingTaskRequests`, `notPermitted`, `unavailable`
- **Fix:** Log errors at minimum

**Missing UIBackgroundModes Capability**
- `Info.plist` correctly lists `BGTaskSchedulerPermittedIdentifiers`
- But the Xcode project must also declare `UIBackgroundModes` capability with `fetch` and `processing`
- Without this capability, tasks are registered but never scheduled by the system

---

## WidgetKit

**File:** `Sources/EddingsWidgets/FreedomVelocityWidget.swift`

### Issues Found

**getSnapshot() Doesn't Check context.isPreview**
- Always returns `placeholder()` data instead of real data
- Apple docs: "If context.isPreview is true, the widget appears in the widget gallery"
- Should return real data for non-preview contexts, placeholder for preview
- **Fix:** Check `context.isPreview`; load from DB for non-preview

**Fresh DatabasePool on Every Call**
- `loadLatestWidgetSnapshot()` opens a new `DatabasePool` each time
- Widgets have 30MB RAM limit — repeated pool creation adds overhead
- **Fix:** Use shared pool or singleton pattern

**Missing TimelineEntry.relevance**
- Neither `FreedomVelocityEntry` nor `NetWorthEntry` implement the optional `relevance` property
- Without this, widgets won't be prioritized in Smart Stacks (iOS 17+)

**6-Hour Reload Policy May Be Too Aggressive**
- Widgets have a limited daily refresh budget
- Two widgets × 4 refreshes/day = 8 daily refreshes
- Financial data only changes during business hours
- **Consider:** Longer intervals or `.atEnd` policy

---

## Security (Keychain)

**File:** `Sources/EddingsKit/Auth/KeychainManager.swift`

### Correct Usage
- Uses `kSecAttrAccessibleAfterFirstUnlock` for background sync credentials (correct for background access)
- Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for interactive credentials
- Service identifier consistent: `com.hackervalley.eddingsindex`

### Issues Found

**SecAccessControl + kSecAttrAccessible Conflict**
- When `biometric: true`, code creates `SecAccessControlCreateWithFlags` with `.userPresence` AND sets `kSecAttrAccessible` separately
- Apple docs state these are mutually exclusive — `SecAccessControl` already specifies access constraints and replaces `kSecAttrAccessible`
- **Impact:** Biometric protection may not work as intended
- **Fix:** When biometric is required, use ONLY `kSecAttrAccessControl` (drop `kSecAttrAccessible`)

**Missing kSecUseDataProtectionKeychain on macOS**
- On macOS 10.15+, items default to the legacy Keychain unless `kSecUseDataProtectionKeychain: true` is set
- Without this flag, SimpleFin URL stores in legacy keychain (not encrypted at rest with device key)
- **Fix:** Add `kSecUseDataProtectionKeychain: true` to all queries on macOS

**No kSecAttrAccessGroup for Widget Extension Sharing**
- KeychainManager doesn't set `kSecAttrAccessGroup`
- Widget extensions need credentials to refresh data but can't access them without a shared access group
- **Fix:** Add `kSecAttrAccessGroup: "group.com.hackervalley.eddingsindex"` on iOS

**Biometric Error Indistinguishable from "Not Found"**
- `retrieve()` returns `nil` for both `errSecItemNotFound` (legitimate miss) and `errSecInteractionNotAllowed` (user denied biometric)
- **Fix:** Differentiate error types — throw for auth denial, return nil for not found

**Update-Before-Add May Trigger Auth Prompts**
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

## Summary of Compliance Issues

| Framework | Severity | Issue |
|-----------|----------|-------|
| NaturalLanguage | MODERATE | No embedding revision pinning — vectors could become misaligned |
| NaturalLanguage | LOW | 512-dim hardcoded without Apple docs confirming this value |
| CloudKit | HIGH | Zone creation never verified before sync |
| CloudKit | HIGH | 7+ delegate events silently ignored |
| CloudKit | MODERATE | No batch size limits — could hit CloudKit limits |
| CloudKit | MODERATE | Account change handling incomplete |
| BackgroundTasks | CRITICAL | Expiration handler doesn't call setTaskCompleted |
| BackgroundTasks | CRITICAL | Missing UIBackgroundModes capability |
| BackgroundTasks | HIGH | Task submission errors silently discarded |
| WidgetKit | HIGH | getSnapshot() ignores context.isPreview |
| WidgetKit | MODERATE | Fresh DatabasePool per call in 30MB-limited widget |
| WidgetKit | LOW | Missing TimelineEntry.relevance for Smart Stacks |
| Security | HIGH | SecAccessControl + kSecAttrAccessible conflict — biometric may not work |
| Security | HIGH | Missing kSecUseDataProtectionKeychain on macOS — legacy keychain used |
| Security | MODERATE | No kSecAttrAccessGroup — widget can't access keychain items |
| Security | MODERATE | Biometric denial returns nil instead of throwing error |
