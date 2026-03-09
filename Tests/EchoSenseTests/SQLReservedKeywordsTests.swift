import Testing
@testable import EchoSense

@Test
func containsCommonKeywords() {
    #expect(SQLReservedKeywords.contains("SELECT"))
    #expect(SQLReservedKeywords.contains("FROM"))
    #expect(SQLReservedKeywords.contains("WHERE"))
    #expect(SQLReservedKeywords.contains("INSERT"))
    #expect(SQLReservedKeywords.contains("UPDATE"))
    #expect(SQLReservedKeywords.contains("DELETE"))
    #expect(SQLReservedKeywords.contains("JOIN"))
    #expect(SQLReservedKeywords.contains("CREATE"))
    #expect(SQLReservedKeywords.contains("DROP"))
}

@Test
func containsIsCaseInsensitive() {
    #expect(SQLReservedKeywords.contains("select"))
    #expect(SQLReservedKeywords.contains("Select"))
    #expect(SQLReservedKeywords.contains("SELECT"))
}

@Test
func doesNotContainNonKeywords() {
    #expect(!SQLReservedKeywords.contains("username"))
    #expect(!SQLReservedKeywords.contains("my_table"))
    #expect(!SQLReservedKeywords.contains(""))
}

@Test
func allLowercasedSetNotEmpty() {
    #expect(SQLReservedKeywords.allLowercased.count > 500)
}

@Test
func allLowercasedContainsLowercaseOnly() {
    for word in SQLReservedKeywords.allLowercased {
        #expect(word == word.lowercased(), "Found non-lowercase keyword: \(word)")
    }
}

@Test
func containsVendorSpecificKeywords() {
    // SQL Server
    #expect(SQLReservedKeywords.contains("NONCLUSTERED"))
    #expect(SQLReservedKeywords.contains("HOLDLOCK"))

    // PostgreSQL
    #expect(SQLReservedKeywords.contains("LATERAL"))
    #expect(SQLReservedKeywords.contains("ILIKE"))

    // MySQL
    #expect(SQLReservedKeywords.contains("UNSIGNED"))
    #expect(SQLReservedKeywords.contains("ZEROFILL"))
}

@Test
func containsAggregateFunction() {
    #expect(SQLReservedKeywords.contains("COUNT"))
    #expect(SQLReservedKeywords.contains("SUM"))
    #expect(SQLReservedKeywords.contains("AVG"))
    #expect(SQLReservedKeywords.contains("MAX"))
    #expect(SQLReservedKeywords.contains("MIN"))
}

@Test
func containsDataTypes() {
    #expect(SQLReservedKeywords.contains("INT"))
    #expect(SQLReservedKeywords.contains("VARCHAR"))
    #expect(SQLReservedKeywords.contains("BOOLEAN"))
    #expect(SQLReservedKeywords.contains("DATE"))
    #expect(SQLReservedKeywords.contains("TIMESTAMP"))
}
