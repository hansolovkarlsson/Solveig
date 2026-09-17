; records.sol -- one record at a time over a table: move, add, save,
; delete, search.
; Run with:  ./bin/solas examples/records.sol && ./bin/solvm examples/records.sob
;
; lib/recordset.sol is the piece between a table and a form: a position among
; the rows a query answers, and the row standing there. It knows nothing of
; any window, which is why it can be run here and checked; a form is written
; over it. This writes into build/, which `make clean` takes away again.

@include "recordset.sol".

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

; Every `save` and `delete` flushed the file, so `sqlite3` reading it now
; would agree with each step; `close` is for the pages and the cache.
db:close.
