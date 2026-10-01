import Foundation

/// What the results footer says about the selected cells (Design/05-components.md › Results card,
/// round 41.2): the pill shows only the count (SP3); its popover lists the exact figures (FG1), and
/// for text only the count, the distinct values and the empty cells (TX0).
public struct GridSelectionSummary: Equatable, Sendable {
    public let cellCount: Int
    /// Cells holding a plain decimal number; the numeric figures are over these.
    public let numericCount: Int
    public let sum: Decimal
    public let minimum: Decimal?
    public let maximum: Decimal?
    public let median: Decimal?
    /// Different non-NULL values.
    public let distinctCount: Int
    /// NULL cells.
    public let emptyCount: Int
    /// The most fraction digits any selected number has, so the figures keep them.
    public let fractionDigits: Int
    /// False when the selection was too large to add up; only the count is shown then.
    public let isComplete: Bool
    /// The column the cells are in, when they are all in one (the popover's title).
    public var columnName: String?

    public init(cellCount: Int, numericCount: Int = 0, sum: Decimal = 0, minimum: Decimal? = nil, maximum: Decimal? = nil,
                median: Decimal? = nil, distinctCount: Int = 0, emptyCount: Int = 0, fractionDigits: Int = 0,
                isComplete: Bool, columnName: String? = nil) {
        self.cellCount = cellCount; self.numericCount = numericCount; self.sum = sum
        self.minimum = minimum; self.maximum = maximum; self.median = median
        self.distinctCount = distinctCount; self.emptyCount = emptyCount
        self.fractionDigits = fractionDigits; self.isComplete = isComplete; self.columnName = columnName
    }

    public var average: Decimal? { numericCount > 0 ? sum / Decimal(numericCount) : nil }

    /// Whether the selection is numbers: at least two, as the sum of one number says nothing.
    public var isNumeric: Bool { isComplete && numericCount > 1 }

    /// Selections larger than this show a count only, so selecting a huge column stays instant.
    public static let maximumSummedCells = 50_000

    /// Adds up `values`; non-numeric and NULL cells count as cells but not towards the figures.
    public static func summarize(_ values: some Sequence<String?>, cellCount: Int, columnName: String? = nil) -> GridSelectionSummary {
        guard cellCount <= maximumSummedCells else {
            return GridSelectionSummary(cellCount: cellCount, isComplete: false, columnName: columnName)
        }
        var numbers: [(approximate: Double, exact: Decimal)] = []
        var distinct = Set<String>()
        var emptyCount = 0
        var sum: Decimal = 0
        var fractionDigits = 0
        for value in values {
            guard let value else { emptyCount += 1; continue }
            distinct.insert(value)
            guard let number = decimalNumber(value) else { continue }
            numbers.append(number)
            sum += number.exact
            fractionDigits = max(fractionDigits, -min(number.exact.exponent, 0))
        }
        // Sorted on the Double, which is quick; the figures come from the exact values.
        numbers.sort { $0.approximate < $1.approximate }
        var median: Decimal?
        if !numbers.isEmpty {
            let middle = numbers.count / 2
            median = numbers.count.isMultiple(of: 2) ? (numbers[middle - 1].exact + numbers[middle].exact) / 2 : numbers[middle].exact
        }
        return GridSelectionSummary(
            cellCount: cellCount, numericCount: numbers.count, sum: sum,
            minimum: numbers.first?.exact, maximum: numbers.last?.exact, median: median,
            distinctCount: distinct.count, emptyCount: emptyCount, fractionDigits: fractionDigits,
            isComplete: true, columnName: columnName)
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// A plain decimal (`12`, `-1.5`, `1e3`); hexadecimal, `nan` and `inf` are text.
    private static func decimalNumber(_ value: String) -> (approximate: Double, exact: Decimal)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ "+-.0123456789eE".contains($0) }),
              let number = Double(trimmed), number.isFinite,
              let exact = Decimal(string: trimmed, locale: posix) else { return nil }
        return (number, exact)
    }

    // MARK: - Text

    /// The pill: "89 cells" (SP3).
    public var text: String { text(locale: .autoupdatingCurrent) }

    /// The same, with numbers written for `locale` (scenarios use a fixed one).
    public func text(locale: Locale) -> String {
        cellCount == 1 ? "1 cell" : "\(cellCount.formatted(.number.locale(locale))) cells"
    }

    /// One line of the popover: a label and its exact value as shown.
    public struct Figure: Equatable, Sendable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }
    }

    /// The popover's figures (FG1): Count, Sum, Average, Min, Max, Median, Distinct and Empty for
    /// numbers; Count, Distinct and Empty for text (TX0); only Count when too many to add up.
    public func figures(locale: Locale = .autoupdatingCurrent) -> [Figure] {
        var figures = [Figure(label: "Count", value: cellCount.formatted(.number.locale(locale)))]
        guard isComplete else { return figures }
        if isNumeric {
            let exact = Decimal.FormatStyle.number.precision(.fractionLength(0...fractionDigits)).locale(locale)
            let derived = Decimal.FormatStyle.number.precision(.fractionLength(0...max(fractionDigits, 2))).locale(locale)
            figures.append(Figure(label: "Sum", value: sum.formatted(exact)))
            if let average { figures.append(Figure(label: "Average", value: average.formatted(derived))) }
            if let minimum { figures.append(Figure(label: "Min", value: minimum.formatted(exact))) }
            if let maximum { figures.append(Figure(label: "Max", value: maximum.formatted(exact))) }
            if let median { figures.append(Figure(label: "Median", value: median.formatted(derived))) }
        }
        figures.append(Figure(label: "Distinct", value: distinctCount.formatted(.number.locale(locale))))
        figures.append(Figure(label: "Empty", value: emptyCount.formatted(.number.locale(locale))))
        return figures
    }

    /// Every figure as "Label<tab>value" lines, for Copy All (pastes as two columns).
    public func copyAllText(locale: Locale = .autoupdatingCurrent) -> String {
        figures(locale: locale).map { "\($0.label)\t\($0.value)" }.joined(separator: "\n")
    }
}
