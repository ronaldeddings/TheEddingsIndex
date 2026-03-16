# TheEddingsIndex

Swift multiplatform personal intelligence platform (macOS + iOS).

## Build & Test

```bash
# Build (debug)
swift build

# Build (release — for launch agent)
swift build -c release

# Run tests
swift test

# Run CLI
.build/debug/ei-cli <command>

# CLI commands
ei-cli sync --all          # Sync all data sources
ei-cli sync --finance      # SimpleFin + QBO only
ei-cli search --json "q"   # Search (JSON output for PAI)
ei-cli status              # Health check + stats
ei-cli migrate --from-postgres  # One-time data import
```

## Project Structure

- `Sources/EddingsKit/` — Shared library (macOS + iOS). All models, search, sync, storage.
- `Sources/EddingsCLI/` — macOS CLI tool (launch agent). Uses ArgumentParser.
- `Sources/EddingsApp/` — SwiftUI app targets defined in Xcode project (not Package.swift).
- `Sources/EddingsWidgets/` — WidgetKit extension, also in Xcode project.
- `Tests/EddingsKitTests/` — Swift Testing framework.
- `prd/` — PRD-01 (finance), PRD-02 (full platform), PROPOSAL.
- `mockups/` — Brand guide, design tokens, UI prototypes (HTML/CSS/JS).
- `com.vram.eddings-index.plist` — Launch agent definition.

## Tech Stack

- **Language:** Swift 6 (strict concurrency)
- **Platforms:** macOS 15+, iOS 18+
- **Storage:** SQLite via GRDB.swift (FTS5 for full-text search, BM25 ranking)
- **Vectors:** USearch HNSW (512-dim on iOS via mmap, 4096-dim on macOS)
- **Sync:** CKSyncEngine (iCloud private database)
- **Embeddings:** NaturalLanguage (512-dim, both platforms) + CoreML Qwen3 (4096-dim, macOS only)
- **UI:** SwiftUI with NavigationSplitView (macOS) / TabView (iOS)
- **Auth:** Keychain via SecItem APIs
- **Dependencies:** GRDB.swift, USearch, swift-argument-parser (3 total)

## Code Conventions

- Swift 6 strict concurrency — use actors for mutable shared state, Sendable for all models
- All models are Codable structs (not classes) for Sendable compliance
- Use `DatabasePool` (not `DatabaseQueue`) for concurrent read/write access
- FTS5 BM25 column weights are applied at QUERY time via `bm25(table, W1, W2, ...)`, NOT at schema definition time. GRDB has no `columnWeight()` API.
- USearch is wrapped in an `actor VectorIndex` — mutations serialized, searches concurrent
- On iOS: use `index.view()` (mmap) to load USearch — never `index.load()` (too much RAM)
- USearch save uses generation-swapping (new file → new view → swap ref → old deallocates). Never use `FileManager.replaceItemAt()` with an active mmap view (SIGBUS crash).
- Pending embeddings tracked in SQLite `pendingEmbeddings` table for crash recovery
- NLEmbedding: always detect language with `NLLanguageRecognizer` before embedding. Never hardcode `.english`.

## Existing Tools — DO NOT MODIFY

The following existing tools write to VRAM disk. TheEddingsIndex READS from their output. Never modify these:

- TypeScript search engine (`/Volumes/VRAM/00-09_System/01_Tools/search_engine/`)
- QBO dump agent (`/Volumes/VRAM/00-09_System/01_Tools/qbo-dump/`)
- Email sync, Slack sync, Fathom sync, Mozilla sync (all launch agents)
- PostgreSQL at localhost:4432 (continues running)
- Qwen3-VL embedding server at port 8081 (continues running)

TheEddingsIndex is ADDITIVE. Both systems coexist.

## VRAM Paths (Read From)

| Data | Path |
|------|------|
| Finance (personal) | `/Volumes/VRAM/20-29_Finance/20_Banking/` |
| Finance (HVM/QBO) | `/Volumes/VRAM/10-19_Work/10_Hacker_Valley_Media/10.06_finance/QuickBooksOnline/` |
| Emails (JSON) | `/Volumes/VRAM/10-19_Work/14_Communications/14.01b_emails_json/` |
| Slack exports | `/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack/` |
| Meeting transcripts | `/Volumes/VRAM/10-19_Work/13_Meetings/13.01_transcripts/` |
| Meeting recordings | `/Volumes/VRAM/10-19_Work/13_Meetings/13.02_recordings/` (665GB — macOS only) |
| Apple dev docs | `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/` |

## iCloud Sync Rules

