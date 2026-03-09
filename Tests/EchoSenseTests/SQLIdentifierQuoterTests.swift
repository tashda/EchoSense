import Testing
@testable import EchoSense

@Test
func postgresQuotingRules() async throws {
    let quoter = SQLIdentifierQuoter.forDialect(.postgresql)
    #expect(quoter.quoteIfNeeded("UserAccount") == "\"UserAccount\"")
    #expect(quoter.quoteIfNeeded("select") == "\"select\"")
    #expect(quoter.quoteIfNeeded("already_quoted") == "already_quoted")
    #expect(quoter.quoteIfNeeded("\"quoted\"") == "\"quoted\"")
    // "public" is intentionally excluded from reserved-word quoting in PostgreSQL
    #expect(quoter.qualify(["public", "Order Items"]) == "public.\"Order Items\"")
}

@Test
func mySQLWhitespaceQuoting() async throws {
    let quoter = SQLIdentifierQuoter.forDialect(.mysql)
    #expect(quoter.quoteIfNeeded("order details") == "`order details`")
    #expect(quoter.quoteIfNeeded("order_id") == "order_id")
}

@Test
func sqlServerEscaping() async throws {
    let quoter = SQLIdentifierQuoter.forDialect(.microsoftSQL)
    #expect(quoter.quoteIfNeeded("select") == "[select]")
    #expect(quoter.quoteIfNeeded("order-items") == "[order-items]")
    #expect(quoter.quoteIfNeeded("name]with") == "[name]]with]")
}

@Test
func sqliteInvalidStartingCharacter() async throws {
    let quoter = SQLIdentifierQuoter.forDialect(.sqlite)
    #expect(quoter.quoteIfNeeded("1column") == "\"1column\"")
    #expect(quoter.quoteIfNeeded("normal") == "normal")
}
