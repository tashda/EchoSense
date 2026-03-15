import Foundation

// MARK: - Derived Table Column Extraction

extension SQLContextParser {

    /// Extracts column names from derived tables (subqueries in FROM/JOIN clauses).
    /// Handles patterns like: `(SELECT col1, col2 FROM ...) [AS] alias`
    /// Only extracts explicitly named columns from the inner SELECT list.
    func parseDerivedTableColumns() -> [String: [String]] {
        guard !text.isEmpty else { return [:] }
        var mapping: [String: [String]] = [:]

        // Find subquery patterns: balanced parens containing SELECT, followed by alias
        let nsText = text as NSString
        let length = nsText.length
        var i = 0

        while i < length {
            let char = nsText.character(at: i)
            // Look for opening paren
            guard char == UnicodeScalar("(").value else {
                i += 1
                continue
            }

            // Find the matching closing paren
            var depth = 1
            var j = i + 1
            while j < length && depth > 0 {
                let c = nsText.character(at: j)
                if c == UnicodeScalar("(").value { depth += 1 }
                else if c == UnicodeScalar(")").value { depth -= 1 }
                j += 1
            }

            guard depth == 0 else {
                i += 1
                continue
            }

            let innerStart = i + 1
            let innerEnd = j - 1
            let innerLength = innerEnd - innerStart
            guard innerLength > 6 else { // At least "SELECT" length
                i = j
                continue
            }

            // Check if inner text starts with SELECT (skip whitespace)
            let innerText = nsText.substring(with: NSRange(location: innerStart, length: innerLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard innerText.uppercased().hasPrefix("SELECT") else {
                i = j
                continue
            }

            // Look for alias after closing paren: ) [AS] alias
            let afterParen = nsText.substring(from: j).trimmingCharacters(in: .whitespacesAndNewlines)
            let alias = Self.extractDerivedTableAlias(from: afterParen)
            guard let alias, !alias.isEmpty else {
                i = j
                continue
            }

            // Extract column names from the inner SELECT list
            let columns = Self.extractSelectListColumns(from: innerText)
            if !columns.isEmpty {
                mapping[alias.lowercased()] = columns
            }

            i = j
        }

        return mapping
    }

    /// Extracts the alias from text immediately following a closing paren.
    /// Handles: `) alias`, `) AS alias`
    private static func extractDerivedTableAlias(from text: String) -> String? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        // Skip optional "AS" (case-insensitive)
        if working.uppercased().hasPrefix("AS") {
            let afterAs = working.dropFirst(2)
            // Must be followed by whitespace (not "ASSIGN" etc.)
            guard let first = afterAs.first, first.isWhitespace else {
                // "AS" is not followed by whitespace — not an AS keyword
                // Fall through to try reading as identifier
                return extractIdentifier(from: working)
            }
            working = afterAs.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return extractIdentifier(from: working)
    }

    private static func extractIdentifier(from text: String) -> String? {
        let identChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        var alias = ""
        for scalar in text.unicodeScalars {
            if identChars.contains(scalar) {
                alias.append(Character(scalar))
            } else {
                break
            }
        }
        guard !alias.isEmpty else { return nil }

        // Verify alias isn't a SQL keyword that would indicate no alias
        let keywordsNotAlias: Set<String> = [
            "WHERE", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS",
            "JOIN", "ON", "SET", "ORDER", "GROUP", "HAVING", "LIMIT",
            "UNION", "INTERSECT", "EXCEPT", "AND", "OR", "THEN", "WHEN",
            "SELECT", "FROM", "INSERT", "UPDATE", "DELETE"
        ]
        if keywordsNotAlias.contains(alias.uppercased()) {
            return nil
        }

        return alias
    }

    /// Extracts column names from a SELECT statement's select list.
    /// Handles: `SELECT col1, col2, table.col3 AS alias FROM ...`
    /// Returns the display name (alias if present, otherwise column name).
    private static func extractSelectListColumns(from sql: String) -> [String] {
        // Strip leading SELECT [DISTINCT] [TOP n]
        var working = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = working.uppercased()
        guard upper.hasPrefix("SELECT") else { return [] }
        working = String(working.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip DISTINCT
        if working.uppercased().hasPrefix("DISTINCT") {
            working = String(working.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            // Handle DISTINCT ON (...)
            if working.uppercased().hasPrefix("ON") {
                let afterOn = String(working.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if afterOn.hasPrefix("(") {
                    // Skip past the closing paren
                    var depth = 1
                    var idx = afterOn.index(after: afterOn.startIndex)
                    while idx < afterOn.endIndex && depth > 0 {
                        if afterOn[idx] == "(" { depth += 1 }
                        else if afterOn[idx] == ")" { depth -= 1 }
                        idx = afterOn.index(after: idx)
                    }
                    working = String(afterOn[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // Skip TOP n (SQL Server)
        if working.uppercased().hasPrefix("TOP") {
            working = String(working.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip the number or (expression)
            if working.hasPrefix("(") {
                var depth = 1
                var idx = working.index(after: working.startIndex)
                while idx < working.endIndex && depth > 0 {
                    if working[idx] == "(" { depth += 1 }
                    else if working[idx] == ")" { depth -= 1 }
                    idx = working.index(after: idx)
                }
                working = String(working[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // Skip number
                working = String(working.drop(while: { $0.isNumber || $0.isWhitespace }))
            }
        }

        // Find FROM to know where the select list ends
        let selectListEnd = Self.findFromKeyword(in: working)
        let selectList = selectListEnd.map { String(working[working.startIndex..<$0]) } ?? working

        // If the select list is just *, we can't extract columns
        if selectList.trimmingCharacters(in: .whitespacesAndNewlines) == "*" {
            return []
        }

        // Split by commas, respecting parentheses depth
        let items = Self.splitByComma(selectList)
        var columns: [String] = []

        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "*" { continue }
            if let name = Self.extractColumnName(from: trimmed) {
                columns.append(name.lowercased())
            }
        }

        return columns
    }

    /// Finds the position of the FROM keyword at depth 0 in the select list.
    private static func findFromKeyword(in text: String) -> String.Index? {
        var depth = 0
        var i = text.startIndex
        let upper = text.uppercased()
        let upperChars = Array(upper)
        var idx = 0

        while i < text.endIndex {
            let c = text[i]
            if c == "(" { depth += 1 }
            else if c == ")" { depth -= 1 }
            else if depth == 0 && idx + 4 <= upperChars.count {
                // Check for " FROM " (with word boundary)
                if upperChars[idx] == "F" && upperChars[idx+1] == "R" &&
                   upperChars[idx+2] == "O" && upperChars[idx+3] == "M" {
                    // Check word boundary before
                    let hasBefore = idx == 0 || !upperChars[idx-1].isLetter
                    // Check word boundary after
                    let hasAfter = idx + 4 >= upperChars.count || !upperChars[idx+4].isLetter
                    if hasBefore && hasAfter {
                        return i
                    }
                }
            }
            i = text.index(after: i)
            idx += 1
        }
        return nil
    }

    /// Splits text by top-level commas (not inside parentheses).
    private static func splitByComma(_ text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var depth = 0

        for char in text {
            if char == "(" { depth += 1; current.append(char) }
            else if char == ")" { depth -= 1; current.append(char) }
            else if char == "," && depth == 0 {
                items.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(current)
        }
        return items
    }

    /// Extracts the output column name from a select list item.
    /// Returns the AS alias if present, otherwise the last identifier.
    private static func extractColumnName(from item: String) -> String? {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Check for explicit alias: ... AS alias
        let upper = trimmed.uppercased()
        if let asRange = upper.range(of: " AS ", options: .backwards) {
            let afterAs = trimmed[asRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let alias = normalizeIdentifier(afterAs)
            if !alias.isEmpty { return alias }
        }

        // Check for implicit alias (last word after space, no operators)
        // e.g., "table.column alias" → "alias"
        let words = trimmed.split(whereSeparator: { $0.isWhitespace })
        if words.count >= 2,
           let lastWord = words.last {
            let candidate = String(lastWord)
            let normalized = normalizeIdentifier(candidate)
            // Make sure it's a valid identifier and not a keyword/operator
            if isValidIdentifier(normalized) &&
               !aliasTerminatingKeywords.contains(normalized.uppercased()) {
                return normalized
            }
        }

        // Simple column reference: just the identifier, possibly qualified
        let components = trimmed.split(separator: ".", omittingEmptySubsequences: true)
        if let last = components.last {
            let candidate = normalizeIdentifier(String(last))
            if isValidIdentifier(candidate) {
                return candidate
            }
        }

        return nil
    }
}
