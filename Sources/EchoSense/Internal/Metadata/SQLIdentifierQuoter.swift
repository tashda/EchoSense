import Foundation

struct SQLIdentifierQuoter {
    enum Rule: Hashable {
        case camelCase
        case whitespace
        case reservedWord
    }

    private let openingQuote: Character
    private let closingQuote: Character
    private let rules: Set<Rule>
    private let reservedWords: Set<String>

    static func forDialect(_ dialect: SQLDialect) -> SQLIdentifierQuoter {
        switch dialect {
        case .postgresql:
            var keywords = SQLReservedKeywords.allLowercased
            // Allow unquoted use of the common "public" schema in PostgreSQL.
            // It is technically a reserved word in some SQL dialects, but in
            // practice users expect to write it without quotes.
            keywords.remove("public")
            return SQLIdentifierQuoter(openingQuote: "\"",
                                       closingQuote: "\"",
                                       rules: [.camelCase, .reservedWord, .whitespace],
                                       reservedWords: keywords)
        case .mysql:
            let keywords = SQLReservedKeywords.allLowercased
            return SQLIdentifierQuoter(openingQuote: "`",
                                       closingQuote: "`",
                                       rules: [.reservedWord, .whitespace],
                                       reservedWords: keywords)
        case .sqlite:
            let keywords = SQLReservedKeywords.allLowercased
            return SQLIdentifierQuoter(openingQuote: "\"",
                                       closingQuote: "\"",
                                       rules: [.reservedWord, .whitespace],
                                       reservedWords: keywords)
        case .microsoftSQL:
            let keywords = SQLReservedKeywords.allLowercased
            return SQLIdentifierQuoter(openingQuote: "[",
                                       closingQuote: "]",
                                       rules: [.reservedWord, .whitespace],
                                       reservedWords: keywords)
        }
    }

    init(openingQuote: Character,
         closingQuote: Character,
         rules: Set<Rule>,
         reservedWords: Set<String>) {
        self.openingQuote = openingQuote
        self.closingQuote = closingQuote
        self.rules = rules
        self.reservedWords = reservedWords
    }

    func quoteIfNeeded(_ value: String) -> String {
        guard shouldQuote(value) else { return value }
        let escaped = escape(value)
        return wrap(escaped)
    }

    func shouldQuote(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isAlreadyQuoted(trimmed) { return false }
        if requiresGeneralQuoting(trimmed) { return true }
        if rules.contains(.camelCase) && isCamelCase(trimmed) { return true }
        if rules.contains(.whitespace) && containsWhitespace(trimmed) { return true }
        if rules.contains(.reservedWord) && reservedWords.contains(trimmed.lowercased()) { return true }
        return false
    }

    func qualify(_ components: [String]) -> String {
        components.map { quoteIfNeeded($0) }.joined(separator: ".")
    }

    private func wrap(_ identifier: String) -> String {
        if openingQuote == "[" && closingQuote == "]" {
            return "[\(identifier)]"
        }
        return "\(openingQuote)\(identifier)\(closingQuote)"
    }

    private func escape(_ identifier: String) -> String {
        switch closingQuote {
        case "]":
            return identifier.replacingOccurrences(of: "]", with: "]]" )
        case "\"":
            return identifier.replacingOccurrences(of: "\"", with: "\"\"")
        case "`":
            return identifier.replacingOccurrences(of: "`", with: "``")
        default:
            return identifier
        }
    }

    private func isAlreadyQuoted(_ identifier: String) -> Bool {
        guard identifier.count >= 2 else { return false }
        if openingQuote == "[" && closingQuote == "]" {
            return identifier.hasPrefix("[") && identifier.hasSuffix("]")
        }
        return identifier.first == openingQuote && identifier.last == closingQuote
    }

    private func requiresGeneralQuoting(_ identifier: String) -> Bool {
        if identifier.first?.isNumber == true { return true }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        for scalar in identifier.unicodeScalars {
            if allowed.contains(scalar) { continue }
            return true
        }
        return false
    }

    private func isCamelCase(_ identifier: String) -> Bool {
        var hasUpper = false
        var hasLower = false
        for character in identifier {
            if character.isUppercase { hasUpper = true }
            if character.isLowercase { hasLower = true }
            if hasUpper && hasLower { return true }
        }
        return false
    }

    private func containsWhitespace(_ identifier: String) -> Bool {
        identifier.contains { $0.isWhitespace }
    }
}
