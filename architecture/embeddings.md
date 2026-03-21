# Embeddings & Vector Search

TheEddingsIndex implements a **dual-embedding strategy** combining Apple's NaturalLanguage framework (512-dim) with Qwen3 CoreML/HTTP embeddings (4096-dim). Vectors are stored in USearch HNSW indices and combined with FTS5 full-text search via Reciprocal Rank Fusion (RRF) for hybrid retrieval.

---

## Architecture Overview

```
                        ┌─────────────────────┐
                        │    EmbeddingProvider  │  (protocol)
                        │  embed(_ text) → [Float]│
                        └──────┬──────────────┘
                               │
               ┌───────────────┼───────────────┐
               │               │               │
      ┌────────▼──────┐ ┌─────▼──────┐ ┌──────▼───────┐
      │  NLEmbedder   │ │ QwenClient │ │CoreMLEmbedder│
      │  512-dim      │ │ 4096-dim   │ │ 4096-dim     │
      │  Both platforms│ │ HTTP API   │ │ ⚠ STUB       │
      └───────┬───────┘ └─────┬──────┘ └──────┬───────┘
              │               │               │
              ▼               ▼               ▼
      ┌─────────────────────────────────────────┐
      │            VectorIndex (actor)           │
      │  USearch HNSW • cosine similarity        │
      │  reality-512.usearch + reality-4096.usearch│
      └──────────────────┬──────────────────────┘
                         │
                         ▼
      ┌─────────────────────────────────────────┐
      │           QueryEngine                    │
      │  FTS5 (BM25) + Semantic → HybridRanker  │
      └─────────────────────────────────────────┘
```

---

## Embedding Providers

### NLEmbedder (512-dim) — Primary, Both Platforms

**File:** `Sources/EddingsKit/Embedding/NLEmbedder.swift`

The reliable baseline. Uses Apple's `NaturalLanguage.NLEmbedding` framework available on macOS 15+ and iOS 18+.

**Process:**
1. Detect language via `NLLanguageRecognizer`
2. Load sentence embedding model for detected language: `NLEmbedding.sentenceEmbedding(for: language)`
3. Fall back to English if detected language unavailable
4. Call `embedding.vector(for: text)` → `[Double]`
5. Convert to `[Float]` (USearch requires Float)

**Revision Tracking:** `currentRevision` property exposes `NLEmbedding.currentSentenceEmbeddingRevision(for:)`. Revision is stored alongside each vector in `vectorKeyMap.embeddingRevision` to detect model changes after OS updates. See Apple doc: `NaturalLanguage/NLEmbedding/currentSentenceEmbeddingRevision(for_)/README.md`.

**Input limit:** 8192 characters (tokenized before embedding).

**Batch processing** uses `withThrowingTaskGroup` for concurrent embedding generation across multiple texts.

