; database.sol -- a database as objects: a file, its tables, a query, a row.
; Run with:  ./bin/solas examples/database.sol && ./bin/solvm examples/database.sob
;
; lib/sqlite.sol reads and writes the file format `sqlite3` uses, and this is
; the front it was wanted for: the database is an object, each table is an
; object, a query is one, and a row is an object whose columns are its slots.
; The SQL shell in programs/sql.sol is a client of the same objects, which is
; how `sqlite3` gets to judge them. This writes into build/, which `make clean`
; takes away again.

@include "sqlite.sol".

system:makeDirectory("build").
path := "build/example-notes.db".
system:fileExists(path):ifTrue({ system:remove(path) }).

; ---------------------------------------------------------------------------
; A database, and a table in it
;
; `open` makes the file if it is not there. A table is created from its
; columns spelled as SQL spells them, because the schema is SQL text in the
; file whatever this front says: it is the one place a program writes any.
db := sqlite:open(path).
notes := db:create("notes", ["title TEXT", "done INTEGER", "weight REAL"]).
db:tableNames:print.                     ; ["notes"]
notes:columnNames:print.                 ; ["title", "done", "weight"]

; ---------------------------------------------------------------------------
; Rows in
;
; `insert` takes a dictionary of column names to values, symbols or strings
; for the names; a column not named is NULL, and the rowid is assigned. It
; answers the row.
milk := notes:insert(#['title = "milk", 'done = #0, 'weight = 1.5]).
milk:rowid:print.                        ; #1
notes:insert(#["title" = "eggs", "done" = #1]):rowid:print.    ; #2
notes:insert(#['title = "figs", 'done = #0, 'weight = #2]):weight:print.
                                         ; 2   -- a REAL column answers a float
notes:count:print.                       ; #3

; ---------------------------------------------------------------------------
; A row is an object
;
; Its columns are its slots, made by `object:new(dictionary)` from the schema,
; so they are read and written as any slot is. `save` puts the row back under
; its rowid; `delete` takes it out.
n := notes:find(#2).
n:title:display.                         ; eggs
n:done:print.                            ; #1
n:weight:print.                          ; nil
n:title := "eggs, a dozen".
n:done := #0.
n:save.
notes:find(#2):title:display.            ; eggs, a dozen
notes:find(#9):print.                    ; nil   -- no such row

; ---------------------------------------------------------------------------
; Queries
;
; `where` keeps the rows equal on every pair; `filter` is one comparison,
; spelled as SQL spells it; `orderBy` sorts, with the rowid breaking ties.
; Each answers a new query, so one can be kept and refined, and `each`,
; `all`, `first`, `count`, `collect` and `delete` run it.
notes:where(#['done = #0]):count:print.                        ; #3
notes:where(#['done = #0]):orderBy("title"):each({ r | r:title:display }).
                                         ; eggs, a dozen figs milk
notes:filter("weight", ">", 1.6):collect({ r | r:title }):print.   ; ["figs"]
notes:orderBy(['weight, 'title]):first:title:display.          ; eggs, a dozen
todo := notes:where(#['done = #0]).
todo:filter("weight", "<=", 1.5):count:print.                  ; #1
todo:count:print.                        ; #3   -- the query kept is unchanged

; An index is a table's, named, on columns; a query on its first column
; walks the index instead of the table, and answers the same rows.
notes:index("notes_done", ["done"]).
notes:where(#['done = #0]):count:print.                        ; #3

; ---------------------------------------------------------------------------
; Rows out, and the file
notes:where(#['title = "figs"]):delete:print.                  ; #1
milk:delete:print.                       ; true
notes:count:print.                       ; #1

; A name that is not a column, and a comparison that is not one, are refused
; by name rather than answering nothing.
{ notes:insert(#['colour = "red"]) }:onError({ e | e:message:display }).
                                         ; no such column: colour
{ notes:filter("done", "<>", #1) }:onError({ e | e:message:display }).
                                         ; a comparison is =, <, >, <= or >=, not <>

; `close` writes every page that changed, once, and is when the file is
; whole. Opened again, by this or by sqlite3, it is what was left.
db:close.
again := sqlite:open(path).
again:table("notes"):all:collect({ r | r:title }):print.       ; ["eggs, a dozen"]
again:table("nothing"):print.            ; nil
again:close.
