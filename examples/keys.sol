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
            key:equals(escape):ifElse(
                ; An escape may begin an arrow or be the escape key itself, and
                ; the only way to know is to read on. `onError` is what makes
                ; that safe to try: a sequence that turns out to be something
                ; else is reported rather than swallowed.
                { { "  arrow: ":concat(readArrow:value):display }
                    :onError({ e | "  escape ({})":fill([e:message]):display }) },
                { key:asByte:lessThan(#32):ifElse(
                    { "  control byte #{}":fill([key:asByte]):display },
                    { "  {} (#{})":fill([key, key:asByte]):display }) }) }) }) }).

; One thing it cannot do, and no byte-level reader can: **tell the escape key
; from the start of a sequence.** Pressing escape and then tab reads the tab as
; the byte after the escape and reports "not an arrow" -- the tab is gone. A
; terminal tells them apart by waiting a few milliseconds and giving up, which
; needs a read with a timeout, and `readKey` has none. Worth knowing before
; writing anything that binds the escape key on its own.
;
; What this wanted otherwise: nothing. It is the first program here to find the
; language already had what it needed -- which is only true because it is the
; program 6.10 was waiting for, and 6.10 was built the day before it.
