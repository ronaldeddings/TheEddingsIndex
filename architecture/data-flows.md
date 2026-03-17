# Data Flows

How data moves through TheEddingsIndex — from external sources, through normalization, into storage, and out through search.

---

## System Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          EXTERNAL DATA SOURCES                          │
│                                                                         │
│  SimpleFin API     QBO CSV Dumps    VRAM Filesystem     Qwen3 Server   │
│  (banking)         (HVM finance)    (/Volumes/VRAM)      (port 8081)    │
│       │                │                   │                  │         │
└───────┼────────────────┼───────────────────┼──────────────────┼─────────┘
        │                │                   │                  │
        ▼                ▼                   │                  │
 ┌──────────────┐ ┌─────────────┐           │                  │
 │ SimpleFinClient│ │ QBOReader   │           │                  │
 └──────┬───────┘ └──────┬──────┘           │                  │
        │                │                   │                  │
        ▼                ▼                   │                  │
 ┌────────────────────────────┐             │                  │
 │   FinanceSyncPipeline      │             │                  │
 │   • Normalizer             │             │                  │
 │   • Deduplicator           │             │                  │
 │   • Categorizer            │             │                  │
 │   • FreedomTracker         │             │                  │
 └──────────────┬─────────────┘             │                  │
                │                            │                  │
                ▼                            ▼                  │
 ┌────────────────────────────────────────────────┐            │
 │              SQLite (GRDB DatabasePool)         │            │
 │                                                 │            │
 │  financialTransactions  │  emailChunks          │            │
 │  financialSnapshots     │  slackChunks          │            │
 │  widgetSnapshots        │  transcriptChunks     │            │
 │  contacts / companies   │  documents / meetings │            │
 │                                                 │            │
 │  FTS5 Virtual Tables (auto-synced)              │            │
 │  vectorKeyMap • pendingEmbeddings               │            │
 └──────────┬──────────────────────────────────────┘            │
            │                                                    │
            ├────────────────────────────────────────────────────┤
            │                                                    │
            ▼                                                    ▼
 ┌──────────────────┐                              ┌──────────────────┐
 │  USearch HNSW    │                              │  QwenClient      │
 │  reality-512     │◄─── (PostgresMigrator) ──────│  → embed query   │
 │  reality-4096    │                              │  → search vectors│
 └────────┬─────────┘                              └────────┬─────────┘
          │                                                  │
          └──────────────────┬───────────────────────────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │   QueryEngine        │
                  │   FTS + Semantic      │
                  │   → HybridRanker     │
                  │   → Top 20 results   │
                  └──────────────────────┘
```

---

## Sync Pipelines

### Orchestration (SyncCommand)

The CLI `sync` command orchestrates all pipelines sequentially:

```
ei-cli sync --all
    │
    ├─ 1. FinanceSyncPipeline (SimpleFin + QBO)
    ├─ 2. FileScanner (VRAM filesystem)
    ├─ 3. SlackClient (Slack exports)
    ├─ 4. IMAPClient (Email JSON files)
    └─ 5. FathomClient (Meeting transcripts)
```

Each pipeline runs independently. Failures in one pipeline don't stop others — errors are collected and reported at the end. The launch agent runs `sync --all` every 12 hours.

### 1. Finance Pipeline

**Source:** SimpleFin API + QBO CSV dumps
**Trigger:** `sync --finance` or `sync --all`

```
SimpleFin API (OAuth) ─────┐
                           ├─► Normalizer ─► Deduplicator ─► Categorizer ─► SQLite
QBO CSV files ─────────────┘                     │
                                                  ▼
                                        FreedomTracker ─► widgetSnapshots
                                                  │
                                                  ▼
                                          VRAMWriter (disk backup)
```

**Detailed flow:**
1. **State check:** Read last sync timestamp from `StateManager`
2. **Overlap window:** `Deduplicator.overlapStartDate(lastSync:)` — pulls transactions with overlap to catch stragglers
3. **Fetch:** `SimpleFinClient.fetchAccounts(startDate:)` — hits SimpleFin API with OAuth access URL from Keychain
4. **Normalize:** `Normalizer.normalizeAccounts()` → `[FinancialSnapshot]`; `Normalizer.normalizeTransactions()` → `[FinancialTransaction]`; `detectTransfers()` marks internal moves
5. **QBO append:** `QBOReader.readAll()` reads CSV deposit records from `/Volumes/VRAM/10-19_Work/10_Hacker_Valley_Media/10.06_finance/QuickBooksOnline/`
6. **Deduplicate:** Exact ID match + fuzzy (amount ± $0.01, date ± 2 days, same payee)
7. **Categorize:** `Categorizer` uses `MerchantMap` for payee → category mapping
8. **Insert:** Batch upsert (100 per transaction) into `financialTransactions` and `financialSnapshots`
9. **Freedom calculation:** Pull last 12 weeks of transactions, calculate weekly non-W2 income vs $6,058 target
10. **Widget update:** Insert `WidgetSnapshot` row, trigger `WidgetCenter.shared.reloadAllTimelines()`
11. **VRAM backup:** If mounted, write snapshot + transaction files to disk
12. **State update:** Record sync timestamp + record count

### 2. File Scanner

**Source:** VRAM filesystem (`/Volumes/VRAM`)
**Trigger:** `sync --files` or `sync --all`

```
/Volumes/VRAM/
  ├─ 10-19_Work/
  ├─ 20-29_Finance/
  ├─ 30-39_Personal/     ──► FileScanner ──► documents table ──► documents_fts
  ├─ 40-49_Family/
  ├─ 50-59_Social/
  ├─ 60-69_Growth/
  └─ 70-79_Lifestyle/
