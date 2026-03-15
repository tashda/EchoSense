import Foundation
import Testing
@testable import EchoSense

// MARK: - Exact Prefix Matching

@Test
func exactPrefixMatchReturnsHighestScore() {
    let result = FuzzyMatcher.match(pattern: "users", candidate: "users")
    #expect(result != nil)
    #expect(result!.score == 1.0)
    #expect(result!.isExactPrefix == true)
}

@Test
func exactPrefixStartReturnsHighScore() {
    let result = FuzzyMatcher.match(pattern: "use", candidate: "users")
    #expect(result != nil)
    #expect(result!.score == 1.0)
    #expect(result!.isExactPrefix == true)
}

@Test
func caseInsensitivePrefixMatch() {
    let result = FuzzyMatcher.match(pattern: "USE", candidate: "users")
    #expect(result != nil)
    #expect(result!.score == 0.95)
    #expect(result!.isExactPrefix == false)
}

// MARK: - Fuzzy Matching

@Test
func fuzzySubsequenceMatch() {
    // "usrs" should match "users" (missing 'e')
    let result = FuzzyMatcher.match(pattern: "usrs", candidate: "users")
    #expect(result != nil)
    #expect(result!.score > 0.0)
    #expect(result!.score < 0.95)
}

@Test
func fuzzyInitialsMatch() {
    // "uo" should match "user_orders" (word boundary match)
    let result = FuzzyMatcher.match(pattern: "uo", candidate: "user_orders")
    #expect(result != nil)
    #expect(result!.score > 0.0)
}

@Test
func noMatchReturnsNil() {
    let result = FuzzyMatcher.match(pattern: "xyz", candidate: "users")
    #expect(result == nil)
}

@Test
func emptyPatternMatchesAnything() {
    let result = FuzzyMatcher.match(pattern: "", candidate: "users")
    #expect(result != nil)
    #expect(result!.score == 1.0)
}

@Test
func emptyPatternAndCandidateMatches() {
    let result = FuzzyMatcher.match(pattern: "", candidate: "")
    #expect(result != nil)
    #expect(result!.score == 1.0)
}

@Test
func emptyCandidate() {
    let result = FuzzyMatcher.match(pattern: "a", candidate: "")
    #expect(result == nil)
}

@Test
func patternLongerThanCandidate() {
    let result = FuzzyMatcher.match(pattern: "users_table_name", candidate: "users")
    #expect(result == nil)
}

// MARK: - Scoring Priority

@Test
func prefixMatchScoresHigherThanFuzzy() {
    let prefix = FuzzyMatcher.match(pattern: "sel", candidate: "select")
    let fuzzy = FuzzyMatcher.match(pattern: "slc", candidate: "select")
    #expect(prefix != nil)
    #expect(fuzzy != nil)
    #expect(prefix!.score > fuzzy!.score)
}

@Test
func consecutiveMatchScoresHigher() {
    // "abc" in "abcdef" (all consecutive) should score higher than "abc" in "axbxcx" (gaps)
    let consecutive = FuzzyMatcher.match(pattern: "abc", candidate: "abcdef")
    let gappy = FuzzyMatcher.match(pattern: "abc", candidate: "axbxcxdef")
    #expect(consecutive != nil)
    #expect(gappy != nil)
    #expect(consecutive!.score > gappy!.score)
}

// MARK: - SQL-Specific Patterns

@Test
func matchesSQLKeywordTypos() {
    // Common typo patterns
    #expect(FuzzyMatcher.match(pattern: "selct", candidate: "select") != nil)
    #expect(FuzzyMatcher.match(pattern: "wher", candidate: "where") != nil)
    #expect(FuzzyMatcher.match(pattern: "grp", candidate: "group") != nil)
}

@Test
func matchesCamelCaseWordBoundaries() {
    let result = FuzzyMatcher.match(pattern: "uI", candidate: "userId")
    #expect(result != nil)
}

@Test
func matchesUnderscoreWordBoundaries() {
    let result = FuzzyMatcher.match(pattern: "cr", candidate: "created_at")
    #expect(result != nil)
}
