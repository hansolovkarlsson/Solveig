# The grammar of Solum

*The whole language on one page.
[solum.bnf](../programs/check_syntax/solum.bnf) is the same grammar in a form a
machine reads, and **that sentence is checked**: every production below is
compared against it character for character on each test run, and the two that
are prose rather than notation are named in the report rather than skipped
quietly. `solum.bnf` in turn is run against every `.sol` file in this repository
by [check_syntax](../programs/check_syntax.sol). So this page is held to the
grammar, and the grammar is held to the language.*

The notation is Wirth's, from *What can we do about the unnecessary diversity of
notation for syntactic definitions* (1977), and it is the notation the Pascal
report is written in:

| | |
| --- | --- |
| `a b` | `a` then `b` |
| `a \| b` | `a` or `b` |
| `[ a ]` | `a`, or nothing |
| `{ a }` | `a`, any number of times, including none |
| `( a )` | grouping |
| `"a"` | those characters, exactly |
| `"a" .. "z"` | one character between the two |
| `"\\"` | a backslash, inside a literal |
| `.` | ends a production |

---

## Words and numbers

```ebnf
identifier = letter { letter | digit } .

letter     = "a" .. "z" | "A" .. "Z" | "_" .
digit      = "0" .. "9" .
hexdigit   = digit | "a" .. "f" | "A" .. "F" .
bindigit   = "0" | "1" .

integer    = "#" [ "-" ] digit { digit }
           | "$" hexdigit { hexdigit }
           | "%" bindigit { bindigit } .

float      = digit { digit } [ "." digit { digit } ] [ exponent ] .
exponent   = ( "e" | "E" ) [ "+" | "-" ] digit { digit } .

string     = '"' { escape | any character but '"' } '"' .
escape     = "\\" ( '"' | "\\" | "n" | "t" | "r" ) .

symbol     = "'" letter { letter | digit } .

comment    = ";" { any character but a newline } .
```

**The tag is the whole difference between `45` and `#45`**, which are the same
characters with two readings. `$FF08` and `%10101100` are integers too, in the
base you are thinking in, and they take no tag and no sign: they are for looking
at bits, and there is no hexadecimal float to be told apart from.

**A leading `-` belongs to the number — outside a `@expr` region.** There the
scanner gives the sign to the literal, and a `-` with no digit after it is not a
token at all. Inside a region it is always the operator, and `-3` is the
operator applied to `3`, which the compiler folds back to the one constant.

**So this page reads `-3` as the operator everywhere**, which is why `float`
above has no sign in it. A lexical grammar has no regions to be inside of, and
the two readings agree on every value, so one grammar describes both. What it
costs is listed at the bottom with the other things the compiler refuses and
this page does not.

**`.` continues a number only when a digit follows it**, so `45.` is the float 45
and then a statement separator.

---

## Statements

```ebnf
program    = [ statement { "." statement } [ "." ] ] .

statement  = include | expression .

include    = "@include" string .
```

**`.` separates statements rather than terminating them** — required between
two, optional after the last. That is the rule in a file, in a block and in a
group alike. An empty file is a program.

**`@include` is the only directive, and the only statement that is not an
expression.** What it does happens while compiling, and there is nowhere inside
an expression to compile a file into.

---

## Expressions

```ebnf
expression = identifier ":=" expression
           | disjunction .

disjunction = conjunction { "|" conjunction } .
conjunction = negation { "&" negation } .
negation    = "~" negation | comparison .
comparison  = sum [ ( "<=" | "<>" | ">=" | "<" | ">" | "=" ) sum ] .
sum         = product { ( "+" | "-" ) product } .
product     = unary { ( "*" | "/" ) unary } .
unary       = "-" unary | power .
power       = ( call | primary ) { send } [ "^" unary ] .

call       = identifier "(" expression ")" .

send       = ":" identifier [ arguments | ":=" expression ] .

arguments  = "(" [ expression { "," expression } ] ")" .

primary    = identifier | integer | float | string | symbol
           | block | array | group | region .

region     = "@expr" ( "(" expression ")" | block ) .
```

**Sends chain left to right.** `a:add(#1):print` sends `print` to the sum, and
outside a `@expr` region there is no precedence to know, because there are no
operators to have any.

**A region opens with either delimiter**, and which one it is decides what it
answers rather than what it reads: `@expr(...)` answers the expression's value
and `@expr{...}` answers a block whose body is infix. That is the language's own
`(group)`/`{block}` pair, so `region` reaches `block` rather than repeating it.

**The ladder runs from `|` at the loosest to `^` at the tightest**, with `~`
between the logic and the comparisons — so `~a = b` is `~(a = b)`, which is what
the words say and what BASIC reads. C and Pascal both bind it tightest and would
have read `(~a) = b`. **Comparison does not chain**, and the
optional-rather-than-repeated tail of `comparison` is the whole of how that
is said: `a < b < c` would compare a boolean to `c`.

