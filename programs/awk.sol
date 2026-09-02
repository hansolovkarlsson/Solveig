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

; ---------------------------------------------------------------------------
; The tokens
;
; **`/` is the only character whose meaning depends on what came before it.**
; `a / b` divides and `/a/ { ... }` matches, and no amount of looking forward
; tells them apart -- `/` after a value is division, `/` after an operator or at
; the start of a statement opens a regular expression. So the scanner carries
; one bit of state, and it is the only state it carries.

token := object:new.
token:kind := 'eof.     ; num str ere name func builtin keyword op newline eof
token:text := "".
token:n := 0.0.

keywords := ["BEGIN", "END", "function", "func", "if", "else", "while", "for",
             "do", "break", "continue", "next", "nextfile", "exit", "return",
             "delete", "in", "getline", "print", "printf"].

builtins := ["length", "substr", "index", "split", "sub", "gsub", "match",
             "sprintf", "sin", "cos", "atan2", "exp", "log", "sqrt", "int",
             "rand", "srand", "tolower", "toupper", "system", "close"].

; Longest first, so that `>=` is not read as `>` and `=`.
operators := ["...", "**=", "&&", "||", "==", "!=", "<=", ">=", "+=", "-=",
              "*=", "/=", "%=", "^=", "**", "++", "--", "!~", ">>", "{", "}",
              "(", ")", "[", "]", ";", ",", "+", "-", "*", "/", "%", "^", "=",
              "<", ">", "!", "~", "?", ":", "$", "|"].

lexer := object:new.
lexer:src := "".
lexer:at := #1.
lexer:tokens := nil.
lexer:regexOk := true.      ; may a `/` here open a regular expression?

lexer:peekAt := { k | k:greaterThan(self:src:size):ifElse(
    { "" }, { self:src:at(k) }) }.

; **Nothing is one of a set**, which the empty string at end of input is not.
; `indexOf` refuses an empty needle rather than answering nil -- correctly, since
; "where is nothing" has no answer -- so the end of the source has to be asked
; about before it is looked up, and once rather than at nine call sites.
oneOf := { set, c | c:notEquals(""):and({ set:indexOf(c):notNil }) }.
lexer:here := { self:peekAt(self:at) }.

lexer:add := { kind, text | | t |
    t := token:new. t:kind := kind. t:text := text.
    self:tokens:add(t).
    ; After a value, `/` divides; after anything else it opens a pattern.
    self:regexOk := (kind:equals('num):or({ kind:equals('str) })
        :or({ kind:equals('name) }):or({ kind:equals('ere) })
        :or({ text:equals(")") }):or({ text:equals("]") })
        :or({ text:equals("$") }):or({ text:equals("++") })
        :or({ text:equals("--") })):not.
    t }.

