; codes.sol -- a code table read once: the key a column stores, and the text
; a person reads.
;
;     @include "codes.sol".
;
;     kinds := codes:on(db:table("kinds"), 'code, 'name).
;     kinds:texts:display.                    ; ["friend", "work"]
;     kinds:textFor("f"):display.             ; "friend"
;     kinds:indexOf("w"):display.             ; #2
;
;     colours := codes:of(["red", "green"]).  ; the key and the text are one
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; This file binds one name, `codes`, and includes `sqlite.sol` for one line:
; a table and a query are told apart by `isKindOf` in `on`, so that a program
; may hand over either. Everything else here is an array of two-element
; arrays, in the order the rows arrived, and a few ways of asking about it.
;
; It is the lookup half of a dropdown, and it is here rather than in the GTK
; binding on purpose: a window cannot be driven down a pipe, so the part that
; can be tested without eyes is put where eyes are not needed, which is the
; same reason `recordset.sol` is here. Scoped in docs/ideas.md on 2026-09-18,
; with the forms that asked for it.
;
; **It knows nothing about a dropdown**, and that is the point of the line.
; A GTK dropdown always shows a choice, so a form that wants *no value* shows
; an empty text first; that blank is the form's and never appears here, and
; every index this file answers counts the codes alone.
;
; A key is compared with `equals`, so it is whatever the column stores: the
; integers and strings SQLite holds are what arrive, and nothing is coerced
; on the way in or out.

@include "sqlite.sol".

codes := object:new.
codes:pairs := [].              ; each [key, text], in the order they arrived

; ---------------------------------------------------------------------------
; Making one

; From an array: either of two-element arrays, key and text, or of plain
; values, where each is its own key and its text is how it displays. The two
; may be mixed, since a code table written in a program often has one odd one.
codes:of := { given | | c |
    c := self:new.
    c:pairs := given:collect({ each |
        each:isKindOf(array):ifElse(
            { each:size:equals(#2):ifFalse({
                  error:raise("a code is a key and a text, and this one has "
                      :concat(each:size:asString)
                      :concat(each:size:equals(#1):ifElse({ " part" }, { " parts" }))) }).
              each },
            { [each, each:asString] }) }).
    c }.

; From a table, or from a query over one, which is how an order is asked for:
; `codes:on(db:table("kinds"):orderBy('name), 'code, 'name)`. A table on its
; own arrives in the order the rows are stored.
codes:on := { source, keyColumn, textColumn | | rows, k, t, first |
    k := sqlite:nameOf(keyColumn).
    t := sqlite:nameOf(textColumn).
    rows := source:isKindOf(sqlite:table):ifElse({ source:all:all }, { source:all }).
    ; A column that is not there is refused here and by name. `slotAt` would
    ; refuse it too, one row at a time and saying only `no slot named 'code'`,
    ; which does not say which table was asked.
    rows:size:greaterThan(#0):ifTrue({
        first := rows:at(#1).
        [k, t]:do({ c |
            first:table:columnNames:indexOf(c):isNil:ifTrue({
                error:raise("no column '":concat(c):concat("' in ")
                    :concat(first:table:name)) }) }) }).
    self:of(rows:collect({ row | [row:slotAt(k:asSymbol), row:slotAt(t:asSymbol)] })) }.

; ---------------------------------------------------------------------------
; Asking about it
;
; Every index counts from #1, as everything here does, and past either end is
; refused by name rather than answered with nil, since an index out of range
; is a mistake in the caller and a missing key is not.

codes:size := { self:pairs:size }.
codes:keys := { self:pairs:collect({ p | p:at(#1) }) }.
codes:texts := { self:pairs:collect({ p | p:at(#2) }) }.

codes:at := { i |
    (i:lessThan(#1):or({ i:greaterThan(self:pairs:size) })):ifTrue({
        error:raise("no code ":concat(i:asString):concat(" among ")
            :concat(self:pairs:size:asString)) }).
    self:pairs:at(i) }.

codes:keyAt := { i | self:at(i):at(#1) }.
codes:textAt := { i | self:at(i):at(#2) }.

; Where a key sits, or nil when the table has no such code. A record holding a
; code nobody kept is the case this answers nil for, and what a form does with
; that nil is the form's business.
codes:indexOf := { key | | found, i |
    found := nil. i := #0.
    self:pairs:do({ p |
        i := i:inc.
        (found:isNil:and({ p:at(#1):equals(key) })):ifTrue({ found := i }) }).
    found }.

codes:includes := { key | self:indexOf(key):notNil }.

; The text for a key, or nil where there is none.
codes:textFor := { key | | i |
    i := self:indexOf(key).
    i:isNil:ifElse({ nil }, { self:textAt(i) }) }.

; The key for a text, or nil. Two codes with one text answers the first, which
; is the same rule `indexOf` follows and the reason a code table's texts are
; meant to be distinct.
codes:keyFor := { text | | found |
    found := nil.
    self:pairs:do({ p |
        (found:isNil:and({ p:at(#2):equals(text) })):ifTrue({ found := p:at(#1) }) }).
    found }.

; One more code on the end, answering the codes. A form uses this for a key it
; met in a record and did not find here, so that the record can say what it
; holds; a program may use it for a choice it adds.
codes:add := { key, text |
    self:pairs:add([key, text]).
    self }.
