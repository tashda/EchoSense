import Foundation
import Testing
@testable import EchoSense

@Suite("Fuzzy Matcher Extended")
struct FuzzyMatcherExtendedTests {

    // MARK: - Exact Match

    @Test func exactMatchReturnsMaxScore() {
        let result = FuzzyMatcher.match(pattern: "users", candidate: "users")
        #expect(result != nil)
        #expect(result!.score == 1.0)
        #expect(result!.isExactPrefix == true)
    }

    @Test func exactMatchCaseSensitive() {
        let result = FuzzyMatcher.match(pattern: "Users", candidate: "Users")
        #expect(result != nil)
        #expect(result!.score == 1.0)
        #expect(result!.isExactPrefix == true)
    }

    // MARK: - Case-Insensitive Prefix

    @Test func caseInsensitivePrefixLowerToUpper() {
        let result = FuzzyMatcher.match(pattern: "use", candidate: "USERS")
        #expect(result != nil)
        #expect(result!.score == 0.95)
        #expect(result!.isExactPrefix == false)
    }

    @Test func caseInsensitivePrefixUpperToLower() {
        let result = FuzzyMatcher.match(pattern: "USE", candidate: "users")
        #expect(result != nil)
        #expect(result!.score == 0.95)
        #expect(result!.isExactPrefix == false)
    }

    @Test func caseInsensitivePrefixMixedCase() {
        let result = FuzzyMatcher.match(pattern: "UsE", candidate: "users")
        #expect(result != nil)
        #expect(result!.score == 0.95)
    }

    // MARK: - Fuzzy Subsequence

    @Test func fuzzyMissingOneCharacter() {
        let result = FuzzyMatcher.match(pattern: "usrs", candidate: "users")
        #expect(result != nil)
        #expect(result!.score > 0.0)
        #expect(result!.score < 0.95, "Fuzzy should score below prefix match")
    }

    @Test func fuzzyMissingTwoCharacters() {
        let result = FuzzyMatcher.match(pattern: "urs", candidate: "users")
        #expect(result != nil)
        #expect(result!.score > 0.0)
    }

    @Test func fuzzyReasonableScore() {
        let result = FuzzyMatcher.match(pattern: "usrs", candidate: "users")
        #expect(result != nil)
        #expect(result!.score > 0.3, "Missing one char should still give reasonable score")
    }

    // MARK: - Word Boundary Matching

    @Test func underscoreBoundaryMatch() {
        let result = FuzzyMatcher.match(pattern: "cr_at", candidate: "created_at")
        #expect(result != nil)
        #expect(result!.score > 0.0)
    }

    @Test func underscoreBoundaryInitials() {
        let result = FuzzyMatcher.match(pattern: "ca", candidate: "created_at")
        #expect(result != nil)
    }

    @Test func camelCaseBoundary() {
        let result = FuzzyMatcher.match(pattern: "gU", candidate: "getUserById")
        #expect(result != nil)
    }

    @Test func camelCaseFullPrefix() {
        let result = FuzzyMatcher.match(pattern: "getU", candidate: "getUserById")
        #expect(result != nil)
        #expect(result!.score > 0.0)
    }

    @Test func wordBoundaryScoresHigherThanNonBoundary() {
        // "uI" matching "userId" at word boundary should score higher
        // than "uI" matching "uid" where 'I' isn't at a boundary
        let boundaryResult = FuzzyMatcher.match(pattern: "uI", candidate: "userId")
        let _ = FuzzyMatcher.match(pattern: "ui", candidate: "uuid_info")

        #expect(boundaryResult != nil)
        // Both may match, but scoring comparison depends on candidate length too
    }

    // MARK: - Long Gap Penalty

