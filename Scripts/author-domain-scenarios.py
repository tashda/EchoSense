#!/usr/bin/env python3
"""Hand-authored domain scenarios for statements, statement-at-caret, go-batches and sqlcmd.

Rewrites Sources/EchoSenseScenarios/DomainScenarios/<domain>.json from the tables below. Expected
lines are written from the rules, never copied from what the code does. Run, then
`swift run echosense-scenarios run --domain <id>` and triage any failure.
"""
import json, os, sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "Sources", "EchoSenseScenarios", "DomainScenarios")
OUT = {}

def add(domain, prefix, group, title, inp, expected, should="", issue=None, caret="|", options=None):
    items = OUT.setdefault(domain, [])
    sid = f"{prefix}-{len(items) + 1:03d}"
    s = {"id": sid, "domain": domain, "group": group, "title": title, "should": should or title,
         "input": inp, "caretMarker": caret, "options": options or {}, "expected": expected}
    if issue: s["knownIssue"] = issue
    items.append(s)

# ---------------------------------------------------------------- statements
D, P = "statements", "STM"
G = "Semicolons"
add(D,P,G,"One statement without a semicolon","SELECT 1",["L1: SELECT 1"])
add(D,P,G,"Two statements on two lines","SELECT 1;\nSELECT 2;",["L1: SELECT 1;","L2: SELECT 2;"])
add(D,P,G,"Two statements on one line","SELECT 1; SELECT 2",["L1: SELECT 1;","L1: SELECT 2"])
add(D,P,G,"A lone semicolon is not a statement","SELECT 1;;\nSELECT 2",["L1: SELECT 1;","L2: SELECT 2"])
add(D,P,G,"Line numbers skip blank lines","SELECT 1;\n\n\nSELECT 2;",["L1: SELECT 1;","L4: SELECT 2;"])
add(D,P,G,"Empty script has no statements","",[])
add(D,P,G,"Only whitespace has no statements","  \n\t\n",[])
G = "Strings and comments"
add(D,P,G,"Semicolon inside a string","SELECT 'a;b'; SELECT 2",["L1: SELECT 'a;b';","L1: SELECT 2"])
add(D,P,G,"Escaped quote inside a string","SELECT 'it''s; fine'; SELECT 2",["L1: SELECT 'it''s; fine';","L1: SELECT 2"])
add(D,P,G,"Semicolon in a line comment","SELECT 1 -- a; b\n; SELECT 2",["L1: SELECT 1 -- a; b\n;","L2: SELECT 2"])
add(D,P,G,"Semicolon in a block comment","SELECT 1 /* a; b */; SELECT 2",["L1: SELECT 1 /* a; b */;","L1: SELECT 2"])
add(D,P,G,"Nested block comment","SELECT 1 /* a /* b; */ c; */; SELECT 2",["L1: SELECT 1 /* a /* b; */ c; */;","L1: SELECT 2"])
add(D,P,G,"String with a newline keeps its lines","SELECT 'a\nb';\nSELECT 2",["L1: SELECT 'a\nb';","L3: SELECT 2"])
add(D,P,G,"Semicolon in a bracketed name","SELECT [a;b] FROM t; SELECT 2",["L1: SELECT [a;b] FROM t;","L1: SELECT 2"],
    issue="Bracketed identifiers are not skipped, so a semicolon inside one splits the statement")
add(D,P,G,"Semicolon in a double-quoted name","SELECT \"a;b\" FROM t; SELECT 2",["L1: SELECT \"a;b\" FROM t;","L1: SELECT 2"],
    issue="Double-quoted identifiers are not skipped, so a semicolon inside one splits the statement")
G = "Blocks"
add(D,P,G,"BEGIN…END stays one statement","BEGIN\n  SELECT 1;\n  SELECT 2;\nEND",["L1: BEGIN\n  SELECT 1;\n  SELECT 2;\nEND"])
add(D,P,G,"Statement after a block","BEGIN SELECT 1; END; SELECT 2;",["L1: BEGIN SELECT 1; END;","L1: SELECT 2;"])
add(D,P,G,"Nested blocks","BEGIN BEGIN SELECT 1; END; SELECT 2; END; SELECT 3;",["L1: BEGIN BEGIN SELECT 1; END; SELECT 2; END;","L1: SELECT 3;"])
add(D,P,G,"CASE … END inside a block","BEGIN SELECT CASE WHEN 1 = 1 THEN 1 END; SELECT 2; END; SELECT 3;",["L1: BEGIN SELECT CASE WHEN 1 = 1 THEN 1 END; SELECT 2; END;","L1: SELECT 3;"],
    issue="The END of a CASE is counted as the end of the block, so the block splits early")
add(D,P,G,"BEGIN TRANSACTION does not open a block","BEGIN TRANSACTION;\nSELECT 1;\nCOMMIT;\nSELECT 2;",["L1: BEGIN TRANSACTION;","L2: SELECT 1;","L3: COMMIT;","L4: SELECT 2;"],
    issue="BEGIN TRANSACTION is counted as a block that never ends, so everything after it is one statement")
add(D,P,G,"BEGIN TRY … END CATCH","BEGIN TRY SELECT 1; END TRY BEGIN CATCH SELECT 2; END CATCH; SELECT 3;",["L1: BEGIN TRY SELECT 1; END TRY BEGIN CATCH SELECT 2; END CATCH;","L1: SELECT 3;"])
add(D,P,G,"IF … ELSE without a block","IF 1 = 1 SELECT 1; ELSE SELECT 2;",["L1: IF 1 = 1 SELECT 1;","L1: ELSE SELECT 2;"],
    should="IF and ELSE are one statement in T-SQL, so they should stay together",
    issue="IF and ELSE are split into two statements at the semicolon")