```

**Indexable extensions:** `.md`, `.txt`, `.csv`, `.yml`, `.yaml`, `.toml`
**Size limit:** <1MB per file
**Skip:** Hidden files, package descendants, `00-09_System`, `80-89_Resources`, `90-99_Archive`
**Dedup:** Checks existing paths in `documents` table before indexing
**Metadata:** Extracts Johnny.Decimal area + category from path structure

### 3. Slack Sync

**Source:** Slack JSON exports at `/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack/`
**Trigger:** `sync --slack` or `sync --all`

```
/14.02_slack/
  └─ json/
      ├─ #channel-name/
      │   ├─ 2025-01-15.json   ──► SlackParser ──► slackChunks ──► slackChunks_fts
      │   └─ 2025-01-16.json
      └─ #another-channel/
          └─ ...
```

**Channel type detection:** Prefix-based — `dm-` → dm, `group-`/`mpdm-` → group_dm, `private-` → private, else → public
**Dedup key:** `{channel}|{date}|{chunkIndex}`
**Parsing:** `SlackParser.parseMessages(data:)` extracts messages, then `toSlackChunks()` groups them with metadata

### 4. Email Sync

**Source:** Email JSON files at `/Volumes/VRAM/10-19_Work/14_Communications/14.01b_emails_json/`
**Trigger:** `sync --emails` or `sync --all`

```
/14.01b_emails_json/
  ├─ 2024/
  │   ├─ email-abc123.json   ──► EmailParser ──► emailChunks ──► emailChunks_fts
  │   └─ email-def456.json
  └─ 2025/
      └─ ...
```

**Process:**
1. Load all existing `emailId` values into a Set for dedup
2. Iterate year directories sorted chronologically
3. Parse each JSON file via `EmailParser.parse(data:)`
4. `EmailParser.isSpam()` filters junk
5. `EmailParser.toEmailChunks()` creates indexed chunks with subject/from/date extraction
6. Skip if all chunks already exist
7. Insert with `onConflict: .ignore`

### 5. Meeting Transcript Sync

**Source:** Fathom transcripts at `/Volumes/VRAM/10-19_Work/13_Meetings/13.01_transcripts/`
**Trigger:** `sync --meetings` or `sync --all`

```
/13.01_transcripts/
  ├─ Meeting-Title-2025-01-15.md   ──► TranscriptParser ──► transcriptChunks
  └─ Another-Meeting.txt                                  ──► meetings
                                                          ──► contacts
                                                          ──► meetingParticipants
```

**Process:**
1. Enumerate `.md` and `.txt` files recursively
2. Skip files with existing `filePath` in `transcriptChunks`
3. `TranscriptParser.toTranscriptChunks()` extracts frontmatter (title, date, meetingId) and speaker-attributed chunks
4. Create/update `Meeting` record
5. Insert `TranscriptChunk` records
6. For each unique speaker:
   - Find or create `Contact` record (increment `meetingCount`, update `lastSeenAt`)
   - Create `MeetingParticipant` junction record

This is the only sync pipeline that creates **contact and relationship data** as a side effect.

---

## Search Pipeline

### Query Flow

```
User Input: "cybersecurity budget discussion"
        │
        ▼