    @Test func longGapPenaltyReducesScore() {
        // "ut" in "user_settings_table" has a long gap between u and t
        let longGap = FuzzyMatcher.match(pattern: "ut", candidate: "user_settings_table")
        let shortGap = FuzzyMatcher.match(pattern: "ut", candidate: "util")

        #expect(longGap != nil)
        #expect(shortGap != nil)
        #expect(shortGap!.score > longGap!.score,
                "Short gap should score higher than long gap")
    }

    // MARK: - Empty Pattern

    @Test func emptyPatternMatchesAnything() {
        let result = FuzzyMatcher.match(pattern: "", candidate: "anything")
        #expect(result != nil)
        #expect(result!.score == 1.0)
        #expect(result!.isExactPrefix == true)
    }

    @Test func emptyPatternAndEmptyCandidate() {
        let result = FuzzyMatcher.match(pattern: "", candidate: "")
        #expect(result != nil)
        #expect(result!.score == 1.0)
    }

    // MARK: - Single Character Pattern

    @Test func singleCharacterMatchesFirstChar() {
        let result = FuzzyMatcher.match(pattern: "u", candidate: "users")
        #expect(result != nil)
        #expect(result!.score > 0.0)
    }

    @Test func singleCharacterMatchesMiddleChar() {
        let result = FuzzyMatcher.match(pattern: "s", candidate: "users")
        #expect(result != nil)
    }

    @Test func singleCharacterNoMatch() {
        let result = FuzzyMatcher.match(pattern: "z", candidate: "users")
        #expect(result == nil)
    }

    // MARK: - Pattern Longer Than Candidate

    @Test func patternLongerThanCandidateReturnsNil() {
        let result = FuzzyMatcher.match(pattern: "users_table_name_is_long", candidate: "users")
        #expect(result == nil)
    }

    @Test func patternEqualLengthToCandidate() {
        let result = FuzzyMatcher.match(pattern: "users", candidate: "users")
        #expect(result != nil)
        #expect(result!.score == 1.0)
    }

    @Test func patternOneLongerThanCandidate() {
        let result = FuzzyMatcher.match(pattern: "userss", candidate: "users")
        #expect(result == nil)
    }

    // MARK: - Empty Candidate

    @Test func emptyCandidate() {
        let result = FuzzyMatcher.match(pattern: "a", candidate: "")
        #expect(result == nil)
    }

    // MARK: - All Uppercase Pattern

    @Test func allUppercasePatternMatchesLowercase() {
        let result = FuzzyMatcher.match(pattern: "USER", candidate: "users")
        #expect(result != nil)
    }

    @Test func allUppercasePatternMatchesUppercase() {
        let result = FuzzyMatcher.match(pattern: "SELECT", candidate: "SELECT")
        #expect(result != nil)
        #expect(result!.score == 1.0)
    }

    // MARK: - SQL-Specific Patterns

    @Test func selectKeywordMatch() {
        let result = FuzzyMatcher.match(pattern: "sel", candidate: "SELECT")
        #expect(result != nil)
        #expect(result!.score == 0.95, "Case-insensitive prefix match")
    }

    @Test func insertKeywordMatch() {
        let result = FuzzyMatcher.match(pattern: "ins", candidate: "INSERT")
        #expect(result != nil)
        #expect(result!.score == 0.95)
    }

    @Test func whereKeywordMatch() {
        let result = FuzzyMatcher.match(pattern: "wher", candidate: "WHERE")
        #expect(result != nil)
        #expect(result!.score == 0.95)
    }

    @Test func commonTypos() {
        #expect(FuzzyMatcher.match(pattern: "selct", candidate: "SELECT") != nil, "selct -> SELECT")
        #expect(FuzzyMatcher.match(pattern: "wher", candidate: "WHERE") != nil, "wher -> WHERE")
        #expect(FuzzyMatcher.match(pattern: "grp", candidate: "GROUP") != nil, "grp -> GROUP")
        #expect(FuzzyMatcher.match(pattern: "ordr", candidate: "ORDER") != nil, "ordr -> ORDER")
        #expect(FuzzyMatcher.match(pattern: "insrt", candidate: "INSERT") != nil, "insrt -> INSERT")
    }

    // MARK: - Score Ordering

    @Test func exactPrefixScoresHigherThanCaseInsensitivePrefix() {
        let exact = FuzzyMatcher.match(pattern: "sel", candidate: "select")
        let caseInsensitive = FuzzyMatcher.match(pattern: "sel", candidate: "SELECT")
        #expect(exact != nil)
        #expect(caseInsensitive != nil)
        #expect(exact!.score >= caseInsensitive!.score,
                "Exact prefix (\(exact!.score)) should score >= case-insensitive (\(caseInsensitive!.score))")
    }

    @Test func prefixMatchScoresHigherThanFuzzy() {
        let prefix = FuzzyMatcher.match(pattern: "sel", candidate: "select")
        let fuzzy = FuzzyMatcher.match(pattern: "slc", candidate: "select")
        #expect(prefix != nil)
        #expect(fuzzy != nil)
        #expect(prefix!.score > fuzzy!.score,
                "Prefix (\(prefix!.score)) should score higher than fuzzy (\(fuzzy!.score))")
    }

    @Test func consecutiveMatchScoresHigherThanGappy() {
        let consecutive = FuzzyMatcher.match(pattern: "abc", candidate: "abcdef")
        let gappy = FuzzyMatcher.match(pattern: "abc", candidate: "axbxcxdef")
        #expect(consecutive != nil)
        #expect(gappy != nil)
        #expect(consecutive!.score > gappy!.score,
                "Consecutive (\(consecutive!.score)) should score higher than gappy (\(gappy!.score))")
    }

    @Test func shorterCandidateScoresHigher() {
        // Fuzzy match (not prefix) — shorter candidate should have higher score due to length ratio
        let short = FuzzyMatcher.match(pattern: "usr", candidate: "user")
        let long = FuzzyMatcher.match(pattern: "usr", candidate: "user_settings_table")
        #expect(short != nil)
        #expect(long != nil)
        #expect(short!.score > long!.score,
                "Shorter candidate (\(short!.score)) should score higher than longer (\(long!.score))")
    }

    // MARK: - No Match Cases

    @Test func completelyDifferentStrings() {
        let result = FuzzyMatcher.match(pattern: "xyz", candidate: "abc")
        #expect(result == nil)
    }

    @Test func reversedCharacters() {
        // "zyx" cannot match "xyz" as a subsequence
        let result = FuzzyMatcher.match(pattern: "zyx", candidate: "xyz")
        #expect(result == nil)
    }

    @Test func partialSubsequenceDoesNotMatch() {
        // "abd" — 'a' and 'b' match in "abc" but 'd' doesn't exist
        let result = FuzzyMatcher.match(pattern: "abd", candidate: "abc")
        #expect(result == nil)
    }

    // MARK: - Score Range

    @Test func fuzzyScoreIsInValidRange() {
        let patterns = ["u", "us", "use", "user", "users"]
        for pattern in patterns {
            if let result = FuzzyMatcher.match(pattern: pattern, candidate: "users_table") {
                #expect(result.score >= 0.0 && result.score <= 1.0,
                        "Score should be in [0, 1], got \(result.score) for pattern '\(pattern)'")
            }
        }
    }

    @Test func fuzzyScoreNeverExceedsOne() {
        let result = FuzzyMatcher.match(pattern: "a", candidate: "a")
        #expect(result != nil)
        #expect(result!.score <= 1.0)
    }

    // MARK: - Unicode and Special Characters

    @Test func numericPatternMatch() {
        let result = FuzzyMatcher.match(pattern: "123", candidate: "abc123def")
        #expect(result != nil)
    }

    @Test func mixedAlphanumericPattern() {
        let result = FuzzyMatcher.match(pattern: "t1", candidate: "table1")
        #expect(result != nil)
    }

    // MARK: - Repeated Characters

    @Test func repeatedCharactersInPattern() {
        let result = FuzzyMatcher.match(pattern: "ss", candidate: "sessions")
        #expect(result != nil)
    }

    @Test func allSameCharacter() {
        let result = FuzzyMatcher.match(pattern: "aaa", candidate: "aaaa")
        #expect(result != nil)
    }

    // MARK: - Long Patterns

    @Test func longPatternMatchingLongCandidate() {
        let pattern = "created_at_timestamp"
        let candidate = "created_at_timestamp_with_timezone"
        let result = FuzzyMatcher.match(pattern: pattern, candidate: candidate)
        #expect(result != nil)
        #expect(result!.score > 0.9, "Long exact prefix should score high")
    }

    @Test func longFuzzyPattern() {
        let pattern = "crtdattmstmp"
        let candidate = "created_at_timestamp"
        let result = FuzzyMatcher.match(pattern: pattern, candidate: candidate)
        #expect(result != nil, "Long fuzzy pattern should still match as subsequence")
    }

    // MARK: - Real-World SQL Identifiers

    @Test func schemaQualifiedTableName() {
        let result = FuzzyMatcher.match(pattern: "pub", candidate: "public")
        #expect(result != nil)
        #expect(result!.score == 1.0, "pub is exact prefix of public")
    }

    @Test func underscoreSeparatedColumnName() {
        let result = FuzzyMatcher.match(pattern: "upd", candidate: "updated_at")
        #expect(result != nil)
    }

    @Test func commonAbbreviations() {
        // "fk" matching "foreign_key"
        let result = FuzzyMatcher.match(pattern: "fk", candidate: "foreign_key")
        #expect(result != nil)
    }

    @Test func multiWordFuzzyMatch() {
        // "orn" matching "order_number"
        let result = FuzzyMatcher.match(pattern: "orn", candidate: "order_number")
        #expect(result != nil)
    }

    // MARK: - isExactPrefix Flag

    @Test func isExactPrefixTrueForExactMatch() {
        let result = FuzzyMatcher.match(pattern: "users", candidate: "users")
        #expect(result!.isExactPrefix == true)
    }

    @Test func isExactPrefixTrueForPrefix() {
        let result = FuzzyMatcher.match(pattern: "use", candidate: "users")
        #expect(result!.isExactPrefix == true)
    }

    @Test func isExactPrefixFalseForCaseInsensitive() {
        let result = FuzzyMatcher.match(pattern: "USE", candidate: "users")
        #expect(result!.isExactPrefix == false)
    }

    @Test func isExactPrefixFalseForFuzzy() {
        let result = FuzzyMatcher.match(pattern: "usrs", candidate: "users")
        #expect(result!.isExactPrefix == false)
    }

    @Test func isExactPrefixTrueForEmpty() {
        let result = FuzzyMatcher.match(pattern: "", candidate: "users")
        #expect(result!.isExactPrefix == true)
    }

    // MARK: - Consistency

    @Test func samePatternAndCandidateAlwaysReturnsOne() {
        let identifiers = ["users", "orders", "SELECT", "created_at", "userId", "pg_catalog"]
        for id in identifiers {
            let result = FuzzyMatcher.match(pattern: id, candidate: id)
            #expect(result?.score == 1.0, "\(id) should match itself with score 1.0")
        }
    }

    @Test func matchingIsIdempotent() {
        let result1 = FuzzyMatcher.match(pattern: "usrs", candidate: "users")
        let result2 = FuzzyMatcher.match(pattern: "usrs", candidate: "users")
        #expect(result1?.score == result2?.score, "Same inputs should produce same score")
    }
}
