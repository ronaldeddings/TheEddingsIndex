# Storage Layer

TheEddingsIndex uses SQLite via GRDB.swift as its primary data store, with USearch HNSW for vector indices and iCloud Private Database (CKSyncEngine) for cross-device sync.

---

## SQLite Configuration

- **Access:** `DatabasePool` (not `DatabaseQueue`) for concurrent read/write
- **WAL mode:** Enabled by default via GRDB's DatabasePool
- **Foreign keys:** Enabled by default; can be disabled during migration (`foreignKeysEnabled: false`)
- **Path (CLI):** `~/Library/Application Support/com.hackervalley.eddingsindex/eddings.sqlite`
- **Path (App):** App Group shared container at `group.com.hackervalley.eddingsindex/eddingsindex.sqlite`
- **Temporary databases:** `DatabaseManager.temporary()` creates UUID-named instances in `/tmp`

---

## Schema

### Migration v1: Core Tables

All tables created in a single `v1_core_tables` migration.

#### companies

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| name | TEXT | NOT NULL |
| domain | TEXT | UNIQUE |
| aliases | TEXT | |
| industry | TEXT | |
| isCustomer | BOOLEAN | DEFAULT false |
| isPartner | BOOLEAN | DEFAULT false |
| isProspect | BOOLEAN | DEFAULT false |
| notes | TEXT | |

#### contacts

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| name | TEXT | NOT NULL |
| email | TEXT | |
| companyId | INTEGER | FK → companies (SET NULL) |
| slackUserId | TEXT | |
| role | TEXT | |
| isMe | BOOLEAN | DEFAULT false |
| firstSeenAt | DATETIME | |
| lastSeenAt | DATETIME | |
| emailCount | INTEGER | DEFAULT 0 |
| meetingCount | INTEGER | DEFAULT 0 |
| slackCount | INTEGER | DEFAULT 0 |
| tags | TEXT | |
| notes | TEXT | |

**Index:** `idx_contact_email` on `email`

#### documents

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| path | TEXT | NOT NULL, UNIQUE |
| filename | TEXT | NOT NULL |
| content | TEXT | |
| extension | TEXT | |
| fileSize | INTEGER | |
| modifiedAt | DATETIME | |
| area | TEXT | |
| category | TEXT | |
| contentType | TEXT | |

**FTS5:** `documents_fts` synced with `documents` — columns: `filename`, `content`. Tokenizer: `unicode61()`.

#### emailChunks

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| emailId | TEXT | NOT NULL, UNIQUE |
| emailPath | TEXT | |
| subject | TEXT | |
| fromName | TEXT | |
| fromEmail | TEXT | |
| toEmails | TEXT | |
| ccEmails | TEXT | |
| chunkText | TEXT | |
| chunkIndex | INTEGER | |
| labels | TEXT | |
| emailDate | DATETIME | |
| year | INTEGER | |
| month | INTEGER | |
| quarter | INTEGER | |
| isSentByMe | BOOLEAN | DEFAULT false |
| hasAttachments | BOOLEAN | DEFAULT false |
| isReply | BOOLEAN | DEFAULT false |
| threadId | TEXT | |
| fromContactId | INTEGER | FK → contacts (SET NULL) |

**FTS5:** `emailChunks_fts` synced with `emailChunks` — columns: `subject`, `fromName`, `chunkText`. Tokenizer: `unicode61()`.

**Indices:** `idx_email_date`, `idx_email_contact`, `idx_email_quarter`, `idx_email_sent`, `idx_email_attachments`

#### slackChunks

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| channel | TEXT | |
| channelType | TEXT | |
| speakers | TEXT | |
| chunkText | TEXT | |
| messageDate | DATETIME | |
| year | INTEGER | |
| month | INTEGER | |
| hasFiles | BOOLEAN | DEFAULT false |
| hasReactions | BOOLEAN | DEFAULT false |
| threadTs | TEXT | |
| isThreadReply | BOOLEAN | DEFAULT false |

**FTS5:** `slackChunks_fts` synced with `slackChunks` — columns: `channel`, `chunkText`. Tokenizer: `unicode61()`.

**Indices:** `idx_slack_date`, `idx_slack_quarter`

#### transcriptChunks

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| filePath | TEXT | |
| chunkText | TEXT | |
| chunkIndex | INTEGER | |
| speakers | TEXT | |
| speakerName | TEXT | |
| meetingId | TEXT | |
| year | INTEGER | |
| month | INTEGER | |

**FTS5:** `transcriptChunks_fts` synced with `transcriptChunks` — columns: `speakerName`, `chunkText`. Tokenizer: `unicode61()`.

**Indices:** `idx_transcript_meeting`, `idx_transcript_quarter`

