# PRD-04: Full Content Storage & Native Data Pipeline

**Status:** IMPLEMENTED
**Date:** 2026-03-16
**Author:** PAI
**Audit Method:** 15 parallel agents (10 Codex, 5 Gemini) auditing codebase, TypeScript search engine, Apple Developer Documentation, and VRAM source data formats
**Target:** Store full markdown content for transcripts, emails, Slack messages, and markdown files in SQLite; build native VRAM readers to replace PostgresMigrator; enhance search results with full content access; fix iCloud sync for large content via CKAsset

---

## Executive Summary

A comprehensive audit of TheEddingsIndex against the TypeScript VRAM Search Engine (`/Volumes/VRAM/00-09_System/01_Tools/search_engine/`) revealed that the Swift app's database is **not storing enough content to deliver search results equivalent to the search engine**. Three systemic failures:

1. **Content is destroyed during migration.** `PostgresMigrator.swift` truncates documents to 10,000 characters (line 106: `LEFT(content, 10000)`), strips all newlines from every content type (line 106, 145, 194, 231: `REPLACE(REPLACE(..., E'\\n', ' '), E'\\r', ' ')`), and loses email chunks to `UNIQUE(emailId)` collision when emails have multiple chunks.

2. **Native sync clients are stubs or incomplete.** `IMAPClient.swift` returns 0 and does nothing (line 25). `SlackClient.swift` dumps an entire day of messages into one chunk with raw user IDs instead of display names (line 46-47). `FathomClient.swift` chunks transcripts but omits year/month metadata. `FileScanner.swift` only stores the first chunk or 10K chars (line 48) and indexes JSON files that should be excluded (line 16).

3. **Search results cannot display full content.** `SearchResult.swift` has no full-content field — only a 200-character truncated preview. FTS5 `snippet()` in `FTSIndex.swift` targets header columns (column index 0: filename, subject, speakerName) instead of body text columns. No source locators exist to navigate from a result to the original content.

**The fix:** Build native VRAM readers that preserve full markdown content with all metadata, store it properly in SQLite, expose it through enhanced search results, and sync large content via CKAsset for iOS access.

**Scope:**
- **In scope:** Native email/slack/transcript/file readers from VRAM, schema migration for full content + metadata, SearchResult enhancement, FTS5 snippet fix, CKAsset for large content sync, meeting_participants junction table, JSON exclusion from indexing
- **Out of scope:** Markdown stripping before embedding (Ron: "pass"), new embedding models, SwiftUI views (UI changes follow this data layer work), App Store distribution

---

## Background & Evidence

### Audit Methodology

15 agents (10 Codex CLI, 5 Gemini CLI) ran parallel audits across three domains:

| Domain | Agent Count | Focus |
|--------|------------|-------|
| Swift codebase | 6 Codex | Schema, migrator data loss, search results, sync client implementation status |
| TypeScript search engine | 3 Codex + 2 Gemini | Email/Slack/transcript pipelines, hybrid search pipeline, PG↔SQLite schema comparison |
| Apple Developer Docs | 4 (2 Codex + 2 Gemini) | FTS5 limits, NLEmbedding input handling, CKRecord size limits, CKAsset patterns, storage best practices |

### Data Loss in PostgresMigrator (Codex Dog 2 — 157K tokens consumed)

| Function | Line | Loss Type | Evidence |
|----------|------|-----------|----------|
| `migrateDocuments` | 106 | `LEFT(content, 10000)` — truncates to 10K chars | Any document >10K chars loses remainder |
| `migrateDocuments` | 106 | `REPLACE(REPLACE(..., E'\\n', ' '), E'\\r', ' ')` — strips newlines | All markdown formatting destroyed |
| `migrateEmailChunks` | 145 | Same REPLACE on `chunk_text` and `subject` | Email body becomes single line |
| `migrateSlackChunks` | 194 | Same REPLACE on `chunk_text` | Conversation turns merged into one line |
| `migrateTranscriptChunks` | 231 | Same REPLACE on `chunk_text` | Speaker turns `[HH:MM] Name: text` become unreadable |
| `migrateTranscriptChunks` | 230-235 | No `year`, `month`, `speakers` extracted | Date filtering impossible for transcripts |
| `migrateEmailChunks` | 179 | `insert(db, onConflict: .ignore)` with `UNIQUE(emailId)` | Multi-chunk emails lose all chunks after the first |
| All functions | 60, 111 | U+001F field separator in content → column-shift corruption | Content containing U+001F breaks field parsing |

### Missing Fields: PostgreSQL → SQLite (Gemini Dog 1 — 1,937 lines)

| Table | Missing in SQLite | Severity |
|-------|------------------|----------|
| `meeting_participants` | **Entire table** — many-to-many meeting↔contact relation lost | CRITICAL |
| `email_chunks` | `attachment_count`, `attachment_names[]`, `bcc_emails[]`, `importance`, `cc_emails` (as array) | MEDIUM |
| `slack_chunks` | `real_names[]`, `companies[]`, `emoji_reactions[]`, `reply_count`, `is_edited`, `quarter`, `user_ids[]` | MEDIUM |
| `chunks` (transcripts) | `content_type`, `speaker_confidence`, `start_time`, `end_time`, `quarter` | MEDIUM |
| `transcript_meetings` | `description`, `team_domain`, `permalink`, `quarter` | LOW-MED |

### Native Sync Client Status (Codex Dog 10 — 1,853 lines)

