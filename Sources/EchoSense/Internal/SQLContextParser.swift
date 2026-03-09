import Foundation

public struct SQLContext {
    public struct TableReference: Hashable {
        public let schema: String?
        public let name: String
        public let alias: String?
        public let matchLocation: Int

        public init(schema: String?, name: String, alias: String?, matchLocation: Int) {
            self.schema = schema
            self.name = name
            self.alias = alias
            self.matchLocation = matchLocation
        }

        public func matches(schema otherSchema: String?, name otherName: String) -> Bool {
            guard name.caseInsensitiveCompare(otherName) == .orderedSame else { return false }
            guard let schema else { return true }
            guard let otherSchema else { return false }
            return schema.caseInsensitiveCompare(otherSchema) == .orderedSame
        }

        public func isEquivalent(to other: SQLContext.TableReference) -> Bool {
            guard matches(schema: other.schema, name: other.name) else { return false }
            let lhsAlias = alias?.lowercased()
            let rhsAlias = other.alias?.lowercased()
            return lhsAlias == rhsAlias
        }

        public static func == (lhs: SQLContext.TableReference, rhs: SQLContext.TableReference) -> Bool {
            lhs.isEquivalent(to: rhs)
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(schema?.lowercased())
            hasher.combine(name.lowercased())
            hasher.combine(alias?.lowercased())
        }
    }

    public let caretLocation: Int
    public let currentToken: String
    public let precedingKeyword: String?
    public let clause: SQLClause
    public let pathComponents: [String]
    public let tablesInScope: [TableReference]
    public let focusTable: TableReference?
    public let cteColumns: [String: [String]]

    init(caretLocation: Int,
         currentToken: String,
         precedingKeyword: String?,
         clause: SQLClause,
         pathComponents: [String],
         tablesInScope: [TableReference],
         focusTable: TableReference?,
         cteColumns: [String: [String]]) {
        self.caretLocation = caretLocation
        self.currentToken = currentToken
        self.precedingKeyword = precedingKeyword
        self.clause = clause
        self.pathComponents = pathComponents
        self.tablesInScope = tablesInScope
        self.focusTable = focusTable
        self.cteColumns = cteColumns
    }
}

public final class SQLContextParser {
    private struct TableMatch {
        let schema: String?
        let name: String
        let alias: String?
        let range: NSRange
    }

    private let text: String
    private let caretLocation: Int
    private let dialect: SQLDialect
    private let catalog: SQLDatabaseCatalog

    public init(text: String, caretLocation: Int, dialect: SQLDialect, catalog: SQLDatabaseCatalog) {
        self.text = text
        self.caretLocation = caretLocation
        self.dialect = dialect
        self.catalog = catalog
    }

    public func parse() -> SQLContext {
        let nsText = text as NSString
        let trimmedLocation = max(0, min(caretLocation, nsText.length))
        let tokens = SQLTokenizer.tokenize(nsText)

        let tokenRange = tokenRange(at: trimmedLocation, in: nsText)
        let token = tokenRange.length > 0 ? nsText.substring(with: tokenRange) : ""

        let components = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let pathComponents = components.dropLast().filter { !$0.isEmpty }

        let precedingKeyword = previousKeyword(before: tokenRange.location, tokens: tokens)
        let clause = inferClause(tokens: tokens, caretLocation: trimmedLocation)
        let tableMatches = parseTableMatches()
        let tables = deduplicatedReferences(from: tableMatches)
        let focusTable = inferFocusTable(matches: tableMatches, caretLocation: trimmedLocation)
        let cteColumns = parseCTEColumns()

        return SQLContext(caretLocation: trimmedLocation,
                          currentToken: token,
                          precedingKeyword: precedingKeyword,
                          clause: clause,
                          pathComponents: Array(pathComponents),
                          tablesInScope: tables,
                          focusTable: focusTable,
                          cteColumns: cteColumns)
    }

    private func tokenRange(at caretLocation: Int, in text: NSString) -> NSRange {
        var start = caretLocation
        while start > 0 {
            let character = text.character(at: start - 1)
            if SQLContextParser.completionTokenCharacterSet.contains(UnicodeScalar(character)!) {
                start -= 1
            } else {
                break
            }
        }
        return NSRange(location: start, length: caretLocation - start)
    }

    private func previousKeyword(before location: Int, tokens: [SQLToken]) -> String? {
        guard location > 0 else { return nil }
        for token in tokens.reversed() {
            guard token.range.location < location else { continue }
            switch token.kind {
            case .keyword:
                return token.lowercased
            case .identifier where SQLContextParser.keywordLikeIdentifiers.contains(token.lowercased):
                return token.lowercased
            default:
                continue
            }
        }
        return nil
    }

    private func inferClause(tokens: [SQLToken], caretLocation: Int) -> SQLClause {
        var machine = ClauseStateMachine()
        for token in tokens {
            guard token.range.location < caretLocation else { break }
            machine.feed(token)
        }
        return machine.currentClause
    }

