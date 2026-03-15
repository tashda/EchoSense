import Foundation

enum FuzzyMatcher {

    struct Match: Sendable {
        let score: Double
        let isExactPrefix: Bool
    }

    /// Returns `nil` if `pattern` is not a fuzzy subsequence match for `candidate`.
    /// Both strings are compared case-insensitively.
    static func match(pattern: String, candidate: String) -> Match? {
        guard !pattern.isEmpty else {
            return Match(score: 1.0, isExactPrefix: true)
        }
        guard !candidate.isEmpty else {
            return nil
        }

        let patternLower = pattern.lowercased()
        let candidateLower = candidate.lowercased()

        // Fast path: exact prefix match (case-sensitive).
        if candidate.hasPrefix(pattern) {
            return Match(score: 1.0, isExactPrefix: true)
        }

        // Fast path: case-insensitive prefix match.
        if candidateLower.hasPrefix(patternLower) {
            return Match(score: 0.95, isExactPrefix: false)
        }

        // General fuzzy subsequence matching.
        // Walk through candidate looking for each pattern character in order.
        let patternChars = Array(patternLower.unicodeScalars)
        let candidateChars = Array(candidateLower.unicodeScalars)
        let originalChars = Array(candidate.unicodeScalars)

        let patternLen = patternChars.count
        let candidateLen = candidateChars.count

        guard patternLen <= candidateLen else {
            return nil
        }

        // First pass: verify the subsequence exists at all (cheap bail-out).
        var pi = 0
        for ci in 0..<candidateLen {
            if candidateChars[ci] == patternChars[pi] {
                pi += 1
                if pi == patternLen { break }
            }
        }
        guard pi == patternLen else {
            return nil
        }

        // Second pass: greedy score computation.
        let score = computeScore(
            patternChars: patternChars,
            candidateChars: candidateChars,
            originalChars: originalChars
        )

        return Match(score: score, isExactPrefix: false)
    }

    // MARK: - Scoring

    private static func computeScore(
        patternChars: [Unicode.Scalar],
        candidateChars: [Unicode.Scalar],
        originalChars: [Unicode.Scalar]
    ) -> Double {
        let patternLen = patternChars.count
        let candidateLen = candidateChars.count

        // Weights
        let consecutiveBonus: Double = 0.15
        let wordBoundaryBonus: Double = 0.10
        let gapPenalty: Double = 0.05
        let startBonus: Double = 0.08

        var totalScore: Double = 0.0
        var pi = 0
        var consecutiveCount = 0
        var lastMatchIndex = -1

        for ci in 0..<candidateLen {
            guard pi < patternLen else { break }

            if candidateChars[ci] == patternChars[pi] {
                var charScore: Double = 1.0

                // Bonus: match at the very start of the candidate.
                if ci == 0 {
                    charScore += startBonus
                }

                // Bonus: consecutive characters matched.
                if lastMatchIndex >= 0 && ci == lastMatchIndex + 1 {
                    consecutiveCount += 1
                    charScore += consecutiveBonus * Double(consecutiveCount)
                } else {
                    consecutiveCount = 0
                }

                // Penalty: gap between matched characters.
                if lastMatchIndex >= 0 {
                    let gap = ci - lastMatchIndex - 1
                    if gap > 0 {
                        charScore -= gapPenalty * Double(min(gap, 5))
                    }
                }

                // Bonus: word boundary (after '_' or camelCase transition).
                if ci > 0 && isWordBoundary(at: ci, in: originalChars) {
                    charScore += wordBoundaryBonus
                }

                totalScore += max(charScore, 0.1)
                lastMatchIndex = ci
                pi += 1
            }
        }

        // Normalize: max possible is roughly patternLen * (1.0 + all bonuses).
        // We scale into [0, 0.9) so prefix matches always win.
        let maxPerChar: Double = 1.0 + startBonus + consecutiveBonus * Double(patternLen) + wordBoundaryBonus
        let maxPossible = Double(patternLen) * maxPerChar
        let normalized = totalScore / maxPossible

        // Length ratio: prefer shorter candidates (closer to the pattern length).
        let lengthRatio = Double(patternLen) / Double(candidateLen)

        // Combine and clamp into (0, 0.9).
        let combined = (normalized * 0.7 + lengthRatio * 0.3) * 0.9
        return min(max(combined, 0.01), 0.9)
    }

    private static func isWordBoundary(at index: Int, in chars: [Unicode.Scalar]) -> Bool {
        guard index > 0 && index < chars.count else { return false }

        let prev = chars[index - 1]
        let curr = chars[index]

        // After underscore.
        if prev == "_" { return true }

        // camelCase transition: lowercase -> uppercase.
        if CharacterSet.lowercaseLetters.contains(prev)
            && CharacterSet.uppercaseLetters.contains(curr) {
            return true
        }

        // Transition from non-letter to letter.
        if !CharacterSet.letters.contains(prev)
            && CharacterSet.letters.contains(curr) {
            return true
        }

        return false
    }
}