add(D,P,G,"Words that only contain BEGIN or END","SELECT beginning, ending FROM t; SELECT 2;",["L1: SELECT beginning, ending FROM t;","L1: SELECT 2;"])
add(D,P,G,"Nested CASE inside a block","BEGIN SELECT CASE WHEN a = 1 THEN CASE WHEN b = 1 THEN 1 END END; SELECT 2; END; SELECT 3;",["L1: BEGIN SELECT CASE WHEN a = 1 THEN CASE WHEN b = 1 THEN 1 END END; SELECT 2; END;","L1: SELECT 3;"])
add(D,P,G,"IF … ELSE with blocks","IF 1 = 1 BEGIN SELECT 1; END ELSE BEGIN SELECT 2; END; SELECT 3;",["L1: IF 1 = 1 BEGIN SELECT 1; END ELSE BEGIN SELECT 2; END;","L1: SELECT 3;"])
add(D,P,G,"ELSE on the next line","IF 1 = 1 SELECT 1;\nELSE SELECT 2;\nSELECT 3;",["L1: IF 1 = 1 SELECT 1;\nELSE SELECT 2;","L3: SELECT 3;"])
add(D,P,G,"A name that only starts with ELSE","SELECT 1; ELSEWHERE_PROC;",["L1: SELECT 1;","L1: ELSEWHERE_PROC;"])
add(D,P,G,"BEGIN DISTRIBUTED TRANSACTION","BEGIN DISTRIBUTED TRANSACTION; SELECT 1; COMMIT;",["L1: BEGIN DISTRIBUTED TRANSACTION;","L1: SELECT 1;","L1: COMMIT;"])
add(D,P,G,"A bracketed name called end","SELECT [end] FROM t; SELECT 2;",["L1: SELECT [end] FROM t;","L1: SELECT 2;"])
add(D,P,G,"Escaped closing bracket","SELECT [a]];b] FROM t; SELECT 2;",["L1: SELECT [a]];b] FROM t;","L1: SELECT 2;"])
G = "GO"
add(D,P,G,"GO separates batches","SELECT 1\nGO\nSELECT 2",["L1: SELECT 1","L3: SELECT 2"])
add(D,P,G,"Line numbers after GO and blank lines","SELECT 1;\nGO\n\nSELECT 2;\n\nSELECT 3;",["L1: SELECT 1;","L4: SELECT 2;","L6: SELECT 3;"])
add(D,P,G,"GO in lower case","SELECT 1\ngo\nSELECT 2",["L1: SELECT 1","L3: SELECT 2"])
add(D,P,G,"GO with a count","SELECT 1\nGO 5\nSELECT 2",["L1: SELECT 1","L3: SELECT 2"])
add(D,P,G,"GO inside a longer word is not a separator","SELECT 1\nGOTO label\nSELECT 2",["L1: SELECT 1\nGOTO label\nSELECT 2"])
add(D,P,G,"Indented GO","SELECT 1\n   GO\nSELECT 2",["L1: SELECT 1","L3: SELECT 2"])

# ---------------------------------------------------------------- statement at caret
D, P = "statement-at-caret", "CAR"
G = "Semicolons"
add(D,P,G,"Caret inside the first statement","SELECT |1; SELECT 2; SELECT 3;",["SELECT 1"])
add(D,P,G,"Caret inside the middle statement","SELECT 1; SELECT |2; SELECT 3;",["SELECT 2"])
add(D,P,G,"Caret at the very start","|SELECT 1; SELECT 2;",["SELECT 1"])
add(D,P,G,"Caret right after a semicolon belongs to the statement before","SELECT 1;| SELECT 2;",["SELECT 1"])
add(D,P,G,"Caret after the last semicolon picks the last statement","SELECT 1; SELECT 2;\n|",["SELECT 2"])
add(D,P,G,"Caret at the end without a semicolon","SELECT 1; SELECT 2|",["SELECT 2"])
add(D,P,G,"A script with no statements","  |  ",["(none)"])
add(D,P,G,"Only semicolons","|;;",["(none)"])
G = "Blank lines"
add(D,P,G,"A blank line ends a statement","SELECT 1\nFROM a\n\nSELECT |2\nFROM b",["SELECT 2\nFROM b"])
add(D,P,G,"Caret on a blank line picks the statement before","SELECT 1\n\n|\n\nSELECT 2",["SELECT 1"])
add(D,P,G,"Several lines without a blank line are one statement","SELECT a,\n  b\nFROM |t\nWHERE x = 1",["SELECT a,\n  b\nFROM t\nWHERE x = 1"])
G = "Quotes and comments"
add(D,P,G,"Semicolon in a string does not end it","SELECT 'a;b', |1; SELECT 2;",["SELECT 'a;b', 1"])
add(D,P,G,"Blank line in a string does not end it","SELECT 'a\n\nb', |1; SELECT 2;",["SELECT 'a\n\nb', 1"])
add(D,P,G,"Semicolon in a line comment","SELECT |1 -- ; not the end\n, 2; SELECT 3;",["SELECT 1 -- ; not the end\n, 2"])
add(D,P,G,"Semicolon in a block comment","SELECT |1 /* ; */, 2; SELECT 3;",["SELECT 1 /* ; */, 2"])
add(D,P,G,"Semicolon in a bracketed name","SELECT [a;b]|, 1; SELECT 2;",["SELECT [a;b], 1"])
add(D,P,G,"Semicolon in a backtick name","SELECT `a;b`|, 1; SELECT 2;",["SELECT `a;b`, 1"])
add(D,P,G,"Dollar-quoted body","DO $$ BEGIN PERFORM 1; |END $$; SELECT 2;",["DO $$ BEGIN PERFORM 1; END $$"])
add(D,P,G,"Dollar-quoted body with a tag","DO $body$ BEGIN PERFORM 1; |END $body$; SELECT 2;",["DO $body$ BEGIN PERFORM 1; END $body$"])
G = "GO"
add(D,P,G,"GO line separates statements","SELECT 1\nGO\nSELECT |2",["SELECT 2"])
add(D,P,G,"Caret on the GO line picks the statement before","SELECT 1\nG|O\nSELECT 2",["SELECT 1"])
add(D,P,G,"GO in lower case","SELECT 1\ngo\nSELECT |2",["SELECT 2"])
G = "Unicode"
add(D,P,G,"Emoji before the caret (UTF-16 offsets)","SELECT '😀'; SELECT |2;",["SELECT 2"])

