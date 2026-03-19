# PRD-07: FSEvents File Watcher — Real-Time Data Ingestion

## Problem

TheEddingsIndex currently syncs via a 12-hour polling interval (`StartInterval: 43200` in the launch agent). This means:

- **New data takes up to 12 hours to become searchable.** An email arriving at 6:00 AM isn't indexed until the next sync window.
- **Every sync re-enumerates all files.** The FileScanner walks 7 VRAM areas recursively, the IMAPClient lists 30K+ email JSON files, and the SlackClient lists every channel directory — all to find the handful of files that changed.
- **Sync runs are expensive.** A full `sync --all` triggers the embedding pipeline across all tables, even when only 3 new files exist. The embedding pipeline then queries every table for unembedded records (`SELECT id FROM {table} WHERE id NOT IN (SELECT sourceId FROM vectorKeyMap WHERE sourceTable = ?)`), which is an O(n) scan against every record.
- **Concurrent syncs cause lock contention.** Multiple `ei-cli` processes (manual + launch agent) fight for SQLite write locks, causing `database is locked` errors and hung processes.

### Evidence

| Metric | Value | Source |
|--------|-------|--------|
| Files changed in last 7 days | 27 | `fd --changed-within 7d` across scan areas |
| Files changed in last 24 hours | 0 | Same scan |
| Total indexable files on VRAM | 1,877 | `fd -e md -e txt -e csv -e yml -e yaml -e toml` |
| Previous document rows in DB (Postgres migration artifacts) | 922,855 | `SELECT count(*) FROM documents` (before cleanup) |
| First observed sync duration | 16+ hours | PID 17113, 355 min CPU time, `sync --all` |
| Observed concurrent processes | 4 | `ps aux \| grep ei-cli` showed 4 fighting for locks |

## Solution

Replace the 12-hour polling launch agent with an FSEvents-based file watcher daemon that indexes files within seconds of creation or modification.

## Architecture

### Why FSEvents (not DispatchSource)

| | FSEvents (CoreServices) | DispatchSource |
|---|---|---|
| Watches directory trees | Yes — recursive, kernel-level | No — single file/directory per source |
| File-level events | Yes, via `kFSEventStreamCreateFlagFileEvents` (macOS 10.7+) | Limited to directory-level change detection |
| Coalescing | Built-in `latency` parameter for temporal coalescing | Manual implementation required |
| File descriptors | Zero — kernel-managed | One per watched path (would exhaust FDs across 1,877+ files) |
| API | `FSEventStreamCreate` → `FSEventStreamSetDispatchQueue` → `FSEventStreamStart` | `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)` |

**Decision: FSEvents.** Watching 10+ directory trees with thousands of files makes DispatchSource impractical (one FD per file). FSEvents watches entire hierarchies with zero file descriptors.

### Apple API Surface

From `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/coreservices/`:

```swift
// Create stream watching multiple paths with file-level events
func FSEventStreamCreate(
    _ allocator: CFAllocator?,
    _ callback: FSEventStreamCallback,
    _ context: UnsafeMutablePointer<FSEventStreamContext>?,
    _ pathsToWatch: CFArray,        // Array of directory paths
    _ sinceWhen: FSEventStreamEventId,  // kFSEventStreamEventIdSinceNow
    _ latency: CFTimeInterval,      // Coalescing window (seconds)
    _ flags: FSEventStreamCreateFlags
) -> FSEventStreamRef?

// Schedule on GCD queue (preferred over run loop)
func FSEventStreamSetDispatchQueue(
    _ streamRef: FSEventStreamRef,
    _ q: dispatch_queue_t?
)

// Start receiving events
func FSEventStreamStart(_ streamRef: FSEventStreamRef) -> Bool
```

**Key flags:**
- `kFSEventStreamCreateFlagFileEvents` — file-level notifications (not just directory)
- `kFSEventStreamCreateFlagNoDefer` — deliver events immediately (no initial latency wait)
- `kFSEventStreamCreateFlagIgnoreSelf` — ignore changes made by our own process

**Key event flags:**
- `kFSEventStreamEventFlagItemCreated` — new file
- `kFSEventStreamEventFlagItemModified` — file content changed
- `kFSEventStreamEventFlagItemRenamed` — file moved/renamed
- `kFSEventStreamEventFlagItemRemoved` — file deleted

