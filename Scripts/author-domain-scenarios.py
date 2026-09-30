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
