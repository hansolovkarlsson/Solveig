; awk.sol -- the pattern-action language, POSIX.
;
; Run with:  ./bin/solas programs/awk.sol && ./bin/solvm programs/awk.sob
; A program and files:  ./bin/solvm awk.sob '{ print $2 }' data.txt
; A program from a file: ./bin/solvm awk.sob -f prog.awk data.txt
; With no arguments it demonstrates itself.
;
; ---------------------------------------------------------------------------
; The nineteenth program here, and the first customer of the extended dialect
;
; [lib/re.sol](../lib/re.sol) reads POSIX basic and extended regular
; expressions, and `sed` and `edit` both want the basic one. awk is the first
; program to want `re:ere` -- and it wants it by *standard* rather than by
; taste, which is a stronger thing for a library to be held to: POSIX says what
; `/a|ab/` matches, so a divergence is a defect rather than a preference.
;
; **It was written after the library rather than before it**, which was the
; whole of the argument on 2026-09-01: awk's largest demand already had two
; customers -- `sed`, whose `\(...\)` was silently wrong, and `edit`'s `/` --
; so writing awk to justify the engine would have been the wrong order.
; [ideas.md](../docs/ideas.md#programs-that-would-press-on-something) has the
; prediction that entry made, written before this file existed, and the
; predictions are worth keeping honest: full ERE, a **lenient numeric read**,
; and `%e`/`%g` formatting were the three things it said awk would want.
;
; ---------------------------------------------------------------------------
; The thing awk is, that nothing else here is
;
; **A value is a string and a number at once**, and which one it behaves as
; depends on where it came from. `"10" < "9"` is true because both are strings;
; `$1 < $2` on the input `10 9` is *false*, because a field that looks like a
; number is compared as one. POSIX calls that a *strnum*, and it is the single
; rule that makes awk awk.
;
; Solum is strict in the other direction -- `#5:add(1.5)` refuses, and the error
; says *no implicit coercion* -- so this is modelling work rather than a gap. A
; value here is a `cell` carrying both forms and a note of which it trusts.

@include "re.sol".
@include "text.sol".

; ---------------------------------------------------------------------------
; A value
;
; `kind` is what the value *is*, which decides comparison:
;
;   'num       arithmetic produced it, or a numeric literal
;   'str       a string literal, or a string operation produced it
;   'strnum    it came from input and looks like a number: compares as one
;   'uninit    never assigned: it is "" and 0 at the same time

cell := object:new.
cell:s := "".
cell:n := 0.0.
cell:kind := 'uninit.

num := { x | | c | c := cell:new. c:kind := 'num.
    c:n := x:isKindOf(float):ifElse({ x }, { x:asFloat }). c }.
str := { t | | c | c := cell:new. c:kind := 'str. c:s := t. c }.
uninit := { | c | c := cell:new. c }.

; **The lenient numeric read the scoping predicted.** `asInteger` and `asFloat`
; are strict on purpose -- the reference says the whole string must be a number
; -- and awk needs the opposite: `"3abc" + 0` is 3, `"" + 0` is 0, `" 7 " + 0`
; is 7. So the leading numeric prefix is scanned here rather than asked for from
; the language, which is the prediction holding and the finding being smaller
; than it looked: this is nine lines and wants nothing new.
numericPrefix := { t | | s, i, seen, dot, ex, out, c |
    s := t:trim. out := "". i := #1. seen := false. dot := false. ex := false.
    (s:size:greaterThan(#0)
        :and({ "+-":indexOf(s:at(#1)):notNil })):ifTrue({
        out := s:at(#1). i := #2 }).
    { i:lessOrEqual(s:size) }:whileTrue({ | stop |
        c := s:at(i). stop := false.
        "0123456789":indexOf(c):notNil:ifElse(
            { out := out:concat(c). seen := true },
            { (c:equals("."):and({ dot:not }):and({ ex:not })):ifElse(
                { out := out:concat(c). dot := true },
                { (("eE":indexOf(c):notNil):and({ seen }):and({ ex:not })
                    :and({ i:lessThan(s:size) })):ifElse(
                    { | j |
                      j := i:inc.
                      ("+-":indexOf(s:at(j)):notNil):ifTrue({ j := j:inc }).
                      (j:lessOrEqual(s:size)
                          :and({ "0123456789":indexOf(s:at(j)):notNil })):ifElse(
                          { out := out:concat(c). ex := true },
                          { stop := true }) },
                    { stop := true }) }) }).
        stop:ifElse({ i := s:size:inc }, { i := i:inc }) }).
    seen:ifElse({ out }, { nil }) }.

; Does the whole of it read as a number? That is what makes a field a strnum.
looksNumeric := { t | | p |
    p := numericPrefix:value(t).
    p:notNil:and({ p:equals(t:trim) }) }.

field := { t | | c |
    c := cell:new.
    c:s := t.
    looksNumeric:value(t):ifElse(
        { c:kind := 'strnum. c:n := numericPrefix:value(t):asFloat },
        { c:kind := 'str }).
    c }.

; ---------------------------------------------------------------------------
; Reading a value as one thing or the other

toNum := { c |
    c:kind:equals('str):ifElse(
        { | p | p := numericPrefix:value(c:s).
          p:isNil:ifElse({ 0.0 }, { p:asFloat }) },
        { c:kind:equals('uninit):ifElse({ 0.0 }, { c:n }) }) }.

; **`%.6g` had to be written, which is the third prediction holding.**
; `asString(spec)` has width, fill, alignment, thousands and *fixed* decimals --
; `45.8:asString("6.2")` is `" 45.80"` -- and not significant digits, which is
; what awk's CONVFMT and OFMT default to. It is laborious rather than blocked:
; `log`, `floor` and `pow` are all here, so the exponent is one division and the
; rest is trimming zeros.
;
; An integral value prints as an integer, which is awk's rule and the reason
; `print 1/1` says `1` rather than `1.000000`.
sixG := { x, digits | | e, out, scaled, dot, i, last |
    x:equals(0.0):ifElse({ "0" }, {
        ; **The exponent has to be corrected after the division**, because
        ; `ln(1e30)/ln(10)` is 29.999999999999996 and flooring it gives 29 --
        ; which put 1e30 on the fixed side of the switch where awk puts it on
        ; the scientific one. Found by holding thirteen numbers against the tool
        ; and having one disagree.
        e := x:abs:log:div(10.0:log):floor.
        (10.0:pow(e:asFloat):greaterThan(x:abs)):ifTrue({ e := e:sub(#1) }).
        (10.0:pow(e:inc:asFloat):lessOrEqual(x:abs)):ifTrue({ e := e:inc }).
        (e:lessThan(#0:sub(#4)):or({ e:greaterOrEqual(digits) })):ifElse(
            { ; scientific, with digits-1 after the point
              scaled := x:div(10.0:pow(e:asFloat)).
              out := scaled:asString("0.":concat(digits:sub(#1):asString)).
              out := trimZeros:value(out).
              out:concat("e"):concat(e:lessThan(#0):ifElse({ "-" }, { "+" }))
                 :concat(e:abs:asString("02")) },
            { out := x:asString("0.":concat(
                  digits:sub(#1):sub(e):asString)).
              trimZeros:value(out) }) }) }.

trimZeros := { t | | out, i |
    t:indexOf("."):isNil:ifElse({ t }, {
        out := t. i := out:size.
        { i:greaterThan(#1):and({ out:at(i):equals("0") }) }:whileTrue({
            out := out:copyFrom(#1, i:sub(#1)). i := i:sub(#1) }).
        out:at(out:size):equals("."):ifTrue({
            out := out:copyFrom(#1, out:size:sub(#1)) }).
        out }) }.

convfmt := #6.

; **An integral value prints in full**, which is awk's rule and the reason
; `print 1/1` says `1` and `print 1e20` says a hundred million million million
; rather than `1e+20`. Held against the tool: it is `%.30g` for those, so 1e20
; comes out in full and 1e30 goes back to scientific, and both were checked.
;
; The magnitude test comes **first**, and that is not style: `and` takes a block
; so the second test is not evaluated, but the receiver is -- and `truncated` on
; 1e20 raises rather than answering, so asking it before the guard is asking the
; question the guard exists to prevent. Above 2^53 every double is integral
; anyway, so the test is only needed below it.
numToStr := { x |
    x:abs:greaterOrEqual(1.0e15):ifElse(
        { sixG:value(x, #30) },
        { x:equals(x:truncated:asFloat):ifElse(
            { x:truncated:asString },
            { sixG:value(x, convfmt) }) }) }.

toStr := { c |
    c:kind:equals('num):ifElse(
        { numToStr:value(c:n) },
        { c:kind:equals('uninit):ifElse({ "" }, { c:s }) }) }.

; Truth in awk: a number is true when it is not zero, a string when it is not
; empty, and a strnum goes by its number -- so a field holding "0" is false.
toBool := { c |
    c:kind:equals('str):ifElse(
        { c:s:notEquals("") },
        { c:kind:equals('uninit):ifElse({ false },
            { toNum:value(c):notEquals(0.0) }) }) }.

; Comparison, and the rule the whole language turns on: **numeric if both sides
; are numbers, or one is a number and the other a strnum**; otherwise string.
compare := { a, b | | an, bn |
    an := a:kind:equals('num):or({ a:kind:equals('strnum) })
        :or({ a:kind:equals('uninit) }).
    bn := b:kind:equals('num):or({ b:kind:equals('strnum) })
        :or({ b:kind:equals('uninit) }).
    (an:and({ bn })):ifElse(
        { | x, y | x := toNum:value(a). y := toNum:value(b).
          x:lessThan(y):ifElse({ #0:sub(#1) },
              { x:greaterThan(y):ifElse({ #1 }, { #0 }) }) },
        { | x, y | x := toStr:value(a). y := toStr:value(b).
          x:lessThan(y):ifElse({ #0:sub(#1) },
              { x:greaterThan(y):ifElse({ #1 }, { #0 }) }) }) }.
