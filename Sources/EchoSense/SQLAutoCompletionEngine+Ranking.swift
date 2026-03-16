import Foundation

extension SQLAutoCompletionEngine {

    private enum ClauseRelevance: Int {
        case primary = 3
        case secondary = 2
        case peripheral = 1
        case irrelevant = 0
    }

    func rankSuggestions(_ suggestions: [SQLAutoCompletionSuggestion],
                         query: SQLAutoCompletionQuery,
                         context: SQLEditorCompletionContext) -> [SQLAutoCompletionSuggestion] {
        guard !suggestions.isEmpty else { return suggestions }

        var ranked: [(index: Int, suggestion: SQLAutoCompletionSuggestion, score: Double, relevance: ClauseRelevance)] = []
        ranked.reserveCapacity(suggestions.count)
        let promoteClauseKeywords = shouldPromoteClauseKeywords(query: query)

        for (index, suggestion) in suggestions.enumerated() {
            let (relevance, boost) = clauseBoost(for: query.clause, kind: suggestion.kind)

            switch aggressiveness {
            case .focused:
                if relevance == .peripheral || relevance == .irrelevant {
                    continue
                }
            case .balanced:
                if relevance == .irrelevant {
                    continue
                }
            case .eager:
                break
            }

            var score = Double(suggestion.priority) + boost

            // Apply history boost to ALL suggestions, not just history-sourced ones.
            // This makes frequently-picked items float to the top regardless of source.
            let historyBoost = historyStore.weight(for: suggestion, context: context)
            if historyBoost > 0 {
                score += historyBoost * (suggestion.source == .history ? 1.0 : 0.5)
            }

            if suggestion.source == .fallback {
                score -= 40
            }

            if suggestion.kind == .column,
               let focus = query.focusTable,
               matchesFocus(suggestion, focus: focus) {
                score += 80
            }

            if suggestion.kind == .column {
                score += aliasBonus(for: suggestion, query: query)
            }

            if suggestion.kind == .keyword {
                if promoteClauseKeywords {
                    score += clauseKeywordPromotionBonus(for: suggestion, query: query)
                } else {
                    score -= 90
                }
            } else if promoteClauseKeywords &&
                        SQLAutoCompletionEngine.relationLikeKinds.contains(suggestion.kind) {
                score -= 140
            }

            // Boost suggestions whose title starts with the typed prefix.
            // This ensures "public" ranks above "player_dummy" when typing "pu".
            score += prefixMatchBoost(for: suggestion, query: query)

            ranked.append((index, suggestion, score, relevance))
        }

        ranked.sort { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.relevance.rawValue == rhs.relevance.rawValue {
                    let comparison = lhs.suggestion.title.localizedCaseInsensitiveCompare(rhs.suggestion.title)
                    if comparison == .orderedSame {
                        return lhs.index < rhs.index
                    }
                    return comparison == .orderedAscending
                }
                return lhs.relevance.rawValue > rhs.relevance.rawValue
            }
            return lhs.score > rhs.score
        }

