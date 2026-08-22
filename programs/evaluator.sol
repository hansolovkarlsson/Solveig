; evaluator.sol -- a calculator: tokenise, parse, evaluate.
; Run with:  ./bin/solas programs/evaluator.sol && ./bin/solvm programs/evaluator.sob
;
; The second program here, and deliberately a different shape from the first. log.sol is line-oriented: read
; text, split it, tally it. This one recurses, builds a tree of objects, and has
; to say something useful when its input is wrong -- which is the ground the
; other one never touched.
;
;     expression -> term (('+' | '-') term)*
;     term       -> factor (('*' | '/') factor)*
;     factor     -> number | '(' expression ')' | '-' factor
;
; Three things it found are in the comments where they bit, and the largest is
; at the bottom, under "how deep it goes".

digits := "0123456789".
isDigit := { c | digits:indexOf(c):notNil }.

token := object:new. token:text := "". token:at := #0.
; A constructor block rather than `( | t | ... )` written twice below. Groups
; share the frame they sit in, so two of them in one block cannot both declare
; `t` -- which is the documented rule, and it means the group-temporary idiom
; does not compose. A block of its own is better here anyway.
makeToken := { text, at | | t | t := token:new. t:text := text. t:at := at. t }.

tokenise := { source | | out, i, c, start |
    out := array:new. i := #1.
    { i:lessOrEqual(source:size) }:whileTrue({
        c := source:at(i).
        c:equals(" "):ifElse({ i := i:add(#1) }, {
            isDigit:value(c):ifElse({
                start := i.
                { i:lessOrEqual(source:size):and({ isDigit:value(source:at(i)) }) }
                    :whileTrue({ i := i:add(#1) }).
                out:add(makeToken:value(source:copyFrom(start, i:sub(#1)), start)) },
                { out:add(makeToken:value(c, i)). i := i:add(#1) }) }) }).
    out }.

; --- the tree ---
node := object:new. node:kind := 'number. node:value := #0.
node:op := "". node:left := nil. node:right := nil.

number := { v | | n | n := node:new. n:kind := 'number. n:value := v. n }.
binary := { op, l, r | | n |
    n := node:new. n:kind := 'binary. n:op := op. n:left := l. n:right := r. n }.
negate := { x | | n | n := node:new. n:kind := 'negate. n:left := x. n }.

; --- the parser ---
tokens := array:new.
pos := #1.
text := "".

peek := { pos:lessOrEqual(tokens:size):ifElse({ tokens:at(pos) }, { nil }) }.
next := { | t | t := peek:value. pos := pos:add(#1). t }.
; Past the last token the position is the end of the *source*, not the number of
; tokens -- which is what this said at first, and it answered 3 for "1 +" where
; the column is 4. A token index and a column are different numbers that agree
; often enough on small input to look right.
here := { | t | t := peek:value. t:isNil:ifElse({ text:size:add(#1) }, { t:at }) }.

isOneOf := { set | | t |
    t := peek:value.
    t:isNil:ifElse({ false }, { set:indexOf(t:text):notNil }) }.

parseExpression := { | left |
    left := parseTerm:value.
    { isOneOf:value("+-") }:whileTrue({ | op |
        op := next:value:text.
        left := binary:value(op, left, parseTerm:value) }).
    left }.

parseTerm := { | left |
    left := parseFactor:value.
    { isOneOf:value("*/") }:whileTrue({ | op |
        op := next:value:text.
        left := binary:value(op, left, parseFactor:value) }).
    left }.

; `ifElse`, not `ifTrue` with two arguments -- which was written twice while
; this was being put together and is not caught until it runs. The compiler
; cannot catch it: it knows `ifTrue` well enough to inline one, but not what the
; receiver is, and any object may define an `ifTrue` of its own taking two. That
; is the same ignorance that keeps a counted loop from being inlined (6.6), and
; it is the price of everything being a message rather than a mistake.
parseFactor := { | t, inner |
    t := peek:value.
    t:isNil:ifTrue({ error:raise("expected a number at {}":fill([here:value])) }).
    t:text:equals("-"):ifElse({ next:value. negate:value(parseFactor:value) }, {
        t:text:equals("("):ifElse({
            next:value.
            inner := parseExpression:value.
            isOneOf:value(")"):ifFalse({
                error:raise("expected ')' at {}":fill([here:value])) }).
            next:value.
            inner },
            { isDigit:value(t:text:at(#1)):ifFalse({
                  error:raise("expected a number at {}, got '{}'"
                      :fill([t:at, t:text])) }).
              next:value.
              number:value(t:text:asInteger) }) }) }.

parse := { source | | tree |
    text := source.
    tokens := tokenise:value(source).
    pos := #1.
    tree := parseExpression:value.
    peek:value:notNil:ifTrue({
        error:raise("unexpected '{}' at {}":fill([peek:value:text, here:value])) }).
    tree }.

; --- evaluation ---
evaluate := { n |
    n:kind:equals('number):ifElse({ n:value }, {
        n:kind:equals('negate):ifElse({ #0:sub(evaluate:value(n:left)) }, {
            | l, r |
            l := evaluate:value(n:left).
            r := evaluate:value(n:right).
            n:op:equals("+"):ifElse({ l:add(r) }, {
            n:op:equals("-"):ifElse({ l:sub(r) }, {
            n:op:equals("*"):ifElse({ l:mul(r) }, {
            n:op:equals("/"):ifElse({ l:div(r) }, {
                error:raise("unknown operator '{}'":fill([n:op])) }) }) }) }) }) }) }.

run := { source |
    { "{} = {}":fill([source, evaluate:value(parse:value(source)):asString]):display }
        :onError({ e | "{} -- {}":fill([source, e:message]):display }) }.


; ---------------------------------------------------------------------------
; It works

run:value("1 + 2").                          ; 3
run:value("2 + 3 * 4").                      ; 14 -- precedence, not left to right
run:value("(2 + 3) * 4").                    ; 20
run:value("100 / 7").                        ; 14 -- integer division floors
run:value("-5 + 3").                         ; -2
run:value("2 * (3 + (4 - 1))").              ; 12

; ---------------------------------------------------------------------------
; It says where it went wrong
;
; The parser raises with a position, and the machine's own failures arrive
; through the same handler with messages of their own. Neither half is much use
; alone: `division by zero in 'div'` does not say which expression, and
; `expected a number at 4` does not say what was wrong with the number.

run:value("1 +").                            ; expected a number at 4
run:value("(1 + 2").                         ; expected ')' at 7
run:value("1 + + 2").                        ; expected a number at 5, got '+'
run:value("1 2").                            ; unexpected '2' at 3
run:value("2 $ 3").                          ; unexpected '$' at 3
run:value("1 / 0").                          ; division by zero in 'div'
run:value("999999999999999999999999").       ; out of integer range

; ---------------------------------------------------------------------------
; How deep it goes
;
; This is the finding worth having written the program for.
;
; A recursive-descent parser spends about three frames per level of nesting --
; expression calls term calls factor calls expression again for a bracket -- and
; the machine has 62. So the limit is real and a program can reach it:

run:value("((((((((((((((((((1+2))))))))))))))))))").      ; 18 deep: 3
run:value("(((((((((((((((((((1+2)))))))))))))))))))").    ; 19 deep: it stops

; **And it is catchable.** `call depth exceeded` arrives at `onError` like any
; other failure, is reported like any other failure, and the program carries on
; -- which is not obvious, since running out of frames is exactly the sort of
; failure a language might not be able to recover from. Everything below still
; works:

run:value("7 * 6").                          ; 42
run:value("(((1+2)))").                      ; 3

; A deeper limit would be a bigger `SOL_FRAMES_MAX`, which costs stack because
; `SOL_STACK_MAX` is derived from it -- see ROADMAP 3.5. Eighteen brackets is
; more than anybody writes by hand and less than a generated expression might
; hold, so what matters is that the failure is a failure and not a crash.
