import Foundation

/// What an editor does to the text when the user accepts a suggestion: which characters it replaces,
/// what it inserts (keywords get a trailing space; a name typed with quotes stays quoted), and where the
/// caret ends up. Echo's editor calls this, and scenarios run it, so both do exactly the same.
public enum SQLEditorAcceptance {
    /// The characters that belong to a name being completed: letters, digits, `$`, `_`, `.` and `*`.
    public static let tokenCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "$_.*")
        return set
    }()

    public struct Plan: Sendable, Equatable {
        /// The range of the current text that is replaced.
        public let range: NSRange
        /// The text that was there.
        public let originalText: String
        /// The text that goes in.
        public let insertion: String
    }

    public struct Result: Sendable, Equatable {
        public let text: String
        /// Where the caret is afterwards (UTF-16 offset).
        public let caret: Int
        public let plan: Plan
    }

    /// The change accepting `suggestion` makes, given the range the engine asked to replace.
    /// A suggestion that is not a column also takes the name typed before it (back to a dot), and every
    /// suggestion takes the rest of the name after the caret.
    public static func plan(
        for suggestion: SQLAutoCompletionSuggestion, replacementRange baseRange: NSRange,
        in text: String, insertion givenInsertion: String? = nil, isSnippet: Bool = false
    ) -> Plan {
        let ns = text as NSString
        var range = baseRange
        if suggestion.kind != .column {
            var lower = range.location
            while lower > 0 {
                let character = ns.character(at: lower - 1)
                if character == 46 || !isTokenCharacter(character) { break }
                lower -= 1
            }
            range = NSRange(location: lower, length: NSMaxRange(range) - lower)
        }
        var upper = NSMaxRange(range)
        while upper < ns.length, isTokenCharacter(ns.character(at: upper)) { upper += 1 }
        range.length = upper - range.location

        // `givenInsertion` is text the caller already prepared (a snippet, an expanded star); otherwise
        // it is the suggestion's own insert text, with a space after a keyword.
        var proposed = givenInsertion ?? suggestion.insertText
        if givenInsertion == nil, suggestion.kind == .keyword, !proposed.hasSuffix(" ") { proposed += " " }
        let original = ns.substring(with: range)
        let insertion = isSnippet ? proposed : adjustedInsertion(for: suggestion, originalText: original, proposedInsertion: proposed)
        return Plan(range: range, originalText: original, insertion: insertion)
    }

    /// The text and caret after accepting `suggestion` from `response`.
    public static func accept(_ suggestion: SQLAutoCompletionSuggestion, from response: SQLCompletionResponse, in text: String) -> Result {
        let plan = plan(for: suggestion, replacementRange: response.replacementRange, in: text)
        let result = (text as NSString).replacingCharacters(in: plan.range, with: plan.insertion)
        return Result(text: result, caret: plan.range.location + (plan.insertion as NSString).length, plan: plan)
    }

    private static func isTokenCharacter(_ character: unichar) -> Bool {
        UnicodeScalar(character).map(tokenCharacters.contains) ?? false
    }

    /// A name typed with quotes ("Ord", `Ord`, [Ord]) is inserted with the same quoting.
    public static func adjustedInsertion(for suggestion: SQLAutoCompletionSuggestion, originalText: String, proposedInsertion: String) -> String {
        switch suggestion.kind {
        case .column, .table, .view, .materializedView: break
        default: return proposedInsertion
        }
        let prefixCount = proposedInsertion.prefix { $0.isWhitespace }.count
        let suffixCount = proposedInsertion.reversed().prefix { $0.isWhitespace }.count
        let prefixString = String(proposedInsertion.prefix(prefixCount))
        let suffixString = String(proposedInsertion.suffix(suffixCount))
        let coreStart = proposedInsertion.index(proposedInsertion.startIndex, offsetBy: prefixCount)
        let coreEnd = proposedInsertion.index(proposedInsertion.endIndex, offsetBy: -suffixCount)
        guard coreStart <= coreEnd else { return proposedInsertion }
        let core = String(proposedInsertion[coreStart..<coreEnd])
        guard !core.isEmpty else { return proposedInsertion }

        let trimmedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else { return proposedInsertion }
        let original = trimmedOriginal.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let proposed = core.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !original.isEmpty else { return proposedInsertion }

        let wrapped: [String]
        if original.count == proposed.count {
            wrapped = zip(original, proposed).map { wrapComponent($1, using: $0) }
        } else if original.count == 1, proposed.count > 1 {
            // A partial name ("sh") and a proposal with a schema prefix ("HumanResources.Shift"): keep the
            // whole proposed path and give only its last part the original's quoting.
            var result = proposed
            result[result.count - 1] = wrapComponent(result[result.count - 1], using: original[0])
            wrapped = result
        } else if original.count == 1 {
            wrapped = [wrapComponent(core, using: original[0])]
        } else {
            return proposedInsertion
        }
        return prefixString + wrapped.joined(separator: ".") + suffixString
    }

    public static func wrapComponent(_ component: String, using originalComponent: String) -> String {
        let trimmedOriginal = originalComponent.trimmingCharacters(in: .whitespaces)
        guard let first = trimmedOriginal.first else { return component }
        let pairs: [Character: Character] = ["\"": "\"", "`": "`", "[": "]"]
        guard let closing = pairs[first], trimmedOriginal.last == closing else { return component }
        let trimmedComponent = component.trimmingCharacters(in: .whitespaces)
        if trimmedComponent.first == first && trimmedComponent.last == closing { return component }
        let inner = trimmedComponent.trimmingCharacters(in: CharacterSet(charactersIn: "\"`[]"))
        return "\(first)\(inner)\(closing)"
    }
}
