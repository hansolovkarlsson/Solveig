; parser.sol -- Solum's grammar, parsed by Solum.
;
;     @include "parser.sol".
;     tree := parser:statements("a := #45. a:print.").
;
; Found on the search path, so no program has to say where this lives. See
; docs/REFERENCE.md#the-library.
;
; Stage 1 of [the self-hosting question](../docs/ideas.md#solas-written-in-solum--self-hosting),
; between [lexer.sol](lexer.sol) and [compile.sol](../programs/compile.sol).
; It includes the scanner, so a program wanting to parse asks only for this.
;
; **This parses the whole language**: statements, bindings, sends, parentheses,
; groups, arrays, blocks with their parameters and temporaries, slot assignment,
; `@include`, and every literal. A construct it does not know is an error rather
; than a silence.
;
; ---------------------------------------------------------------------------
; The shape of a node
;
; A dictionary with a `"kind"` symbol and a `"line"`, plus what that kind needs:
;
;   'int 'float 'string 'symbol   "text" -- the literal, undecoded
;   'name                          "text" -- an identifier being read
;   'bind                          "text", "value"
;   'send                          "receiver", "text", "arguments"
;   'slot                          "receiver", "text", "value" -- `a:b := c`
;   'array                         "elements"
;   'block                         "parameters", "temporaries", "body"
;   'group                         "temporaries", "body" -- `( | t | ... )`
;   'include                       "text" -- the file name, still in quotes
;
; There is no node for a parenthesised expression: brackets group and leave no
; trace, which is what design.md means by two spellings of the same thing being
; the same thing.

@include "lexer.sol".

parser := object:new.

parser:tokens := [].
parser:at := #1.

; ---------------------------------------------------------------------------
; The cursor over the tokens
;
; **Not a recursive-descent parser over characters**, which matters more here
; than it looks. A parser that recurses once per nesting level runs out at about
; 18 levels ([3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-254-levels)),
; and Solum source nests further than that in ordinary use. The recursion below
; is over *expressions*, which nest shallowly -- a send chain is a loop, not a
; recursion -- and the deep case, a block inside a block inside a block, is the
; one this subset does not do yet. When it does, it will carry an explicit stack
; the way `lib/html.sol` does.

parser:peek := { self:tokens:at(self:at) }.
parser:kind := { self:peek:at("type") }.
parser:line := { self:peek:at("line") }.
parser:text := { self:peek:at("text") }.
; The line of the token most recently consumed.
;
; **This is here because of how the C compiler numbers a line**: every byte it
; emits takes the line of the token it had just consumed, not the line the
; construct began on. For a one-line statement the two are the same, which is
; why the first version of this compiler matched `hello.sol` without knowing the
; difference. For a send whose arguments run over three lines they are not, and
; the whole file compares differently. So each node below records the line that
; was current when the instruction it stands for would have been emitted.
parser:previousLine := #1.

parser:step := { | t |
    t := self:peek.
    self:previousLine := t:at("line").
    self:at := self:at:inc.
    t }.

parser:fail := { message |
    error:raise("[line {}] {} at {}":fill([
        self:line,
        message,
        self:kind:equals('eof):ifElse(
            { "end of file" },
            { "'{}'":fill([self:text]) })])) }.

parser:expect := { kind, what |
    self:kind:equals(kind):ifFalse({ self:fail("expected {}":fill([what])) }).
    self:step }.

parser:node := { kind, line | | n |
    n := dictionary:new.
    n:atPut("kind", kind).
    n:atPut("line", line).
    n }.

; ---------------------------------------------------------------------------
; An expression
;
; One rule, and the whole of the grammar's shape: **a primary followed by any
; number of sends**. There is no precedence to get wrong because there are no
; operators -- `#2:add(#3):mul(#4)` is (2+3)*4 because it reads left to right,
; and the loop below is that reading.

; **A binding is an expression**, not a statement, which is easy to get the
; wrong way round -- and did get it wrong here, until a block body refused
; `t := x:add(a)`. It has to be an expression because a block body is a list of
; expressions and bindings appear in them; and because the value takes the whole
; of the rest, `a := #1:print` binds what `print` answered rather than sending
; `print` to what was bound.
parser:expression := { | node |
    self:kind:equals('ident):and({
        self:tokens:at(self:at:inc):at("type"):equals('assign)
    }):ifTrue({
        node := self:node('bind, self:line).
        node:atPut("text", self:step:at("text")).
        self:step.                              ; the ':='
        node:atPut("value", self:expression).
        node:atPut("emit", self:previousLine) }).

    node:isNil:ifTrue({
        node := self:primary.
        { self:kind:equals('colon) }:whileTrue({ node := self:sendOnto(node) }) }).
    node }.

parser:sendOnto := { receiver | | line, name, node, args |
    line := self:line.
    self:step.                                  ; the ':'
    name := self:expect('ident, "a message name"):at("text").
    node := self:node('send, line).
    node:atPut("receiver", receiver).
    node:atPut("text", name).

    args := array:new.
    self:kind:equals('lparen):ifTrue({
        self:step.
        ; The `(` is where an inlined conditional's first jump is emitted, so
        ; its line is worth keeping even though an ordinary send never reads it.
        node:atPut("lparenLine", self:previousLine).
        self:kind:equals('rparen):ifFalse({
            args:add(self:expression).
            { self:kind:equals('comma) }:whileTrue({
                self:step.
                args:add(self:expression) }) }).
        self:expect('rparen, "')'")  }).
    node:atPut("arguments", args).
    node:atPut("emit", self:previousLine).

    ; `a:b := c` binds a slot rather than sending. It is spotted here, after the
    ; send has been built, because it is only a binding when the send took no
    ; arguments -- the C compiler settles it the same way round, by emitting the
    ; send and then unemitting it.
    args:size:equals(#0):and({ self:kind:equals('assign) }):ifTrue({
        self:step.
        node:atPut("kind", 'slot).
        node:atPut("value", self:expression).
        node:atPut("emit", self:previousLine) }).
    node }.

; A literal, a name, a group, or an array.
parser:primary := { | kind, line, node |
    kind := self:kind.
    line := self:line.

    kind:equals('lparen):ifTrue({ node := self:group }).
    kind:equals('lbrace):ifTrue({ node := self:blockLiteral }).

    node:isNil:ifTrue({
        kind:equals('lbracket):ifElse(
            { node := self:arrayLiteral },
            { ['int, 'float, 'string, 'symbol, 'ident]:indexOf(kind):isNil:ifElse(
                { self:fail("expected an expression") },
                { node := self:node(
                      kind:equals('ident):ifElse({ 'name }, { kind }), line).
                  node:atPut("text", self:step:at("text")).
                  node:atPut("emit", line) }) }) }).
    node }.

; `( ... )` groups, and may open with `| a, b |` declaring temporaries of the
; frame it sits in -- not of a frame of its own, which is the whole difference
; between a group and a block.
parser:group := { | node |
    node := self:node('group, self:line).
    self:step.                                  ; the '('
    node:atPut("temporaries", self:declarations).
    node:atPut("body", self:body('rparen, "')'")).
    node }.

; `{ params | | temps | body }`.
parser:blockLiteral := { | node |
    node := self:node('block, self:line).
    self:step.                                  ; the '{'
    node:atPut("parameters", self:parameters).
    node:atPut("temporaries", self:declarations).
    node:atPut("body", self:body('rbrace, "'}'")).
    node:atPut("emit", self:previousLine).
    node }.

; `a, b |` is a parameter list and a bare `a` is a body, which takes looking
; past the identifiers to the `|`. The tokens are already an array, so this
; counts forward over a copy of the cursor rather than probing a second scanner
; the way the C does -- the one place having scanned everything first pays.
parser:parameters := { | at, names |
    names := array:new.
    self:kind:equals('ident):ifTrue({
        at := self:at.
        { self:tokens:at(at):at("type"):equals('ident):and({
              self:tokens:at(at:inc):at("type"):equals('comma) }) }
            :whileTrue({ at := at:add(#2) }).
        self:tokens:at(at):at("type"):equals('ident):and({
            self:tokens:at(at:inc):at("type"):equals('pipe)
        }):ifTrue({
            { self:kind:equals('ident) }:whileTrue({
                names:add(self:step:at("text")).
                self:kind:equals('comma):ifTrue({ self:step }) }).
            self:expect('pipe, "'|' after the block parameters") }) }).
    names }.

; `| a, b |` if it is there, and nothing if it is not.
parser:declarations := { | names |
    names := array:new.
    self:kind:equals('pipe):ifTrue({
        self:step.
        { self:kind:equals('ident) }:whileTrue({
            names:add(self:step:at("text")).
            self:kind:equals('comma):ifTrue({ self:step }) }).
        self:expect('pipe, "'|' to close the declarations") }).
    names }.

; The statements up to a closing bracket. A trailing `.` is allowed, and an
; empty body is allowed too -- it answers nil.
parser:body := { closer, what | | out, last |
    out := array:new.
    self:kind:equals(closer):ifFalse({
        last := self:expression.
        out:add(last).
        { self:kind:equals(closer):not }:whileTrue({
            self:expect('dot, "'.' between statements").
            ; The `.` is what the POP between two statements takes its line
            ; from, and a trailing one before the closing bracket emits nothing.
            last:atPut("dot", self:previousLine).
            self:kind:equals(closer):ifFalse({
                last := self:expression.
                out:add(last) }) }) }).
    self:expect(closer, what).
    out }.

parser:arrayLiteral := { | node, elements |
    node := self:node('array, self:line).
    self:step.                                  ; the '['
    node:atPut("openEmit", self:previousLine).
    elements := array:new.
    self:kind:equals('rbracket):ifFalse({
        elements:add(self:expression).
        { self:kind:equals('comma) }:whileTrue({
            self:step.
            elements:add(self:expression) }) }).
    self:expect('rbracket, "']'").
    node:atPut("elements", elements).
    node:atPut("emit", self:previousLine).
    node }.

; ---------------------------------------------------------------------------
; A statement
;
; An expression and then a `.`. There is nothing else: a binding is an
; expression, so this exists to be read rather than to do anything.

; A directive stands alone, and a statement is the only place one may stand --
; buried in an expression there would be nowhere for a compiled-in file to go.
parser:statement := { | node |
    self:kind:equals('directive):ifElse(
        { self:peek:at("text"):equals("@include"):ifFalse({
              self:fail("unknown directive") }).
          node := self:node('include, self:line).
          self:step.
          self:kind:equals('string):ifFalse({
              self:fail("@include needs a file name in quotes") }).
          node:atPut("text", self:step:at("text")).
          node },
        { self:expression }) }.

; Every statement in the source, as an array. The `.` after the last one is
; required, as it is everywhere: this language terminates statements rather
; than separating them.
parser:statements := { source | | out |
    self:tokens := lexer:all(source).
    self:at := #1.
    out := array:new.
    { self:kind:equals('eof):not }:whileTrue({ | s |
        s := self:statement.
        self:expect('dot, "'.'").
        s:atPut("dot", self:previousLine).
        out:add(s) }).
    out }.

; The line the file ended on, which is the line the compiler puts its final
; instruction at.
parser:endLine := { self:tokens:last(#1):at(#1):at("line") }.