#### financialTransactions

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| transactionId | TEXT | NOT NULL, UNIQUE |
| source | TEXT | NOT NULL |
| accountId | TEXT | NOT NULL |
| accountName | TEXT | |
| institution | TEXT | |
| transactionDate | DATETIME | NOT NULL |
| amount | DOUBLE | NOT NULL |
| description | TEXT | |
| payee | TEXT | |
| category | TEXT | |
| subcategory | TEXT | |
| isRecurring | BOOLEAN | DEFAULT false |
| isTransfer | BOOLEAN | DEFAULT false |
| tags | TEXT | |
| year | INTEGER | |
| month | INTEGER | |
| categoryModifiedAt | DATETIME | |

**FTS5:** `financialTransactions_fts` synced with `financialTransactions` — columns: `payee`, `description`, `category`. Tokenizer: `unicode61()`.

**Indices:** `idx_txn_date`, `idx_txn_category`

#### meetings

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| meetingId | TEXT | NOT NULL, UNIQUE |
| title | TEXT | |
| startTime | DATETIME | |
| endTime | DATETIME | |
| durationMinutes | INTEGER | |
| year | INTEGER | |
| month | INTEGER | |
| isInternal | BOOLEAN | DEFAULT false |
| participantCount | INTEGER | |
| videoUrl | TEXT | |
| filePath | TEXT | |

**Indices:** `idx_meeting_date`, `idx_meeting_quarter`, `idx_meeting_internal`

#### financialSnapshots

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| snapshotDate | DATE | NOT NULL |
| accountId | TEXT | NOT NULL |
| accountName | TEXT | |
| institution | TEXT | |
| accountType | TEXT | |
| balance | DOUBLE | NOT NULL |
| availableBalance | DOUBLE | |
| currency | TEXT | DEFAULT 'USD' |
| source | TEXT | NOT NULL |

**Unique:** `(snapshotDate, accountId, source)`
**Index:** `idx_snap_date`

#### pendingEmbeddings (crash recovery)

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| sourceTable | TEXT | NOT NULL |
| sourceId | INTEGER | NOT NULL |
| vector512 | BLOB | |
| vector4096 | BLOB | |
| createdAt | DATETIME | DEFAULT CURRENT_TIMESTAMP |

**Status:** Active. `EmbeddingPipeline` writes to this table when embedding fails (catch blocks in both `run()` and `embedRecord()`). `retryPendingEmbeddings()` processes up to 500 pending records on each pipeline run.

#### vectorKeyMap

| Column | Type | Constraints |
|--------|------|-------------|
| vectorKey | INTEGER | PRIMARY KEY |
| sourceTable | TEXT | NOT NULL |
| sourceId | INTEGER | NOT NULL |
| embeddingRevision | INTEGER | (v3 migration) |

Maps USearch HNSW vector keys to source records across multiple tables. The indirection allows a single vector index to reference records from emailChunks, slackChunks, transcriptChunks, documents, and financialTransactions. The `embeddingRevision` column (added in v3 migration) records which `NLEmbedding.currentSentenceEmbeddingRevision(for:)` value generated each vector, enabling detection of model changes after OS updates.

#### widgetSnapshots

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| date | DATETIME | NOT NULL |
| weeklyAmount | DOUBLE | NOT NULL |
| weeklyTarget | DOUBLE | NOT NULL |
| velocityPercent | DOUBLE | NOT NULL |
| netWorth | DOUBLE | NOT NULL |
| dailyChange | DOUBLE | NOT NULL |

Pre-calculated data for WidgetKit (avoids loading USearch in 30MB widget process).

### Migration v2: Full Content

Adds the `meetingParticipants` junction table and extends existing tables with richer metadata.

#### meetingParticipants (new)

| Column | Type | Constraints |
|--------|------|-------------|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT |
| meetingId | INTEGER | NOT NULL, FK → meetings (CASCADE) |
| contactId | INTEGER | NOT NULL, FK → contacts (CASCADE) |
| role | TEXT | |
| speakingTimeSeconds | INTEGER | |

**Unique:** `(meetingId, contactId)`
**Indices:** `idx_mp_meeting`, `idx_mp_contact`

#### Column additions (v2)

| Table | New Columns |
|-------|-------------|
| emailChunks | `attachmentCount`, `attachmentNames`, `bccEmails`, `importance` |
| slackChunks | `userIds`, `realNames`, `companies`, `quarter`, `messageCount`, `isEdited`, `replyCount`, `emojiReactions`, `chunkIndex` |
| transcriptChunks | `quarter`, `startTime`, `endTime`, `speakerConfidence` |
| meetings | `quarter`, `description`, `teamDomain` |
| documents | `createdAt`, `indexedAt` |

Quarter values are backfilled from existing month data during migration.

