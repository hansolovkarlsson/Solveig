; sql.sol -- an SQL shell over lib/sqlite.sol: statements in, rows out.
;
; Run with:  ./bin/solas programs/sql.sol && ./bin/solvm programs/sql.sob
; Over a file:  ./bin/solvm programs/sql.sob notes.db < statements.sql
; Or one statement:  ./bin/solvm programs/sql.sob notes.db 'SELECT * FROM t'
; With no arguments it demonstrates itself on a file it writes under build/.
;
; The twenty-third program here, and the first of the directions design.md
; lists to be reached. It was programs/sqlite.sol, engine and shell in one
; file, until 2026-09-15; the engine is lib/sqlite.sol now, and this is
; what is left when it goes: the SQL tokens made into statements, each
; statement parsed and run against the engine, and SELECT answered in the
; shell's default list mode, columns with `|` between them, nothing for
; NULL, one row a line. That is so the two can be compared byte for byte,
; which is what programs/sql/sweep.sh does in both directions: `sqlite3`
; builds every database in the corpus and `sqlite3` says what is in it, and
; then this program builds the same databases and `sqlite3` judges the
; files, with `PRAGMA integrity_check` and by reading them.
;
; The plan is in ideas.md under *An SQLite file, read and then written*,
; with what it predicted written above what it found, and the split is
; under *The database as objects*. The SQL it parses is the SQL the plan
; bounds: SELECT of named columns, `rowid` or `*`, from one table, with a
; WHERE of comparisons on columns joined by AND and an ORDER BY; CREATE
; TABLE with plain columns; CREATE INDEX on plain columns; INSERT of
; literals; PRAGMA page_size; DELETE with the same WHERE; and UPDATE of
; literals with the same WHERE, which the plan had left out and the objects
; brought in, since sqlite3 could not judge the library's `update` without
; a statement to reach it by. Nothing else, and
; a statement outside that is reported as such rather than quietly meaning
; something else. `SQLITE_PAGES=1` in the environment reports how many
; pages a run read and how many bytes it wrote, which are the numbers a
; statement is measured by here.
;
; What the format is, and the three things about the language found while
; writing it, are at the top of lib/sqlite.sol, where the code they are
; about now lives.

@include "sqlite.sol".

; ---------------------------------------------------------------------------
; SELECT
;
; Parsed into: the columns wanted (each a name, or `*`), the table, the
; WHERE as [column, value] or nil, and the ORDER BY as a list of columns.
; The parser is a cursor over the statement's tokens, and past the end it
; reads an 'end token rather than falling off the array.

