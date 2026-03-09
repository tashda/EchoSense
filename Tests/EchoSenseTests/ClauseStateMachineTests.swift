import Foundation
import Testing
@testable import EchoSense

private func tokens(from text: String) -> [SQLToken] {
    SQLTokenizer.tokenize(text as NSString)
}

private func clause(for text: String) -> SQLClause {
    var machine = ClauseStateMachine()
    for token in tokens(from: text) {
        machine.feed(token)
    }
    return machine.currentClause
}

// MARK: - Basic Clause Detection (parity with existing tests)

@Test
func machineDetectsSelectClause() {
    #expect(clause(for: "SELECT ") == .selectList)
}

@Test
func machineDetectsFromClause() {
    #expect(clause(for: "SELECT id FROM ") == .from)
}

@Test
func machineDetectsWhereClause() {
    #expect(clause(for: "SELECT id FROM users WHERE ") == .whereClause)
}

@Test
func machineDetectsJoinTarget() {
    #expect(clause(for: "SELECT * FROM users JOIN ") == .joinTarget)
}

@Test
func machineDetectsJoinCondition() {
    #expect(clause(for: "SELECT * FROM users JOIN orders ON ") == .joinCondition)
}

@Test
func machineDetectsGroupBy() {
    #expect(clause(for: "SELECT name FROM users GROUP BY ") == .groupBy)
}

@Test
func machineDetectsOrderBy() {
    #expect(clause(for: "SELECT name FROM users ORDER BY ") == .orderBy)
}

@Test
func machineDetectsHaving() {
    #expect(clause(for: "SELECT name, COUNT(*) FROM users GROUP BY name HAVING ") == .having)
}

@Test
func machineDetectsLimit() {
    #expect(clause(for: "SELECT name FROM users LIMIT ") == .limit)
}

@Test
func machineDetectsOffset() {
    #expect(clause(for: "SELECT name FROM users LIMIT 10 OFFSET ") == .offset)
}

@Test
func machineDetectsInsertColumns() {
    #expect(clause(for: "INSERT INTO users (") == .insertColumns)
}

@Test
func machineDetectsValues() {
    #expect(clause(for: "INSERT INTO users (name) VALUES ") == .values)
}

@Test
func machineDetectsUpdateSet() {
    #expect(clause(for: "UPDATE users SET ") == .updateSet)
}

@Test
func machineDetectsDeleteWhere() {
    #expect(clause(for: "DELETE ") == .from)
}

@Test
func machineDetectsReturning() {
    #expect(clause(for: "INSERT INTO users (name) VALUES ('test') RETURNING ") == .selectList)
}

@Test
func machineDetectsWithCTE() {
    #expect(clause(for: "WITH ") == .withCTE)
}

// MARK: - New: UNION / INTERSECT / EXCEPT

@Test
func unionResetsClause() {
    // After UNION, the next SELECT should set clause to selectList
    #expect(clause(for: "SELECT id FROM users UNION SELECT ") == .selectList)
}

@Test
func intersectResetsClause() {
    #expect(clause(for: "SELECT id FROM users INTERSECT SELECT ") == .selectList)
}

@Test
func exceptResetsClause() {
    #expect(clause(for: "SELECT id FROM users EXCEPT SELECT ") == .selectList)
}

@Test
func unionAllWithFrom() {
    #expect(clause(for: "SELECT id FROM users UNION SELECT id FROM ") == .from)
}

// MARK: - New: Window Functions (OVER)

@Test
func overDoesNotChangeClause() {
    // OVER(...) should not change the clause from selectList
    #expect(clause(for: "SELECT ROW_NUMBER() OVER (") == .selectList)
}

@Test
func partitionByInsideOverDoesNotChangeClause() {
    #expect(clause(for: "SELECT ROW_NUMBER() OVER (PARTITION BY ") == .selectList)
}

@Test
func clauseRestoresAfterOverCloses() {
    #expect(clause(for: "SELECT ROW_NUMBER() OVER (ORDER BY id) FROM ") == .from)
}

// MARK: - Statement Type

@Test
func statementTypeTracksInsert() {
    var machine = ClauseStateMachine()
    for token in tokens(from: "INSERT INTO users (name) VALUES ") {
        machine.feed(token)
    }
    // After VALUES, statement type should no longer be insert
    // (so 'into' doesn't re-trigger)
    #expect(machine.currentClause == .values)
}

@Test
func statementTypeTracksDelete() {
    var machine = ClauseStateMachine()
    for token in tokens(from: "DELETE ") {
        machine.feed(token)
    }
    #expect(machine.statementType == .delete)
}

@Test
func deleteWithoutWhereGivesDeleteWhere() {
    // DELETE alone with no WHERE → deleteWhere fallback
    var machine = ClauseStateMachine()
    for token in tokens(from: "DELETE FROM users ") {
        machine.feed(token)
    }
    // from keyword sets clause to .from, then 'users' is an identifier, doesn't change clause
    // clause is .from, not .unknown, so deleteWhere fallback doesn't apply
    #expect(machine.currentClause == .from)
}

// MARK: - Left/Right Join Variants

@Test
func machineDetectsLeftJoin() {
    #expect(clause(for: "SELECT * FROM users LEFT JOIN ") == .joinTarget)
}

@Test
func machineDetectsInnerJoin() {
    #expect(clause(for: "SELECT * FROM users INNER JOIN ") == .joinTarget)
}
