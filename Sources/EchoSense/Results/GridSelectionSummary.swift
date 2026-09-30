import Foundation

/// What the results footer says about the selected cells (Design/05-components.md › Results card,
/// plan R5): how many, and the sum and average of the numeric ones.
public struct GridSelectionSummary: Equatable, Sendable {
    public let cellCount: Int
    public let numericCount: Int
    public let sum: Double
    /// False when the selection was too large to add up; only the count is shown then.
    public let isComplete: Bool

    public init(cellCount: Int, numericCount: Int, sum: Double, isComplete: Bool) {
        self.cellCount = cellCount; self.numericCount = numericCount; self.sum = sum; self.isComplete = isComplete
    }

    public var average: Double? { numericCount > 0 ? sum / Double(numericCount) : nil }

    /// Selections larger than this show a count only, so selecting a huge column stays instant.
    public static let maximumSummedCells = 50_000

    /// Adds up `values`; non-numeric and NULL cells count as cells but not towards the sum.
    public static func summarize(_ values: some Sequence<String?>, cellCount: Int) -> GridSelectionSummary {
        guard cellCount <= maximumSummedCells else {
            return GridSelectionSummary(cellCount: cellCount, numericCount: 0, sum: 0, isComplete: false)
        }
        var numericCount = 0
        var sum = 0.0
        for value in values {
            guard let value, let number = decimalNumber(value) else { continue }
            numericCount += 1
            sum += number
        }
        return GridSelectionSummary(cellCount: cellCount, numericCount: numericCount, sum: sum, isComplete: true)
    }

    /// A plain decimal (`12`, `-1.5`, `1e3`); hexadecimal, `nan` and `inf` are text.
    private static func decimalNumber(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ "+-.0123456789eE".contains($0) }),
              let number = Double(trimmed), number.isFinite else { return nil }
        return number
    }

    /// "3 cells · Sum 1,234 · Avg 411.33", or just the count when nothing numeric is selected.
    public var text: String { text(locale: .autoupdatingCurrent) }

    /// The same, with numbers written for `locale` (scenarios use a fixed one).
    public func text(locale: Locale) -> String {
        let count = cellCount.formatted(.number.locale(locale))
        var parts = [cellCount == 1 ? "1 cell" : "\(count) cells"]
        if isComplete, numericCount > 1, let average {
            let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...2)).locale(locale)
            parts.append("Sum \(sum.formatted(style))")
            parts.append("Avg \(average.formatted(style))")
        }
        return parts.joined(separator: " · ")
    }
}
