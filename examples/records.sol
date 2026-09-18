; records.sol -- one record at a time over a table: move, add, save,
; delete, search.
; Run with:  ./bin/solas examples/records.sol && ./bin/solvm examples/records.sob
;
; lib/recordset.sol is the piece between a table and a form: a position among
; the rows a query answers, and the row standing there. It knows nothing of
; any window, which is why it can be run here and checked; a form is written
; over it. This writes into build/, which `make clean` takes away again.

@include "recordset.sol".
@include "codes.sol".

system:makeDirectory("build").
path := "build/example-contacts.db".
system:fileExists(path):ifTrue({ system:remove(path) }).

db := sqlite:open(path).
contacts := db:create("contacts", ["name TEXT", "email TEXT", "kind TEXT"]).

; ---------------------------------------------------------------------------
; Over an empty table there is nowhere to stand
people := recordset:on(contacts).
people:count:print.                      ; #0
people:position:print.                   ; #0
people:current:print.                    ; nil
people:next:print.                       ; nil   -- a move with nowhere to go

; ---------------------------------------------------------------------------
; A new record
;
; `addNew` makes a record with every column nil and no rowid, under the
; table's own prototype, so its columns are slots as any row's are. `save`
; inserts it, flushes the file, and stands on it.
people:addNew.
people:isNew:print.                      ; true
people:current:name := "Ada".
people:current:kind := "friend".
people:save:rowid:print.                 ; #1
people:isNew:print.                      ; false
people:position:print.                   ; #1
people:addNew. people:current:name := "Bob". people:current:kind := "work". people:save.
people:addNew. people:current:name := "Cy". people:current:kind := "friend". people:save.
people:count:print.                      ; #3

; ---------------------------------------------------------------------------
; Moving
;
; Each move answers the row now current. Past either end it stays put, so
; `next` on the last row is the last row again; `at` past the end is refused.
people:first:name:display.               ; Ada
people:next:name:display.                ; Bob
people:last:name:display.                ; Cy
people:next:name:display.                ; Cy
people:previous:name:display.            ; Bob
people:at(#1):name:display.              ; Ada
{ people:at(#4) }:onError({ e | e:message:display }).
                                         ; no record 4 among 3

; ---------------------------------------------------------------------------
; Changing, and not
;
; The current row is re-read from the pages on every move, so a change not
; saved is gone once the position moves. `changed` says whether there is
; one, which is what a form asks before it lets the position move; `revert`
; re-reads the row in place.
people:current:email := "ada@example.org".
people:changed:print.                    ; true
people:revert:email:print.               ; nil
people:changed:print.                    ; false
people:current:email := "ada@example.org".
people:save.
contacts:find(#1):email:display.         ; ada@example.org

; A column is a slot, so `people:current:email := ...` writes it; a column
; named at run time, as a form's are from the schema, is written by `set`,
; which makes the record again with the pairs applied.
people:set(#["email" = "ada@work.example", 'kind = "friend"]):kind:display. ; friend
people:changed:print.                    ; true
people:save:email:display.               ; ada@work.example
{ people:set(#['colour = "red"]) }:onError({ e | e:message:display }).
                                         ; no such column: colour

; ---------------------------------------------------------------------------
; Searching, and order
;
; `find` narrows to the rows equal on every pair and stands on the first;
; `all` drops the narrowing and keeps the position on the same row where it
; can. `orderBy` takes a column or an array of them; nil is rowid order.
people:find(#['kind = "friend"]):name:display.                 ; Ada
people:count:print.                      ; #2
people:next:name:display.                ; Cy
people:all.
people:count:print.                      ; #3
people:position:print.                   ; #3
people:orderBy("name"). people:first:name:display.             ; Ada
people:orderBy(nil).

; ---------------------------------------------------------------------------
; Deleting
;
; The position moves to the next neighbour where there is one, else the
; previous. A record not yet saved is simply dropped.
people:at(#2).
people:delete:print.                     ; true
people:count:print.                      ; #2
people:current:name:display.             ; Cy
people:addNew.
people:delete:print.                     ; false  -- nothing was in the table
people:current:name:display.             ; Cy
people:last. people:delete. people:current:name:display.       ; Ada
people:delete. people:count:print.       ; #0
people:current:print.                    ; nil
{ people:save }:onError({ e | e:message:display }).
                                         ; nothing to save

; ---------------------------------------------------------------------------
; A code table: the key a column stores, the text a person reads
;
; `codes` is the lookup a dropdown is made of, and it is here rather than in
; the GTK binding for the reason the recordset is: it can be run and checked,
; where a window cannot. It knows nothing about a dropdown, and the blank a
; dropdown needs is the form's business and never appears here.
kindTable := db:create("kinds", ["code TEXT", "name TEXT"]).
kindTable:insert(#['code = "f", 'name = "friend"]).
kindTable:insert(#['code = "w", 'name = "work"]).
kindTable:insert(#['code = "a", 'name = "acquaintance"]).

kinds := codes:on(kindTable, 'code, 'name).
kinds:size:print.                        ; #3
kinds:keys:print.                        ; ["f", "w", "a"]
kinds:texts:print.                       ; ["friend", "work", "acquaintance"]
kinds:textFor("w"):display.              ; work
kinds:keyFor("friend"):display.          ; f
kinds:indexOf("a"):print.                ; #3
kinds:keyAt(#1):display.                 ; f
kinds:textAt(#2):display.                ; work

; A key no code answers, which is what a record holding a code somebody
; deleted looks like. Nil rather than a refusal: an index out of range is the
; caller's mistake and a missing key is not.
kinds:indexOf("zz"):print.               ; nil
kinds:textFor("zz"):print.               ; nil
kinds:includes("zz"):print.              ; false
{ kinds:at(#9) }:onError({ e | e:message:display }).
                                         ; no code 9 among 3

; A query rather than a table, which is how an order of its own is asked for.
codes:on(kindTable:orderBy('name), 'code, 'name):texts:print.
                                         ; ["acquaintance", "friend", "work"]

; Written in the program instead: an array of pairs, or of plain values where
; each is its own key. The two may be mixed.
codes:of([[#1, "one"], [#2, "two"]]):textFor(#2):display.      ; two
codes:of(["red", "green"]):keys:print.   ; ["red", "green"]

; One more on the end. A form does this with a key it met in a record and did
; not find here, so that the record can say what it holds.
kinds:add("x", "x (not in the table)").
kinds:size:print.                        ; #4
kinds:textFor("x"):display.              ; x (not in the table)

; Every `save` and `delete` flushed the file, so `sqlite3` reading it now
; would agree with each step; `close` is for the pages and the cache.
db:close.
