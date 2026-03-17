# Architecture Documentation

Comprehensive documentation of TheEddingsIndex — a Swift multiplatform personal intelligence platform.

## Documents

| Document | Description |
|----------|-------------|
| [overview.md](overview.md) | High-level architecture, technology stack, targets, subsystems, CLI commands, SwiftUI app structure, design system |
| [data-flows.md](data-flows.md) | How data moves through the system — sync pipelines, search pipeline, migration flow, iCloud sync, launch agent |
| [storage.md](storage.md) | SQLite schema (all tables, columns, indices, FTS5), GRDB patterns, USearch configuration, iCloud CKSyncEngine |
| [embeddings.md](embeddings.md) | Deep dive on the dual-embedding strategy — NLEmbedder (512-dim), QwenClient (4096-dim), CoreMLEmbedder (stub), VectorIndex actor, hybrid search with RRF, migration from PostgreSQL |
| [gaps.md](gaps.md) | Known gaps between planned and actual implementation — critical (no live embeddings, hardcoded UI), moderate (iOS background stubs), and minor issues |
| [apple-api-compliance.md](apple-api-compliance.md) | Cross-reference against Apple developer docs — NaturalLanguage, CloudKit CKSyncEngine, BackgroundTasks, WidgetKit, Security/Keychain, CoreML |

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
│  SimpleFin · QBO · VRAM · Slack · Email · Fathom · Qwen3  │
└───────────────────┬──────────────────────────┘
                    │
                    ▼
┌──────────────────────────────────────────────┐
│            EddingsKit (Shared Library)        │
│                                               │
│  Sync → Normalize → Deduplicate → Store       │
│  Search → FTS5 + Semantic → HybridRanker      │
│  Intelligence → Freedom · Relationships       │
└───────────────────┬──────────────────────────┘
                    │
          ┌─────────┼─────────┐
          │         │         │
          ▼         ▼         ▼
      ei-cli    SwiftUI    Widgets
     (macOS)   (macOS+iOS)  (iOS)
```
