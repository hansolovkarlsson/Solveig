; matching.sol -- regular expressions, in the subset an editor searches with.
;
; Run with:  ./bin/solas examples/matching.sol && ./bin/solvm examples/matching.sob
;
; Called `matching.sol` and not `pattern.sol` because a file that includes a
; library of its own name finds *itself* on the search path first, and, a file
; being compiled once, that include quietly does nothing --
; [6.22](../docs/COMPLETED.md#622-a-file-that-includes-a-library-of-its-own-name-silently-does-nothing--done).
; [examples/scanning.sol](scanning.sol) is named the same way and for the same
; reason.

@include "pattern.sol".

; ---------------------------------------------------------------------------
; A pattern is compiled once and asked many times
;
; `on` reads the pattern text and answers an object holding it in pieces. That
; is the shape because the caller is usually a search: the same pattern against
; a hundred thousand lines, and re-reading `[a-z]` at every one of them is the
; work worth not doing.

p := pattern:on("ab").
p:find("xxabxx"):print.                 ; #3
p:find("nothing here"):print.           ; nil

; `find` answers **where a match begins**, one-based, or nil. Not a boolean:
; the caller that only wants yes or no has `matches`, and the one that wants to
; move a cursor there needs the number.
p:matches("xxabxx"):print.              ; true
p:matches("nothing here"):print.        ; false

; ---------------------------------------------------------------------------
; The seven things a pattern is made of

pattern:on("a.c"):find("xxabc"):print.          ; #3   -- any one character
pattern:on("ab*c"):find("ac"):print.            ; #1   -- zero or more
pattern:on("ab*c"):find("abbbbc"):print.        ; #1
pattern:on("[0-9]"):find("port 8080"):print.    ; #6   -- one of these
pattern:on("[^0-9 ]"):find("80 x"):print.       ; #4   -- anything but
pattern:on("^ab"):find("abc"):print.            ; #1   -- the start of the text
pattern:on("^ab"):find("xabc"):print.           ; nil
pattern:on("c$"):find("abc"):print.             ; #3   -- the end of it
pattern:on("c$"):find("abcd"):print.            ; nil
pattern:on("a\\.c"):find("abc"):print.          ; nil  -- an escaped dot is a dot
pattern:on("a\\.c"):find("a.c"):print.          ; #1

; `^` and `$` are ordinary characters anywhere else, and a `*` with nothing
; before it is one too -- there is nothing there for it to repeat. That is vi's
; rule, and it is why a price and a shell variable can be searched for without
; being escaped.
pattern:on("a$b"):find("xa$b"):print.           ; #2
pattern:on("*"):find("2*3"):print.              ; #2

; ---------------------------------------------------------------------------
; Where a match ends, and where the next one is
;
; `find` answers only the beginning, because that is what a search wants. The
; end is a second question and has a second message, which nothing has to ask.

pattern:on("<.*>"):endOfMatchAt("<a><b>", #1):print.    ; #7

; A star takes as much as it can and gives characters back until the rest of the
; pattern fits, so `<.*>c` ends at the second `>` and not the first.
pattern:on("<.*>c"):endOfMatchAt("<a><b>c", #1):print.  ; #8

; `findFrom` starts at a position rather than at the beginning, which is how a
; second match is found; `findLast` looks for the last one that begins *before*
; a position, which is how a search runs backwards.
pattern:on("ab"):findFrom("abxab", #2):print.           ; #4
pattern:on("ab"):findLast("abxabxab", #7):print.        ; #4

; ---------------------------------------------------------------------------
; Putting something in a match's place
;
; The other half of `s/find/replace/`, and the reason `endOfMatchAt` is here at
; all: replacing a match needs to know where it ends.

pattern:on("a"):replaceIn("banana", "X"):display.        ; bXnana
pattern:on("a"):replaceAllIn("banana", "X"):display.     ; bXnXnX

; `&` in the replacement is what was matched, which is sed's rule and vi's;
; `\&` is an ampersand, and `\\` is a backslash.
pattern:on("an"):replaceAllIn("banana", "[&]"):display.  ; b[an][an]a
pattern:on("an"):replaceIn("banana", "\\&"):display.     ; b&ana

; A match that consumed nothing carries the character it stood on across and
; moves one further, because a loop that searched again from where it started
; would replace for ever. This is what sed answers too.
pattern:on("x*"):replaceAllIn("abc", "-"):display.       ; -a-b-c-

; And how many there are, which is what a substitution reports. Counted rather
; than compared: replacing `a` with `a` changes nothing and is still a
; substitution.
pattern:on("an"):countIn("banana"):print.                ; #2
pattern:on("q"):countIn("banana"):print.                 ; #0

; ---------------------------------------------------------------------------
; A pattern that will not read
;
; It raises, with a message a person can act on -- `programs/edit.sol` puts it
; on the bottom line and leaves the cursor where it was.

unclosed := { pattern:on("[abc") }:onError({ e | e:message }).
unclosed:display.             ; a pattern has an unclosed '['

dangling := { pattern:on("ab\\") }:onError({ e | e:message }).
dangling:display.             ; a pattern cannot end with a backslash

; ---------------------------------------------------------------------------
; What is not here
;
; No groups, no alternation, no `+` or `?`, no captures, no counted repetition.
; Those want a backtracker over a tree rather than over a list, and nothing has
; wanted one. What is here is what vi searches with, which is the half that
; earns its keep.
;
; The one number worth knowing: **the matcher recurses once per `*`**, and
; nowhere else. 250 stars in one pattern work and 251 does not
; ([3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels)), while
; the length of the pattern and the length of the text cost nothing at all --
; a 2,001-character line is searched at a depth of two.
