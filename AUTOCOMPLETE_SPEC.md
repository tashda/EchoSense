# EchoSense Autocomplete Specification

This document defines the **expected behavior** of EchoSense's SQL autocomplete engine.
Every rule maps to one or more behavioral tests. If the engine disagrees with this spec, the engine is wrong.

---

## Notation

- `|` marks the cursor position
- `=> [...]` lists expected completions in priority order
- `=> NONE` means no completions should appear
- `=> SILENT` means no auto-trigger; manual trigger shows empty or relevant results
- All examples use PostgreSQL dialect unless noted with `-- MSSQL`
- Default schema is `public` (PostgreSQL) or `dbo` (MSSQL)

## Test Schema

Unless otherwise specified, tests use this schema:

```
Database: mydb
Schema: public (default)
  Tables:
    users (id PK serial, name, email, created_at, department_id FK->departments.id)
    orders (id PK serial, user_id FK->users.id, total, status, created_at)
    products (id PK serial, name, price, category_id FK->categories.id)
    categories (id PK serial, name, description)
    departments (id PK serial, name, budget)
  Views:
    active_users (id, name, email)
  Materialized Views:
    user_stats (user_id, order_count, total_spent)
  Functions:
    calculate_tax(amount) -> numeric

Schema: analytics
  Tables:
    events (id PK serial, user_id, event_type, payload, created_at)
    metrics (id PK serial, name, value, recorded_at)
```

For MSSQL tests, same structure but default schema is `dbo`, PKs are identity instead of serial.

---

## Design Principles

These principles override any individual rule when in conflict:

1. **Never auto-suggest without clear intent.** Silence is better than noise.
2. **Keywords are never word-completed.** Typing `SEL` does NOT suggest `SELECT`. Keywords only appear as contextual next-clause suggestions.
3. **Space after an identifier = silence.** The user may be typing an alias.
4. **Space after a clause keyword = trigger.** `FROM `, `WHERE `, `JOIN ` trigger immediately.
5. **Dot always triggers immediately.** `u.`, `analytics.`, `otherdb.` show suggestions.
6. **Comma always triggers immediately.** Next column, next table, etc.
7. **Right-hand side of operators = silence.** `WHERE name = |` is silent until user types.
8. **No suggestions inside comments or string literals.**
9. **Manual trigger opens the popover but doesn't change what's relevant.** If nothing is relevant, popover is empty.
10. **Never crash.** All edge cases handled gracefully.

---

## Removed Features

The following features are intentionally removed from EchoSense:

- **Snippets** — Removed entirely. KISS.
- **Aggressiveness levels** (focused/balanced/eager) — One mode, done right.
- **Alias shortcuts** — `users u` auto-alias generation removed.
- **Keyword word-completion** — `SEL` -> `SELECT` removed. Keywords are contextual only.

---

## 1. SELECT Clause

### 1.1 Empty SELECT, no tables in scope

```sql
SELECT |
```

`=> NONE` — No tables in FROM yet, nothing useful to suggest.

### 1.2 SELECT with tables in scope (cursor jumped back)

```sql
SELECT | FROM users
```

`=> [columns from users, functions]`
- Columns ranked first, PK `id` boosted highest
- FK columns (`department_id`) boosted above regular columns
- Functions ranked below columns
- No tables, no schemas, no keywords

### 1.3 SELECT with partial typing

```sql
SELECT na| FROM users
```

`=> [name]` — Columns matching "na" first, then functions matching "na" (ranked lowest).

### 1.4 SELECT after comma — deduplication

```sql
SELECT id, | FROM users
```

`=> [name, email, created_at, department_id, functions]`
- `id` is excluded — already in the SELECT list
- Deduplication applies to top-level column references only

### 1.5 SELECT after comma with partial typing

```sql
SELECT id, na| FROM users
```

`=> [name]`

### 1.6 SELECT with multiple tables — smart qualification

```sql
SELECT | FROM users u JOIN orders o ON u.id = o.user_id
```