tok := { tokens, i | i:greaterThan(tokens:size):ifElse({ ['end, ""] }, { tokens:at(i) }) }.

; Punctuation is matched by kind as well as text: a blob of the one byte
; `)` or the text `','` is a value, and the first sweep of the writer found
; a value list ending at one.
isPunct := { tokens, i, ch | | t | t := tok:value(tokens, i). t:at(#1):equals('punct):and({ t:at(#2):equals(ch) }) }.

expect := { tokens, i, text |
    (i:greaterThan(tokens:size):or({ tok:value(tokens, i):at(#2):asUppercase:notEquals(text:asUppercase) })):ifTrue({
        error:raise("expected ":concat(text):concat(i:greaterThan(tokens:size):ifElse({ " at the end" },
            { " and found ":concat(tokens:at(i):at(#2)) }))) }).
    i:inc }.

isWord := { tokens, i, text |
    i:lessOrEqual(tokens:size):and({ tok:value(tokens, i):at(#1):equals('word) })
        :and({ tok:value(tokens, i):at(#2):asUppercase:equals(text) }) }.

; A literal: a number with an optional sign, text, a blob, or NULL. Answers
; the value and the index after it.
numberLiteral := { text, negative | | signed |
    ; The sign goes on before the digits are read, so that -9223372036854775808
    ; is the integer it is rather than an overflow negated: SQLite reads the
    ; minimum the same way, and a corpus row found the difference.
    signed := negative:ifElse({ "-":concat(text) }, { text }).
    (text:indexOf("."):isNil:and({ text:asUppercase:indexOf("E"):isNil })):ifElse(
        { { signed:asInteger }:onError({ e |
              ; Too large for an integer: SQLite reads it as a real.
              sqlite:real:of(sqlite:floatParts(signed:asFloat)) }) },
        { sqlite:real:of(sqlite:floatParts(signed:asFloat)) }) }.

literal := { tokens, i | | t, negative |
    t := tok:value(tokens, i).
    t:at(#1):equals('end):ifTrue({ error:raise("a value is missing at the end") }).
    negative := false.
    (t:at(#1):equals('punct):and({ t:at(#2):equals("-") })):ifTrue({
        negative := true. i := i:inc. t := tok:value(tokens, i) }).
    t:at(#1):equals('number):ifElse({ [numberLiteral:value(t:at(#2), negative), i:inc] },
        { t:at(#1):equals('text):ifElse({ [t:at(#2), i:inc] },
            { t:at(#1):equals('blob):ifElse({ [sqlite:blob:of(t:at(#2)), i:inc] },
                { (t:at(#1):equals('word):and({ t:at(#2):asUppercase:equals("NULL") })):ifElse(
                    { [nil, i:inc] },
                    { error:raise("not a literal: ":concat(t:at(#2))) }) }) }) }) }.

; A column reference: a name, optionally qualified by the table.
columnRef := { tokens, i | | name |
    name := tok:value(tokens, i):at(#2).
    i := i:inc.
    (i:lessOrEqual(tokens:size):and({ tok:value(tokens, i):at(#1):equals('punct) }):and({ tok:value(tokens, i):at(#2):equals(".") })):ifTrue({
        name := tok:value(tokens, i:inc):at(#2). i := i:add(#2) }).
    [name, i] }.

; WHERE: comparisons on columns joined by AND, each [column, op, literal]
; with op one of = < > <= >=. Answers the terms and the index after them.
parseWhere := { tokens, i | | terms, r, op, done |
    terms := []. done := false.
    { done:not }:whileTrue({
        r := columnRef:value(tokens, i). i := r:at(#2).
        op := tok:value(tokens, i):at(#2).
        tok:value(tokens, i):at(#1):equals('punct):ifFalse({ error:raise("expected a comparison and found ":concat(op)) }).
        i := i:inc.
        (op:equals("<"):or({ op:equals(">") })):and({ isPunct:value(tokens, i, "=") }):ifTrue({
            op := op:concat("="). i := i:inc }).
        (["=", "<", ">", "<=", ">="]:indexOf(op)):isNil:ifTrue({
            error:raise("only = < > <= and >= are understood, not ":concat(op)) }).
        terms:add([r:at(#1), op, nil]).
        r := literal:value(tokens, i). i := r:at(#2).
        terms:at(terms:size):atPut(#3, r:at(#1)).
        isWord:value(tokens, i, "AND"):ifElse({ i := i:inc }, { done := true }) }).
    [terms, i] }.

parseSelect := { tokens | | i, columns, tableName, where, order, r, done |
    i := expect:value(tokens, #1, "SELECT").
    columns := []. done := false.
    { done:not }:whileTrue({
        (tok:value(tokens, i):at(#1):equals('punct):and({ tok:value(tokens, i):at(#2):equals("*") })):ifElse(
            { columns:add("*"). i := i:inc },
            { r := columnRef:value(tokens, i). columns:add(r:at(#1)). i := r:at(#2) }).
        isPunct:value(tokens, i, ","):ifElse(
            { i := i:inc }, { done := true }) }).
    i := expect:value(tokens, i, "FROM").
    tableName := tok:value(tokens, i):at(#2). i := i:inc.
    where := []. order := [].
    isWord:value(tokens, i, "WHERE"):ifTrue({
        i := i:inc.
        r := parseWhere:value(tokens, i). where := r:at(#1). i := r:at(#2) }).
    isWord:value(tokens, i, "ORDER"):ifTrue({
        i := i:inc.
        i := expect:value(tokens, i, "BY").
        done := false.
        { done:not }:whileTrue({
            r := columnRef:value(tokens, i). i := r:at(#2).
            order:add(r:at(#1)).
            isWord:value(tokens, i, "ASC"):ifTrue({ i := i:inc }).
            isPunct:value(tokens, i, ","):ifElse(
                { i := i:inc }, { done := true }) }) }).
    i:lessOrEqual(tokens:size):ifTrue({
        error:raise("this SELECT goes on past what is understood, at: ":concat(tok:value(tokens, i):at(#2))) }).
    [columns, tableName, where, order] }.

; Where the output goes: gathered and written once.
out := [].
emit := { line | out:add(line):add("\n") }.

runSelect := { d, parsed | | t, wanted, q |
    t := d:table(parsed:at(#2)).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(parsed:at(#2))) }).
    ; The columns to print, resolved to the keys a row has; `*` is every
    ; column of the table.
    wanted := [].
    parsed:at(#1):do({ c |
        c:equals("*"):ifElse(
            { t:columns:do({ col | wanted:add(col:at(#3):ifElse({ 'rowid }, { col:at(#1):asSymbol })) }) },
            { | which |
              which := sqlite:resolve(t, c).
              wanted:add(which:equals('rowid):ifElse({ 'rowid }, { t:columns:at(which):at(#1):asSymbol })) }) }).
    q := t:all.
    parsed:at(#3):do({ term | q := q:filter(term:at(#1), term:at(#2), term:at(#3)) }).
    parsed:at(#4):size:greaterThan(#0):ifTrue({ q := q:orderBy(parsed:at(#4)) }).
    q:each({ row |
        emit:value(wanted:collect({ w | sqlite:render(row:slotAt(w)) }):join("|")) }) }.

; ---------------------------------------------------------------------------
; CREATE TABLE, CREATE INDEX, INSERT, UPDATE, DELETE, and PRAGMA page_size
;
; Each statement is parsed here and run through the library's objects: a
; table made or found on the database, a row put in as a dictionary of
; column names, a query narrowed by the WHERE and then updated or deleted.
; The shell keeps nothing of its own but the parse, which is why the sweep
; that judges it judges the objects.

; A statement's text as written, from its first token to its last.
statementText := { text, st | text:copyFrom(st:at(#1):at(#3), st:at(st:size):at(#4)) }.

; `text` is the whole source, since the tokens' positions are into it.
createTable := { d, st, text | | name |
    st:size:lessThan(#4):ifTrue({ error:raise("CREATE TABLE needs a name and columns") }).
    name := tok:value(st, #3):at(#2).
    ; Stored as written, after the two words SQLite spells for itself.
    sqlite:createTable(d, name, "CREATE TABLE ":concat(text:copyFrom(st:at(#3):at(#3), st:at(st:size):at(#4)))) }.

createIndex := { d, st, text | | name, tblName, t, cols |
    st:size:lessThan(#7):ifTrue({ error:raise("CREATE INDEX needs a name, a table and columns") }).
    name := tok:value(st, #3):at(#2).
    isWord:value(st, #4, "ON"):ifFalse({ error:raise("expected ON in CREATE INDEX") }).
    tblName := tok:value(st, #5):at(#2).
    t := d:table(tblName).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(tblName)) }).
    cols := sqlite:indexColumnsFromSql(statementText:value(text, st)).
    cols:isNil:ifTrue({ error:raise("an index with DESC, COLLATE, an expression or a WHERE is not written here") }).
    sqlite:createIndex(d, t, name, cols, "CREATE INDEX ":concat(text:copyFrom(st:at(#3):at(#3), st:at(st:size):at(#4)))) }.

; INSERT INTO t [(cols)] VALUES (v, ...), (v, ...)
insertStatement := { d, st | | i, name, t, which, r, rowValues, row, done, count |
    i := expect:value(st, #1, "INSERT").
    i := expect:value(st, i, "INTO").
    name := tok:value(st, i):at(#2). i := i:inc.
    t := d:table(name).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(name)) }).
    ; The columns named, as the schema spells them; none named is every
    ; column in order.
    which := nil.
    isPunct:value(st, i, "("):ifTrue({
        i := i:inc. which := [].
        { isPunct:value(st, i, ")"):not:and({ i:lessOrEqual(st:size) }) }:whileTrue({
            r := columnRef:value(st, i). i := r:at(#2).
            sqlite:resolve(t, r:at(#1)).
            which:add(r:at(#1)).
            isPunct:value(st, i, ","):ifTrue({ i := i:inc }) }).
        i := i:inc }).
    which:isNil:ifTrue({ which := t:columnNames }).
    i := expect:value(st, i, "VALUES").
    count := #0.
    done := false.
    { done:not }:whileTrue({
        i := expect:value(st, i, "(").
        rowValues := [].
        { isPunct:value(st, i, ")"):not:and({ i:lessOrEqual(st:size) }) }:whileTrue({
            r := literal:value(st, i). i := r:at(#2).
            rowValues:add(r:at(#1)).
            isPunct:value(st, i, ","):ifTrue({ i := i:inc }) }).
        i := i:inc.
        rowValues:size:notEquals(which:size):ifTrue({
            error:raise("table ":concat(t:name):concat(" has "):concat(which:size:asString)
                :concat(" columns but "):concat(rowValues:size:asString):concat(" values were supplied")) }).
        row := dictionary:new.
        [#1, which:size]:loop({ k | row:atPut(which:at(k), rowValues:at(k)) }).
        t:insert(row).
        count := count:inc.
        isPunct:value(st, i, ","):ifElse(
            { i := i:inc }, { done := true }) }).
    i:lessOrEqual(st:size):ifTrue({
        error:raise("this INSERT goes on past what is understood, at: ":concat(tok:value(st, i):at(#2))) }).
    count }.

; UPDATE t SET col = v, ... [WHERE ...]: each row the WHERE keeps, with
; those columns changed, put back through the table's `update`. It was
; outside the plan, being a delete and an insert at the page level, and is
; here so that sqlite3 judges `update` the way it judges the rest.
updateStatement := { d, st | | i, name, t, sets, r, where, q, count |
    i := expect:value(st, #1, "UPDATE").
    name := tok:value(st, i):at(#2). i := i:inc.
    t := d:table(name).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(name)) }).
    i := expect:value(st, i, "SET").
    sets := [].
    { isWord:value(st, i, "WHERE"):not:and({ i:lessOrEqual(st:size) }) }:whileTrue({
        r := columnRef:value(st, i). i := r:at(#2).
        sqlite:resolve(t, r:at(#1)).
        i := expect:value(st, i, "=").
        sets:add([r:at(#1), nil]).
        r := literal:value(st, i). i := r:at(#2).
        sets:at(sets:size):atPut(#2, r:at(#1)).
        isPunct:value(st, i, ","):ifTrue({ i := i:inc }) }).
    sets:size:equals(#0):ifTrue({ error:raise("UPDATE needs SET column = value") }).
    where := [].
    isWord:value(st, i, "WHERE"):ifTrue({
        i := i:inc.
        r := parseWhere:value(st, i). where := r:at(#1). i := r:at(#2) }).
    i:lessOrEqual(st:size):ifTrue({
        error:raise("this UPDATE goes on past what is understood, at: ":concat(tok:value(st, i):at(#2))) }).
    q := t:all.
    where:do({ term | q := q:filter(term:at(#1), term:at(#2), term:at(#3)) }).
    ; Each SET as the key the row carries: the column's symbol, or 'rowid
    ; for the rowid and its aliases. A row whose rowid moves is taken out
    ; and put in again, since its rowid is where `update` finds it.
    sets := sets:collect({ s | | which |
        which := sqlite:resolve(t, s:at(#1)).
        [which:equals('rowid):ifElse({ 'rowid }, { t:columns:at(which):at(#1):asSymbol }), s:at(#2)] }).
    count := #0.
    q:all:do({ row | | moved, was, pairs |
        moved := false. was := row:rowid.
        pairs := row:asDictionary.
        sets:do({ s |
            s:at(#1):equals('rowid):ifTrue({ moved := true }).
            pairs:atPut(s:at(#1), s:at(#2)) }).
        moved:ifElse({ t:delete(was). t:insert(pairs) }, { t:update(pairs) }).
        count := count:inc }).
    count }.

; DELETE FROM t [WHERE ...]
deleteStatement := { d, st | | i, name, t, where, r, q |
    i := expect:value(st, #1, "DELETE").
    i := expect:value(st, i, "FROM").
    name := tok:value(st, i):at(#2). i := i:inc.
    t := d:table(name).
    t:isNil:ifTrue({ error:raise("no such table: ":concat(name)) }).
    where := [].
    isWord:value(st, i, "WHERE"):ifTrue({
        i := i:inc.
        r := parseWhere:value(st, i). where := r:at(#1). i := r:at(#2) }).
    i:lessOrEqual(st:size):ifTrue({
        error:raise("this DELETE goes on past what is understood, at: ":concat(tok:value(st, i):at(#2))) }).
    q := t:all.
    where:do({ term | q := q:filter(term:at(#1), term:at(#2), term:at(#3)) }).
    q:delete }.

; PRAGMA page_size = N sets the size of a database that is still empty, and
; is ignored on one that is not, as SQLite ignores it. Any other pragma is
; not understood, and says so rather than answering nothing.
pragmaStatement := { d, st | | n |
    (isWord:value(st, #2, "PAGE_SIZE"):and({ isPunct:value(st, #3, "=") })):ifFalse({
        error:raise("only PRAGMA page_size = N is understood") }).
    n := tok:value(st, #4):at(#2):asInteger.
    ([#512, #1024, #2048, #4096, #8192, #16384, #32768, #65536]:indexOf(n)):isNil:ifTrue({
        error:raise("page_size must be a power of two from 512 to 65536") }).
    d:isEmpty:ifTrue({ d:pageSize := n. d:usable := n }) }.

; One statement of any kind this program has.
execute := { d, st, text | | first |
    first := st:at(#1):at(#2):asUppercase.
    first:equals("SELECT"):ifElse({ runSelect:value(d, parseSelect:value(st)) },
    { first:equals("INSERT"):ifElse({ insertStatement:value(d, st) },
    { first:equals("UPDATE"):ifElse({ updateStatement:value(d, st) },
    { first:equals("DELETE"):ifElse({ deleteStatement:value(d, st) },
    { first:equals("PRAGMA"):ifElse({ pragmaStatement:value(d, st) },
    { (first:equals("CREATE"):and({ isWord:value(st, #2, "TABLE") })):ifElse({ createTable:value(d, st, text) },
    { (first:equals("CREATE"):and({ isWord:value(st, #2, "INDEX") })):ifElse({ createIndex:value(d, st, text) },
    { (first:equals("CREATE"):and({ isWord:value(st, #2, "UNIQUE") })):ifElse(
        { error:raise("a UNIQUE index is not written here; the constraint is not checked") },
        { error:raise("only SELECT, CREATE TABLE, CREATE INDEX, INSERT, UPDATE, DELETE and PRAGMA page_size are understood; this begins with ":concat(st:at(#1):at(#2))) }) }) }) }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; The demonstration
;
; Every program here runs with no arguments on input it supplies itself. This
; one writes a small database under build/, reads it back, and if the sqlite3
; on the machine is there, asks it whether the file is well formed and what
; it reads, since that is the judge the sweep uses. Until step 3 the file
; was made by sqlite3; now it is made here.

demonstrate := { | path, run, verdict |
    system:makeDirectory("build").
    path := "build/sql-demo.db".
    system:fileExists(path):ifTrue({ system:remove(path) }).
    demoDb := sqlite:open(path).
    run := { sql |
        "-- ":concat(sql):display.
        sqlite:statements(sqlite:tokenize(sql)):do({ st |
            execute:value(demoDb, st, sql) }).
        out:size:greaterThan(#0):ifTrue({ system:write(out:join("")). out := []. "":display }) }.
    run:value("CREATE TABLE fruit (name TEXT, count INTEGER, price REAL)").
    run:value("CREATE INDEX fruit_name ON fruit (name)").
    run:value("INSERT INTO fruit VALUES ('pear', 3, 0.5), ('apple', 10, 0.25), ('fig', 1, 2.0)").
    run:value("INSERT INTO fruit VALUES ('banana', 2, 0.3), ('apple', 7, 0.25), (NULL, 0, 1e20)").
    "":display.
    run:value("SELECT * FROM fruit").
    run:value("SELECT rowid, name FROM fruit WHERE name = 'apple'").
    run:value("SELECT name, price FROM fruit ORDER BY price, rowid").
    run:value("SELECT count FROM fruit WHERE rowid = 3").
    run:value("SELECT type, name, rootpage FROM sqlite_schema").
    demoDb:flush.
    "-- ":concat(demoDb:pageCount:asString):concat(" pages of "):concat(demoDb:pageSize:asString)
        :concat(" bytes written to "):concat(path):display.
    verdict := system:capture(["sqlite3", path, "PRAGMA integrity_check; SELECT name, count FROM fruit WHERE name = 'apple'"],
                              ["stderr", 'discard]).
    verdict:at("status"):equals(#0):ifElse(
        { "-- sqlite3 on this machine says: ":concat(verdict:at("output"):trim:split("\n"):join(" / ")):display },
        { "-- no sqlite3 on this machine to judge it":display }) }.

demoDb := nil.

; ---------------------------------------------------------------------------
; Main

main := { | args, d, text, tokens, status |
    args := system:arguments.
    args:size:lessThan(#1):ifTrue({
        { demonstrate:value }:onError({ e |
            system:writeError("sql: ":concat(e:message):concat("\n")).
            system:exit(#2) }).
        system:exit(#0) }).
    status := #0.
    { d := sqlite:open(args:at(#1)) }:onError({ e |
        system:writeError("Error: ":concat(e:message):concat("\n")).
        system:exit(#1) }).
    text := args:size:greaterOrEqual(#2):ifElse({ args:at(#2) }, { system:readFile("/dev/stdin") }).
    sqlite:statements(sqlite:tokenize(text)):do({ st |
        { execute:value(d, st, text) }
        :onError({ e |
            system:write(out:join("")). out := [].
            system:writeError("Error: ":concat(e:message):concat("\n")).
            status := #1 }) }).
    system:write(out:join("")).
    ; What changed is written now, whole, as the statements that finished left
    ; it; there is no journal, so a statement that failed half way is in the
    ; file half way, and the sweep judges only files whose script finished.
    { d:flush }:onError({ e |
        system:writeError("Error: ":concat(e:message):concat("\n")).
        status := #1 }).
    ; The numbers to watch, on request: pages read, and for a run that wrote,
    ; pages changed and bytes written, which is the measurement step 4 of the
    ; plan exists for and 3.27 was closed on.
    system:environment("SQLITE_PAGES"):notNil:ifTrue({
        d:written:equals(#0):ifElse(
            { system:writeError(d:reads:asString:concat(" pages read of "):concat(d:pageCount:asString):concat("\n")) },
            { system:writeError(d:reads:asString:concat(" pages read, "):concat(d:changed:asString)
                  :concat(" changed and written of "):concat(d:pageCount:asString):concat(", ")
                  :concat(d:written:asString):concat(" bytes\n")) }) }).
    system:exit(status) }.

main:value.

