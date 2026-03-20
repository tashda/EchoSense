import Foundation

/// Consolidated preferences for the autocomplete engine.
public struct SQLCompletionPreferences: Sendable {
    public var includeHistory: Bool
    public var includeSystemSchemas: Bool
    public var qualifyTableInsertions: Bool
    public var autoJoinOnClause: Bool

    public init(
        includeHistory: Bool = true,
        includeSystemSchemas: Bool = false,
        qualifyTableInsertions: Bool = false,
        autoJoinOnClause: Bool = true
    ) {
        self.includeHistory = includeHistory
        self.includeSystemSchemas = includeSystemSchemas
        self.qualifyTableInsertions = qualifyTableInsertions
        self.autoJoinOnClause = autoJoinOnClause
    }
}
