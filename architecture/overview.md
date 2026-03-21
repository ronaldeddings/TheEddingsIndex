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

## EddingsKit Subsystems (57+ files)

The shared library is organized into 7 subsystems:

### Storage (5 files)
- **DatabaseManager** — GRDB `DatabasePool`, WAL mode, schema migrations (v1–v3), `DataPolicy.cutoffDate` (Oct 1, 2025)
- **DataAccess** — `Sendable` struct for typed read queries: contacts, meetings, interaction timelines, financial aggregations, search result resolution
- **FTSIndex** — FTS5 BM25 search across 5 content tables with column weighting
- **VectorIndex** — USearch HNSW actor (thread-safe mutations, concurrent reads)
- **StateManager** — Sync checkpoint persistence

### Sync/Import (13 files)
- **SimpleFinClient** — Banking API integration (OAuth)
- **QBOReader** — QuickBooks Online CSV deposits
- **IMAPClient** — Email JSON file parsing from VRAM; `indexSingleFile(path:)` for real-time ingestion
- **SlackClient** — Slack export parsing; `indexSingleFile(path:)` for real-time ingestion
- **FathomClient** — Meeting transcript sync; `indexSingleFile(path:)` for real-time ingestion
- **FileScanner** — Recursive VRAM filesystem scanning; `indexSingleFile(path:)` for real-time ingestion
- **FileWatcher** — FSEvents-based file watcher actor (`CoreServices.FSEventStreamCreate`); monitors 10 VRAM paths with 2-second coalescing; routes events to sync clients + `EmbeddingPipeline`
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

### Embedding (5 files)
- **EmbeddingProvider** — Protocol: `embed(_ text:) → [Float]`
- **NLEmbedder** — 512-dim via NaturalLanguage framework; revision tracking via `currentSentenceEmbeddingRevision(for:)`
- **QwenClient** — 4096-dim via HTTP API to localhost:8081
- **CoreMLEmbedder** — 4096-dim CoreML (currently a stub)
- **EmbeddingPipeline** — Actor orchestrating post-sync embedding generation. Processes 5 content tables (emailChunks, slackChunks, transcriptChunks, documents, financialTransactions). Supports batch `run()` for catchup and `embedRecord(table:id:)` for real-time single-record embedding from FileWatcher. Writes failures to `pendingEmbeddings` for retry.

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
ei-cli watch                # Start FSEvents watcher daemon (primary mode — runs catchup sync then watches VRAM)
ei-cli sync --all           # Sync all data sources + run embedding pipeline
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

### ViewModels (5 files)

All `@Observable @MainActor`, wired to live data via `DataAccess` and GRDB queries:

| ViewModel | Purpose |
|-----------|---------|
| `PeopleViewModel` | Contacts by depth (Inner Circle ≥100, Growing 10–99, Peripheral <10), relationship scoring, interaction timelines |
| `SearchViewModel` | Query debouncing (300ms), NLEmbedder 512-dim embedding, source filtering |
| `FreedomViewModel` | Velocity calculation, net worth history, spending/income categorization, period selection |
| `MeetingsViewModel` | Meeting grouping by date buckets (today, this week, earlier), participants, transcript excerpts |
| `SettingsViewModel` | Sync source status, table counts, database size, embedding counts |

### EddingsEngine (Observable State Container)

The main app state container managing:
- All dependencies: `DatabaseManager`, `QueryEngine`, `VectorIndex`, `DataAccess`, `StateManager`
- Instantiates and provides all 5 ViewModels as environment objects
- Bootstraps on launch: loads freedom → people → meetings → settings sequentially
- macOS: 3-column `NavigationSplitView` via `AppSidebar` with `@SceneStorage` for persistent section selection
- iOS: `TabView` via `AppTabBar`

### Reusable Components (12 files)

`Sources/EddingsApp/Components/`:
`CardContainer`, `CategoryBar`, `DepthBadge`, `FreedomGauge`, `InsightCard`, `InteractionTimeline`, `MiniSparkline`, `PillToggle`, `SourceIcon`, `StatCard`, `StatChip`, `ContentListView`

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
| Command | `/Volumes/VRAM/.../ei-cli watch` |
| KeepAlive | `true` (launchd restarts on crash) |
| RunAtLoad | `true` |
| Logs | `~/Library/Logs/vram/reality/sync.log` + `error.log` |

The launch agent runs `ei-cli watch` as a continuous daemon. On startup, it performs a full catchup sync (all 5 pipelines + embedding pipeline), then starts the FSEvents file watcher monitoring 10 VRAM paths. `KeepAlive: true` replaces the previous `StartInterval: 43200` (12-hour polling) model.

## Build & Distribution

**File:** `scripts/build.sh`

Complete macOS build pipeline: release/debug modes, signing with Developer ID Application cert (HACKER VALLEY MEDIA, LLC), DMG creation with versioned naming, optional notarization via `xcrun`. Verifies linkage (checks for external dylibs) and applies hardened runtime entitlements.

**Entitlements:** `Sources/EddingsApp/EddingsIndex.entitlements` — app sandbox, network, file access
**Info.plist:** `Sources/EddingsApp/AppInfo.plist`

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
