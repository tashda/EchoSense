import Foundation
import Testing
@testable import EchoSense

// MARK: - Basic Token Types

@Test
func tokenizesSimpleSelect() {
    let tokens = SQLTokenizer.tokenize("SELECT id FROM users" as NSString)
    let nonWhitespace = tokens.filter { $0.kind != .whitespace }

    #expect(nonWhitespace.count == 4)
    #expect(nonWhitespace[0].kind == .keyword)
    #expect(nonWhitespace[0].text == "SELECT")
    #expect(nonWhitespace[1].kind == .identifier)
    #expect(nonWhitespace[1].text == "id")
    #expect(nonWhitespace[2].kind == .keyword)
    #expect(nonWhitespace[2].text == "FROM")
    #expect(nonWhitespace[3].kind == .identifier)
    #expect(nonWhitespace[3].text == "users")
}

@Test
func tokenizesKeywordsAreCaseInsensitive() {
    let tokens = SQLTokenizer.tokenize("select FROM Where" as NSString)
    let nonWhitespace = tokens.filter { $0.kind != .whitespace }

    #expect(nonWhitespace.allSatisfy { $0.kind == .keyword })
}

@Test
func tokenizesIdentifiers() {
    let tokens = SQLTokenizer.tokenize("my_table column1 _private" as NSString)
    let nonWhitespace = tokens.filter { $0.kind != .whitespace }

    #expect(nonWhitespace.count == 3)
    #expect(nonWhitespace.allSatisfy { $0.kind == .identifier })
}

// MARK: - String Literals & Quoted Identifiers

@Test
func tokenizesSingleQuotedString() {
    let tokens = SQLTokenizer.tokenize("WHERE name = 'hello'" as NSString)
    let stringTokens = tokens.filter { $0.kind == .stringLiteral }

    #expect(stringTokens.count == 1)
    #expect(stringTokens[0].text == "'hello'")
}

@Test
func tokenizesEscapedSingleQuote() {
    let tokens = SQLTokenizer.tokenize("'it''s'" as NSString)

    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .stringLiteral)
    #expect(tokens[0].text == "'it''s'")
}

@Test
func tokenizesDoubleQuotedIdentifier() {
    let tokens = SQLTokenizer.tokenize("\"UserName\"" as NSString)

    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .quotedIdentifier)
    #expect(tokens[0].text == "\"UserName\"")
}

@Test
func tokenizesBacktickIdentifier() {
    let tokens = SQLTokenizer.tokenize("`table name`" as NSString)

    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .quotedIdentifier)
    #expect(tokens[0].text == "`table name`")
}

@Test
func tokenizesBracketIdentifier() {
    let tokens = SQLTokenizer.tokenize("[Order Details]" as NSString)

    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .quotedIdentifier)
    #expect(tokens[0].text == "[Order Details]")
}

// MARK: - Numbers

@Test
func tokenizesNumbers() {
    let tokens = SQLTokenizer.tokenize("LIMIT 100" as NSString)
    let numberTokens = tokens.filter { $0.kind == .number }

    #expect(numberTokens.count == 1)
    #expect(numberTokens[0].text == "100")
}

// MARK: - Comments

@Test
func tokenizesLineComment() {
    let tokens = SQLTokenizer.tokenize("SELECT -- this is a comment\nid" as NSString)
    let commentTokens = tokens.filter { $0.kind == .comment }

    #expect(commentTokens.count == 1)
    #expect(commentTokens[0].text == "-- this is a comment")
}

@Test
func tokenizesBlockComment() {
    let tokens = SQLTokenizer.tokenize("SELECT /* block */ id" as NSString)
    let commentTokens = tokens.filter { $0.kind == .comment }

    #expect(commentTokens.count == 1)
    #expect(commentTokens[0].text == "/* block */")
}

// MARK: - Parameters

@Test
func tokenizesPostgresParameter() {
    let tokens = SQLTokenizer.tokenize("$1" as NSString)

    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .parameter)
    #expect(tokens[0].text == "$1")
}

