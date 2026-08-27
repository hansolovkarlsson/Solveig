; pascal.sol -- ISO 7185 Pascal compiled to bytecode. Stage 1.
;
; Run with:  ./bin/solas programs/pascal.sol && ./bin/solvm programs/pascal.sob
; On a file:  ./bin/solvm programs/pascal.sob prog.pas [prog.sob]
;
; The fifteenth program here, and the second that compiles another language.
; Where [sola.sol](sola.sol) had to define its dialect first -- there being no
; standard for a QBasic -- this one has [ISO 7185](../docs/PASCAL.md) and a
; **real compiler to disagree with**: `fpc -Miso`, which
; [programs/pas/oracle.sh](pas/oracle.sh) runs beside this one.
;
; ---------------------------------------------------------------------------
; What stage 1 is
;
;   program       the heading, with or without its file list
;   var           integer, real, char and boolean
;   :=            with the assignment compatibility the standard gives
;   expressions   + - * / div mod, unary -, the six comparisons, and/or/not
;   write         write and writeln, with `:width` and `:width:places`
;   begin end     compound statements
;   if            with and without else
;   while         do
;
; Everything else is a stage, and [PASCAL.md](../docs/PASCAL.md) says which.
;
; ---------------------------------------------------------------------------
; Why a type checker is not optional here
;
; **Solum refuses `#1:add(1.0)`.** There is no implicit conversion anywhere in
; the machine, so a compiler for a language that *has* one cannot avoid knowing
; the type of every expression it emits. Pascal's rule is that an integer
; becomes a real where a real is wanted and never the other way, and `/` is
; always real -- so `i / 2` needs an `asFloat` on `i` and `i div 2` needs none,
; and the compiler has to have decided which before it writes a byte.
;
; That is the difference between this and `sola.sol`, whose header says
; *everything a SolaBasic program computes is a Double*. One numeric type needs
; no analysis. Two need all of it.
;
; ---------------------------------------------------------------------------
; Three things the oracle settled before this file was started
;
; **`mod` is free and `div` is not**, which is the reverse of SolaBasic. ISO
; says `i mod j` is non-negative for positive `j` -- that is a *floored*
; remainder, and SolVM's is floored, so `mod` is one instruction. ISO's `div`
; truncates toward nought where SolVM's floors, so `-3 div 2` is `-1` in Pascal
; and `-2` on the machine, and it is compiled through `abs` and a sign.
;
; **And a divergence that was not one.** `fpc` answers `-1` for `-3 mod 2`, which
; looked like it disagreeing with ISO's non-negative remainder -- and does not.
; Pascal's sign belongs to the whole *term*, so `-3 mod 2` is `-(3 mod 2)` and
; `-1` is right. Asked with a variable holding `-3` it answers `1`, as the
; standard says and as this compiler does. The claim was written down here
; before it was checked and is left as a note, because a compiler for a language
; whose grammar it has read is exactly the place to misread precedence.
;
; **Its `integer` is 32 bits.** `maxint` is 2147483647 there and 2^63-1 here,
; which [PASCAL.md](../docs/PASCAL.md) already listed as a divergence and the
; oracle confirmed on the first run.
;
; ---------------------------------------------------------------------------
; What a write costs, and why the widths are compile-time strings
;
; `fpc` writes an integer in a field of **11**, a boolean in **5**, a char in
; **1**, and a string in its own length. None of that is the standard's doing --
; ISO leaves the default width to the implementation -- but agreement has to be
; checkable, so these are its numbers.
;
; Solum's `asString(spec)` does the padding, and a spec is known while
; compiling: `writeln(i:6)` emits the constant `">6"`. So a write is a `GLOBAL
; system`, the value, one `asString`, and a `SEND write` -- no runtime formatter
; and no prelude, which is the other thing `sola.sol` needed and this does not.

@include "sob.sol".

; ---------------------------------------------------------------------------
; The instruction set, by the order of the enum in solum/include/solum/bytecode.h

CONST    := #0.
NIL      := #1.
GLOBAL   := #2.
SETGLOB  := #3.
LOCAL    := #4.
SETLOCAL := #5.
OUTER    := #6.
SETOUTER := #7.
STRING   := #9.
BLOCK    := #8.
SEND     := #11.
RETURN   := #19.
JUMP     := #13.
JMPF     := #14.
LOOP     := #17.
POP      := #18.
HALT     := #20.

; ---------------------------------------------------------------------------
; Characters

digits := "0123456789".
lower  := "abcdefghijklmnopqrstuvwxyz".

isDigit := { c | c:notNil:and({ digits:indexOf(c):notNil }) }.
isAlpha := { c | c:notNil:and({ | l | l := c:asLowercase.
    lower:indexOf(l):notNil:or({ l:equals("_") }) }) }.
isAlnum := { c | isAlpha:value(c):or({ isDigit:value(c) }) }.
isSpace := { c | c:notNil:and({ c:equals(" "):or({ c:equals("\t") })
    :or({ c:equals("\n") }):or({ c:equals("\r") }) }) }.

; ---------------------------------------------------------------------------
; The compiler

pas := object:new.

pas:src   := "".
pas:path  := "".
pas:pos   := #1.
pas:line  := #1.

; The token: kind is 'name 'int 'real 'text 'punct 'eof, and `text` is the
; spelling -- folded to lower case for a name, since Pascal does not
; distinguish, and left alone inside a string.
pas:kind  := 'eof.
pas:text  := "".
pas:tline := #1.

pas:code      := array:new.
pas:names     := array:new.
pas:nameIndex := dictionary:new.
pas:constants := array:new.
pas:constIndex := dictionary:new.
pas:lineRuns  := array:new.
pas:atLine    := #1.
pas:runLine   := #1.
pas:runLength := #0.

pas:slotNames := array:new.       ; slot 0 is reserved and unnameable
pas:vars      := dictionary:new.  ; name -> [slot, type]

; ---------------------------------------------------------------------------
; Refusing

pas:fail := { message |
    error:raise("{}:{}: {}":fill([self:path, self:tline, message])) }.

; ---------------------------------------------------------------------------
; The scanner
;
; Pascal's two comment forms nest neither in themselves nor in each other, and
; the standard lets `{` be closed by `*)`. That is not a kindness anybody wants
; and it is what the standard says, so it is what happens here.

pas:atEnd := { self:pos:greaterThan(self:src:size) }.
pas:peek  := { self:atEnd:ifElse({ nil }, { self:src:at(self:pos) }) }.
pas:peekAt := { n | | i | i := self:pos:add(n).
    i:greaterThan(self:src:size):ifElse({ nil }, { self:src:at(i) }) }.