    private static let tableMatchRegex: NSRegularExpression? = {
        let pattern = "(?ix)\\b(from|join|update|into)\\s+([A-Za-z0-9_.\\\"`\\[\\]]+)(?:\\s+(?:AS\\s+)?([A-Za-z0-9_]+))?"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let ctePatternRegexes: [NSRegularExpression] = {
        let patterns = [
            "(?is)\\bwith\\s+([A-Za-z0-9_\"`\\[\\]]+)\\s*\\(([^)]+)\\)",
            "(?is)\\)\\s+([A-Za-z0-9_]+)\\s*\\(([^)]+)\\)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    private func parseTableMatches() -> [TableMatch] {
        guard !text.isEmpty else { return [] }

        guard let regex = SQLContextParser.tableMatchRegex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var matches: [TableMatch] = []

        regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let identifierRange = match.range(at: 2)
            guard let identifierSwift = Range(identifierRange, in: text) else { return }
            let rawIdentifier = String(text[identifierSwift])
            let normalized = SQLContextParser.normalizeIdentifier(rawIdentifier)
            guard !normalized.isEmpty else { return }

            let aliasRange = match.range(at: 3)
            var alias: String?
            if aliasRange.location != NSNotFound,
               let aliasSwift = Range(aliasRange, in: text) {
                let candidate = SQLContextParser.normalizeIdentifier(String(text[aliasSwift]))
                if !candidate.isEmpty,
                   SQLContextParser.isValidIdentifier(candidate),
                   !SQLContextParser.aliasTerminatingKeywords.contains(candidate.uppercased()) {
                    alias = candidate
                }
            }

            let components = normalized.split(separator: ".", omittingEmptySubsequences: true).map(String.init)
            guard let name = components.last else { return }
            let schema = components.dropLast().last
            matches.append(TableMatch(schema: schema,
                                       name: name,
                                       alias: alias,
                                       range: match.range))
        }

        return matches
    }

    private func deduplicatedReferences(from matches: [TableMatch]) -> [SQLContext.TableReference] {
        var unique: [SQLContext.TableReference] = []
        for match in matches {
            let reference = SQLContext.TableReference(schema: match.schema,
                                                      name: match.name,
                                                      alias: match.alias,
                                                      matchLocation: match.range.location)
            if !unique.contains(where: { $0.isEquivalent(to: reference) }) {
                unique.append(reference)
            }
        }
        return unique
    }

    private func inferFocusTable(matches: [TableMatch], caretLocation: Int) -> SQLContext.TableReference? {
        guard !matches.isEmpty else { return nil }
        let candidate = matches.last { NSMaxRange($0.range) <= caretLocation } ?? matches.last!
        return SQLContext.TableReference(schema: candidate.schema,
                                         name: candidate.name,
                                         alias: candidate.alias,
                                         matchLocation: candidate.range.location)
    }

    private static func normalizeIdentifier(_ value: String) -> String {
        var identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spaceIndex = identifier.firstIndex(where: { $0.isWhitespace }) {
            identifier = String(identifier[..<spaceIndex])
        }
        identifier = identifier.trimmingCharacters(in: CharacterSet(charactersIn: ",;()"))
        let removable: Set<Character> = ["\"", "'", "[", "]", "`"]
        identifier.removeAll(where: { removable.contains($0) })
        return identifier
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        let startSet = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        let bodySet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard startSet.contains(first) else { return false }
        return value.unicodeScalars.dropFirst().allSatisfy { bodySet.contains($0) }
    }

    private static let completionTokenCharacterSet: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "$_.")
        set.insert(charactersIn: "*")
        return set
    }()

    public static let objectContextKeywords: Set<String> = [
        "from", "join", "inner", "left", "right", "full", "outer", "cross", "update", "into", "delete"
    ]

    private static let aliasTerminatingKeywords: Set<String> = [
        "WHERE", "INNER", "LEFT", "RIGHT", "ON", "JOIN", "SET", "ORDER", "GROUP", "HAVING", "LIMIT"
    ]

    private static let keywordLikeIdentifiers: Set<String> = [
        "select", "from", "join", "on", "where", "group", "by", "order", "having", "limit",
        "offset", "insert", "into", "values", "update", "set", "delete", "with", "returning"
    ]

    public static let columnContextKeywords: Set<String> = [
        "select", "where", "on", "and", "or", "having", "group", "order", "by", "set", "values", "case", "when", "then", "else", "returning", "using"
    ]

    private func parseCTEColumns() -> [String: [String]] {
        var mapping: [String: [String]] = [:]

        for regex in SQLContextParser.ctePatternRegexes {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

            regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }

                let identifierRange = match.range(at: 1)
                guard let identifierSwift = Range(identifierRange, in: text) else { return }
                let rawIdentifier = String(text[identifierSwift])
                let normalizedIdentifier = SQLContextParser.normalizeIdentifier(rawIdentifier).lowercased()
                guard !normalizedIdentifier.isEmpty else { return }

                let columnsRange = match.range(at: 2)
                guard let columnsSwift = Range(columnsRange, in: text) else { return }
                let columnsString = String(text[columnsSwift])
                let columns = columnsString
                    .split(separator: ",")
                    .map { SQLContextParser.normalizeIdentifier(String($0)).lowercased() }
                    .filter { !$0.isEmpty }

                if !columns.isEmpty {
                    mapping[normalizedIdentifier] = columns
                }
            }
        }

        return mapping
    }
}