- **Unique columns** (exist in only one table) → unqualified: `name`, `email`, `total`, `status`, `department_id`, `user_id`
- **Ambiguous columns** (exist in multiple tables) → qualified: `u.id`, `o.id`, `u.created_at`, `o.created_at`
- Sorted by relevance and history, not grouped by table

### 1.7 SELECT with alias dot

```sql
SELECT u.| FROM users u JOIN orders o ON u.id = o.user_id
```

`=> [id, name, email, created_at, department_id]` — Only columns from `users`.
- Insert text is just the column name (`name`), since `u.` is already typed.

### 1.8 SELECT with alias dot and partial typing

```sql
SELECT u.na| FROM users u
```

`=> [name]`

### 1.9 SELECT with table name dot (no alias)

```sql
SELECT users.| FROM users
```

`=> [id, name, email, created_at, department_id]`

### 1.10 SELECT DISTINCT

```sql
SELECT DISTINCT | FROM users
```

`=> [columns from users, functions]` — Same as regular SELECT with tables in scope.

### 1.11 CASE WHEN

```sql
SELECT id, CASE WHEN | FROM users
```

`=> [columns from users]`

### 1.12 CASE THEN

```sql
SELECT CASE WHEN status = 'active' THEN | FROM users
```

`=> [columns from users, functions]`

### 1.13 CASE ELSE

```sql
SELECT CASE WHEN status = 'active' THEN name ELSE | FROM users
```

`=> [columns from users, functions]`

### 1.14 Partial typing with ambiguous column — both shown qualified

```sql
SELECT na| FROM users u JOIN orders o ON u.id = o.user_id
```

If `name` exists in both `users` and `orders`:
`=> [u.name, o.name]` — Both shown with alias, insert text includes qualifier.

If `name` only exists in `users`:
`=> [name]` — Unqualified.

### 1.15 Window function does not count as SELECT-list deduplication

```sql
SELECT ROW_NUMBER() OVER (PARTITION BY id ORDER BY name), | FROM users
```

