# Architecture Overview

TheEddingsIndex is a Swift multiplatform personal intelligence platform (macOS + iOS) that unifies financial data, communications (email, Slack), meetings, documents, and relationships into a single searchable system with hybrid full-text + semantic search.

---

## System Context

```
┌──────────────────────────────────────────────────────────────────────┐
│                        External Data Sources                         │
│                                                                      │
│  SimpleFin API    QBO CSVs     VRAM Filesystem     Qwen3 Server     │
│  (banking)        (HVM finance) (emails, Slack,     (port 8081)      │
│                                  meetings, files)                    │
└──────┬──────────────┬──────────────┬───────────────────┬─────────────┘
       │              │              │                   │
       ▼              ▼              ▼                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      TheEddingsIndex                                 │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐    │
│  │ Sync     │  │ Storage  │  │ Search   │  │ Intelligence     │    │
│  │ Pipeline │→ │ (SQLite  │→ │ (FTS5 +  │  │ (Freedom Tracker │    │
│  │          │  │  + USearch│  │  Semantic)│  │  Relationships   │    │
│  │          │  │  + iCloud)│  │          │  │  Anomaly Detect) │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘    │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                          │
│  │ ei-cli   │  │ SwiftUI  │  │ Widgets  │                          │
│  │ (macOS   │  │ App      │  │ (Widget  │                          │
│  │  launch  │  │ (macOS + │  │  Kit)    │                          │
│  │  agent)  │  │  iOS)    │  │          │                          │
│  └──────────┘  └──────────┘  └──────────┘                          │
└──────────────────────────────────────────────────────────────────────┘
       │                   │                    │
       ▼                   ▼                    ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Launch Agent          iCloud Private DB       App Group Container   │
│  (12hr sync)           (CKSyncEngine)          (shared SQLite)       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Targets & Products

| Target | Type | Platform | Purpose |
|--------|------|----------|---------|
| `EddingsKit` | Library | macOS + iOS | Shared core: models, storage, sync, search, intelligence |
| `ei-cli` | Executable | macOS | CLI tool for sync/search/status/migrate, runs as launch agent |
| `TheEddingsIndex` | Executable | macOS + iOS | SwiftUI app with NavigationSplitView (macOS) / TabView (iOS) |
| `EddingsWidgets` | WidgetKit Extension | iOS | Freedom Velocity + Net Worth widgets |

### Package.swift

- **Platforms:** macOS 15+, iOS 18+
- **Language Mode:** Swift 6 (strict concurrency)
- **Dependencies:** 3 total
  - `swift-argument-parser` (1.5.0+) — CLI command parsing
  - `GRDB.swift` (7.0.0+) — SQLite with FTS5
  - `USearch` (2.0.0+) — HNSW vector index

---

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Language | Swift 6 | Strict concurrency, Sendable models |
| Storage | SQLite via GRDB.swift | Relational data, FTS5 full-text search, BM25 ranking |
| Vectors | USearch HNSW | 512-dim (iOS/macOS) + 4096-dim (macOS) cosine similarity |
| iCloud | CKSyncEngine | Private database sync between devices |
| Embeddings (small) | NaturalLanguage framework | 512-dim sentence embeddings, both platforms |
| Embeddings (large) | Qwen3 HTTP API (port 8081) | 4096-dim embeddings, macOS only |
| UI | SwiftUI | NavigationSplitView (macOS 3-column) / TabView (iOS) |
| Auth | Keychain (SecItem) | Credential storage with biometric protection |
| CLI | swift-argument-parser | Subcommands: sync, search, status, migrate |
| Widgets | WidgetKit | Freedom Velocity gauge, Net Worth display |

---

## EddingsKit Subsystems (53 files)

The shared library is organized into 7 subsystems:

### Storage (4 files)
- **DatabaseManager** — GRDB `DatabasePool`, WAL mode, schema migrations
- **FTSIndex** — FTS5 BM25 search across 5 content tables with column weighting
- **VectorIndex** — USearch HNSW actor (thread-safe mutations, concurrent reads)
- **StateManager** — Sync checkpoint persistence

### Sync/Import (11 files)
- **SimpleFinClient** — Banking API integration (OAuth)
- **QBOReader** — QuickBooks Online CSV deposits
- **IMAPClient** — Email JSON file parsing from VRAM
- **SlackClient** — Slack export parsing
- **FathomClient** — Meeting transcript sync
- **FileScanner** — Recursive VRAM filesystem scanning
- **CalDAVClient** — Calendar sync for meetings
- **PostgresMigrator** — One-time 1.3M+ record migration from PostgreSQL
- **FinanceSyncPipeline** — Orchestrates finance: aggregation → dedup → FreedomTracker → categorization
- **BackgroundTaskManager** — iOS BGAppRefreshTask + BGProcessingTask
- **VRAMWriter** — Checkpoint writing for iCloud CKSyncEngine

### Normalization (6 files)
- **Normalizer** — SimpleFin accounts/transactions normalization
- **EmailParser** — Email subject/from/date extraction + chunking
- **SlackParser** — Slack message chunking (preserves channel, user)
- **TranscriptParser** — Speaker + timestamp extraction from Fathom
- **ContactExtractor** — NLP contact mention detection
- **SmartChunker** — Context-aware text chunking (256-512 token windows)
- **Deduplicator** — Exact ID + fuzzy (amount + date + payee) matching

### Embedding (4 files)
- **EmbeddingProvider** — Protocol: `embed(_ text:) → [Float]`
- **NLEmbedder** — 512-dim via NaturalLanguage framework
- **QwenClient** — 4096-dim via HTTP API to localhost:8081
- **CoreMLEmbedder** — 4096-dim CoreML (currently a stub)

See [embeddings.md](embeddings.md) for deep dive.

### Search (3 files)
- **FTSIndex** — Full-text BM25 search with temporal filters
- **QueryEngine** — Orchestrates FTS + semantic + result enrichment
- **HybridRanker** — RRF fusion (FTS 0.4 + semantic 0.6 weight)

### Intelligence (4 files)
- **FreedomTracker** — Weekly non-W2 income vs $6,058 target; velocity percentage
- **RelationshipScorer** — Contact depth scoring across email/Slack/meetings
- **ActivityDigest** — Weekly summaries (PAI integration ready)
- **AnomalyDetector** — Unusual transaction/contact patterns

### Models (13 files)
All `Codable` structs with `Sendable` compliance:
- Content: `Document`, `EmailChunk`, `SlackChunk`, `TranscriptChunk`
- Finance: `FinancialTransaction`, `BalanceSnapshot`, `Transaction`, `MonthlySummary`
- People: `Contact`, `Company`, `Meeting`, `MeetingParticipant`
- System: `SearchResult`, `VectorKeyMap`, `SyncState`, `WidgetSnapshot`

### Platform/Utilities (5 files)
- **KeychainManager** — SecItem with biometric auth
- **iCloudManager** — CKSyncEngine for private database
- **Categorizer** — Transaction category assignment
- **MerchantMap** — Payee normalization
- **SpotlightIndexer** — macOS Spotlight integration
- **DesignTokens** — Design system constants

---

## CLI Commands

```bash
ei-cli sync --all           # Sync all data sources
ei-cli sync --finance       # SimpleFin + QBO only
ei-cli sync --files         # VRAM filesystem scanning
ei-cli sync --slack         # Slack exports
ei-cli sync --meetings      # Meeting transcripts (Fathom)
ei-cli sync --emails        # Email JSON files
ei-cli search "query"       # Hybrid search (FTS + semantic)
ei-cli search --json "q"    # JSON output (for PAI integration)
ei-cli search --fts-only    # Skip semantic, FTS only
ei-cli search --sources email,slack  # Filter by source type
ei-cli search --year 2026 --month 3  # Temporal filter
ei-cli status               # Health check + database stats
ei-cli migrate --from-postgres        # Full data migration
ei-cli migrate --with-vectors         # Include vector migration
ei-cli migrate --vectors-only         # Vectors only (data already migrated)
```

**Default subcommand:** `status`

**Database path:** `~/Library/Application Support/com.hackervalley.eddingsindex/eddings.sqlite` (configurable with `--db-path`)

---

## SwiftUI App

### macOS — 3-Column NavigationSplitView

```
┌─────────┬────────────────┬──────────────────────────┐
│ Sidebar │   Content      │      Detail              │
│         │                │                          │
│ Search  │  Results List  │  Full record view        │
│ Freedom │  Meeting List  │  with source provenance  │
│ Meetings│  Contact List  │  and metadata             │
│ People  │  Financial     │                          │
│ Settings│  Dashboard     │                          │
│         │                │                          │
└─────────┴────────────────┴──────────────────────────┘
  240px       380px             flexible
