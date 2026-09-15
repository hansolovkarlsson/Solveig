# Parasol

*The second compiler in this toolkit, and the case for it. Since 2026-09-15
this is a page of Solveig's documents rather than the front page of a
repository of its own; what it argues has not moved.*

A compiler whose syntax arrives with the file it is compiling. A module declares
its own grammar in its header, and that grammar holds for that file and no
other. What comes out is Solveig source, which `solas` turns into bytecode like
any other.

```parasol
@infix  +   60 add.
@infix  *   70 mul.
@prefix ~      not.

a := #2 + #3 * #4.
a:print.                          ; #14
```

```sh
make                                      # from Solveig's root, five binaries
bin/parasol --map examples/vectors.psol -o build/vectors.sol   # + build/vectors.sol.map
bin/solas build/vectors.sol
bin/solvm build/vectors.sob
```

Or the middle two as one, `bin/parasol --sob --map examples/vectors.psol -o
build/vectors.sob`, which writes the `.sol` beside the `.sob` and then runs
the `solas` beside itself. Same three files; see *What Parasol is allowed to
know about Solveig* for why that is a convenience and not a merger. Without
`-o` the files land beside the source, which is what a program of your own
wants and what this tree does not: `examples/` holds Solveig's `.sol` files
too, and a generated one beside them would be read as one of them by the
document checker. So `make` writes everything it generates under `build/`.

The three lines of header are the whole of that module's grammar. `*` binds
tighter than `+` because this file said 70 against 60, and nothing anywhere else
knows or cares. A second module in the same program may declare `+` to mean
something else entirely, or declare no operators at all — and then it reads as
Solveig does, in shape and nearly in full. Two differences are left of the nine
[POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) 16 found, and neither is an oversight: no
`@expr`, which is refused, and `-3`, which needs a declared prefix where
Solveig's scanner folds the sign into the number. **The second is forced rather
than missing** — a lexer cannot both read `-3` as a literal and let a dialect
declare `-`.

## Where to start

**Not here.** The first two readers who had never seen this language were put
in front of it, and neither opened this page: one grepped it after the fact, one
never opened it at all and volunteered that they had not. The third, on
2026-09-04, opened it first, met the two words above, and stopped reading, which
is the first time any part of this page has been shown to do a reader any good.
All three got a correct program on the first compile-and-run, out of files that
are not this one:

| | |
| --- | --- |
| [`lib/clike.psol`](../lib/clike.psol) | the dialect they used, and each thing it cannot do explained where it is declared |
| [`examples/clike.psol`](../examples/clike.psol) | that dialect used: a whole program, header to result, in forty-five lines |
| [`PARASOL-REFERENCE.md`](PARASOL-REFERENCE.md) | every directive, hole kind and shipped dialect: the page to look things up in |

