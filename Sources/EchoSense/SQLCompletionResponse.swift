import Foundation

/// The result of asking EchoSense for completions at a cursor position.
/// This is the single return type for the clean API.
public struct SQLCompletionResponse: Sendable {
    /// Ranked suggestions ready for display. Empty means nothing to show.
    public let suggestions: [SQLAutoCompletionSuggestion]

    /// Range in text to replace when accepting a suggestion.
    public let replacementRange: NSRange

    /// The token the user is currently typing at the cursor position.
    public let token: String

    /// The parsed SQL clause at the cursor position.
    public let clause: SQLClause

    /// Whether database metadata is limited (structure not loaded).
    public let isMetadataLimited: Bool

    /// Whether the popover should be shown. Convenience for !suggestions.isEmpty.
    public var shouldShow: Bool { !suggestions.isEmpty }

    /// Internal: used by recordSelection to track context
    let caretLocation: Int
}
