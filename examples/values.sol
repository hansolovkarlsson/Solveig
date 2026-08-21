; Everything in Solum is an object, but they divide in two on one question:
; can this thing change? That single split decides what `equals` means, what
; `a := b` does, and whether handing something to a block is safe.
; Run with:  ./bin/solas examples/values.sol && ./bin/solvm examples/values.sob

; ---------------------------------------------------------------------------
; Values: numbers, strings, symbols, booleans, nil

; They are immutable, so two of them are equal when they SAY the same thing.
; Nothing can change 45 into something else, so sharing one is always safe.
a := #45.
b := #45.
a:equals(b):print.               ; true   -- the same number

s := "hello".
t := "hel":concat("lo").
s:equals(t):print.               ; true   -- built differently, equal anyway

; `concat` answers a new string. It cannot change `s`, because there is no
; message that changes a string -- that is what immutable means.
s:concat(" there"):print.        ; "hello there"
s:print.                         ; "hello"   -- untouched

; So rebinding a name affects only that name. `b` was never a window onto `a`.
a := #1.
b:print.                         ; #45

; ---------------------------------------------------------------------------
; References: objects, arrays, blocks

; They can change, so two of them are equal only when they are THE SAME ONE.
xs := [#1, #2].
ys := [#1, #2].
xs:equals(ys):print.             ; false  -- same contents, two arrays
xs:equals(xs):print.             ; true

; And `zs := xs` makes two names for one array, not a copy.
zs := xs.
zs:add(#3).
xs:print.                        ; [#1, #2, #3]   -- visible through both names
xs:equals(zs):print.             ; true

; The same holds for objects.
point := object:new.
point:x := #0.
p := point:new.
q := p.
q:x := #99.
p:x:print.                       ; #99   -- one object, two names

r := point:new.
p:equals(r):print.               ; false -- two objects, both fresh
r:x:print.                       ; #0    -- and r never saw the assignment

; ---------------------------------------------------------------------------
; Why the split is where it is

; It is not arbitrary. Mutability is what makes identity matter: if a thing can
; change under you, you need to know whether the thing you are holding is the
; thing that changed. If it cannot change, that question has no consequences,
; so equality can be about contents instead.

; It is also what lets numbers ride unboxed. A number never needs a place on the
; heap for someone else to point at, because nobody can change it there.

; ---------------------------------------------------------------------------
; Mutable state lives in slots

; Since a number cannot change, state is held by giving an object a slot and
; changing what the slot holds.
counter := object:new.
counter:n := #0.
counter:bump := { self:n := self:n:add(#1) }.

c := counter:new.
c:bump. c:bump. c:bump.
c:n:print.                       ; #3

; Assigning on an instance always makes the INSTANCE's own slot, shadowing the
; prototype rather than writing through to it -- so one instance cannot change
; all of them.
counter:n:print.                 ; #0   -- the prototype is untouched

d := counter:new.
d:n:print.                       ; #0   -- and a new instance starts fresh

; ---------------------------------------------------------------------------
; Blocks are references too

; Two blocks written the same way are two blocks.
{ #1 }:equals({ #1 }):print.     ; false

; Which is what makes `boundTo` answer a new block rather than changing one:
; see examples/reflect.sol and docs/fetched-methods.md.

; ---------------------------------------------------------------------------
; nil and the booleans

; nil is the answer of a branch not taken and of a method with nothing to say.
false:ifTrue({ #1 }):print.      ; nil
nil:equals(nil):print.           ; true

; isNil asks whether a value is there, and notNil is its negative. Both are on
; every type, which they have to be: the point of asking is that you do not know
; what the receiver is, so a message only nil understood could not be sent to
; find out.
nil:isNil:print.                 ; true
#1:isNil:print.                  ; false
#1:notNil:print.                 ; true

; Absence is not emptiness. None of these is nil.
"":isNil:print.                  ; false
[]:isNil:print.                  ; false
#0:isNil:print.                  ; false
false:isNil:print.               ; false

; notNil is the form that gets written, since running out of something is how a
; loop finishes -- see examples/reading.sol, which reads until readLine is nil.

; Booleans are values, and they are the only thing control flow accepts -- there
; is no truthiness, so a number is not a condition:
;   #1:ifTrue({ #2 }).           ; solvm: integer does not understand 'ifTrue'
true:notEquals(false):print.     ; true
