import Foundation

/// What an editor does when the user types: whether the completion popup is asked for at all.
///
/// The engine (`SQLAutoCompletionEngine`) answers wherever it is asked; the editor decides *when* to
/// ask. That decision is part of the completion behaviour, so it lives here, where scenarios and
/// tests can run it, and Echo's editor calls this instead of keeping its own copy.
public enum SQLEditorTrigger: Sendable, Equatable {
    /// Typing this doesn't ask for completions.
    case none
    /// A letter or underscore: ask, and let the engine decide whether there is anything to show.
    case standard
    /// A dot: ask at once (schema.table.column chaining).
    case immediate
    /// A space: ask only after a keyword that is followed by an object name.
    case evaluateSpace
}

public enum SQLEditorTriggerPolicy {
    /// How the text just typed is treated.
    public static func trigger(forInsertedText inserted: String) -> SQLEditorTrigger {
        guard inserted.count == 1, let scalar = inserted.unicodeScalars.first else { return .none }
        if CharacterSet.letters.contains(scalar) { return .standard }
        if inserted == "_" { return .standard }
        if inserted == "." { return .immediate }
        if inserted == " " { return .evaluateSpace }
        return .none
    }

    /// After a space: keywords that are followed by a table or routine name open the popup at once.
    public static func shouldTriggerAfterKeywordSpace(linePrefix: String) -> Bool {
        guard !linePrefix.isEmpty else { return false }
        let pattern = #"(?i)(from|join|update|call|exec|execute|into)\s*$"#
        return linePrefix.range(of: pattern, options: .regularExpression) != nil
    }

    /// The text of the caret's line before the caret.
    public static func linePrefix(in text: String, caret: Int) -> String {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return "" }
        let line = ns.lineRange(for: NSRange(location: caret, length: 0))
        let length = max(0, caret - line.location)
        return length > 0 ? ns.substring(with: NSRange(location: line.location, length: length)) : ""
    }

    /// Whether typing the character before the caret opens the popup by itself (the engine may still
    /// find nothing to show). No character before the caret, or one that isn't typed input, doesn't.
    public static func opensAfterTyping(text: String, caret: Int) -> (opens: Bool, reason: String) {
        let ns = text as NSString
        guard caret > 0, caret <= ns.length else { return (false, "Nothing was typed before the caret.") }
        let typed = ns.substring(with: NSRange(location: caret - 1, length: 1))
        switch trigger(forInsertedText: typed) {
        case .standard, .immediate: return (true, "Typing “\(typed)” asks EchoSense.")
        case .evaluateSpace:
            let opens = shouldTriggerAfterKeywordSpace(linePrefix: linePrefix(in: text, caret: caret))
            return (opens, opens ? "A space after a keyword such as FROM or JOIN asks EchoSense."
                                 : "A space only asks EchoSense after FROM, JOIN, UPDATE, CALL, EXEC or INTO.")
        case .none:
            return (false, "Typing “\(typed)” doesn't ask EchoSense; a manual trigger (⌘.) does.")
        }
    }
}