pas:step := {
    self:peek:equals("\n"):ifTrue({ self:line := self:line:add(#1) }).
    self:pos := self:pos:add(#1) }.

pas:skipSpace := { | going |
    going := true.
    { going }:whileTrue({
        isSpace:value(self:peek):ifElse({ self:step }, {
            self:peek:equals("{"):or({ self:peek:equals("(")
                :and({ self:peekAt(#1):equals("*") }) }):ifElse({
                self:skipComment }, { going := false }) }) }) }.

pas:skipComment := { | going |
    self:peek:equals("{"):ifElse({ self:step }, { self:step. self:step }).
    going := true.
    { going }:whileTrue({
        self:atEnd:ifTrue({ self:fail("a comment is not closed") }).
        self:peek:equals("}"):ifElse({ self:step. going := false }, {
            self:peek:equals("*"):and({ self:peekAt(#1):equals(")") }):ifElse(
                { self:step. self:step. going := false },
                { self:step }) }) }) }.

; A quoted literal. Two quotes in a row are one quote, which is the only escape
; the language has.
pas:readText := { | out, going |
    self:step.
    out := "". going := true.
    { going }:whileTrue({
        self:atEnd:ifTrue({ self:fail("a string is not closed") }).
        self:peek:equals("'"):ifElse({
            self:peekAt(#1):equals("'"):ifElse(
                { out := out:concat("'"). self:step. self:step },
                { self:step. going := false }) },
          { out := out:concat(self:peek). self:step }) }).
    out }.

pas:readNumber := { | start, isReal |
    start := self:pos.
    isReal := false.
    { isDigit:value(self:peek) }:whileTrue({ self:step }).

    ; A point only continues the number when a digit follows, so `1..5` is a
    ; subrange and not a malformed real. The standard requires the digit.
    self:peek:equals("."):and({ isDigit:value(self:peekAt(#1)) }):ifTrue({
        isReal := true. self:step.
        { isDigit:value(self:peek) }:whileTrue({ self:step }) }).

    self:peek:notNil:and({ self:peek:asLowercase:equals("e") }):ifTrue({ | save |
        save := self:pos.
        self:step.
        self:peek:equals("+"):or({ self:peek:equals("-") }):ifTrue({ self:step }).
        isDigit:value(self:peek):ifElse({
            isReal := true.
            { isDigit:value(self:peek) }:whileTrue({ self:step }) },
          { self:pos := save }) }).

    self:kind := isReal:ifElse({ 'real }, { 'int }).
    self:text := self:src:copyFrom(start, self:pos:sub(#1)).
    nil }.

; The two-character operators come first, or `:=` is a `:` and `<=` is a `<`.
pas:twoChar := [":=", "<=", ">=", "<>", ".."].

pas:next := { | c, start |
    self:skipSpace.
    self:tline := self:line.
    self:atEnd:ifElse({ self:kind := 'eof. self:text := "" }, {
        c := self:peek.
        isAlpha:value(c):ifElse({
            start := self:pos.
            { isAlnum:value(self:peek) }:whileTrue({ self:step }).
            self:kind := 'name.
            self:text := self:src:copyFrom(start, self:pos:sub(#1)):asLowercase },
        { isDigit:value(c):ifElse({ self:readNumber }, {
          c:equals("'"):ifElse({
              self:kind := 'text. self:text := self:readText },
            { | two, found |
              two := self:peekAt(#1):isNil:ifElse({ "" },
                  { c:concat(self:peekAt(#1)) }).
              found := self:twoChar:indexOf(two):notNil.
              found:ifElse(
                  { self:step. self:step. self:kind := 'punct. self:text := two },
                  { self:step. self:kind := 'punct. self:text := c }) }) }) }) }).
    nil }.

; ---------------------------------------------------------------------------
; Asking about the token

pas:isName := { word | self:kind:equals('name):and({ self:text:equals(word) }) }.
pas:isPunct := { p | self:kind:equals('punct):and({ self:text:equals(p) }) }.

pas:accept := { word |
    self:isName(word):ifElse({ self:next. true }, { false }) }.
pas:acceptPunct := { p |
    self:isPunct(p):ifElse({ self:next. true }, { false }) }.

pas:expect := { word |
    self:accept(word):ifFalse({
        self:fail("expected '{}' and found '{}'":fill([word, self:text])) }).
    nil }.
pas:expectPunct := { p |
    self:acceptPunct(p):ifFalse({
        self:fail("expected '{}' and found '{}'":fill([p, self:text])) }).
    nil }.

pas:expectName := { | t |
    self:kind:equals('name):ifFalse({
        self:fail("expected a name and found '{}'":fill([self:text])) }).
    t := self:text. self:next. t }.

; ---------------------------------------------------------------------------
; Emitting
;
; Bytes into an array, operands little-endian, and the whole chunk handed to
; `sob.sol` at the end -- the arrangement `sola.sol` established and the reason
; that file is in `lib/` rather than inside it.

pas:here := { self:code:size }.
pas:byte := { b | self:code:add(b:bitAnd(#255)) }.
pas:u16  := { n | self:byte(n). self:byte(n:shiftRight(#8)) }.

pas:nameFor := { text |
    self:nameIndex:includes(text):ifElse(
        { self:nameIndex:at(text) },
        { | i | i := self:names:size.
                self:names:add(text).
                self:nameIndex:atPut(text, i).
                i }) }.

; Shared by value **and tag**, because `#0` and `0.0` are two constants and
; pushing the wrong one is a program that runs and is wrong.
pas:constFor := { tag, value | | key |
    key := tag:asString:concat(":"):concat(value:asString).
    self:constIndex:includes(key):ifElse(
        { self:constIndex:at(key) },
        { | i | i := self:constants:size.
                self:constants:add([tag, value]).
                self:constIndex:atPut(key, i).
                i }) }.

pas:emitInt    := { n | self:byte(CONST). self:u16(self:constFor(#1, n)) }.
pas:emitReal   := { v | self:byte(CONST). self:u16(self:constFor(#2, v)) }.
pas:emitBool   := { b | self:byte(CONST). self:u16(self:constFor(#3, b)) }.
pas:emitString := { s | self:byte(STRING). self:u16(self:nameFor(s)) }.
pas:emitGlobal := { s | self:byte(GLOBAL). self:u16(self:nameFor(s)) }.
pas:emitLocal    := { slot | self:byte(LOCAL).    self:byte(slot) }.
pas:emitSetLocal := { slot | self:byte(SETLOCAL). self:byte(slot) }.
pas:emitPop      := { self:byte(POP) }.
pas:emitSend := { sel, argc |
    self:byte(SEND). self:u16(self:nameFor(sel)). self:byte(argc) }.

; A forward jump, patched once its landing place is known. `JUMP_IF_FALSE`
; carries the selector it was inlined from as well as its offset -- so that a
; non-boolean complains the way the send it stands for would have.
pas:emitJump := { | at | self:byte(JUMP). at := self:here. self:u16(#0). at }.
pas:emitJumpFalse := { why | | at |
    self:byte(JMPF). at := self:here. self:u16(#0). self:u16(self:nameFor(why)). at }.

; **The offset is measured from the end of the whole instruction**, and that is
; not always the end of the operand being patched: `JUMP_IF_FALSE` carries the
; selector it was inlined from after its offset, so it is five bytes where
; `JUMP` is three. Getting this wrong produces a file the verifier refuses as
; *internally inconsistent*, which is what it did.
pas:patch := { at | | offset, length |
    length := self:code:at(at):equals(JMPF):ifElse({ #5 }, { #3 }).
    offset := self:here:sub(at):add(#1):sub(length).
    offset:greaterThan(#65535):ifTrue({ self:fail("this jump is too long") }).
    self:code:atPut(at:add(#1), offset:bitAnd(#255)).
    self:code:atPut(at:add(#2), offset:shiftRight(#8):bitAnd(#255)).
    nil }.

pas:emitLoop := { top | | offset |
    self:byte(LOOP).
    offset := self:here:add(#2):sub(top).
    offset:greaterThan(#65535):ifTrue({ self:fail("this loop is too long") }).
    self:u16(offset).
    nil }.

; Run-length encoded, one run per line the code came from.
pas:mark := { n |
    n:equals(self:runLine):ifFalse({
        self:runLength:greaterThan(#0):ifTrue({
            self:lineRuns:add([self:runLength, self:runLine]) }).
        self:runLine := n. self:runLength := #0 }).
    nil }.

; ---------------------------------------------------------------------------
; Scratch slots
;
; `div` wants both its operands twice and the machine has no way to duplicate
; the top of the stack, so they go into slots. Handed out by nesting depth, so
; that `(a div b) div c` does not have its inner pair overwritten by its outer
; one -- which is `sola.sol`'s arrangement and its reasoning.

pas:scratchDepth := #0.
pas:scratchMax   := #0.

; Slots are counted from nought, so the highest one a frame of `n` has is
; `n - 1` -- and handing out `slotBase + scratchMax` rather than one less than
; it is a file the verifier refuses, because a `LOCAL` addressed a slot the
; frame does not have. It says *internally inconsistent* and not which slot,
; which is the whole of the debugging story here.
pas:scratchSlot := { n |
    self:scratchDepth:add(n):greaterThan(self:scratchMax):ifTrue({
        self:scratchMax := self:scratchDepth:add(n) }).
    self:slotBase:add(self:scratchDepth):add(n):sub(#1) }.

pas:slotBase := #1.
; ---------------------------------------------------------------------------
; Types
;
; **A type is an object, and the interesting thing about it is that it has two
; kinds.** `run` is what the machine will be holding -- an integer, a float, a
; one-character string, a boolean -- and `kind` is what Pascal thinks it is. An
; enumeration is an integer at run time and a `Colour` at compile time, and a
; subrange of `char` is a character at run time and a `1 .. 20` at compile time.
;
; Every check below is on `kind` and every instruction emitted is chosen by
; `run`, and keeping those two words apart is most of what stage 2 added.

ptype := object:new.
ptype:kind    := 'integer.   ; integer real char boolean text enum subrange
ptype:run     := 'integer.   ; integer real char boolean text
ptype:name    := "".
ptype:members := nil.        ; an enumeration's names, in order
ptype:base    := nil.        ; a subrange's base type
ptype:lo      := #0.
ptype:hi      := #0.
ptype:elem    := nil.        ; an array's element type
ptype:count   := #0.         ; how many elements an array has, or fields a record
ptype:fields  := nil.        ; a record's [name, type, offset], in order

makeType := { kind, run, name | | t |
    t := ptype:new. t:kind := kind. t:run := run. t:name := name. t }.

tInteger := makeType:value('integer, 'integer, "integer").
tReal    := makeType:value('real,    'real,    "real").
tChar    := makeType:value('char,    'char,    "char").
tBoolean := makeType:value('boolean, 'boolean, "boolean").
tText    := makeType:value('text,    'text,    "string").

; **An array and a record are both a Solum array at run time**, and the
; difference is entirely in what the compiler knows. A record's field is an
; index worked out while compiling, so it costs an `at` and not a lookup; an
; array's subscript is the Pascal index less its lower bound, folded in the same
; way. Neither is a dictionary and neither carries its shape at run time.
isStructured := { t | t:kind:equals('array):or({ t:kind:equals('record) })
    :or({ t:kind:equals('set) }) }.

; The ordinal a bound stands for. A char subrange holds its ends as characters,
; because that is what the source wrote and what a `case` label compares
; against -- so the arithmetic has to ask for the number.
ordinalOf := { t, v | t:run:equals('char):ifElse({ v:asByte }, { v }) }.

; How many elements an ordinal type has, which is what an index range is worth.
spanOf := { t |
    t:kind:equals('subrange):ifElse({
        ordinalOf:value(t, t:hi):sub(ordinalOf:value(t, t:lo)):add(#1) },
    { t:kind:equals('enum):ifElse({ t:members:size },
    { t:run:equals('boolean):ifElse({ #2 },
      { nil }) }) }) }.

; The lowest value an index type takes, as the integer the machine will see.
originOf := { t |
    t:kind:equals('subrange):ifElse({ ordinalOf:value(t, t:lo) },
    { t:kind:equals('enum):ifElse({ #0 },
      { #0 }) }) }.

; A subrange stands for its base wherever compatibility is asked about, which
; is the standard's rule and the reason `1 .. 20` may be assigned to an
; `integer` and compared with one.
rootOf := { t | t:kind:equals('subrange):ifElse({ rootOf:value(t:base) }, { t }) }.

sameType := { a, b | rootOf:value(a):equals(rootOf:value(b)) }.

isNumeric := { t | t:run:equals('integer):or({ t:run:equals('real) }) }.

; What `case`, `for`, `ord`, `succ` and `pred` all want: something with a
; predecessor and a successor. A `real` has neither and a string is not one.
isOrdinal := { t | t:run:equals('integer):or({ t:run:equals('char) })
    :or({ t:run:equals('boolean) }) }.

pas:typeName := { t | t:name:size:equals(#0):ifElse({ t:kind:asString }, { t:name }) }.

; ---------------------------------------------------------------------------
; What the compiler is carrying

pas:types     := dictionary:new.   ; name -> type
pas:consts    := dictionary:new.   ; name -> [type, value]
pas:enumOf    := dictionary:new.   ; an enumeration's member name -> [type, ordinal]
pas:labels    := dictionary:new.   ; label -> [where, jumps waiting for it]
pas:routines  := dictionary:new.   ; name -> [params, resultType, seen]
pas:methods   := array:new.        ; the nested chunks, one per procedure
pas:scope     := "".               ; "" at program level, else the routine's name
pas:result    := nil.              ; the slot a function answers from

; ---------------------------------------------------------------------------
; Which variables live in a box
;
; **A `var` parameter is a box, and the variable *is* the box** -- `sola.sol`'s
; answer, and Pascal is the easier case because `var` is *declared* where QBasic
; made that compiler infer it by a fixed point.
;
; What is not easier is knowing which of the caller's variables need boxing,
; because a variable read in one procedure may be handed to a `var` parameter by
; another one declared later:
;
;     var g : integer;
;     procedure A;                 begin writeln(g) end;   { g read here }
;     procedure B(var x: integer); begin x := 1 end;
;     procedure C;                 begin B(g) end;         { and boxed here }
;
; A's body is already emitted by the time C says so. **So the source is parsed
; twice**: the first pass fills `boxed` and its output is thrown away, and the
; second emits with the answer in hand. Both passes agree about everything else,
; so a program that compiles on the second compiled on the first.
;
; The alternative -- boxing every variable -- costs an allocation and two sends
; on every access in every program, to buy the case where one is passed by
; reference. The alternative to *that* is copy-in and copy-out, which is a
; different language when two parameters name one variable.

pas:boxed := dictionary:new.
pas:pass  := #1.

; **Keyed by identity, not by name.** Every declared variable gets a number when
; it is declared, and the two passes declare in the same order, so the number is
; the same both times. Names cannot do this job once procedures nest: three
; different `i`s at three levels are three variables.
pas:varId := #0.

pas:nextVarId := { self:varId := self:varId:add(#1). self:varId }.

pas:isBoxed   := { entry | self:boxed:includes(entry:at(#4)) }.
pas:markBoxed := { entry | self:boxed:atPut(entry:at(#4), true). nil }.

; ---------------------------------------------------------------------------
; Levels, which are what nesting costs
;
; The program is level 0 and its variables are globals. A procedure written in
; it is level 1, one written inside that is level 2, and a name declared at
; level L and used at level C is:
;
;   L = 0        a global
;   L = C        a slot of this frame        LOCAL
;   L < C        a slot C - L frames out     OUTER C-L
;
; **`OP_OUTER` takes a depth and a slot, which is a static link by another
; name**, and that is the whole of Pascal's scoping. It was written down as a
; prediction in ideas.md before this stage was started, and it held.

pas:level := #0.

; A chunk that reaches out of its own frame has to say so in its flags, and the
; C compiler decides the same thing the same way -- by looking for the
; instruction. Here it is noticed as it is emitted.
pas:touchesHome := false.

pas:lookupVar := { name | | found, i, saved |
    found := self:vars:includes(name):ifElse({ self:vars:at(name) }, { nil }).
    i := self:unitStack:size.
    { found:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
        saved := self:unitStack:at(i):at("vars").
        saved:includes(name):ifTrue({ found := saved:at(name) }).
        i := i:sub(#1) }).
    found }.

pas:lookupRoutine := { name | | found, i, saved |
    found := self:routines:includes(name):ifElse({ self:routines:at(name) }, { nil }).
    i := self:unitStack:size.
    { found:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
        saved := self:unitStack:at(i):at("routines").
        saved:includes(name):ifTrue({ found := saved:at(name) }).
        i := i:sub(#1) }).
    found }.

; Pascal's one implicit conversion: an integer where a real is wanted, and never
; the other way.
pas:toReal := { t |
    t:run:equals('integer):ifTrue({ self:emitSend("asFloat", #0) }).
    tReal }.

pas:wantSame := { a, b, what |
    sameType:value(a, b):ifFalse({
        self:fail("'{}' will not take a {} and a {}"
            :fill([what, self:typeName(a), self:typeName(b)])) }).
    nil }.

; ---------------------------------------------------------------------------
; The value **under** the top of the stack has to become a real, and there is
; no instruction that reaches past the top. Both go into scratch slots and come
; back in the other order, which is three instructions and no cleverness.

pas:widenUnder := { | sb |
    sb := self:scratchSlot(#2).
    self:emitSetLocal(sb). self:emitPop.
    self:emitSend("asFloat", #0).
    self:emitLocal(sb).
    nil }.

; ---------------------------------------------------------------------------
; The required functions this stage has
;
; `ord` of an integer is the integer, so it emits nothing at all -- which is the
; clearest case of `run` and `kind` being different questions. `ord` of a
; boolean has to become 0 or 1 and the machine has no instruction for it, so it
; is a jump, the way `and` is.

pas:emitOrd := { t |
    t:run:equals('char):ifTrue({ self:emitSend("asByte", #0) }).
    t:run:equals('boolean):ifTrue({ | over, past |
        over := self:emitJumpFalse("ord").
        self:emitInt(#1).
        past := self:emitJump.
        self:patch(over).
        self:emitInt(#0).
        self:patch(past) }).
    nil }.

; One step along an ordinal type, in whatever the machine is actually holding.
pas:emitStep := { t, delta |
    t:run:equals('char):ifElse({
        self:emitSend("asByte", #0).
        self:emitInt(delta:abs).
        self:emitSend(delta:lessThan(#0):ifElse({ "sub" }, { "add" }), #1).
        self:emitSend("asCharacter", #0) },
      { t:run:equals('integer):ifElse({
            self:emitInt(delta:abs).
            self:emitSend(delta:lessThan(#0):ifElse({ "sub" }, { "add" }), #1) },
          { self:fail("'succ' and 'pred' want an ordinal") }) }).
    nil }.

pas:builtinCall := { name | | t, s |
    self:expectPunct("(").

    name:equals("ord"):ifElse({
        t := self:expression. self:expectPunct(")").
        isOrdinal:value(t):ifFalse({ self:fail("'ord' wants an ordinal") }).
        self:emitOrd(t). tInteger },

    { name:equals("chr"):ifElse({
        t := self:expression. self:expectPunct(")").
        t:run:equals('integer):ifFalse({ self:fail("'chr' wants an integer") }).
        self:emitSend("asCharacter", #0). tChar },

    { name:equals("succ"):or({ name:equals("pred") }):ifElse({
        t := self:expression. self:expectPunct(")").
        isOrdinal:value(t):ifFalse({
            self:fail("'{}' wants an ordinal":fill([name])) }).
        self:emitStep(t, name:equals("succ"):ifElse({ #1 }, { #-1 })).
        t },

    { name:equals("odd"):ifElse({
        t := self:expression. self:expectPunct(")").
        t:run:equals('integer):ifFalse({ self:fail("'odd' wants an integer") }).
        self:emitInt(#2). self:emitSend("mod", #1).
        self:emitInt(#0). self:emitSend("notEquals", #1). tBoolean },

    { name:equals("abs"):ifElse({
        t := self:expression. self:expectPunct(")").
        isNumeric:value(t):ifFalse({ self:fail("'abs' wants a number") }).
        self:emitSend("abs", #0). t },

    { name:equals("sqr"):ifElse({
        t := self:expression. self:expectPunct(")").
        isNumeric:value(t):ifFalse({ self:fail("'sqr' wants a number") }).
        ; The value is wanted twice and the machine cannot duplicate a stack
        ; top, so it goes into a slot -- the same arrangement `div` needs.
        s := self:scratchSlot(#1).
        self:emitSetLocal(s). self:emitPop.
        self:emitLocal(s). self:emitLocal(s).
        self:emitSend("mul", #1).
        t },

      { self:fail("'{}' is not a function this stage has":fill([name])) }) }) }) }) }) }) }.

pas:builtins := ["ord", "chr", "succ", "pred", "odd", "abs", "sqr"].

; ---------------------------------------------------------------------------
; Expressions
;
; Recursive descent over the standard's grammar, and every one of these answers
; the **type** of what it left on the stack. That answer is the whole of the
; type checking: there is no tree to walk afterwards.

pas:relOps := dictionary:new.
pas:relOps:atPut("=", "equals").
pas:relOps:atPut("<>", "notEquals").
pas:relOps:atPut("<", "lessThan").
pas:relOps:atPut("<=", "lessOrEqual").
pas:relOps:atPut(">", "greaterThan").
pas:relOps:atPut(">=", "greaterOrEqual").

; A constant, wherever one may stand: a literal, a `const` name, or an
; enumeration member. Answers [type, value] and emits nothing, because a
; constant expression is worked out here and never at run time.
pas:constValue := { | name, sign, v, found |
    sign := #1.
    self:isPunct("+"):ifTrue({ self:next }).
    self:isPunct("-"):ifTrue({ self:next. sign := #-1 }).

    self:kind:equals('int):ifElse({
        v := self:text:asInteger:mul(sign). self:next. [tInteger, v] },
    { self:kind:equals('real):ifElse({
        v := self:text:asFloat:mul(sign:asFloat). self:next. [tReal, v] },
    { self:kind:equals('text):ifElse({
        sign:equals(#-1):ifTrue({ self:fail("a string has no sign") }).
        v := self:text. self:next.
        [v:size:equals(#1):ifElse({ tChar }, { tText }), v] },
      { name := self:expectName.
        name:equals("true"):or({ name:equals("false") }):ifElse({
            [tBoolean, name:equals("true")] },
        { name:equals("maxint"):ifElse({ [tInteger, #9223372036854775807] },
          { self:consts:includes(name):ifElse({
                found := self:consts:at(name).
                sign:equals(#-1):ifTrue({
                    isNumeric:value(found:at(#1)):ifFalse({
                        self:fail("'{}' has no sign":fill([name])) }).
                    found := [found:at(#1), #0:sub(found:at(#2))] }).
                found },
            { self:enumOf:includes(name):ifElse({
                  found := self:enumOf:at(name).
                  [found:at(#1), found:at(#2)] },
                { self:fail("'{}' is not a constant":fill([name])) }) }) }) }) }) }) }) }.

; ---------------------------------------------------------------------------
; Reading and writing a variable
;
; **Two questions, and they are independent.** Where it lives -- a frame slot
; inside a procedure, a global at program level -- and whether it is in a box.
;
; A program's variables are globals because a procedure has to see them, and a
; block cannot reach the script's slots without `OP_OUTER`, which is stage 4's
; business. They carry a `pas.` in front so that a Pascal program declaring
; `var system : integer` cannot reach in and replace the machine's own.

pas:globalName := { name | "pas.":concat(name) }.

pas:emitAccess := { name, entry, store | | at |
    at := entry:at(#3).
    at:equals(#0):ifElse({
        store:ifElse(
            { self:byte(SETGLOB). self:u16(self:nameFor(self:globalName(name))) },
            { self:emitGlobal(self:globalName(name)) }) },

    { at:equals(self:level):ifElse({
        store:ifElse({ self:emitSetLocal(entry:at(#1)) },
                     { self:emitLocal(entry:at(#1)) }) },

      { self:touchesHome := true.
        self:byte(store:ifElse({ SETOUTER }, { OUTER })).
        self:byte(self:level:sub(at)).
        self:byte(entry:at(#1)) }) }).
    nil }.

pas:emitReadVar := { name, entry |
    self:emitAccess(name, entry, false).
    self:isBoxed(entry):ifTrue({
        self:emitInt(#1). self:emitSend("at", #1) }).
    nil }.

; The value is already on the stack. A boxed store needs the array underneath
; it and there is no reaching past the top, so the value goes into a scratch
; slot and comes back -- the same three instructions `widenUnder` needs.
pas:emitStoreVar := { name, entry | | tmp |
    self:isBoxed(entry):ifElse({
        self:scratchDepth := self:scratchDepth:add(#2).
        tmp := self:scratchSlot(#1).
        self:emitSetLocal(tmp). self:emitPop.
        self:emitAccess(name, entry, false).
        self:emitInt(#1).
        self:emitLocal(tmp).
        self:emitSend("atPut", #2).
        self:emitPop.
        self:scratchDepth := self:scratchDepth:sub(#2) },

      { self:emitAccess(name, entry, true).
        self:emitPop }).
    nil }.

; ---------------------------------------------------------------------------
; Sets
;
; Every one of these is a loop over the base type's whole span, because that is
; what a set of booleans is. **Membership is the exception and the reason for
; the representation**: `x in s` is one `at`, and it is the operation a program
; writes most.

pas:setHint := nil.

pas:setAt := { slot, i |
    self:emitLocal(slot). self:emitLocal(i).
    self:emitInt(#1). self:emitSend("add", #1).
    self:emitSend("at", #1).
    nil }.

; `a`, `b` and a fresh array, filled one element at a time. The three operations
; differ only in the two instructions that combine one pair -- and each of those
; is a jump, the machine's own `and` and `or` taking blocks.
pas:emitSetOp := { t, which | | a, b, res, i, top, over, l1, l2 |
    self:scratchDepth := self:scratchDepth:add(#6).
    b := self:scratchSlot(#1). a := self:scratchSlot(#2).
    res := self:scratchSlot(#3). i := self:scratchSlot(#4).

    self:emitSetLocal(b). self:emitPop.
    self:emitSetLocal(a). self:emitPop.
    self:emitGlobal("array"). self:emitSend("new", #0).
    self:emitSetLocal(res). self:emitPop.
    self:emitInt(#0). self:emitSetLocal(i). self:emitPop.

    top := self:here.
    self:emitLocal(i). self:emitInt(t:count). self:emitSend("lessThan", #1).
    over := self:emitJumpFalse("set").

    self:emitLocal(res).
    self:setAt(a, i).
    l1 := self:emitJumpFalse("set").
    which:equals('union):ifElse({ self:emitBool(true) },
        { self:setAt(b, i).
          which:equals('difference):ifTrue({ self:emitSend("not", #0) }) }).
    l2 := self:emitJump.
    self:patch(l1).
    which:equals('union):ifElse({ self:setAt(b, i) }, { self:emitBool(false) }).
    self:patch(l2).
    self:emitSend("add", #1). self:emitPop.

    self:emitLocal(i). self:emitInt(#1). self:emitSend("add", #1).
    self:emitSetLocal(i). self:emitPop.
    self:emitLoop(top).
    self:patch(over).

    self:emitLocal(res).
    self:scratchDepth := self:scratchDepth:sub(#6).
    nil }.

; `res := res and <this pair agrees>`, which short-circuits: once it is false
; nothing further is computed, and the accumulator is what the loop answers.
pas:emitSetCompare := { t, which | | a, b, res, i, top, over, skip, l1, l2 |
    self:scratchDepth := self:scratchDepth:add(#6).
    b := self:scratchSlot(#1). a := self:scratchSlot(#2).
    res := self:scratchSlot(#3). i := self:scratchSlot(#4).

    ; The right operand is on top, so it is stored first.
    self:emitSetLocal(b). self:emitPop.
    self:emitSetLocal(a). self:emitPop.

    ; **After the stores, not before.** `a >= b` is `b <= a`, so the two are
    ; exchanged -- and exchanging the names first only makes the stores put them
    ; back, which is what it did.
    which:equals('superset):ifTrue({ | swap | swap := a. a := b. b := swap }).
    self:emitBool(true). self:emitSetLocal(res). self:emitPop.
    self:emitInt(#0). self:emitSetLocal(i). self:emitPop.

    top := self:here.
    self:emitLocal(i). self:emitInt(t:count). self:emitSend("lessThan", #1).
    over := self:emitJumpFalse("set").

    self:emitLocal(res).
    skip := self:emitJumpFalse("set").

    which:equals('equal):ifElse({
        self:setAt(a, i). self:setAt(b, i). self:emitSend("equals", #1) },

      ; `a <= b` is *for every member of a, b has it too*, which is
      ; `(not a[i]) or b[i]` -- and the `or` is a jump like every other.
      { self:setAt(a, i).
        l1 := self:emitJumpFalse("set").
        self:setAt(b, i).
        l2 := self:emitJump.
        self:patch(l1).
        self:emitBool(true).
        self:patch(l2) }).
    self:emitSetLocal(res). self:emitPop.
    self:patch(skip).

    self:emitLocal(i). self:emitInt(#1). self:emitSend("add", #1).
    self:emitSetLocal(i). self:emitPop.
    self:emitLoop(top).
    self:patch(over).

    self:emitLocal(res).
    self:scratchDepth := self:scratchDepth:sub(#6).
    nil }.

; **A set literal has no type of its own**, so it takes one from where it
; stands: the variable it is assigned to, the set it is combined with, or the
; value it is tested against. Failing all of those, from its first member --
; and an integer member has no span, so it gets `0 .. 255`, which is `fpc`'s
; choice and recorded as one.
pas:setTypeFor := { base | | t |
    t := makeType:value('set, 'set, "set of {}":fill([self:typeName(base)])).
    t:base := base.
    t:lo := originOf:value(base).
    t:count := spanOf:value(base).
    t:count:isNil:ifTrue({ t:lo := #0. t:count := #256 }).
    t }.

pas:emitSetIndex := { t | | it |
    it := self:expression.
    sameType:value(it, t:base):ifFalse({
        self:fail("this set holds {} and that is a {}"
            :fill([self:typeName(t:base), self:typeName(it)])) }).
    self:emitOrd(it).
    t:lo:equals(#0):ifFalse({ self:emitInt(t:lo). self:emitSend("sub", #1) }).
    nil }.

pas:setConstructor := { | t, slot, more, lo2, hi2, i, top, over |
    t := self:setHint.
    self:setHint := nil.

    self:scratchDepth := self:scratchDepth:add(#6).
    slot := self:scratchSlot(#5).

    self:isPunct("]"):ifElse({
        self:next.
        t:isNil:ifTrue({
            self:fail("the type of an empty set cannot be told from here") }).
        self:emitZeroOf(t).
        self:emitSetLocal(slot). self:emitPop },

      { ; The first member settles the type when nothing else has.
        t:isNil:ifTrue({ | probe |
            probe := self:pass. nil }).
        t:isNil:ifTrue({
            self:fail("the type of this set cannot be told from here -- assign it to a set variable") }).
        self:emitZeroOf(t).
        self:emitSetLocal(slot). self:emitPop.

        more := true.
        { more }:whileTrue({
            self:emitSetIndex(t).
            self:acceptPunct(".."):ifElse({
                ; A range: both ends into slots, then a loop between them.
                lo2 := self:scratchSlot(#1).
                hi2 := self:scratchSlot(#2).
                i := self:scratchSlot(#3).
                self:emitSetLocal(lo2). self:emitPop.
                self:emitSetIndex(t).
                self:emitSetLocal(hi2). self:emitPop.
                self:emitLocal(lo2). self:emitSetLocal(i). self:emitPop.
                top := self:here.
                self:emitLocal(i). self:emitLocal(hi2).
                self:emitSend("lessOrEqual", #1).
                over := self:emitJumpFalse("set").
                self:emitLocal(slot). self:emitLocal(i).
                self:emitInt(#1). self:emitSend("add", #1).
                self:emitBool(true). self:emitSend("atPut", #2). self:emitPop.
                self:emitLocal(i). self:emitInt(#1). self:emitSend("add", #1).
                self:emitSetLocal(i). self:emitPop.
                self:emitLoop(top).
                self:patch(over) },

              { ; One member: the index is on the stack already.
                self:scratchDepth := self:scratchDepth:add(#2).
                lo2 := self:scratchSlot(#1).
                self:emitSetLocal(lo2). self:emitPop.
                self:emitLocal(slot).
                self:emitLocal(lo2). self:emitInt(#1). self:emitSend("add", #1).
                self:emitBool(true). self:emitSend("atPut", #2). self:emitPop.
                self:scratchDepth := self:scratchDepth:sub(#2) }).
            more := self:acceptPunct(",") }).
        self:expectPunct("]") }).

    self:emitLocal(slot).
    self:scratchDepth := self:scratchDepth:sub(#6).
    t }.

; ---------------------------------------------------------------------------
; Designators
;
; `a[i]`, `r.f`, and any run of the two. **A read leaves the value; a store
; stops one step short**, leaving the container and the index for an `atPut`.
; Which of those is wanted is known before the last step is emitted, which is
; the only lookahead any of this needs.
;
; A whole variable with no selectors is a third case, because a store into one
; is a `SETLOCAL` and has no container at all.

pas:withStack := array:new.

pas:lookupWith := { name | | found, i, w |
    found := nil.
    i := self:withStack:size.
    { found:isNil:and({ i:greaterOrEqual(#1) }) }:whileTrue({
        w := self:withStack:at(i).
        w:at(#2):fields:do({ f |
            found:isNil:and({ f:at(#1):equals(name) }):ifTrue({
                found := [w:at(#1), f] }) }).
        i := i:sub(#1) }).
    found }.

pas:atSelector := { self:isPunct("["):or({ self:isPunct(".") }) }.

pas:emitIndexStep := { t | | it |
    t:kind:equals('array):ifFalse({
        self:fail("a {} cannot be subscripted":fill([self:typeName(t)])) }).
    it := self:expression.
    sameType:value(it, t:base):ifFalse({
        self:fail("this array is indexed by a {} and that is a {}"
            :fill([self:typeName(t:base), self:typeName(it)])) }).
    ; Whatever the index type is, what the machine needs is its ordinal --
    ; `asByte` for a char, a jump for a boolean, and nothing at all for an
    ; integer or an enumeration.
    self:emitOrd(it).

    ; Solum counts from one and Pascal from wherever it was told, so the
    ; difference is folded in here and costs nothing at run time when it is nought.
    t:lo:equals(#1):ifFalse({
        self:emitInt(t:lo:sub(#1)). self:emitSend("sub", #1) }).
    t:elem }.

pas:emitFieldStep := { t, name | | found |
    t:kind:equals('record):ifFalse({
        self:fail("a {} has no fields":fill([self:typeName(t)])) }).
    found := nil.
    t:fields:do({ f | f:at(#1):equals(name):ifTrue({ found := f }) }).
    found:isNil:ifTrue({
        self:fail("this record has no field '{}'":fill([name])) }).
    self:emitInt(found:at(#3)).
    found:at(#2) }.

pas:selectors := { t, forStore | | going, more, mode, f |
    mode := 'value.
    going := true.
    { going }:whileTrue({
        self:acceptPunct("["):ifElse({
            more := true.
            { more }:whileTrue({
                t := self:emitIndexStep(t).
                more := self:acceptPunct(",").
                more:ifElse({ self:emitSend("at", #1) },
                  { self:expectPunct("]").
                    going := self:atSelector.
                    going:not:and({ forStore }):ifElse({ mode := 'element },
                        { self:emitSend("at", #1) }) }) }) },

          { self:expectPunct(".").
            f := self:expectName.
            t := self:emitFieldStep(t, f).
            going := self:atSelector.
            going:not:and({ forStore }):ifElse({ mode := 'element },
                { self:emitSend("at", #1) }) }) }).
    [mode, t, nil] }.

pas:designator := { name, forStore | | entry, t, w |
    w := self:lookupWith(name).
    w:notNil:ifElse({
        ; A field made visible by `with`: the record is already in a slot and
        ; the field is an index into it.
        self:emitLocal(w:at(#1)).
        self:emitInt(w:at(#2):at(#3)).
        t := w:at(#2):at(#2).
        self:atSelector:ifElse({
            self:emitSend("at", #1).
            self:selectors(t, forStore) },
          { forStore:ifElse({ ['element, t, nil] },
              { self:emitSend("at", #1). ['value, t, nil] }) }) },

    { entry := self:lookupVar(name).
      entry:isNil:ifTrue({ self:fail("'{}' is not declared":fill([name])) }).
      t := entry:at(#2).
      self:atSelector:ifElse({
          self:emitReadVar(name, entry).
          self:selectors(t, forStore) },
        { forStore:ifElse({ ['whole, t, entry] },
            { self:emitReadVar(name, entry). ['value, t, nil] }) }) }) }.

pas:emitValue := { t, v |
    t:run:equals('integer):ifTrue({ self:emitInt(v) }).
    t:run:equals('real):ifTrue({ self:emitReal(v) }).
    t:run:equals('boolean):ifTrue({ self:emitBool(v) }).
    t:run:equals('char):or({ t:run:equals('text) }):ifTrue({ self:emitString(v) }).
    nil }.

pas:factor := { | t, name, v, over, pair, found |
    self:kind:equals('int):ifElse({
        self:emitInt(self:text:asInteger). self:next. tInteger },
    { self:kind:equals('real):ifElse({
        self:emitReal(self:text:asFloat). self:next. tReal },
    { self:kind:equals('text):ifElse({
        v := self:text. self:next.
        self:emitString(v).
        v:size:equals(#1):ifElse({ tChar }, { tText }) },
    { self:acceptPunct("["):ifElse({ self:setConstructor },

    { self:acceptPunct("("):ifElse({
        t := self:expression.
        self:expectPunct(")").
        t },
    { self:accept("not"):ifElse({
        t := self:factor.
        t:run:equals('boolean):ifFalse({
            self:fail("'not' wants a boolean and found a {}"
                :fill([self:typeName(t)])) }).
        self:emitSend("not", #0).
        tBoolean },
    { self:kind:equals('name):ifElse({
        name := self:text.

        self:builtins:indexOf(name):notNil:ifElse({
            self:next. self:builtinCall(name) },

        { self:lookupRoutine(name):notNil:ifElse({
            self:next.
            self:callRoutine(name, true) },

        { self:lookupVar(name):notNil:or({ self:lookupWith(name):notNil })
            :ifElse({
            self:next.
            self:designator(name, false):at(#2) },

          ; Everything left is a constant of some kind -- a `const`, an
          ; enumeration member, `true`, `false` or `maxint` -- and all of them
          ; are worked out here rather than emitted as a lookup.
          { pair := self:constValue.
            self:emitValue(pair:at(#1), pair:at(#2)).
            pair:at(#1) }) }) }) },

      { self:fail("expected a value and found '{}'":fill([self:text])) }) }) }) }) }) }) }) }.

; `div` truncates toward nought where the machine floors, so it is compiled
; through `abs` and a sign rather than emitted as one send. See the header.
pas:emitTruncatingDiv := { | sa, sb, over |
    sa := self:scratchSlot(#1).
    sb := self:scratchSlot(#2).

    self:emitSetLocal(sb). self:emitPop.       ; the divisor is on top
    self:emitSetLocal(sa). self:emitPop.

    self:emitLocal(sa). self:emitSend("abs", #0).
    self:emitLocal(sb). self:emitSend("abs", #0).
    self:emitSend("div", #1).

    self:emitLocal(sa). self:emitInt(#0). self:emitSend("lessThan", #1).
    self:emitLocal(sb). self:emitInt(#0). self:emitSend("lessThan", #1).
    self:emitSend("notEquals", #1).
    over := self:emitJumpFalse("div").
    self:emitSend("negated", #0).
    self:patch(over).
    nil }.

pas:term := { | left, op, right, over, past |
    self:scratchDepth := self:scratchDepth:add(#2).
    left := self:factor.
    { self:isPunct("*"):or({ self:isPunct("/") })
        :or({ self:isName("div") }):or({ self:isName("mod") })
        :or({ self:isName("and") }) }:whileTrue({
        op := self:text. self:next.

        op:equals("and"):ifElse({
            left:run:equals('boolean):ifFalse({
                self:fail("'and' wants booleans") }).
            over := self:emitJumpFalse("and").
            right := self:factor.
            right:run:equals('boolean):ifFalse({ self:fail("'and' wants booleans") }).
            past := self:emitJump.
            self:patch(over).
            self:emitBool(false).
            self:patch(past).
            left := tBoolean },

        { left:kind:equals('set):ifTrue({ self:setHint := left }).
          right := self:factor.
          op:equals("/"):ifElse({
              isNumeric:value(left):and({ isNumeric:value(right) }):ifFalse({
                  self:fail("'/' wants numbers") }).
              self:toReal(right).
              left:run:equals('integer):ifTrue({ self:widenUnder }).
              self:emitSend("div", #1).
              left := tReal },

          { op:equals("div"):or({ op:equals("mod") }):ifElse({
              left:run:equals('integer):and({ right:run:equals('integer) })
                  :ifFalse({ self:fail("'{}' wants integers":fill([op])) }).
              op:equals("div"):ifElse(
                  { self:emitTruncatingDiv },
                  { self:emitSend("mod", #1) }).
              left := tInteger },

            { left:kind:equals('set):ifTrue({
                  self:wantSame(left, right, "*").
                  self:emitSetOp(left, 'intersection) }).
              left:kind:equals('set):ifFalse({
              isNumeric:value(left):and({ isNumeric:value(right) }):ifFalse({
                  self:fail("'*' wants numbers") }).
              left:run:equals('real):or({ right:run:equals('real) }):ifElse({
                  self:toReal(right).
                  left:run:equals('integer):ifTrue({ self:widenUnder }).
                  self:emitSend("mul", #1).
                  left := tReal },
                { self:emitSend("mul", #1). left := tInteger }) }) }) }) }) }).
    self:scratchDepth := self:scratchDepth:sub(#2).
    left }.

pas:simpleExpression := { | left, op, right, negate, past, skip |
    negate := false.
    self:isPunct("+"):ifTrue({ self:next }).
    self:isPunct("-"):ifTrue({ self:next. negate := true }).

    left := self:term.
    negate:ifTrue({
        isNumeric:value(left):ifFalse({ self:fail("'-' wants a number") }).
        self:emitSend("negated", #0) }).

    { self:isPunct("+"):or({ self:isPunct("-") }):or({ self:isName("or") }) }
        :whileTrue({
        op := self:text. self:next.

        ; `a or b` is a jump and not a send, because the machine's `or` takes a
        ; block. It short-circuits, which the standard permits and does not
        ; require -- evaluation order for these is the implementation's.
        op:equals("or"):ifElse({
            left:run:equals('boolean):ifFalse({ self:fail("'or' wants booleans") }).
            past := self:emitJumpFalse("or").
            self:emitBool(true).
            skip := self:emitJump.
            self:patch(past).
            right := self:term.
            right:run:equals('boolean):ifFalse({ self:fail("'or' wants booleans") }).
            self:patch(skip).
            left := tBoolean },

        { left:kind:equals('set):ifTrue({ self:setHint := left }).
          right := self:term.

          left:kind:equals('set):ifElse({
              self:wantSame(left, right, op).
              self:emitSetOp(left, op:equals("+"):ifElse({ 'union },
                                                        { 'difference })) },

            { isNumeric:value(left):and({ isNumeric:value(right) }):ifFalse({
                  self:fail("'{}' wants numbers":fill([op])) }).
              left:run:equals('real):or({ right:run:equals('real) }):ifElse({
                  self:toReal(right).
                  left:run:equals('integer):ifTrue({ self:widenUnder }).
                  left := tReal },
                { left := tInteger }).
              self:emitSend(op:equals("+"):ifElse({ "add" }, { "sub" }), #1) }) }) }).
    left }.

pas:expression := { | left, op, right, xs |
    left := self:simpleExpression.

    ; `x in s` is one `at`, which is the whole case for a set being an array of
    ; booleans. The member is put aside first because the set has to be the
    ; receiver and it arrives second.
    self:isName("in"):ifTrue({
        self:next.
        self:scratchDepth := self:scratchDepth:add(#2).
        xs := self:scratchSlot(#1).
        self:emitSetLocal(xs). self:emitPop.
        self:setHint := self:setTypeFor(rootOf:value(left)).
        right := self:simpleExpression.
        right:kind:equals('set):ifFalse({
            self:fail("'in' wants a set on the right") }).
        sameType:value(left, right:base):ifFalse({
            self:fail("this set holds {} and that is a {}"
                :fill([self:typeName(right:base), self:typeName(left)])) }).
        self:emitLocal(xs).
        self:emitOrd(left).
        right:lo:equals(#0):ifFalse({
            self:emitInt(right:lo). self:emitSend("sub", #1) }).
        self:emitInt(#1). self:emitSend("add", #1).
        self:emitSend("at", #1).
        self:scratchDepth := self:scratchDepth:sub(#2).
        left := tBoolean }).

    self:kind:equals('punct):and({ self:relOps:includes(self:text) }):ifTrue({
        op := self:text. self:next.
        left:kind:equals('set):ifTrue({ self:setHint := left }).
        right := self:simpleExpression.

        left:kind:equals('set):ifTrue({
            self:wantSame(left, right, op).
            op:equals("="):or({ op:equals("<>") }):ifTrue({
                self:emitSetCompare(left, 'equal).
                op:equals("<>"):ifTrue({ self:emitSend("not", #0) }) }).
            op:equals("<="):ifTrue({ self:emitSetCompare(left, 'subset) }).
            op:equals(">="):ifTrue({ self:emitSetCompare(left, 'superset) }).
            op:equals("<"):or({ op:equals(">") }):ifTrue({
                self:fail("sets compare with =, <>, <= and >=") }) }).

        left:kind:equals('set):ifFalse({
        isNumeric:value(left):and({ isNumeric:value(right) }):ifElse({
            left:run:equals('real):or({ right:run:equals('real) }):ifTrue({
                self:toReal(right).
                left:run:equals('integer):ifTrue({ self:widenUnder }) }) },
          { self:wantSame(left, right, op).
            left:run:equals('boolean):and({ op:equals("="):or({ op:equals("<>") })
                :not }):ifTrue({
                self:fail("booleans compare with '=' and '<>' in this stage") }) }).

        self:emitSend(self:relOps:at(op), #1) }).
        left := tBoolean }).
    left }.

; ---------------------------------------------------------------------------
; Writing
;
; Every field width is a compile-time string, which is what makes a write four
; instructions and no runtime formatter. A width computed while running is
; legal Pascal and is stage 8; it is refused by name rather than accepted and
; got wrong.

pas:widthOf := { | sign, v |
    sign := #1.
    self:isPunct("-"):ifTrue({ self:next. sign := #-1 }).
    self:kind:equals('int):ifFalse({
        self:fail("a field width has to be a literal in this stage") }).
    v := self:text:asInteger:mul(sign).
    self:next.
    v }.

; fpc's defaults, adopted so that agreement is checkable: the standard leaves
; every one of these to the implementation.
pas:defaultWidth := dictionary:new.
pas:defaultWidth:atPut('integer, #11).
pas:defaultWidth:atPut('boolean, #5).

pas:writeItem := { | t, width, places |
    t := self:expression.
    width := nil. places := nil.
    self:acceptPunct(":"):ifTrue({
        width := self:widthOf.
        self:acceptPunct(":"):ifTrue({ places := self:widthOf }) }).

    ; **An enumeration cannot be written**, which is the standard's rule and not
    ; a gap here: `write` takes an integer, a real, a char, a boolean or a
    ; string, and a `Colour` is none of them however it is held.
    t:kind:equals('enum):ifTrue({
        self:fail("an enumeration cannot be written -- ord() can") }).
    isStructured:value(t):ifTrue({
        self:fail("a {} cannot be written; write its parts"
            :fill([self:typeName(t)])) }).

    places:notNil:ifTrue({
        t:run:equals('real):ifFalse({
            self:fail("only a real takes a second field width") }) }).

    t:run:equals('boolean):ifTrue({ self:emitSend("asString", #0) }).

    t:run:equals('real):ifElse({
        places:notNil:ifElse({
            self:emitString(">{}.{}":fill([width, places])).
            self:emitSend("asString", #1) },
          { width:isNil:ifElse(
                { self:emitSend("asString", #0) },
                { self:emitSend("asString", #0).
                  self:emitString(">{}":fill([width])).
                  self:emitSend("asString", #1) }) }) },

      { width:isNil:ifElse({
            self:defaultWidth:includes(t:run):ifTrue({
                self:emitString(">{}":fill([self:defaultWidth:at(t:run)])).
                self:emitSend("asString", #1) }) },
          { t:run:equals('integer):ifTrue({ self:emitSend("asString", #0) }).
            self:emitString(">{}":fill([width])).
            self:emitSend("asString", #1) }) }).
    nil }.

pas:writeCall := { newline | | more |
    self:acceptPunct("("):ifElse({
        more := true.
        { more }:whileTrue({
            self:emitGlobal("system").
            self:writeItem.
            self:emitSend("write", #1).
            self:emitPop.
            more := self:acceptPunct(",") }).
        self:expectPunct(")") },
      { newline:ifFalse({ self:fail("'write' wants something to write") }) }).

    newline:ifTrue({
        self:emitGlobal("system").
        self:emitString("\n").
        self:emitSend("write", #1).
        self:emitPop }).
    nil }.

; ---------------------------------------------------------------------------
; Labels and goto
;
; A label is an unsigned integer the standard makes you declare, and a `goto`
; may be written before or after the label it names. Backwards is `OP_LOOP` and
; forwards is `OP_JUMP` with the offset filled in when the label arrives --
; which is `sola.sol`'s arrangement, and it works for the same reason: **every
; statement here leaves the stack as it found it**, so every label is a depth-0
; merge point by construction and the verifier needs no analysis at all.

pas:labelDecl := { | more |
    more := true.
    { more }:whileTrue({
        self:kind:equals('int):ifFalse({ self:fail("a label is a number") }).
        self:labels:includes(self:text):ifTrue({
            self:fail("label {} is declared twice":fill([self:text])) }).
        self:labels:atPut(self:text, [nil, array:new]).
        self:next.
        more := self:acceptPunct(",") }).
    self:expectPunct(";").
    nil }.

pas:placeLabel := { name | | entry |
    entry := self:labels:at(name).
    entry:at(#1):notNil:ifTrue({
        self:fail("label {} marks two places":fill([name])) }).
    entry:atPut(#1, self:here).
    entry:at(#2):do({ at | self:patch(at) }).
    entry:atPut(#2, array:new).
    nil }.

pas:gotoLabel := { name | | entry |
    self:labels:includes(name):ifFalse({
        self:fail("label {} is not declared":fill([name])) }).
    entry := self:labels:at(name).
    entry:at(#1):isNil:ifElse(
        { entry:at(#2):add(self:emitJump) },
        { self:emitLoop(entry:at(#1)) }).
    nil }.

; ---------------------------------------------------------------------------
; Statements

pas:statement := { | name, over, past, top, target, ends |
    self:lineMark(self:tline).

    ; A number here is a label on this statement, not a value.
    self:kind:equals('int):ifTrue({
        name := self:text. self:next. self:expectPunct(":").
        self:placeLabel(name) }).

    self:isName("begin"):ifElse({ self:compound },

    { self:accept("if"):ifElse({
        self:conditionFor("if").
        self:expect("then").
        over := self:emitJumpFalse("ifTrue").
        self:statement.
        self:accept("else"):ifElse({
            past := self:emitJump.
            self:patch(over).
            self:statement.
            self:patch(past) },
          { self:patch(over) }) },

    { self:accept("while"):ifElse({
        top := self:here.
        self:conditionFor("while").
        self:expect("do").
        over := self:emitJumpFalse("whileTrue").
        self:statement.
        self:emitLoop(top).
        self:patch(over) },

    ; **`repeat` needs both jumps**, because `JUMP_IF_FALSE` only goes forward
    ; and `OP_LOOP` is unconditional. A false condition jumps over the exit and
    ; into the loop back; a true one falls into the exit. Written the other way
    ; round -- the way it reads -- the loop runs exactly once.
    { self:accept("repeat"):ifElse({
        top := self:here.
        self:statement.
        { self:acceptPunct(";") }:whileTrue({ self:statement }).
        self:expect("until").
        self:conditionFor("until").
        over := self:emitJumpFalse("doUntil").
        past := self:emitJump.
        self:patch(over).
        self:emitLoop(top).
        self:patch(past) },

    { self:accept("with"):ifElse({ self:withStatement },

    { self:accept("for"):ifElse({ self:forStatement },
    { self:accept("case"):ifElse({ self:caseStatement },
    { self:accept("goto"):ifElse({
        self:kind:equals('int):ifFalse({ self:fail("'goto' wants a label") }).
        name := self:text. self:next.
        self:gotoLabel(name) },

    { self:accept("writeln"):ifElse({ self:writeCall(true) },
    { self:accept("write"):ifElse({ self:writeCall(false) },

    { self:kind:equals('name):ifElse({
        name := self:expectName.

        ; A name at the start of a statement is a procedure call or the target
        ; of an assignment, and the name itself says which -- no lookahead.
        ;
        ; **This unit's own names come first, and that is what makes a function
        ; able to answer.** Inside `Fact`, the name `Fact` is the result
        ; variable here and a recursive call in an expression, which is the
        ; standard's rule and falls out of asking the two questions in this
        ; order.
        self:vars:includes(name):and({ self:atSelector:not }):ifElse({
            target := self:vars:at(name).
            self:expectPunct(":=").
            self:assignInto(target, name) },

        { self:lookupRoutine(name):notNil:ifElse({
            self:callRoutine(name, false). self:emitPop },

          { self:assignTo(name) }) }) },

      ; The empty statement, which the standard has and which is what a `;`
      ; before an `end` produces.
      { nil }) }) }) }) }) }) }) }) }) }) }).
    nil }.

; **The record is evaluated once and kept in a slot**, which is what makes
; `with a[i] do` sound: the standard says the designator is evaluated once, so a
; subscript with a side effect -- or one whose variable the body changes --
; cannot be re-read.
;
; The slot is a scratch one, taken at a depth the body cannot reach, because a
; `with` lives across a whole statement where every other scratch use lives
; inside one expression.
pas:withStatement := { | more, res, slot, added, name |
    added := #0.
    more := true.
    { more }:whileTrue({
        self:scratchDepth := self:scratchDepth:add(#2).
        name := self:expectName.
        res := self:designator(name, false).
        res:at(#2):kind:equals('record):ifFalse({
            self:fail("'with' wants a record and '{}' is a {}"
                :fill([name, self:typeName(res:at(#2))])) }).
        slot := self:scratchSlot(#1).
        self:emitSetLocal(slot). self:emitPop.
        self:withStack:add([slot, res:at(#2)]).
        added := added:add(#1).
        more := self:acceptPunct(",") }).

    self:expect("do").
    self:statement.

    added:repeat({
        self:withStack:removeLast.
        self:scratchDepth := self:scratchDepth:sub(#2) }).
    nil }.

; **The selector is evaluated once**, which the standard requires and a chain of
; comparisons would otherwise get wrong. It goes into a slot and every arm reads
; it from there.
;
; ISO 7185 has no `else` here and says an unmatched value is an error. `fpc`
; lets it fall through, and so does this -- recorded in PASCAL.md rather than
; being the one place the two disagree by accident.
pas:caseStatement := { | t, slot, ends, matches, skip, c, over, more, moreConsts |
    self:scratchDepth := self:scratchDepth:add(#2).
    t := self:expression.
    isOrdinal:value(t):ifFalse({ self:fail("'case' wants an ordinal") }).
    slot := self:scratchSlot(#1).
    self:emitSetLocal(slot). self:emitPop.
    self:expect("of").

    ends := array:new.
    more := true.
    { more }:whileTrue({
        matches := array:new.
        moreConsts := true.
        { moreConsts }:whileTrue({
            c := self:constValue.
            self:wantSame(t, c:at(#1), "case").
            self:emitLocal(slot).
            self:emitValue(c:at(#1), c:at(#2)).
            self:emitSend("equals", #1).
            over := self:emitJumpFalse("case").
            matches:add(self:emitJump).
            self:patch(over).
            moreConsts := self:acceptPunct(",") }).
        self:expectPunct(":").

        ; Nothing in the list matched: past this arm and on to the next.
        skip := self:emitJump.
        matches:do({ m | self:patch(m) }).
        self:statement.
        ends:add(self:emitJump).
        self:patch(skip).

        more := self:acceptPunct(";").
        more:ifTrue({ self:isName("end"):ifTrue({ more := false }) }) }).

    self:expect("end").
    ends:do({ e | self:patch(e) }).
    self:scratchDepth := self:scratchDepth:sub(#2).
    nil }.

; **The limit is evaluated once**, which the standard requires, and the control
; variable is compared against it before the body -- so a range that is already
; empty runs no times.
;
; The step is guarded rather than tested afterwards: at the limit the loop
; leaves instead of incrementing, because incrementing past the end of a
; subrange or an enumeration is a value the type does not have.
pas:forStatement := { | name, target, t, slot, top, over, done, cont, up, got |
    name := self:expectName.
    target := self:lookupVar(name).
    target:isNil:ifTrue({
        self:fail("'{}' is not declared":fill([name])) }).
    t := target:at(#2).
    isOrdinal:value(t):ifFalse({
        self:fail("'for' wants an ordinal control variable") }).
    t:run:equals('boolean):ifTrue({
        self:fail("a boolean control variable is not in this stage") }).

    self:expectPunct(":=").
    got := self:expression.
    sameType:value(got, t):ifFalse({
        self:fail("'{}' is a {} and this is a {}"
            :fill([name, self:typeName(t), self:typeName(got)])) }).
    self:emitStoreVar(name, target).

    up := self:accept("to"):ifElse({ true }, { self:expect("downto"). false }).

    self:scratchDepth := self:scratchDepth:add(#2).
    slot := self:scratchSlot(#1).
    got := self:expression.
    sameType:value(got, t):ifFalse({
        self:fail("the limit of this 'for' is a {}":fill([self:typeName(got)])) }).
    self:emitSetLocal(slot). self:emitPop.
    self:expect("do").

    top := self:here.
    self:emitReadVar(name, target).
    self:emitLocal(slot).
    self:emitSend(up:ifElse({ "lessOrEqual" }, { "greaterOrEqual" }), #1).
    over := self:emitJumpFalse("for").

    self:statement.

    self:emitReadVar(name, target).
    self:emitLocal(slot).
    self:emitSend("equals", #1).
    cont := self:emitJumpFalse("for").
    done := self:emitJump.
    self:patch(cont).

    self:emitReadVar(name, target).
    self:emitStep(t, up:ifElse({ #1 }, { #-1 })).
    self:emitStoreVar(name, target).
    self:emitLoop(top).

    self:patch(over).
    self:patch(done).
    self:scratchDepth := self:scratchDepth:sub(#2).
    nil }.

pas:conditionFor := { what | | t |
    t := self:expression.
    t:run:equals('boolean):ifFalse({
        self:fail("'{}' wants a boolean and found a {}"
            :fill([what, self:typeName(t)])) }).
    nil }.

; Pascal's assignment compatibility: an integer may go into a real, a subrange
; stands for its base, and nothing else converts.
; A store through a designator: the container and the index are already on the
; stack when the value arrives, so the whole thing is one `atPut`.
pas:assignTo := { name | | res, mode, want, got |
    res := self:designator(name, true).
    mode := res:at(#1). want := res:at(#2).
    self:expectPunct(":=").
    want:kind:equals('set):ifTrue({ self:setHint := want }).
    got := self:expression.
    want:run:equals('real):and({ got:run:equals('integer) }):ifTrue({
        self:toReal(got). got := tReal }).
    sameType:value(got, want):ifFalse({
        self:fail("'{}' is a {} and this is a {}"
            :fill([name, self:typeName(want), self:typeName(got)])) }).
    isStructured:value(want):ifTrue({ self:emitCopyOf(want) }).
    mode:equals('whole):ifElse(
        { self:emitStoreVar(name, res:at(#3)) },
        { self:emitSend("atPut", #2). self:emitPop }).
    nil }.

pas:assignInto := { target, name | | want, got |
    want := target:at(#2).
    want:kind:equals('set):ifTrue({ self:setHint := want }).
    got := self:expression.
    want:run:equals('real):and({ got:run:equals('integer) }):ifTrue({
        self:toReal(got). got := tReal }).
    sameType:value(got, want):ifFalse({
        self:fail("'{}' is a {} and this is a {}"
            :fill([name, self:typeName(want), self:typeName(got)])) }).
    isStructured:value(want):ifTrue({ self:emitCopyOf(want) }).
    self:emitStoreVar(name, target).
    nil }.

pas:compound := {
    self:expect("begin").
    self:statement.
    { self:acceptPunct(";") }:whileTrue({ self:statement }).
    self:expect("end").
    nil }.

; ---------------------------------------------------------------------------
; Declarations
;
; The standard's order, and it is not a preference: `label`, `const`, `type`,
; `var`. Each section runs until a word that opens the next one, which is the
; only lookahead any of this needs because Pascal declares everything before it
; is used.

pas:sectionWords := ["label", "const", "type", "var", "begin",
                     "procedure", "function"].

pas:atSection := {
    self:kind:equals('name):and({ self:sectionWords:indexOf(self:text):notNil }) }.

; ---------------------------------------------------------------------------
; Making one
;
; **A loop, not an unrolled run of instructions**, because an array's size is a
; constant the compiler knows and a program is free to declare a thousand of
; something. The emitted code grows with how deeply a type nests and not with
; how big it is.

pas:emitArrayOf := { count, body | | a, i, top, over |
    self:scratchDepth := self:scratchDepth:add(#4).
    a := self:scratchSlot(#1).
    i := self:scratchSlot(#2).

    self:emitGlobal("array"). self:emitSend("new", #0).
    self:emitSetLocal(a). self:emitPop.
    self:emitInt(#0). self:emitSetLocal(i). self:emitPop.

    top := self:here.
    self:emitLocal(i). self:emitInt(count). self:emitSend("lessThan", #1).
    over := self:emitJumpFalse("array").

    self:emitLocal(a).
    body:value.
    self:emitSend("add", #1). self:emitPop.

    self:emitLocal(i). self:emitInt(#1). self:emitSend("add", #1).
    self:emitSetLocal(i). self:emitPop.
    self:emitLoop(top).
    self:patch(over).

    self:emitLocal(a).
    self:scratchDepth := self:scratchDepth:sub(#4).
    nil }.

pas:emitZeroOf := { t |
    t:kind:equals('set):ifElse({
        self:emitArrayOf(t:count, { self:emitBool(false) }) },

    { t:kind:equals('array):ifElse({
        self:emitArrayOf(t:count, { self:emitZeroOf(t:elem) }) },

    { t:kind:equals('record):ifElse({
        self:emitGlobal("array").
        t:fields:do({ f | self:emitZeroOf(f:at(#2)) }).
        self:emitSend("of", t:fields:size) },

      { t:run:equals('integer):ifTrue({ self:emitInt(#0) }).
        t:run:equals('real):ifTrue({ self:emitReal(0.0) }).
        t:run:equals('char):ifTrue({ self:emitString(" ") }).
        t:run:equals('boolean):ifTrue({ self:emitBool(false) }).
        t:run:equals('text):ifTrue({ self:emitString("") }) }) }) }).
    nil }.

; **Assigning a whole array or record copies it**, which the standard says and
; the machine does not: a Solum array is a reference, so assigning one without
; this would make two names for one thing. The copy is as deep as the type is,
; because a record of arrays is still one value in Pascal.
;
; Nothing is emitted for a simple type: an integer, a float, a string and a
; boolean are values on this machine and cannot be shared into.
pas:emitCopyOf := { t | | src, a, i, top, over |
    isStructured:value(t):ifTrue({
        self:scratchDepth := self:scratchDepth:add(#4).
        src := self:scratchSlot(#3).
        self:emitSetLocal(src). self:emitPop.

        t:kind:equals('record):ifElse({
            self:emitGlobal("array").
            t:fields:do({ f |
                self:emitLocal(src).
                self:emitInt(f:at(#3)).
                self:emitSend("at", #1).
                self:emitCopyOf(f:at(#2)) }).
            self:emitSend("of", t:fields:size) },

          { ; A set's members are booleans, so its copy is shallow by nature --
            ; the loop below reaches for `elem`, which a set has not got, so it
            ; is told to copy nothing.
            t:kind:equals('set):ifTrue({ t := t }).
            a := self:scratchSlot(#1).
            i := self:scratchSlot(#2).
            self:emitGlobal("array"). self:emitSend("new", #0).
            self:emitSetLocal(a). self:emitPop.
            self:emitInt(#0). self:emitSetLocal(i). self:emitPop.
            top := self:here.
            self:emitLocal(i). self:emitInt(t:count). self:emitSend("lessThan", #1).
            over := self:emitJumpFalse("array").
            self:emitLocal(a).
            self:emitLocal(src). self:emitLocal(i). self:emitInt(#1).
            self:emitSend("add", #1). self:emitSend("at", #1).
            t:elem:notNil:ifTrue({ self:emitCopyOf(t:elem) }).
            self:emitSend("add", #1). self:emitPop.
            self:emitLocal(i). self:emitInt(#1). self:emitSend("add", #1).
            self:emitSetLocal(i). self:emitPop.
            self:emitLoop(top).
            self:patch(over).
            self:emitLocal(a) }).
        self:scratchDepth := self:scratchDepth:sub(#4) }).
    nil }.

pas:typeDenoter := { | members, t, lo, hi, i, elem, indices, fields, offset, names |
    ; **A set is an array of booleans, one per member of its base type**, and
    ; not the array of bit-words this was planned as. The plan met
    ; [3.12](../docs/ROADMAP.md#312-no-shift-can-produce-a-negative-integer):
    ; `1 shiftLeft 63` overflows, because SolVM's integers are signed and there
    ; is no unsigned type to borrow -- so a 64-bit word would have to be a
    ; 63-bit word, or the top bit special-cased everywhere.
    ;
    ; A boolean each makes **membership one `at`**, which is the operation a
    ; program does most, and costs a `set of char` 256 booleans rather than four
    ; integers. That is the trade, taken deliberately.
    self:accept("set"):ifTrue({
        self:expect("of").
        t := self:typeDenoter.
        isOrdinal:value(t):and({ spanOf:value(t):notNil }):ifFalse({
            self:fail("a set is of an ordinal with known bounds") }).
        elem := makeType:value('set, 'set, "set of {}":fill([self:typeName(t)])).
        elem:base := t.
        elem:lo := originOf:value(t).
        elem:count := spanOf:value(t).
        nil }).

    self:accept("array"):ifTrue({
        self:expectPunct("[").
        indices := array:new.
        indices:add(self:typeDenoter).
        { self:acceptPunct(",") }:whileTrue({ indices:add(self:typeDenoter) }).
        self:expectPunct("]").
        self:expect("of").
        elem := self:typeDenoter.

        ; `array [a, b] of T` is `array [a] of array [b] of T`, which the
        ; standard says outright -- so the list is folded from the right.
        i := indices:size.
        { i:greaterOrEqual(#1) }:whileTrue({ | ix, made |
            ix := indices:at(i).
            isOrdinal:value(ix):and({ spanOf:value(ix):notNil }):ifFalse({
                self:fail("an array is indexed by an ordinal with known bounds") }).
            made := makeType:value('array, 'array, "").
            made:elem := elem.
            made:base := ix.
            made:lo := originOf:value(ix).
            made:count := spanOf:value(ix).
            made:name := "array of {}":fill([self:typeName(elem)]).
            elem := made.
            i := i:sub(#1) }).
        nil }).
    self:kind:equals('name):and({ self:text:equals("array") }):ifTrue({ nil }).

    ; The fold above leaves the finished type in `elem`; everything else is
    ; decided below.
    elem:notNil:ifElse({ elem },

    { self:accept("record"):ifElse({
        fields := array:new.
        offset := #1.
        { self:isName("end"):not }:whileTrue({
            names := array:new.
            names:add(self:expectName).
            { self:acceptPunct(",") }:whileTrue({ names:add(self:expectName) }).
            self:expectPunct(":").
            t := self:typeDenoter.
            names:do({ n |
                fields:do({ f | f:at(#1):equals(n):ifTrue({
                    self:fail("'{}' is a field twice":fill([n])) }) }).
                fields:add([n, t, offset]).
                offset := offset:add(#1) }).
            self:acceptPunct(";"):ifFalse({ nil }) }).
        self:expect("end").
        t := makeType:value('record, 'record, "record").
        t:fields := fields.
        t:count := fields:size.
        t },

    { self:acceptPunct("("):ifElse({
        members := array:new.
        members:add(self:expectName).
        { self:acceptPunct(",") }:whileTrue({ members:add(self:expectName) }).
        self:expectPunct(")").
        t := makeType:value('enum, 'integer, "").
        t:members := members.
        i := #0.
        members:do({ m |
            self:enumOf:includes(m):ifTrue({
                self:fail("'{}' is in two enumerations":fill([m])) }).
            self:enumOf:atPut(m, [t, i]).
            i := i:add(#1) }).
        t },

      { self:kind:equals('name):and({ self:types:includes(self:text) }):ifElse({
            self:types:at(self:expectName) },

          ; Anything else opens a subrange, and both ends are constants -- which
          ; is why `constValue` exists apart from `factor`.
          { lo := self:constValue.
            self:expectPunct("..").
            hi := self:constValue.
            self:wantSame(lo:at(#1), hi:at(#1), "..").
            isOrdinal:value(lo:at(#1)):ifFalse({
                self:fail("a subrange runs between ordinals") }).
            t := makeType:value('subrange, lo:at(#1):run, "").
            t:base := rootOf:value(lo:at(#1)).
            t:lo := lo:at(#2). t:hi := hi:at(#2).
            t:name := "{} .. {}":fill([lo:at(#2):asString, hi:at(#2):asString]).
            t }) }) }) }) }.

pas:constSection := { | name, pair |
    { self:kind:equals('name):and({ self:atSection:not }) }:whileTrue({
        name := self:expectName.
        self:expectPunct("=").
        pair := self:constValue.
        self:expectPunct(";").
        self:consts:includes(name):ifTrue({
            self:fail("'{}' is declared twice":fill([name])) }).
        self:consts:atPut(name, pair) }).
    nil }.

pas:typeSection := { | name, t |
    { self:kind:equals('name):and({ self:atSection:not }) }:whileTrue({
        name := self:expectName.
        self:expectPunct("=").
        t := self:typeDenoter.
        self:expectPunct(";").
        self:types:includes(name):ifTrue({
            self:fail("'{}' is declared twice":fill([name])) }).

        ; A type made here takes the name it was given, so a message about it
        ; says `Colour` rather than what it is underneath.
        t:name:size:equals(#0):ifTrue({ t:name := name }).
        self:types:atPut(name, t) }).
    nil }.

pas:declareVar := { name, type | | slot, entry |
    self:vars:includes(name):ifTrue({
        self:fail("'{}' is declared twice":fill([name])) }).
    slot := #0.
    self:level:greaterThan(#0):ifTrue({
        slot := self:slotNames:size.
        slot:greaterThan(#254):ifTrue({
            self:fail("too many variables in one procedure") }).
        self:slotNames:add(name) }).
    entry := [slot, type, self:level, self:nextVarId].
    self:vars:atPut(name, entry).

    ; **Every variable starts at nought**, which the standard does not promise
    ; and this machine cannot avoid: a slot that was never written holds nil,
    ; and nil understands nothing. So the zero is emitted rather than assumed.
    self:emitZeroOf(type).

    ; A boxed variable *is* the box, made once here, so that handing it to a
    ; `var` parameter hands over the storage rather than a copy of it.
    self:isBoxed(entry):ifTrue({ | zero |
        zero := self:scratchSlot(#1).
        self:emitSetLocal(zero). self:emitPop.
        self:emitGlobal("array").
        self:emitLocal(zero).
        self:emitSend("of", #1) }).

    self:emitAccess(name, entry, true).
    self:emitPop.
    nil }.

pas:varSection := { | names, type |
    { self:kind:equals('name):and({ self:atSection:not }) }:whileTrue({
        names := array:new.
        names:add(self:expectName).
        { self:acceptPunct(",") }:whileTrue({ names:add(self:expectName) }).
        self:expectPunct(":").
        type := self:typeDenoter.
        self:expectPunct(";").
        names:do({ n | self:declareVar(n, type) }) }).
    nil }.

; ---------------------------------------------------------------------------
; A program

pas:lineAt := #0.

pas:lineMark := { n | | grown |
    grown := self:here:sub(self:lineAt).
    grown:greaterThan(#0):ifTrue({
        self:lineRuns:add([grown, self:runLine]).
        self:lineAt := self:here }).
    self:runLine := n.
    nil }.

pas:program := { | pending |
    self:expect("program").
    self:expectName.
    self:acceptPunct("("):ifTrue({
        self:expectName.
        { self:acceptPunct(",") }:whileTrue({ self:expectName }).
        self:expectPunct(")") }).
    self:expectPunct(";").

    self:accept("label"):ifTrue({ self:labelDecl }).
    self:accept("const"):ifTrue({ self:constSection }).
    self:accept("type"):ifTrue({ self:typeSection }).
    self:accept("var"):ifTrue({ self:varSection }).

    { self:isName("procedure"):or({ self:isName("function") }) }:whileTrue({
        self:accept("procedure"):ifElse({ self:routineDecl(false) },
            { self:expect("function"). self:routineDecl(true) }) }).

    ; Scratch slots live above the variables, so their numbers are known only
    ; once the declarations are read -- which is why Pascal declaring first is
    ; a convenience to the compiler and not only to the reader.
    self:slotBase := self:slotNames:size.

    self:compound.
    self:expectPunct(".").

    ; A `goto` to a label nobody ever marked would otherwise be a jump with a
    ; blank offset, which is a file the verifier refuses without saying why.
    self:labels:keysAndValuesDo({ name, entry |
        entry:at(#2):size:greaterThan(#0):ifTrue({
            self:fail("label {} is jumped to and never marked":fill([name])) }) }).
    nil }.

; ---------------------------------------------------------------------------
; Units
;
; A procedure is compiled into a chunk of its own -- its own code, names,
; constants, slots and line runs -- which is nested inside the program's. So
; the emitter's whole state is put aside and a fresh one started, and `sola.sol`
; calls the same thing a unit for the same reason.

pas:unitStack := array:new.

pas:unitFields := ["code", "names", "nameIndex", "constants", "constIndex",
                   "lineRuns", "lineAt", "runLine", "slotNames", "vars",
                   "slotBase", "scratchDepth", "scratchMax", "methods",
                   "labels", "scope", "result"].

pas:pushUnit := { | saved |
    saved := dictionary:new.
    saved:atPut("code", self:code).             saved:atPut("names", self:names).
    saved:atPut("nameIndex", self:nameIndex).   saved:atPut("constants", self:constants).
    saved:atPut("constIndex", self:constIndex). saved:atPut("lineRuns", self:lineRuns).
    saved:atPut("lineAt", self:lineAt).         saved:atPut("runLine", self:runLine).
    saved:atPut("slotNames", self:slotNames).   saved:atPut("vars", self:vars).
    saved:atPut("slotBase", self:slotBase).
    saved:atPut("scratchDepth", self:scratchDepth).
    saved:atPut("scratchMax", self:scratchMax). saved:atPut("methods", self:methods).
    saved:atPut("labels", self:labels).         saved:atPut("scope", self:scope).
    saved:atPut("result", self:result).         saved:atPut("routines", self:routines).
    saved:atPut("level", self:level).
    saved:atPut("touchesHome", self:touchesHome).
    self:unitStack:add(saved).

    self:code := array:new.
    self:names := array:new.     self:nameIndex := dictionary:new.
    self:constants := array:new. self:constIndex := dictionary:new.
    self:lineRuns := array:new.  self:lineAt := #0. self:runLine := #1.
    self:slotNames := array:new. self:slotNames:add("").
    self:vars := dictionary:new.
    self:slotBase := #1.
    self:scratchDepth := #0. self:scratchMax := #0.
    self:methods := array:new.
    self:labels := dictionary:new.
    self:result := nil.
    self:routines := dictionary:new.
    self:level := self:level:add(#1).
    self:touchesHome := false.
    nil }.

pas:popUnit := { | saved |
    saved := self:unitStack:removeLast.
    self:code := saved:at("code").             self:names := saved:at("names").
    self:nameIndex := saved:at("nameIndex").   self:constants := saved:at("constants").
    self:constIndex := saved:at("constIndex"). self:lineRuns := saved:at("lineRuns").
    self:lineAt := saved:at("lineAt").         self:runLine := saved:at("runLine").
    self:slotNames := saved:at("slotNames").   self:vars := saved:at("vars").
    self:slotBase := saved:at("slotBase").
    self:scratchDepth := saved:at("scratchDepth").
    self:scratchMax := saved:at("scratchMax"). self:methods := saved:at("methods").
    self:labels := saved:at("labels").         self:scope := saved:at("scope").
    self:result := saved:at("result").         self:routines := saved:at("routines").
    self:level := saved:at("level").
    self:touchesHome := saved:at("touchesHome").
    nil }.

; **The line runs have to cover every byte of the chunk**, and a method's are
; closed here rather than by whoever finishes its body -- forgetting to is a
; file the verifier calls *internally inconsistent*, and the disassembler shows
; every instruction at line 0, which is the only visible sign of it.
pas:closeLines := {
    self:lineMark(self:runLine).
    self:lineAt:lessThan(self:here):ifTrue({
        self:lineRuns:add([self:here:sub(self:lineAt), self:runLine]) }).
    nil }.

; The scratch slots are appended last, their number being known only once the
; body is compiled.
pas:chunkOfUnit := { | chunk, i |
    self:closeLines.
    i := #0.
    { i:lessThan(self:scratchMax) }:whileTrue({
        self:slotNames:add("scratch"). i := i:add(#1) }).

    chunk := dictionary:new.
    chunk:atPut("slots", self:slotNames:size).
    chunk:atPut("names", self:names).
    chunk:atPut("constants", self:constants).
    chunk:atPut("code", self:code).
    chunk:atPut("lines", self:lineRuns).
    chunk:atPut("files", [self:path]).
    chunk:atPut("fileRuns", [[self:code:size, #0]]).
    chunk:atPut("slotNames", self:slotNames).
    chunk:atPut("methods", self:methods).
    chunk }.

; ---------------------------------------------------------------------------
; Procedures and functions
;
; A routine is a **block held in a global**, made with `OP_BLOCK` and stored
; under its own name. A call is that global, the arguments, and `value` -- so
; recursion needs nothing special: the body names the global, and the global is
; bound before anything runs it.
;
; `forward` needs nothing special either, for the same reason. The heading is
; registered before the body is compiled, so a call may be emitted long before
; there is anything to call.

pas:formalParams := { | out, isVar, names, t, more |
    out := array:new.
    more := true.
    { more }:whileTrue({
        isVar := self:accept("var").
        names := array:new.
        names:add(self:expectName).
        { self:acceptPunct(",") }:whileTrue({ names:add(self:expectName) }).
        self:expectPunct(":").
        t := self:typeDenoter.
        names:do({ n | out:add([n, t, isVar]) }).
        more := self:acceptPunct(";") }).
    self:expectPunct(")").
    out }.

pas:routineBody := { name, params, result, home | | method, index, slot |
    self:pushUnit.
    self:scope := name.

    ; Slot 0 of a block frame holds whatever the send put there, so parameters
    ; land in 1..arity exactly as a `value` lays them out.
    params:do({ p | | s, entry |
        s := self:slotNames:size.
        self:slotNames:add(p:at(#1)).
        entry := [s, p:at(#2), self:level, self:nextVarId].
        self:vars:atPut(p:at(#1), entry).
        p:at(#3):ifTrue({ self:markBoxed(entry) }) }).

    ; A function answers by assigning to its own name, so the name is a local
    ; and the body's last act is to push it.
    result:notNil:ifTrue({
        slot := self:slotNames:size.
        self:slotNames:add(name).
        self:vars:atPut(name, [slot, result, self:level, self:nextVarId]).
        self:result := slot }).

    self:accept("label"):ifTrue({ self:labelDecl }).
    self:accept("const"):ifTrue({ self:constSection }).
    self:accept("type"):ifTrue({ self:typeSection }).
    self:accept("var"):ifTrue({ self:varSection }).

    ; **Nested routines are declared here and live in slots of this frame**,
    ; which is what makes their `OP_OUTER` reach the right activation: a block
    ; captures the frame it was made in, and this one is made anew every time
    ; this procedure runs.
    { self:isName("procedure"):or({ self:isName("function") }) }:whileTrue({
        self:accept("procedure"):ifElse({ self:routineDecl(false) },
            { self:expect("function"). self:routineDecl(true) }) }).

    self:slotBase := self:slotNames:size.

    ; A **value** parameter that is itself handed on by reference has to become
    ; a box on entry; a `var` parameter arrives as one already.
    params:do({ p | | entry |
        entry := self:vars:at(p:at(#1)).
        p:at(#3):not:and({ self:isBoxed(entry) }):ifTrue({
            self:emitGlobal("array").
            self:emitLocal(entry:at(#1)).
            self:emitSend("of", #1).
            self:emitSetLocal(entry:at(#1)).
            self:emitPop }) }).

    result:notNil:ifTrue({
        self:emitZeroOf(result).
        self:emitSetLocal(self:result). self:emitPop }).

    self:compound.
    self:expectPunct(";").

    result:isNil:ifElse({ self:byte(NIL) }, { self:emitLocal(self:result) }).
    self:byte(RETURN).

    self:labels:keysAndValuesDo({ label, entry |
        entry:at(#2):size:greaterThan(#0):ifTrue({
            self:fail("label {} is jumped to and never marked":fill([label])) }) }).

    method := self:chunkOfUnit.
    method:atPut("name", name).
    method:atPut("arity", params:size).

    ; **Flag 1 says block and flag 2 says it reaches out of its own frame.**
    ; The C compiler decides the second by scanning its own code for `OP_OUTER`;
    ; here it is noticed as the instruction is emitted, which is the same
    ; question asked earlier. `sola.sol` has never set it -- SolaBasic has no
    ; nested procedures -- so a nested Pascal one is the first block this
    ; repository has produced that captures its home.
    method:atPut("flags", self:touchesHome:ifElse({ #3 }, { #1 })).
    self:popUnit.

    index := self:methods:size.
    self:methods:add(method).
    self:byte(BLOCK). self:u16(index).
    home:equals(#0):ifElse(
        { self:byte(SETGLOB). self:u16(self:nameFor(self:globalName(name))) },
        { self:emitSetLocal(home) }).
    self:emitPop.
    nil }.

pas:routineDecl := { isFunction | | name, params, result, sig, home |
    name := self:expectName.
    sig := self:routines:includes(name):ifElse({ self:routines:at(name) }, { nil }).

    params := array:new.
    result := nil.
    self:acceptPunct("("):ifElse({ params := self:formalParams },
        { sig:notNil:ifTrue({ params := sig:at(#1) }) }).
    isFunction:ifTrue({
        self:acceptPunct(":"):ifElse({ result := self:typeDenoter },
            { sig:notNil:ifTrue({ result := sig:at(#2) }) }).
        result:isNil:ifTrue({ self:fail("a function needs a result type") }) }).
    self:expectPunct(";").

    ; Registered **before** the body, which is the whole of what recursion needs
    ; and the whole of what `forward` needs.
    ;
    ; A routine written in the program is a global; one written inside another
    ; is a slot of that other's frame, made fresh on each of its activations.
    sig:isNil:ifTrue({
        home := #0.
        self:level:greaterThan(#0):ifTrue({
            home := self:slotNames:size.
            self:slotNames:add(name) }).
        self:routines:atPut(name, [params, result, false, self:level, home]) }).

    self:accept("forward"):ifElse({ self:expectPunct(";") },
      { self:routines:at(name):atPut(#3, true).
        self:routineBody(name, params, result,
                         self:routines:at(name):at(#5)) }).
    nil }.

pas:callRoutine := { name, asFunction | | sig, params, result, i, argName, entry, got, p |
    sig := self:lookupRoutine(name).
    params := sig:at(#1). result := sig:at(#2).

    asFunction:and({ result:isNil }):ifTrue({
        self:fail("'{}' is a procedure and has no value":fill([name])) }).
    asFunction:not:and({ result:notNil }):ifTrue({
        self:fail("'{}' is a function, so its value has to be used":fill([name])) }).

    ; The routine itself, reached the same way a variable at its level is.
    sig:at(#4):equals(#0):ifElse(
        { self:emitGlobal(self:globalName(name)) },
        { sig:at(#4):equals(self:level):ifElse(
            { self:emitLocal(sig:at(#5)) },
            { self:touchesHome := true.
              self:byte(OUTER).
              self:byte(self:level:sub(sig:at(#4))).
              self:byte(sig:at(#5)) }) }).

    params:size:greaterThan(#0):ifElse({
        self:expectPunct("(").
        i := #1.
        { i:lessOrEqual(params:size) }:whileTrue({
            i:greaterThan(#1):ifTrue({ self:expectPunct(",") }).
            p := params:at(i).

            p:at(#3):ifElse({
                ; **The box itself goes over**, so the callee's `atPut` writes
                ; the caller's storage and there is nothing to copy back -- and
                ; an expression has no box, which is why the standard says a
                ; `var` argument is a variable and not a value.
                self:kind:equals('name):ifFalse({
                    self:fail("a 'var' argument has to be a variable, and '{}' is not"
                        :fill([self:text])) }).
                argName := self:expectName.
                self:atSelector:ifTrue({
                    self:fail("an element or a field cannot be a 'var' argument in this stage") }).
                entry := self:lookupVar(argName).
                entry:isNil:ifTrue({
                    self:fail("a 'var' argument has to be a variable, and '{}' is not"
                        :fill([argName])) }).
                sameType:value(entry:at(#2), p:at(#2)):ifFalse({
                    self:fail("'{}' takes a {} here and '{}' is a {}"
                        :fill([name, self:typeName(p:at(#2)), argName,
                               self:typeName(entry:at(#2))])) }).
                self:markBoxed(entry).

                ; The box, not what is in it -- `emitAccess` stops short of the
                ; dereference that `emitReadVar` adds.
                self:emitAccess(argName, entry, false) },

              { p:at(#2):kind:equals('set):ifTrue({ self:setHint := p:at(#2) }).
                got := self:expression.
                p:at(#2):run:equals('real):and({ got:run:equals('integer) }):ifTrue({
                    self:toReal(got). got := tReal }).
                sameType:value(got, p:at(#2)):ifFalse({
                    self:fail("'{}' takes a {} here and this is a {}"
                        :fill([name, self:typeName(p:at(#2)),
                               self:typeName(got)])) }) }).
            i := i:add(#1) }).
        self:expectPunct(")") },

      { self:acceptPunct("("):ifTrue({ self:expectPunct(")") }) }).

    self:emitSend("value", params:size).
    result:isNil:ifElse({ tInteger }, { result }) }.

pas:parseOnce := { source | | i |
    self:src := source.
    self:pos := #1. self:line := #1.
    self:code := array:new.
    self:names := array:new. self:nameIndex := dictionary:new.
    self:constants := array:new. self:constIndex := dictionary:new.
    self:lineRuns := array:new. self:runLine := #1. self:lineAt := #0.
    self:slotNames := array:new. self:slotNames:add("").
    self:vars := dictionary:new.
    self:types := dictionary:new.
    self:consts := dictionary:new.
    self:enumOf := dictionary:new.
    self:labels := dictionary:new.
    self:routines := dictionary:new.
    self:methods := array:new.
    self:unitStack := array:new.
    self:scope := "".
    self:result := nil.
    self:level := #0.
    self:touchesHome := false.
    self:varId := #0.
    self:slotBase := #1.
    self:scratchDepth := #0. self:scratchMax := #0.

    self:types:atPut("integer", tInteger).
    self:types:atPut("real",    tReal).
    self:types:atPut("char",    tChar).
    self:types:atPut("boolean", tBoolean).

    self:next.
    self:program.
    self:lineMark(self:runLine).
    self:byte(HALT).
    nil }.

; **Twice, and the first answer is thrown away.** The reason is in the note
; above `boxed`: a variable read in one procedure may be handed to a `var`
; parameter by another one declared after it, and by then the read is already
; emitted. The first pass fills `boxed` and the second emits with it in hand.
;
; Both passes agree about everything else, so a program that compiles on the
; second compiled on the first -- and a program that fails, fails on the first
; with the same message.
pas:compile := { source, path |
    self:path := path.
    self:boxed := dictionary:new.

    self:pass := #1.
    self:parseOnce(source).

    self:pass := #2.
    self:parseOnce(source).

    self:chunkOfUnit }.

; ---------------------------------------------------------------------------
; Running it

compileFile := { inPath, outPath | | source, chunk |
    source := system:readFile(inPath).
    chunk := pas:compile(source, inPath).
    system:writeFile(outPath, sob:file(chunk)).
    "{} -> {}, {} bytes":fill([inPath, outPath,
        system:fileSize(outPath)]):display.
    "":display.
    "run it:  ./bin/solvm {}":fill([outPath]):display.
    "see it:  ./bin/solvm --dump {}":fill([outPath]):display.
    nil }.

; The demonstration, which every program in this directory has: a Pascal
; program carried here, compiled, and run, so that the compiler says something
; when it is given nothing.
demonstration := "program Demo(output);
var
  i, total : integer;
  average  : real;
  grew     : boolean;
  mark     : char;
begin
  total := 0;
  i := 1;
  while i <= 10 do
    begin
      total := total + i * i;
      i := i + 1
    end;
  writeln('sum of the first ten squares:', total:6);

  average := total / 10;
  writeln('the average:', average:9:2);

  grew := (total > 100) and not (total = 0);
  writeln('bigger than a hundred:', grew:7);

  mark := 'P';
  writeln('a letter:', mark:3);

  writeln(-7 div 2:6, -7 mod 2:6, 7 div 2:6);

  for i := 1 to 5 do write(sqr(i):5);
  writeln;

  case total mod 3 of
    0 : writeln('a multiple of three');
    1 : writeln('one more than a multiple of three');
    2 : writeln('two more than a multiple of three')
  end;

  if total > 300 then
    writeln('over three hundred')
  else
    writeln('not over three hundred')
end.
".

args := system:arguments.

args:size:equals(#0):ifTrue({ | chunk, out |
    "pascal.sol -- ISO 7185 Pascal to bytecode. Stage 1.":display.
    "":display.
    demonstration:display.
    out := "build/pascal-demo.sob".
    system:isDirectory("build"):ifFalse({ system:makeDirectory("build") }).
    chunk := pas:compile(demonstration, "demo.pas").
    system:writeFile(out, sob:file(chunk)).
    "-- compiled to {}, {} bytes. Running it:":fill([out,
        system:fileSize(out)]):display.
    "":display.
    system:run(["./bin/solvm", out]).
    nil }).

args:size:greaterOrEqual(#1):ifTrue({ | inPath, outPath |
    inPath := args:at(#1).
    outPath := args:size:greaterOrEqual(#2):ifElse({ args:at(#2) },
        { inPath:concat(".sob") }).
    { compileFile:value(inPath, outPath) }:onError({ e |
        e:message:display.
        system:exit(#1) }).
    nil }).