```

### iOS — TabView

Tab-based navigation with safe area handling. Same views adapted for mobile layout (393px max width).

### Key Views

| View | Section | Purpose |
|------|---------|---------|
| SearchView | Search | Query input with source filters (email, Slack, meeting, file, finance), results list |
| FreedomDashboard | Freedom | Velocity gauge, weekly target ($6,058), net worth, projection (Nov 2027), stats grid |
| MeetingList | Meetings | Timeline with duration, participants, internal flag |
| ContactList | People | Relationships sorted by depth/recent/fading/companies |
| SettingsView | Settings | App configuration |

### EddingsEngine (Observable State Container)

The main app state container managing:
- `searchResults`, `searchQuery`, `selectedSection`, `isSearching`
- Initializes: `DatabaseManager`, `QueryEngine`, `VectorIndex`
- Executes async search with error recovery

---

## WidgetKit Extension

| Widget | Sizes | Data Source |
|--------|-------|-------------|
| FreedomVelocityWidget | small, medium | `widgetSnapshots.weeklyAmount`, `weeklyTarget`, `velocityPercent` |
| NetWorthWidget | small | `widgetSnapshots.netWorth`, `dailyChange` |

- Reads from App Group shared SQLite: `group.com.hackervalley.eddingsindex`
- 6-hour refresh interval
- Dark gradient backgrounds (amber/emerald tinted)
- No USearch loading (30MB widget RAM limit)

---

## Launch Agent

**File:** `com.vram.eddings-index.plist`

| Setting | Value |
|---------|-------|
| Label | `com.vram.eddings-index` |
| Command | `.build/release/ei-cli sync --all` |
| Interval | 43,200 seconds (12 hours) |
| RunAtLoad | true |
| Logs | `~/Library/Logs/vram/reality/sync.log` + `error.log` |

---

## Identifiers

| Identifier | Value |
|------------|-------|
| Package | `TheEddingsIndex` |
| Bundle ID | `com.hackervalley.eddingsindex` |
| App Group | `group.com.hackervalley.eddingsindex` |
| iCloud Container | `iCloud.com.hackervalley.eddingsindex` |
| Keychain Service | `com.hackervalley.eddingsindex` |
| Launch Agent | `com.vram.eddings-index` |
| CLI binary | `ei-cli` |
| Signing | Developer ID Application: HACKER VALLEY MEDIA, LLC (TPWBZD35WW) |

---

## Design System

See `mockups/design-tokens.json` for machine-readable tokens and `mockups/brand-guide.html` for the full brand guide.

### Color Semantics

| Color | Hex | Role |
|-------|-----|------|
| Gold | `#e8a849` | Human warmth, freedom, primary accent |
| Indigo | `#7c8cf5` | AI intelligence, PAI insights |
| Emerald | `#3dd68c` | Growth, positive, income, sync |
| Rose | `#f472b6` | Attention, debt, fading connections |
| Violet | `#a78bfa` | Meetings, creativity, connection |
| Blue | `#60a5fa` | Information, W-2, transcripts |

### Source Identity

| Source | Color | SF Symbol |
|--------|-------|-----------|
| Email | Gold | `envelope.fill` |
| Slack | Indigo | `bubble.left.fill` |
| Meeting | Violet | `video.fill` |
| Transcript | Blue | `text.quote` |
| File | Emerald | `doc.fill` |
| Finance | Rose | `dollarsign.circle.fill` |

### Design Principles

1. **Stories, Not Records** — Search results are timelines, not database rows
2. **Warm Dark** — Subtle amber-tinted darks, no pure black
3. **Density With Breathing Room** — High info density balanced with whitespace
4. **AI Present, Not Dominant** — PAI insights in small contextual cards, indigo dot = "PAI contributed this"
5. **Source-Aware Everything** — Every piece of data carries color + icon + label provenance
6. **Purposeful Motion** — 180ms for interactions, 300ms for transitions
