import Foundation

protocol SQLSuggestionBuilderFactory {
    func makeBuilder(for dialect: SQLDialect) -> SQLSuggestionBuilder
}

protocol SQLSuggestionBuilder {
    func buildSuggestions(context: SQLContext,
                          request: SQLCompletionRequest,
                          catalog: SQLDatabaseCatalog) -> [SQLCompletionSuggestion]
}

struct DefaultSuggestionBuilderFactory: SQLSuggestionBuilderFactory {
    func makeBuilder(for dialect: SQLDialect) -> SQLSuggestionBuilder {
        return DefaultSuggestionBuilder(dialect: dialect)
    }
}

final class DefaultSuggestionBuilder: SQLSuggestionBuilder {
    private let dialect: SQLDialect
    private let keywordProvider: SQLKeywordProvider
    private let providers: [SuggestionProvider]

    init(dialect: SQLDialect, keywordProvider: SQLKeywordProvider = DefaultKeywordProvider()) {
        self.dialect = dialect
        self.keywordProvider = keywordProvider
        self.providers = [
            JoinSuggestionProvider(),
            StarExpansionProvider(),
            ColumnSuggestionProvider(),
            TableSuggestionProvider(),
            SchemaSuggestionProvider(),
            FunctionSuggestionProvider(),
            ParameterSuggestionProvider(),
            SnippetSuggestionProvider(),
            KeywordSuggestionProvider()
        ]
    }

    func buildSuggestions(context: SQLContext,
                          request: SQLCompletionRequest,
                          catalog: SQLDatabaseCatalog) -> [SQLCompletionSuggestion] {
        let identifier = IdentifierContext(token: context.currentToken)
        let quoter = SQLIdentifierQuoter.forDialect(request.dialect)
        let providerContext = ProviderContext(sqlContext: context,
                                              request: request,
                                              catalog: catalog,
                                              identifier: identifier,
                                              dialect: dialect,
                                              keywordProvider: keywordProvider,
                                              identifierQuoter: quoter)

        var collected: [SQLCompletionSuggestion] = []
        for provider in providers {
            collected.append(contentsOf: provider.suggestions(in: providerContext))
        }
        return deduplicatedAndSorted(collected)
    }

    private func deduplicatedAndSorted(_ suggestions: [SQLCompletionSuggestion]) -> [SQLCompletionSuggestion] {
        // Sort first so that when we deduplicate, we keep the highest-priority version
        let sorted = suggestions.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.priority > rhs.priority
        }

        var seen = Set<String>()
        var unique: [SQLCompletionSuggestion] = []
        for suggestion in sorted {
            if seen.insert(suggestion.id).inserted {
                unique.append(suggestion)
            }
        }

        return unique
    }
}

struct ProviderContext {
    let sqlContext: SQLContext
    let request: SQLCompletionRequest
    let catalog: SQLDatabaseCatalog
    let identifier: IdentifierContext
    let dialect: SQLDialect
    let keywordProvider: SQLKeywordProvider
    let identifierQuoter: SQLIdentifierQuoter

    var defaultSchemaLowercased: String? {
        request.defaultSchema?.lowercased()
    }

    var hasObjectKeywordContext: Bool {
        sqlContext.precedingKeyword.map { SQLContextParser.objectContextKeywords.contains($0) } ?? false
    }

    var hasColumnKeywordContext: Bool {
        sqlContext.precedingKeyword.map { SQLContextParser.columnContextKeywords.contains($0) } ?? false
    }

    func resolve(_ reference: SQLContext.TableReference) -> TableResolution? {
        if let schemaName = reference.schema {
            if let schema = catalog.schemas.first(where: { $0.name.caseInsensitiveCompare(schemaName) == .orderedSame }),
               let object = schema.objects.first(where: { $0.name.caseInsensitiveCompare(reference.name) == .orderedSame }) {
                return TableResolution(schema: schema, object: object)
            }
        } else {
            for schema in catalog.schemas {
                if let object = schema.objects.first(where: { $0.name.caseInsensitiveCompare(reference.name) == .orderedSame }) {
                    return TableResolution(schema: schema, object: object)
                }
            }
        }
        return nil
    }

    func cteColumns(for reference: SQLContext.TableReference) -> [String]? {
        let lowerAlias = reference.alias?.lowercased()
        let lowerName = reference.name.lowercased()
        if let alias = lowerAlias, let columns = sqlContext.cteColumns[alias] {
            return columns
        }
        if let columns = sqlContext.cteColumns[lowerName] {
            return columns
        }
        return nil
    }

    func cteColumns(for name: String) -> [String]? {
        sqlContext.cteColumns[name.lowercased()]
    }

    func qualify(_ components: [String]) -> String {
        identifierQuoter.qualify(components)
    }

    func qualifier(for reference: SQLContext.TableReference) -> String {
        if let alias = reference.alias {
            return alias
        }
        return identifierQuoter.quoteIfNeeded(reference.name)
    }

    func qualifier(for reference: SQLContext.TableReference, candidate: String) -> String {
        if let alias = reference.alias,
           alias.caseInsensitiveCompare(candidate) == .orderedSame {
            return alias
        }
        return identifierQuoter.quoteIfNeeded(candidate)
    }

    func quotedColumn(_ name: String) -> String {
        identifierQuoter.quoteIfNeeded(name)
    }
}

struct IdentifierContext {
    let rawToken: String
    let trimmedToken: String
    let prefix: String
    let lowercasePrefix: String
    let precedingSegments: [String]
    let precedingLowercased: [String]
    let isTrailingDot: Bool

    init(token: String) {
        rawToken = token
        trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmedToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if let last = components.last {
            prefix = last
        } else {
            prefix = ""
        }
        lowercasePrefix = prefix.lowercased()
        isTrailingDot = trimmedToken.last == "."
        let preceding = components.isEmpty ? [] : Array(components.dropLast())
        precedingSegments = preceding
        precedingLowercased = preceding.map { $0.lowercased() }
    }

    func matchesPrefix(of candidate: String) -> Bool {
        guard !lowercasePrefix.isEmpty else { return true }
        return candidate.lowercased().hasPrefix(lowercasePrefix)
    }

    /// Returns a fuzzy match score (0.0–1.0) or nil if no match.
    /// Prefix matches always win (score 0.95–1.0), fuzzy is lower.
    func fuzzyScore(for candidate: String) -> Double? {
        guard !lowercasePrefix.isEmpty else { return 1.0 }
        return FuzzyMatcher.match(pattern: lowercasePrefix, candidate: candidate)?.score
    }
}

struct TableResolution {
    let schema: SQLSchema
    let object: SQLObject
}

protocol SuggestionProvider {
    func suggestions(in context: ProviderContext) -> [SQLCompletionSuggestion]
}
