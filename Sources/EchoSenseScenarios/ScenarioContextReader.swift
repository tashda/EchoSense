import EchoSense
import Foundation

/// Reads a `ScenarioContext` from a scenario's SQL. Deliberately small and separate from the engine's
/// parser: it understands FROM, JOIN, INTO, UPDATE and APPLY targets with aliases, CTEs, subqueries in
/// FROM, the path before the caret and the SELECT list. Comments and strings are skipped.
public enum ScenarioContextReader {
    public static func read(_ text: String, caret: Int, structure: EchoSenseDatabaseStructure, database: String?) -> ScenarioContext {
        let ns = text as NSString
        let caret = max(0, min(caret, ns.length))
        let tokens = tokenize(text)
        // The token being typed: identifier characters and dots right before the caret.
        var start = caret
        while start > 0, let scalar = UnicodeScalar(ns.character(at: start - 1)), isPathCharacter(Character(scalar)) { start -= 1 }
        let path = ns.substring(with: NSRange(location: start, length: caret - start))
        let statement = statementTokens(tokens, caret: caret).filter { $0.range.upperBound <= start || $0.range.location >= caret }

        var context = ScenarioContext()
        let components = path.split(separator: ".", omittingEmptySubsequences: false).map { unquote(String($0)) }
        context.typed = components.last ?? ""
        readCTEs(statement, into: &context)
        readTables(statement, into: &context)
        context.changedTable = changedTable(statement)
        context.selectList = selectList(statement)
        if components.count > 1 {
            context.dot = dot(Array(components.dropLast()), context: context, structure: structure, database: database)
        }
        return context
    }

    // MARK: Tokens

    struct Token {
        enum Kind { case word, quoted, punctuation, string, number }
        var text: String
        var kind: Kind
        var range: NSRange
        var upper: String { text.uppercased() }
        func isKeyword(_ word: String) -> Bool { kind == .word && upper == word }
    }