### Migration v3: Embedding Revision Tracking

Adds `embeddingRevision` column to `vectorKeyMap` to track which NLEmbedding model version generated each vector. This enables detection of model changes after OS updates and targeted re-embedding.

#### Column additions (v3)

| Table | New Columns |
|-------|-------------|
| vectorKeyMap | `embeddingRevision INTEGER` |

---

## FTS5 Full-Text Search

### Virtual Table Configuration

All FTS5 tables use `synchronize(withTable:)` for automatic content sync (insertions, updates, deletes to the source table automatically update FTS). Tokenizer is `unicode61()` for all tables.

### BM25 Column Weights

Weights are applied at **query time** via raw SQL, NOT at schema definition time (GRDB has no `columnWeight()` API):

```sql
SELECT *, bm25(emailChunks_fts, 3.0, 2.0, 1.0) AS rank
FROM emailChunks_fts
WHERE emailChunks_fts MATCH ?
ORDER BY rank
```

| Table | Column Weights |
|-------|---------------|
| documents_fts | `filename=5.0`, `content=1.0` |
| emailChunks_fts | `subject=3.0`, `fromName=2.0`, `chunkText=1.0` |
| slackChunks_fts | `channel=2.0`, `chunkText=1.0` |
| transcriptChunks_fts | `speakerName=2.0`, `chunkText=1.0` |
| financialTransactions_fts | `payee=3.0`, `description=2.0`, `category=1.0` |

### Query Sanitization

1. Quoted phrases (`"exact match"`) pass through unchanged
2. Boolean operators (AND, OR, NOT, NEAR) detected via regex and passed through
3. Otherwise, tokens are cleaned (letters, numbers, hyphens, underscores only) and joined with spaces
4. If the initial FTS query throws an error, falls back to tokenized version

### Default Temporal Filter

When no temporal filter is specified (year, month, quarter, since), searches default to the **last 3 months**. This prevents overwhelming results from the full 1.3M+ record corpus.

---

## GRDB Record Types

All model structs conform to `Codable`, `Sendable`, `FetchableRecord`, `PersistableRecord`, and `MutablePersistableRecord`. They use GRDB's auto-synthesis from column names matching struct properties.

Key patterns:
- `autoIncrementedPrimaryKey` with optional `id: Int64?` property
- `insert(db, onConflict: .ignore)` for dedup during sync
- `upsert(db)` with custom `PersistenceConflictPolicy` for financial snapshots (insert: .replace, update: .replace)
- Batch writes in groups of 100 for transaction insertion

---

## USearch HNSW Vector Index

See [embeddings.md](embeddings.md) for complete vector storage documentation.

**Summary:**
- Two index files: `reality-512.usearch` (both platforms) and `reality-4096.usearch` (macOS only)
- Actor-based thread safety
- iOS uses memory-mapped loading (`.view()`) with int8 quantization
- macOS uses in-memory loading (`.load()`) with float32 quantization
- Generation swapping for atomic saves

---

## iCloud Sync (CKSyncEngine)

### Configuration

- **Container:** `iCloud.com.hackervalley.eddingsindex`
- **Zone:** `EddingsData` in private database
- **State persistence:** `ck-sync-state.dat` (JSON-serialized), persisted on every `.stateUpdate` event

### Synced Record Types

```
Contact, Company, FinancialTransaction, FinancialSnapshot,
Meeting, MonthlySummary, MeetingParticipant,
TranscriptChunk, EmailChunk, SlackChunk
```

### NOT Synced

- Meeting MP4 recordings (665GB)
- Raw email JSON archives
- 4096-dim embedding vectors
- VRAM filesystem
- USearch index files (rebuilt locally per device)
- Document records

### Large Content Handling

Text fields exceeding 50KB are stored as `CKAsset` instead of inline `CKRecord` fields:
- Writes: `attachContentAsAssetIfNeeded` checks `text.utf8.count < 50_000`
- Reads: `readContentFromAssetOrInline` tries the `Asset` variant first, falls back to inline

### Conflict Resolution

**Financial transactions** use field-level conflict resolution via `categoryModifiedAt`:
- Compares local vs server `categoryModifiedAt` timestamps
- Newer timestamp wins (prevents bulk import from overwriting manual iOS categorizations)
- Other record types: server record wins (standard CKSyncEngine behavior)

### Account Changes

| Event | Action |
|-------|--------|
| `.signOut` | Pause sync, log warning |
| `.switchAccounts` | Clear local sync state file |
| `.signIn` | Resume sync, log info |

### Record ID Format

All CKRecord IDs follow the pattern `{tableName}/{rowId}` (e.g., `contacts/42`). This enables bidirectional mapping between SQLite rows and CloudKit records.