`=> [id, name, email, ...]` — `id` and `name` are NOT excluded (they're inside a function, not top-level SELECT columns).

---

## 2. FROM Clause

### 2.1 After FROM keyword

```sql
SELECT * FROM |
```

`=> [tables/views/materialized views from all schemas, schema names]`
- History-boosted items first
- Default schema tables above non-default schema tables
- Tables and materialized views ranked slightly above views
- Schemas ranked equally with tables
- Schema suggestions insert with trailing dot (`analytics.`)

### 2.2 After FROM with partial typing

```sql
SELECT * FROM us|
```

`=> [users]` — Prefix match.

### 2.3 After FROM with schema dot

```sql
SELECT * FROM analytics.|
```

`=> [events, metrics]` — Tables/views from `analytics` schema only.

### 2.4 After FROM with schema dot and partial typing

```sql
SELECT * FROM analytics.ev|
```

`=> [events]`

### 2.5 After FROM with comma — additional table

```sql
SELECT * FROM users, |
```

`=> [tables/views]` — Immediately show tables.

### 2.6 Space after table on same line — SILENCE

```sql
SELECT * FROM users |
```

`=> SILENT` — User may be typing an alias. No suggestions at all.

### 2.7 New line after table — keywords only on typing

```sql
SELECT * FROM users
|
```

`=> SILENT` — Even on new line, wait for user input.

```sql
SELECT * FROM users
W|
```

`=> [WHERE]` — Contextual keyword match.

```sql
SELECT * FROM users
J|
```

`=> [JOIN]`

```sql
SELECT * FROM users
IN|
```

`=> [INNER JOIN]`

### 2.8 INSERT INTO

```sql
INSERT INTO |
```

`=> [tables]` — Only tables (not views).

### 2.9 UPDATE

```sql
UPDATE |
```

`=> [tables]`

### 2.10 DELETE FROM

```sql
DELETE FROM |
```

`=> [tables]`

### 2.11 Default schema tables unqualified, non-default qualified

For `users` in `public` (default): insert text is `users`.
For `events` in `analytics`: insert text is `analytics.events`.

When `preferQualifiedTableInsertions` is enabled:
All tables insert with schema prefix: `public.users`, `analytics.events`.

### 2.12 Multiple schemas with same table name

If both `public.users` and `analytics.users` exist:
- Both appear as suggestions
- Schema shown in subtitle to distinguish them
- Default schema version ranked higher

---

## 3. JOIN

### 3.1 JOIN target — FK suggestions immediately

```sql
SELECT * FROM users u JOIN |
```

`=> [FK-based join targets first, then regular tables]`
- `orders` with auto ON clause: insert text `orders o ON u.id = o.user_id`
- `departments` with auto ON clause: insert text `departments d ON u.department_id = d.id`
- Then remaining tables without ON clause
- Tables already in scope (`users`) excluded from join targets
- FK join auto-ON is a toggleable setting

### 3.2 JOIN target with partial typing

```sql
SELECT * FROM users u JOIN or|
```

`=> [orders (with ON clause)]`

### 3.3 Multiple JOINs — already-joined tables excluded

```sql
SELECT * FROM users u JOIN orders o ON u.id = o.user_id JOIN |
```

- `users` and `orders` excluded from suggestions
- Remaining tables shown

### 3.4 LEFT/RIGHT/FULL JOIN — same as regular JOIN

```sql
SELECT * FROM users u LEFT JOIN |
```

`=> [same as regular JOIN]`

### 3.5 JOIN ON — FK condition suggestions

```sql
SELECT * FROM users u JOIN orders o ON |
```

`=> [u.id = o.user_id (FK-based), then columns from both tables]`

### 3.6 JOIN ON with alias dot

```sql
SELECT * FROM users u JOIN orders o ON u.|
```

`=> [id, name, email, created_at, department_id]` — Columns from `users`.

### 3.7 Self-join — qualified columns only, no auto-condition

```sql
SELECT * FROM users u1 JOIN users u2 ON |
```

`=> [u1.id, u1.name, ..., u2.id, u2.name, ...]` — All columns qualified with alias. No auto-generated condition.

### 3.8 CROSS APPLY / OUTER APPLY (MSSQL)

```sql
-- MSSQL
SELECT * FROM users u CROSS APPLY |
```

`=> [tables/functions]` — Behaves like JOIN target.

---

## 4. WHERE Clause

### 4.1 After WHERE — columns immediately

```sql
SELECT * FROM users WHERE |
```

`=> [columns from users, functions]` — Columns ranked first.

### 4.2 WHERE with partial typing

```sql
SELECT * FROM users WHERE na|
```

`=> [name]`

### 4.3 Right-hand side of operator — SILENT

```sql
SELECT * FROM users WHERE name = |
```

`=> SILENT` — User most likely typing a literal value.

On manual trigger: show columns from other tables (if any) first, then functions, then same-table columns, then parameters.

### 4.4 After AND/OR — columns immediately

```sql
SELECT * FROM users WHERE name = 'foo' AND |
```

`=> [columns from users, functions]`

### 4.5 WHERE with multiple tables — smart qualification

```sql
SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE |
```

Same rules as SELECT: unique columns unqualified, ambiguous columns qualified.

### 4.6 WHERE with alias dot

```sql
SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.|
```

`=> [id, name, email, created_at, department_id]` — Only `users` columns.

### 4.7 Parameters only on sigil

```sql
SELECT * FROM users WHERE id = $|
```

`=> [$1]` — PostgreSQL parameter. Only shown when `$` is typed.

```sql
-- MSSQL
SELECT * FROM users WHERE id = @|
```

`=> [@p1]` — MSSQL parameter. Only shown when `@` is typed.

### 4.8 WHERE IN — silent after open paren

```sql
SELECT * FROM users WHERE id IN (|
```

`=> SILENT` — User might type literals.

```sql
SELECT * FROM users WHERE id IN (na|
```

`=> [name]` — Column suggestion once user types.

### 4.9 WHERE EXISTS subquery

```sql
SELECT * FROM users u WHERE EXISTS (SELECT 1 FROM orders o WHERE o.|)
```

`=> [columns from orders]`

### 4.10 Operator keywords — only on typing, not after space

```sql
SELECT * FROM users WHERE name |
```

`=> SILENT` — Same line after identifier.

```sql
SELECT * FROM users WHERE name I|
```

`=> [ILIKE (PostgreSQL), IN, IS NULL, IS NOT NULL]` — Operator keywords on typing.

---

## 5. GROUP BY / ORDER BY / HAVING

### 5.1 GROUP BY — prioritize SELECT-list columns

```sql
SELECT department_id, COUNT(*) FROM users GROUP BY |
```

`=> [department_id (top), then remaining columns]`
- Columns that appear in the SELECT list are ranked first.

### 5.2 ORDER BY — prioritize SELECT-list columns

```sql
SELECT name, email FROM users ORDER BY |
```

`=> [name (top), email (top), then remaining columns]`

### 5.3 ORDER BY with partial typing

```sql
SELECT * FROM users ORDER BY na|
```

`=> [name]`

### 5.4 ORDER BY direction — auto-suggest after column

```sql
SELECT * FROM users ORDER BY name |
```

`=> [ASC, DESC, NULLS FIRST, NULLS LAST]` — Exception to space-after-identifier rule.

### 5.5 ORDER BY after comma

```sql
SELECT * FROM users ORDER BY name ASC, |
```

`=> [columns from users]` — Immediately.

### 5.6 HAVING — aggregates ranked highest

```sql
SELECT department_id, COUNT(*) FROM users GROUP BY department_id HAVING |
```

Order:
1. Aggregate functions (`COUNT(`, `SUM(`, `AVG(`, `MIN(`, `MAX(`)
2. Columns from tables in scope
3. Other functions

---

## 6. INSERT / UPDATE / DELETE

### 6.1 INSERT column list — auto-increment deprioritized

```sql
INSERT INTO users (|)
```

`=> [name, email, created_at, department_id]`
- Auto-increment/serial/identity columns (`id`) deprioritized (shown last or excluded).

### 6.2 INSERT VALUES — silent

```sql
INSERT INTO users (name, email) VALUES (|)
```

`=> SILENT` — User typing literal values.

### 6.3 UPDATE SET — columns immediately

```sql
UPDATE users SET |
```

`=> [columns from users]`

### 6.4 UPDATE SET right-hand side — silent

```sql
UPDATE users SET name = |
```

`=> SILENT` — Same rule as WHERE right-hand side.

### 6.5 UPDATE SET after comma — columns immediately

```sql
UPDATE users SET name = 'foo', |
```

`=> [columns from users]`

### 6.6 DELETE WHERE

```sql
DELETE FROM users WHERE |
```

`=> [columns from users, functions]`

---

## 7. CTEs (Common Table Expressions)

### 7.1 CTE with explicit column list

```sql
WITH active(id, name) AS (SELECT id, name FROM users WHERE status = 'active')
SELECT | FROM active
```

`=> [id, name]` — CTE columns from explicit list.

### 7.2 CTE without explicit column list — infer from inner SELECT

```sql
WITH active AS (SELECT id, name FROM users WHERE status = 'active')
SELECT | FROM active
```

`=> [id, name]` — Columns inferred from inner SELECT.

### 7.3 CTE with aliased columns — use aliases

```sql
WITH active AS (SELECT id AS user_id, name AS user_name FROM users)
SELECT | FROM active
```

`=> [user_id, user_name]` — Aliased column names.

### 7.4 CTE with SELECT * — resolve to actual columns

```sql
WITH active AS (SELECT * FROM users)
SELECT | FROM active
```

`=> [id, name, email, created_at, department_id]` — Resolved from `users` metadata.

### 7.5 CTE name as table in FROM

```sql
WITH active(id, name) AS (SELECT id, name FROM users)
SELECT * FROM |
```

`=> [active, users, orders, ...]` — CTE name appears as a table option.

### 7.6 CTE column with dot access

```sql
WITH active(id, name) AS (SELECT id, name FROM users)
SELECT active.| FROM active
```

`=> [id, name]`

### 7.7 Multiple CTEs — smart qualification

```sql
WITH
  active(id, name) AS (SELECT id, name FROM users),
  recent_orders(id, total) AS (SELECT id, total FROM orders)
SELECT | FROM active a JOIN recent_orders r ON a.id = r.id
```

- `id` exists in both → qualified: `a.id`, `r.id`
- `name` unique → unqualified: `name`
- `total` unique → unqualified: `total`

### 7.8 CTE column lookup is case-insensitive

```sql
WITH Active(Id, Name) AS (SELECT id, name FROM users)
SELECT | FROM Active
```

`=> [Id, Name]` — Case-insensitive lookup, preserves original casing.

### 7.9 CTE before INSERT

```sql
WITH source(id, name) AS (SELECT id, name FROM users)
INSERT INTO |
```

`=> [tables]` — CTE doesn't change INSERT behavior.

---

## 8. Derived Tables (Subqueries in FROM)

### 8.1 Derived table — columns from inner SELECT

```sql
SELECT sub.| FROM (SELECT id, name FROM users) sub
```

`=> [id, name]`

### 8.2 Derived table with aliased columns

```sql
SELECT sub.| FROM (SELECT id AS user_id, name AS user_name FROM users) sub
```

`=> [user_id, user_name]`

### 8.3 Derived table with SELECT * — resolve

```sql
SELECT sub.| FROM (SELECT * FROM users) sub
```

`=> [id, name, email, created_at, department_id]` — Resolved from `users` metadata.

### 8.4 Nested derived tables

```sql
SELECT outer_sub.| FROM (SELECT inner_sub.id FROM (SELECT id FROM users) inner_sub) outer_sub
```

`=> [id]`

---

## 9. Dot Path Completions

### 9.1 Table dot — columns

```sql
SELECT users.| FROM users
```

`=> [id, name, email, created_at, department_id]`

### 9.2 Alias dot — columns

```sql
SELECT u.| FROM users u
```

`=> [id, name, email, created_at, department_id]`

### 9.3 Schema dot — tables

```sql
SELECT * FROM analytics.|
```

`=> [events, metrics]`

### 9.4 Schema.table dot — columns

```sql
SELECT analytics.events.| FROM analytics.events
```

`=> [id, user_id, event_type, payload, created_at]`

### 9.5 Cross-database dot (MSSQL)

```sql
-- MSSQL, databases: mydb, otherdb
SELECT * FROM otherdb.|
```

`=> [tables from otherdb]` — Insert text includes full path: `otherdb.dbo.tablename`.
Status API reports loading state: Loading → Loaded / Not Found.

```sql
SELECT * FROM otherdb.dbo.|
```

`=> [tables from otherdb.dbo]`

### 9.6 Database names never auto-suggested

```sql
SELECT * FROM |
```

Database names do NOT appear. Only activate when user types a known database name + dot.

### 9.7 Dot with partial typing

```sql
SELECT u.na| FROM users u
```

`=> [name]`

### 9.8 Dot after unknown alias — no crash

```sql
SELECT x.| FROM users u
```

`=> NONE` — No columns, no crash.

---

## 10. Star Expansion

### 10.1 Single table — unqualified

```sql
SELECT *| FROM users
```

Manual trigger required. `=> ["Expand * to columns"]`
Insert text: `id, name, email, created_at, department_id` (unqualified).

### 10.2 Multiple tables — all qualified

```sql
SELECT *| FROM users u JOIN orders o ON u.id = o.user_id
```

Manual trigger required. `=> ["Expand * to columns"]`
Insert text: `u.id, u.name, u.email, u.created_at, u.department_id, o.id, o.user_id, o.total, o.status, o.created_at` (ALL qualified).

### 10.3 Alias-qualified star

```sql
SELECT u.*| FROM users u JOIN orders o ON u.id = o.user_id
```

Manual trigger required. `=> ["Expand * to columns"]`
Insert text: `u.id, u.name, u.email, u.created_at, u.department_id` (only `users` columns, qualified).

### 10.4 Star expansion requires manual trigger

Without manual trigger: `=> NONE`.

### 10.5 Star expansion only in SELECT

Not available in FROM, WHERE, or any other clause.

---

## 11. Functions

### 11.1 Functions in SELECT — ranked below columns

```sql
SELECT CO| FROM users
```

`=> [columns matching "CO" first, then COUNT(), COALESCE(), CONCAT()]`

### 11.2 Functions insert with parentheses

- Functions with arguments: insert `COUNT()` with cursor between parens.
- Functions without arguments: insert `NOW()` with cursor after closing paren.

### 11.3 Functions in WHERE

```sql
SELECT * FROM users WHERE LOW|
```

`=> [LOWER()]`

### 11.4 Functions in HAVING

```sql
SELECT department_id FROM users GROUP BY department_id HAVING CO|
```

`=> [COUNT()]` — Aggregates ranked highest in HAVING.

### 11.5 Functions are dialect-specific

- PostgreSQL: `STRING_AGG(`, `ARRAY_AGG(`, `UNNEST(` — NOT `STUFF(`, `ISNULL(`
- MSSQL: `ISNULL(`, `STUFF(`, `CONVERT(` — NOT `IFNULL(`, `UNNEST(`

### 11.6 Functions NOT in FROM clause

```sql
SELECT * FROM CO|
```

Functions do NOT appear in FROM context.

### 11.7 User-defined functions

```sql
SELECT calc| FROM users
```

`=> [calculate_tax()]` — User-defined functions from schema.

---

## 12. Parameters

### 12.1 Parameters only on sigil character

Parameters are NOT shown by default. They appear only when the user types the dialect's parameter prefix:

- PostgreSQL: `$` → `$1`, `$2`, ...
- MSSQL: `@` → `@p1`, `@p2`, ...
- MySQL: `?` → `?`

### 12.2 Parameter numbering auto-increments

```sql
-- PostgreSQL
SELECT * FROM users WHERE id = $1 AND name = $|
```

`=> [$2]` — Next parameter number.

---

## 13. Keywords

### 13.1 Never word-completed

```sql
SEL|
```

`=> NONE` — Typing `SEL` does NOT suggest `SELECT`.

```sql
WHER|
```

`=> NONE`

### 13.2 Contextual keyword suggestions — new line + typing

```sql
SELECT * FROM users
W|
```

`=> [WHERE]` — Contextual match after new line.

```sql
SELECT * FROM users
IN|
```

`=> [INNER JOIN]`

### 13.3 Same line after identifier — no keywords

```sql
SELECT * FROM users W|
```

`=> NONE` — User might be typing an alias.

### 13.4 Always UPPERCASE

Keywords insert as `WHERE`, `SELECT`, `JOIN` — never lowercase.

### 13.5 ORDER BY direction — exception to space rule

```sql
SELECT * FROM users ORDER BY name |
```

`=> [ASC, DESC, NULLS FIRST, NULLS LAST]` — Auto-suggested after ORDER BY column.

### 13.6 Operator keywords — on typing only

```sql
SELECT * FROM users WHERE name I|
```

`=> [ILIKE (PostgreSQL), IN, IS NULL, IS NOT NULL]`

---

## 14. History

### 14.1 History boosts previously selected items

If `users` was previously selected in FROM, it ranks higher next time.
History boost applies to ALL matching suggestions, not just history-sourced ones.

### 14.2 Context key — database type + database name

Key format: `{databaseType}|{selectedDatabase}`.
Schema is NOT part of the key.

### 14.3 Frequency over recency

An item selected 10 times ranks above an item selected once, regardless of recency.

### 14.4 Persistable kinds

- **Persist**: tables, views, materialized views, columns, functions, joins
- **Don't persist**: keywords, parameters

### 14.5 History disabled

When history is disabled: no history suggestions, no history boost.

---

## 15. Identifier Quoting

### 15.1 Auto-quote aggressively

Any identifier that could conflict with a SQL keyword or data type is auto-quoted:
- Reserved words: `order`, `select`, `datetime`, `date`, `time`, `user`, `type`, `status`
- Data type keywords: `integer`, `varchar`, `text`, `boolean`
- CamelCase in PostgreSQL: `UserData`
- Special characters or spaces

### 15.2 Dialect-specific quoting

- PostgreSQL: `"Order"`, `"UserData"`
- MSSQL: `[Order]`
- MySQL: `` `Order` ``

### 15.3 Plain identifiers — no quoting

`users`, `my_table`, `order_items` — no quoting needed.

---

## 16. Insert Text Behavior

### 16.1 Default schema tables — unqualified

`users` in `public` → insert `users`.

### 16.2 Non-default schema tables — qualified

`events` in `analytics` → insert `analytics.events`.

### 16.3 Qualified insertion preference (toggle)

When enabled: all tables insert with schema prefix (`public.users`, `analytics.events`).

### 16.4 Already-typed path components stripped

```sql
SELECT u.| FROM users u
```

Suggestion insert text is `name`, not `u.name`. The `u.` is already typed.

### 16.5 Comma spacing (toggle)

When accepting a suggestion after a comma:
`SELECT id,|` + accept `name` → `SELECT id, name` (auto-space after comma).
Toggleable preference.

### 16.6 Function parentheses

- With arguments: `COUNT()` — cursor between parens
- Without arguments: `NOW()` — cursor after closing paren

---

## 17. Suppression Rules

### 17.1 Post-commit suppression

After accepting a suggestion:
- Same position, same clause → suppress
- User types characters that extend the token → re-enable (e.g., accepted `Users`, types `R` → suggest `UsersReview`)
- User types space → stay suppressed
- User moves cursor elsewhere → clear suppression

### 17.2 Reserved keyword as complete token

```sql
SELECT|
```

`=> NONE` — Complete reserved keyword suppresses.

### 17.3 After star without manual trigger

```sql
SELECT * |
```

`=> SILENT`

### 17.4 No tables in scope — empty SELECT

```sql
SELECT |
```

`=> NONE` — Unless manual trigger (which shows empty if nothing relevant).

### 17.5 Inside comments

```sql
SELECT * FROM users -- WHERE |
```

`=> NONE`

```sql
SELECT * FROM users /* WHERE | */
```

`=> NONE`

### 17.6 Inside string literals

```sql
SELECT * FROM users WHERE name = 'Jo|
```

`=> NONE`

---

## 18. Ranking

### 18.1 Ranking factors (in order of influence)

1. **Context relevance** — columns in SELECT/WHERE, tables in FROM, etc.
2. **History boost** — frequency * 45 + recency decay
3. **Prefix match bonus** — exact prefix >> fuzzy match
4. **Shorter match bonus** — `users` beats `user_sessions` for `us`
5. **PK/FK boost** — PKs ranked above FKs, FKs above regular columns
6. **Focus table boost** — columns from the nearest table before cursor
7. **Fuzzy penalty** — proportional to match quality gap

### 18.2 Table vs view ranking

Tables and materialized views ranked slightly above views.

### 18.3 Auto-increment deprioritized in INSERT

Serial/identity columns ranked last in INSERT column list.

### 18.4 GROUP BY / ORDER BY prioritize SELECT-list columns

Columns appearing in the SELECT list ranked first.

### 18.5 HAVING prioritizes aggregate functions

`COUNT(`, `SUM(`, `AVG(` ranked above columns.

---

## 19. System Schemas

### 19.1 Hidden by default

- PostgreSQL: `pg_catalog`, `information_schema` hidden
- MSSQL: `sys`, `INFORMATION_SCHEMA` hidden

### 19.2 Visible via toggle

When `includeSystemSchemas` is enabled, system schema tables appear.

---

## 20. Multi-Statement & Set Operations

### 20.1 Semicolon resets context

```sql
SELECT * FROM users; SELECT | FROM orders
```

Second statement suggests `orders` columns, not `users`.

### 20.2 UNION / INTERSECT / EXCEPT

```sql
SELECT id FROM users UNION SELECT | FROM orders
```

Fresh SELECT context — suggests `orders` columns.

---

## 21. Procedure Calls

### 21.1 EXEC (MSSQL)

```sql
-- MSSQL
EXEC |
```

`=> [stored procedures/functions]`

### 21.2 CALL (PostgreSQL)

```sql
CALL |
```

`=> [stored procedures/functions]`

---

## 22. PostgreSQL-Specific

### 22.1 RETURNING

```sql
INSERT INTO users (name) VALUES ('foo') RETURNING |
```

`=> [columns from users]`

### 22.2 ON CONFLICT — columns

```sql
INSERT INTO users (name) VALUES ('foo') ON CONFLICT |
```

`=> [columns from users]` — For conflict target.

### 22.3 ON CONFLICT DO

```sql
INSERT INTO users (name) VALUES ('foo') ON CONFLICT (name) DO |
```

`=> [NOTHING, UPDATE SET]`

---

## 23. MSSQL-Specific

### 23.1 Bracket quoting

```sql
-- MSSQL
SELECT * FROM [Order] o WHERE o.|
```

Resolves `[Order]` and shows its columns.

---

## 24. Cross-Database (MSSQL)

### 24.1 Database names never auto-suggested in FROM

```sql
SELECT * FROM |
```

No database names shown.

### 24.2 Database dot triggers lazy load

```sql
SELECT * FROM otherdb.|
```

- EchoSense lazy-loads metadata for `otherdb`
- Returns status: Loading → Loaded / Not Found
- Once loaded, shows tables (insert text: `otherdb.dbo.tablename`)

### 24.3 Database.schema.table path

```sql
SELECT * FROM otherdb.dbo.|
```

`=> [tables from otherdb.dbo]`

---

## 25. Window Functions

### 25.1 PARTITION BY

```sql
SELECT ROW_NUMBER() OVER (PARTITION BY | ) FROM users
```

`=> [columns from users]`

### 25.2 ORDER BY inside OVER

```sql
SELECT ROW_NUMBER() OVER (ORDER BY | ) FROM users
```

`=> [columns from users]`

### 25.3 After OVER closes — back to SELECT context

```sql
SELECT ROW_NUMBER() OVER (PARTITION BY id), | FROM users
```

`=> [columns from users]` — `id` NOT excluded (inside function, not top-level SELECT).

---

## 26. Edge Cases

### 26.1 Empty input

```sql
|
```

`=> NONE`

### 26.2 Cursor past end of string

Clamp to string length, no crash.

### 26.3 Very long SQL

10K+ characters — should still work. Performance benchmark test determines threshold.

### 26.4 Unclosed string literal

```sql
SELECT * FROM users WHERE name = 'incomplete|
```

`=> NONE` — Inside string, no crash.

### 26.5 Unclosed parenthesis

```sql
SELECT * FROM users WHERE id IN (|
```

`=> SILENT` — Silent after open paren, suggestions on typing.

### 26.6 CRLF and tab characters

Handled identically to Unix line endings and spaces.

### 26.7 Reserved words as table names

```sql
SELECT * FROM "Order" o WHERE o.|
```

Resolves quoted identifier, shows columns.

### 26.8 Nil/empty database structure

No suggestions. `isMetadataLimited = true`. No crash.

### 26.9 Subquery in WHERE — fresh scope

```sql
SELECT * FROM users WHERE id IN (SELECT | FROM orders)
```

`=> NONE` — No tables in scope for the subquery's SELECT yet... wait, `orders` IS in scope.

Actually: `=> [columns from orders]` since `FROM orders` gives context.

---

## Appendix: Toggleable Settings

| Setting | Default | Effect |
|---------|---------|--------|
| `preferQualifiedTableInsertions` | false | Always insert schema prefix |
| `includeHistory` | true | History suggestions and boost |
| `includeSystemSchemas` | false | Show system schema objects |
| `autoJoinOnClause` | true | FK-based JOIN inserts include ON clause |
| `commaSpacing` | true | Auto-insert space after comma on accept |
