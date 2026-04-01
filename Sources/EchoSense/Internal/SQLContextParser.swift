import Foundation
import Logging

public struct SQLContext {
    public struct TableReference: Hashable {
        public let database: String?
        public let schema: String?
        public let name: String
        public let alias: String?
        public let matchLocation: Int

        public init(database: String? = nil, schema: String?, name: String, alias: String?, matchLocation: Int) {
            self.database = database
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
            hasher.combine(database?.lowercased())
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
        let database: String?
        let schema: String?
        let name: String
        let alias: String?
        let range: NSRange
    }

    let text: String
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

        // Find the start of the current statement (after the last ';' before cursor)
        let statementStart = findCurrentStatementStart(in: nsText, before: trimmedLocation)

        let tokenRange = tokenRange(at: trimmedLocation, in: nsText)
        let token = tokenRange.length > 0 ? nsText.substring(with: tokenRange) : ""

        let components = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let pathComponents = components.dropLast().filter { !$0.isEmpty }

        let precedingKeyword = previousKeyword(before: tokenRange.location, tokens: tokens)
        let clause = inferClause(tokens: tokens, caretLocation: trimmedLocation)

        // If there's a WITH clause, skip CTE bodies when scanning for table references
        // so inner FROM tables don't leak into the outer scope
        let tableSearchStart = findOuterQueryStart(from: statementStart, in: nsText) ?? statementStart
        let tableMatches = parseTableMatches(from: tableSearchStart)
        let tables = deduplicatedReferences(from: tableMatches)
        let focusTable = inferFocusTable(matches: tableMatches, caretLocation: trimmedLocation)
        var cteColumns = parseCTEColumns()
        let derivedColumns = parseDerivedTableColumns(catalog: catalog)
        for (key, columns) in derivedColumns where cteColumns[key] == nil {
            cteColumns[key] = columns
        }