lexer:number := { | start, seen |
    start := self:at.
    { oneOf:value("0123456789", self:here) }:whileTrue({
        self:at := self:at:inc }).
    self:here:equals("."):ifTrue({ self:at := self:at:inc.
        { oneOf:value("0123456789", self:here) }:whileTrue({
            self:at := self:at:inc }) }).
    (oneOf:value("eE", self:here)):ifTrue({ | save |
        save := self:at. self:at := self:at:inc.
        (oneOf:value("+-", self:here)):ifTrue({ self:at := self:at:inc }).
        (oneOf:value("0123456789", self:here):not):ifElse(
            { self:at := save },
            { { oneOf:value("0123456789", self:here) }:whileTrue({
                  self:at := self:at:inc }) }) }).
    self:add('num, self:src:copyFrom(start, self:at:sub(#1))) }.

; A string, with awk's escapes. `\/` is a slash, which matters because a
; replacement written for `sub` often carries one.
lexer:string := { | out, c |
    out := "". self:at := self:at:inc.
    { self:here:notEquals("\"") }:whileTrue({
        self:here:equals(""):ifTrue({
            error:raise("a string is not closed") }).
        c := self:here. self:at := self:at:inc.
        c:equals("\\"):ifElse(
            { | e | e := self:here. self:at := self:at:inc.
              out := out:concat(
                  e:equals("n"):ifElse({ "\n" },
                  { e:equals("t"):ifElse({ "\t" },
                  { e:equals("r"):ifElse({ "\r" },
                  { e:equals("\\"):ifElse({ "\\" },
                  { e:equals("\""):ifElse({ "\"" },
                  { e:equals("/"):ifElse({ "/" },
                  { e:equals("a"):ifElse({ #7:asCharacter },
                  { e:equals("b"):ifElse({ #8:asCharacter },
                  { e:equals("f"):ifElse({ #12:asCharacter },
                  { e:equals("v"):ifElse({ #11:asCharacter },
                  { "\\":concat(e) }) }) }) }) }) }) }) }) }) })) },
            { out := out:concat(c) }) }).
    self:at := self:at:inc.
    self:add('str, out) }.

; A regular expression literal. `\/` is a slash and every other backslash is
; handed to re.sol untouched, which is what makes `/\.c$/` mean what it says.
lexer:regex := { | out |
    out := "". self:at := self:at:inc.
    { self:here:notEquals("/") }:whileTrue({
        self:here:equals(""):ifTrue({
            error:raise("a regular expression is not closed") }).
        self:here:equals("\\"):ifElse(
            { self:at := self:at:inc.
              self:here:equals("/"):ifElse(
                  { out := out:concat("/") },
                  { out := out:concat("\\"):concat(self:here) }).
              self:at := self:at:inc },
            { out := out:concat(self:here). self:at := self:at:inc }) }).
    self:at := self:at:inc.
    self:add('ere, out) }.

lexer:word := { | start, text |
    start := self:at.
    { | c | c := self:here.
      oneOf:value("abcdefghijklmnopqrstuvwxyz":concat(
          "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"), c)
    }:whileTrue({ self:at := self:at:inc }).
    text := self:src:copyFrom(start, self:at:sub(#1)).
    keywords:indexOf(text):notNil:ifElse(
        { self:add('keyword, text) },
        { builtins:indexOf(text):notNil:ifElse(
            { self:add('builtin, text) },
            { self:add('name, text) }) }) }.

; **A newline is a token, because in awk it ends a statement.** It is dropped
; after anything that cannot end one -- `{`, `&&`, a comma -- which is the rule
; that lets a condition be written across two lines.
lexer:run := { source | | c, matched |
    self:src := source. self:at := #1. self:tokens := array:new.
    self:regexOk := true.
    { self:at:lessOrEqual(self:src:size) }:whileTrue({
        c := self:here.
        c:equals("\n"):ifElse(
            { self:at := self:at:inc.
              self:dropNewline:ifFalse({ self:add('newline, "\n") }) },
            { (oneOf:value(" \t\r", c)):ifElse(
                { self:at := self:at:inc },
                { c:equals("#"):ifElse(
                    { { self:here:notEquals("\n"):and({
                          self:here:notEquals("") }) }:whileTrue({
                          self:at := self:at:inc }) },
                    { (c:equals("\\"):and({
                          self:peekAt(self:at:inc):equals("\n") })):ifElse(
                        { self:at := self:at:add(#2) },     ; a joined line
                        { oneOf:value("0123456789", c)
                            :or({ c:equals("."):and({
                                oneOf:value("0123456789",
                                    self:peekAt(self:at:inc)) }) })
                          :ifElse(
                            { self:number },
                            { c:equals("\""):ifElse(
                                { self:string },
                                { (c:equals("/"):and({ self:regexOk })):ifElse(
                                    { self:regex },
                                    { self:symbolOrWord }) }) }) }) }) }) }) }).
    self:add('eof, "").
    self:tokens }.

; Is the token before this newline one that a statement cannot end on?
lexer:dropNewline := { | last |
    self:tokens:size:equals(#0):ifElse({ true }, {
        last := self:tokens:at(self:tokens:size).
        last:kind:equals('newline)
            :or({ ["{", "&&", "||", ",", ";", "?", ":"]
                      :indexOf(last:text):notNil })
            :or({ ["do", "else"]:indexOf(last:text):notNil }) }) }.

lexer:symbolOrWord := { | c, found |
    c := self:here.
    (oneOf:value("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_",
        c)):ifElse(
        { self:word },
        { found := nil.
          operators:do({ op |
              (found:isNil:and({ self:at:add(op:size):sub(#1)
                      :lessOrEqual(self:src:size) })
                  :and({ self:src:copyFrom(self:at,
                      self:at:add(op:size):sub(#1)):equals(op) })):ifTrue({
                  found := op }) }).
          found:isNil:ifTrue({
              error:raise("awk: cannot read `{}`":fill([c])) }).
          self:at := self:at:add(found:size).
          self:add('op, found) }) }.

; ---------------------------------------------------------------------------
; The parser
;
; **Precedence climbing rather than a function per level, and the frame limit is
; why.** awk has twelve levels of binary precedence, and the textbook shape is
; twelve functions calling each other -- which spends three frames a level, so
; one expression costs thirty-six before it has nested at all.
; [3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels) allows
; about 254, so `((((a))))` would run out at six or seven parentheses.
;
; One loop with a precedence table costs three frames for the whole chain.
; [ideas.md](../docs/ideas.md#solas-written-in-solum--self-hosting) predicted
; exactly this for a Solum parser -- *the frame limit dictates the parser's
; shape* -- and it is the second program here to be shaped by it after
; `check_syntax.sol`.

node := object:new.
node:kind := 'num.
node:text := "".
node:n := 0.0.
node:a := nil.
node:b := nil.
node:c := nil.
node:list := nil.

mk := { kind | | n | n := node:new. n:kind := kind. n }.

; What binds how tightly. Concatenation has no operator to name it, so it sits
; in the table under a name the scanner never produces.
precedence := dictionary:of(
    "||", #2, "&&", #3, "in", #4,
    "~", #5, "!~", #5,
    "<", #6, "<=", #6, ">", #6, ">=", #6, "!=", #6, "==", #6,
    " ", #7,
    "+", #8, "-", #8,
    "*", #9, "/", #9, "%", #9,
    "^", #11).

parser := object:new.
parser:toks := nil.
parser:at := #1.
parser:funcNames := nil.

parser:peek := { self:toks:at(self:at) }.
parser:kind := { self:peek:kind }.
parser:text := { self:peek:text }.
parser:next := { | t | t := self:peek. self:at := self:at:inc. t }.
parser:isOp := { t | self:kind:equals('op):and({ self:text:equals(t) }) }.
parser:isWord := { t | self:text:equals(t):and({
    self:kind:equals('keyword):or({ self:kind:equals('name) }) }) }.
parser:eat := { t | self:isOp(t):ifElse({ self:next. true }, { false }) }.
parser:want := { t |
    self:eat(t):ifFalse({
        error:raise("awk: expected `{}` and found `{}`":fill([t, self:text])) }) }.
parser:skipNewlines := { { self:kind:equals('newline) }:whileTrue({ self:next }) }.
parser:skipTerminators := {
    { self:kind:equals('newline):or({ self:isOp(";") }) }:whileTrue({
        self:next }) }.

; Can a token begin an expression? This is what makes juxtaposition readable as
; concatenation: `a b` is two primaries in a row and `a > b` is not.
parser:startsValue := {
    self:kind:equals('num):or({ self:kind:equals('str) })
        :or({ self:kind:equals('ere) }):or({ self:kind:equals('name) })
        :or({ self:kind:equals('builtin) })
        :or({ ["$", "(", "!", "-", "+", "++", "--"]
                  :indexOf(self:text):notNil:and({
                  self:kind:equals('op) }) }) }.

; A primary: a literal, a name, a field, a call, or a bracketed expression.
;
; Written flat with a `done` flag rather than as a chain of `ifElse`, because a
; chain fourteen deep is fourteen closing brackets in a row and one of them will
; be in the wrong place. This shape also costs one frame instead of fourteen.
parser:primary := { | t, n, done |
    t := self:peek. n := nil. done := false.

    self:isOp("("):ifTrue({
        self:next.
        n := self:expr(#1).
        ; `(a, b) in arr` is the one place a bracketed list is not a group.
        self:isOp(","):ifElse(
            { n:list := array:new. n:list:add(n).
              { self:eat(",") }:whileTrue({
                  self:skipNewlines. n:list:add(self:expr(#1)) }).
              self:want(")").
              n:kind := 'group },
            { self:want(")") }).
        done := true }).

    done:ifFalse({ self:isOp("$"):ifTrue({
        self:next. n := mk:value('field). n:a := self:primary. done := true }) }).

    done:ifFalse({ self:isOp("!"):ifTrue({
        self:next. n := mk:value('not). n:a := self:unary. done := true }) }).
    done:ifFalse({ self:isOp("-"):ifTrue({
        self:next. n := mk:value('neg). n:a := self:unary. done := true }) }).
    done:ifFalse({ self:isOp("+"):ifTrue({
        self:next. n := mk:value('pos). n:a := self:unary. done := true }) }).
    done:ifFalse({ self:isOp("++"):ifTrue({
        self:next. n := mk:value('preinc). n:a := self:unary. done := true }) }).
    done:ifFalse({ self:isOp("--"):ifTrue({
        self:next. n := mk:value('predec). n:a := self:unary. done := true }) }).

    done:ifFalse({ t:kind:equals('num):ifTrue({
        self:next. n := mk:value('num). n:n := t:text:asFloat. done := true }) }).
    done:ifFalse({ t:kind:equals('str):ifTrue({
        self:next. n := mk:value('str). n:text := t:text. done := true }) }).
    done:ifFalse({ t:kind:equals('ere):ifTrue({
        self:next. n := mk:value('ere). n:text := t:text. done := true }) }).
    done:ifFalse({ t:kind:equals('builtin):ifTrue({
        n := self:builtinCall. done := true }) }).
    done:ifFalse({ t:kind:equals('name):ifTrue({
        n := self:nameOrCall. done := true }) }).
    done:ifFalse({ self:isWord("getline"):ifTrue({
        self:next. n := mk:value('getline).
        (self:kind:equals('name)):ifTrue({ n:a := self:nameOrCall }).
        done := true }) }).

    done:ifFalse({
        error:raise("awk: cannot read `{}` here"
            :fill([t:text:equals(""):ifElse({ "end of program" },
                                            { t:text })])) }).
    n }.

parser:nameOrCall := { | name, n |
    name := self:next:text.
    self:isOp("("):and({ self:funcNames:indexOf(name):notNil }):ifElse(
        { self:next.
          n := mk:value('call). n:text := name. n:list := self:arguments.
          n },
        { self:isOp("["):ifElse(
            { self:next.
              n := mk:value('index). n:text := name. n:list := array:new.
              n:list:add(self:expr(#1)).
              { self:eat(",") }:whileTrue({ n:list:add(self:expr(#1)) }).
              self:want("]").
              n },
            { n := mk:value('var). n:text := name. n }) }) }.

parser:arguments := { | out |
    out := array:new.
    self:skipNewlines.
    self:isOp(")"):ifFalse({
        out:add(self:expr(#1)).
        { self:eat(",") }:whileTrue({ self:skipNewlines. out:add(self:expr(#1)) }) }).
    self:want(")").
    out }.

parser:builtinCall := { | name, n |
    name := self:next:text.
    n := mk:value('builtin). n:text := name. n:list := array:new.
    self:isOp("("):ifElse(
        { self:next. n:list := self:arguments },
        { ; `length` alone is `length($0)`, and it is the only one written so.
          name:equals("length"):ifFalse({
              error:raise("awk: `{}` wants its arguments":fill([name])) }) }).
    n }.

; Postfix `++` and `--` bind to what is already parsed.
parser:unary := { | n |
    n := self:primary.
    { self:isOp("++"):or({ self:isOp("--") }) }:whileTrue({ | p |
        p := mk:value(self:next:text:equals("++"):ifElse({ 'postinc },
                                                        { 'postdec })).
        p:a := n. n := p }).
    n }.

; **Precedence climbing.** One loop, one table, three frames for the whole
; chain -- and concatenation is an operator whose spelling is *nothing at all*,
; so it is looked for by asking whether the next token could start a value.
;
; `^` is the one that associates to the right: `2^3^2` is 2^9, not 8^2. That is
; the whole of the difference between the two branches below.
parser:expr := { min | | left, opText, prec, right, n |
    left := self:unary.

    { | got |
      got := false.
      opText := self:isOp(""):ifElse({ "" }, { self:text }).

      ; `in` is a keyword rather than an operator, and binds like one.
      (self:isWord("in"):and({ #4:greaterOrEqual(min) })):ifTrue({
          self:next.
          n := mk:value('in). n:a := left. n:text := self:next:text.
          left := n. got := true }).

      (got:not:and({ self:kind:equals('op) })
          :and({ precedence:includes(opText) })
          :and({ precedence:at(opText):greaterOrEqual(min) })):ifTrue({
          prec := precedence:at(opText).
          self:next.
          self:skipNewlines.
          right := opText:equals("^"):ifElse(
              { self:expr(prec) },              ; right-associative
              { self:expr(prec:inc) }).
          n := mk:value('binary). n:text := opText. n:a := left. n:b := right.
          left := n. got := true }).

      ; Concatenation: no token of its own, so it is juxtaposition. `-` and `+`
      ; are excluded because `a -b` is subtraction, which is what every awk
      ; does and is the one place the grammar is genuinely ambiguous.
      (got:not:and({ #7:greaterOrEqual(min) }):and({ self:startsValue })
          :and({ self:isOp("-"):not }):and({ self:isOp("+"):not })
          :and({ self:isOp("++"):not }):and({ self:isOp("--"):not })):ifTrue({
          right := self:expr(#8).
          n := mk:value('concat). n:a := left. n:b := right.
          left := n. got := true }).
      got }:whileTrue({ nil }).

    ; The ternary, which is right-associative and lowest of all.
    (min:lessOrEqual(#1):and({ self:isOp("?") })):ifTrue({
        self:next. self:skipNewlines.
        n := mk:value('ternary). n:a := left.
        n:b := self:expr(#1).
        self:skipNewlines. self:want(":"). self:skipNewlines.
        n:c := self:expr(#1).
        left := n }).

    ; Assignment, right-associative, and lower still.
    (min:lessOrEqual(#1):and({ self:kind:equals('op) })
        :and({ ["=", "+=", "-=", "*=", "/=", "%=", "^="]
                   :indexOf(self:text):notNil })):ifTrue({
        opText := self:next:text.
        self:skipNewlines.
        n := mk:value('assign). n:text := opText. n:a := left.
        n:b := self:expr(#1).
        left := n }).
    left }.

; ---------------------------------------------------------------------------
; Statements

parser:block := { | out |
    self:want("{").
    out := mk:value('block). out:list := array:new.
    self:skipTerminators.
    { self:isOp("}"):not:and({ self:kind:equals('eof):not }) }:whileTrue({
        out:list:add(self:stmt).
        self:skipTerminators }).
    self:want("}").
    out }.

parser:simpleOrBlock := {
    self:skipNewlines.
    self:isOp("{"):ifElse({ self:block }, { self:stmt }) }.

parser:stmt := { | n, done, t |
    self:skipNewlines.
    n := nil. done := false. t := self:text.

    self:isOp("{"):ifTrue({ n := self:block. done := true }).
    self:isOp(";"):ifTrue({ self:next. n := mk:value('block).
        n:list := array:new. done := true }).

    done:ifFalse({ self:isWord("print"):ifTrue({
        self:next. n := self:printStmt('print). done := true }) }).
    done:ifFalse({ self:isWord("printf"):ifTrue({
        self:next. n := self:printStmt('printf). done := true }) }).

    done:ifFalse({ self:isWord("if"):ifTrue({
        self:next. self:want("(").
        n := mk:value('if). n:a := self:expr(#1). self:want(")").
        n:b := self:simpleOrBlock.
        self:skipTerminators.
        self:isWord("else"):ifTrue({ self:next. n:c := self:simpleOrBlock }).
        done := true }) }).

    done:ifFalse({ self:isWord("while"):ifTrue({
        self:next. self:want("(").
        n := mk:value('while). n:a := self:expr(#1). self:want(")").
        n:b := self:simpleOrBlock.
        done := true }) }).

    done:ifFalse({ self:isWord("do"):ifTrue({
        self:next.
        n := mk:value('dowhile). n:b := self:simpleOrBlock.
        self:skipTerminators.
        self:isWord("while"):ifFalse({
            error:raise("awk: `do` wants a `while`") }).
        self:next. self:want("(").
        n:a := self:expr(#1). self:want(")").
        done := true }) }).

    done:ifFalse({ self:isWord("for"):ifTrue({
        self:next. self:want("(").
        n := self:forStmt.
        done := true }) }).

    done:ifFalse({ self:isWord("break"):ifTrue({
        self:next. n := mk:value('break). done := true }) }).
    done:ifFalse({ self:isWord("continue"):ifTrue({
        self:next. n := mk:value('continue). done := true }) }).
    done:ifFalse({ self:isWord("next"):ifTrue({
        self:next. n := mk:value('next). done := true }) }).
    done:ifFalse({ self:isWord("exit"):ifTrue({
        self:next. n := mk:value('exit).
        self:startsValue:ifTrue({ n:a := self:expr(#1) }).
        done := true }) }).
    done:ifFalse({ self:isWord("return"):ifTrue({
        self:next. n := mk:value('return).
        self:startsValue:ifTrue({ n:a := self:expr(#1) }).
        done := true }) }).
    done:ifFalse({ self:isWord("delete"):ifTrue({
        self:next.
        n := mk:value('delete). n:text := self:next:text.
        self:isOp("["):ifTrue({
            self:next. n:list := array:new.
            n:list:add(self:expr(#1)).
            { self:eat(",") }:whileTrue({ n:list:add(self:expr(#1)) }).
            self:want("]") }).
        done := true }) }).

    done:ifFalse({
        n := mk:value('expression). n:a := self:expr(#1) }).
    n }.

; `for (k in a)` and `for (init; test; step)` share a bracket and nothing else,
; so the two are told apart by looking one token ahead of the name.
parser:forStmt := { | n, save |
    n := nil.
    save := self:at.
    (self:kind:equals('name)):ifTrue({
        self:next.
        self:isWord("in"):ifElse(
            { self:at := save.
              n := mk:value('forin).
              n:text := self:next:text.
              self:next.                        ; `in`
              n:c := mk:value('var). n:c:text := self:next:text.
              self:want(")").
              n:b := self:simpleOrBlock },
            { self:at := save }) }).
    n:isNil:ifTrue({
        n := mk:value('for).
        self:isOp(";"):ifFalse({ n:a := self:stmt }).
        self:want(";"). self:skipNewlines.
        self:isOp(";"):ifFalse({ n:c := self:expr(#1) }).
        self:want(";"). self:skipNewlines.
        self:isOp(")"):ifFalse({ n:list := array:new. n:list:add(self:stmt) }).
        self:want(")").
        n:b := self:simpleOrBlock }).
    n }.

; `print` and `printf`, with the redirections they can carry.
;
; **`>` after `print` is a redirection, not a comparison**, which is why
; `print a > b` writes to a file and `print (a > b)` prints a boolean. That is
; awk's rule and it surprises people; the grammar has no way round it, so the
; expression list is parsed at a precedence that stops before `>`.
parser:printStmt := { which | | n |
    n := mk:value(which). n:list := array:new.
    (self:kind:equals('newline):or({ self:isOp(";") }):or({ self:isOp("}") })
        :or({ self:isOp(">") }):or({ self:isOp(">>") })
        :or({ self:isOp("|") })):ifFalse({
        n:list:add(self:expr(#7)).
        { self:eat(",") }:whileTrue({ self:skipNewlines.
            n:list:add(self:expr(#7)) }) }).
    ; A single bracketed list is the argument list, not one group.
    (n:list:size:equals(#1):and({ n:list:at(#1):kind:equals('group) })):ifTrue({
        n:list := n:list:at(#1):list }).
    (self:isOp(">"):or({ self:isOp(">>") }):or({ self:isOp("|") })):ifTrue({
        n:text := self:next:text.
        n:c := self:expr(#7) }).
    n }.

; ---------------------------------------------------------------------------
; A program: a list of rules, and the functions they call

rule := object:new.
rule:kind := 'pattern.      ; 'begin 'end 'pattern
rule:test := nil.
rule:test2 := nil.          ; the second half of a range pattern
rule:body := nil.
rule:active := false.       ; a range that has started and not finished

parser:program := { source | | toks, rules, r |
    toks := lexer:run(source).
    self:toks := toks. self:at := #1.
    self:funcNames := array:new.
    ; One pass for the function names first, so that `f(1)` reads as a call
    ; even before `function f` has been seen -- which is legal awk, and is why
    ; they cannot be collected as the parse goes.
    self:collectFunctionNames(toks).

    rules := array:new.
    functions := dictionary:new.
    self:skipTerminators.
    { self:kind:equals('eof):not }:whileTrue({
        self:isWord("function"):or({ self:isWord("func") }):ifElse(
            { self:functionDefinition },
            { rules:add(self:rule) }).
        self:skipTerminators }).
    rules }.

parser:collectFunctionNames := { toks | | i |
    i := #1.
    { i:lessThan(toks:size) }:whileTrue({
        (["function", "func"]:indexOf(toks:at(i):text):notNil
            :and({ toks:at(i):kind:equals('keyword) })):ifTrue({
            self:funcNames:add(toks:at(i:inc):text) }).
        i := i:inc }) }.

functions := dictionary:new.

parser:functionDefinition := { | name, params, body |
    self:next.
    name := self:next:text.
    self:want("(").
    params := array:new.
    self:isOp(")"):ifFalse({
        params:add(self:next:text).
        { self:eat(",") }:whileTrue({ self:skipNewlines.
            params:add(self:next:text) }) }).
    self:want(")").
    self:skipNewlines.
    body := self:block.
    functions:atPut(name, [params, body]).
    nil }.

parser:rule := { | r |
    r := rule:new.
    self:isWord("BEGIN"):ifTrue({ self:next. r:kind := 'begin }).
    self:isWord("END"):ifTrue({ self:next. r:kind := 'end }).
    r:kind:equals('pattern):ifTrue({
        self:isOp("{"):ifFalse({
            r:test := self:expr(#1).
            self:eat(","):ifTrue({ self:skipNewlines.
                r:test2 := self:expr(#1) }) }) }).
    self:isOp("{"):ifElse(
        { r:body := self:block },
        { ; A pattern with no action prints the line, which is awk's shortest
          ; program: `/x/` is `/x/ { print }`.
          r:body := mk:value('block). r:body:list := array:new.
          r:body:list:add(mk:value('print)).
          r:body:list:at(#1):list := array:new }).
    r }.

; ---------------------------------------------------------------------------
; The state a running program has
;
; **Globals are one dictionary and arrays are another**, because awk keeps them
; apart: a name is a scalar or an array and never both, and `delete a` needs to
; find the array by name rather than through a value.

globals := dictionary:new.
arrays := dictionary:new.
locals := nil.              ; the frame of the function being run, or nil
localArrays := nil.

fields := array:new.        ; $1 upwards
record := "".               ; $0
nf := #0.

exitCode := #0.
exiting := false.
returning := false.
returnValue := nil.
looping := 'none.           ; 'break or 'continue while one is unwinding

; A name is local when the function being run declared it. Written once here
; because every read and every write has to ask.
isLocal := { name | locals:notNil:and({ locals:includes(name) }) }.

getVar := { name |
    isLocal:value(name):ifElse(
        { locals:at(name) },
        { globals:at(name, uninit:value) }) }.

setVar := { name, v |
    isLocal:value(name):ifElse(
        { locals:atPut(name, v) },
        { globals:atPut(name, v) }).
    v }.

arrayFor := { name |
    (localArrays:notNil:and({ localArrays:includes(name) })):ifElse(
        { localArrays:at(name) },
        { arrays:includes(name):ifFalse({ arrays:atPut(name, dictionary:new) }).
          arrays:at(name) }) }.

; ---------------------------------------------------------------------------
; The record, and the fields it is cut into
;
; **`FS` is three languages in one character.** A single space means *runs of
; blanks, with the ends trimmed*, which is the default and is not the same as
; splitting on one space. A single other character is that character. Anything
; longer is an extended regular expression -- which is where `re:ere` gets its
; first customer that is not this file's own tests.

splitRecord := { text, fs | | out, sep |
    out := array:new.
    fs:equals(" "):ifElse(
        { text:trim:split(" "):do({ piece |
              piece:equals(""):ifFalse({ out:add(piece) }) }).
          ; `split` gives an empty piece for every run, so the tabs have to go
          ; too -- the default FS is blanks, not spaces.
          out:size:equals(#0):ifTrue({ nil }) },
        { fs:size:equals(#1):ifElse(
            { text:split(fs):do({ piece | out:add(piece) }) },
            { | p, at, start |
              p := re:ere(fs). at := #1.
              { | found |
                found := p:findFrom(text, at).
                found:notNil:and({ p:lastEnd:greaterThan(found) })
              }:whileTrue({ | found |
                  found := p:findFrom(text, at).
                  out:add(text:copyFrom(at, found:sub(#1))).
                  at := p:lastEnd }).
              out:add(text:copyFrom(at, text:size)) }) }).
    out }.

; The default FS is a single space, which means blanks; a tab-separated file
; wants FS="\t" and gets exactly one character.
setRecord := { text |
    record := text.
    fields := splitRecord:value(text, toStr:value(getVar:value("FS"))).
    nf := fields:size.
    setVar:value("NF", num:value(nf:asFloat)).
    nil }.

; Putting $0 back together after a field was assigned, which is what OFS is for.
rebuildRecord := { | parts |
    parts := array:new.
    fields:do({ f | parts:add(f) }).
    record := parts:join(toStr:value(getVar:value("OFS"))).
    nil }.

getField := { i |
    i:equals(#0):ifElse(
        { field:value(record) },
        { i:lessOrEqual(fields:size):ifElse(
            { field:value(fields:at(i)) },
            { uninit:value }) }) }.

setField := { i, v |
    i:equals(#0):ifElse(
        { setRecord:value(toStr:value(v)) },
        { { fields:size:lessThan(i) }:whileTrue({ fields:add("") }).
          fields:atPut(i, toStr:value(v)).
          nf := fields:size.
          setVar:value("NF", num:value(nf:asFloat)).
          rebuildRecord:value }).
    v }.

; ---------------------------------------------------------------------------
; Evaluating an expression
;
; A dispatch on `kind`, written flat for the same reason the parser is: a chain
; of twenty `ifElse` costs twenty frames and this costs one.

patternCache := dictionary:new.

ereFor := { source |
    patternCache:includes(source):ifFalse({
        patternCache:atPut(source, re:ere(source)) }).
    patternCache:at(source) }.

matchesEre := { text, source | ereFor:value(source):matches(text) }.

subscript := { list | | parts |
    parts := array:new.
    list:do({ e | parts:add(toStr:value(eval:value(e))) }).
    parts:join(toStr:value(getVar:value("SUBSEP"))) }.

eval := { n | | k, v |
    k := n:kind.

    k:equals('num):ifTrue({ v := num:value(n:n) }).
    k:equals('str):ifTrue({ v := str:value(n:text) }).
    ; A bare regular expression is a test against $0, which is what makes
    ; `/x/` a pattern and `x ~ /y/` a comparison of two different shapes.
    k:equals('ere):ifTrue({
        v := num:value(matchesEre:value(record, n:text):ifElse(
            { 1.0 }, { 0.0 })) }).
    k:equals('var):ifTrue({ v := getVar:value(n:text) }).
    k:equals('field):ifTrue({
        v := getField:value(toNum:value(eval:value(n:a)):truncated) }).
    k:equals('index):ifTrue({ | a, key |
        a := arrayFor:value(n:text). key := subscript:value(n:list).
        a:includes(key):ifFalse({ a:atPut(key, uninit:value) }).
        v := a:at(key) }).
    k:equals('group):ifTrue({ v := eval:value(n:list:at(n:list:size)) }).

    k:equals('not):ifTrue({
        v := num:value(toBool:value(eval:value(n:a)):ifElse({ 0.0 },
                                                            { 1.0 })) }).
    k:equals('neg):ifTrue({ v := num:value(0.0:sub(toNum:value(eval:value(n:a)))) }).
    k:equals('pos):ifTrue({ v := num:value(toNum:value(eval:value(n:a))) }).

    k:equals('binary):ifTrue({ v := evalBinary:value(n) }).
    k:equals('concat):ifTrue({
        v := str:value(toStr:value(eval:value(n:a))
                :concat(toStr:value(eval:value(n:b)))) }).
    k:equals('ternary):ifTrue({
        v := toBool:value(eval:value(n:a)):ifElse(
            { eval:value(n:b) }, { eval:value(n:c) }) }).
    k:equals('in):ifTrue({
        v := num:value(arrayFor:value(n:text):includes(
            toStr:value(eval:value(n:a))):ifElse({ 1.0 }, { 0.0 })) }).
    k:equals('assign):ifTrue({ v := evalAssign:value(n) }).

    k:equals('preinc):ifTrue({ v := step:value(n:a, 1.0, true) }).
    k:equals('predec):ifTrue({ v := step:value(n:a, 0.0:sub(1.0), true) }).
    k:equals('postinc):ifTrue({ v := step:value(n:a, 1.0, false) }).
    k:equals('postdec):ifTrue({ v := step:value(n:a, 0.0:sub(1.0), false) }).

    k:equals('call):ifTrue({ v := callFunction:value(n:text, n:list) }).
    k:equals('builtin):ifTrue({ v := callBuiltin:value(n) }).
    k:equals('getline):ifTrue({ v := doGetline:value(n) }).

    v:isNil:ifTrue({ error:raise("awk: cannot evaluate a {}":fill([k])) }).
    v }.

; Assignment has to know *where*, not just what, and the three places a value
; can live are the three branches here.
assignTo := { target, v |
    target:kind:equals('var):ifTrue({ setVar:value(target:text, v) }).
    target:kind:equals('field):ifTrue({
        setField:value(toNum:value(eval:value(target:a)):truncated, v) }).
    target:kind:equals('index):ifTrue({
        arrayFor:value(target:text):atPut(subscript:value(target:list), v) }).
    (["var", "field", "index"]:indexOf(target:kind:asString):isNil):ifTrue({
        error:raise("awk: cannot assign to a {}":fill([target:kind])) }).
    v }.

step := { target, by, before | | old, new |
    old := toNum:value(eval:value(target)).
    new := num:value(old:add(by)).
    assignTo:value(target, new).
    before:ifElse({ new }, { num:value(old) }) }.

evalAssign := { n | | op, cur, rhs |
    op := n:text.
    op:equals("="):ifElse(
        { assignTo:value(n:a, eval:value(n:b)) },
        { cur := toNum:value(eval:value(n:a)).
          rhs := toNum:value(eval:value(n:b)).
          assignTo:value(n:a, num:value(
              op:equals("+="):ifElse({ cur:add(rhs) },
              { op:equals("-="):ifElse({ cur:sub(rhs) },
              { op:equals("*="):ifElse({ cur:mul(rhs) },
              { op:equals("/="):ifElse({ divide:value(cur, rhs) },
              { op:equals("%="):ifElse({ modulo:value(cur, rhs) },
              { cur:pow(rhs) }) }) }) }) }))) }) }.

divide := { a, b |
    b:equals(0.0):ifTrue({ error:raise("awk: division by zero") }).
    a:div(b) }.

modulo := { a, b |
    b:equals(0.0):ifTrue({ error:raise("awk: division by zero in %") }).
    a:sub(a:div(b):truncated:asFloat:mul(b)) }.

; **Written flat with a `done` flag, and this is the third place in this file
; that wanted [3.2](../docs/ROADMAP.md#32-no-non-local-return) and could not
; have it.** An evaluator dispatching on a tag is exactly the shape that wants
; to answer and leave: `~` is settled long before arithmetic is reached, and
; without an early return every later branch has to be guarded against having
; already finished. The editor's dispatcher was that entry's first customer;
; this is the second, and it wanted it once per dispatch rather than once.
evalBinary := { n | | op, a, b, c, v |
    op := n:text. v := nil.

    ; `~` and `!~` take a pattern on the right, which may be a literal or any
    ; expression that answers one.
    (op:equals("~"):or({ op:equals("!~") })):ifTrue({ | text, pat, hit |
        text := toStr:value(eval:value(n:a)).
        pat := n:b:kind:equals('ere):ifElse({ n:b:text },
                                            { toStr:value(eval:value(n:b)) }).
        hit := matchesEre:value(text, pat).
        op:equals("!~"):ifTrue({ hit := hit:not }).
        v := num:value(hit:ifElse({ 1.0 }, { 0.0 })) }).

    ; **Both of these stop early**, which is awk's rule and matters: `x != 0 &&
    ; 1/x > 2` must not divide when x is nought.
    (v:isNil:and({ op:equals("&&") })):ifTrue({
        v := num:value(toBool:value(eval:value(n:a))
            :and({ toBool:value(eval:value(n:b)) }):ifElse({ 1.0 },
                                                           { 0.0 })) }).
    (v:isNil:and({ op:equals("||") })):ifTrue({
        v := num:value(toBool:value(eval:value(n:a))
            :or({ toBool:value(eval:value(n:b)) }):ifElse({ 1.0 },
                                                          { 0.0 })) }).

    v:isNil:ifTrue({
        a := eval:value(n:a).
        b := eval:value(n:b).

        (["<", "<=", ">", ">=", "==", "!="]:indexOf(op):notNil):ifElse({
            c := compare:value(a, b).
            v := num:value((op:equals("<"):ifElse({ c:lessThan(#0) },
                { op:equals("<="):ifElse({ c:lessOrEqual(#0) },
                { op:equals(">"):ifElse({ c:greaterThan(#0) },
                { op:equals(">="):ifElse({ c:greaterOrEqual(#0) },
                { op:equals("=="):ifElse({ c:equals(#0) },
                { c:notEquals(#0) }) }) }) }) })):ifElse({ 1.0 }, { 0.0 })) },

        { v := num:value(
            op:equals("+"):ifElse({ toNum:value(a):add(toNum:value(b)) },
            { op:equals("-"):ifElse({ toNum:value(a):sub(toNum:value(b)) },
            { op:equals("*"):ifElse({ toNum:value(a):mul(toNum:value(b)) },
            { op:equals("/"):ifElse({
                  divide:value(toNum:value(a), toNum:value(b)) },
            { op:equals("%"):ifElse({
                  modulo:value(toNum:value(a), toNum:value(b)) },
            { toNum:value(a):pow(toNum:value(b)) }) }) }) }) })) }) }).
    v }.

; ---------------------------------------------------------------------------
; Running a statement
;
; `next`, `exit`, `break`, `continue` and `return` all unwind, and none of them
; can be a non-local return -- so each sets a flag and every loop below asks.
; That is five flags where one mechanism would do, and it is the clearest case
; [3.2](../docs/ROADMAP.md#32-no-non-local-return) has had here.

nexting := false.

stopped := { exiting:or({ returning }):or({ nexting })
    :or({ looping:notEquals('none) }) }.

exec := { n | | k |
    k := n:kind.

    k:equals('block):ifTrue({
        n:list:do({ each | stopped:value:ifFalse({ exec:value(each) }) }) }).
    k:equals('expression):ifTrue({ eval:value(n:a) }).
    k:equals('print):ifTrue({ doPrint:value(n) }).
    k:equals('printf):ifTrue({ doPrintf:value(n) }).

    k:equals('if):ifTrue({
        toBool:value(eval:value(n:a)):ifElse(
            { exec:value(n:b) },
            { n:c:notNil:ifTrue({ exec:value(n:c) }) }) }).

    k:equals('while):ifTrue({
        { stopped:value:not:and({ toBool:value(eval:value(n:a)) })
        }:whileTrue({
            exec:value(n:b).
            looping:equals('continue):ifTrue({ looping := 'none }).
            looping:equals('break):ifTrue({ looping := 'stop }) }).
        looping:equals('stop):ifTrue({ looping := 'none }) }).

    k:equals('dowhile):ifTrue({ | go |
        go := true.
        { go }:whileTrue({
            exec:value(n:b).
            looping:equals('continue):ifTrue({ looping := 'none }).
            looping:equals('break):ifTrue({ looping := 'stop }).
            go := stopped:value:not:and({ toBool:value(eval:value(n:a)) }) }).
        looping:equals('stop):ifTrue({ looping := 'none }) }).

    k:equals('for):ifTrue({
        n:a:notNil:ifTrue({ exec:value(n:a) }).
        { stopped:value:not:and({
            n:c:isNil:or({ toBool:value(eval:value(n:c)) }) }) }:whileTrue({
            exec:value(n:b).
            looping:equals('continue):ifTrue({ looping := 'none }).
            looping:equals('break):ifTrue({ looping := 'stop }).
            looping:equals('stop):ifFalse({
                n:list:notNil:ifTrue({ exec:value(n:list:at(#1)) }) }) }).
        looping:equals('stop):ifTrue({ looping := 'none }) }).

    ; **The keys are taken first**, because the body may add to the array or
    ; delete from it and walking a dictionary that is changing underneath is
    ; not a thing awk promises either way.
    k:equals('forin):ifTrue({ | keys |
        keys := arrayFor:value(n:c:text):keys.
        keys:do({ key |
            looping:equals('stop):ifFalse({ stopped:value:ifFalse({
                setVar:value(n:text, field:value(key)).
                exec:value(n:b).
                looping:equals('continue):ifTrue({ looping := 'none }).
                looping:equals('break):ifTrue({ looping := 'stop }) }) }) }).
        looping:equals('stop):ifTrue({ looping := 'none }) }).

    k:equals('break):ifTrue({ looping := 'break }).
    k:equals('continue):ifTrue({ looping := 'continue }).
    k:equals('next):ifTrue({ nexting := true }).
    k:equals('exit):ifTrue({
        n:a:notNil:ifTrue({
            exitCode := toNum:value(eval:value(n:a)):truncated }).
        exiting := true }).
    k:equals('return):ifTrue({
        returnValue := n:a:isNil:ifElse({ uninit:value },
                                        { eval:value(n:a) }).
        returning := true }).
    k:equals('delete):ifTrue({
        n:list:isNil:ifElse(
            { arrayFor:value(n:text):keys:do({ key |
                  arrayFor:value(n:text):remove(key) }) },
            { | key | key := subscript:value(n:list).
              arrayFor:value(n:text):includes(key):ifTrue({
                  arrayFor:value(n:text):remove(key) }) }) }).
    nil }.

; ---------------------------------------------------------------------------
; Output

outputs := dictionary:new.      ; open files and pipes, by name

writeTo := { where, how, text |
    where:isNil:ifElse(
        { system:write(text) },
        { how:equals("|"):ifElse(
            { | key | key := "|":concat(where).
              outputs:includes(key):ifFalse({ outputs:atPut(key, array:new) }).
              outputs:at(key):add(text) },
            { how:equals(">>"):and({ outputs:includes(where) }):not
                  :and({ how:equals(">") }):ifTrue({
                  system:writeFile(where, "").
                  outputs:atPut(where, true) }).
              system:appendFile(where, text) }) }) }.

destination := { n |
    n:c:isNil:ifElse({ nil }, { toStr:value(eval:value(n:c)) }) }.

doPrint := { n | | parts, text |
    parts := array:new.
    n:list:size:equals(#0):ifElse(
        { parts:add(record) },
        { n:list:do({ e | parts:add(toStr:value(eval:value(e))) }) }).
    text := parts:join(toStr:value(getVar:value("OFS")))
        :concat(toStr:value(getVar:value("ORS"))).
    writeTo:value(destination:value(n), n:text, text).
    nil }.

doPrintf := { n | | args, text |
    n:list:size:equals(#0):ifTrue({
        error:raise("awk: printf wants a format") }).
    args := array:new.
    n:list:do({ e | args:add(eval:value(e)) }).
    text := formatted:value(toStr:value(args:at(#1)), args, #2).
    writeTo:value(destination:value(n), n:text, text).
    nil }.

; **printf, which is the third thing the scoping predicted awk would want.**
; `fill` takes `{}` and no conversion at all -- deliberately, so that nothing in
; its spec starts looking like a format language -- and `asString(spec)` gives
; width, fill and fixed decimals. Neither is `%c`, `%o`, `%x`, `%e` or `%g`, and
; a `*` width is in none of them. So it is written here, which is where a format
; belongs: the language declined to grow one and this is a program that wants
; one, which is the trade working rather than a gap.
formatted := { fmt, args, from | | out, i, argAt, c |
    out := "". i := #1. argAt := from.
    { i:lessOrEqual(fmt:size) }:whileTrue({
        c := fmt:at(i).
        c:notEquals("%"):ifElse(
            { out := out:concat(c). i := i:inc },
            { i:inc:greaterThan(fmt:size):ifElse(
                { out := out:concat("%"). i := i:inc },
                { fmt:at(i:inc):equals("%"):ifElse(
                    { out := out:concat("%"). i := i:add(#2) },
                    { | spec |
                      spec := oneConversion:value(fmt, i, args, argAt).
                      out := out:concat(spec:at(#1)).
                      i := spec:at(#2).
                      argAt := spec:at(#3) }) }) }) }).
    out }.

; One `%...` conversion: flags, width, precision, letter. Answers the text, the
; position after it, and the next argument to take.
oneConversion := { fmt, start, args, argAt | | i, flags, width, prec, letter,
                   take, v, text, at |
    i := start:inc. flags := "". width := nil. prec := nil. at := argAt.

    { oneOf:value("-+ 0#", fmt:at(i)) }:whileTrue({
        flags := flags:concat(fmt:at(i)). i := i:inc }).

    fmt:at(i):equals("*"):ifElse(
        { width := toNum:value(args:at(at)):truncated. at := at:inc. i := i:inc },
        { | d | d := "".
          { oneOf:value("0123456789", fmt:at(i)) }:whileTrue({
              d := d:concat(fmt:at(i)). i := i:inc }).
          d:equals(""):ifFalse({ width := d:asInteger }) }).

    fmt:at(i):equals("."):ifTrue({
        i := i:inc.
        fmt:at(i):equals("*"):ifElse(
            { prec := toNum:value(args:at(at)):truncated. at := at:inc.
              i := i:inc },
            { | d | d := "".
              { oneOf:value("0123456789", fmt:at(i)) }:whileTrue({
                  d := d:concat(fmt:at(i)). i := i:inc }).
              prec := d:equals(""):ifElse({ #0 }, { d:asInteger }) }) }).

    letter := fmt:at(i). i := i:inc.
    take := at:lessOrEqual(args:size):ifElse({ args:at(at) }, { uninit:value }).
    at := at:inc.

    text := conversion:value(letter, take, prec).
    [padded:value(text, flags, width), i, at] }.

conversion := { letter, v, prec | | x |
    letter:equals("d"):or({ letter:equals("i") }):ifElse(
        { toNum:value(v):truncated:asString },

    { letter:equals("s"):ifElse(
        { | t | t := toStr:value(v).
          prec:isNil:ifElse({ t },
              { t:copyFrom(#1, prec:lessThan(t:size):ifElse({ prec },
                                                            { t:size })) }) },

    { letter:equals("c"):ifElse(
        { | t | t := toStr:value(v).
          v:kind:equals('num):ifElse(
              { toNum:value(v):truncated:asCharacter },
              { t:equals(""):ifElse({ "" }, { t:at(#1) }) }) },

    { letter:equals("f"):or({ letter:equals("F") }):ifElse(
        { toNum:value(v):asString(".":concat(
            prec:isNil:ifElse({ #6 }, { prec }):asString)) },

    { letter:equals("e"):or({ letter:equals("E") }):ifElse(
        { | t | t := scientific:value(toNum:value(v),
              prec:isNil:ifElse({ #6 }, { prec })).
          letter:equals("E"):ifElse({ t:asUppercase }, { t }) },

    { letter:equals("g"):or({ letter:equals("G") }):ifElse(
        { | t | t := sixG:value(toNum:value(v),
              prec:isNil:ifElse({ #6 }, { prec:equals(#0):ifElse({ #1 },
                                                                 { prec }) })).
          letter:equals("G"):ifElse({ t:asUppercase }, { t }) },

    { letter:equals("o"):ifElse(
        { toNum:value(v):truncated:asBase(#8) },

    { letter:equals("x"):or({ letter:equals("X") }):ifElse(
        { | t | t := toNum:value(v):truncated:asBase(#16).
          letter:equals("X"):ifElse({ t:asUppercase }, { t }) },

    { letter:equals("u"):ifElse(
        { toNum:value(v):truncated:asString },
        { error:raise("awk: `%{}` is not a conversion":fill([letter])) })
    }) }) }) }) }) }) }) }) }.

; `%e`: one digit before the point, `prec` after it, and a two-digit exponent.
scientific := { x, prec | | e, scaled, out |
    x:equals(0.0):ifElse(
        { out := 0.0:asString(".":concat(prec:asString)).
          out:concat("e+00") },
        { e := x:abs:log:div(10.0:log):floor.
          (10.0:pow(e:asFloat):greaterThan(x:abs)):ifTrue({ e := e:sub(#1) }).
          (10.0:pow(e:inc:asFloat):lessOrEqual(x:abs)):ifTrue({ e := e:inc }).
          scaled := x:div(10.0:pow(e:asFloat)).
          out := scaled:asString(".":concat(prec:asString)).
          ; Rounding can carry: 9.99 to two places is 10.0, which is a digit too
          ; many before the point and one too few in the exponent.
          (out:indexOf("10."):equals(#1):or({
              out:indexOf("-10."):equals(#1) })):ifTrue({
              e := e:inc.
              scaled := x:div(10.0:pow(e:asFloat)).
              out := scaled:asString(".":concat(prec:asString)) }).
          out:concat("e"):concat(e:lessThan(#0):ifElse({ "-" }, { "+" }))
             :concat(e:abs:asString("02")) }) }.

; Width and the flags that decide which side the padding goes.
padded := { text, flags, width | | out, pad |
    out := text.
    (flags:indexOf("+"):notNil:and({ out:size:greaterThan(#0) })
        :and({ "-0123456789":indexOf(out:at(#1)):notNil })
        :and({ out:at(#1):notEquals("-") })):ifTrue({
        out := "+":concat(out) }).
    width:isNil:ifElse({ out }, {
        out:size:greaterOrEqual(width):ifElse({ out }, {
            pad := "".
            [#1, width:sub(out:size)]:loop({ i |
                pad := pad:concat(
                    flags:indexOf("0"):notNil:and({
                        flags:indexOf("-"):isNil }):ifElse({ "0" },
                                                           { " " })) }).
            flags:indexOf("-"):notNil:ifElse(
                { out:concat(pad) },
                { ; A zero pad goes after the sign, not before it.
                  (flags:indexOf("0"):notNil:and({ out:size:greaterThan(#0) })
                      :and({ "+-":indexOf(out:at(#1)):notNil })):ifElse(
                      { out:at(#1):concat(pad)
                            :concat(out:copyFrom(#2, out:size)) },
                      { pad:concat(out) }) }) }) }) }.

; ---------------------------------------------------------------------------
; The built-in functions

callBuiltin := { n | | name, a, v |
    name := n:text. a := n:list. v := nil.

    name:equals("length"):ifTrue({
        v := num:value(a:size:equals(#0):ifElse(
            { record:size:asFloat },
            { | first |
              first := a:at(#1).
              (first:kind:equals('var):and({
                  arrays:includes(first:text) })):ifElse(
                  { arrays:at(first:text):size:asFloat },
                  { toStr:value(eval:value(first)):size:asFloat }) })) }).

    name:equals("substr"):ifTrue({ | t, from, len, stop |
        t := toStr:value(eval:value(a:at(#1))).
        from := toNum:value(eval:value(a:at(#2))):rounded.
        stop := a:size:greaterOrEqual(#3):ifElse(
            { from:add(toNum:value(eval:value(a:at(#3))):rounded):sub(#1) },
            { t:size }).
        from:lessThan(#1):ifTrue({ from := #1 }).
        stop:greaterThan(t:size):ifTrue({ stop := t:size }).
        v := str:value(stop:lessThan(from):ifElse({ "" },
                                                  { t:copyFrom(from, stop) })) }).

    name:equals("index"):ifTrue({ | t, w |
        t := toStr:value(eval:value(a:at(#1))).
        w := toStr:value(eval:value(a:at(#2))).
        v := num:value(w:equals(""):ifElse({ 0.0 },
            { | at | at := t:indexOf(w).
              at:isNil:ifElse({ 0.0 }, { at:asFloat }) })) }).

    name:equals("split"):ifTrue({ | t, arr, fs, parts |
        t := toStr:value(eval:value(a:at(#1))).
        arr := arrayFor:value(a:at(#2):text).
        arr:keys:do({ key | arr:remove(key) }).
        fs := a:size:greaterOrEqual(#3):ifElse(
            { a:at(#3):kind:equals('ere):ifElse({ a:at(#3):text },
                  { toStr:value(eval:value(a:at(#3))) }) },
            { toStr:value(getVar:value("FS")) }).
        parts := t:equals(""):ifElse({ array:new },
                                     { splitRecord:value(t, fs) }).
        [#1, parts:size]:loop({ i |
            arr:atPut(i:asString, field:value(parts:at(i))) }).
        v := num:value(parts:size:asFloat) }).

    name:equals("sub"):ifTrue({ v := substitute:value(a, false) }).
    name:equals("gsub"):ifTrue({ v := substitute:value(a, true) }).

    name:equals("match"):ifTrue({ | t, p, at |
        t := toStr:value(eval:value(a:at(#1))).
        p := ereFor:value(a:at(#2):kind:equals('ere):ifElse({ a:at(#2):text },
            { toStr:value(eval:value(a:at(#2))) })).
        at := p:find(t).
        at:isNil:ifElse(
            { setVar:value("RSTART", num:value(0.0)).
              setVar:value("RLENGTH", num:value(0.0:sub(1.0))).
              v := num:value(0.0) },
            { setVar:value("RSTART", num:value(at:asFloat)).
              setVar:value("RLENGTH",
                  num:value(p:lastEnd:sub(at):asFloat)).
              v := num:value(at:asFloat) }) }).

    name:equals("sprintf"):ifTrue({ | args |
        args := array:new.
        a:do({ e | args:add(eval:value(e)) }).
        v := str:value(formatted:value(toStr:value(args:at(#1)), args, #2)) }).

    name:equals("sin"):ifTrue({ v := num:value(toNum:value(eval:value(a:at(#1))):sin) }).
    name:equals("cos"):ifTrue({ v := num:value(toNum:value(eval:value(a:at(#1))):cos) }).
    name:equals("exp"):ifTrue({ v := num:value(toNum:value(eval:value(a:at(#1))):exp) }).
    name:equals("log"):ifTrue({ v := num:value(toNum:value(eval:value(a:at(#1))):log) }).
    name:equals("sqrt"):ifTrue({ v := num:value(toNum:value(eval:value(a:at(#1))):sqrt) }).
    name:equals("int"):ifTrue({
        v := num:value(toNum:value(eval:value(a:at(#1))):truncated:asFloat) }).
    name:equals("atan2"):ifTrue({
        v := num:value(float:atan2(toNum:value(eval:value(a:at(#1))),
                                   toNum:value(eval:value(a:at(#2))))) }).

    name:equals("rand"):ifTrue({ v := num:value(generator:fraction) }).
    name:equals("srand"):ifTrue({ | old |
        old := lastSeed.
        lastSeed := a:size:equals(#0):ifElse(
            { system:time:secondsSince(epoch):truncated },
            { toNum:value(eval:value(a:at(#1))):truncated }).
        generator := random:new(lastSeed).
        v := num:value(old:asFloat) }).

    name:equals("tolower"):ifTrue({
        v := str:value(toStr:value(eval:value(a:at(#1))):asLowercase) }).
    name:equals("toupper"):ifTrue({
        v := str:value(toStr:value(eval:value(a:at(#1))):asUppercase) }).

    name:equals("system"):ifTrue({ | cmd |
        cmd := toStr:value(eval:value(a:at(#1))).
        flush:value.
        v := num:value(system:run(["/bin/sh", "-c", cmd]):asFloat) }).

    name:equals("close"):ifTrue({ v := num:value(closeStream:value(
        toStr:value(eval:value(a:at(#1))))) }).

    v:isNil:ifTrue({ error:raise("awk: `{}` is not written yet":fill([name])) }).
    v }.

lastSeed := #0.
generator := random:new(#0).
epoch := "1970-01-01T00:00:00Z":asTime.

; `sub` and `gsub` share everything but a boolean, and `&` in the replacement is
; the matched text -- which lib/re.sol already does, so this is the one built-in
; that is mostly a message send.
substitute := { a, all | | pat, repl, target, before, result |
    pat := ereFor:value(a:at(#1):kind:equals('ere):ifElse({ a:at(#1):text },
        { toStr:value(eval:value(a:at(#1))) })).
    repl := toStr:value(eval:value(a:at(#2))).
    target := a:size:greaterOrEqual(#3):ifElse({ a:at(#3) },
        { | f | f := mk:value('field). f:a := mk:value('num). f:a:n := 0.0. f }).
    before := toStr:value(eval:value(target)).
    result := pat:substitutionIn(before, repl, all).
    result:at("count"):greaterThan(#0):ifTrue({
        assignTo:value(target, str:value(result:at("text"))) }).
    num:value(result:at("count"):asFloat) }.

; ---------------------------------------------------------------------------
; User functions
;
; **Parameters are the only locals awk has**, and the extra ones are how a
; function declares a local variable -- `function f(a, b,   i, j)` takes two
; arguments and has two locals, told apart by nothing but a wider gap. That is
; not a shape worth defending and it is what the language is.
;
; An array passed as an argument is passed **by reference** and a scalar by
; value, which is decided by what the caller's name already is.

callFunction := { name, argNodes | | def, params, body, saveL, saveA, i, v |
    functions:includes(name):ifFalse({
        error:raise("awk: no function `{}`":fill([name])) }).
    def := functions:at(name).
    params := def:at(#1). body := def:at(#2).

    saveL := locals. saveA := localArrays.
    locals := dictionary:new. localArrays := dictionary:new.

    i := #1.
    { i:lessOrEqual(params:size) }:whileTrue({ | argNode |
        argNode := i:lessOrEqual(argNodes:size):ifElse({ argNodes:at(i) },
                                                       { nil }).
        (argNode:notNil:and({ argNode:kind:equals('var) })
            :and({ arrays:includes(argNode:text)
                :or({ saveA:notNil:and({ saveA:includes(argNode:text) }) }) })
        ):ifElse(
            { ; an array, by reference
              localArrays:atPut(params:at(i),
                  (saveA:notNil:and({ saveA:includes(argNode:text) })):ifElse(
                      { saveA:at(argNode:text) },
                      { arrays:at(argNode:text) })) },
            { | val |
              val := argNode:isNil:ifElse({ uninit:value }, {
                  ; The argument is evaluated in the *caller's* frame, so the
                  ; new one is put in place only after all of them are read.
                  locals:isNil:ifElse({ eval:value(argNode) }, {
                      | l, la, got |
                      l := locals. la := localArrays.
                      locals := saveL. localArrays := saveA.
                      got := eval:value(argNode).
                      locals := l. localArrays := la.
                      got }) }).
              locals:atPut(params:at(i), val) }).
        i := i:inc }).

    returning := false. returnValue := uninit:value.
    exec:value(body).
    v := returnValue.
    returning := false.

    locals := saveL. localArrays := saveA.
    v }.

; ---------------------------------------------------------------------------
; Reading the input
;
; **A record is a line and `RS` is not honoured beyond that**, which is stated
; rather than hidden: POSIX allows RS to be any single character and an empty RS
; to mean paragraph mode, and neither is here. The reason is that
; `system:readFile` answers a whole file and there is no line-at-a-time read --
; the same limitation `sed` records, and the same one that made `tail` read
; ranges by hand.

; **There is no read-the-whole-of-standard-input**, so it is `readLine` until
; nil. That is the same shape `sed` records and the reason both read a file
; whole: a stream has no size to ask for, and one line at a time through a
; message is the only way in.
standardInput := { | out, line |
    out := "".
    { line := system:readLine. line:notNil }:whileTrue({
        out := out:concat(line):concat("\n") }).
    out }.

inputLines := array:new.
inputAt := #1.
inputFiles := nil.
inputFileAt := #1.

pendingText := nil.

loadNextFile := { | got |
    got := false.
    { got:not:and({ inputFileAt:lessOrEqual(inputFiles:size) }) }:whileTrue({
        | name |
        name := inputFiles:at(inputFileAt).
        inputFileAt := inputFileAt:inc.
        setVar:value("FILENAME", str:value(name)).
        inputLines := linesOf:value(name:equals("-"):ifElse(
            { standardInput:value }, { system:readFile(name) })).
        inputAt := #1.
        got := inputLines:size:greaterThan(#0) }).
    got }.

; A trailing newline ends the last record rather than starting an empty one,
; which is the difference between `wc -l` and what awk sees.
linesOf := { text | | parts |
    text:equals(""):ifElse({ array:new }, {
        parts := text:split("\n").
        (parts:size:greaterThan(#0)
            :and({ parts:at(parts:size):equals("") })):ifTrue({
            parts := parts:copyFrom(#1, parts:size:sub(#1)) }).
        parts }) }.

nextRecord := { | got |
    got := nil.
    { got:isNil:and({ inputAt:lessOrEqual(inputLines:size)
        :or({ inputFileAt:lessOrEqual(inputFiles:size) }) }) }:whileTrue({
        inputAt:greaterThan(inputLines:size):ifElse(
            { loadNextFile:value },
            { got := inputLines:at(inputAt). inputAt := inputAt:inc }) }).
    got }.

doGetline := { n | | line |
    line := nextRecord:value.
    line:isNil:ifElse(
        { num:value(0.0) },
        { setVar:value("NR", num:value(
              toNum:value(getVar:value("NR")):add(1.0))).
          n:a:isNil:ifElse(
              { setRecord:value(line).
                setVar:value("FNR", num:value(
                    toNum:value(getVar:value("FNR")):add(1.0))) },
              { assignTo:value(n:a, field:value(line)) }).
          num:value(1.0) }) }.

; ---------------------------------------------------------------------------
; Running a program over the input

flush := {
    outputs:keysAndValuesDo({ key, v |
        (key:size:greaterThan(#0):and({ key:at(#1):equals("|") })):ifTrue({
            system:run(["/bin/sh", "-c", key:copyFrom(#2, key:size)],
                       dictionary:of("input", v:join(""))).
            outputs:atPut(key, array:new) }) }).
    nil }.

closeStream := { name | | key |
    key := "|":concat(name).
    outputs:includes(key):ifElse(
        { system:run(["/bin/sh", "-c", name],
                     dictionary:of("input", outputs:at(key):join(""))).
          outputs:remove(key). #0 },
        { outputs:includes(name):ifElse({ outputs:remove(name). #0 },
                                        { #0:sub(#1) }) }) }.

setDefaults := {
    setVar:value("FS", str:value(" ")).
    setVar:value("OFS", str:value(" ")).
    setVar:value("ORS", str:value("\n")).
    setVar:value("RS", str:value("\n")).
    setVar:value("NR", num:value(0.0)).
    setVar:value("FNR", num:value(0.0)).
    setVar:value("NF", num:value(0.0)).
    setVar:value("SUBSEP", str:value(#28:asCharacter)).
    setVar:value("RSTART", num:value(0.0)).
    setVar:value("RLENGTH", num:value(0.0:sub(1.0))).
    setVar:value("CONVFMT", str:value("%.6g")).
    setVar:value("OFMT", str:value("%.6g")).
    setVar:value("FILENAME", str:value("")).
    nil }.

matchesRule := { r |
    r:test:isNil:ifElse({ true }, {
        r:test2:isNil:ifElse(
            { toBool:value(eval:value(r:test)) },
            { ; A range pattern: on at the first, off at the second, and both
              ; can be the same line.
              r:active:ifElse(
                  { toBool:value(eval:value(r:test2)):ifTrue({
                        r:active := false }).
                    true },
                  { toBool:value(eval:value(r:test)):ifElse(
                        { r:active := toBool:value(
                              eval:value(r:test2)):not.
                          true },
                        { false }) }) }) }) }.

; **`setDefaults` is the caller's**, not this one's. It was here, and it ran
; *after* `-F` had been read on the command line -- so `awk -F: '{print $2}'`
; put the separator back to a blank before the first record was cut. Found by
; the one flag in three that had input to act on.
run := { rules | | began |
    rules:do({ r | (r:kind:equals('begin):and({ exiting:not })):ifTrue({
        exec:value(r:body) }) }).

    ; The main loop is skipped when there is nothing but BEGIN, which is what
    ; makes `awk 'BEGIN { print 1 }'` not wait on standard input.
    began := false.
    rules:do({ r | r:kind:equals('pattern):or({ r:kind:equals('end) }):ifTrue({
        began := true }) }).

    (began:and({ exiting:not })):ifTrue({ | line |
        { exiting:not:and({ | got |
            got := nextRecord:value.
            pendingText := got.
            got:notNil }) }:whileTrue({
            setRecord:value(pendingText).
            setVar:value("NR", num:value(
                toNum:value(getVar:value("NR")):add(1.0))).
            setVar:value("FNR", num:value(
                toNum:value(getVar:value("FNR")):add(1.0))).
            nexting := false.
            rules:do({ r |
                (r:kind:equals('pattern):and({ exiting:not })
                    :and({ nexting:not })):ifTrue({
                    matchesRule:value(r):ifTrue({ exec:value(r:body) }) }) }) }) }).

    exiting := false.
    rules:do({ r | (r:kind:equals('end):and({ exiting:not })):ifTrue({
        exec:value(r:body) }) }).

    flush:value.
    exitCode }.

; ---------------------------------------------------------------------------
; The command line
;
;   awk [-F fs] [-v name=value]... 'program' [file...]
;   awk [-F fs] [-v name=value]... -f progfile [file...]

usage := "usage: awk [-F fs] [-v name=value] 'program' [file...]".

main := { | args, i, source, files, fs, assignments, done, rules |
    args := system:arguments.
    args:size:equals(#0):ifTrue({ demonstrate:value. system:exit(#0) }).

    i := #1. source := nil. files := array:new. fs := nil.
    assignments := array:new. done := false.

    { done:not:and({ i:lessOrEqual(args:size) }) }:whileTrue({ | a |
        a := args:at(i).
        ; **A flag and its value may be joined**, which POSIX allows and every
        ; awk script in the world writes: `-F:` is far commoner than `-F :`.
        a:equals("-F"):ifElse(
            { fs := args:at(i:inc). i := i:add(#2) },
        { (a:size:greaterThan(#2):and({ a:copyFrom(#1, #2):equals("-F") })):ifElse(
            { fs := a:copyFrom(#3, a:size). i := i:inc },
        { a:equals("-v"):ifElse(
            { assignments:add(args:at(i:inc)). i := i:add(#2) },
        { (a:size:greaterThan(#2):and({ a:copyFrom(#1, #2):equals("-v") })):ifElse(
            { assignments:add(a:copyFrom(#3, a:size)). i := i:inc },
        { a:equals("-f"):ifElse(
            { source := system:readFile(args:at(i:inc)). i := i:add(#2) },
        { (a:size:greaterThan(#2):and({ a:copyFrom(#1, #2):equals("-f") })):ifElse(
            { source := system:readFile(a:copyFrom(#3, a:size)). i := i:inc },
        { a:equals("--"):ifElse(
            { i := i:inc. done := true },
        { (a:size:greaterThan(#1):and({ a:at(#1):equals("-") })
            :and({ a:notEquals("-") })):ifElse(
            { system:writeError(usage:concat("\n")). system:exit(#2) },
            { done := true }) }) }) }) }) }) }) }) }).

    source:isNil:ifTrue({
        i:greaterThan(args:size):ifTrue({
            system:writeError(usage:concat("\n")). system:exit(#2) }).
        source := args:at(i). i := i:inc }).

    { i:lessOrEqual(args:size) }:whileTrue({ files:add(args:at(i)). i := i:inc }).

    rules := parser:program(source).
    setDefaults:value.
    fs:notNil:ifTrue({ setVar:value("FS", str:value(fs)) }).
    assignments:do({ each | | at |
        at := each:indexOf("=").
        at:notNil:ifTrue({
            setVar:value(each:copyFrom(#1, at:sub(#1)),
                field:value(each:copyFrom(at:inc, each:size))) }) }).

    inputFiles := files:size:equals(#0):ifElse({ ["-"] }, { files }).
    inputFileAt := #1. inputLines := array:new. inputAt := #1.

    system:exit(run:value(rules)) }.

; ---------------------------------------------------------------------------
; What it does with no arguments

demonstrate := { | data, path |
    path := "build/awk-demo.txt".
    system:makeDirectory("build").
    data := "alice   42  ok\nbob     17  warn\ncarol   93  ok\ndave     5  error\n".
    system:writeFile(path, data).

    "":display.
    "awk -- the pattern-action language.":display.
    "":display.
    "  {} holds:":fill([path]):display.
    "":display.
    system:write(data).

    ["{ print $1 }",
     "$2 > 40 { print $1, $2 }",
     "/warn|error/ { n++ } END { print n, \"to look at\" }",
     "{ total += $2 } END { printf \"%-8s %6.2f\\n\", \"mean\", total / NR }"
    ]:do({ prog |
        "":display.
        "  awk '{}'":fill([prog]):display.
        "":display.
        inputFiles := [path]. inputFileAt := #1.
        inputLines := array:new. inputAt := #1.
        globals := dictionary:new. arrays := dictionary:new.
        exiting := false. exitCode := #0.
        setDefaults:value.
        run:value(parser:program(prog)) }).
    "":display.
    nil }.

main:value.