        return ranked.map { $0.suggestion }
    }

    private func shouldPromoteClauseKeywords(query: SQLAutoCompletionQuery) -> Bool {
        // Promote clause-continuation keywords (WHERE, JOIN, ORDER BY, etc.)
        // when in FROM clause with tables already referenced and user isn't
        // actively typing a table name or after a comma (which means more tables).
        if query.clause != .from { return false }
        if !query.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if !query.pathComponents.isEmpty { return false }
        if query.precedingCharacter == "," { return false }
        // After object-context keywords like FROM/JOIN, user expects tables not keywords
        if let keyword = query.precedingKeyword,
           SQLAutoCompletionEngine.objectContextKeywords.contains(keyword) {
            // Exception: if tables are already in scope after this keyword,
            // e.g., "FROM users " — the space moved past the table, show keywords
            let isImmediatelyAfterKeyword = query.tablesInScope.isEmpty
            if isImmediatelyAfterKeyword {
                return false
            }
        }
        return !query.tablesInScope.isEmpty
    }

    private func clauseKeywordPromotionBonus(for suggestion: SQLAutoCompletionSuggestion,
                                              query: SQLAutoCompletionQuery) -> Double {
        let normalized = suggestion.title.lowercased()

        // Demote keywords that already appear in the query's context
        if keywordAlreadyPresent(normalized, in: query) {
            return -200.0
        }

        if let orderIndex = SQLAutoCompletionEngine.postObjectClauseKeywordOrder.firstIndex(of: normalized) {
            let base = 1900.0
            return base - Double(orderIndex) * 25.0
        }
        return 900.0
    }

    /// Checks if a keyword is likely already present in the query text.
    /// Used to avoid suggesting WHERE when WHERE already exists, etc.
    private func keywordAlreadyPresent(_ keyword: String, in query: SQLAutoCompletionQuery) -> Bool {
        // Check tables in scope to infer what clauses are already present.
        // If the query has tables in scope and the keyword is "from", it's already there.
        switch keyword {
        case "from":
            return !query.tablesInScope.isEmpty
        case "where":
            // If we're in FROM clause and it was preceded by WHERE-like context, skip
            return query.clause == .whereClause
        default:
            return false
        }
    }

    private func clauseBoost(for clause: SQLClause,
                             kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch clause {
        case .selectList, .whereClause, .groupBy, .orderBy, .having, .values, .updateSet:
            return columnContextBoost(for: kind)
        case .joinCondition:
            return joinConditionBoost(for: kind)
        case .from, .joinTarget, .insertColumns, .deleteWhere, .withCTE:
            return objectContextBoost(for: kind)
        case .limit, .offset:
            return limitContextBoost(for: kind)
        case .unknown:
            return fallbackBoost(for: kind)
        }
    }

    private func columnContextBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .column:
            return (.primary, 520)
        case .function, .snippet, .parameter:
            return (.secondary, 260)
        case .keyword:
            return (.peripheral, -220)
        case .table, .view, .materializedView, .schema, .join:
            return (.peripheral, -260)
        @unknown default:
            return (.peripheral, -200)
        }
    }

    private func joinConditionBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .join:
            return (.primary, 560)
        case .column:
            return (.primary, 500)
        case .function, .snippet, .parameter:
            return (.secondary, 220)
        case .keyword:
            return (.peripheral, -260)
        case .table, .view, .materializedView, .schema:
            return (.peripheral, -280)
        }
    }

    private func objectContextBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .table, .view, .materializedView:
            return (.primary, 520)
        case .join:
            return (.primary, 500)
        case .schema:
            return (.secondary, 200)
        case .snippet, .parameter:
            return (.secondary, 180)
        case .column, .function:
            return (.peripheral, -220)
        case .keyword:
            return (.peripheral, -260)
        }
    }

    private func limitContextBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .keyword:
            return (.primary, 420)
        case .parameter, .snippet:
            return (.secondary, 160)
        case .column, .table, .view, .materializedView, .function, .schema, .join:
            return (.peripheral, -200)
        }
    }

    private func fallbackBoost(for kind: SQLAutoCompletionKind) -> (ClauseRelevance, Double) {
        switch kind {
        case .column, .table, .view, .materializedView, .function:
            return (.secondary, 140)
        case .keyword, .snippet, .parameter, .schema:
            return (.peripheral, -120)
        case .join:
            return (.peripheral, -180)
        }
    }

    /// Boosts suggestions that start with the typed prefix over substring matches.
    /// An exact prefix match gets a significant boost so that "public" ranks above
    /// "player_dummy" when the user types "pu" in a FROM clause.
    private func prefixMatchBoost(for suggestion: SQLAutoCompletionSuggestion,
                                   query: SQLAutoCompletionQuery) -> Double {
        let typed = query.normalizedPrefix
        guard !typed.isEmpty else { return 0 }
        let typedLower = typed.lowercased()
        let titleLower = suggestion.title.lowercased()

        if titleLower.hasPrefix(typedLower) {
            // Stronger boost the more characters match proportionally
            let matchRatio = Double(typedLower.count) / Double(max(titleLower.count, 1))
            return 150 + matchRatio * 100
        }

        // Substring match (contains but doesn't start with) gets no boost
        return 0
    }

    private func matchesFocus(_ suggestion: SQLAutoCompletionSuggestion,
                              focus: SQLAutoCompletionTableFocus) -> Bool {
        guard let origin = suggestion.origin else { return false }

        if let object = origin.object,
           object.caseInsensitiveCompare(focus.name) != .orderedSame {
            return false
        }

        if let focusSchema = focus.schema,
           let originSchema = origin.schema,
           focusSchema.caseInsensitiveCompare(originSchema) != .orderedSame {
            return false
        }

        if origin.object == nil {
            return false
        }

        return true
    }

    private func aliasBonus(for suggestion: SQLAutoCompletionSuggestion,
                            query: SQLAutoCompletionQuery) -> Double {
        guard suggestion.kind == .column else { return 0 }
        guard !query.tablesInScope.isEmpty else { return 0 }

        let insertLower = suggestion.insertText.lowercased()
        for table in query.tablesInScope {
            if let alias = table.alias?.lowercased(),
               insertLower.hasPrefix("\(alias).") {
                return 60
            }
        }

        return 0
    }

    func injectHistorySuggestions(base: [SQLAutoCompletionSuggestion],
                                  query: SQLAutoCompletionQuery,
                                  context: SQLEditorCompletionContext) -> [SQLAutoCompletionSuggestion] {
        guard includeHistorySuggestions else { return base }
        let history = historyStore.suggestions(matching: query.normalizedPrefix,
                                               context: context,
                                               limit: 6)
            .filter { matchesQuery($0, query: query) }
        guard !history.isEmpty else { return base }

        var seen = Set<String>()
        var combined: [SQLAutoCompletionSuggestion] = []

        // Add live suggestions first — prefer live versions (fresher metadata).
        // History boost is applied in rankSuggestions() via historyStore.weight().
        for suggestion in base {
            let key = suggestion.id.lowercased()
            if seen.insert(key).inserted {
                combined.append(suggestion)
            }
        }

        // Add history-only suggestions that don't have a live equivalent
        for rawSuggestion in history {
            let suggestion = refinedHistorySuggestion(rawSuggestion.withSource(.history),
                                                      query: query)
            let key = suggestion.id.lowercased()
            if seen.insert(key).inserted {
                combined.append(suggestion)
            }
        }

        return combined
    }

    private func refinedHistorySuggestion(_ suggestion: SQLAutoCompletionSuggestion,
                                          query: SQLAutoCompletionQuery) -> SQLAutoCompletionSuggestion {
        guard let originalKind = mapBackKind(suggestion.kind) else {
            return suggestion
        }

        let baseInsertText: String
        if let originObject = suggestion.origin?.object, !originObject.isEmpty {
            baseInsertText = originObject
        } else {
            baseInsertText = suggestion.insertText
        }

        let completionSuggestion = SQLCompletionSuggestion(id: suggestion.id,
                                                           title: suggestion.title,
                                                           subtitle: suggestion.subtitle,
                                                           detail: suggestion.detail,
                                                           insertText: baseInsertText,
                                                           kind: originalKind,
                                                           priority: suggestion.priority)

        let adjustedInsert = makeInsertText(from: completionSuggestion,
                                            mappedKind: suggestion.kind,
                                            query: query,
                                            origin: suggestion.origin)
        return suggestion.withInsertText(adjustedInsert)
    }

}
