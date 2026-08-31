# The core grammar

What Phoenix reads before a dialect has said anything. **A dialect cannot change
this**; it can only fill in the one hole marked below.

```ebnf
module      = { directive } { statement } .

directive   = "@language" identifier "."
            | "@use" string "."
            | "@infix"  operator number identifier "."
            | "@infixr" operator number identifier "."
            | "@prefix" operator identifier "."
            | "@syntax" identifier [ parameters | pattern ] "=>" expression "." .

parameters  = "(" [ identifier { "," identifier } ] ")" .
pattern     = { hole | identifier } .
hole        = "<" identifier ">" .

statement   = include | expression [ "." ] .
include     = "@include" string "." .

expression  = infix [ ":=" expression ] .

infix       = unary { operator unary } .          (* precedence: declared *)
unary       = operator unary | postfix .          (* prefix: declared     *)
postfix     = primary { ":" identifier [ arguments ] } .

arguments   = "(" [ expression { "," expression } ] ")" .

primary     = integer | float | string | symbol
            | form
            | identifier [ "(" expression ")" ]
            | group | array | block .

form        = identifier [ "(" [ expression { "," expression } ] ")" ]     (* a call    *)
            | identifier { expression | identifier } .                    (* a pattern *)

group       = "(" [ expression { "." expression } ] ")" .
array       = "[" [ expression { "," expression } ] "]" .
block       = "{" [ parameters ] [ temporaries ] body "}" .

parameters  = identifier { "," identifier } "|" .
temporaries = "|" identifier { "," identifier } "|" .
body        = [ expression { "." expression } [ "." ] ] .
```

**The holes are `infix`, `unary` and `form`.** Which spellings are operators,
what they group into and how tightly, and which names are forms, comes from the
module's own directives. Everything else on this page is the same for every
Phoenix file there will ever be.

**`form` is tried before prefix application**, and only for a name the header
has already declared. A name that is not a form is whatever Solveig says it is,
so `f(x)` is `x:f` until some line above it says otherwise.

**A pattern's shape comes from its declaration**, which is why `form` above
cannot say more than *expressions and identifiers in some order*: which
positions are holes and which are literal words is what `@syntax` settled. The
words in a pattern are not reserved -- `then` is a form's word in a file that
declared one and an ordinary name in every other, this one included.

**A statement separator is a `.` between two, optional after the last** — in a
file, in a block and in a group alike. That is Solveig's rule and Phoenix does
not have a second one.

## Tokens

| | |
| --- | --- |
| name | `[A-Za-z_][A-Za-z0-9_]*` |
| integer | `#` and then digits |
| float | digits, optionally a `.` and more digits |
| string | `"…"`, `\` escaping the next character |
| symbol | `'` and then a name |
| directive | `@` and then a name |
| operator | one or more of `+ - * / < > = ! & ^ % ~ ? \` |
| comment | `;` to the end of the line |

Everything but `operator` is Solveig's own spelling, so a file can be read by
somebody who knows Solveig without a second set of habits. **The header is where
the two are meant to differ, and nowhere else.**

**`|`, `:`, `.` and `,` are not operator characters and cannot become any.** `|`
is what tells a block's parameters from its body, and the rest are the core
syntax of a send, a statement and an argument list. A dialect gets the
characters that mean nothing until it says so — `\` is in the list for the
dialect that wants `\/` for an `or` it cannot spell `|`.

**Operator characters run together as far as they go.** `a<=b` is one operator
`<=` and not `<` then `=`, which is what lets a dialect declare `<=` without `<`
having to stop existing. `:=` is taken before any of this and is always itself.

## What a dialect file is

A `.phx` holding directives and nothing else, reached with `@use "name.phx".`
and read into the header of whoever used it. A statement in one is an error.

**A dialect provides syntax; Solveig's own `@include` provides code.** So there
is no third thing for a `.phx` to be, and a dialect that wants both ships a
`.sol` beside itself.

**Looked for beside the file using it, then in each `-I` directory, then in
`PHOENIX_PATH`** — the order `@include` uses over in Solveig.

**Read once.** Two dialects that both use a third meet it once, so a diamond
costs nothing and its declarations do not collide with themselves. A file still
being read is a cycle, and is an error rather than a silent stop: the silent
stop terminates and then reports the operators as undeclared, which is true and
no help at all.

**Nesting is limited to 64**, the depth Solveig allows an `@include`.

What happens when two of them declare one spelling is in the README, under *When
two dialects collide*.

## Patterns

**A pattern begins with a word and never has two holes in a row.** Both are
forced. A reader finds a form by seeing a name it knows, so a pattern beginning
with a hole would put it back to guessing; and two holes in a row have no
boundary between them for anything to find.

**Several forms may share a leading word**, and are matched together:

```
@syntax if <c> then <a>          => c:ifTrue({ a }).
@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).
```

**No backtracking, and none needed.** A hole is parsed once and shared by every
candidate still standing, so two forms can only part company at a word -- here,
after the second hole, where one has ended and the other wants `else`. Each step
either reads an expression or looks at one token.

**Which holds because the declaration refuses any pair that would part company
anywhere else.** Two forms under one word whose first difference is a hole
against a word cannot be told apart at all, and are an error at the second
declaration rather than a rule at every use.

**A name is either a call or patterns, never both.**

## What a form may reach

**A form's template is read under the header as it stood at its own line.** It
may use the operators declared above it and the forms declared above it, and it
cannot see what comes after — inside the header as much as after it, and across
a `@use` as much as within one file.

That is not a restriction for tidiness. **It is why expansion terminates.**
Expanding form N yields uses of forms below N, so the highest index strictly
falls and no form can reach itself, however the declarations are arranged. There
is no recursion to limit and no counter deciding when to give up.

**A template may not bind a name that is already one of its parameters.**

```
@syntax f(t) => { | t | t:add(#1) }.
```

The `t` inside is two things at once — the argument the caller passed, and the
block's own temporary — and no rule about which wins is a rule anybody should
have to know. Refused at the declaration, where the author is.

**Everything else a template binds is renamed at every expansion**, to a name
nothing in the module uses. See *Hygiene* in the README for what that does and
does not buy.

## What settles a block

The leading `|` of a temporary list, exactly as in Solveig:

```
{ a | a }.              ; -- one parameter
{ | a | a }.            ; -- no parameters, one temporary
{ a | | t | t }.        ; -- one parameter and one temporary
{ a:print }.            ; -- neither: a body that happens to start with a name
```

This is the one place the reader looks ahead, and it looks ahead over names and
commas only.

## Precedence against the core

A send binds tighter than any operator, and an assignment looser than all of
them. Neither is negotiable, because neither is an operator: `:` and `:=` are
core syntax and a dialect never sees them.

```
a := #1 + #2:negated       is    a := #1:add(#2:negated)
a := ~b + c                is    a := b:not:add(c)
```

So `#3 + #4:negated` is a sum whose second operand was negated, and a dialect
cannot make it anything else.