        // Add CTE/derived table names to tablesInScope if they have columns
        // but weren't captured by the FROM/JOIN regex.
        // This handles: CTEs (cursor before FROM), derived tables (alias after subquery)
        var enrichedTables = tables
        for cteName in cteColumns.keys {
            let alreadyInScope = enrichedTables.contains { $0.name.lowercased() == cteName }
            if !alreadyInScope {
                // Check if the name appears anywhere in the text as a word
                let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: cteName))\\b"
                guard let regex: NSRegularExpression = {
                    do {
                        return try NSRegularExpression(pattern: pattern)
                    } catch {
                        Logger.echosense.warning("Regex compilation failed for CTE name lookup pattern")
                        return nil
                    }
                }() else { continue }
                if regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil {
                    enrichedTables.append(SQLContext.TableReference(schema: nil,
                                                                     name: cteName,
                                                                     alias: nil,
                                                                     matchLocation: 0))
                }
            }
        }

        return SQLContext(caretLocation: trimmedLocation,
                          currentToken: token,
                          precedingKeyword: precedingKeyword,
                          clause: clause,
                          pathComponents: Array(pathComponents),
                          tablesInScope: enrichedTables,
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
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            Logger.echosense.warning("Regex compilation failed for table match pattern")
            return nil
        }
    }()

    private static let ctePatternRegexes: [NSRegularExpression] = {
        let patterns = [
            "(?is)\\bwith\\s+([A-Za-z0-9_\"`\\[\\]]+)\\s*\\(([^)]+)\\)",
            "(?is)\\)\\s+([A-Za-z0-9_]+)\\s*\\(([^)]+)\\)"
        ]
        return patterns.compactMap { pattern in
            do {
                return try NSRegularExpression(pattern: pattern, options: [])
            } catch {
                Logger.echosense.warning("Regex compilation failed for CTE pattern")
                return nil
            }
        }
    }()

    /// Finds the start of the outer query after WITH ... AS (...) blocks.
    /// Returns nil if there's no WITH clause, meaning we should use the default start.
    private func findOuterQueryStart(from statementStart: Int, in nsText: NSString) -> Int? {
        let length = nsText.length
        guard statementStart < length else { return nil }

        let stmtText = nsText.substring(from: statementStart) as NSString
        // Check if this statement starts with WITH
        let trimmed = stmtText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("WITH") else { return nil }

        // Find the main query keyword (SELECT, INSERT, UPDATE, DELETE) that follows the CTE
        // by tracking parenthesis depth. The outer query starts when we're at depth 0
        // and encounter a statement keyword.
        var pos = statementStart
        var depth = 0
        var inCTE = false

        while pos < length {
            let char = nsText.character(at: pos)
            if char == 0x28 { // (
                depth += 1
                if !inCTE { inCTE = true }
            } else if char == 0x29 { // )
                depth -= 1
                if depth == 0 && inCTE {
                    // We just closed a CTE body. Check what comes next.
                    // It could be another CTE (after comma) or the main query.
                    let remaining = pos + 1
                    if remaining < length {
                        let after = nsText.substring(from: remaining).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        if after.hasPrefix("SELECT") || after.hasPrefix("INSERT") ||
                           after.hasPrefix("UPDATE") || after.hasPrefix("DELETE") {
                            return remaining
                        }
                        // Could be a comma followed by another CTE — continue scanning
                        inCTE = false
                    }
                }
            }
            pos += 1
        }
        return nil
    }

    private func findCurrentStatementStart(in nsText: NSString, before location: Int) -> Int {
        // Scan backwards from cursor to find the last ';'
        var pos = location - 1
        while pos >= 0 {
            if nsText.character(at: pos) == 0x3B { // ';'
                return pos + 1
            }
            pos -= 1
        }
        return 0
    }

    private func parseTableMatches(from statementStart: Int = 0) -> [TableMatch] {
        guard !text.isEmpty else { return [] }

        guard let regex = SQLContextParser.tableMatchRegex else { return [] }
        let nsText = text as NSString
        let clampedStart = max(0, min(statementStart, nsText.length))
        let nsRange = NSRange(location: clampedStart, length: nsText.length - clampedStart)
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
            let database: String?
            let schema: String?
            if components.count >= 3 {
                // 3-part name: database.schema.table (MSSQL)
                database = components[components.count - 3]
                schema = components[components.count - 2]
            } else {
                database = nil
                schema = components.dropLast().last
            }
            matches.append(TableMatch(database: database,
                                       schema: schema,
                                       name: name,
                                       alias: alias,
                                       range: match.range))
        }

        return matches
    }

    private func deduplicatedReferences(from matches: [TableMatch]) -> [SQLContext.TableReference] {
        var unique: [SQLContext.TableReference] = []
        for match in matches {
            let reference = SQLContext.TableReference(database: match.database,
                                                      schema: match.schema,
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
        return SQLContext.TableReference(database: candidate.database,
                                         schema: candidate.schema,
                                         name: candidate.name,
                                         alias: candidate.alias,
                                         matchLocation: candidate.range.location)
    }

    static func normalizeIdentifier(_ value: String) -> String {
        var identifier = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spaceIndex = identifier.firstIndex(where: { $0.isWhitespace }) {
            identifier = String(identifier[..<spaceIndex])
        }
        identifier = identifier.trimmingCharacters(in: CharacterSet(charactersIn: ",;()"))
        let removable: Set<Character> = ["\"", "'", "[", "]", "`"]
        identifier.removeAll(where: { removable.contains($0) })
        return identifier
    }

    static func isValidIdentifier(_ value: String) -> Bool {
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

    static let aliasTerminatingKeywords: Set<String> = [
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

        // Pass 1: CTEs with explicit column lists — WITH name(col1, col2) AS (...)
        for regex in SQLContextParser.ctePatternRegexes {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

            regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }

                let identifierRange = match.range(at: 1)
                guard let identifierSwift = Range(identifierRange, in: text) else { return }
                let rawIdentifier = String(text[identifierSwift])
                let normalizedIdentifier = SQLContextParser.normalizeIdentifier(rawIdentifier).lowercased()
                guard !normalizedIdentifier.isEmpty else { return }
                // Skip SQL keywords that accidentally match the CTE name pattern
                guard normalizedIdentifier != "as" && normalizedIdentifier != "select" else { return }

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

        // Pass 2: CTEs without explicit column lists — WITH name AS (SELECT ...)
        // Infer columns from the inner SELECT statement
        if let regex = SQLContextParser.cteWithoutColumnsRegex {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }

                let nameRange = match.range(at: 1)
                guard let nameSwift = Range(nameRange, in: text) else { return }
                let cteName = SQLContextParser.normalizeIdentifier(String(text[nameSwift])).lowercased()
                guard !cteName.isEmpty, mapping[cteName] == nil else { return }

                let bodyRange = match.range(at: 2)
                guard let bodySwift = Range(bodyRange, in: text) else { return }
                let body = String(text[bodySwift])

                let columns = Self.extractSelectColumns(from: body, catalog: catalog)
                if !columns.isEmpty {
                    mapping[cteName] = columns
                }
            }
        }

        return mapping
    }

    /// Regex for CTEs without explicit column lists: WITH name AS (SELECT ...)
    private static let cteWithoutColumnsRegex: NSRegularExpression? = {
        // Match: WITH name AS ( followed by the body.
        // Uses (?:[^()]*|\([^()]*\))* to handle one level of nested parens (e.g., SUM(total))
        let pattern = "(?is)\\bwith\\s+([A-Za-z0-9_\"`\\[\\]]+)\\s+AS\\s*\\(\\s*(SELECT\\b(?:[^()]+|\\([^()]*\\))*)"
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            Logger.echosense.warning("Regex compilation failed for CTE-without-columns pattern")
            return nil
        }
    }()

    /// Extracts column names/aliases from a SELECT clause.
    /// Handles: "col", "t.col", "col AS alias", "t.col alias", "*" (resolves from catalog).
    static func extractSelectColumns(from selectBody: String, catalog: SQLDatabaseCatalog) -> [String] {
        // Find the SELECT ... FROM boundary
        let upper = selectBody.uppercased()
        guard let selectIndex = upper.range(of: "SELECT") else { return [] }

        let afterSelect = selectBody[selectIndex.upperBound...]
        // Skip DISTINCT / TOP
        var body = afterSelect.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.uppercased().hasPrefix("DISTINCT") {
            body = String(body.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if body.uppercased().hasPrefix("TOP") {
            // Skip TOP N or TOP (N) — handled by the FROM search below
        }

        // Find FROM to delimit the column list
        let fromPattern = "(?i)\\bFROM\\b"
        let fromRegex: NSRegularExpression
        do {
            fromRegex = try NSRegularExpression(pattern: fromPattern)
        } catch {
            Logger.echosense.warning("Regex compilation failed for FROM keyword pattern")
            return []
        }
        guard let fromMatch = fromRegex.firstMatch(in: body, range: NSRange(body.startIndex..<body.endIndex, in: body)),
              let fromSwift = Range(fromMatch.range, in: body) else {
            return []
        }

        let columnsPart = String(body[body.startIndex..<fromSwift.lowerBound])

        // Extract the FROM table name for resolving *
        let afterFrom = String(body[fromSwift.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let fromTableName = afterFrom.split { $0.isWhitespace || $0 == "," || $0 == "(" }.first.map(String.init) ?? ""

        // Split columns by top-level commas
        var columns: [String] = []
        var depth = 0
        var current = ""

        for char in columnsPart {
            if char == "(" { depth += 1; current.append(char) }
            else if char == ")" { depth -= 1; current.append(char) }
            else if char == "," && depth == 0 {
                if let col = extractSingleColumnName(from: current, fromTable: fromTableName, catalog: catalog) {
                    columns.append(contentsOf: col)
                }
                current = ""
            } else {
                current.append(char)
            }
        }
        if let col = extractSingleColumnName(from: current, fromTable: fromTableName, catalog: catalog) {
            columns.append(contentsOf: col)
        }

        return columns
    }

    /// Extracts the column name from a single SELECT expression.
    /// Returns the alias if AS is used, the bare column name otherwise.
    /// For *, resolves to the actual column names from the catalog.
    private static func extractSingleColumnName(from expression: String,
                                                 fromTable: String,
                                                 catalog: SQLDatabaseCatalog) -> [String]? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Handle * — resolve from catalog
        if trimmed == "*" || trimmed.hasSuffix(".*") {
            let tableName = trimmed == "*" ? fromTable : String(trimmed.dropLast(2))
            return resolveStarColumns(table: tableName, catalog: catalog)
        }

        // Handle AS alias — check this BEFORE function detection
        // This handles both "col AS alias" and "FUNC(x) AS alias"
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 3,
           parts[parts.count - 2].caseInsensitiveCompare("AS") == .orderedSame {
            return [normalizeIdentifier(parts.last!).lowercased()]
        }

        // Handle function calls without alias — skip (can't determine column name)
        if trimmed.contains("(") { return nil }

        // Handle implicit alias (two tokens without AS): "col alias"
        if parts.count == 2, !parts[1].contains("("), !parts[1].contains(")") {
            let candidate = normalizeIdentifier(parts[1]).lowercased()
            if isValidIdentifier(candidate) {
                return [candidate]
            }
        }

        // Bare column or table.column — take the last component
        let components = trimmed.split(separator: ".")
        guard let last = components.last else { return nil }
        return [normalizeIdentifier(String(last)).lowercased()]
    }

    /// Resolves * or table.* to actual column names from the catalog.
    private static func resolveStarColumns(table: String, catalog: SQLDatabaseCatalog) -> [String]? {
        let tableLower = normalizeIdentifier(table).lowercased()
        guard !tableLower.isEmpty else { return nil }

        for schema in catalog.schemas {
            for object in schema.objects {
                if object.name.lowercased() == tableLower {
                    return object.columns.map { $0.name.lowercased() }
                }
            }
        }
        return nil
    }
}
