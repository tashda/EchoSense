#!/usr/bin/env python3
"""Turns AUTOCOMPLETE_SPEC.md into scenario files under Sources/EchoSenseScenarios/Scenarios/.

    python3 Scripts/import-spec-scenarios.py

Every ```sql block with a caret (`|`) becomes a scenario in the group of its "## N. Title" heading.
The prose under the heading and the block becomes `should`; a `=> NONE`, `=> SILENT` or
`=> [a, b, c]` line of plain identifiers becomes the expectation. Anything more descriptive
("columns from users, functions") stays as words in `should` until the owner writes the expected
result in Echo Labs. Existing scenarios with the same id are left alone, so re-running only adds.
"""
import json, re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
spec = (root / "AUTOCOMPLETE_SPEC.md").read_text().splitlines()
out_dir = root / "Sources/EchoSenseScenarios/Scenarios"

def slug(text):
    return "-".join(re.findall(r"[a-z0-9]+", text.lower()))

def prefix_for(group):
    words = re.findall(r"[A-Za-z]+", group)
    return ("".join(w[0] for w in words[:3]) if len(words) > 1 else words[0][:4]).upper()

group = None; section = None; title = None
blocks = []   # (group, section, title, sql, prose_lines)
i = 0
while i < len(spec):
    line = spec[i]
    if m := re.match(r"## (\d+)\. (.+)", line):
        group = m.group(2).strip(); section = m.group(1)
    elif m := re.match(r"### (\d+)\.(\d+) (.+)", line):
        section = f"{m.group(1)}.{m.group(2)}"; title = m.group(3).strip()
    elif line.strip() == "```sql" and group and title:
        j = i + 1; body = []
        while spec[j].strip() != "```": body.append(spec[j]); j += 1
        k = j + 1; prose = []
        while k < len(spec) and not spec[k].startswith("#") and spec[k].strip() != "```sql" and spec[k].strip() != "---":
            prose.append(spec[k]); k += 1
        sql = "\n".join(body)
        if "|" in sql: blocks.append((group, section, title, sql, prose))
        i = j
    i += 1

ident = re.compile(r"^[A-Za-z_][A-Za-z0-9_.]*$")
# Words the spec uses for a whole kind of thing; a list containing one is descriptive, not exact.
vague = {"functions", "columns", "tables", "keywords", "views", "schemas", "snippets", "parameters", "aggregates", "others", "etc"}
def expectation(prose):
    arrows = [l for l in prose if l.strip().startswith("`=>")]
    if len(arrows) != 1: return None
    text = arrows[0].strip()
    if m := re.match(r"`=> NONE`", text): return {"outcome": "none"}
    if m := re.match(r"`=> SILENT`", text): return {"outcome": "silent"}
    if m := re.match(r"`=> \[([^\]]*)\]`", text):
        items = [x.strip() for x in m.group(1).split(",")]
        if items and all(ident.match(x) and x.lower() not in vague for x in items): return {"outcome": "suggests", "items": items, "order": "leading"}
    return None

by_group = {}
used = {}
for group, section, title, sql, prose in blocks:
    # The id is the spec's own number, so "SPEC-1.4" is section 1.4; a second block in the same section gets b, c…
    n = used.get(section, 0); used[section] = n + 1
    sid = f"SPEC-{section}" + ("" if n == 0 else chr(ord("a") + n))
    dialect = "mssql" if re.search(r"--\s*MSSQL", sql) or "MSSQL" in title else "postgresql"
    text = "\n".join(l for l in prose if l.strip() and not l.strip().startswith("`=>"))
    arrow = next((l.strip().strip("`") for l in prose if l.strip().startswith("`=>")), "")
    scenario = {
        "id": sid, "group": group, "title": title,
        "should": (arrow + ("\n" if arrow and text else "") + text).strip(),
        "dialect": dialect, "schema": "spec", "sql": sql, "source": f"AUTOCOMPLETE_SPEC.md {section}", "review": "imported",
    }
    if (e := expectation(prose)): scenario["echoSense"] = e
    by_group.setdefault(group, []).append(scenario)

out_dir.mkdir(parents=True, exist_ok=True)
for stale in out_dir.glob("empty.json"): stale.unlink()
added = 0
for group, scenarios in by_group.items():
    path = out_dir / f"{slug(group)}.json"
    existing = json.loads(path.read_text()) if path.exists() else []
    known = {s["id"] for s in existing}
    new = [s for s in scenarios if s["id"] not in known]
    added += len(new)
    merged = existing + new
    path.write_text(json.dumps(merged, indent=2, sort_keys=True, ensure_ascii=False).replace("\\/", "/") + "\n")
print(f"{added} scenarios added in {len(by_group)} groups; {sum(1 for g in by_group.values() for s in g if 'echoSense' in s)} with an expectation")
