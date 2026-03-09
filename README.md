# EchoSense

SQL autocomplete engine for the [Echo](https://github.com/tashda/Echo) macOS database client. Provides intelligent, context-aware SQL completion across PostgreSQL, MySQL, SQLite, and Microsoft SQL Server.

## Features

- **Context-aware suggestions** — Knows whether you're in a SELECT, FROM, WHERE, JOIN, or other clause and suggests accordingly
- **Schema-aware** — Completes table names, column names, views, and functions from live database metadata
- **Foreign key joins** — Suggests JOIN conditions and targets based on foreign key relationships
- **Identifier quoting** — Automatically quotes reserved words, CamelCase identifiers (PostgreSQL), and special characters using dialect-correct delimiters
- **Parameter placeholders** — Suggests the next parameter (`$1`, `?`, `@p1`) based on dialect and existing parameters
- **Code snippets** — Dialect-specific snippets (CASE WHEN, COALESCE, JSON functions, etc.)
- **Star expansion** — Expands `SELECT *` into the full column list for the focus table
- **CTE support** — Parses WITH clause column definitions and offers them as completions
- **History tracking** — Records selections and boosts frequently-used completions
- **Multi-database** — Full support for PostgreSQL, MySQL, SQLite, and SQL Server dialects

## Requirements

- Swift 6.2+
- macOS 15+

## Installation

Add EchoSense as a Swift Package dependency:

```swift
dependencies: [
    .package(url: "https://github.com/tashda/EchoSense", branch: "dev")
]
```

## Usage

```swift
import EchoSense

// Create the engine
let engine = SQLAutoCompletionEngine()

// Provide database metadata
let context = SQLEditorCompletionContext(
    databaseType: .postgresql,
    selectedDatabase: "mydb",
    defaultSchema: "public",
    structure: databaseStructure  // EchoSenseDatabaseStructure from your driver
)
engine.updateContext(context)

// Get suggestions
let query = SQLAutoCompletionQuery(
    token: "us",
    prefix: "us",
    pathComponents: [],
    replacementRange: range,
    precedingKeyword: "from",
    precedingCharacter: nil,
    focusTable: nil,
    tablesInScope: [],
    clause: .from
)

let result = engine.suggestions(for: query, text: sqlText, caretLocation: caretPosition)
// result.sections contains grouped suggestions
```

## Architecture

```
EchoSense/
├── SQLAutoCompletionEngine.swift     — Public API facade
├── SQLAutoCompletionModels.swift     — Public types (queries, suggestions, sections)
├── SQLAutocompleteKit.swift          — Core protocol layer
├── SchemaMetadata.swift              — Database structure types
├── SQLAutoCompletionHistoryStore.swift — Selection history persistence
└── Internal/
    ├── SQLCompletionEngine.swift     — Completion pipeline orchestrator
    ├── SQLContextParser.swift        — SQL text parsing & clause inference
    ├── SQLTokenizer.swift            — Lexical analysis
    ├── SuggestionBuilder.swift       — Multi-provider suggestion generation
    ├── SQLParameterSuggester.swift   — Parameter placeholder suggestions
    ├── SQLSnippets.swift             — Dialect-specific code snippets
    └── Metadata/
        ├── SQLIdentifierQuoter.swift — Dialect-aware identifier quoting
        ├── SQLMetadataCatalog.swift  — Metadata indexing & lookup
        └── SQLReservedKeywords.swift — SQL reserved keyword database
```

## Testing

```bash
swift test
```

## License

Proprietary. Copyright Tashda Inc.