**`|` is the one operator the language already used.** A block's parameters and
a group's temporaries are matched before a body is, and ordered choice is what
keeps that true — so `{ a | b }` is still a block taking `a`, and `( a | b )` is
a disjunction because a group's temporaries have to come first and did not.

**The ladder is written once, at the top of `expression`.** That is not tidiness
— it is the rule. A region is *lexical*: it covers everything inside it, so an
argument, an array element, a group and a block body all read as infix within
one. A ladder every expression reaches is that rule with nothing duplicated.

**`^` groups to the right and binds tighter than the minus in front of it**, so
`-2^2` is `-(2^2)` and `2^3^2` is `2^(3^2)`. The other three group to the left,
the way they read.

**`sin(x)` is `x:sin`** — prefix application is a send to its argument, which is
the whole rule. The name is an `identifier` and not a word this page names, and
that is deliberate: a list of the mathematical functions would have had to be
written here as literals, and a checker that reserves every word-shaped literal
a rule mentions would then have taken `sin` and `cos` out of circulation as
ordinary names. **The reserved-word count stays at nought because the rule is
general.**

**Exactly one argument**, which is what leaves the rule with no exceptions. The
two-argument cases are the ones that would have needed them — `float:atan2` is
class-side, so `atan2(y, x)` could never have meant `y:atan2(x)`, and `pow`
already has `^` — and neither can enter a rule that has no two-argument form to
enter. `float:atan2(y, x)` is written out, as a term like any other.

**`:=` binds, and it appears in exactly two places.** After a bare identifier it
binds a name; after a send that took *no arguments* it binds a slot, which is
what makes `point:x := #3` and, when the value is a block, a method. After a send
that took arguments it is a syntax error — `o:at(#1) := #2` is not a way of
storing into a collection, and that is why the two possibilities are written
inside `send` rather than after the chain.

---

## Blocks, arrays and groups

```ebnf
block       = "{" [ parameters ] [ temporaries ] body "}" .

array       = "[" [ expression { "," expression } ] "]" .

group       = "(" [ temporaries ] expression { "." expression } [ "." ] ")" .

parameters  = identifier { "," identifier } "|" .
temporaries = "|" identifier { "," identifier } "|" .
body        = [ expression { "." expression } [ "." ] ] .
```

**The leading `|` of a temporary list is what tells the two apart:**

```
{ a | a }.              ; -- one parameter
{ | a | a }.            ; -- no parameters, one temporary
{ a | | t | t }.        ; -- one parameter and one temporary
{ a:print }.            ; -- neither: a body that happens to start with a name
```

It is also why parameters could not have reused the parenthesised form: `{ (a) }`
would be both a one-parameter block and a block answering the value of `a`.

**An array literal is sugar**, and for exactly one thing: `[a, b]` is
`array:of(a, b)`.

**A group holds at least one expression**, its value being the last one's, and it
may open with `| a, b |` — which is the only way to declare a temporary at the
top level of a script.

---

## What is not here, and why the page is this short

**There are no keywords.** Not a single one. `nil`, `true`, `object` and `self`
are ordinary identifiers that happen to be bound, and nothing above reserves a
word. A grammar-driven checker discovers this by having nothing to reserve.

**There is no control-flow syntax**, so no `if`, no `while`, no `for`, no
`return`, and no `else` to dangle. Those are messages taking blocks —
`ifTrue:`, `whileTrue:` — and the compiler inlines them to jumps when it can see
that is what they are. That is an optimisation and not a rule of the language:
the grammar above admits nothing about them, because there is nothing to admit.

**There are no operators outside `@expr`.** That sentence used to have no
qualifier, and losing it was the price of the one notation the language has for
arithmetic. What was bought is that a transcribed formula can be read against
the page it was copied from: a send chain runs left to right and precedence does
not, so `a^2 + 3*(sin(a/2) + sqrt(b))` written as sends puts its outermost
operation in the middle of the line.

**What did not change is the semantics.** Every operator lowers to the send it
reads as — `+` to `add`, `^` to `pow` — and the region emits the bytes the chain
would have emitted, which a test compares rather than takes on trust. That is
the rule an array literal already lives under: `[a, b]` is `array:of(a, b)`, and
two spellings of the same thing mean the same thing. `a:add(b)` is a send like
every other, and so is `@expr( a + b )`.

**Two things are refused by the compiler rather than by the grammar**, so a file
may match this page and still not compile:

| | |
| --- | --- |
| `self` outside a block | there is no receiver at the top level of a script |
| an escape that is not one of the five | `"\q"` scans as a string and is then refused |
| an operator, or `f(x)`, outside `@expr` | the ladder and `call` above are written once and reached everywhere, because a region is lexical; the compiler is what knows where one begins |