| Client | Implementation | Content Handling |
|--------|---------------|-----------------|
| `IMAPClient.swift` | **Stub (0%)** — returns 0 at line 25 | No email reading |
| `SlackClient.swift` | **Partial (60%)** — reads JSON but one chunk/day, raw user IDs | No time-window grouping, no display names |
| `FathomClient.swift` | **Partial (50%)** — reads .md/.txt/.vtt/.srt, chunks with SmartChunker | No year/month, SmartChunker uses 200-word chunks vs search engine's 1800 chars |
| `FileScanner.swift` | **Working (80%)** — reads VRAM files | Only first chunk stored (line 48), indexes JSON (line 16) |
| `CalDAVClient.swift` | **Stub** | Not implemented |

### VRAM Source Data Formats (Gemini Dog 3 — 1,009 lines)

**Emails** (`/Volumes/VRAM/10-19_Work/14_Communications/14.01b_emails_json/`):
- Format: JSON per email, named `YYYY-MM-DD_HHMMSS_<hash>_<subject>.json`
- Content field: `content.body` (plain text, cleaned from HTML)
- Date: `headers.date.iso` (ISO 8601) + `headers.date.timestamp` (Unix)
- Threading: `threading.references[]` for thread chain
- Size: 5–100KB per file, ~4,800 files in 2026
- Organization: year directories (`2020/`–`2026/`)

**Slack** (`/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack/json/`):
- Format: JSON array per day per channel, named `YYYY-MM-DD.json`
- Content: `text` (plain with `<@USERID>` markers) + `blocks[]` (rich text)
- Identity: `user` (Slack user ID) + `user_profile.real_name` + `user_profile.display_name`
- Threading: `thread_ts`, `replies[]`, `reply_count`
- Reactions: `reactions[]` with emoji name + user IDs
- Files: `files[]` with metadata (name, size, type, URLs)
- Size: 0.5–50KB per file, 442 channels
- Timestamps: `ts` as `"seconds.microseconds"` string (parse as float)

**Transcripts** (`/Volumes/VRAM/10-19_Work/13_Meetings/13.01_transcripts/`):
- Format: Markdown with YAML frontmatter, named `YYYY-MM-DD-<meeting_id>.md`
- Content: `**[MM:SS]** **Speaker Name**: text` per turn
- Metadata: YAML `title`, `date` (ISO 8601 UTC), `meeting_id`
- Size: 5–100KB, ~330 files in 2026, ~2,100 in 2025
- Organization: year directories

### Search Engine Filter Capabilities (Explore Agent — 53K tokens)

The TypeScript search engine supports these filters that the Swift app must replicate:

| Filter | Type | Sources | Swift Status |
|--------|------|---------|-------------|
| `year` | Int | email, slack, transcript | Partially supported in FTSIndex |
| `month` | Int | email, slack, transcript | Partially supported |
| `quarter` | Int | email, slack, transcript | **Missing** (no quarter in schema) |
| `since` | Date | all | **Missing** |
| `allTime` | Bool | all | **Missing** (no default time window) |
| `person` | String | email, slack, transcript | **Missing** |
| `company` | String | email, slack, transcript | **Missing** |
| `speaker` | String | slack, transcript | **Missing** |
| `sentByMe` | Bool | email | **Missing** |
| `hasAttachments` | Bool | email | **Missing** |
| `isInternal` | Bool | transcript | **Missing** |
| `includeSpam` | Bool | email | **Missing** |
| `area` | String | file | Supported |
| `extension` | String | file | Supported |

**Default time window:** Search engine defaults to 3 months when no temporal filter is set (`pg-fts.ts` lines 644-650). The Swift app has no such default.

### Apple Developer Documentation Evidence

**SQLite TEXT limits** (Codex Dog 7 — `https://www.sqlite.org/limits.html`):
- SQLite TEXT columns: max ~1 billion bytes. Storing full 100KB transcripts is well within limits.
- FTS5 handles large documents but BM25 score saturates on very long text — chunking remains important for relevance ranking, not storage limits.
- WAL mode: correct for concurrent reader (widget) + writer (app). Per `https://www.sqlite.org/wal.html`.

**NLEmbedding** (Codex Dog 8 — `.../NaturalLanguage/NLEmbedding/README.md`):
- `vector(for:)` returns `[Double]?` — returns `nil` if input not processable, does not throw.
- No documented maximum input length. Treat as short-passage encoder.
- `NLContextualEmbedding` (`.../NaturalLanguage/NLContextualEmbedding/README.md`) available macOS 14+/iOS 17+ with `maximumSequenceLength` property — use for longer texts if needed.

**CKRecord limits** (`.../CloudKit/CKRecord/README.md`):
- Per-record limit: **1MB max** for all non-asset data combined.
- CKAsset does NOT count toward the 1MB limit — stored separately.

**CKAsset** (`.../CloudKit/CKAsset/README.md`):
- No documented size limit for assets.
- Created via `init(fileURL:)`, attached to CKRecord fields.
- Must copy from staging area immediately after fetch — system cleans staging regularly.
- Use `desiredKeys` to exclude assets from queries when not needed.

**File metadata** (`.../Foundation/URL/resourceValues(forKeys_)/README.md`):
- Use `URL.resourceValues(forKeys:)` with `contentModificationDateKey` and `creationDateKey` for file timestamps.
- `isExcludedFromBackupKey` must be re-set after every file save (resets to false on common operations). Per `.../Foundation/URLResourceKey/isExcludedFromBackupKey/README.md`.

**App Group** (`.../Foundation/FileManager/containerURL(forSecurityApplicationGroupIdentifier_)/README.md`):
- Returns shared container URL for `group.com.hackervalley.eddingsindex`.
- System creates `Library/Application Support`, `Library/Caches`, `Library/Preferences` subdirectories.

---

## Architecture

### Design Principles