# ---------------------------------------------------------------- GO batches
D, P = "go-batches", "GOB"
G = "Separators"
add(D,P,G,"One batch without GO","SELECT 1",["×1: SELECT 1"])
add(D,P,G,"GO between two batches","SELECT 1\nGO\nSELECT 2",["×1: SELECT 1","×1: SELECT 2"])
add(D,P,G,"GO in lower and mixed case","SELECT 1\ngo\nSELECT 2\nGo\nSELECT 3",["×1: SELECT 1","×1: SELECT 2","×1: SELECT 3"])
add(D,P,G,"GO at the very end","SELECT 1\nGO",["×1: SELECT 1"])
add(D,P,G,"GO at the very start","GO\nSELECT 1",["×1: SELECT 1"])
add(D,P,G,"Empty batches are dropped","SELECT 1\nGO\nGO\nSELECT 2",["×1: SELECT 1","×1: SELECT 2"])
add(D,P,G,"Indented GO","SELECT 1\n   GO   \nSELECT 2",["×1: SELECT 1","×1: SELECT 2"])
add(D,P,G,"GO; is not a separator","SELECT 1\nGO;\nSELECT 2",["×1: SELECT 1\nGO;\nSELECT 2"])
add(D,P,G,"GO with other text on the line is not a separator","SELECT 1\nGO SELECT 2",["×1: SELECT 1\nGO SELECT 2"])
add(D,P,G,"GO in the middle of a line is not a separator","SELECT 1 GO SELECT 2",["×1: SELECT 1 GO SELECT 2"])
G = "Repeat counts"
add(D,P,G,"GO 3 repeats the batch three times","SELECT 1\nGO 3\nSELECT 2",["×3: SELECT 1","×1: SELECT 2"])
add(D,P,G,"GO 1","SELECT 1\nGO 1",["×1: SELECT 1"])
add(D,P,G,"GO with a comment after it","SELECT 1\nGO -- run it\nSELECT 2",["×1: SELECT 1","×1: SELECT 2"])
add(D,P,G,"GO with a count and a comment","SELECT 1\nGO 2 -- twice\nSELECT 2",["×2: SELECT 1","×1: SELECT 2"])
G = "Quotes and comments"
add(D,P,G,"GO inside a string","SELECT '\nGO\n'",["×1: SELECT '\nGO\n'"])
add(D,P,G,"GO inside a block comment","/*\nGO\n*/\nSELECT 1",["×1: /*\nGO\n*/\nSELECT 1"])
add(D,P,G,"GO inside a bracketed name","SELECT [a\nGO\nb]",["×1: SELECT [a\nGO\nb]"])
add(D,P,G,"GO after a closed comment","/* x */\nGO\nSELECT 1",["×1: /* x */","×1: SELECT 1"])
add(D,P,G,"Windows line endings","SELECT 1\r\nGO\r\nSELECT 2",["×1: SELECT 1","×1: SELECT 2"])

# ---------------------------------------------------------------- SQLCMD
D, P = "sqlcmd", "CMD"
G = "Variables"
add(D,P,G,"Plain SQL is one batch","SELECT 1",["batch: SELECT 1"])
add(D,P,G,"setvar and substitution",":setvar Db Sales\nUSE $(Db)",["batch: USE Sales"])
add(D,P,G,"A variable used twice",":setvar T orders\nSELECT * FROM $(T)\nSELECT COUNT(*) FROM $(T)",["batch: SELECT * FROM orders\nSELECT COUNT(*) FROM orders"])
add(D,P,G,"setvar with a quoted value",":setvar Name \"Big Corp\"\nSELECT '$(Name)'",["batch: SELECT 'Big Corp'"])
add(D,P,G,"A variable that is not set stays as written","SELECT '$(Nope)'",["batch: SELECT '$(Nope)'","warning: Variable 'Nope' is not defined"],
    should="An unset variable is reported, and the text is left as it was",
    issue="Check what the preprocessor does with an unset variable; this expectation is the owner's to confirm")
add(D,P,G,"A colon in a string is not a directive","SELECT ':setvar x 1'",["batch: SELECT ':setvar x 1'"])
G = "Batches"
add(D,P,G,"GO splits batches","SELECT 1\nGO\nSELECT 2",["batch: SELECT 1","batch: SELECT 2"])
add(D,P,G,"Variables carry across GO",":setvar N 5\nSELECT $(N)\nGO\nSELECT $(N)",["batch: SELECT 5","batch: SELECT 5"])
add(D,P,G,"GO 2 runs the batch twice","SELECT 1\nGO 2",["batch: SELECT 1","batch: SELECT 1"])
G = "Unsupported"
add(D,P,G,"An unsupported directive is a warning",":connect server1\nSELECT 1",["batch: SELECT 1","warning: :connect is not supported and was skipped"],
    issue="The exact warning text is a guess; confirm against the preprocessor")
add(D,P,G,"On error directive",":on error exit\nSELECT 1",["batch: SELECT 1","warning: :on error is not supported and was skipped"],
    issue="The exact warning text is a guess; confirm against the preprocessor")

# ---------------------------------------------------------------- error line
D, P = "error-line", "ERL"
G = "Servers"
add(D,P,G,"SQL Server message","Msg 102, Level 15, State 1, Line 3\nIncorrect syntax near 'FROM'.",["3"])
add(D,P,G,"PostgreSQL message","ERROR:  syntax error at or near \"FORM\"\nLINE 3: SELECT * FORM users\n                 ^",["3"])
add(D,P,G,"MySQL message","You have an error in your SQL syntax; check the manual near 'FORM users' at line 2",["2"])
add(D,P,G,"Lower case","error at line 12",["12"])
G = "No line"
add(D,P,G,"No line in the message","relation \"users\" does not exist",["(none)"])
add(D,P,G,"The word line without a number","Incorrect syntax near 'line'.",["(none)"])
add(D,P,G,"Line 0 is not a line","Msg 50000, Level 16, State 1, Line 0",["(none)"])
add(D,P,G,"Part of a longer word","Query timeline 5 exceeded the deadline 4",["(none)"])
add(D,P,G,"The first line wins","Line 3: first\nLine 5: second",["3"])
add(D,P,G,"A large line number","Msg 102, Level 15, State 1, Line 10482",["10482"])

