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

@include "re.sol".

; ---------------------------------------------------------------------------
; A pattern is compiled once and asked many times
;
; `on` reads the pattern text and answers an object holding it in pieces. That
; is the shape because the caller is usually a search: the same pattern against
; a hundred thousand lines, and re-reading `[a-z]` at every one of them is the
; work worth not doing.

p := re:on("ab").
p:find("xxabxx"):print.                 ; #3
p:find("nothing here"):print.           ; nil

; `find` answers **where a match begins**, one-based, or nil. Not a boolean:
; the caller that only wants yes or no has `matches`, and the one that wants to
; move a cursor there needs the number.
p:matches("xxabxx"):print.              ; true
p:matches("nothing here"):print.        ; false

; ---------------------------------------------------------------------------
; The seven things a pattern is made of

re:on("a.c"):find("xxabc"):print.          ; #3   -- any one character
re:on("ab*c"):find("ac"):print.            ; #1   -- zero or more
re:on("ab*c"):find("abbbbc"):print.        ; #1
re:on("[0-9]"):find("port 8080"):print.    ; #6   -- one of these
re:on("[^0-9 ]"):find("80 x"):print.       ; #4   -- anything but
re:on("^ab"):find("abc"):print.            ; #1   -- the start of the text
re:on("^ab"):find("xabc"):print.           ; nil
re:on("c$"):find("abc"):print.             ; #3   -- the end of it
re:on("c$"):find("abcd"):print.            ; nil
re:on("a\\.c"):find("abc"):print.          ; nil  -- an escaped dot is a dot
re:on("a\\.c"):find("a.c"):print.          ; #1

; `^` and `$` are ordinary characters anywhere else, and a `*` with nothing
; before it is one too -- there is nothing there for it to repeat. That is vi's
; rule, and it is why a price and a shell variable can be searched for without
; being escaped.
re:on("a$b"):find("xa$b"):print.           ; #2
re:on("*"):find("2*3"):print.              ; #2

; ---------------------------------------------------------------------------
; Where a match ends, and where the next one is
;
; `find` answers only the beginning, because that is what a search wants. The
; end is a second question and has a second message, which nothing has to ask.