    static func isPathCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "." || c == "\"" || c == "[" || c == "]" || c == "$" || c == "@" || c == "#"
    }

    static func unquote(_ name: String) -> String {
        guard name.count >= 2, let first = name.first, let last = name.last else { return name }
        if (first == "\"" && last == "\"") || (first == "[" && last == "]") || (first == "`" && last == "`") { return String(name.dropFirst().dropLast()) }
        return name
    }

    static func tokenize(_ text: String) -> [Token] {
        let chars = Array(text.utf16)
        var tokens: [Token] = []
        var i = 0
        func char(_ k: Int) -> Character { k < chars.count ? Character(UnicodeScalar(chars[k]) ?? " ") : "\0" }
        while i < chars.count {
            let c = char(i)
            if c == "-" && char(i + 1) == "-" { while i < chars.count && char(i) != "\n" { i += 1 }; continue }
            if c == "/" && char(i + 1) == "*" { i += 2; while i < chars.count && !(char(i) == "*" && char(i + 1) == "/") { i += 1 }; i += 2; continue }
            if c.isWhitespace { i += 1; continue }
            let begin = i
            if c == "'" {
                i += 1; while i < chars.count && char(i) != "'" { i += 1 }; i += 1
                tokens.append(Token(text: "", kind: .string, range: NSRange(location: begin, length: min(i, chars.count) - begin))); continue
            }
            if c == "\"" || c == "[" || c == "`" {
                let close: Character = c == "[" ? "]" : c
                i += 1; while i < chars.count && char(i) != close { i += 1 }; i += 1
                let end = min(i, chars.count)
                let raw = String(utf16CodeUnits: Array(chars[begin..<end]), count: end - begin)
                tokens.append(Token(text: unquote(raw), kind: .quoted, range: NSRange(location: begin, length: end - begin))); continue
            }
            if c.isLetter || c == "_" || c == "@" || c == "#" || c == "$" {
                while i < chars.count && (char(i).isLetter || char(i).isNumber || char(i) == "_" || char(i) == "$" || char(i) == "@" || char(i) == "#") { i += 1 }
                tokens.append(Token(text: String(utf16CodeUnits: Array(chars[begin..<i]), count: i - begin), kind: .word, range: NSRange(location: begin, length: i - begin))); continue
            }
            if c.isNumber {
                while i < chars.count && (char(i).isNumber || char(i) == ".") { i += 1 }
                tokens.append(Token(text: String(utf16CodeUnits: Array(chars[begin..<i]), count: i - begin), kind: .number, range: NSRange(location: begin, length: i - begin))); continue
            }
            i += 1
            tokens.append(Token(text: String(c), kind: .punctuation, range: NSRange(location: begin, length: 1)))
        }
        return tokens
    }

    /// The tokens of the statement the caret is in (statements end at `;`).
    static func statementTokens(_ tokens: [Token], caret: Int) -> [Token] {
        var current: [Token] = []
        for token in tokens {
            if token.kind == .punctuation && token.text == ";" {
                if token.range.location >= caret { return current }
                current = []
            } else {
                current.append(token)
            }
        }
        return current
    }

    static let notAliases: Set<String> = ["WHERE", "ON", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS", "OUTER", "SET", "VALUES", "ORDER",
        "GROUP", "HAVING", "LIMIT", "UNION", "EXCEPT", "INTERSECT", "AS", "USING", "RETURNING", "SELECT", "FROM", "WITH", "APPLY", "OFFSET",
        "FETCH", "WINDOW", "NATURAL", "LATERAL", "DEFAULT", "INTO", "OUTPUT", "TOP", "WHEN", "THEN", "ELSE", "END"]

    static func isName(_ token: Token) -> Bool { token.kind == .quoted || (token.kind == .word && !notAliases.contains(token.upper)) }

    // MARK: Tables, CTEs, subqueries

    static func readTables(_ tokens: [Token], into context: inout ScenarioContext) {
        var i = 0
        while i < tokens.count {
            let word = tokens[i].upper
            guard tokens[i].kind == .word, ["FROM", "JOIN", "INTO", "UPDATE", "APPLY"].contains(word) else { i += 1; continue }
            i += 1
            repeat {
                if i < tokens.count, tokens[i].text == "(" {
                    // A subquery in FROM: its columns, under its alias.
                    let close = matchingParen(tokens, from: i)
                    let inner = Array(tokens[(i + 1)..<max(i + 1, close)])
                    i = close + 1
                    if i < tokens.count, tokens[i].isKeyword("AS") { i += 1 }
                    if i < tokens.count, isName(tokens[i]) {
                        context.derived[tokens[i].text] = columns(ofSelect: inner)
                        context.tables.append(.init(name: tokens[i].text, alias: nil))
                        i += 1
                    }
                } else if i < tokens.count, isName(tokens[i]) {
                    var parts = [tokens[i].text]
                    i += 1
                    while i + 1 < tokens.count, tokens[i].text == ".", isName(tokens[i + 1]) || tokens[i + 1].kind == .word { parts.append(tokens[i + 1].text); i += 2 }
                    var alias: String?
                    if i < tokens.count, tokens[i].isKeyword("AS") { i += 1 }
                    if i < tokens.count, isName(tokens[i]), !(i + 1 < tokens.count && tokens[i + 1].text == "(") { alias = tokens[i].text; i += 1 }
                    let name = parts.last ?? ""
                    let schema = parts.count >= 2 ? parts[parts.count - 2] : nil
                    let database = parts.count >= 3 ? parts[parts.count - 3] : nil
                    context.tables.append(.init(database: database, schema: schema, name: name, alias: alias))
                }
                guard i < tokens.count, tokens[i].text == "," else { break }
                i += 1
            } while i < tokens.count
        }
    }

    static func readCTEs(_ tokens: [Token], into context: inout ScenarioContext) {
        guard let first = tokens.first, first.isKeyword("WITH") else { return }
        var i = 1
        if i < tokens.count, tokens[i].isKeyword("RECURSIVE") { i += 1 }
        while i < tokens.count, isName(tokens[i]) {
            let name = tokens[i].text
            i += 1
            var explicit: [String] = []
            if i < tokens.count, tokens[i].text == "(" {
                let close = matchingParen(tokens, from: i)
                explicit = tokens[(i + 1)..<close].filter { $0.kind == .word || $0.kind == .quoted }.map(\.text)
                i = close + 1
            }
            guard i < tokens.count, tokens[i].isKeyword("AS") else { return }
            i += 1
            guard i < tokens.count, tokens[i].text == "(" else { return }
            let close = matchingParen(tokens, from: i)
            context.derived[name] = explicit.isEmpty ? columns(ofSelect: Array(tokens[(i + 1)..<close])) : explicit
            i = close + 1
            guard i < tokens.count, tokens[i].text == "," else { return }
            i += 1
        }
    }

    static func matchingParen(_ tokens: [Token], from open: Int) -> Int {
        var depth = 0
        for k in open..<tokens.count {
            if tokens[k].text == "(" { depth += 1 }
            if tokens[k].text == ")" { depth -= 1; if depth == 0 { return k } }
        }
        return tokens.count
    }

    /// The column names a SELECT produces: aliases, plain names, or `*table` for `SELECT * FROM table`.
    static func columns(ofSelect tokens: [Token]) -> [String] {
        let items = selectItems(tokens)
        if items.count == 1, items[0].count == 1, items[0][0].text == "*" {
            if let from = tokens.firstIndex(where: { $0.isKeyword("FROM") }), from + 1 < tokens.count { return ["*" + tokens[from + 1].text] }
            return []
        }
        return items.compactMap { item in
            if let asIndex = item.lastIndex(where: { $0.isKeyword("AS") }), asIndex + 1 < item.count { return item[asIndex + 1].text }
            let names = item.filter { $0.kind == .word || $0.kind == .quoted }
            if item.allSatisfy({ $0.kind == .word || $0.kind == .quoted || $0.text == "." }), let last = names.last { return last.text }
            return nil
        }
    }

    /// The items between the first SELECT and its FROM at the same depth, split at commas.
    static func selectItems(_ tokens: [Token]) -> [[Token]] {
        guard let select = tokens.firstIndex(where: { $0.isKeyword("SELECT") }) else { return [] }
        var items: [[Token]] = [[]]
        var depth = 0
        for token in tokens[(select + 1)...] {
            if token.text == "(" { depth += 1 }
            if token.text == ")" { depth -= 1 }
            if depth == 0 && token.isKeyword("FROM") { break }
            if depth == 0 && token.text == "," { items.append([]); continue }
            if depth == 0 && token.isKeyword("DISTINCT") { continue }
            items[items.count - 1].append(token)
        }
        return items.filter { !$0.isEmpty }
    }

    static func selectList(_ tokens: [Token]) -> [String] {
        guard tokens.first?.isKeyword("SELECT") == true || tokens.first?.isKeyword("WITH") == true else { return [] }
        let start = tokens.firstIndex { $0.isKeyword("SELECT") && !isInsideParens(tokens, $0) } ?? 0
        return selectItems(Array(tokens[start...])).compactMap { item in
            guard item.allSatisfy({ $0.kind == .word || $0.kind == .quoted || $0.text == "." }) else { return nil }
            return item.last?.text
        }
    }

    static func isInsideParens(_ tokens: [Token], _ target: Token) -> Bool {
        var depth = 0
        for token in tokens {
            if token.range.location == target.range.location { return depth > 0 }
            if token.text == "(" { depth += 1 }
            if token.text == ")" { depth -= 1 }
        }
        return false
    }

    static func changedTable(_ tokens: [Token]) -> String? {
        guard let first = tokens.first(where: { $0.kind == .word }) else { return nil }
        let target: Token?
        switch first.upper {
        case "INSERT": target = tokens.firstIndex { $0.isKeyword("INTO") }.flatMap { $0 + 1 < tokens.count ? tokens[$0 + 1] : nil }
        case "UPDATE": target = tokens.count > 1 ? tokens[1] : nil
        case "DELETE": target = tokens.firstIndex { $0.isKeyword("FROM") }.flatMap { $0 + 1 < tokens.count ? tokens[$0 + 1] : nil }
        default: target = nil
        }
        return target.flatMap { isName($0) ? $0.text : nil }
    }

    // MARK: The path before the caret

    static func dot(_ path: [String], context: ScenarioContext, structure: EchoSenseDatabaseStructure, database: String?) -> ScenarioContext.Dot {
        let name = path.last ?? ""
        let lower = name.lowercased()
        if let table = context.tables.first(where: { $0.alias?.lowercased() == lower }) {
            return .init(kind: context.derived[table.name] != nil ? .derived : .alias, name: name, table: table.name)
        }
        if let key = context.derived.keys.first(where: { $0.lowercased() == lower }) { return .init(kind: .derived, name: name, table: key) }
        let databases = structure.databases
        let current = databases.first { $0.name == database } ?? databases.first
        if path.count >= 2, let db = databases.first(where: { $0.name.lowercased() == path[path.count - 2].lowercased() }),
           db.schemas.contains(where: { $0.name.lowercased() == lower }) {
            return .init(kind: .schema, name: name, database: db.name)
        }
        if let table = context.tables.first(where: { $0.name.lowercased() == lower }) { return .init(kind: .table, name: name, table: table.name) }
        if current?.schemas.contains(where: { $0.name.lowercased() == lower }) == true { return .init(kind: .schema, name: name, database: current?.name) }
        if path.count >= 2, current?.schemas.contains(where: { $0.name.lowercased() == path[path.count - 2].lowercased() }) == true {
            return .init(kind: .table, name: name, table: name)
        }
        if databases.contains(where: { $0.name.lowercased() == lower }) { return .init(kind: .database, name: name) }
        if current?.schemas.contains(where: { $0.objects.contains { $0.name.lowercased() == lower } }) == true { return .init(kind: .table, name: name, table: name) }
        return .init(kind: .unknown, name: name)
    }
}