# ---------------------------------------------------------------- run note
D, P = "run-note", "RUN"
G = "Success"
add(D,P,G,"Rows and time","",["✓ 1,200 rows · 3.2 s","tooltip: ✓ 1,200 rows · 3.2 s"],options={"kind":"success","rows":"1200","seconds":"3.2"})
add(D,P,G,"One row","",["✓ 1 row · 12 ms","tooltip: ✓ 1 row · 12 ms"],options={"kind":"success","rows":"1","seconds":"0.012"})
add(D,P,G,"No rows","",["✓ 0 rows · 5 ms","tooltip: ✓ 0 rows · 5 ms"],options={"kind":"success","rows":"0","seconds":"0.005"})
add(D,P,G,"A statement without results","",["✓ Done · 45 ms","tooltip: ✓ Done · 45 ms"],options={"kind":"success","hasResults":"false","seconds":"0.045"})
add(D,P,G,"No time known","",["✓ Done","tooltip: ✓ Done"],options={"kind":"success","hasResults":"false"})
add(D,P,G,"Minutes","",["✓ 10 rows · 1 min 15 s","tooltip: ✓ 10 rows · 1 min 15 s"],options={"kind":"success","rows":"10","seconds":"75"})
add(D,P,G,"Just under a second rounds up to a second","",["✓ 1 row · 1.0 s","tooltip: ✓ 1 row · 1.0 s"],options={"kind":"success","rows":"1","seconds":"0.9996"},
    should="0.9996 seconds is shown as 1.0 s, not 1000 ms",issue="Shown as 1000 ms")
add(D,P,G,"Just under a minute rounds up to a minute","",["✓ 1 row · 1 min 0 s","tooltip: ✓ 1 row · 1 min 0 s"],options={"kind":"success","rows":"1","seconds":"59.96"},
    should="59.96 seconds is shown as 1 min 0 s, not 60.0 s",issue="Shown as 60.0 s")
G = "Errors"
add(D,P,G,"Short message","Incorrect syntax near 'FROM'.",["Incorrect syntax near 'FROM'.","tooltip: Incorrect syntax near 'FROM'."],options={"kind":"failure"})
add(D,P,G,"Only the first line shows","Msg 102, Level 15\nIncorrect syntax near 'FROM'.",["Msg 102, Level 15","tooltip: Msg 102, Level 15\nIncorrect syntax near 'FROM'."],options={"kind":"failure"})
add(D,P,G,"A long first line is cut at 80 characters","0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789",["0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 012","tooltip: 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789"],options={"kind":"failure"})
add(D,P,G,"Short form says Error","relation \"users\" does not exist",["! Error","tooltip: relation \"users\" does not exist"],options={"kind":"shortFailure"})
G = "Cancelled"
add(D,P,G,"Cancelled with nothing known","",["Cancelled","tooltip: Cancelled"],options={"kind":"cancelled"})
add(D,P,G,"Cancelled after a time","",["Cancelled after 3.2 s","tooltip: Cancelled after 3.2 s"],options={"kind":"cancelled","seconds":"3.2"})
add(D,P,G,"Cancelled with rows kept","",["Cancelled after 3.2 s · 1,200 rows","tooltip: Cancelled after 3.2 s · 1,200 rows"],options={"kind":"cancelled","seconds":"3.2","rows":"1200"})
add(D,P,G,"Cancelled with one row","",["Cancelled · 1 row","tooltip: Cancelled · 1 row"],options={"kind":"cancelled","rows":"1"})
add(D,P,G,"Cancelled inside a transaction","",["Cancelled after 3.2 s · The transaction now needs ROLLBACK","tooltip: Cancelled after 3.2 s · The transaction now needs ROLLBACK"],options={"kind":"cancelled","seconds":"3.2","rollback":"true"})

# ---------------------------------------------------------------- connection loss
D, P = "connection-loss", "LOS"
G = "Dropped"
add(D,P,G,"Dropped with a transaction open","",["Connection lost: the connection to sales dropped while a transaction was open. The server rolled the transaction back; nothing since BEGIN was saved. Reconnect to start a new session. Details: the server or the network closed the connection."],options={"kind":"droppedWithTransaction","database":"sales"})
add(D,P,G,"Notification when a transaction was open","",["Connection lost: Query 1 (sales) had a transaction open. The server rolled it back; nothing since BEGIN was saved."],options={"kind":"notification","database":"sales","tab":"Query 1"},
    should="The notification splits into a title and a detail at the first “: ”")
add(D,P,G,"Dropped while idle","",["Connection closed: Query 1 (sales) was idle, so nothing was lost. The next run reconnects."],options={"kind":"droppedIdle","database":"sales","tab":"Query 1"})
G = "Reconnecting"
add(D,P,G,"Running while waiting for Reconnect","",["Not connected: the connection to sales was lost with a transaction open, and the server rolled it back. Press Reconnect in the notification to start a new session (SET and temporary tables will be gone)."],options={"kind":"awaitingReconnect","database":"sales"})
add(D,P,G,"Reconnected","",["Reconnected to sales: a new session. SET, temporary tables and the lost transaction are gone."],options={"kind":"reconnected","database":"sales"})
add(D,P,G,"Reconnect failed","",["Reconnect failed: could not connect to sales. Login timeout expired."],options={"kind":"reconnectFailed","database":"sales","reason":"Login timeout expired."})