@Test
func tokenizesSQLServerParameter() {
    let tokens = SQLTokenizer.tokenize("@p1" as NSString)

    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .parameter)
    #expect(tokens[0].text == "@p1")
}

@Test
func tokenizesNamedParameter() {
    let tokens = SQLTokenizer.tokenize(":user_id" as NSString)

    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .parameter)
    #expect(tokens[0].text == ":user_id")
}

// MARK: - Operators

@Test
func tokenizesSimpleOperators() {
    let tokens = SQLTokenizer.tokenize("a + b" as NSString)
    let opTokens = tokens.filter { $0.kind == .operatorSymbol }

    #expect(opTokens.count == 1)
    #expect(opTokens[0].text == "+")
}

@Test
func tokenizesCompoundOperators() {
    let tokens = SQLTokenizer.tokenize("a <= b" as NSString)
    let opTokens = tokens.filter { $0.kind == .operatorSymbol }

    #expect(opTokens.count == 1)
    #expect(opTokens[0].text == "<=")
}

@Test
func tokenizesNotEqualOperator() {
    let tokens = SQLTokenizer.tokenize("a != b" as NSString)
    let opTokens = tokens.filter { $0.kind == .operatorSymbol }

    #expect(opTokens.count == 1)
    #expect(opTokens[0].text == "!=")
}

@Test
func tokenizesAngleBracketNotEqual() {
    let tokens = SQLTokenizer.tokenize("a <> b" as NSString)
    let opTokens = tokens.filter { $0.kind == .operatorSymbol }

    #expect(opTokens.count == 1)
    #expect(opTokens[0].text == "<>")
}

// MARK: - Punctuation

@Test
func tokenizesPunctuation() {
    let tokens = SQLTokenizer.tokenize("(a, b)" as NSString)
    let punctTokens = tokens.filter { $0.kind == .punctuation }

    #expect(punctTokens.count == 3) // (, comma, )
    #expect(punctTokens[0].text == "(")
    #expect(punctTokens[1].text == ",")
    #expect(punctTokens[2].text == ")")
}

// MARK: - Ranges

@Test
func tokenRangesAreCorrect() {
    let text = "SELECT id" as NSString
    let tokens = SQLTokenizer.tokenize(text)

    #expect(tokens[0].range == NSRange(location: 0, length: 6)) // SELECT
    #expect(tokens[1].range == NSRange(location: 6, length: 1)) // space
    #expect(tokens[2].range == NSRange(location: 7, length: 2)) // id
}

// MARK: - Lowercased

@Test
func lowercasedPropertyWorks() {
    let tokens = SQLTokenizer.tokenize("SELECT" as NSString)

    #expect(tokens[0].lowercased == "select")
}

// MARK: - Complex Queries

@Test
func tokenizesComplexQuery() {
    let sql = "SELECT u.name, COUNT(*) FROM users u WHERE u.active = 1 GROUP BY u.name" as NSString
    let tokens = SQLTokenizer.tokenize(sql)
    let nonWhitespace = tokens.filter { $0.kind != .whitespace }

    #expect(nonWhitespace.count > 10)
    let keywords = nonWhitespace.filter { $0.kind == .keyword }
    let keywordTexts = keywords.map { $0.lowercased }
    #expect(keywordTexts.contains("select"))
    #expect(keywordTexts.contains("from"))
    #expect(keywordTexts.contains("where"))
    #expect(keywordTexts.contains("group"))
    #expect(keywordTexts.contains("by"))
}

@Test
func tokenizesEmptyString() {
    let tokens = SQLTokenizer.tokenize("" as NSString)
    #expect(tokens.isEmpty)
}

@Test
func tokenizesWhitespaceOnly() {
    let tokens = SQLTokenizer.tokenize("   \n\t  " as NSString)
    #expect(tokens.count == 1)
    #expect(tokens[0].kind == .whitespace)
}
