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
; **The subset is deliberate and is named here so nothing has to guess**: this
; parses statements, bindings, sends, parentheses, arrays and every literal.
; It does **not** yet parse blocks, temporaries or directives, which are the
; next stage's work and are where slot allocation and nested chunks come in.
; A construct it does not know is an error rather than a silence.
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
;   'array                         "elements"
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
; 18 levels ([3.5](../docs/ROADMAP.md#35-recursion-is-limited-to-about-62-levels)),
; and Solum source nests further than that in ordinary use. The recursion below
; is over *expressions*, which nest shallowly -- a send chain is a loop, not a
; recursion -- and the deep case, a block inside a block inside a block, is the
; one this subset does not do yet. When it does, it will carry an explicit stack
; the way `lib/html.sol` does.

parser:peek := { self:tokens:at(self:at) }.
parser:kind := { self:peek:at("type") }.
parser:line := { self:peek:at("line") }.
parser:text := { self:peek:at("text") }.
parser:step := { | t | t := self:peek. self:at := self:at:inc. t }.

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

parser:expression := { | node |
    node := self:primary.
    { self:kind:equals('colon) }:whileTrue({ node := self:sendOnto(node) }).
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
        self:kind:equals('rparen):ifFalse({
            args:add(self:expression).
            { self:kind:equals('comma) }:whileTrue({
                self:step.
                args:add(self:expression) }) }).
        self:expect('rparen, "')'")  }).
    node:atPut("arguments", args).
    node }.

; A literal, a name, a group, or an array.
parser:primary := { | kind, line, node |
    kind := self:kind.
    line := self:line.

    kind:equals('lparen):ifTrue({
        self:step.
        node := self:expression.
        self:expect('rparen, "')'").
        node := node }).

    node:isNil:ifTrue({
        kind:equals('lbracket):ifElse(
            { node := self:arrayLiteral },
            { ['int, 'float, 'string, 'symbol, 'ident]:indexOf(kind):isNil:ifElse(
                { self:fail("expected an expression") },
                { node := self:node(
                      kind:equals('ident):ifElse({ 'name }, { kind }), line).
                  node:atPut("text", self:step:at("text")) }) }) }).
    node }.

parser:arrayLiteral := { | node, elements |
    node := self:node('array, self:line).
    self:step.                                  ; the '['
    elements := array:new.
    self:kind:equals('rbracket):ifFalse({
        elements:add(self:expression).
        { self:kind:equals('comma) }:whileTrue({
            self:step.
            elements:add(self:expression) }) }).
    self:expect('rbracket, "']'").
    node:atPut("elements", elements).
    node }.

; ---------------------------------------------------------------------------
; A statement
;
; `name := expression` or an expression, and then a `.`. The binding is spotted
; by looking one token past an identifier, which is the only lookahead this
; grammar needs -- and it needs it only because `:=` is one token, which is
; itself why selectors have to be identifiers.

parser:statement := { | line, name, node |
    self:kind:equals('ident):and({
        self:tokens:at(self:at:inc):at("type"):equals('assign)
    }):ifElse(
        { line := self:line.
          name := self:step:at("text").
          self:step.                            ; the ':='
          node := self:node('bind, line).
          node:atPut("text", name).
          node:atPut("value", self:expression).
          node },
        { self:expression }) }.

; Every statement in the source, as an array. The `.` after the last one is
; required, as it is everywhere: this language terminates statements rather
; than separating them.
parser:statements := { source | | out |
    self:tokens := lexer:all(source).
    self:at := #1.
    out := array:new.
    { self:kind:equals('eof):not }:whileTrue({
        out:add(self:statement).
        self:expect('dot, "'.'") }).
    out }.

; The line the file ended on, which is the line the compiler puts its final
; instruction at.
parser:endLine := { self:tokens:last(#1):at(#1):at("line") }.
