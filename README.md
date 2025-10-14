# EchoAutocomplete

A modular Swift engine for building database-aware SQL autocompletion.

## Features

- Alias-aware column suggestions (`SELECT e.` → `e.id`, `e.name`, …).
- Optional table alias shortcuts (insert `orders o` when configured).
- Dialect-specific keyword casing and context heuristics.
- Metadata-driven table, view, materialized view, function, and procedure suggestions.
- Pure Swift implementation that can be embedded in AppKit, UIKit, or CLI tools.

## Package Structure

- `EchoAutocomplete`: core types, metadata protocols, and the completion engine.
- `Internal/`: parsing and suggestion builders kept separate for easier maintenance.
- `Tests/EchoAutocompleteTests`: alias detection coverage; extend with more dialect fixtures as needed.

## Usage

1. Add the package to your project (Xcode > File > Add Packages… and point to this repo once it's pushed).
2. Adopt `SQLMetadataProvider` to expose schemas, objects, and columns from your app's cache or API.
3. Construct `SQLCompletionRequest` whenever you need completions and call `SQLCompletionEngine().completions(for:)`.
4. Render `SQLCompletionSuggestion` results however you like (popover, menu, table view, etc.).

## Running Tests

```bash
swift test
```

## Next Steps

- Flesh out dialect-specific rule sets (identifier quoting, default schema resolution).
- Expand the test suite with more fixtures (quoted identifiers, subqueries, multi-schema workspaces).
- Wire the package into the Echo editor and surface user preferences (alias shortcuts, keyword casing) through the UI.
