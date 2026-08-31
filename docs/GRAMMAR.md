# The core grammar

What Phoenix reads before a dialect has said anything. **A dialect cannot change
this**; it can only fill in the one hole marked below.

```ebnf
module      = { directive } { statement } .

directive   = "@language" identifier "."
            | "@infix"  operator number identifier "."
            | "@infixr" operator number identifier "."
            | "@prefix" operator identifier "."
            | "@syntax" identifier [ parameters ] "=>" expression "." .

parameters  = "(" [ identifier { "," identifier } ] ")" .

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

form        = identifier [ "(" [ expression { "," expression } ] ")" ] .

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

## What a form may reach

**A form's template is read under the header as it stood at its own line.** It
may use the operators declared above it and the forms declared above it, and it
cannot see what comes after — inside the header as much as after it.

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