re:on("<.*>"):endOfMatchAt("<a><b>", #1):print.    ; #7

; A star takes as much as it can and gives characters back until the rest of the
; pattern fits, so `<.*>c` ends at the second `>` and not the first.
re:on("<.*>c"):endOfMatchAt("<a><b>c", #1):print.  ; #8

; `findFrom` starts at a position rather than at the beginning, which is how a
; second match is found; `findLast` looks for the last one that begins *before*
; a position, which is how a search runs backwards.
re:on("ab"):findFrom("abxab", #2):print.           ; #4
re:on("ab"):findLast("abxabxab", #7):print.        ; #4

; ---------------------------------------------------------------------------
; Putting something in a match's place
;
; The other half of `s/find/replace/`, and the reason `endOfMatchAt` is here at
; all: replacing a match needs to know where it ends.

re:on("a"):replaceIn("banana", "X"):display.        ; bXnana
re:on("a"):replaceAllIn("banana", "X"):display.     ; bXnXnX

; `&` in the replacement is what was matched, which is sed's rule and vi's;
; `\&` is an ampersand, and `\\` is a backslash.
re:on("an"):replaceAllIn("banana", "[&]"):display.  ; b[an][an]a
re:on("an"):replaceIn("banana", "\\&"):display.     ; b&ana

; A match that consumed nothing carries the character it stood on across and
; moves one further, because a loop that searched again from where it started
; would replace for ever. This is what sed answers too.
re:on("x*"):replaceAllIn("abc", "-"):display.       ; -a-b-c-

; And the rule beside it: an empty match *where the last one ended* is the same
; position seen twice, and is not a match. Without this `o*` over "aoc" answers
; "-a--c-" -- one dash for the `o`, and another for the nothing after it.
;
; The line above cannot show the difference, which is why these are here: in
; "abc" the star never matches a character, so no match has an end for a later
; empty one to land on. It takes a pattern that matches something.
re:on("o*"):replaceAllIn("aoc", "-"):display.       ; -a-c-
re:on("o*"):replaceAllIn("oo", "-"):display.        ; -
re:on("b*"):replaceAllIn("abc", "-"):display.       ; -a-c-
re:on("o*"):countIn("aoc"):print.                   ; #3

; And how many there are, which is what a substitution reports. Counted rather
; than compared: replacing `a` with `a` changes nothing and is still a
; substitution.
re:on("an"):countIn("banana"):print.                ; #2
re:on("q"):countIn("banana"):print.                 ; #0

; `substitutionIn` answers both in one walk of the text -- the new text and how
; many times it changed -- which is what a program replacing across a whole file
; wants and what `replaceAllIn` is with the count dropped.
done := re:on("an"):substitutionIn("banana", "AN", true).
done:at("text"):display.                                 ; bANANa
done:at("count"):print.                                  ; #2

; ---------------------------------------------------------------------------
; A pattern that will not read
;
; It raises, with a message a person can act on -- `programs/edit.sol` puts it
; on the bottom line and leaves the cursor where it was.

unclosed := { re:on("[abc") }:onError({ e | e:message }).
unclosed:display.             ; a pattern has an unclosed '['

dangling := { re:on("ab\\") }:onError({ e | e:message }).
dangling:display.             ; a pattern cannot end with a backslash

; ---------------------------------------------------------------------------
; Groups, and what a back-reference is for
;
; **A group is `\(...\)` here and `(...)` in an extended pattern**, numbered
; from one by its opening bracket, and `\1` in a *replacement* puts back what it
; took. That is the half `sed` needs and had been getting wrong: until
; 2026-09-01 `\(` was a literal parenthesis, so `s/\(ab\)c/YES/` matched the
; characters `(ab)c` and missed `abc` -- the wrong answer rather than a missing
; one, and nothing said so.

re:on("\\(ab\\)*c"):find("xababc"):print.        ; #2   -- a group, repeated
re:on("\\(a*\\)b"):replaceAllIn("aab b", "[\\1]"):display.
                                                ; [aa] []

; **A back-reference asks for the same text again**, which is the one thing a
; pattern can do that an automaton cannot -- and the reason this engine
; backtracks rather than simulating one.
re:on("\\(ab\\)\\1"):find("xabab"):print.        ; #2
re:on("\\(ab\\)\\1"):find("xabcd"):print.        ; nil

; ---------------------------------------------------------------------------
; The other dialect
;
; **`re:ere` is the same engine reading POSIX extended syntax**, where the
; operators are bare rather than backslashed. One message rather than a flag, so
; a reader of the call site can see which language the string is written in.
; `awk` means this one; `sed` and `vi` mean the other.

re:ere("(ab)+c"):find("ababc"):print.           ; #1
re:ere("colou?r"):find("color"):print.          ; #1
re:ere("a{2,3}"):endOfMatchAt("aaaa", #1):print.    ; #4   -- greedy, and bounded

; **Leftmost-longest, which is POSIX and is not what most engines give.**
; `a|ab` against `ab` answers the *longer* match, not the first alternative that
; succeeds -- and `a*ab` matches `aaab` whole, because `a*` gives characters
; back until `ab` fits.
re:ere("a|ab"):endOfMatchAt("ab", #1):print.    ; #3
re:ere("a*ab"):endOfMatchAt("aaab", #1):print.  ; #5

; ---------------------------------------------------------------------------
; What is not here, and the bargain that is
;
; No lookahead, no non-greedy `*?`, no named groups, no Unicode classes. Those
; are Perl's rather than POSIX's, and this is the two dialects the standard
; describes and nothing beside them.
;
; **The bargain is the same one `lib/shell.sol` strikes**: build a pattern out
; of things you wrote, not out of things a file or a user gave you. This is a
; backtracker, so a starred group inside a starred group -- `\(a\+\)\+b` against
; a run of `a` -- doubles per character on input that nearly matches. A pattern
; chosen by a stranger is a way to stop a program.
;
; Two things keep that bounded rather than theoretical. `--steps` stops a
; runaway and says so, because every step this takes is an instruction the
; machine counts -- which an engine inside a C primitive could not offer. And
; `guarded` turns on a visited set that removes the exponential outright, for a
; caller that does not control its input after all.
;
; **The matcher's depth is an array's length, not the call stack's**, so the
; length of a pattern and the length of the text cost nothing: a
; 2,000-character pattern compiles and matches. The file this replaced recursed
; once per `*` while matching and stopped at 250 of them.
;
; What still costs frames is the *compiler*, which walks a tree: **groups nested
; 48 deep compile and 49 do not**
; ([3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels)). That
; was 220 plain characters until a sequence was made a list rather than a spine
; of pairs, which is the same lesson three programs here have now learned.