### Watched Paths

| Path | Data Type | Current Sync Client |
|------|-----------|-------------------|
| `/Volumes/VRAM/10-19_Work/14_Communications/14.01b_emails_json/` | Email JSON | `IMAPClient` |
| `/Volumes/VRAM/10-19_Work/14_Communications/14.02_slack/` | Slack JSON | `SlackClient` |
| `/Volumes/VRAM/10-19_Work/13_Meetings/13.01_transcripts/` | Transcripts | `FathomClient` |
| `/Volumes/VRAM/10-19_Work/` | Documents | `FileScanner` |
| `/Volumes/VRAM/20-29_Finance/` | Documents | `FileScanner` |
| `/Volumes/VRAM/30-39_Personal/` | Documents | `FileScanner` |
| `/Volumes/VRAM/40-49_Family/` | Documents | `FileScanner` |
| `/Volumes/VRAM/50-59_Social/` | Documents | `FileScanner` |
| `/Volumes/VRAM/60-69_Growth/` | Documents | `FileScanner` |
| `/Volumes/VRAM/70-79_Lifestyle/` | Documents | `FileScanner` |

Total: 10 root paths → 1 FSEventStream.

## Implementation

### New Files

| File | Purpose |
|------|---------|
| `Sources/EddingsKit/Sync/FileWatcher.swift` | FSEvents stream wrapper actor |
| `Sources/EddingsCLI/Commands/WatchCommand.swift` | `ei-cli watch` daemon command |

### Modified Files

| File | Change |
|------|--------|
| `com.vram.eddings-index.plist` | Switch from `StartInterval` to `KeepAlive`, change command to `watch` |
| `Sources/EddingsKit/Sync/IMAPClient.swift` | Add `indexSingleFile(path:)` method |
| `Sources/EddingsKit/Sync/SlackClient.swift` | Add `indexSingleFile(path:)` method |
| `Sources/EddingsKit/Sync/FathomClient.swift` | Add `indexSingleFile(path:)` method |
| `Sources/EddingsKit/Sync/FileScanner.swift` | Add `indexSingleFile(path:)` method |
| `Sources/EddingsKit/Embedding/EmbeddingPipeline.swift` | Add `embedRecord(table:id:)` for single-record embedding |

### FileWatcher Actor

```swift
import CoreServices
import Foundation

public actor FileWatcher {
    private var stream: FSEventStreamRef?
    private let dbPool: DatabasePool
    private let watchPaths: [String]
    private let latency: CFTimeInterval
    private let handler: @Sendable ([FileEvent]) -> Void

    public struct FileEvent: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags
        var isCreated: Bool { flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 }
        var isModified: Bool { flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 }
        var isRemoved: Bool { flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 }
        var isRenamed: Bool { flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 }
    }
}
```

**Coalescing strategy:** `latency: 2.0` — FSEvents coalesces all events within a 2-second window into a single callback. This handles burst writes (e.g., email sync agent dumping 50 files) without triggering 50 separate index operations.

### Event Routing

When a file event arrives, route based on path prefix:

| Path contains | Route to | Action |
|--------------|----------|--------|
| `14.01b_emails_json/` + `.json` | `IMAPClient.indexSingleFile()` | Parse email, insert chunks |
| `14.02_slack/` + `.json` | `SlackClient.indexSingleFile()` | Parse messages, insert chunks |
| `13.01_transcripts/` + `.md`/`.txt` | `FathomClient.indexSingleFile()` | Parse transcript, insert chunks + meeting + contacts |
| `{scan_area}/` + indexable extension | `FileScanner.indexSingleFile()` | Read content, insert document |

After each file is indexed, call `EmbeddingPipeline.embedRecord(table:id:)` to generate vectors for just that record — no full-table scan needed.

### Single-File Embedding

Current `EmbeddingPipeline.run()` scans all tables for unembedded records. The watcher needs a targeted method:

```swift
public func embedRecord(table: String, id: Int64) async throws {
    // 1. Fetch text from table by ID
    // 2. NLEmbedder.embed(text) → 512-dim
    // 3. QwenClient.embed(text) → 4096-dim (macOS)
    // 4. Insert into VectorIndex + vectorKeyMap
}
```

This avoids the `SELECT id WHERE id NOT IN (...)` anti-join that currently scans all vectorKeyMap entries.