1. **Store full content in SQLite.** iOS has no VRAM access. Every piece of content the user might want to read must live in the database. SQLite TEXT columns have no practical size limit.
2. **Chunk for search relevance, not storage.** Full content stored in the content table; chunks stored separately for FTS5 and embedding. Search returns chunks, but the user can navigate to full content.
3. **Preserve all metadata.** File dates (created, modified), Slack user IDs AND display names, email threading, transcript speaker timestamps — everything the search engine stores.
4. **Replicate search engine filters.** Every filter parameter in `pg-fts.ts` must have a Swift equivalent in `FTSIndex.swift`.
5. **No JSON in embeddings.** JSON files excluded from indexing/embedding pipeline entirely.

### Content Storage Model

```
Source File (VRAM)
    │
    ▼
Native Reader (Swift)
    │
    ├──→ Content Table (full markdown, all metadata, dates)
    │       • documents.content (full file, no truncation)
    │       • emailChunks.chunkText (full body with newlines)
    │       • slackChunks.chunkText (formatted conversation)
    │       • transcriptChunks.chunkText (speaker turns with timestamps)
    │
    ├──→ FTS5 Virtual Table (for keyword search + BM25 ranking)
    │       • Synchronized with content table via triggers
    │       • BM25 weights applied at query time
    │
    └──→ USearch Vector Index (for semantic search)
            • Chunks embedded, not full documents
            • vectorKeyMap links vector keys to source table + ID
```

---

## Schema Migrations

### Migration v2: Enhanced Content & Metadata

```swift
migrator.registerMigration("v2_full_content") { db in

    // -- meeting_participants junction table (CRITICAL missing from v1) --
    try db.create(table: "meetingParticipants") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("meetingId", .integer)
            .notNull()
            .references("meetings", onDelete: .cascade)
        t.column("contactId", .integer)
            .notNull()
            .references("contacts", onDelete: .cascade)
        t.column("role", .text)
        t.column("speakingTimeSeconds", .integer)
        t.uniqueKey(["meetingId", "contactId"])
    }
    try db.create(index: "idx_mp_meeting", on: "meetingParticipants", columns: ["meetingId"])
    try db.create(index: "idx_mp_contact", on: "meetingParticipants", columns: ["contactId"])

    // -- Add quarter to all temporal tables --
    try db.alter(table: "emailChunks") { t in
        t.add(column: "attachmentCount", .integer).defaults(to: 0)
        t.add(column: "attachmentNames", .text)  // JSON array
        t.add(column: "bccEmails", .text)         // JSON array
        t.add(column: "importance", .text)
    }

    try db.alter(table: "slackChunks") { t in
        t.add(column: "userIds", .text)           // JSON array of Slack user IDs
        t.add(column: "realNames", .text)         // JSON array of display names
        t.add(column: "companies", .text)         // JSON array
        t.add(column: "quarter", .integer)
        t.add(column: "messageCount", .integer)
        t.add(column: "isEdited", .boolean).defaults(to: false)
        t.add(column: "replyCount", .integer).defaults(to: 0)
        t.add(column: "emojiReactions", .text)    // JSON array
    }

    try db.alter(table: "transcriptChunks") { t in
        t.add(column: "quarter", .integer)
        t.add(column: "startTime", .text)         // "MM:SS" or seconds offset
        t.add(column: "endTime", .text)
        t.add(column: "speakerConfidence", .double)
    }

    try db.alter(table: "meetings") { t in
        t.add(column: "quarter", .integer)
        t.add(column: "description", .text)
        t.add(column: "teamDomain", .text)
    }

    // -- Add file metadata columns for date tracking --
    try db.alter(table: "documents") { t in
        t.add(column: "createdAt", .datetime)
        t.add(column: "indexedAt", .datetime)
    }

    // -- New indexes for filter support --
    try db.create(index: "idx_email_quarter", on: "emailChunks", columns: ["quarter"])
    try db.create(index: "idx_email_sent", on: "emailChunks", columns: ["isSentByMe"])
    try db.create(index: "idx_email_attachments", on: "emailChunks", columns: ["hasAttachments"])
    try db.create(index: "idx_slack_quarter", on: "slackChunks", columns: ["quarter"])
    try db.create(index: "idx_transcript_quarter", on: "transcriptChunks", columns: ["quarter"])
    try db.create(index: "idx_meeting_quarter", on: "meetings", columns: ["quarter"])
    try db.create(index: "idx_meeting_internal", on: "meetings", columns: ["isInternal"])

    // -- Backfill quarter for existing data --
    try db.execute(sql: """
        UPDATE emailChunks SET quarter = CASE
            WHEN month BETWEEN 1 AND 3 THEN 1
            WHEN month BETWEEN 4 AND 6 THEN 2
            WHEN month BETWEEN 7 AND 9 THEN 3
            WHEN month BETWEEN 10 AND 12 THEN 4
        END WHERE quarter IS NULL AND month IS NOT NULL
    """)

    try db.execute(sql: """
        UPDATE slackChunks SET quarter = CASE
            WHEN month BETWEEN 1 AND 3 THEN 1
            WHEN month BETWEEN 4 AND 6 THEN 2
            WHEN month BETWEEN 7 AND 9 THEN 3
            WHEN month BETWEEN 10 AND 12 THEN 4
        END WHERE quarter IS NULL AND month IS NOT NULL
    """)

    try db.execute(sql: """
        UPDATE meetings SET quarter = CASE
            WHEN month BETWEEN 1 AND 3 THEN 1
            WHEN month BETWEEN 4 AND 6 THEN 2
            WHEN month BETWEEN 7 AND 9 THEN 3
            WHEN month BETWEEN 10 AND 12 THEN 4
        END WHERE quarter IS NULL AND month IS NOT NULL
    """)
}
```