**Then [Solveig's reference](REFERENCE.md) for the library**, which Parasol's
pages document nowhere and do not intend to. A dialect gives you syntax and Solveig gives you the messages; `@use`
reaches the first and `@include` the second, and neither reaches the other.
That line is in the reference because the second reader got the whole notation
right and then spent every remaining cycle on the wrong side of it.

> **A front page is where somebody decides whether to try a language. It is not
> where they learn it.** What follows is the case for the idea, at length. The
> three files above are the language.

[second-reader.md](PARASOL-SECOND-READER.md) is the measurement.

## Why it takes nothing from Solveig

Parasol was a repository of its own until 2026-09-12, on the rule Solveig's
`solveig-sdl` states about itself:

> This is an *extension*, so it is not part of Solveig and does not build with
> it. That separation is the point rather than an inconvenience.

It applied here for one reason more than it applies there. **Parasol's whole
claim is that a language is something a programmer writes on top of a substrate
they do not get to change.** A front end living two directories from the
compiler it targets would reach into that compiler, because it could, and would
then have proved only that Solveig's author can write a front end for Solveig.
It lives two directories from that compiler now, under `parasol/`, and the
separation the second repository kept by distance is kept by the build instead.

So the build takes nothing from Solveig at all. No header, no archive, no symbol.
Parasol emits text; `solas` reads text. **The coupling is a file format and a
command line, and it is the same surface anybody else would have.** Since
2026-09-14 the rules that build Parasol live in Solveig's own Makefile, in a
section of their own, and the claim is kept by the build rather than by a
separate file: every Parasol object is compiled with Parasol's include path
and no other, so a `#include "solum/..."` fails to compile; `bin/parasol` is
linked against `libparasol.a` and nothing else, so a `sol_*` reference fails
to link; and `make test` reads the binary's symbol table and refuses one that
exports any.

## What Parasol is allowed to know about Solveig

Nothing that is not published.

`solas` exposes `sol_compile(const char *source, SolChunk *chunk)` — the parser
running straight into the emitter, one pass, no tree in between. That is a good
shape for a compiler with fixed syntax and the wrong one to hang a macro
expander off, because expansion and hygiene both want a tree and there is none
to borrow. **So Parasol has its own**, which settles the question of what
Parasol is: not a bolt-on to Solas, but a second compiler that happens to target
Solveig.

Given that, the output could have been a `SolChunk`, bypassing Solas entirely.
It is source text instead:

| | |
| --- | --- |
| **Source text**, then `solas` | Nothing to link. Nothing to keep in step with a Solveig release. `solid` and every existing tool still work, because what they are given is an ordinary `.sob` from an ordinary `.sol`. |
| **Bytecode**, bypassing `solas` | Independent of Solas, and pinned to Solum's instruction set and the `.sob` format instead. Reimplements what Solas already does well. |

The cost of the first is that the file `solas` reports an error in is not the
file anybody wrote. That is paid for once, by the map.

**`--sob` is the first row, driven.** Since 2026-09-14 `parasol --sob` writes the
`.sol` and then *runs* `solas` on it, the one beside its own binary or else the
one on PATH, handing through `-o`, every `-I` and `--dump`, and never `--expr`.
One command from `.psol` to `.sob`, and the coupling is what it was: a file
format and a command line, with Parasol now the one typing the command. The
other way to get the same command, linking `libsol.a` and calling
`sol_compile_options` on the emitted text, is forty lines and was put aside on
2026-09-14 because it would have made the sentence above the table false, and
that sentence is the experiment. What the driver gets that a link could not is
also worth having: `solas` speaks on a pipe Parasol holds, so its diagnostics
could one day be read against the map and re-said in `.psol` lines, without
Solas hearing of it.

**What a program written in Parasol emits is a different question**, and not one
Parasol has an opinion about — a compiler written here can write machine code,
or a disk image, or nothing at all. [targets.md](PARASOL-TARGETS.md) separates
the two.

## The map

`--map` writes `<output>.sol.map` beside the generated source: every position in
the generated file, against the position in the `.psol` that caused it.

```text
# parasol source map 1
# from examples/vectors.psol
# to   examples/vectors.sol
#
# generated  source   offset
3:1  25:1  937
3:6  25:6  942
3:13  25:11  947
3:20  25:16  952
```

Plain text, because it has to be readable by `less` and diffable by `git` long
before anything reads it programmatically, and Source Map v3 is neither.

**This is written in the first commit rather than a later one, and it is tested
harder than anything else here.** A language whose syntax is declared per module
has one characteristic way of failing: somebody writes one thing, is shown an
error about another, and cannot get from the second back to the first. Every
macro system that became unusable became unusable that way. The map and the
diagnostics are the two things standing in front of it, so `tests/test_parasol_map.c`
checks that a column in the generated file names the token in the `.psol` that
put it there — including a column *inside* a token, which is what a number off a
stack trace actually is.

## The header is the grammar

| | |
| --- | --- |
| `@use "<file>".` | Read that dialect file's header into this module. |
| `@infix <op> <precedence> <message>.` | An infix operator, grouping to the left. Higher precedence binds tighter. |
| `@infix <op> <precedence> => <template>.` | The same, standing for a template rather than a message. The operands are `left` and `right`; a prefix operand is `operand`. |
| `@infixr <op> <precedence> <message>.` | The same, grouping to the right. |
| `@prefix <op> <message>.` | A prefix operator. Binds tighter than any infix and looser than a send. |
| `@syntax <name>(<params>) => <template>.` | A form that reads like a call. Its arguments arrive unevaluated, so the template may put them somewhere the caller never wrote. |
| `@syntax <name> <\<hole\>> <word> … => <template>.` | The same, reading like a statement. A hole may say what it accepts: `<a: place>`. |

An operator is written out of `+ - * / < > = ! & ^ % ~ ? \` , run together as far
as they go — so a dialect can declare `<=` without `<` having to stop existing.
`||` joins them as a token in its own right, taken before the bar.

**A lone `|` is not among the operator characters and cannot be** — one of
those runs together with its neighbours, and a `|` there would make `|=` a
spelling and `{ a | b }` a guess.

**It may be declared, though, and that is a different question.** A bar is a
token of its own, so `@infix | 40 bitOr.` asks the *parser* to look one up and
the lexer never has to. A block settles its parameters and its temporaries by a
bounded lookahead that consults no dialect, so `{ a | b }` is a parameter and a
body in every module there will ever be — and `{ (a) | b }` is the escape, one
bracket down, exactly as `#[(b = c) = d]` escapes the dictionary rule. Nine
versions of documents said this was impossible;
[POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) 18 says why they were wrong and
[COMPLETED.md](../parasol/docs/COMPLETED.md) 16 what it took. **`||` is two bars and not a
bar**, and a block wants a lone one everywhere it looks, so the pair could be
handed to dialects without the single one moving at all. **And since 0.14.0 the
single one may be declared too** — not as an operator character, but as the
token it already was, looked up by the parser. So the bitwise `or` is spelled
`|`, the way C spells it, and the logical one `||`, the way C spells that.
Solveig settles the same question the same way, and
[says so](GRAMMAR.md):
*ordered choice is what keeps that true*.

**What a module did not declare has no meaning in it.**

```text
module.psol:5:14: error: '*' has no meaning in this module
 5 | a := #2 + #3 * #4.
   |              ^
module.psol:5:14: note: a module declares its operators in its header: @infix * <precedence> <message>.
```

An undeclared `+` quietly meaning `add` is the one convenience that would make
every dialect secretly the same dialect.

**The header comes before the code, and the compiler says so when it does not.**
A directive further down is the mistake worth naming precisely, because the file
looks right and the operator simply did not exist for the statements above it.

## A dialect is a file

```parasol
; lib/control.psol
@use "arith.psol".

@syntax if <c> then <a>          => c:ifTrue({ a }).
@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).
@syntax while <t> do <b>         => { t }:whileTrue({ b }).
```

```parasol
@use "../lib/control.psol".

if n > #10 then "over ten":print else "not over ten":print.
while i < n do (total := total + i. i := i + #1).
```

One line of header, and everything the body uses comes out of `lib/` —
`control.psol` in turn using `arith.psol`, so the chain is two deep.

**A dialect file holds directives and nothing else.** A statement in one is an
error. That is not a restriction so much as a division: **a dialect provides
syntax, and Solveig's own `@include` provides code**, so a dialect that wants
both ships a `.sol` beside itself and says so. There is no third thing for a
`.psol` to be.

**A `@use`d file is read into the header of the module using it**, rather than
compiled beside it. That is the rule the rest of this section follows from: it
is why a dialect file may hold no statements, why a diamond has to be read once,
and why two dialects declaring one operator collide in the file that used them
both rather than in either of themselves.

**It is looked for beside the file using it, then in each `-I` directory, then
in `PARASOL_PATH`** — the order Solveig's `@include` uses, because a program
with its dialect in the same folder should not need a command line to say so.

**A diamond is read once.** Two dialects that both use a third meet it once, so
its declarations are not added twice and cannot collide with themselves. A file
still being read is a cycle, and says so with the chain that got there:

```text
y.psol:1:1: error: 'x.psol' is already being read -- @use is a cycle
 1 | @use "x.psol".
   | ^^^^^^^^^^^^
  ... used from x.psol, line 1
  ... used from cyc.psol, line 2
```

## When two dialects collide

**Solveig has already answered this question**, for two files claiming one
global: the later one wins, and the compiler says so rather than letting it
pass. Parasol follows it, and the four cases differ in *who could have known* —
which is the same distinction Solveig draws when it warns on a claim and not on
an update.

| | |
| --- | --- |
| Both in this module | **An error.** A module contradicting itself in eight lines of header is a mistake, not a choice. |
| This module over a `@use` | **Silent.** Deliberate, local, and both lines are in the file being edited. Overriding an imported operator is a thing a module is allowed to want. |
| A `@use` over this module | **A warning.** Almost certainly the `@use` wanting to be above the declaration rather than below it. |
| Two `@use`s | **A warning.** Neither author knew about the other, which is the case the rule exists for. |

```text
b.psol:1:8: warning: operator '+' was already declared by a.psol -- this one wins, and nothing else will say so
 1 | @infix + 55 concat.
   |        ^
  ... used from p.psol, line 3
a.psol:1:1: note: declared here
```

**This is the decision the roadmap had been queuing everything behind**, and the
answer turned out to be *do what Solveig does*. A warning rather than an error
because rebinding is legal and sometimes meant; loud rather than silent because
nothing else will say so.

## An operator that stands for a template

```text
@infix && 30 => left:and({ right }).

x > #1 && y > #0
```

becomes

```text
x:greaterThan(#1):and({ y:greaterThan(#0) })
```

**This exists because a message cannot express a short circuit.** Solveig's
`and` takes a *block*, so that its right-hand side is not evaluated unless it is
needed — and `@infix && 30 and` compiles to `a:and(b)`, which is refused at run
time. `@syntax` could not fill the gap either: **a pattern must begin with a
word**, and an infix operator begins with its left operand.

So the two extension points did not compose, and short-circuiting fell exactly
between them. `programs/ember` found it the hard way — six expressions in that
compiler were written `(a == b):and({ ... })` by hand, every one of them a
run-time failure first.

**An operator with a template *is* a form**, and gets everything a form gets:
substitution, hygiene, provenance, the expansion trail. The operands are called
`left` and `right` because an operator has exactly as many operands as it has,
so there is nothing to name.

**`&&` and `||`, which is where `lib/arith.psol` arrived rather than where it
started.** It declared `/\` and `\/` until 0.10.0, on the grounds that a file of
arithmetic and logic should read as logic. What overturned that was not taste:
`\/` was *also* how `examples/utf8.psol` and `programs/digest/sha2.psol` spelled a
**bitwise** or, and `~` was logical not in one file and bitwise not in another.
One spelling, two meanings, twice over.

The repository now spells one operation one way — `&&`, `||` and `!` logical,
`&`, `\`, `^` and `~` bitwise. That is C's table with a single substitution, and
the substitution is the interesting part: `\` stands where C writes `|`, which
is the one character a dialect can never have. **The irregularity is forced by
the design rather than chosen**, which is the best kind to be left with — it
points at the constraint instead of hiding it.

Nothing about the language changed. `/\` and `\/` lex and declare exactly as
they did, and a module that prefers them may still say so.

## Forms

**A form is not a method, and the difference is why it exists: its arguments
arrive unevaluated.**

```text
@syntax unless(test, body) => test:not:ifTrue({ body }).

unless(x > #5, "small":print).
```

becomes

```text
x:greaterThan(#5):not:ifTrue({ "small":print }).
```

The block around `"small":print` is the template's doing. Written as a method,
`unless` would need braces at every call and every call would be a chance to
forget one. That is the whole of what a form buys, and it is not a small thing:
`while`, in `examples/forms.psol`, is four words of declaration and turns two
sets of braces per loop into none.

**A form may read as a statement instead of as a call.**

```text
@syntax unless <test> then <body> => test:not:ifTrue({ body }).

unless x > #5 then "small":print.
```

Same holes, same template, same expansion — a pattern changes how a form is
written and nothing about what one is. A hole is `<name>` and everything else is
a literal word.

**A pattern begins with a word.** That one is forced: a reader finds a form by
seeing a name it knows, so a pattern starting with a hole would put it back to
guessing.

**Two holes may sit in a row when the second is a block.**

```text
@syntax if <c> <t: block>    => c:ifTrue(t).
@syntax while <c> <b: block> => { c }:whileTrue(b).

while (n < #20) { n = n + #1 }.
```

Until 0.8.0 that was refused, and the reason given was *no boundary between
them*, which was wrong — a block is a primary, consumed only where an operand
may start, so an expression always stops at the `{`. What the rule is really
about is **greed**: given `<a> <b>` and `f x + y`, the first hole takes the sum
and the second finds nothing, and the split is not where anybody would put it. A
delimited hole has no such problem, and a hole could not have said it was one
before 0.6.0 gave holes kinds.

`lib/clike.psol` is what this makes possible, and
[`examples/clike.psol`](../examples/clike.psol) is a program that looks like C.

**A word in a pattern is not reserved anywhere else.** A module that never used
`control.psol` may call a variable `then`, and so may one that did.

## Two forms under one word

```parasol
@syntax if <c> then <a>          => c:ifTrue({ a }).
@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).
```

Both are matched at once, and **no backtracking is needed or done.** A hole is
parsed once and shared by every candidate still standing, so two forms can only
part company at a *word* — and after the second hole above, one has ended and
the other wants `else`, so the next token settles it.

That works because the declaration refuses any pair that would have parted
company anywhere else:

```text
on.psol:3:9: error: this cannot be told apart from the other 'on'
 3 | @syntax on error do <b> => b:run.
   |         ^^
on.psol:2:1: note: which has a hole where this has a word
```

`on error do x` is both of those. Preferring the literal word would be a rule,
and it would be a rule nobody could see from either declaration — so it is
refused at the second one, where somebody is looking at the first.

**A use that goes wrong says what it wanted**, with the declaration pointed at:

```text
if.psol:5:6: error: expected 'then' here, in the form 'if'
 5 | if x "y":print.
   |      ^^^
```

## A hole may say what it accepts

```parasol
@syntax swap <a: place> and <b: place> => { | t | t := a. a := b. b := t }:value.
```

```text
p.psol:4:6: error: 'swap' wants a place here, and this is an integer
 4 | swap #1 and b.
   |      ^^
../lib/control.psol:33:1: note: 'a' is declared to want a place
```

Before this, `swap #1 and b` was `this cannot be assigned to` **after
expansion**, with a trail leading into somebody else's template. Now it names
the form, at the line somebody wrote, and points at the dialect file the hole
came from.

Five kinds, all decided by looking at what was parsed — so **none of them needs
an evaluator**, which is the whole reason they come before guards:
`expression` (the default), `name`, `literal`, `block`, `place`. Spelled the
same way in the call shape: `@syntax setTo(p: place, v) => …`.

**Saying nothing goes on meaning `expression`.** It had to: every dialect
written before kinds existed would otherwise break at once.

**Checked after the argument is expanded**, so a hole filled by another form is
checked against what that form *became*. `swap alias x and y` is a place if
`alias` makes one.

**A hole asks for what the template does not supply.** That is the rule, and it
is narrower than it first looked:

```parasol
@syntax while <t> do <b>            => { t }:whileTrue({ b }).
@syntax repeat <n> times <b: block> => n:repeat(b).
```

`while` puts the braces on itself, so `<b: block>` there would *refuse*
`while i < n do (total := total + i)` — the correct spelling. `repeat` hands its
hole straight through, so that one has to ask.

**A template is read under the header as it stood at its own line.** It may use
the operators and the forms declared above it and nothing after. That is not
tidiness — **it is why expansion terminates.** Expanding form N yields uses of
forms below N, the highest index strictly falls, and no form can reach itself
however the declarations are arranged. There is no recursion to limit.

## Hygiene

**A name a template binds cannot capture a name its caller passed it.**

```parasol
@syntax swap(a, b) => { | t | t := a. a := b. b := t }:value.

t := #1.
u := #2.
swap(t, u).
```

becomes

```text
{ | t__1 |
    t__1 := t.
    t := u.
    u := t__1 }:value.
```

Without the rename this compiles, runs, and leaves both variables where they
started — `t := a` writes over the caller's `t` before `a := b` can read it. So
`examples/forms.psol` demonstrates it by printing the two values rather than by
asserting anything: the wrong compiler produces a running program with the wrong
answer, which is exactly the failure hygiene exists to prevent.

**A generated name avoids every identifier in every file the module is made
of**, collected by lexing them rather than by walking the tree. A caller who
already has a `t__1` gets `t__2`; a template out of a `@use`d dialect brings
identifiers the module never mentions and they count too. After expansion no
identifier exists that was not either in that set or generated against it, which
is what makes *fresh* mean fresh rather than probably fresh.

**And a name a template reaches *out* for cannot be caught by its caller.**

```parasol
@syntax bump(n) => total := total:add(n).

total := #0.
run := { | total | total := #100. bump(#5). total }.
```

`total` is not a parameter, so the form means the global. Written out literally
it lands inside a block whose temporary is also called `total`, and Solveig
resolves a bare name to a local before a global — so the form would update the
caller's variable and leave the global at `#0`. **Both numbers would be wrong
and neither would be an error.** `examples/forms.psol` prints them, because that
is what the failure looks like.

**The caller's local is what gives way**, renamed throughout its own frame:

```text
total := #0.
run := { | total__1 |
    total__1 := #100.
    total := total:add(#5).
    total__1 }.
```

The template cannot be renamed — reaching the global is the whole of what it
meant — and renaming a local is invisible to everybody else, a local being a
thing no other frame can see.

**Solveig's own rule is what makes this one pass rather than a resolver.** Only
parameters and `| ... |` temporaries are locals and everything else is a global
in one flat namespace, so the frames are exactly the blocks, a frame's locals
are exactly its parameters and temporaries, and a name that is neither needs no
protecting: there is no second global called `total` a template could have meant
instead.

## When a form goes wrong

The characteristic failure of a macro system is an error about code nobody
wrote. Every node an expansion produces records the use that produced it, and a
diagnostic walks the chain:

```text
outer.psol:5:7: error: this cannot be assigned to
 5 | outer(#5).
   |       ^^
outer.psol:3:21: note: in the expansion of 'bad', written here
 3 | @syntax outer(x) => bad(x).
   |                     ^^^
outer.psol:5:1: note: in the expansion of 'outer', written here
 5 | outer(#5).
   | ^^^^^
```

**The caret is on the argument, because that is what the reader is looking at.**
The trail comes off the assignment, because the argument is the caller's own
code and knows nothing about how it got there — it is the template that put it
in a place a place has to be.

## Why operators came first

Because a precedence table composes and a grammar rule does not. **Adding an
operator cannot change what an expression that does not use it already meant.**
Adding a production can, silently, and two libraries that each add one can
collide in a way neither author can see — which is the open question at the
bottom of this page.

A form in 0.2.0 sidestepped that by being call-shaped: `name(args)` is a shape
the core grammar already had, so declaring one added a meaning without adding a
production. A pattern does add one — and it could wait until the collision rule
existed to say what happens when two files add the same one.

Solveig already has the fixed version of this. `@expr(a^2 + b/2)` opens a region
where a hard-coded ladder runs from `|` to `^`, and everything in it is the same
sends written another way. Parasol is that ladder handed to the module.

## Three fields, and what each carries now

Every node in `parasol/include/parasol/tree.h` has them. Two were read by nothing
in 0.1.0 and are read by the expander in 0.2.0, which is what they were put there
for. They are there because each is impossible to add later
without touching every constructor and every rewrite in the compiler.

| | |
| --- | --- |
| `span` | Where in the **surface text** this came from. Read by every diagnostic and by the map. |
| `introduced_by` | For a node an expansion produced, the use that produced it. Walked by `parasol_note_expansion` to print the trail above. |
| `scope` | The hygiene anchor: one scope per expansion, stamped on everything a template produced, `0` for what a person wrote. Both directions of capture are decided by comparing two of these. [Binding as sets of scopes](https://users.cs.utah.edu/plt/scope-sets/) (Flatt, 2016) is where it goes — a set rather than a number — when a dialect can be imported and a template can be defined somewhere other than the module using it. |

A tree without them is a tree that has to be rebuilt to get them, and the
expander was written in one sitting rather than three because it did not have to
be. **Hygiene in particular cannot be retrofitted**, which is the lesson every
macro system that tried has to teach — a system that expands without it grows
programs that depend on the capture, and those programs are what make it
impossible to add.

## How it works, as it was asked

Asked on 2026-09-02, with 0.9.0 in and three programs written, and kept **as
it was asked and answered** rather than rewritten, because the explanation
landed and nothing else was doing the same job: the grammar page says what the
syntax is, the roadmap says what is left, and neither says how the parts fit
together. It is a transcript, so it is in the first person and it is dated;
the paths in it are today's. Five questions were asked. The first, *what is
next?*, was a status answer at 0.9.0 whose items are on the roadmap, and the
four that explain the tool are here. The diagrams that came out of the last
question are in [PARASOL-PIPELINE.html](PARASOL-PIPELINE.html): the master
pipeline, lockstep pattern matching, where a span comes from during expansion,
and one generated line with two origins.

### 2 · How does it work?

> So exactly how does it work? Parasol runs the rules on the code and replaces the
> parts that matches?

Roughly yes — but the order matters, and it's the thing the design is built
around: **the rules don't scan finished code looking for matches. They change how
the file parses in the first place.**

#### The pipeline

`parasol/cmd/main.c:123-173`, in order:

1. **Read the header.** Every `@infix`/`@prefix`/`@syntax`/`@use` at the top of
   the file builds a `ParasolDialect` — a precedence table and a form table
   (`parasol/src/dialect.c`).
2. **Parse the body under that dialect.** The parser consults the table as it
   goes. `parasol/src/reader.c` has holes at exactly three places (`infix`,
   `unary`, `form` in `PARASOL-GRAMMAR.md`); everything else in the grammar is
   fixed for every `.psol` there will ever be.
3. **Expand.** The tree now has a `PARASOL_NODE_MACRO` at every use of a declared
   form. `parasol_expand` (`parasol/src/expand.c`) replaces each one with an instance
   of its template, in place.
4. **Emit Solveig source**, plus a `.sol.map`.

So the "matching" happens in step 2 — during parsing — and the "replacing" in
step 3, over a tree that already knows which declaration each use matched.
There's no rewrite-and-rescan loop over text.

#### How a use is recognised

Two mechanisms, and they're different:

**Operators** are just a precedence table. `@infix + 60 add.` means the `infix`
loop knows `+` binds at 60 and produces `a:add(b)`. Adding an operator can't
change what an expression without it already meant — that's why operators came
first.

**Forms** are names the header declared, and a declared form wins over anything
else the name could be (`reader.c:1022`). A name the header *didn't* declare is
whatever Solveig says it is — `f(x)` is `x:f` until some line above says
otherwise. Two shapes: a call `unless(test, body)`, or a pattern
`if <c> then <a>`.

Pattern matching is the interesting half. All the forms under one word are
matched **at once, in lockstep**, candidates dropping out as the tokens come in
(`reader.c:837-941`) — no backtracking. Two forms can only part company *on a
word*, which is why `if <c> then <a>` and `if <c> then <a> else <b>` coexist with
nothing declaring which is meant: after the second hole, the next token is either
`else` or it isn't. That single property is also why the roadmap's optional-parts
item insists an optional part must begin with a word.

#### What expansion actually does

Three things at once (`parasol/include/parasol/expand.h`), because doing any later
means redoing the others:

- **substitution** — the argument is copied in *keeping its own spans*, so an
  error inside an argument points at the argument, not the template;
- **hygiene** — every name the template binds is renamed to one nothing in the
  module uses;
- **provenance** — each produced node remembers the use that produced it, so a
  diagnostic can print the trail.

You can see all three in `examples/forms.psol` → `build/examples/forms.sol`:

```text
swap t and u          ->  { | t__1 | t__1 := t. t := u. u := t__1 }:value.
```

The template binds `t`; the caller also has a `t`. Without the rename that swap
loses a value instead of swapping.

And the reason a form isn't just a method: **its arguments arrive unevaluated.**
`unless(x > #5, y:print)` hands `y:print` over as *code*, and the braces in
`test:not:ifTrue({ body })` are the template's doing. A method can't do that —
which is exactly why `@infix && 30 and.` produces `a:and(b)` and a run-time
refusal, and templates exist.

#### Two properties that fall out

**Expansion terminates without a counter.** A template is read under the header
as it stood at its own line, so it can only mention forms declared above it — the
highest form index strictly falls. That's a property of reading the header top to
bottom, not a recursion limit bolted on.

**Parsing never runs anything.** A tool can read any `.psol` top to bottom and
know its syntax. That's the line [Parasol's roadmap](../parasol/docs/ROADMAP.md) refuses to cross ("Not
planned: a dialect that changes the lexer"), and it's the same rule constraining
the two open items I mentioned earlier — a guard must validate and not select,
and constant folding would mean evaluating a send at expand time.

---

### 3 · Would a different body language clash differently?

> So depending on what language is in the body, different pattern works better or
> worse dependig on what they define? For instance, the issue with | that we had
> in the past, which clashes with the syntax of Solveig. So if the body was a
> different programming language, then the clash might not happen with the |, say
> Pascal for instance?

Good question, and it splits into two very different ones. The short answer:
**the `|` clash is a property of the *reader*, not of the body language — so a
different object language changes nothing, and a different host language would
move the clash rather than remove it.**

#### Why `|` is reserved

Not because of anything the program is about. Parasol's fixed token set and core
grammar *are* Solveig's spelling, deliberately — `#3` for integers, `'sym` for
symbols, `x:msg` for sends, `{ }` for blocks, `.` between statements.
[PARASOL-GRAMMAR.md](PARASOL-GRAMMAR.md) puts it as: *everything but `operator` is Solveig's own
spelling, so a file can be read by somebody who knows Solveig without a second
set of habits.*

`|` is load-bearing in that grammar — it's what separates a block's parameters
from its body, and it brackets temporaries. So `|`, `:`, `.` and `,` are not
operator characters and cannot become any. A dialect gets the characters that
mean nothing until it says so, and that set (`+ - * / < > = ! & ^ % ~ ? \`) is
fixed by the lexer, which no `.psol` can change.

#### Reading 1: the body is a different language

This is `programs/ember` — a lexer, parser and **ARM64 code generator** written
in Parasol. It emits machine instructions, and that never touched Parasol's token set
once. Same with `programs/grammar`: EBNF rules live in a table as data, not as
forms.

The object language sits one level down, as data the program manipulates. It has
no vote on which characters Parasol's lexer reserves. So a Pascal compiler written
in Parasol would still not be able to declare `|`.

`programs/grammar` is actually the sharpest evidence here: it was written to
settle whether repeated pattern parts were needed, and the finding was that **a
grammar can't be written as forms at all** — a template can't declare a form — so
the repetition it wanted was in the object language, where Parasol's syntax doesn't
reach.

#### Reading 2: Parasol emits Pascal instead of Solveig

*Now* the question is real, and it's exactly the unbuilt half of `@language`.
[targets.md](PARASOL-TARGETS.md) notes the front end knows nothing about Solveig — the lexer,
dialect table, tree, spans and map are all substrate-agnostic, and
`parasol/src/emit.c` is the only file that has ever heard of Solveig. Replacing it
is a seam, not a rewrite.

But swapping *only* the emitter wouldn't free `|`, because `|` is the reader's
constraint, not the emitter's. You'd still be reading Solveig-shaped source and
writing Pascal out the back. That's precisely why targets.md says the growth is
for `@language` to choose **the reader *and* the emitter** — and why the roadmap
files it as a decision rather than a build.

If you did swap the reader for a Pascal-shaped one, then yes: `|` becomes free,
since Pascal doesn't use it. But the budget doesn't get bigger, it gets
redistributed. Pascal would reserve `;` as its separator, `..` for ranges,
`(* *)` for comments, and `^` for pointers — and `^` is currently a *free*
operator character a Parasol dialect can claim today. `..` would be worse than a
swap: `.` isn't an operator character, so a range operator would need a lexer
case rather than a declaration, which is the shape of the `@token` request that
was refused in 0.9.0.

#### The rule that survives both readings

Whatever the host, some characters are load-bearing for the reader and can't be
declarable — otherwise you're across the line where a tool has to run a file to
tokenise it, which is where Forth and TeX ended up.

Which is why the answer to the `|` want wasn't to make `|` claimable. It was
`||`: a new token taken by the lexer before the bar, belonging to every dialect
rather than to any declaration. Grow the fixed vocabulary rather than make the
vocabulary declarable — and the roadmap says explicitly that's the shape any
future version of that request should take.

---

### 4 · The process, end to end

> Explain to me the process and steps how Parasol works. I'm still confounded by
> how things tie together.

Let me trace one real file all the way through. I compiled this just now:

```text
; trace.psol
@language solveig.
@use "control.psol".

n := #3.
total := #0.
while n > #0 do (total := total + n. n := n - #1).
if total > #5 then total:print else "small":print.
```

#### Step 0 — a file is two halves

`module = { directive } { statement }`. Every `@`-directive comes first, then the
code. That split is the whole architecture: **the top of the file decides how the
bottom of it parses.** Nothing after the first statement can change the syntax.

(`@include` is the exception that proves it — it's Solveig's own directive, so
Parasol treats it as a *statement* and passes it through.)

#### Step 1 — gather the files

`parasol_unit_read` loads `trace.psol`. The `@use "control.psol"` pulls in
`lib/control.psol`, which itself does `@use "arith.psol"`. Each file is read
**once** — a diamond costs nothing — and they all live in one `ParasolUnit` with a
single shared offset space. That last detail matters in step 5.

A dialect file is directives and nothing else. A statement in one is an error.

#### Step 2 — the header builds two tables

Reading top to bottom, the directives fill a `ParasolDialect`:

| from | table | entry |
|---|---|---|
| `@infix + 60 add.` | precedence table | `+`, binds at 60, becomes `:add` |
| `@infix > 40 greaterThan.` | precedence table | `>`, binds at 40, becomes `:greaterThan` |
| `@syntax while <t> do <b> => { t }:whileTrue({ b }).` | form table | word `while`, holes `t` and `b`, plus the template |
| `@syntax if <c> then <a> => …` | form table | word `if`, two parts |
| `@syntax if <c> then <a> else <b> => …` | form table | word `if`, three parts |

Two `if` forms under one word, and nothing declares which is meant. That's fine,
and step 3 says why.

**These tables are all that varies.** Everything else — `#3`, `'sym`,
`x:msg(y)`, `{ }`, `.` between statements — is fixed for every `.psol` there will
ever be.

#### Step 3 — parse the body, consulting the tables

The parser has exactly three holes in it (`infix`, `unary`, `form`) and the
dialect fills them.

Hits `while`. The header declared it, and **a declared form beats anything else
that name could be** — otherwise `while` would just be an ordinary identifier.
Now it matches the pattern, and this is the part worth being precise about:

> All the forms under that word advance **in lockstep**, candidates dropping out
> as tokens arrive. No backtracking.

At `if`, both candidates are alive through `<c> then <a>`. Then one token
decides: `else` keeps the long form and kills the short one; anything else does
the reverse. That's why two forms can only part company *on a word* — and it's
why the roadmap's optional-parts item insists an optional part must begin with
one.

What comes out is a tree with an unexpanded `MACRO` node at each use, tagged with
which declaration matched. `n > #0` inside it is already parsed as
`n:greaterThan(#0)` — operators resolve here, in the same pass.

#### Step 4 — expand

`parasol_expand` replaces each `MACRO` with its template. Run `--tree` on that file
and you can see all three things it does at once:

```text
send whileTrue @1178+9 scope:1 from:while      <- template's span, in control.psol
  block @1172+1 scope:1 from:while
    send greaterThan @70+1                     <- argument's own span, in trace.psol
      name n @68+1
```

- **substitution** — `{ t }` became a block wrapping `n:greaterThan(#0)`, and
  that subtree kept offset `@70`, its position *in trace.psol*. An error inside an
  argument points at the argument, not at the library.
- **hygiene** — `scope:1` and `scope:2` are the two expansions. Any name the
  template binds gets renamed per scope; that's how `swap t and u` emits `t__1`
  instead of destroying the caller's `t`.
- **provenance** — `from:while` on every produced node, so a diagnostic can say
  which form you're inside and where it was written.

And it terminates without a counter: a template is read under the header **as it
stood at its own line**, so it can only mention forms declared above it. The
highest form index strictly falls. That's a consequence of reading the header top
to bottom, not a recursion limit.

#### Step 5 — emit, and the map

Only `parasol/src/emit.c` has ever heard of Solveig. It walks the expanded tree and
prints:

```text
n := #3.
total := #0.
{ n:greaterThan(#0) }:whileTrue({ (total := total:add(n). n := n:sub(#1)) }).
total:greaterThan(#5):ifElse({ total:print }, { "small":print }).
```

Alongside it, `--map` writes what those spans were for:

```text
5:1   24:40  1172  lib/control.psol     <- the whileTrue came from the template
5:3   6:7    68                        <- the condition came from your line 6
```

Generated line 5 has two origins on one line, and the map knows which is which.
**That's the payback for carrying spans through expansion** — without it,
generated code is where the trail goes cold.

Then Solveig takes over, and Parasol is done:

```sh
parasol trace.psol -o trace.sol --map
solas trace.sol -o trace.sob
solvm trace.sob
```

#### What ties it together

Three invariants, and every design decision on the roadmap is downstream of one
of them:

**The header is the only thing that varies, and it is read, never run.** Any tool
can tokenise and parse any `.psol` top to bottom. This is what the refused
`@token` directive would have cost, and it's why a guard must validate rather
than select — if a guard could *choose* a parse, reading a file would require
evaluating it.

**Matching happens while parsing, not afterwards.** There's no scan-and-rewrite
pass over finished code. That's what buys single-token decisions and no
backtracking — and what makes *choosing the wrong shape silent*, since a pattern
where a call was meant is also a legal parse.

**Expansion is one pass, and it carries the provenance out with it.** Hygiene
went in the same commit as forms rather than after, because a system that expands
without it grows programs that depend on the capture.

---

### 5 · Is it a precompiler?

> So is it fair to say that in a way Parasol is a very flexible and smart
> precompiler?

**"Smart precompiler" gets the position right and the mechanism wrong.** Parasol
does sit where a precompiler sits — runs before the real compiler, emits source,
never runs your program. But `cpp` and `m4` substitute over *tokens or text*,
with no grammar and no tree, which is why `cpp` can happily emit something that
won't parse. Parasol's matching happens *inside* the parser, and expansion operates
on a tree that already parsed. It's a **hygienic syntax-macro system whose
extension point is the grammar** — closer to `syntax-rules` or `macro_rules!`
than to `#define`. The line it deliberately won't cross is Lisp's: no code runs
at expand time.

|  | a preprocessor (cpp, m4) | Parasol |
| --- | --- | --- |
| operates on | tokens or text, with no grammar | a tree, matched inside the parser |
| bad output | can emit something that will not parse | cannot — expansion is over a parse that succeeded |
| capture | none; `SWAP` eats your `t` | every template-bound name renamed per expansion |
| positions | `#line`, by hand | a span on every node, and a map |
| extension point | a substitution | the grammar itself — precedence and pattern shape |

The nearer relatives are `syntax-rules`, `macro_rules!` and Dylan — hygienic
syntax macros. The line Parasol keeps that Lisp does not is that **nothing runs at
expand time**. A template is a pattern and a tree, never a computation. That
single restriction is what the two hardest open questions are both about:
whether a guard may evaluate anything (it may not, or parsing would depend on
running the file), and whether the expander may fold `#32:sub(#17)` when
`integer:sub` is a slot a program may reassign.

It is also worth saying that Parasol is not "very flexible" in the unbounded sense,
and that this is the point. The lexer is fixed, the core grammar is fixed, there
are three holes and no more, a rule may not begin with a nonterminal, and nothing
evaluates. The flexibility is inside a fence, and the fence is what lets any tool
read a `.psol` without running it.

---

## Building

From Solveig's root, since 2026-09-14, where the one Makefile is:

```sh
make            # bin/parasol beside Solveig's four; a C11 compiler and make, nothing else
make test       # Solveig's suite, then Parasol's: the unit tests, every example and
                # every program run through solas and solvm
make examples   # every example, Solveig's and Parasol's, to a .sob
make ember      # one program at a time: ember, grammar, digest, ledger, prose, basic, bignum
make sanitize   # the whole suite under AddressSanitizer and UBSan, from a clean build
```

**The build needs no Solveig.** `make test`, `make examples`, the program
targets and `parasol --sob` do, because each hands it a file, and the file
goes through the `solas` and `solvm` that the same `make` built. There is no
Makefile under `parasol/` any more; the section that builds Parasol in the
root's says why it takes nothing from the rest of that file, and how the
build enforces it.

**The examples are compiled and run, not just compiled.** A front end that emits
text can be wrong in a way no unit test sees: Solveig-looking source that
Solveig rejects, or accepts and reads differently. The only witness to that is
the real compiler, so `make test` runs both examples all the way down to SolVM.

## The five examples

| | |
| --- | --- |
| [`examples/vectors.psol`](../examples/vectors.psol) | precedence, associativity, a prefix operator, and where a send binds against all of them |
| [`examples/utf8.psol`](../examples/utf8.psol) | `integer:asUtf8` out of Solveig's own `lib/text.sol`, written in operators |
| [`examples/forms.psol`](../examples/forms.psol) | `unless`, `while` and `swap` declared by the module, and hygiene demonstrated by running rather than by assertion |
| [`examples/dialect.psol`](../examples/dialect.psol) | a two-line header, and everything the body reads coming out of `lib/` — with a diamond, read once |
| [`examples/clike.psol`](../examples/clike.psol) | `while (n < #20) { … }`, `if (…) { … } else { … }`, `do { … } while (…)` — C's shape out of `lib/clike.psol`, and a note on the three things it cannot have |

The second one is the argument, and it is Solveig's argument rather than this
project's. The note at the top of `lib/text.sol` says the encoder was first
written with `div(#64)` for a shift and `mod(#64)` for a mask —

> exact, since the bits are disjoint by construction, and nothing like what it
> means. Reading it against the table in RFC 3629 meant translating every line.

Solveig's fix was to grow `shiftRight`, `bitAnd` and `bitOr`, which was right and
which went as far as a fixed syntax can go: the code names the operations now,
and still spells each one as a message send. Parasol's version declares three
operators at the top of one file and costs the language nothing.

What comes out the other end is the library's own line back again:

```text
integer:utf8Tail := { at |
    (#128:bitOr(self:shiftRight(at):bitAnd(#63))):asCharacter }.
```

## What 0.17.0 is not

**A pattern has no optional or repeated parts.** `if <c> then <a> else <b>` is a
second declaration rather than an optional tail, which is honest and costs a
line. Repetition — a form taking a list — has no spelling at all.

**A hole cannot ask for anything a look does not settle.** The five kinds are
all decided by inspecting what was parsed. A real guard — an arbitrary condition
— needs an evaluator, and Parasol has none on purpose;
[rules-and-logic.md](PARASOL-RULES-AND-LOGIC.md) prices it and says what
rule would have to be fixed first.

**A form is not free at run time, and the number is known.** A template expands
rather than calls, so it should cost what writing the code out costs. It does
not, because nothing folds the constants the expansion introduces: measured on
`programs/digest`, a rotation declared as an operator saves 2.03 instructions by
not calling and spends 2.00 recomputing a `#32:sub(#17)`. **It gives back 98% of
what it saves.**

`programs/ledger` then measured the same shape at **0.19%**, because a dialect's
constants cost per *use* and that dialect's uses sit outside its loop. Two
numbers, and the second argues the first was not as large as it looked — so the
case for folding rests on the claim being made true rather than on the figure.
It would also need the expander to decide which sends are safe to evaluate,
which is the guard question one size smaller;
[ROADMAP.md](../parasol/docs/ROADMAP.md) carries both measurements and the rule
to settle first.

**A wrong precedence is silent.** A module declares its own ladder, so there is
nothing for `@infix * 60` to be wrong against — it is as legal as `70` and means
something else. `programs/digest` declared `*` on `+`'s rung, compiled, ran, and
failed as an array index four calls deep in generated code. It is the operator
half's version of *choosing a form's shape wrongly is silent*, and it has the
same cause: both readings are legal.

**Hygiene is still one scope per expansion**, and a template declared in a
`@use`d file did not change that. 0.3.0 said one number would stop being enough
once a template could be declared outside the module using it; it turns out not
to, and the reason is Solveig's rather than Parasol's. **Globals are one flat
namespace**, so a template's free `total` and a caller's global `total` are the
same variable by construction — there is no second one for a definition context
to have meant. A `scope` becomes a set the day the *substrate* has a module
system, not the day Parasol does.

Known gaps, each for a reason rather than for lack of time:

| | |
| --- | --- |
| Temporaries in a group | `( \| t \| ... )` is Solveig's; Parasol reads `( expr. expr )` and no temporaries. |
| `@expr` | Deliberately absent. It is the fixed form of what `@infix` generalises, and having both would be having two. |
| An installed dialect is not found on its own | `make install` puts `lib/*.psol` beside the binary and nothing looks there. `PARASOL_PATH` is one line in a profile; Solveig's binaries are told their library path at build time and could be copied. |
| A `@use` path is shown as written | `examples/../lib/control.psol` is what a diagnostic shows, which is where somebody can look. Since 0.17.0 that is display only: identity is `realpath`, so two spellings of one file are one file. |
| Long send chains | A block that will not fit is broken across lines; a chain of sends that will not fit is not, yet. |

## The question that was open

**What stops two dialects' declarations from colliding when their code meets?**
Answered in 0.4.0, above. Racket answers it with modules and scoped bindings and
it was worth reading how — but the answer Parasol took is Solveig's, because
Solveig had already made the choice for globals and a language should not hold
two philosophies about one question.

Every part of Parasol that looked over-careful is why that answer was
cheap to give: the spans were already on the tree, so making them carry a file
was a field and not a rewrite; the map already existed, so it grew a column; the
expansion trail already walked a chain, so it learned to name a file.

**What is open now is smaller and more concrete.** A hole takes an expression
and cannot ask for anything else; a pattern has no optional or repeated parts.
Both are about what a form can *say* it wants, and both turn a strange expansion
into a diagnostic at the use — which is the same argument the spans and the
trail were built on, one level up.

**How far the rules could go, and where they stop**, is worked through in
[rules-and-logic.md](PARASOL-RULES-AND-LOGIC.md): `@syntax` is already BNF with
most of EBNF missing and one thing refused, and refusing a rule that begins with
a nonterminal is what keeps the matcher from guessing. The same page prices
predicate logic, which turns out to be three questions wearing one name.

## The documents

Eight beside this one in `docs/`, since 2026-09-15; the five records still
under `parasol/docs/`, until the step that moves them.

| | |
| --- | --- |
| [PARASOL-REFERENCE.md](PARASOL-REFERENCE.md) | every directive, hole kind and shipped dialect, and where everything lives — the page to look things up in |
| [PARASOL-GRAMMAR.md](PARASOL-GRAMMAR.md) | the core grammar, the tokens, and which shape a form should have |
| [PARASOL-PIPELINE.html](PARASOL-PIPELINE.html) | the path through the compiler, drawn: the pipeline, lockstep matching, expansion, and the map |
| [PARASOL-DOES-IT-PAY.md](PARASOL-DOES-IT-PAY.md) | what seven programs and four strangers say about the question this project exists to answer |
| [PARASOL-SECOND-READER.md](PARASOL-SECOND-READER.md) | the measurement: what a stranger pays to read and write this |
| [PARASOL-TARGETS.md](PARASOL-TARGETS.md) | what Parasol targets, and what a program written in Parasol targets |
| [PARASOL-RULES-AND-LOGIC.md](PARASOL-RULES-AND-LOGIC.md) | how far the rules could go, where they stop, and predicate logic |
| [PARASOL-SOLVEIG-NOTES.md](PARASOL-SOLVEIG-NOTES.md) | what Parasol found in Solveig while it was outside; the log is closed and its open findings are on the roadmap |
| [method.md](method.md#what-came-in-from-parasols-conventionsmd-and-what-was-retired) | the standing agreements and the method, Parasol's folded into Solveig's |
| [ROADMAP.md](../parasol/docs/ROADMAP.md) | what is outstanding, what is refused, and what a customer declined |
| [COMPLETED.md](../parasol/docs/COMPLETED.md) | the case for each piece of work as it was argued *before* the work |
| [CHANGELOG.md](../parasol/docs/CHANGELOG.md) | what landed, per version, with the commit |
| [POSTMORTEM.md](../parasol/docs/POSTMORTEM.md) | every defect this project found in itself, and **what found it** |
| [journal.md](../parasol/docs/journal.md) | what a day of work actually consisted of |

## The programs

**Seven, and they are why several of the versions above exist.**

| | |
| --- | --- |
| [`programs/ember`](../programs/ember) | a small language compiled to ARM64 assembly, all the way to a running binary. Found the gap that became 0.7.0. |
| [`programs/grammar`](../programs/grammar) | a grammar toolkit. Declined the roadmap's repetition item with a reason. |
| [`programs/digest`](../programs/digest) | SHA-256, agreeing with `shasum -a 256`. The first customer for the *operator* half, and the one that measured what a form costs at run time. |
| [`programs/ledger`](../programs/ledger) | a statement in fixed-point decimal, against exact-decimal figures produced elsewhere. Found that Parasol has one of Solveig's three integer literals, and that folding is worth 0.19% when the dialect is not in the loop. |
| [`programs/prose`](../programs/prose) | a document written in its own dialect and rendered to text. Found that a form can contain content but not half a line, and that a document is a domain of steps like the other two. |
| [`programs/minibasic`](../programs/minibasic) | a BASIC interpreter, with a prompt. The first program that is not a pass over its input, and the one that stated the ceiling: notation is fixed when a file is read, and an interpreter decides everything after that. |
| [`programs/bignum`](../programs/bignum) | arbitrary-precision integers, checked against `bc`, in two modules that were meant to disagree about `+` and did not. Found that a dialect traps its scaffolding exactly when its values are the substrate's own, and that a large-number library is a library. |

Each carries a table of predictions recorded **before** it was written and a
*What it found* section written after. Predictions that were wrong stay in,
marked wrong.

## Licence

MIT, the same as Solveig.