# ---------------------------------------------------------------- table preview
D, P = "table-preview", "TBL"
G = "Dialects"
add(D,P,G,"SQL Server uses TOP and brackets","dbo.Orders",["SELECT TOP 1000 * FROM [dbo].[Orders];"],options={"dialect":"mssql"})
add(D,P,G,"PostgreSQL uses LIMIT and double quotes","public.orders",["SELECT * FROM \"public\".\"orders\" LIMIT 1000;"],options={"dialect":"postgresql"})
add(D,P,G,"MySQL uses LIMIT and backticks","shop.orders",["SELECT * FROM `shop`.`orders` LIMIT 1000;"],options={"dialect":"mysql"})
add(D,P,G,"SQLite has no schema","main.orders",["SELECT * FROM \"orders\" LIMIT 1000;"],options={"dialect":"sqlite"})
G = "Quoting"
add(D,P,G,"A closing bracket is doubled","",["SELECT TOP 1000 * FROM [dbo].[a]]b];"],options={"dialect":"mssql","schema":"dbo","table":"a]b"})
add(D,P,G,"A double quote is doubled","",["SELECT * FROM \"public\".\"a\"\"b\" LIMIT 1000;"],options={"dialect":"postgresql","schema":"public","table":"a\"b"})
add(D,P,G,"A backtick is doubled","",["SELECT * FROM `shop`.`a``b` LIMIT 1000;"],options={"dialect":"mysql","schema":"shop","table":"a`b"})
add(D,P,G,"Names with spaces and capitals","",["SELECT * FROM \"My Schema\".\"Order Items\" LIMIT 1000;"],options={"dialect":"postgresql","schema":"My Schema","table":"Order Items"})

# ---------------------------------------------------------------- grid selection
D, P = "grid-selection", "GRD"
G = "Counting"
add(D,P,G,"One cell","5",["1 cell"])
add(D,P,G,"Two numbers","1\n3",["2 cells · Sum 4 · Avg 2"])
add(D,P,G,"Three numbers","1\n2\n3",["3 cells · Sum 6 · Avg 2"])
add(D,P,G,"One number among text is only counted","5\nabc",["2 cells"])
add(D,P,G,"Text only","a\nb\nc",["3 cells"])
add(D,P,G,"NULL counts as a cell but adds nothing","1\n∅\n3",["3 cells · Sum 4 · Avg 2"])
add(D,P,G,"Text among numbers counts as a cell","1\nx\n3",["3 cells · Sum 4 · Avg 2"])
G = "Numbers"
add(D,P,G,"Decimals","1.5\n2.25",["2 cells · Sum 3.75 · Avg 1.88"])
add(D,P,G,"Thousands separators in the result","1000\n2000",["2 cells · Sum 3,000 · Avg 1,500"])
add(D,P,G,"Negative numbers","-1\n1",["2 cells · Sum 0 · Avg 0"])
add(D,P,G,"Spaces around a number","  4 \n6",["2 cells · Sum 10 · Avg 5"])
add(D,P,G,"Exponent notation","1e3\n1",["2 cells · Sum 1,001 · Avg 500.5"])
add(D,P,G,"NaN and infinity are not numbers","NaN\n1\n2\ninf",["4 cells · Sum 3 · Avg 1.5"])
add(D,P,G,"Hexadecimal text is not a number","0x10\n1\n2",["3 cells · Sum 3 · Avg 1.5"],
    should="A cell holding 0x10 is text, not 16",issue="Swift reads 0x10 as 16, so it is added to the sum")
G = "Large selections"
add(D,P,G,"More than 50,000 cells shows the count only","1\n2",["60,000 cells"],options={"cellCount":"60000"})
add(D,P,G,"Exactly 50,000 cells is still added up","1\n2",["50,000 cells · Sum 3 · Avg 1.5"],options={"cellCount":"50000"})

# ---------------------------------------------------------------- JSON viewer
D, P = "json-outline", "JSN"
G = "Values"
add(D,P,G,"A number","42",["Number: 42  $"])
add(D,P,G,"A string","\"hi\"",["String: hi  $"])
add(D,P,G,"true, false and null","[true,false,null]",["Array: 3 items  $","  [0]: true  $[0]","  [1]: false  $[1]","  [2]: null  $[2]"])
add(D,P,G,"Unicode escapes","\"\\u4e16\\u754c\"",["String: 世界  $"])
add(D,P,G,"Empty object","{}",["Object: 0 keys  $"])
add(D,P,G,"Empty array","[]",["Array: 0 items  $"])
add(D,P,G,"One key is singular","{\"a\":1}",["Object: 1 key  $","  a: 1  $.a"])
add(D,P,G,"One item is singular","[7]",["Array: 1 item  $","  [0]: 7  $[0]"])
G = "Structure"
add(D,P,G,"Nested paths","{\"a\":{\"b\":[{\"c\":1}]}}",["Object: 1 key  $","  a: 1 key  $.a","    b: 1 item  $.a.b","      [0]: 1 key  $.a.b[0]","        c: 1  $.a.b[0].c"])
add(D,P,G,"Keys keep the order of the document","{\"b\":1,\"a\":2}",["Object: 2 keys  $","  b: 1  $.b","  a: 2  $.a"],
    should="A JSON column's keys are shown in the order they are stored",
    issue="Keys are sorted alphabetically (an Echo test pins this). Whether the viewer should keep the document's order is the owner's to decide")