### Migration v2 Model Updates

**MeetingParticipant** (new model):
```swift
public struct MeetingParticipant: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var meetingId: Int64
    public var contactId: Int64
    public var role: String?
    public var speakingTimeSeconds: Int?
    public static let databaseTableName = "meetingParticipants"
}
```

---

## Native VRAM Readers

### Phase 1: Email Reader (`IMAPClient.swift` — currently stub)

**Source:** `/Volumes/VRAM/10-19_Work/14_Communications/14.01b_emails_json/{year}/{file}.json`

**JSON structure** (verified from sample `2026-01-01_060913_e671f78b43bdf72a_Ron, 2 remote roles needed.json`):
```
id.hash → emailId (unique per email, 8-char hex)
headers.subject → subject
headers.from.name → fromName
headers.from.email → fromEmail
headers.to[].email → toEmails (JSON array)
headers.cc[].email → ccEmails (JSON array)
headers.bcc[].email → bccEmails (JSON array)
headers.date.iso → emailDate (parse with ISO8601DateFormatter)
headers.date.timestamp → Unix timestamp (backup)
headers.in_reply_to → isReply (non-nil = true)
content.body → chunkText (FULL body with newlines preserved)
metadata.labels → labels (JSON array)
attachments.count → attachmentCount
attachments.files[].filename → attachmentNames (JSON array)
threading.thread_topic → threadId
```

**Chunking strategy:**
- Short emails (≤2000 chars): store as single chunk with `chunkIndex: 0`
- Long emails (>2000 chars): chunk at paragraph boundaries (`\n\n`), 1500–2000 char target, 300 char overlap
- Each chunk gets its own `emailId` suffix: `{hash}_chunk{N}` — avoids the UNIQUE collision bug
- `emailId` unique constraint must be changed to allow multi-chunk emails (use `emailId + chunkIndex` composite)

**Spam filtering:**
Per search engine `email-chunker.ts` line 72: skip emails where any label matches `/(^|[^a-z])(spam|junk|trash)([^a-z]|$)/i`

**Metadata extraction:**
```swift
let components = Calendar.current.dateComponents([.year, .month], from: emailDate)
let year = components.year
let month = components.month
let quarter = ((month ?? 1) - 1) / 3 + 1
let isSentByMe = fromEmail.lowercased().contains("@hackervalley.com")
    && fromEmail.lowercased().hasPrefix("ron")
```

**Deduplication:** Check `SELECT COUNT(*) FROM emailChunks WHERE emailId = ? AND chunkIndex = ?` before insert.

**File metadata:** Use `URL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])` per `.../Foundation/URL/resourceValues(forKeys_)/README.md` to capture when each JSON file was added to VRAM.

### Phase 2: Transcript Reader (`FathomClient.swift` — currently partial)

**Source:** `/Volumes/VRAM/10-19_Work/13_Meetings/13.01_transcripts/{year}/{file}.md`

**Markdown format** (verified from sample `2026-03-13-129872379.md`, 50.5KB):
```markdown
---
title: "Meeting Title"
date: 2026-03-13T20:12:14Z
meeting_id: "129872379"
---

# Meeting Title

## Transcript

**[MM:SS]** **Speaker Name**: Quoted text...
**[MM:SS]** **Another Speaker**: Response...
```

