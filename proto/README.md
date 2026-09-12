# Proto

A compiler whose syntax arrives with the file it is compiling. A module declares
its own grammar in its header, and that grammar holds for that file and no
other. What comes out is [Solveig](https://github.com/hansolovkarlsson/Solveig)
source, which `solas` turns into bytecode like any other.

```
@infix  +   60 add.
@infix  *   70 mul.
@prefix ~      not.

a := #2 + #3 * #4.
a:print.                          ; #14
```

```sh
make
bin/proto --map examples/vectors.pro      # -> examples/vectors.sol + .sol.map
../Solveig/bin/solas examples/vectors.sol
../Solveig/bin/solvm examples/vectors.sob
```

The three lines of header are the whole of that module's grammar. `*` binds
tighter than `+` because this file said 70 against 60, and nothing anywhere else
knows or cares. A second module in the same program may declare `+` to mean
something else entirely, or declare no operators at all — and then it reads as
Solveig does, in shape and nearly in full. Two differences are left of the nine
[POSTMORTEM.md](docs/POSTMORTEM.md) 16 found, and neither is an oversight: no
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
| [`lib/clike.pro`](lib/clike.pro) | the dialect they used, and each thing it cannot do explained where it is declared |
| [`examples/clike.pro`](examples/clike.pro) | that dialect used: a whole program, header to result, in forty-five lines |
| [`docs/REFERENCE.md`](docs/REFERENCE.md) | every directive, hole kind and shipped dialect: the page to look things up in |

**Then [Solveig's reference](https://hansolovkarlsson.github.io/Solveig/docs/REFERENCE.html)
for the library**, which this repository documents nowhere and does not intend
to. A dialect gives you syntax and Solveig gives you the messages; `@use`
reaches the first and `@include` the second, and neither reaches the other.
That line is in REFERENCE.md because the second reader got the whole notation
right and then spent every remaining cycle on the wrong side of it.

> **A front page is where somebody decides whether to try a language. It is not
> where they learn it.** What follows is the case for the idea, at length. The
> three files above are the language.

[docs/second-reader.md](docs/second-reader.md) is the measurement.

## Why it is not a folder inside Solveig

Solveig's `solveig-sdl` states the rule this repository follows, and states it
about itself:

> This is an *extension*, so it is not part of Solveig and does not build with
> it. That separation is the point rather than an inconvenience.

It applies here for one reason more than it applies there. **Proto's whole
claim is that a language is something a programmer writes on top of a substrate
they do not get to change.** A front end living two directories from the
compiler it targets would reach into that compiler, because it could — and would
then have proved only that Solveig's author can write a front end for Solveig.

So the build takes nothing from Solveig at all. No header, no archive, no symbol.
Proto emits text; `solas` reads text. **The coupling is a file format and a
command line, and it is the same surface anybody else would have.**

## What Proto is allowed to know about Solveig

Nothing that is not published.

`solas` exposes `sol_compile(const char *source, SolChunk *chunk)` — the parser
running straight into the emitter, one pass, no tree in between. That is a good
shape for a compiler with fixed syntax and the wrong one to hang a macro
expander off, because expansion and hygiene both want a tree and there is none
to borrow. **So Proto has its own**, which settles the question of what
Proto is: not a bolt-on to Solas, but a second compiler that happens to target
Solveig.

Given that, the output could have been a `SolChunk`, bypassing Solas entirely.
It is source text instead:

| | |
| --- | --- |
| **Source text**, then `solas` | Nothing to link. Nothing to keep in step with a Solveig release. `solid` and every existing tool still work, because what they are given is an ordinary `.sob` from an ordinary `.sol`. |
| **Bytecode**, bypassing `solas` | Independent of Solas, and pinned to Solum's instruction set and the `.sob` format instead. Reimplements what Solas already does well. |

The cost of the first is that the file `solas` reports an error in is not the
file anybody wrote. That is paid for once, by the map.

**What a program written in Proto emits is a different question**, and not one
Proto has an opinion about — a compiler written here can write machine code,
or a disk image, or nothing at all. [docs/targets.md](docs/targets.md) separates
the two.

## The map

`--map` writes `<output>.sol.map` beside the generated source: every position in
the generated file, against the position in the `.pro` that caused it.

```
# proto source map 1
# from examples/vectors.pro
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
diagnostics are the two things standing in front of it, so `tests/test_map.c`
checks that a column in the generated file names the token in the `.pro` that
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
[POSTMORTEM.md](docs/POSTMORTEM.md) 18 says why they were wrong and
[COMPLETED.md](docs/COMPLETED.md) 16 what it took. **`||` is two bars and not a
bar**, and a block wants a lone one everywhere it looks, so the pair could be
handed to dialects without the single one moving at all. **And since 0.14.0 the
single one may be declared too** — not as an operator character, but as the
token it already was, looked up by the parser. So the bitwise `or` is spelled
`|`, the way C spells it, and the logical one `||`, the way C spells that.
Solveig settles the same question the same way, and
[says so](https://hansolovkarlsson.github.io/Solveig/docs/GRAMMAR.html):
*ordered choice is what keeps that true*.

**What a module did not declare has no meaning in it.**

```
module.pro:5:14: error: '*' has no meaning in this module
 5 | a := #2 + #3 * #4.
   |              ^
module.pro:5:14: note: a module declares its operators in its header: @infix * <precedence> <message>.
```

An undeclared `+` quietly meaning `add` is the one convenience that would make
every dialect secretly the same dialect.

**The header comes before the code, and the compiler says so when it does not.**
A directive further down is the mistake worth naming precisely, because the file
looks right and the operator simply did not exist for the statements above it.

## A dialect is a file

```
; lib/control.pro
@use "arith.pro".

@syntax if <c> then <a>          => c:ifTrue({ a }).
@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).
@syntax while <t> do <b>         => { t }:whileTrue({ b }).
```

```
@use "../lib/control.pro".

if n > #10 then "over ten":print else "not over ten":print.
while i < n do (total := total + i. i := i + #1).
```

One line of header, and everything the body uses comes out of `lib/` —
`control.pro` in turn using `arith.pro`, so the chain is two deep.

**A dialect file holds directives and nothing else.** A statement in one is an
error. That is not a restriction so much as a division: **a dialect provides
syntax, and Solveig's own `@include` provides code**, so a dialect that wants
both ships a `.sol` beside itself and says so. There is no third thing for a
`.pro` to be.

**A `@use`d file is read into the header of the module using it**, rather than
compiled beside it. That is the rule the rest of this section follows from: it
is why a dialect file may hold no statements, why a diamond has to be read once,
and why two dialects declaring one operator collide in the file that used them
both rather than in either of themselves.

**It is looked for beside the file using it, then in each `-I` directory, then
in `PROTO_PATH`** — the order Solveig's `@include` uses, because a program
with its dialect in the same folder should not need a command line to say so.

**A diamond is read once.** Two dialects that both use a third meet it once, so
its declarations are not added twice and cannot collide with themselves. A file
still being read is a cycle, and says so with the chain that got there:

```
y.pro:1:1: error: 'x.pro' is already being read -- @use is a cycle
 1 | @use "x.pro".
   | ^^^^^^^^^^^^
  ... used from x.pro, line 1
  ... used from cyc.pro, line 2
```

## When two dialects collide

**Solveig has already answered this question**, for two files claiming one
global: the later one wins, and the compiler says so rather than letting it
pass. Proto follows it, and the four cases differ in *who could have known* —
which is the same distinction Solveig draws when it warns on a claim and not on
an update.

| | |
| --- | --- |
| Both in this module | **An error.** A module contradicting itself in eight lines of header is a mistake, not a choice. |
| This module over a `@use` | **Silent.** Deliberate, local, and both lines are in the file being edited. Overriding an imported operator is a thing a module is allowed to want. |
| A `@use` over this module | **A warning.** Almost certainly the `@use` wanting to be above the declaration rather than below it. |
| Two `@use`s | **A warning.** Neither author knew about the other, which is the case the rule exists for. |

```
b.pro:1:8: warning: operator '+' was already declared by a.pro -- this one wins, and nothing else will say so
 1 | @infix + 55 concat.
   |        ^
  ... used from p.pro, line 3
a.pro:1:1: note: declared here
```

**This is the decision the roadmap had been queuing everything behind**, and the
answer turned out to be *do what Solveig does*. A warning rather than an error
because rebinding is legal and sometimes meant; loud rather than silent because
nothing else will say so.

## An operator that stands for a template

```
@infix && 30 => left:and({ right }).

x > #1 && y > #0
```

becomes

```
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

**`&&` and `||`, which is where `lib/arith.pro` arrived rather than where it
started.** It declared `/\` and `\/` until 0.10.0, on the grounds that a file of
arithmetic and logic should read as logic. What overturned that was not taste:
`\/` was *also* how `examples/utf8.pro` and `programs/digest/sha2.pro` spelled a
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

```
@syntax unless(test, body) => test:not:ifTrue({ body }).

unless(x > #5, "small":print).
```

becomes

```
x:greaterThan(#5):not:ifTrue({ "small":print }).
```

The block around `"small":print` is the template's doing. Written as a method,
`unless` would need braces at every call and every call would be a chance to
forget one. That is the whole of what a form buys, and it is not a small thing:
`while`, in `examples/forms.pro`, is four words of declaration and turns two
sets of braces per loop into none.

**A form may read as a statement instead of as a call.**

```
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

```
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

`lib/clike.pro` is what this makes possible, and
[`examples/clike.pro`](examples/clike.pro) is a program that looks like C.

**A word in a pattern is not reserved anywhere else.** A module that never used
`control.pro` may call a variable `then`, and so may one that did.

## Two forms under one word

```
@syntax if <c> then <a>          => c:ifTrue({ a }).
@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).
```

Both are matched at once, and **no backtracking is needed or done.** A hole is
parsed once and shared by every candidate still standing, so two forms can only
part company at a *word* — and after the second hole above, one has ended and
the other wants `else`, so the next token settles it.

That works because the declaration refuses any pair that would have parted
company anywhere else:

```
on.pro:3:9: error: this cannot be told apart from the other 'on'
 3 | @syntax on error do <b> => b:run.
   |         ^^
on.pro:2:1: note: which has a hole where this has a word
```

`on error do x` is both of those. Preferring the literal word would be a rule,
and it would be a rule nobody could see from either declaration — so it is
refused at the second one, where somebody is looking at the first.

**A use that goes wrong says what it wanted**, with the declaration pointed at:

```
if.pro:5:6: error: expected 'then' here, in the form 'if'
 5 | if x "y":print.
   |      ^^^
```

## A hole may say what it accepts

```
@syntax swap <a: place> and <b: place> => { | t | t := a. a := b. b := t }:value.
```

```
p.pro:4:6: error: 'swap' wants a place here, and this is an integer
 4 | swap #1 and b.
   |      ^^
../lib/control.pro:33:1: note: 'a' is declared to want a place
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

```
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

```
@syntax swap(a, b) => { | t | t := a. a := b. b := t }:value.

t := #1.
u := #2.
swap(t, u).
```

becomes

```
{ | t__1 |
    t__1 := t.
    t := u.
    u := t__1 }:value.
```

Without the rename this compiles, runs, and leaves both variables where they
started — `t := a` writes over the caller's `t` before `a := b` can read it. So
`examples/forms.pro` demonstrates it by printing the two values rather than by
asserting anything: the wrong compiler produces a running program with the wrong
answer, which is exactly the failure hygiene exists to prevent.

**A generated name avoids every identifier in every file the module is made
of**, collected by lexing them rather than by walking the tree. A caller who
already has a `t__1` gets `t__2`; a template out of a `@use`d dialect brings
identifiers the module never mentions and they count too. After expansion no
identifier exists that was not either in that set or generated against it, which
is what makes *fresh* mean fresh rather than probably fresh.

**And a name a template reaches *out* for cannot be caught by its caller.**

```
@syntax bump(n) => total := total:add(n).

total := #0.
run := { | total | total := #100. bump(#5). total }.
```

`total` is not a parameter, so the form means the global. Written out literally
it lands inside a block whose temporary is also called `total`, and Solveig
resolves a bare name to a local before a global — so the form would update the
caller's variable and leave the global at `#0`. **Both numbers would be wrong
and neither would be an error.** `examples/forms.pro` prints them, because that
is what the failure looks like.

**The caller's local is what gives way**, renamed throughout its own frame:

```
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

```
outer.pro:5:7: error: this cannot be assigned to
 5 | outer(#5).
   |       ^^
outer.pro:3:21: note: in the expansion of 'bad', written here
 3 | @syntax outer(x) => bad(x).
   |                     ^^^
outer.pro:5:1: note: in the expansion of 'outer', written here
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
sends written another way. Proto is that ladder handed to the module.

## Three fields, and what each carries now

Every node in `proto/include/proto/tree.h` has them. Two were read by nothing
in 0.1.0 and are read by the expander in 0.2.0, which is what they were put there
for. They are there because each is impossible to add later
without touching every constructor and every rewrite in the compiler.

| | |
| --- | --- |
| `span` | Where in the **surface text** this came from. Read by every diagnostic and by the map. |
| `introduced_by` | For a node an expansion produced, the use that produced it. Walked by `proto_note_expansion` to print the trail above. |
| `scope` | The hygiene anchor: one scope per expansion, stamped on everything a template produced, `0` for what a person wrote. Both directions of capture are decided by comparing two of these. [Binding as sets of scopes](https://users.cs.utah.edu/plt/scope-sets/) (Flatt, 2016) is where it goes — a set rather than a number — when a dialect can be imported and a template can be defined somewhere other than the module using it. |

A tree without them is a tree that has to be rebuilt to get them, and the
expander was written in one sitting rather than three because it did not have to
be. **Hygiene in particular cannot be retrofitted**, which is the lesson every
macro system that tried has to teach — a system that expands without it grows
programs that depend on the capture, and those programs are what make it
impossible to add.

## Building

```sh
make            # -> bin/proto. Needs a C11 compiler and make, and nothing else.
make test       # the unit tests, and every example run through solas and solvm
make run        # examples/vectors.pro, compiled and executed
```

**The build needs no Solveig.** `make test`, `make run` and `make examples` do,
because they hand it a file — `SOLVEIG` defaults to `../Solveig` and the version
is checked rather than taken on trust:

```
proto: ../Solveig has not been built -- no bin/solas.
      make -C ../Solveig
```

**The examples are compiled and run, not just compiled.** A front end that emits
text can be wrong in a way no unit test sees: Solveig-looking source that
Solveig rejects, or accepts and reads differently. The only witness to that is
the real compiler, so `make test` runs both examples all the way down to SolVM.

## The five examples

| | |
| --- | --- |
| [`examples/vectors.pro`](examples/vectors.pro) | precedence, associativity, a prefix operator, and where a send binds against all of them |
| [`examples/utf8.pro`](examples/utf8.pro) | `integer:asUtf8` out of Solveig's own `lib/text.sol`, written in operators |
| [`examples/forms.pro`](examples/forms.pro) | `unless`, `while` and `swap` declared by the module, and hygiene demonstrated by running rather than by assertion |
| [`examples/dialect.pro`](examples/dialect.pro) | a two-line header, and everything the body reads coming out of `lib/` — with a diamond, read once |
| [`examples/clike.pro`](examples/clike.pro) | `while (n < #20) { … }`, `if (…) { … } else { … }`, `do { … } while (…)` — C's shape out of `lib/clike.pro`, and a note on the three things it cannot have |

The second one is the argument, and it is Solveig's argument rather than this
project's. The note at the top of `lib/text.sol` says the encoder was first
written with `div(#64)` for a shift and `mod(#64)` for a mask —

> exact, since the bits are disjoint by construction, and nothing like what it
> means. Reading it against the table in RFC 3629 meant translating every line.

Solveig's fix was to grow `shiftRight`, `bitAnd` and `bitOr`, which was right and
which went as far as a fixed syntax can go: the code names the operations now,
and still spells each one as a message send. Proto's version declares three
operators at the top of one file and costs the language nothing.

What comes out the other end is the library's own line back again:

```
integer:utf8Tail := { at |
    (#128:bitOr(self:shiftRight(at):bitAnd(#63))):asCharacter }.
```

## What 0.17.0 is not

**A pattern has no optional or repeated parts.** `if <c> then <a> else <b>` is a
second declaration rather than an optional tail, which is honest and costs a
line. Repetition — a form taking a list — has no spelling at all.

**A hole cannot ask for anything a look does not settle.** The five kinds are
all decided by inspecting what was parsed. A real guard — an arbitrary condition
— needs an evaluator, and Proto has none on purpose;
[docs/rules-and-logic.md](docs/rules-and-logic.md) prices it and says what rule
would have to be fixed first.

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
[ROADMAP.md](docs/ROADMAP.md) carries both measurements and the rule to settle
first.

**A wrong precedence is silent.** A module declares its own ladder, so there is
nothing for `@infix * 60` to be wrong against — it is as legal as `70` and means
something else. `programs/digest` declared `*` on `+`'s rung, compiled, ran, and
failed as an array index four calls deep in generated code. It is the operator
half's version of *choosing a form's shape wrongly is silent*, and it has the
same cause: both readings are legal.

**Hygiene is still one scope per expansion**, and a template declared in a
`@use`d file did not change that. 0.3.0 said one number would stop being enough
once a template could be declared outside the module using it; it turns out not
to, and the reason is Solveig's rather than Proto's. **Globals are one flat
namespace**, so a template's free `total` and a caller's global `total` are the
same variable by construction — there is no second one for a definition context
to have meant. A `scope` becomes a set the day the *substrate* has a module
system, not the day Proto does.

Known gaps, each for a reason rather than for lack of time:

| | |
| --- | --- |
| Temporaries in a group | `( \| t \| ... )` is Solveig's; Proto reads `( expr. expr )` and no temporaries. |
| `@expr` | Deliberately absent. It is the fixed form of what `@infix` generalises, and having both would be having two. |
| An installed dialect is not found on its own | `make install` puts `lib/*.pro` beside the binary and nothing looks there. `PROTO_PATH` is one line in a profile; Solveig's binaries are told their library path at build time and could be copied. |
| A `@use` path is shown as written | `examples/../lib/control.pro` is what a diagnostic shows, which is where somebody can look. Since 0.17.0 that is display only: identity is `realpath`, so two spellings of one file are one file. |
| Long send chains | A block that will not fit is broken across lines; a chain of sends that will not fit is not, yet. |

## The question that was open

**What stops two dialects' declarations from colliding when their code meets?**
Answered in 0.4.0, above. Racket answers it with modules and scoped bindings and
it was worth reading how — but the answer Proto took is Solveig's, because
Solveig had already made the choice for globals and a language should not hold
two philosophies about one question.

Every part of this repository that looked over-careful is why that answer was
cheap to give: the spans were already on the tree, so making them carry a file
was a field and not a rewrite; the map already existed, so it grew a column; the
expansion trail already walked a chain, so it learned to name a file.

**What is open now is smaller and more concrete.** A hole takes an expression
and cannot ask for anything else; a pattern has no optional or repeated parts.
Both are about what a form can *say* it wants, and both turn a strange expansion
into a diagnostic at the use — which is the same argument the spans and the
trail were built on, one level up.

**How far the rules could go, and where they stop**, is worked through in
[docs/rules-and-logic.md](docs/rules-and-logic.md): `@syntax` is already BNF with
most of EBNF missing and one thing refused, and refusing a rule that begins with
a nonterminal is what keeps the matcher from guessing. The same page prices
predicate logic, which turns out to be three questions wearing one name.

## The documents

| | |
| --- | --- |
| [does-it-pay.md](docs/does-it-pay.md) | what six programs and four strangers say about the question this project exists to answer |
| [REFERENCE.md](docs/REFERENCE.md) | every directive, hole kind and shipped dialect, and where everything lives — the page to look things up in |
| [what-is-proto.md](docs/what-is-proto.md) | how the parts fit together, kept as the five questions that were asked and answered |
| [pipeline.html](docs/pipeline.html) | the same path drawn — the pipeline, lockstep matching, expansion, and the map |
| [GRAMMAR.md](docs/GRAMMAR.md) | the core grammar, the tokens, and which shape a form should have |
| [ROADMAP.md](docs/ROADMAP.md) | what is outstanding, what is refused, and what a customer declined |
| [COMPLETED.md](docs/COMPLETED.md) | the case for each piece of work as it was argued *before* the work |
| [CHANGELOG.md](docs/CHANGELOG.md) | what landed, per version, with the commit |
| [POSTMORTEM.md](docs/POSTMORTEM.md) | every defect this project found in itself, and **what found it** |
| [journal.md](docs/journal.md) | what a day of work actually consisted of |
| [conventions.md](docs/conventions.md) | the standing agreements and the method |
| [targets.md](docs/targets.md) | what Proto targets, and what a program written in Proto targets |
| [rules-and-logic.md](docs/rules-and-logic.md) | how far the rules could go, where they stop, and predicate logic |
| [solveig-notes.md](docs/solveig-notes.md) | what Proto has found in Solveig, as a running log |

## The programs

**Six, and they are why several of the versions above exist.**

| | |
| --- | --- |
| [`programs/ember`](programs/ember) | a small language compiled to ARM64 assembly, all the way to a running binary. Found the gap that became 0.7.0. |
| [`programs/grammar`](programs/grammar) | a grammar toolkit. Declined the roadmap's repetition item with a reason. |
| [`programs/digest`](programs/digest) | SHA-256, agreeing with `shasum -a 256`. The first customer for the *operator* half, and the one that measured what a form costs at run time. |
| [`programs/ledger`](programs/ledger) | a statement in fixed-point decimal, against exact-decimal figures produced elsewhere. Found that Proto has one of Solveig's three integer literals, and that folding is worth 0.19% when the dialect is not in the loop. |
| [`programs/prose`](programs/prose) | a document written in its own dialect and rendered to text. Found that a form can contain content but not half a line, and that a document is a domain of steps like the other two. |
| [`programs/basic`](programs/basic) | a BASIC interpreter, with a prompt. The first program that is not a pass over its input, and the one that stated the ceiling: notation is fixed when a file is read, and an interpreter decides everything after that. |

Each carries a table of predictions recorded **before** it was written and a
*What it found* section written after. Predictions that were wrong stay in,
marked wrong.

## Licence

MIT, the same as Solveig.