add(D,P,G,"Array of arrays","[[1,2],[3]]",["Array: 2 items  $","  [0]: 2 items  $[0]","    [0]: 1  $[0][0]","    [1]: 2  $[0][1]","  [1]: 1 item  $[1]","    [0]: 3  $[1][0]"])
G = "Paths"
add(D,P,G,"A name with a dot","{\"a.b\":1}",["Object: 1 key  $","  a.b: 1  $['a.b']"])
add(D,P,G,"A name with a space","{\"a b\":1}",["Object: 1 key  $","  a b: 1  $['a b']"])
add(D,P,G,"A name with a hyphen","{\"a-b\":1}",["Object: 1 key  $","  a-b: 1  $['a-b']"])
add(D,P,G,"A name with an underscore","{\"a_b\":1}",["Object: 1 key  $","  a_b: 1  $.a_b"])
add(D,P,G,"A name with an apostrophe is escaped","{\"it's\":1}",["Object: 1 key  $","  it's: 1  $['it\\'s']"])
add(D,P,G,"A name starting with a digit","{\"1a\":1}",["Object: 1 key  $","  1a: 1  $['1a']"])
add(D,P,G,"A name with brackets","{\"a[0]\":1}",["Object: 1 key  $","  a[0]: 1  $['a[0]']"])
add(D,P,G,"An empty name","{\"\":1}",["Object: 1 key  $","  : 1  $['']"])
G = "Numbers"
add(D,P,G,"A decimal","0.1",["Number: 0.1  $"])
add(D,P,G,"A number too big for a double","12345678901234567890",["Number: 12345678901234567890  $"],
    should="The digits in the column are the digits shown",issue="Shown as 1.2345678901234567e+19")
add(D,P,G,"A trailing zero","1.0",["Number: 1.0  $"],
    should="The digits in the column are the digits shown",issue="Shown as 1")
G = "Invalid"
add(D,P,G,"Not JSON","not json",["(invalid)"])
add(D,P,G,"Empty","",["(invalid)"])
add(D,P,G,"A trailing comma","[1,]",["(invalid)"])
add(D,P,G,"Single quotes","{'a':1}",["(invalid)"])
add(D,P,G,"An unclosed object","{\"a\":1",["(invalid)"])

# ---------------------------------------------------------------- table DDL
D, P = "table-ddl", "DDL"
def ddl(group, title, dialect, opts, expected, issue=None, should=""):
    o = {"dialect": dialect}; o.update(opts)
    add(D, P, group, title, "", expected, should=should, issue=issue, options=o)
PG, MS, MY = "postgresql", "mssql", "mysql"
G = "Transactions"
ddl(G,"Begin, PostgreSQL",PG,{"op":"begin"},["BEGIN;"])
ddl(G,"Begin, SQL Server",MS,{"op":"begin"},["BEGIN TRANSACTION;"])
ddl(G,"Begin, MySQL",MY,{"op":"begin"},["START TRANSACTION;"])
ddl(G,"Rollback, SQL Server",MS,{"op":"rollback"},["ROLLBACK TRANSACTION;"])
G = "Add column"
ddl(G,"Plain column, PostgreSQL",PG,{"op":"addColumn","column":"note","type":"text"},['ALTER TABLE "public"."orders" ADD COLUMN "note" text;'])
ddl(G,"Not null with default, PostgreSQL",PG,{"op":"addColumn","column":"status","type":"text","nullable":"false","default":"'new'"},['ALTER TABLE "public"."orders" ADD COLUMN "status" text NOT NULL DEFAULT \'new\';'])
ddl(G,"Identity, PostgreSQL",PG,{"op":"addColumn","column":"id","type":"integer","nullable":"false","identity":"1,1"},['ALTER TABLE "public"."orders" ADD COLUMN "id" integer GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1) NOT NULL;'])
ddl(G,"Generated column, PostgreSQL",PG,{"op":"addColumn","column":"total","type":"numeric","expression":"price * qty"},['ALTER TABLE "public"."orders" ADD COLUMN "total" numeric GENERATED ALWAYS AS (price * qty) STORED;'])
ddl(G,"Collation, PostgreSQL",PG,{"op":"addColumn","column":"name","type":"text","collation":"C"},['ALTER TABLE "public"."orders" ADD COLUMN "name" text COLLATE "C";'])
ddl(G,"Plain column, SQL Server",MS,{"op":"addColumn","column":"note","type":"nvarchar(200)"},['ALTER TABLE [dbo].[orders] ADD [note] nvarchar(200) NULL;'])
ddl(G,"Not null with default, SQL Server",MS,{"op":"addColumn","column":"status","type":"nvarchar(20)","nullable":"false","default":"'new'"},["ALTER TABLE [dbo].[orders] ADD [status] nvarchar(20) NOT NULL DEFAULT 'new';"])
ddl(G,"Identity, SQL Server",MS,{"op":"addColumn","column":"id","type":"int","nullable":"false","identity":"1,1"},['ALTER TABLE [dbo].[orders] ADD [id] int IDENTITY(1, 1) NOT NULL;'])
ddl(G,"Computed column, SQL Server",MS,{"op":"addColumn","column":"total","type":"money","expression":"price * qty"},['ALTER TABLE [dbo].[orders] ADD [total] AS (price * qty) PERSISTED;'])
ddl(G,"Collation, SQL Server",MS,{"op":"addColumn","column":"name","type":"nvarchar(50)","collation":"Latin1_General_CI_AS"},['ALTER TABLE [dbo].[orders] ADD [name] nvarchar(50) COLLATE Latin1_General_CI_AS NULL;'])
ddl(G,"Plain column, MySQL",MY,{"op":"addColumn","column":"note","type":"varchar(200)"},['ALTER TABLE `shop`.`orders` ADD COLUMN `note` varchar(200);'])
ddl(G,"Not null with default, MySQL",MY,{"op":"addColumn","column":"status","type":"varchar(20)","nullable":"false","default":"'new'"},["ALTER TABLE `shop`.`orders` ADD COLUMN `status` varchar(20) NOT NULL DEFAULT 'new';"])
ddl(G,"Auto increment, MySQL",MY,{"op":"addColumn","column":"id","type":"int","nullable":"false","identity":"1,1"},['ALTER TABLE `shop`.`orders` ADD COLUMN `id` int NOT NULL AUTO_INCREMENT;'])
ddl(G,"A name with a quote is escaped",PG,{"op":"addColumn","column":"a\"b","type":"text"},['ALTER TABLE "public"."orders" ADD COLUMN "a""b" text;'])
G = "Drop and rename column"
ddl(G,"Drop column, PostgreSQL",PG,{"op":"dropColumn","column":"note"},['ALTER TABLE "public"."orders" DROP COLUMN "note";'],
    should="Dropping a column does not silently drop the views and constraints that use it",
    issue="Adds CASCADE, which also drops dependent views and constraints without saying so. Whether it should is the owner's to decide")