- Sync: contacts, companies, financial transactions, snapshots, summaries, merchant map, meeting metadata, transcript text
- Do NOT sync: meeting MP4s, raw email JSON archives, 4096-dim embeddings, VRAM filesystem
- USearch index is NEVER synced as a binary file. Embedding vectors sync as CKRecord Data blobs. USearch index rebuilt locally on each device.
- CKSyncEngine state serialization MUST be persisted to disk on every `.stateUpdate` event
- Handle `.accountChange` event — flush pending writes before accepting state reset
- Field-level conflict resolution: use `categoryModifiedAt` for financial transactions (prevents bulk import from overwriting manual iOS categorizations)

## Widget / App Extension Rules

- Widget extensions have 30MB RAM limit — NEVER load USearch index in widgets
- Database MUST live in App Group shared container: `group.com.hackervalley.eddingsindex`
- Use `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` for DB path
- Pre-calculate widget data into `widgetSnapshots` SQLite table
- GRDB must use WAL mode for concurrent reader (widget) + writer (app)

## iOS Background Sync

- `BGAppRefreshTask` (30 sec): quick check for new transactions only
- `BGProcessingTask` (minutes, requires idle + power): heavy sync (IMAP, indexing)
- Sync engine is checkpoint-based — commit every 100 records. iOS can kill background tasks at any time.
- Register in Info.plist: `com.hackervalley.eddingsindex.refresh`, `com.hackervalley.eddingsindex.sync`

## Security

- SimpleFin Access URL stored in Keychain with `kSecAttrAccessibleAfterFirstUnlock` (for background sync)
- Interactive credentials use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Bind Keychain items to biometrics via `SecAccessControlCreateWithFlags(.userPresence)`
- `NSFaceIDUsageDescription` MUST be in Info.plist
- All financial data at rest on encrypted APFS. No additional encryption needed.
- Never interpolate user data into SQL — GRDB uses parameterized queries by default.

## Signing

- Developer ID Application: HACKER VALLEY MEDIA, LLC (TPWBZD35WW)
- Always sign with this cert. Always create .app bundle at minimum.

## Identifiers

| Identifier | Value |
|------------|-------|
| Package name | `TheEddingsIndex` |
| Bundle ID | `com.hackervalley.eddingsindex` |
| App Group | `group.com.hackervalley.eddingsindex` |
| iCloud Container | `iCloud.com.hackervalley.eddingsindex` |
| Keychain Service | `com.hackervalley.eddingsindex` |
| Launch Agent | `com.vram.eddings-index` |
| CLI binary | `ei-cli` |
| Shorthand | `EI` |

## Design System

The brand guide and design tokens define the visual language. Follow these when building UI.

- **Brand Guide:** `mockups/brand-guide.html` — Origin story, 5 brand pillars, 6 design principles, voice & tone, color psychology, typography scale, source identity system, iconography, the Freedom Narrative, platform personality
- **Design Tokens:** `mockups/design-tokens.json` — Machine-readable tokens for Swift/SwiftUI (colors, typography, spacing, radius, shadows, motion, layout, components)
- **UI Mockups:** `mockups/ei-app.html` (macOS 3-column), `ei-freedom.html` (Freedom Dashboard), `ei-people.html` (Relationships), `ei-mobile.html` (iOS)

### Design Principles (Summary)

1. **Stories, Not Records** — Search results are timelines. Financial data tells a narrative. Contacts show relationship arcs.
2. **Warm Dark** — Subtle amber-tinted darks. No pure black. Feels like a well-lit study, not a terminal.
3. **Density With Breathing Room** — High info density balanced with generous whitespace.
4. **AI Present, Not Dominant** — PAI insights in small contextual cards, not chatbot takeovers. Indigo dot = "PAI contributed this."
5. **Source-Aware Everything** — Every piece of data carries color + icon + label provenance.
6. **Purposeful Motion** — 180ms for interactions. 300ms for transitions. Nothing moves without reason.

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

| Source | Color | Icon | SF Symbol |
|--------|-------|------|-----------|
| Email | Gold | ✉ | `envelope.fill` |
| Slack | Indigo | ◈ | `bubble.left.fill` |
| Meeting | Violet | ◉ | `video.fill` |
| Transcript | Blue | ▶ | `text.quote` |
| File | Emerald | ▤ | `doc.fill` |
| Finance | Rose | $ | `dollarsign.circle.fill` |

### Voice Rules

- Direct, not hedging. "You need $3,211 more per week" not "Based on analysis..."
- Human-scale. "15 years of conversations with 2,847 people" not "282,341 email records"
- Actionable. "3 deals need attention" not "Pipeline contains 3 opportunities"
- Warm. "Good evening, Ron" not "Dashboard loaded"

## Key PRD References

- PRD-01 (Finance Pipeline): `prd/PRD-01-vram-finance-pipeline.md`
- PRD-02 (Full Platform): `prd/PRD-02-reality-search-engine.md`
- Proposal: `prd/PROPOSAL-reality-search-engine.md`

@/Users/ronaldeddings/.claude/RTK.md