┌─────────────────────────────────────────────────────┐
│ SearchCommand (CLI) / EddingsEngine (App)           │
│                                                      │
│  1. Parse query + options (sources, year, month...)  │
│  2. If not --fts-only:                               │
│     Try QwenClient.embed(query) → 4096-dim vector   │
│     (falls back gracefully if server unavailable)    │
│  3. Call QueryEngine.search(query, embedding)        │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ QueryEngine (actor)                                  │
│                                                      │
│  FTS Path:                                           │
│  ├─ FTSIndex.search(query, tables, limit*3)         │
│  ├─ Returns up to 150 results ranked by BM25        │
│  │                                                   │
│  Semantic Path (if embedding provided):              │
│  ├─ VectorIndex.search(vector, count: limit*3)      │
│  ├─ Returns up to 60 nearest neighbors              │
│  ├─ resolveVectorKeys() → maps USearch keys to rows │
│  │                                                   │
│  Fusion:                                             │
│  ├─ HybridRanker.rank(ftsResults, semanticResults)  │
│  ├─ RRF: ftsWeight=0.4, semanticWeight=0.6, k=60   │
│  ├─ Dedup by (sourceId, sourceTable)                │
│  ├─ Sort by combined score descending               │
│  ├─ Take top 20                                      │
│  │                                                   │
│  Hydration:                                          │
│  ├─ resolveResults() → fetch full records from SQLite│
│  └─ Build SearchResult with snippet, date, metadata │
└─────────────────────────────────────────────────────┘
```

### Filter Support

| Filter | Where Applied | Tables Affected |
|--------|---------------|-----------------|
| `--year` | SQL WHERE clause | All except documents |
| `--month` | SQL WHERE clause | All except documents |
| `--quarter` | SQL WHERE clause | All except documents |
| `--since` | Date comparison | emailChunks, slackChunks, financialTransactions |
| `--sources` | Table selection | Limits which FTS tables are queried |
| `--fts-only` | Skip embedding | No semantic search, FTS results only |
| `person:` | LIKE matching | fromName, fromEmail, toEmails, speakers, realNames |
| `speaker:` | LIKE matching | speakers (slack, transcript) |
| `sentByMe:` | Boolean filter | emailChunks only |
| `hasAttachments:` | Boolean filter | emailChunks only |
| `isInternal:` | Subquery | transcriptChunks → meetings.isInternal |

---

## PostgreSQL Migration Flow

One-time migration from the existing TypeScript search engine (`localhost:4432`):

```
PostgreSQL (345K+ embeddings, 1.3M+ records)
        │
        ▼
┌─────────────────────────────────────────────────┐
│ PostgresMigrator                                 │
│                                                  │
│ Phase 1: Data Import                             │
│ ├─ psql export with \u{1F} separator             │
│ ├─ Stream 50K rows at a time                     │
│ ├─ Foreign keys disabled for bulk speed          │
│ ├─ Tables: documents, emailChunks, slackChunks,  │
│ │  transcriptChunks, contacts, companies, meetings│
│ ├─ Rebuild FTS5 indices post-import              │
│ └─ Progress logging at 100K increments           │
│                                                  │
│ Phase 2: Vector Migration                        │
│ ├─ Query PG for non-null embedding records       │
│ ├─ Parse 4096-dim float vectors from text format │
│ ├─ Add to USearch with incrementing vectorKey    │
│ ├─ Record mapping in vectorKeyMap table          │
│ ├─ Sources: transcripts, emails, slack only      │
│ └─ Save USearch index (generation swapped)       │
└─────────────────────────────────────────────────┘
```

---

## iCloud Sync Flow

```
┌──────────────┐         CKSyncEngine          ┌──────────────┐
│  macOS Device │ ◄──── iCloud Private DB ────► │  iOS Device   │
│  (primary)    │                                │  (secondary)  │
└──────┬───────┘                                └──────┬───────┘
       │                                               │
       ▼                                               ▼
  Full SQLite DB                               Synced subset only
  + USearch 512 + 4096                         + USearch 512 only
  + VRAM access                                + No VRAM access
```

**Sync direction:** Bidirectional. macOS is primary data producer; iOS receives + can modify categories.

**Conflict resolution:** `categoryModifiedAt` timestamp wins for financial transaction categories. Server record wins for all other types.

**Large text handling:** Chunk text >50KB stored as CKAsset (file attachment) instead of inline CKRecord field.

**State persistence:** CKSyncEngine state serialized to `ck-sync-state.dat` on every `.stateUpdate` event.

---

## Launch Agent Automation

**File:** `com.vram.eddings-index.plist`

```
Every 12 hours (and at login):
    .build/release/ei-cli sync --all
        │
        ├─ Finance (SimpleFin API + QBO)
        ├─ Files (VRAM scan)
        ├─ Slack (export parse)
        ├─ Emails (JSON parse)
        └─ Meetings (transcript parse)
        │
        ├─ stdout → ~/Library/Logs/vram/reality/sync.log
        └─ stderr → ~/Library/Logs/vram/reality/error.log
```

---

## Intelligence Pipelines

### Freedom Tracker

```
financialTransactions (last 12 weeks)
        │
        ▼
FreedomTracker.calculate()
  ├─ Filter: non-W2, non-transfer income
  ├─ Calculate: weekly average take-home
  ├─ Compare: vs $6,058/week target
  ├─ Output: velocityPercent, weeklyAmount, projection date
  └─ Store: widgetSnapshots table
```

### Relationship Scorer

```
contacts table (emailCount, meetingCount, slackCount)
        │
        ▼
RelationshipScorer
  ├─ Weight: email × 1, meeting × 3, slack × 0.5
  ├─ Recency: lastSeenAt decay
  ├─ Output: depth score per contact
  └─ Surfaced in: ContactList (sorted by depth/recent/fading)
```

### Anomaly Detection

```
financialTransactions + contacts
        │
        ▼
AnomalyDetector
  ├─ Unusual transaction amounts
  ├─ Unusual contact patterns
  └─ Output: alerts for ActivityDigest
```
