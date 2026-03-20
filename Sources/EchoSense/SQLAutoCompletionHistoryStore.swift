import Foundation
import os

/// Tracks user selection history with frequency/recency scoring.
///
/// Thread-safety: Uses `OSAllocatedUnfairLock` for synchronous mutual exclusion.
/// This avoids the cooperative-thread-pool deadlock that occurs with `DispatchQueue`
/// reader-writer patterns under Swift Testing's parallel execution.
public final class SQLAutoCompletionHistoryStore: Sendable {

    struct HistoryEntry: Sendable {
        var suggestion: SQLAutoCompletionSuggestion
        var lastUsed: Date
        var usageCount: Int
    }

    public static let shared = SQLAutoCompletionHistoryStore()

    private struct State: Sendable {
        var storage: [String: [HistoryEntry]] = [:]
        var pendingSave: Bool = false
    }

    private let state: OSAllocatedUnfairLock<State>
    private let maxEntriesPerContext = 20
    private let fileURL: URL
    private let saveDebounceInterval: TimeInterval = 1.0
    private let persistenceVersion = 1

    private init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory,
                                   in: .userDomainMask,
                                   appropriateFor: nil,
                                   create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseDir = support.appendingPathComponent("Echo", isDirectory: true)
        if !fm.fileExists(atPath: baseDir.path) {
            try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        let historyDir = baseDir.appendingPathComponent("AutocompleteHistory", isDirectory: true)
        if !fm.fileExists(atPath: historyDir.path) {
            try? fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
        }
        fileURL = historyDir.appendingPathComponent("history.json")

        // Load from disk
        var initialStorage: [String: [HistoryEntry]] = [:]
        if fm.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                if snapshot.version == 1 {
                    for (context, entries) in snapshot.entriesByContext {
                        let mapped = entries.map { $0.makeEntry() }
                        if !mapped.isEmpty {
                            initialStorage[context] = mapped
                        }
                    }
                }
            } catch {
                try? fm.removeItem(at: fileURL)
            }
        }

        state = OSAllocatedUnfairLock(initialState: State(storage: initialStorage))
    }

    public struct Snapshot: Codable, Sendable {
        var version: Int
        var entriesByContext: [String: [PersistedHistoryEntry]]
    }

    struct PersistedHistoryEntry: Codable, Sendable {
        var suggestion: SQLAutoCompletionSuggestion
        var lastUsed: Date
        var usageCount: Int

        init(entry: HistoryEntry) {
            var storedSuggestion = entry.suggestion
            storedSuggestion = storedSuggestion.withSource(.history)
            self.suggestion = storedSuggestion
            self.lastUsed = entry.lastUsed
            self.usageCount = entry.usageCount
        }

        func makeEntry() -> HistoryEntry {
            HistoryEntry(suggestion: suggestion.withSource(.history),
                  lastUsed: lastUsed,
                  usageCount: max(usageCount, 1))
        }
    }

    public func record(_ suggestion: SQLAutoCompletionSuggestion,
                       context: SQLEditorCompletionContext?) {
        guard shouldPersist(suggestion: suggestion) else { return }
        let key = contextKey(for: context)
        let now = Date()
        let maxEntries = maxEntriesPerContext

        let needsSave = state.withLock { state in
            var entries = state.storage[key] ?? []
            let storedSuggestion = suggestion.withSource(.history)
            if let index = entries.firstIndex(where: { $0.suggestion.id == suggestion.id }) {
                entries[index].suggestion = storedSuggestion
                entries[index].lastUsed = now
                entries[index].usageCount += 1
            } else {
                entries.append(HistoryEntry(suggestion: storedSuggestion,
                                     lastUsed: now,
                                     usageCount: 1))
            }
            if entries.count > maxEntries {
                entries.sort { $0.lastUsed > $1.lastUsed }
                entries = Array(entries.prefix(maxEntries))
            }
            state.storage[key] = entries

            if !state.pendingSave {
                state.pendingSave = true
                return true
            }
            return false
        }

        if needsSave {
            scheduleSave()
        }
    }

    public func suggestions(matching prefix: String,
                            context: SQLEditorCompletionContext?,
                            limit: Int) -> [SQLAutoCompletionSuggestion] {
        let key = contextKey(for: context)
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()

        return state.withLock { state in
            guard let entries = state.storage[key] else { return [] }
            let filtered = entries
                .sorted { lhs, rhs in
                    Self.score(for: lhs, now: now) > Self.score(for: rhs, now: now)
                }
                .compactMap { entry -> SQLAutoCompletionSuggestion? in
                    if normalizedPrefix.isEmpty {
                        return entry.suggestion.withSource(.history)
                    }
                    if FuzzyMatcher.match(pattern: normalizedPrefix, candidate: entry.suggestion.title) != nil {
                        return entry.suggestion.withSource(.history)
                    }
                    return nil
                }
            return Array(filtered.prefix(limit))
        }
    }

    public func weight(for suggestion: SQLAutoCompletionSuggestion,
                       context: SQLEditorCompletionContext?) -> Double {
        let key = contextKey(for: context)
        let now = Date()
        return state.withLock { state in
            guard let entries = state.storage[key],
                  let match = entries.first(where: { $0.suggestion.id == suggestion.id }) else { return 0 }
            return Self.score(for: match, now: now)
        }
    }

    private static func score(for entry: HistoryEntry, now: Date) -> Double {
        let recency = now.timeIntervalSince(entry.lastUsed)
        let recencyDecay = max(0, 3600 - recency) / 10.0
        let frequencyBoost = Double(entry.usageCount) * 45.0
        return frequencyBoost + recencyDecay
    }

    public func snapshot() -> Snapshot? {
        state.withLock { state in
            guard !state.storage.isEmpty else { return nil }
            return makeSnapshot(from: state.storage)
        }
    }

    public func importSnapshot(_ snapshot: Snapshot, merge: Bool = true) {
        guard snapshot.version == persistenceVersion else { return }
        let maxEntries = maxEntriesPerContext

        let needsSave = state.withLock { state in
            if !merge {
                state.storage.removeAll()
            }

            for (context, entries) in snapshot.entriesByContext {
                var existing = state.storage[context] ?? []
                for persisted in entries {
                    let entry = persisted.makeEntry()
                    if let index = existing.firstIndex(where: { $0.suggestion.id == entry.suggestion.id }) {
                        existing[index].suggestion = entry.suggestion
                        existing[index].lastUsed = max(existing[index].lastUsed, entry.lastUsed)
                        existing[index].usageCount = max(existing[index].usageCount, entry.usageCount)
                    } else {
                        existing.append(entry)
                    }
                }
                existing.sort { $0.lastUsed > $1.lastUsed }
                if existing.count > maxEntries {
                    existing = Array(existing.prefix(maxEntries))
                }
                state.storage[context] = existing
            }

            if !state.pendingSave {
                state.pendingSave = true
                return true
            }
            return false
        }

        if needsSave {
            scheduleSave()
        }
    }

    public func currentUsageBytes() -> UInt64 {
        let fm = FileManager.default
        if let attributes = try? fm.attributesOfItem(atPath: fileURL.path),
           let fileSize = attributes[.size] as? NSNumber {
            return fileSize.uint64Value
        }
        return 0
    }

    public func flush() {
        state.withLock { state in
            state.pendingSave = false
        }
        persistImmediately()
    }

    private func shouldPersist(suggestion: SQLAutoCompletionSuggestion) -> Bool {
        switch suggestion.kind {
        case .table, .view, .materializedView, .column, .function, .join, .snippet:
            return true
        default:
            return false
        }
    }

    private func contextKey(for context: SQLEditorCompletionContext?) -> String {
        guard let context else { return "global" }
        let database = context.selectedDatabase ?? "default"
        return "\(context.databaseType.rawValue)|\(database)"
    }

    public func reset() {
        state.withLock { state in
            state.pendingSave = false
            state.storage.removeAll()
        }
        removePersistedFile()
    }

    private func scheduleSave() {
        Task {
            try? await Task.sleep(for: .seconds(saveDebounceInterval))
            let shouldPersist = state.withLock { state in
                if state.pendingSave {
                    state.pendingSave = false
                    return true
                }
                return false
            }
            if shouldPersist {
                persistImmediately()
            }
        }
    }

    private func makeSnapshot(from storage: [String: [HistoryEntry]]) -> Snapshot {
        let entries = storage.mapValues { contextEntries in
            contextEntries.map { PersistedHistoryEntry(entry: $0) }
        }
        return Snapshot(version: persistenceVersion, entriesByContext: entries)
    }

    private func persistImmediately() {
        let snapshotData = state.withLock { state in
            makeSnapshot(from: state.storage)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snapshotData)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Failed to persist autocomplete history: \(error)")
        }
    }

    private func removePersistedFile() {
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try? fm.removeItem(at: fileURL)
        }
    }
}
