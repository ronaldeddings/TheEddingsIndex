# Architecture Documentation

Comprehensive documentation of TheEddingsIndex — a Swift multiplatform personal intelligence platform.

## Documents

| Document | Description |
|----------|-------------|
| [overview.md](overview.md) | High-level architecture, technology stack, targets, subsystems (57+ files), CLI commands (including `watch`), SwiftUI app structure (ViewModels, Components), build pipeline, design system |
| [data-flows.md](data-flows.md) | How data moves through the system — batch sync + real-time FSEvents watcher, EmbeddingPipeline, search pipeline, data policy (Oct 2025 cutoff), iCloud sync, launch agent |
| [storage.md](storage.md) | SQLite schema (all tables, columns, indices, FTS5), migrations v1–v3, GRDB patterns, USearch configuration, iCloud CKSyncEngine |
| [embeddings.md](embeddings.md) | Dual-embedding strategy — NLEmbedder (512-dim, revision tracking), QwenClient (4096-dim), EmbeddingPipeline (batch + real-time), VectorIndex actor, hybrid search with RRF |
| [gaps.md](gaps.md) | Known gaps — critical (CoreML stub), moderate (CalDAV stub, Double precision, test coverage), minor (Xcode project, Spotlight). Resolved gaps tracker for PRD-05/06/07 |
| [apple-api-compliance.md](apple-api-compliance.md) | Cross-reference against Apple developer docs — NaturalLanguage, CloudKit CKSyncEngine, BackgroundTasks, WidgetKit, Security/Keychain, CoreServices/FSEvents. 12 of 17 original issues resolved |

## Quick Reference

**Build:** `swift build` (debug) or `swift build -c release` (production)
**Test:** `swift test`
**CLI:** `.build/debug/ei-cli <command>`
**Dependencies:** GRDB.swift, USearch, swift-argument-parser (3 total)
**Platforms:** macOS 15+, iOS 18+
**Language:** Swift 6 (strict concurrency)

## Architecture at a Glance

```
┌──────────────────────────────────────────────┐
│              External Sources                  │
│  SimpleFin · QBO · VRAM · Slack · Email · Fathom · Qwen3 · FSEvents  │
└───────────────────┬──────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────┐
│            EddingsKit (Shared Library)        │
│                                               │
│  Sync → Normalize → Deduplicate → Store       │
│  Embed → NLEmbedder(512) + Qwen(4096)        │
│  Search → FTS5 + Semantic → HybridRanker      │
│  Watch → FSEvents → indexSingleFile → embed   │
│  Intelligence → Freedom · Relationships       │
└───────────────────┬──────────────────────────┘
                    │
          ┌─────────┼─────────┐
          │         │         │
          ▼         ▼         ▼
      ei-cli    SwiftUI    Widgets
     (macOS)   (macOS+iOS)  (iOS)
```