ddl(G,"Drop column, SQL Server",MS,{"op":"dropColumn","column":"note"},['ALTER TABLE [dbo].[orders] DROP COLUMN [note];'])
ddl(G,"Drop column, MySQL",MY,{"op":"dropColumn","column":"note"},['ALTER TABLE `shop`.`orders` DROP COLUMN `note`;'])
ddl(G,"Rename column, PostgreSQL",PG,{"op":"renameColumn","column":"status","to":"state"},['ALTER TABLE "public"."orders" RENAME COLUMN "status" TO "state";'])
ddl(G,"Rename column, MySQL",MY,{"op":"renameColumn","column":"status","to":"state"},['ALTER TABLE `shop`.`orders` RENAME COLUMN `status` TO `state`;'])
ddl(G,"Rename column, SQL Server",MS,{"op":"renameColumn","column":"status","to":"state"},["EXEC sp_rename 'dbo.orders.status', 'state', 'COLUMN';"])
ddl(G,"Rename with an apostrophe in the name, SQL Server",MS,{"op":"renameColumn","column":"it's","to":"its"},["EXEC sp_rename 'dbo.orders.it''s', 'its', 'COLUMN';"],
    should="A quote in a name is doubled inside the string",issue="The apostrophe is not doubled, so the statement breaks (or runs something else)")
G = "Change a column"
ddl(G,"Change type, PostgreSQL",PG,{"op":"alterColumnType","column":"total","type":"numeric(12,2)"},['ALTER TABLE "public"."orders" ALTER COLUMN "total" TYPE numeric(12,2);'])
ddl(G,"Change type, SQL Server",MS,{"op":"alterColumnType","column":"total","type":"decimal(12,2)","nullable":"false"},['ALTER TABLE [dbo].[orders] ALTER COLUMN [total] decimal(12,2) NOT NULL;'])
ddl(G,"Change type, MySQL",MY,{"op":"alterColumnType","column":"total","type":"decimal(12,2)"},['ALTER TABLE `shop`.`orders` MODIFY COLUMN `total` decimal(12,2) NULL;'])
ddl(G,"Allow NULL, PostgreSQL",PG,{"op":"alterColumnNullability","column":"note","nullable":"true"},['ALTER TABLE "public"."orders" ALTER COLUMN "note" DROP NOT NULL;'])
ddl(G,"Disallow NULL, PostgreSQL",PG,{"op":"alterColumnNullability","column":"note","nullable":"false"},['ALTER TABLE "public"."orders" ALTER COLUMN "note" SET NOT NULL;'])
ddl(G,"Disallow NULL, SQL Server",MS,{"op":"alterColumnNullability","column":"note","nullable":"false","type":"nvarchar(200)"},['ALTER TABLE [dbo].[orders] ALTER COLUMN [note] nvarchar(200) NOT NULL;'])
ddl(G,"Set default, PostgreSQL",PG,{"op":"setDefault","column":"status","default":"'new'"},['ALTER TABLE "public"."orders" ALTER COLUMN "status" SET DEFAULT \'new\';'])
ddl(G,"Drop default, MySQL",MY,{"op":"dropDefault","column":"status"},['ALTER TABLE `shop`.`orders` ALTER COLUMN `status` DROP DEFAULT;'])
ddl(G,"Set default names the constraint after the table and column, SQL Server",MS,{"op":"setDefault","column":"status","default":"'new'"},["ALTER TABLE [dbo].[orders] ADD CONSTRAINT [DF_orders_status] DEFAULT 'new' FOR [status];"],
    should="Two tables with a status column do not get the same constraint name (names are unique per schema)",
    issue="The constraint is named DF_status, so the second table's default fails with a duplicate name")
G = "Keys and constraints"
ddl(G,"Primary key, PostgreSQL",PG,{"op":"addPrimaryKey","name":"pk_orders","columns":"id"},['ALTER TABLE "public"."orders" ADD CONSTRAINT "pk_orders" PRIMARY KEY ("id");'])
ddl(G,"Primary key on two columns, SQL Server",MS,{"op":"addPrimaryKey","name":"pk_orders","columns":"a,b"},['ALTER TABLE [dbo].[orders] ADD CONSTRAINT [pk_orders] PRIMARY KEY ([a], [b]);'])
ddl(G,"Primary key, MySQL has no name",MY,{"op":"addPrimaryKey","name":"pk_orders","columns":"id"},['ALTER TABLE `shop`.`orders` ADD PRIMARY KEY (`id`);'])
ddl(G,"Deferrable primary key, PostgreSQL",PG,{"op":"addPrimaryKey","name":"pk_orders","columns":"id","deferrable":"true","deferred":"true"},['ALTER TABLE "public"."orders" ADD CONSTRAINT "pk_orders" PRIMARY KEY ("id") DEFERRABLE INITIALLY DEFERRED;'])
ddl(G,"Unique, PostgreSQL",PG,{"op":"addUnique","name":"uq_email","columns":"email"},['ALTER TABLE "public"."orders" ADD CONSTRAINT "uq_email" UNIQUE ("email");'])
ddl(G,"Check, SQL Server",MS,{"op":"addCheck","name":"ck_total","expression":"total >= 0"},['ALTER TABLE [dbo].[orders] ADD CONSTRAINT [ck_total] CHECK (total >= 0);'])
ddl(G,"Drop constraint, PostgreSQL",PG,{"op":"dropConstraint","name":"uq_email"},['ALTER TABLE "public"."orders" DROP CONSTRAINT "uq_email";'])
ddl(G,"Drop constraint, SQL Server",MS,{"op":"dropConstraint","name":"uq_email"},['ALTER TABLE [dbo].[orders] DROP CONSTRAINT [uq_email];'])
ddl(G,"Drop the primary key, MySQL",MY,{"op":"dropConstraint","name":"PRIMARY"},['ALTER TABLE `shop`.`orders` DROP PRIMARY KEY;'])
ddl(G,"Drop a foreign key, MySQL",MY,{"op":"dropConstraint","name":"fk_customer"},['ALTER TABLE `shop`.`orders` DROP FOREIGN KEY `fk_customer`;'],
    should="Dropping a foreign key in MySQL uses DROP FOREIGN KEY; a unique or check constraint needs DROP INDEX or DROP CHECK")