### Launch Agent Change

**Before:**
```xml
<key>ProgramArguments</key>
<array>
    <string>.build/release/ei-cli</string>
    <string>sync</string>
    <string>--all</string>
</array>
<key>StartInterval</key>
<integer>43200</integer>
<key>KeepAlive</key>
<false/>
```

**After:**
```xml
<key>ProgramArguments</key>
<array>
    <string>.build/release/ei-cli</string>
    <string>watch</string>
</array>
<key>KeepAlive</key>
<true/>
```

`KeepAlive: true` means launchd restarts the daemon if it crashes. No `StartInterval` — the process runs continuously.

### WatchCommand

```swift
struct WatchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Watch VRAM for changes and index in real-time"
    )

    func run() async throws {
        // 1. Initialize DB, embedding pipeline
        // 2. Run initial sync (catch up on anything missed while stopped)
        // 3. Start FSEvents watcher
        // 4. Block forever (RunLoop.main.run() or dispatchMain())
    }
}
```

The initial sync on startup catches any files created while the daemon was down (e.g., during a reboot). After that, FSEvents handles everything.

## Data Policy Enforcement

All existing cutoff rules apply:

- `DataPolicy.cutoffDate` (October 1, 2025) checked before inserting any record
- Email filename prefix skip (pre-Oct filenames rejected without reading)
- Slack date parsing from filename
- Transcript frontmatter date check
- Document `modifiedAt` check
- Only indexable extensions: `md`, `txt`, `csv`, `yml`, `yaml`, `toml`
- File size < 1MB

## VRAM Mount Handling

VRAM is an external volume. The watcher must handle:

1. **VRAM unmounted** — FSEvents delivers `kFSEventStreamEventFlagRootChanged` or `kFSEventStreamEventFlagMount`/`Unmount`. Log warning, pause indexing.
2. **VRAM remounted** — Detect mount event, run a quick sync to catch files created while unmounted, resume watching.
3. **Startup without VRAM** — Log error, retry with exponential backoff until VRAM appears at `/Volumes/VRAM`.

## Concurrency Safety

- `FileWatcher` is an actor — all state mutations serialized
- FSEvents callback dispatches to a dedicated serial queue
- Database writes use GRDB `DatabasePool` (WAL mode, concurrent reads)
- Single `ei-cli watch` process enforced by launchd (`KeepAlive` without multiple instances)
- `sync --all` remains available for manual catchup but should check for running watcher via PID file to avoid lock contention

## Performance Expectations

| Scenario | Current (polling) | After (watcher) |
|----------|-------------------|-----------------|
| New email → searchable | Up to 12 hours | ~3 seconds |
| New transcript → searchable | Up to 12 hours | ~3 seconds |
| Idle CPU usage | 0% (between syncs) | ~0% (FSEvents is kernel-managed) |
| Sync CPU spike | High (re-enumerates everything) | None (only processes changed files) |
| DB lock contention risk | High (overlapping syncs) | Low (single daemon process) |

## Out of Scope

- **SimpleFin/QBO finance sync** — API-driven, not file-driven. Keep on a separate timer (e.g., every 4 hours) or trigger manually.
- **iCloud sync** — CKSyncEngine handles its own push notifications.
- **iOS background tasks** — iOS has no FSEvents; continues using `BGAppRefreshTask`/`BGProcessingTask`.
- **Embedding model hot-reload** — If Qwen server is down, queue failed embeddings in `pendingEmbeddings` for retry.

## Test Plan

1. **Unit: FileWatcher event routing** — mock FSEvents callback, verify correct sync client is called for each path pattern
2. **Unit: Single-file indexing** — call `indexSingleFile()` on each client, verify DB insertion
3. **Unit: Single-record embedding** — call `embedRecord()`, verify vectorKeyMap entry
4. **Integration: End-to-end latency** — create a file in VRAM, measure time until searchable via `ei-cli search`
5. **Integration: VRAM unmount/remount** — eject VRAM, verify graceful pause, remount, verify catchup sync
6. **Integration: Burst writes** — dump 100 email JSONs in 1 second, verify coalescing produces reasonable batch count
7. **Regression: DataPolicy cutoff** — create a file with pre-Oct-2025 date, verify it's rejected
8. **Regression: `sync --all` still works** — manual sync runs clean alongside watcher daemon
