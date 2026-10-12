; recordset.sol -- one table, one record at a time: a position, and the
; messages that move it, make a new record, save, delete and search.
;
;     @include "recordset.sol".
;
;     people := recordset:on(db:table("contacts")).
;     people:current:name:display.
;     people:next. people:last. people:previous.
;     people:addNew. people:current:name := "Ada". people:save.
;     people:find(#['kind = "friend"]):current:name:display.
;     people:all.
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; This file binds one name, `recordset`, and includes `sqlite.sol`, which is
; all it knows: a table from that library, a query over it narrowed or not,
; the rowids the query answers in order, a position among them, and the row
; standing there. It is what VB's Data control and .NET's BindingSource are,
; the piece between a table and a form that knows where the user is, and it
; knows nothing of any widget, which is the reason it is a file of its own:
; a window cannot be driven down a pipe, so what a form does with a record
; lives here where the suite can see it, and the form is written over it.
; Scoped in docs/ideas.md on 2026-09-17, for the forms that asked.
;
; A column is written as a slot, `people:current:name := "Ada"`, or by a
; name held in a value through `set`, which a form needs since its column
; names come out of the schema. A record is a row of the table, re-read from
; the pages on every move, so a
; change made to `current` and not saved is gone once the position moves; a
; form that wants to refuse the move asks `changed` first. A new record is a
; row with no rowid yet, made under the table's own prototype so that its
; columns are slots as any row's are; `save` inserts it and stands on it.
; Every `save` and `delete` flushes the file, since a record is the unit a
; person expects to be on disk when they were told it was saved.
;
; A recordset can follow another, which is master and child: orders under a
; contact. `orders:follow(people, 'contact)` narrows the orders to the rows
; whose `contact` holds the rowid of the person `people` stands on, and they
; follow every move `people` makes, since every move goes through `goTo`. A
; new order is given the person's rowid, and a person with orders following
; is not deleted. Scoped in docs/ideas.md on 2026-10-12.

@include "sqlite.sol".

recordset := object:new.
recordset:table := nil.
recordset:base := nil.          ; the narrowing: the table's `all`, or a `where`
recordset:order := nil.         ; column names to order by, or nil for rowid order
recordset:rowids := nil.        ; the rowids the query answers, in order
recordset:position := #0.       ; among them, from #1; #0 when there are none
recordset:current := nil.       ; the row standing there, a new record, or nil
recordset:isNew := false.       ; whether `current` is a record not yet saved
recordset:parent := nil.        ; the recordset this one follows, or nil
recordset:link := nil.          ; the column holding the parent's rowid, as a symbol
recordset:followers := nil.     ; the recordsets following this one

; ---------------------------------------------------------------------------
; Making one, and the query under it

; A recordset over a table, standing on its first row if it has one.
recordset:on := { t | | r |
    r := self:new.
    r:table := t.
    r:base := t:all.
    r:order := nil.
    r:followers := [].
    r:refresh.
    r:first.
    r }.

; The query, as narrowed and ordered.
recordset:query := {
    self:order:isNil:ifElse({ self:base }, { self:base:orderBy(self:order) }) }.

; The rowids read again from the pages, and the position kept on the same
; rowid where it still answers, else clamped to what there is.
recordset:refresh := { | was, i |
    was := self:isNew:ifElse({ nil }, { self:current:isNil:ifElse({ nil }, { self:current:rowid }) }).
    self:rowids := self:query:rows:collect({ r | r:at(#1) }).
    i := was:isNil:ifElse({ nil }, { self:rowids:indexOf(was) }).
    i:isNil:ifTrue({
        i := self:position.
        i:greaterThan(self:rowids:size):ifTrue({ i := self:rowids:size }).
        (i:lessThan(#1):and({ self:rowids:size:greaterThan(#0) })):ifTrue({ i := #1 }) }).
    self:isNew:ifFalse({ self:goTo(i) }).
    self:isNew:ifTrue({ self:position := i }).
    self }.

; ---------------------------------------------------------------------------
; Moving
;
; Each answers the row now current, or nil when there is none. A move past
; either end stays where it is, so `next` on the last row answers the last
; row again; `position` and `count` say where that is.

recordset:goTo := { i |
    (i:lessThan(#1):or({ i:greaterThan(self:rowids:size) })):ifElse(
        { self:position := #0. self:current := nil },
        { self:position := i. self:current := self:table:find(self:rowids:at(i)) }).
    self:isNew := false.
    self:followers:do({ c | c:track }).
    self:current }.

recordset:count := { self:rowids:size }.
recordset:first := { self:goTo(#1) }.
recordset:last := { self:goTo(self:rowids:size) }.
recordset:next := { self:position:lessThan(self:rowids:size):ifElse({ self:goTo(self:position:inc) }, { self:goTo(self:position) }) }.
recordset:previous := { self:position:greaterThan(#1):ifElse({ self:goTo(self:position:dec) }, { self:goTo(self:position) }) }.

; The record at that position, from #1; past the ends is refused by name.
recordset:at := { i |
    (i:lessThan(#1):or({ i:greaterThan(self:rowids:size) })):ifTrue({
        error:raise("no record ":concat(i:asString):concat(" among "):concat(self:rowids:size:asString)) }).
    self:goTo(i) }.

; ---------------------------------------------------------------------------
; Changing
;
; `changed` compares the current record with the pages, column by column,
; which is what a form asks before it lets the position move.

recordset:changed := { | saved |
    self:current:isNil:ifElse({ false }, {
        self:isNew:ifElse({ true }, {
            saved := self:table:find(self:current:rowid).
            saved:isNil:ifElse({ true }, {
                self:table:columnNames:select({ c | | s |
                    s := c:asSymbol.
                    self:current:slotAt(s):equals(saved:slotAt(s)):not }):size:greaterThan(#0) }) }) }) }.

; A record not yet in the table: every column nil, no rowid, the table's
; prototype so that its columns are slots. The position is kept, and is where
; `revert` goes back to. `addNew` is DAO's name for it, and it is not `new`
; because `new` is how a recordset itself is made.
recordset:addNew := { | slots |
    slots := dictionary:new.
    slots:atPut('rowid, nil).
    self:table:columnNames:do({ c | slots:atPut(c:asSymbol, nil) }).
    self:parent:isNil:ifFalse({
        self:parentKey:isNil:ifTrue({
            error:raise("no record to add under: the ":concat(self:parent:table:name):concat(" record is not saved")) }).
        slots:atPut(self:link, self:parentKey) }).
    self:current := self:table:rowProto:new(slots).
    self:isNew := true.
    self:followers:do({ c | c:track }).
    self:current }.

; Columns of the current record given values by name, from a dictionary of
; column names to values, as `insert` takes them. A slot cannot be written
; by a name held in a value, which is the line docs/ROADMAP.md 2.14 draws,
; so the record is made again under the table's prototype with the pairs
; applied, the same rowid, and the same `isNew`; a form, whose column names
; come out of the schema at run time, is the customer. A name that is not a
; column is refused by name. Answers the record.
recordset:set := { pairs | | slots |
    self:current:isNil:ifTrue({ error:raise("no record to set") }).
    slots := self:current:asDictionary.
    pairs:keysAndValuesDo({ k, v | | s |
        s := sqlite:nameOf(k):asSymbol.
        slots:includes(s):ifFalse({
            error:raise("no such column: ":concat(sqlite:nameOf(k))) }).
        slots:atPut(s, v) }).
    self:current := self:table:rowProto:new(slots).
    self:current }.

; The current record written: inserted if new, put back under its rowid
; otherwise, and the file flushed. Answers the row, now standing on it.
recordset:save := { | row |
    self:current:isNil:ifTrue({ error:raise("nothing to save") }).
    self:isNew:ifElse(
        { row := self:table:insert(self:current).
          self:isNew := false.
          self:current := row },
        { self:current:save }).
    self:table:db:flush.
    self:refresh.
    self:current }.

; The current record forgotten: a new one dropped, a changed one re-read.
recordset:revert := {
    self:isNew := false.
    self:goTo(self:position) }.

; The current record taken out, and the file flushed; the position moves to
; the neighbour, the next one where there is one. Answers whether there was
; a record to take out; a new record is simply dropped.
recordset:delete := { | had |
    self:current:isNil:ifElse({ false }, {
        self:isNew:ifElse({ self:revert. false }, {
            self:refuseIfFollowed.
            had := self:table:delete(self:current).
            self:table:db:flush.
            self:current := nil.
            self:refresh.
            had }) }) }.

; ---------------------------------------------------------------------------
; Searching
;
; `find` narrows the recordset to the rows equal on every pair, the way the
; library's `where` does, and stands on the first of them; `all` drops the
; narrowing. `orderBy` takes a column or an array of them, or nil for rowid
; order, and keeps the position on the same record.

recordset:find := { pairs |
    self:base := self:narrowed(self:table:where(pairs)).
    self:isNew := false.
    self:current := nil.
    self:position := #1.
    self:refresh.
    self:current }.

recordset:all := {
    self:base := self:narrowed(self:table:all).
    self:isNew := false.
    self:refresh.
    self:current }.

recordset:orderBy := { columns |
    self:order := columns.
    self:refresh.
    self:current }.

; ---------------------------------------------------------------------------
; Following
;
; A follower's narrowing is its parent's rowid in one column, and every query
; it makes is made inside that: `all` is every row under the parent and not
; every row in the table, and `find` looks among them. A parent with no
; record, or a new one with no rowid yet, is followed by no rows at all,
; since an `=` with nil on either side holds for nothing.

; This recordset narrowed to the rows under the parent's current record, in
; that column, and kept there. A column the table does not have is refused
; here, naming the table, rather than as an empty result. Answers the
; recordset, so that it chains off `on`.
recordset:follow := { parent, column | | c |
    c := column:isKindOf(symbol):ifElse({ column }, { column:asSymbol }).
    self:table:columnNames:indexOf(c:asString):isNil:ifTrue({
        error:raise("no such column: ":concat(c:asString):concat(" in "):concat(self:table:name)) }).
    self:parent := parent.
    self:link := c.
    parent:followers:add(self).
    self:track.
    self }.

; The parent's rowid, or nil when it has no saved record to stand on.
recordset:parentKey := { | p |
    p := self:parent.
    (p:current:isNil:or({ p:isNew })):ifElse({ nil }, { p:current:rowid }) }.

; A query kept inside the parent's record, or left as it is when there is no
; parent.
recordset:narrowed := { q |
    self:parent:isNil:ifElse({ q }, { q:filter(self:link, "=", self:parentKey) }) }.

; The parent moved: every row under its record again, standing on the first.
; What was found among the previous record's rows is dropped with it.
recordset:track := {
    self:base := self:narrowed(self:table:all).
    self:isNew := false.
    self:current := nil.
    self:position := #1.
    self:refresh }.

; A record with rows following it is not deleted. The rows are counted in
; full, not as a follower narrowed by a `find` sees them, and the refusal
; names the table and how many. An orphaned row is worse than untidy here:
; the next record inserted can be given the deleted one's rowid, and the
; orphans would be under it.
recordset:refuseIfFollowed := {
    self:followers:do({ c | | n |
        n := c:table:all:filter(c:link, "=", self:current:rowid):count.
        n:greaterThan(#0):ifTrue({
            error:raise("not deleted: ":concat(n:asString)
                :concat(n:equals(#1):ifElse({ " row in " }, { " rows in " }))
                :concat(c:table:name)
                :concat(n:equals(#1):ifElse({ " follows it" }, { " follow it" }))) }) }).
    self }.