**Dimensions:** 512 (fixed by Apple's model)

### QwenClient (4096-dim) — HTTP API, macOS Only

**File:** `Sources/EddingsKit/Embedding/QwenClient.swift`

Connects to the external Qwen3 embedding server running on localhost.

**Process:**
1. HTTP POST to `http://localhost:8081/v1/embeddings`
2. Request body: `{"input": text, "model": "qwen"}`
3. Parse response: extract `data[0]["embedding"]` as `[Double]`
4. Convert to `[Float]`
5. 30-second timeout; returns errors on HTTP non-200 or missing fields

**Dependency:** Requires the Qwen3-VL embedding server to be running externally at port 8081. This server is NOT managed by TheEddingsIndex.

### CoreMLEmbedder (4096-dim) — NOT IMPLEMENTED

**File:** `Sources/EddingsKit/Embedding/CoreMLEmbedder.swift`

**Status: STUB.** Currently throws `EmbeddingError.modelUnavailable` on all calls.

Intended to load a CoreML-compiled Qwen3 model directly in-process, eliminating the external HTTP server dependency. Not yet implemented.

### EmbeddingProvider Protocol

**File:** `Sources/EddingsKit/Embedding/EmbeddingProvider.swift`

```swift
protocol EmbeddingProvider: Sendable {
    var dimensions: Int { get }
    func embed(_ text: String) async throws -> [Float]
    func embedBatch(_ texts: [String]) async throws -> [[Float]]
}
```

All providers conform. Strategy selection order: CoreML → Qwen HTTP → NLEmbedding fallback.

---

## Vector Storage (USearch HNSW)

### VectorIndex Actor

**File:** `Sources/EddingsKit/Storage/VectorIndex.swift`

The `VectorIndex` is an `actor` providing thread-safe access to USearch indices. Mutations are serialized; searches are concurrent.

### Index Configuration

| Parameter | iOS (512-dim) | macOS (512-dim) | macOS (4096-dim) |
|-----------|---------------|-----------------|------------------|
| Metric | Cosine (`.cos`) | Cosine (`.cos`) | Cosine (`.cos`) |
| Connectivity | 16 | 16 | 16 |
| Quantization | `i8` (int8) | `f32` (float32) | `f32` (float32) |
| Loading | `.view()` (mmap) | `.load()` | `.load()` |
| File | `reality-512.usearch` | `reality-512.usearch` | `reality-4096.usearch` |

**Quantization trade-offs:**
- **iOS i8:** 4x memory savings, faster mmap loading, slight accuracy loss. Required for mobile RAM constraints.
- **macOS f32:** Full precision, larger memory footprint, best ranking quality.

### Capacity Management

Dynamic reservation with doubling strategy:
- When `key >= currentCapacity`, calls `reserve(UInt32(newCapacity))`
- New capacity: `max(key + 1, reserved * 2)`
- Separate tracking for `reserved512` and `reserved4096`

### iOS Pending Index

iOS maintains a separate in-memory `pendingIndex512` for crash recovery during background sync tasks. If the app terminates mid-embedding, pending vectors survive in SQLite's `pendingEmbeddings` table and are merged on next launch.

### Generation Swapping (Save Strategy)

USearch indices are saved atomically using generation swapping to prevent corruption:

1. Save to new timestamped file: `reality-512-{timestamp}.usearch`
2. **iOS only:** Merge main + pending indices (exhaustive search to extract all keys, re-add to new index)
3. Create new `.view()` or `.load()` from new file
4. Atomic file replacement via `replaceItemAt`
5. Mark as excluded from backup (`isExcludedFromBackup`)
6. Reset pending index on iOS

This avoids `FileManager.replaceItemAt()` with an active mmap view (which causes SIGBUS crashes).

### Key Assignment

- `USearchKey` (unsigned integer) as primary key
- Sequential allocation starting from 1
- NOT tied to SQLite row IDs — decoupled via `vectorKeyMap` table
- Allows flexible re-indexing without database changes

### Search

```swift
func search(vector: [Float], count: Int) async -> [SearchHit]
```

- **iOS:** Searches both main and pending indices, merges results, returns top N
- **macOS:** Auto-selects index based on vector dimension (4096 → `index4096`, else → `index512`)
- Returns `[SearchHit(key: USearchKey, distance: Float)]` sorted by distance ascending (lower = more similar)

---

## EmbeddingPipeline (Post-Sync Embedding Generation)

**File:** `Sources/EddingsKit/Embedding/EmbeddingPipeline.swift`

Actor that closes the embedding loop — every new record gets vectors after sync.

```
Sync Pipeline (existing)                    FileWatcher (real-time)
  IMAPClient → SlackClient →                  FSEvents callback →
  FathomClient → FileScanner →                route by path prefix →
  FinanceSyncPipeline                         {Client}.indexSingleFile()
        │                                            │
        ▼                                            ▼
  EmbeddingPipeline.run()                  EmbeddingPipeline.embedRecord(table:id:)
        │                                            │
        ├─ retryPendingEmbeddings() (up to 500)      ├─ NLEmbedder → 512-dim
        ├─ For each of 5 tables:                     ├─ QwenClient → 4096-dim (macOS, best-effort)
        │   fetchUnembeddedIds()                     ├─ VectorIndex.add()
        │   fetchTexts() (batches of 100)            └─ vectorKeyMap insert + embeddingRevision
        │   NLEmbedder → 512-dim (always)
        │   QwenClient → 4096-dim (macOS, best-effort)
        │   VectorIndex.add()
        │   vectorKeyMap insert + embeddingRevision
        │   On failure → pendingEmbeddings
        └─ VectorIndex.save()
```

**Embeddable tables:**

| Table | Text Source |
|-------|-----------|
| emailChunks | `chunkText` |
| slackChunks | `chunkText` |
| transcriptChunks | `chunkText` |
| documents | `content` |
| financialTransactions | composite: `description` + `payee` |

---

## Database Schema for Embeddings

### vectorKeyMap Table

Maps USearch vector keys to source records:

```sql
CREATE TABLE vectorKeyMap (
    vectorKey INTEGER PRIMARY KEY,
    sourceTable TEXT NOT NULL,
    sourceId INTEGER NOT NULL,
    embeddingRevision INTEGER          -- v3 migration: tracks NLEmbedding model revision
);
```

This indirection layer allows vectors to reference records across multiple tables (emailChunks, slackChunks, transcriptChunks, documents, financialTransactions) with a single USearch index. The `embeddingRevision` column records which `NLEmbedding.currentSentenceEmbeddingRevision(for:)` value generated each vector, enabling detection of model changes after OS updates.

### pendingEmbeddings Table

Crash recovery for in-flight embeddings:

```sql
CREATE TABLE pendingEmbeddings (
    id INTEGER PRIMARY KEY,
    sourceTable TEXT NOT NULL,
    sourceId INTEGER NOT NULL,
    vector512 BLOB,
    vector4096 BLOB,
    createdAt DATETIME
);
```

**Current status:** Active. `EmbeddingPipeline` writes to this table when embedding fails (catch blocks in both `run()` and `embedRecord()`). `retryPendingEmbeddings()` processes up to 500 pending records on each pipeline run, deleting them from the table on success.

---

## Hybrid Search Pipeline

### Query Flow

```
User Query
    │
    ├─► FTSIndex.search(query) ──► BM25 ranked results (~60)
    │                                    │
    ├─► EmbeddingProvider.embed(query)   │
    │       │                            │
    │       ▼                            │
    │   VectorIndex.search(vector, 60)   │
    │       │                            │
    │       ▼                            │
    │   vectorKeyMap lookup ─────────────┤
    │       (key → sourceTable, sourceId)│
    │                                    │
    └───────────────┬────────────────────┘
                    │
                    ▼
            HybridRanker (RRF)
                    │
                    ▼
            Top 20 results
```

### HybridRanker — Reciprocal Rank Fusion (RRF)

**File:** `Sources/EddingsKit/Search/HybridRanker.swift`

**Algorithm:**
- FTS weight: **0.4**
- Semantic weight: **0.6**
- k parameter: **60**
- FTS score per result: `0.4 × (1.0 / (60 + rank + 1))`
- Semantic score per result: `0.6 × (1.0 / (60 + rank + 1))`
- Combined: sum per record (by composite key `sourceId + sourceTable`)
- Final: sorted descending, top 20 returned

**Deduplication:** Records appearing in both FTS and semantic results are merged by `(sourceId, sourceTable)` composite key, with scores summed.

### FTS5 BM25 Column Weights

Applied at **query time** via raw SQL (not at schema definition time — GRDB has no `columnWeight()` API):

```sql
SELECT *, bm25(emailChunks_fts, 3.0, 2.0, 1.0) as rank
FROM emailChunks_fts
WHERE emailChunks_fts MATCH ?
ORDER BY rank
```

Example weights:
- `emailChunks_fts`: subject=3.0, fromName=2.0, chunkText=1.0
- Heavier weights on structured fields (subject, speaker) vs body text

### Graceful Degradation

If the Qwen embedding server is unavailable or embedding fails, the system falls back to **FTS-only search** silently. No error is surfaced to the user — results are simply FTS-ranked without semantic boost.

---

## PostgreSQL Migration Path

**File:** `Sources/EddingsKit/Sync/PostgresMigrator.swift`

The existing TypeScript search engine at `localhost:4432` has 345K+ embeddings in PostgreSQL. TheEddingsIndex migrates these via a two-phase process:

### Phase 1: Data Import

- Exports via `psql` with field separator `\u{1F}` (unit separator)
- Streams 50K rows at a time
- Migrates: documents, email chunks, slack chunks, transcript chunks, contacts, companies, meetings
- Rebuilds FTS5 indices from scratch (faster for bulk import)
- Handles 1.3M+ records with progress logging at 100K increments

### Phase 2: Vector Migration

- Queries PostgreSQL for records with non-null embeddings
- Parses 4096-dim float vectors from PostgreSQL text format: `[f1,f2,...,f4096]`
- Adds each vector to USearch with incrementing `vectorKey`
- Records mapping in SQLite `vectorKeyMap` table
- Saves USearch index (generation swapped)
- **Sources with 4096-dim vectors:** transcript chunks, email chunks, slack chunks only

---

## iOS vs macOS Differences

| Aspect | iOS | macOS |
|--------|-----|-------|
| 512-dim embeddings | NLEmbedder | NLEmbedder |
| 4096-dim embeddings | Not available | QwenClient (HTTP) |
| USearch 512 loading | `.view()` mmap, i8 quant | `.load()`, f32 quant |
| USearch 4096 | Not present (`index4096 = nil`) | Full index, f32 quant |
| Pending index | Yes (background crash recovery) | No |
| CoreML Qwen | Not supported | Stub (throws error) |
| Widget access | No USearch (30MB RAM limit) | N/A |
| Search quality | FTS + 512-dim semantic | FTS + 4096-dim semantic |

---

## Known Gaps & Issues

### Critical

1. **CoreMLEmbedder is a stub** — The in-process Qwen3 CoreML model is not implemented. All 4096-dim embeddings require the external HTTP server at port 8081. This creates a fragile dependency for macOS search quality.

### Resolved (PRD-05/07)

2. ~~**New data gets no embeddings**~~ — **RESOLVED.** `EmbeddingPipeline` actor processes all 5 content tables after sync. Both batch (`run()`) and single-record (`embedRecord()`) paths exist. FileWatcher calls `embedRecord()` on every file event for real-time embedding.

3. ~~**pendingEmbeddings table is unused**~~ — **RESOLVED.** `EmbeddingPipeline` writes to this table on embedding failure. `retryPendingEmbeddings()` processes up to 500 pending records per run.

4. ~~**Documents and financial transactions have no embeddings**~~ — **RESOLVED.** `EmbeddingPipeline.embeddableTables` includes `documents` (text: `content`) and `financialTransactions` (composite: `description` + `payee`).

5. ~~**No background embedding job queue**~~ — **RESOLVED.** `EmbeddingPipeline` is the job queue. Runs after every sync and on every FileWatcher event.

### Moderate

6. **Widget snapshot generation only runs during finance sync** — `widgetSnapshots` rows are only created by `FinanceSyncPipeline.run()`. If finance sync fails or is skipped, widget data goes stale.

### By Design (Not Issues)

- Both PostgreSQL and TheEddingsIndex coexist — no migration pressure
- Embeddings are optional — FTS-only search works correctly as a fallback
- NaturalLanguage 512-dim is the reliable baseline (both platforms)
- Qwen3 4096-dim is a premium enhancement (macOS + external API)
- USearch indices are NOT synced via iCloud — rebuilt locally per device
