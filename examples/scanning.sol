; scanning.sol -- a cursor over text: a position, and the questions you ask at
; one.
;
; Called `scanning.sol` and not `scan.sol` for the same reason
; [manifest.sol](../programs/manifest.sol) is not called `json.sol`: a file
; that includes a library of its own name finds *itself*, and the include does
; nothing. That is [6.22](../docs/COMPLETED.md#622-a-file-that-includes-a-library-of-its-own-name-silently-does-nothing--done),
; and writing this file is how it was fallen into for the third time -- the
; warning it added is what said so.
;
; The library exists because five files here had each written the same object,
; which is [5.5](../docs/COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done).
; It is deliberately not a pattern language: what repeated across those files
; was never a pattern, it was a position.

@include "scan.sol".

; ---------------------------------------------------------------------------
; Looking without moving

s := scan:on("8080ab").
s:pos:print.                     ; #1
s:peek:print.                    ; "8"
s:peekAt(#0):print.              ; "8"
s:peekAt(#1):print.              ; "0"
s:atEnd:print.                   ; false
s:looksLike("8080"):print.       ; true
s:looksLike("80x"):print.        ; false

; Nothing above moved the cursor.
s:pos:print.                     ; #1

; ---------------------------------------------------------------------------
; Runs
;
; A predicate is a question about a character. The cursor never hands it nil, so
; it says nothing about running out -- which every hand-written version of this
; loop had to.

digit := { c | c:greaterOrEqual("0"):and({ c:lessOrEqual("9") }) }.

s:takeWhile(digit):print.        ; "8080"
s:peek:print.                    ; "a"

; It answers the empty string when the first character already fails, rather
; than raising.
s:takeWhile(digit):print.        ; ""

s:rest:print.                    ; "ab"
s:atEnd:print.                   ; true
s:peek:print.                    ; nil

; ---------------------------------------------------------------------------
; Moving

t := scan:on("  hello, world").
t:skipWhile({ c | c:equals(" ") }).
t:takeUntil({ c | c:equals(",") }):print.    ; "hello"

; `match` consumes only if it was there, and says which.
t:match("nope"):print.                       ; false
t:match(", "):print.                         ; true
t:rest:print.                                ; "world"

u := scan:on("abc").
u:next:print.                    ; "a"
u:take(#2):print.                ; "bc"

; `next` at the end answers nil and stays put, so a cursor cannot walk off.
u:next:print.                    ; nil
u:pos:print.                     ; #4
u:next:print.                    ; nil
u:pos:print.                     ; #4

; `take` gives what is there when the text runs out.
scan:on("ab"):take(#10):print.   ; "ab"

; ---------------------------------------------------------------------------
; The span one predicate cannot describe
;
; `takeWhile` covers a run of one kind of character. A grammar in parts -- a
; sign, then digits, then a fraction, then an exponent -- is not one run, and
; what the caller wants at the end is all of it. `pos` is the mark.

n := scan:on("-12.5e3!").
start := n:pos.
n:match("-").
n:skipWhile(digit).
n:match("."):ifTrue({ n:skipWhile(digit) }).
n:match("e"):ifTrue({ n:skipWhile(digit) }).
n:since(start):print.            ; "-12.5e3"
n:peek:print.                    ; "!"

; ---------------------------------------------------------------------------
; Backtracking, which is why `pos` is written as well as read

v := scan:on("&notanentity;").
mark := v:pos.
v:match("&").
lower := { c | c:greaterOrEqual("a"):and({ c:lessOrEqual("z") }) }.
v:takeWhile(lower):print.        ; "notanentity"

; Not a real entity, so put the cursor back and take the "&" literally.
v:pos := mark.
v:next:print.                    ; "&"

; ---------------------------------------------------------------------------
; Two at once
;
; `on` answers a new cursor rather than resetting a shared one, so scanning one
; thing while part-way through another is fine.

a := scan:on("11").
b := scan:on("22").
a:next:print.                    ; "1"
b:next:print.                    ; "2"
a:next:print.                    ; "1"
b:next:print.                    ; "2"