**Parsing requirements:**
1. Parse YAML frontmatter: extract `title`, `date` (ISO 8601), `meeting_id`
2. Parse speaker turns: regex `\*\*\[(\d{1,2}:\d{2})\]\*\*\s*\*\*([^*]+)\*\*:\s*(.+)` per line
3. Group turns into chunks by time window (match search engine's ~1800 char target with 400 char overlap)
4. Extract unique speakers per chunk
5. Compute `year`, `month`, `quarter` from frontmatter `date`
6. Upsert into `meetings` table with metadata from frontmatter

**Chunking strategy:**
- Use speaker-turn-aware chunking (from search engine's `smart-chunker.ts`):
  - Accumulate turns until ~1800 characters
  - Break at turn boundaries (never mid-sentence within a turn)
  - 400 char overlap for context continuity
  - Track `startTime` and `endTime` per chunk
  - Track all `speakers` per chunk as JSON array

**Meeting metadata:**
```swift
var meeting = Meeting(
    meetingId: frontmatter.meetingId,
    title: frontmatter.title,
    startTime: frontmatter.date,
    year: components.year,
    month: components.month,
    quarter: quarter,
    filePath: url.path()
)
```

**Meeting participants:** For each unique speaker name in the transcript, look up or create a Contact, then insert into `meetingParticipants`.

### Phase 3: Slack Reader (`SlackClient.swift` — currently partial, needs rewrite)

**Source:** `/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack/json/{channel}/{YYYY-MM-DD}.json`

**JSON format** (verified from sample `00-development/2025-04-18.json`, 14.6KB):
```json
[{
    "user": "U079XQ70Y2G",
    "text": "message text with <@USERID> mentions",
    "ts": "1745009138.940379",
    "user_profile": {
        "real_name": "Christian Santos",
        "display_name": "Christian",
        "name": "csantos"
    },
    "thread_ts": "...",
    "reactions": [{"name": "+1", "count": 2, "users": [...]}],
    "files": [{"name": "...", "size": 1234}]
}]
```

**Current problems in SlackClient.swift:**
1. Line 46-47: Concatenates ALL messages into one chunk with `[userId] text` format — no display names
2. No time-window grouping — one chunk per entire day regardless of conversation structure
3. No rich metadata (reactions, files, threads, real names)

**Required rewrite:**
1. Parse messages from JSON array
2. Group by 15-minute time windows (match search engine `slack-chunker.ts` SLACK_CONFIG.timeWindowMinutes = 15)
3. Format as `[HH:MM] DisplayName: text` preserving conversation structure
4. Preserve BOTH `user` (Slack user ID) AND `user_profile.real_name`/`display_name`
5. Store user IDs in `userIds` column (JSON array), display names in `realNames` column (JSON array), conversation speakers in `speakers` column (comma-separated for backward compat)
6. Track `messageCount`, `hasFiles`, `hasReactions`, `isEdited`, `replyCount`, `threadTs`, `isThreadReply`
7. Chunk at 1800 chars target with 300 char overlap, breaking at message boundaries

**Dedup:** Composite key of `channel + messageDate + chunkIndex` to allow multiple chunks per day per channel.

**Metadata extraction:**
```swift
let date = dateFormatter.date(from: dateStr)  // from filename YYYY-MM-DD
let components = Calendar.current.dateComponents([.year, .month], from: date)
let quarter = ((components.month ?? 1) - 1) / 3 + 1
```

### Phase 4: FileScanner Fixes

**Two changes required:**

1. **Exclude JSON files** (line 16): Remove `"json"` from `indexableExtensions`:
```swift
private let indexableExtensions: Set<String> = ["md", "txt", "csv", "yml", "yaml", "toml"]
```

2. **Store full content** (line 48): Replace first-chunk-only logic:
```swift
// BEFORE (line 48):
let storedContent = chunks.first?.text ?? String(content.prefix(10000))

// AFTER:
let storedContent = content  // Store FULL file content
```

3. **Add file dates** — capture `createdAt` and `modifiedAt` using `URL.resourceValues(forKeys:)` per `.../Foundation/URLResourceKey/contentModificationDateKey/README.md` and `.../Foundation/URLResourceKey/creationDateKey/README.md`.

---

## Search Enhancements

### SearchResult Model Enhancement

Current `SearchResult.swift` (6 fields):
```swift
public struct SearchResult: Codable, Sendable, Identifiable {
    public let id: Int64
    public let sourceTable: SourceTable
    public let title: String
    public let snippet: String?
    public let date: Date?
    public let score: Double
    public let metadata: [String: String]?
}
```

Enhanced `SearchResult` (add 3 fields):
```swift
public struct SearchResult: Codable, Sendable, Identifiable {
    public let id: Int64
    public let sourceTable: SourceTable
    public let title: String
    public let snippet: String?
    public let fullContent: String?     // NEW: full markdown content for display
    public let date: Date?
    public let score: Double
    public let metadata: [String: String]?
    public let sourceLocator: String?   // NEW: path/emailId/channel for navigation
    public let speakers: [String]?      // NEW: speakers for transcript/slack results
}
```

**`fullContent` population:** In `QueryEngine.swift` `resolveResult()`:
- Documents: `doc.content` (full file content)
- Emails: `email.chunkText` (full email body)
- Slack: `slack.chunkText` (formatted conversation)
- Transcripts: `chunk.chunkText` (speaker turns with timestamps)

**`sourceLocator` population:**
- Documents: `doc.path` (VRAM filesystem path)
- Emails: `email.emailPath` (path to JSON file) or `email.emailId`
- Slack: `"slack://\(slack.channel)/\(slack.messageDate)"`
- Transcripts: `chunk.filePath` (path to markdown file)

### FTS5 Snippet Fix

Current `FTSIndex.swift` line 110:
```swift
snippet(\(table.ftsTableName), 0, '<b>', '</b>', '...', 32)
```

Column 0 is the **header column** (filename, subject, speakerName, channel, payee). The body text is column 1 (content, chunkText) or column -1 (best match).

**Fix:** Use column index `-1` for best-match snippet across all columns:
```swift
snippet(\(table.ftsTableName), -1, '<b>', '</b>', '...', 64)
```

Or use column 1 explicitly for body content with increased token count:
```swift
// For emailChunks_fts: columns are [subject, fromName, chunkText]
// chunkText is column index 2
snippet(emailChunks_fts, 2, '<b>', '</b>', '...', 64)
```

### Enhanced Filtering in FTSIndex

Add filter parameters to match search engine capabilities:

```swift
public func search(
    query: String,
    tables: [FTSTable] = FTSTable.allCases,
    limit: Int = 50,
    year: Int? = nil,
    month: Int? = nil,
    quarter: Int? = nil,        // NEW
    since: Date? = nil,         // NEW
    person: String? = nil,      // NEW
    company: String? = nil,     // NEW
    speaker: String? = nil,     // NEW
    sentByMe: Bool? = nil,      // NEW (email only)
    hasAttachments: Bool? = nil, // NEW (email only)
    isInternal: Bool? = nil,    // NEW (transcript only)
    includeSpam: Bool = false   // NEW (email only)
) throws -> [FTSResult]
```

**Default time window:** When no temporal filter is set, default to 3 months per search engine behavior (`pg-fts.ts` lines 644-650).

---

## iCloud Sync: CKAsset for Large Content

### Current State

`iCloudManager.swift` syncs: contacts, companies, financialTransactions, financialSnapshots.

Does NOT sync: emails, slack, transcripts, documents, meetings.

### Changes Required

**Add to `syncableRecordTypes` (line 153):**
```swift
private static let syncableRecordTypes: Set<String> = [
    "Contact", "Company", "FinancialTransaction", "FinancialSnapshot",
    "Meeting", "MeetingParticipant",
    "TranscriptChunk", "EmailChunk", "SlackChunk"  // NEW
]
```

**Content sync strategy** per Apple docs evidence:

| Content Type | Avg Size | CKRecord Inline? | Strategy |
|-------------|----------|-------------------|----------|
| Email chunk | 1–5KB | Yes | Inline `chunkText` as CKRecord string field |
| Slack chunk | 1–5KB | Yes | Inline `chunkText` as CKRecord string field |
| Transcript chunk | 1–5KB | Yes | Inline `chunkText` as CKRecord string field |
| Full transcript (via document) | 5–100KB | Conditional | If <50KB: inline. If ≥50KB: CKAsset |
| Full document content | 1KB–1MB | Conditional | If <50KB: inline. If ≥50KB: CKAsset |

**CKAsset pattern** per `.../CloudKit/CKAsset/README.md`:
```swift
func buildCKRecord(for chunk: TranscriptChunk, recordID: CKRecord.ID) -> CKRecord {
    let record = CKRecord(recordType: "TranscriptChunk", recordID: recordID)
    record["filePath"] = chunk.filePath
    record["chunkIndex"] = chunk.chunkIndex
    record["speakerName"] = chunk.speakerName
    record["meetingId"] = chunk.meetingId
    record["year"] = chunk.year
    record["month"] = chunk.month

    // Content: inline if small, CKAsset if large
    let text = chunk.chunkText ?? ""
    if text.utf8.count < 50_000 {
        record["chunkText"] = text
    } else {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "ck-asset-\(UUID().uuidString).txt")
        try? text.write(to: tempURL, atomically: true, encoding: .utf8)
        record["chunkTextAsset"] = CKAsset(fileURL: tempURL)
    }
    return record
}
```

**On fetch:** Check `chunkTextAsset` first, fall back to inline `chunkText`:
```swift
let text = (record["chunkTextAsset"] as? CKAsset)
    .flatMap { try? String(contentsOf: $0.fileURL!, encoding: .utf8) }
    ?? record["chunkText"] as? String
```

---

## Implementation Phases

### Phase 1 (P0): Schema Migration + FileScanner Fix
**Goal:** Get the data model right before writing readers.

- [x] 1.1 — Add `v2_full_content` migration to `DatabaseManager.swift`
- [x] 1.2 — Create `MeetingParticipant` model
- [x] 1.3 — Add new columns to existing models (`SlackChunk`, `TranscriptChunk`, `Meeting`, `Document`, `EmailChunk`)
- [x] 1.4 — Remove `"json"` from `FileScanner.indexableExtensions`
- [x] 1.5 — Fix `FileScanner` to store full content (remove 10K truncation)
- [x] 1.6 — Add `createdAt`/`indexedAt` columns to documents, populate from file metadata
- [x] 1.7 — `swift build` — verify compilation
- [x] 1.8 — `swift test` — verify existing tests pass with new migration

**Guard:** `swift build` succeeds with zero errors. Migration applies cleanly on fresh DB.

### Phase 2 (P0): Email Reader
**Goal:** Native email ingestion from VRAM JSON files.

- [x] 2.1 — Define `EmailJSON` Codable struct matching the VRAM JSON format
- [x] 2.2 — Implement email chunking (1500–2000 char target, paragraph boundary splitting, 300 char overlap)
- [x] 2.3 — Implement spam/junk/trash label filtering
- [x] 2.4 — Implement `isSentByMe` detection (from_email matches `ron*@hackervalley.com`)
- [x] 2.5 — Implement year/month/quarter extraction
- [x] 2.6 — Implement deduplication (emailId + chunkIndex composite check)
- [x] 2.7 — Fix `emailId` UNIQUE constraint — change to composite unique on `(emailId, chunkIndex)` via migration
- [x] 2.8 — Implement full `IMAPClient.sync()` — iterate year dirs, parse JSON, chunk, insert
- [x] 2.9 — Test: run sync, verify emails indexed with full content and metadata preserved
- [x] 2.10 — Test: run sync twice, verify dedup (0 new inserts on second run)

**Guard:** `ei-cli sync --emails` indexes emails with chunkText containing full body with preserved newlines.

### Phase 3 (P0): Transcript Reader
**Goal:** Native transcript ingestion from VRAM markdown files.

- [x] 3.1 — Implement YAML frontmatter parser (extract title, date, meeting_id)
- [x] 3.2 — Implement speaker-turn-aware chunking (1800 char target, 400 char overlap, break at turn boundaries)
- [x] 3.3 — Implement speaker extraction from `**[MM:SS]** **Name**:` pattern
- [x] 3.4 — Implement `startTime`/`endTime` extraction per chunk
- [x] 3.5 — Implement year/month/quarter from frontmatter date
- [x] 3.6 — Upsert meeting metadata into `meetings` table
- [x] 3.7 — Populate `meetingParticipants` — for each unique speaker, find or create Contact, insert junction row
- [x] 3.8 — Rewrite `FathomClient.sync()` with enhanced chunking and metadata
- [x] 3.9 — Test: verify transcript chunks have full speaker turns with timestamps preserved
- [x] 3.10 — Test: verify meetings table populated with year/month/quarter

**Guard:** `ei-cli sync --transcripts` indexes transcripts with readable `[MM:SS] Speaker: text` format in chunkText.

### Phase 4 (P0): Slack Reader
**Goal:** Native Slack ingestion from VRAM JSON exports.

- [x] 4.1 — Define `SlackMessage` Codable struct matching VRAM JSON format
- [x] 4.2 — Implement 15-minute time-window grouping (match search engine's algorithm)
- [x] 4.3 — Implement message formatting: `[HH:MM] DisplayName: text` with file/reaction annotations
- [x] 4.4 — Implement speaker extraction: store BOTH user ID and display_name/real_name
- [x] 4.5 — Implement thread detection (thread_ts, isThreadReply, replyCount)
- [x] 4.6 — Implement chunking (1800 char target, 300 char overlap, break at message boundaries)
- [x] 4.7 — Populate all new columns: userIds, realNames, companies, quarter, messageCount, isEdited, replyCount, emojiReactions
- [x] 4.8 — Implement channel type detection (public, private, dm, group_dm)
- [x] 4.9 — Implement dedup: composite key of channel + messageDate + chunkIndex
- [x] 4.10 — Rewrite `SlackClient.sync()` completely
- [x] 4.11 — Test: verify chunks have formatted conversations with display names AND user IDs
- [x] 4.12 — Test: verify time-window grouping produces multiple chunks per active day

**Guard:** `ei-cli sync --slack` produces readable conversation chunks with speaker identity preserved (both user ID and display name).

### Phase 5 (P1): Search Result Enhancement
**Goal:** Search results expose full content and match search engine capabilities.

- [x] 5.1 — Add `fullContent`, `sourceLocator`, `speakers` to `SearchResult`
- [x] 5.2 — Update `QueryEngine.resolveResult()` to populate new fields from source records
- [x] 5.3 — Fix FTS5 snippet column index (use -1 or body column index)
- [x] 5.4 — Increase snippet token count from 32 to 64
- [x] 5.5 — Add enhanced filter parameters to `FTSIndex.search()`
- [x] 5.6 — Implement `since` filter with 3-month default when no temporal filter set
- [x] 5.7 — Implement `person` filter (LIKE match on sender names/emails across sources)
- [x] 5.8 — Implement `speaker` filter for transcript and slack chunks
- [x] 5.9 — Implement `sentByMe`, `hasAttachments`, `isInternal`, `includeSpam` filters
- [x] 5.10 — Implement `quarter` filter
- [x] 5.11 — Test: verify search returns full content in results
- [x] 5.12 — Test: verify filters produce correct filtered results
- [x] 5.13 — Test: `ei-cli search --json "Optro"` returns results with fullContent populated

**Guard:** CLI search output includes full readable content and all metadata. Filters match search engine behavior.

### Phase 6 (P1): iCloud Sync Enhancement
**Goal:** Sync content records to iOS via CKSyncEngine with CKAsset for large content.

- [x] 6.1 — Add TranscriptChunk, EmailChunk, SlackChunk, Meeting, MeetingParticipant to syncable record types
- [x] 6.2 — Implement `buildCKRecord()` for each new syncable type
- [x] 6.3 — Implement CKAsset strategy: inline if <50KB, CKAsset if ≥50KB
- [x] 6.4 — Implement `upsertRecord()` for each new type (handle CKAsset fetch)
- [x] 6.5 — Implement `deleteRecord()` for each new type
- [x] 6.6 — Set `isExcludedFromBackup` on USearch index files per `.../Foundation/URLResourceKey/isExcludedFromBackupKey/README.md`
- [x] 6.7 — Test: verify records sync to iCloud (check CloudKit Dashboard)
- [x] 6.8 — Test: verify large content uses CKAsset path

**Guard:** Records appear in CloudKit Dashboard. Content accessible on second device.

---

## Files to Modify

| File | Phase | Change |
|------|-------|--------|
| `Sources/EddingsKit/Storage/DatabaseManager.swift` | 1 | Add v2 migration |
| `Sources/EddingsKit/Models/MeetingParticipant.swift` | 1 | New file |
| `Sources/EddingsKit/Models/EmailChunk.swift` | 1,2 | Add new columns |
| `Sources/EddingsKit/Models/SlackChunk.swift` | 1,4 | Add new columns |
| `Sources/EddingsKit/Models/TranscriptChunk.swift` | 1,3 | Add new columns |
| `Sources/EddingsKit/Models/Meeting.swift` | 1,3 | Add quarter, description, teamDomain |
| `Sources/EddingsKit/Models/Document.swift` | 1 | Add createdAt, indexedAt |
| `Sources/EddingsKit/Models/SearchResult.swift` | 5 | Add fullContent, sourceLocator, speakers |
| `Sources/EddingsKit/Sync/IMAPClient.swift` | 2 | Full rewrite — native email reader |
| `Sources/EddingsKit/Sync/FathomClient.swift` | 3 | Enhanced chunking + metadata |
| `Sources/EddingsKit/Sync/SlackClient.swift` | 4 | Full rewrite — time-window grouping |
| `Sources/EddingsKit/Sync/FileScanner.swift` | 1 | Remove JSON, store full content, add dates |
| `Sources/EddingsKit/Storage/FTSIndex.swift` | 5 | Fix snippet column, add filters |
| `Sources/EddingsKit/Search/QueryEngine.swift` | 5 | Populate new SearchResult fields |
| `Sources/EddingsKit/CloudSync/iCloudManager.swift` | 6 | Sync content records, CKAsset |

**New files:**
| File | Phase | Purpose |
|------|-------|---------|
| `Sources/EddingsKit/Models/MeetingParticipant.swift` | 1 | Junction table model |
| `Sources/EddingsKit/Normalize/EmailParser.swift` | 2 | Parse VRAM email JSON |
| `Sources/EddingsKit/Normalize/TranscriptParser.swift` | 3 | Parse YAML frontmatter + speaker turns |
| `Sources/EddingsKit/Normalize/SlackParser.swift` | 4 | Parse Slack JSON + time-window grouping |

---

## Testing & Verification Protocol

### Per-Phase Verification

| ID | Phase | Check | Method | Pass Criteria |
|----|-------|-------|--------|---------------|
| V-1 | 1 | Migration applies cleanly | Fresh DB init | No errors, all tables + columns exist |
| V-2 | 1 | Existing tests pass | `swift test` | Zero failures |
| V-3 | 1 | JSON excluded from file scan | `ei-cli sync --files` | Zero .json files in documents table |
| V-4 | 1 | Full content stored for files | Query documents.content | Content matches source file exactly |
| V-5 | 2 | Emails indexed with full body | `ei-cli sync --emails` | chunkText contains newlines, readable paragraphs |
| V-6 | 2 | Email dedup works | Run sync twice | 0 new inserts on second run |
| V-7 | 2 | Spam filtered | Check labels | No spam/junk/trash labeled emails in DB |
| V-8 | 2 | Multi-chunk emails preserved | Long email check | All chunks present for emails >2000 chars |
| V-9 | 3 | Transcripts have speaker turns | Query transcriptChunks | chunkText contains `[MM:SS] Speaker:` format |
| V-10 | 3 | Meeting metadata populated | Query meetings | title, year, month, quarter populated |
| V-11 | 3 | meetingParticipants populated | Query junction | Contacts linked to meetings |
| V-12 | 4 | Slack has display names | Query slackChunks.realNames | JSON array contains real names, not just user IDs |
| V-13 | 4 | Time-window grouping works | Active day produces >1 chunk | Multiple chunks per day with high message volume |
| V-14 | 4 | User IDs preserved | Query slackChunks.userIds | Slack user IDs stored alongside display names |
| V-15 | 5 | Search returns full content | `ei-cli search --json "test"` | fullContent field populated in JSON output |
| V-16 | 5 | Snippet shows body text | Search result snippets | Snippets from body content, not headers |
| V-17 | 5 | Filters work | Year/person/speaker filter | Filtered results match expected data |
| V-18 | 6 | CKAsset used for large content | Sync 100KB transcript | Content stored as CKAsset in CloudKit |

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Database size increase from full content | MEDIUM | SQLite handles large DBs well. Monitor with `PRAGMA page_count * page_size`. Full content for ~300K records at avg 5KB = ~1.5GB — well within 2TB iPhone. |
| iCloud sync quota for large content | MEDIUM | CKAsset for content >50KB. Monitor quota via CloudKit Dashboard. Free tier: 1GB assets, 10MB per asset. |
| Migration breaks existing data | LOW | v2 migration only ADDs columns (ALTER TABLE ADD) and creates new table. No existing data modified. |
| Email unique constraint change | MEDIUM | Must handle in migration carefully — drop old unique index on emailId, create composite unique on (emailId, chunkIndex). |
| SmartChunker chunk size mismatch | LOW | Align with search engine's 1800 char target for new readers. Existing 200-word SmartChunker only used by FileScanner (acceptable for general files). |
| NLEmbedding returns nil for long text | LOW | Chunking ensures text stays within embedding model's sweet spot. Per `.../NaturalLanguage/NLEmbedding/README.md`, returns nil rather than erroring. |
| Slack user_profile might be missing | LOW | Fall back to `user` (Slack user ID) when `user_profile` is absent. Store both fields always. |

---

## Success Criteria

When all phases are complete:

1. `ei-cli search --json "Optro"` returns results with full readable content across emails, Slack, and transcripts — matching what the TypeScript search engine returns
2. `ei-cli sync --all` natively reads from VRAM without PostgreSQL dependency
3. No JSON artifacts appear in search results
4. Every email chunk preserves full body with paragraph breaks
5. Every transcript chunk preserves `[MM:SS] Speaker: text` format
6. Every Slack chunk includes both user IDs and display names
7. Search filters (year, month, quarter, person, speaker, sentByMe, hasAttachments, isInternal) work identically to the TypeScript search engine
8. Large transcripts sync to iOS via CKAsset
9. `meetingParticipants` junction table links meetings to contacts

---

## Apple Developer Documentation References

| Framework | Doc Path | API | Usage |
|-----------|----------|-----|-------|
| CloudKit | `.../CloudKit/CKAsset/README.md` | `CKAsset(fileURL:)` | Large content sync to iCloud |
| CloudKit | `.../CloudKit/CKRecord/README.md` | 1MB per-record limit | Size threshold for CKAsset decision |
| CloudKit | `.../CloudKit/CKSyncEngine-5sie5/README.md` | `handleEvent(_:syncEngine:)` | Sync delegate pattern |
| CloudKit | `.../CloudKit/local-records/README.md` | `encodeSystemFields(with:)` | Local record caching |
| NaturalLanguage | `.../NaturalLanguage/NLEmbedding/README.md` | `vector(for:)` returns `nil` on failure | Input handling for embeddings |
| NaturalLanguage | `.../NaturalLanguage/NLContextualEmbedding/README.md` | `maximumSequenceLength` | Alternative for longer text (future) |
| Foundation | `.../Foundation/URL/resourceValues(forKeys_)/README.md` | `contentModificationDateKey`, `creationDateKey` | File date metadata |
| Foundation | `.../Foundation/URLResourceKey/isExcludedFromBackupKey/README.md` | `isExcludedFromBackup` | Exclude large files from iCloud backup |
| Foundation | `.../Foundation/FileManager/containerURL(forSecurityApplicationGroupIdentifier_)/README.md` | App Group container URL | Shared database location |
| SQLite | `https://www.sqlite.org/limits.html` | TEXT max ~1B bytes | Full content storage is safe |
| SQLite | `https://www.sqlite.org/fts5.html` | FTS5 snippet(), bm25() | Search relevance and highlighting |
| SQLite | `https://www.sqlite.org/wal.html` | WAL mode | Concurrent reader + writer |
