; keys.sol -- reading one key at a time.
;
; Run with:  ./bin/solas examples/keys.sol && ./bin/solvm examples/keys.sob
; Then press keys. `q` quits, and so does the end of input.
;
; `system:readLine` waits for return; this does not. That is the whole
; difference, and it is what anything interactive needs -- a menu, a pager, a
; game, a prompt that redraws as you type.
;
; It answers **one byte** as a one-character string, or **nil** at the end of
; input. Not a key: a key can be several bytes, and which several is the
; terminal's business rather than the language's. The arrow keys below are
; assembled here, out of the bytes, which is the point -- a program that only
; wants "any key" is not made to unpick a sequence it never asked about.
;
; Piped input works too, and reads the same way:
;
;     printf 'abq' | ./bin/solvm examples/keys.sob

escape := #27:asCharacter.

; An arrow arrives as escape, then '[', then one of A B C D. Reading the two
; after the escape is how that is told from the escape key on its own -- and
; from anything else beginning with one, which this reports rather than guesses
; at.
readArrow := { | bracket, letter |
    bracket := system:readKey.
    bracket:isNil:ifTrue({ error:raise("the input ended inside an escape") }).
    bracket:equals("["):ifFalse({ error:raise("not an arrow") }).

    letter := system:readKey.
    letter:isNil:ifTrue({ error:raise("the input ended inside an escape") }).
    "ABCD":indexOf(letter):isNil:ifTrue({ error:raise("not an arrow") }).

    ["up", "down", "right", "left"]:at("ABCD":indexOf(letter)) }.

"press keys -- q to quit":display.

done := false.
{ done:not }:whileTrue({ | key |
    key := system:readKey.

    key:isNil:ifTrue({ "":display. "end of input":display. done := true }).

    key:notNil:ifTrue({
        key:equals("q"):ifTrue({ "bye":display. done := true }).

        key:notNil:and({ key:equals("q"):not }):ifTrue({
            key:equals(escape):and({ system:keyWaiting(0.05) }):ifElse(
                ; An escape may begin an arrow or be the escape key itself, and
                ; the only way to know is to read on. `onError` is what makes
                ; that safe to try: a sequence that turns out to be something
                ; else is reported rather than swallowed.
                { { "  arrow: ":concat(readArrow:value):display }
                    :onError({ e | "  escape ({})":fill([e:message]):display }) },
                { key:asByte:lessThan(#32):ifElse(
                    { "  control byte #{}":fill([key:asByte]):display },
                    { "  {} (#{})":fill([key, key:asByte]):display }) }) }) }) }).

; **The escape key, and how it is told from the start of a sequence.** A
; byte-level reader cannot do it on its own: pressing escape and then tab reads
; the tab as the byte after the escape, and the tab is gone. A terminal tells
; them apart by waiting a few milliseconds and giving up, and that is
; `system:keyWaiting(0.05)` above -- *is a byte coming?* Nothing follows an
; escape that fast except a machine, so a false there means somebody pressed the
; key, and this program reports it as one rather than eating whatever is typed
; next.
;
; **This file asked for that message and did not get it for a day.** What is
; written just above used to end *"and `readKey` has none. Worth knowing before
; writing anything that binds the escape key on its own"*, and it stood as a
; warning nobody had tested, because nothing here bound that key. Then
; [programs/edit.sol](../programs/edit.sol) bound it to the most frequent action
; a modal editor has, found that escape did nothing until the *next* key
; arrived, and `keyWaiting` was built -- [6.35](../docs/COMPLETED.md#635-a-read-that-gives-up--done).
;
; **Piped input has no timing in it**, and this is where that shows. Down a pipe
; every byte is already there, so `keyWaiting` says true and an escape is always
; read as the start of a sequence:
;
;     printf '\033q' | ./bin/solvm examples/keys.sob    ; the q is eaten
;
; which is right rather than a compromise -- a program cannot invent a pause
; nobody typed. It is worth knowing before testing an editor through a pipe and
; concluding that its escape key is broken.
;
; The rule that stayed: a *program* is what turns a known limitation into a
; fixed one. The warning was right, it was written on the day `readKey` landed,
; and it waited for somebody to be annoyed by it.