ddl(G,"Foreign key with actions, PostgreSQL",PG,{"op":"addForeignKey","name":"fk_customer","columns":"customer_id","refTable":"customers","refColumns":"id","onDelete":"CASCADE","onUpdate":"NO ACTION"},['ALTER TABLE "public"."orders" ADD CONSTRAINT "fk_customer" FOREIGN KEY ("customer_id") REFERENCES "public"."customers" ("id") ON UPDATE NO ACTION ON DELETE CASCADE;'])
ddl(G,"Foreign key, SQL Server",MS,{"op":"addForeignKey","name":"fk_customer","columns":"customer_id","refTable":"customers","refColumns":"id"},['ALTER TABLE [dbo].[orders] ADD CONSTRAINT [fk_customer] FOREIGN KEY ([customer_id]) REFERENCES [dbo].[customers] ([id]);'])
ddl(G,"Foreign key across schemas, MySQL",MY,{"op":"addForeignKey","name":"fk_customer","columns":"customer_id","refSchema":"crm","refTable":"customers","refColumns":"id"},['ALTER TABLE `shop`.`orders` ADD CONSTRAINT `fk_customer` FOREIGN KEY (`customer_id`) REFERENCES `crm`.`customers` (`id`);'])
G = "Indexes"
ddl(G,"Index, PostgreSQL",PG,{"op":"createIndex","name":"ix_orders_date","columns":"created_at DESC"},['CREATE INDEX "ix_orders_date" ON "public"."orders" ("created_at" DESC);'])
ddl(G,"Unique index with include and filter, SQL Server",MS,{"op":"createIndex","name":"ix_orders_email","columns":"email","unique":"true","include":"name","filter":"email IS NOT NULL"},['CREATE UNIQUE INDEX [ix_orders_email] ON [dbo].[orders] ([email] ASC) INCLUDE ([name]) WHERE email IS NOT NULL;'])
ddl(G,"GIN index, PostgreSQL",PG,{"op":"createIndex","name":"ix_orders_doc","columns":"doc","indexType":"GIN"},['CREATE INDEX "ix_orders_doc" ON "public"."orders" USING gin ("doc" ASC);'])
ddl(G,"A plain btree index has no USING, PostgreSQL",PG,{"op":"createIndex","name":"ix_a","columns":"a","indexType":"btree"},['CREATE INDEX "ix_a" ON "public"."orders" ("a" ASC);'])
ddl(G,"Fulltext index, MySQL",MY,{"op":"createIndex","name":"ft_body","columns":"body","indexType":"fulltext"},['CREATE FULLTEXT INDEX `ft_body` ON `shop`.`orders` (`body` ASC);'])
ddl(G,"Drop index, PostgreSQL",PG,{"op":"dropIndex","name":"ix_a"},['DROP INDEX IF EXISTS "public"."ix_a";'])
ddl(G,"Drop index, SQL Server",MS,{"op":"dropIndex","name":"ix_a"},['DROP INDEX [ix_a] ON [dbo].[orders];'])
ddl(G,"Drop index, MySQL",MY,{"op":"dropIndex","name":"ix_a"},['DROP INDEX `ix_a` ON `shop`.`orders`;'])
G = "Table properties"
ddl(G,"Storage parameter, PostgreSQL",PG,{"op":"tableProperties","properties":"fillfactor = 70"},['ALTER TABLE "public"."orders" SET (fillfactor = 70);'])
ddl(G,"No properties, PostgreSQL",PG,{"op":"tableProperties"},[])
ddl(G,"Compression, SQL Server",MS,{"op":"tableProperties","properties":"DATA_COMPRESSION = PAGE"},['ALTER TABLE [dbo].[orders] REBUILD WITH (DATA_COMPRESSION = PAGE);'])
ddl(G,"Engine and comment, MySQL",MY,{"op":"tableProperties","properties":"ENGINE = InnoDB, COMMENT = 'orders'"},["ALTER TABLE `shop`.`orders` ENGINE = InnoDB, COMMENT = 'orders';"])
G = "Names"
ddl(G,"A table with a space, PostgreSQL",PG,{"op":"dropColumn","table":"Order Items","column":"x"},['ALTER TABLE "public"."Order Items" DROP COLUMN "x";'],issue="Adds CASCADE; see the drop column scenario")
ddl(G,"A table with a closing bracket, SQL Server",MS,{"op":"dropColumn","table":"a]b","column":"x"},['ALTER TABLE [dbo].[a]]b] DROP COLUMN [x];'])
ddl(G,"A table with a backtick, MySQL",MY,{"op":"dropColumn","table":"a`b","column":"x"},['ALTER TABLE `shop`.`a``b` DROP COLUMN `x`;'])

for domain, items in OUT.items():
    path = os.path.join(ROOT, domain + ".json")
    os.makedirs(ROOT, exist_ok=True)
    existing = []
    if os.path.exists(path):
        existing = json.load(open(path))
    # never overwrite what is already there: keep existing ids, add new ones
    have = {s["id"] for s in existing}
    merged = existing + [s for s in items if s["id"] not in have]
    merged.sort(key=lambda s: (len(s["id"]), s["id"]))
    with open(path, "w") as f:
        json.dump(merged, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    print(domain, len(merged))
