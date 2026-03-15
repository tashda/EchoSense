# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
swift build          # Build the package
swift test           # Run all 230 tests
swift test --filter EchoSenseTests.FuzzyMatcherTests   # Run a single test suite
swift test --filter EchoSenseTests.FuzzyMatcherTests/testExactMatch  # Run a single test
```

CI runs on macOS 15 / Xcode 26 and includes a strict concurrency check (`-Xswiftc -strict-concurrency=complete`). All code must pass this check. Package.swift enables Swift 6 language mode explicitly.

## Architecture

**Request flow:** `SQLAutoCompletionEngine` (public facade) → `SQLCompletionEngine` (orchestrator) → `SQLContextParser` + `SuggestionBuilder`

- **SQLAutoCompletionEngine** — Public API facade. Split across 3 files: core (`SQLAutoCompletionEngine.swift`), ranking (`+Ranking.swift`), mapping/filtering (`+Mapping.swift`).
- **SQLContextParser** — Analyzes SQL text at caret position to produce `SQLContext` (clause, token, tables in scope, CTEs, derived table columns). Uses `ClauseStateMachine` for clause inference, `SQLTokenizer` for lexical analysis. Derived table extraction in `+DerivedTables.swift`.
- **SuggestionBuilder** — Dispatches to 9 independent providers, each in its own file: `ColumnSuggestionProvider`, `TableSuggestionProvider` (includes Schema and Join), `KeywordSuggestionProvider`, `MiscSuggestionProviders` (Function, Parameter, Snippet).
- **SQLMetadataCatalog** — Indexes `EchoSenseDatabaseStructure` for fast lookups. All keys normalized to lowercase.
- **SQLAutoCompletionHistoryStore** — Tracks selection frequency/recency. Boosts applied to all suggestions (live and history) during ranking.

## Key Conventions

- **Swift 6.2, Swift 6 language mode.** All public types must be `Sendable`. Package types are `nonisolated` by default — no `@MainActor`. Existing `@unchecked Sendable` on `PrefixTrie` (NSLock) and `HistoryStore` (DispatchQueue) is justified — see comments in those files.
- **Zero external dependencies.** Only Foundation imports allowed.
- **Synchronous API.** The completion engine is synchronous for immediate UI feedback — no async/await.
- **File size limit: 500 lines.** Split files using the `TypeName+Concern.swift` extension pattern. Data-only files (e.g., `SQLReservedKeywords.swift`) may exceed this.
- **Naming:** Public types use `SQL*` or `EchoSense*` prefix. Providers use `*SuggestionProvider` suffix. No vague names (`Helper`, `Manager`, `Handler`, etc.). Protocols are nouns/adjectives, not suffixed with `Protocol` (e.g., `SQLCompletionProviding`).
- **Testing:** Swift Testing framework (`@Test`, `#expect`). Use `@testable import EchoSense`.
- **Four SQL dialects:** PostgreSQL, MySQL, SQLite, Microsoft SQL Server. Dialect-specific keywords, functions, quoting, and snippets handled via strategy pattern.
- **FuzzyMatcher** is integrated across all providers for filtering — use `matchesQuery()` rather than exact string matching.
- **History ranking:** `historyStore.weight()` is applied to ALL suggestions during ranking (50% boost for live, 100% for history-sourced), making frequently-picked items float to top.
