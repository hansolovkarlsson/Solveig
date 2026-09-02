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
