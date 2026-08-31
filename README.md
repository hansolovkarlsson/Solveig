# Phoenix

A compiler whose syntax arrives with the file it is compiling. A module declares
its own grammar in its header, and that grammar holds for that file and no
other. What comes out is [Solveig](https://github.com/hansolovkarlsson/Solveig)
source, which `solas` turns into bytecode like any other.

```
@language solveig.

@infix  +   60 add.
@infix  *   70 mul.
@prefix ~      not.

a := #2 + #3 * #4.
a:print.                          ; #14
```

```sh
make
bin/phoenix --map examples/vectors.phx      # -> examples/vectors.sol + .sol.map
../Solveig/bin/solas examples/vectors.sol
../Solveig/bin/solvm examples/vectors.sob
```

The five lines of header are the whole of that module's grammar. `*` binds
tighter than `+` because this file said 70 against 60, and nothing anywhere else
knows or cares. A second module in the same program may declare `+` to mean
something else entirely, or declare no operators at all and read exactly as
Solveig does today.

## Why it is not a folder inside Solveig

Solveig's `solveig-sdl` states the rule this repository follows, and states it
about itself:

> This is an *extension*, so it is not part of Solveig and does not build with
> it. That separation is the point rather than an inconvenience.

It applies here for one reason more than it applies there. **Phoenix's whole
claim is that a language is something a programmer writes on top of a substrate
they do not get to change.** A front end living two directories from the
compiler it targets would reach into that compiler, because it could — and would
then have proved only that Solveig's author can write a front end for Solveig.

So the build takes nothing from Solveig at all. No header, no archive, no symbol.
Phoenix emits text; `solas` reads text. **The coupling is a file format and a
command line, and it is the same surface anybody else would have.**

## What Phoenix is allowed to know about Solveig

Nothing that is not published.

`solas` exposes `sol_compile(const char *source, SolChunk *chunk)` — the parser
running straight into the emitter, one pass, no tree in between. That is a good
shape for a compiler with fixed syntax and the wrong one to hang a macro
expander off, because expansion and hygiene both want a tree and there is none
to borrow. **So Phoenix has its own**, which settles the question of what
Phoenix is: not a bolt-on to Solas, but a second compiler that happens to target
Solveig.

Given that, the output could have been a `SolChunk`, bypassing Solas entirely.
It is source text instead:

| | |
| --- | --- |
| **Source text**, then `solas` | Nothing to link. Nothing to keep in step with a Solveig release. `solid` and every existing tool still work, because what they are given is an ordinary `.sob` from an ordinary `.sol`. |
| **Bytecode**, bypassing `solas` | Independent of Solas, and pinned to Solum's instruction set and the `.sob` format instead. Reimplements what Solas already does well. |

The cost of the first is that the file `solas` reports an error in is not the
file anybody wrote. That is paid for once, by the map.

**What a program written in Phoenix emits is a different question**, and not one
Phoenix has an opinion about — a compiler written here can write machine code,
or a disk image, or nothing at all. [docs/targets.md](docs/targets.md) separates
the two.

## The map

`--map` writes `<output>.sol.map` beside the generated source: every position in
the generated file, against the position in the `.phx` that caused it.

```
# phoenix source map 1
# from examples/vectors.phx
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
checks that a column in the generated file names the token in the `.phx` that
put it there — including a column *inside* a token, which is what a number off a
stack trace actually is.

## The header is the grammar

| | |
| --- | --- |
| `@language <name>.` | What dialect this module is written in. Recorded and not yet acted on: there is one reader. |
| `@use "<file>".` | Read that dialect file's header into this module. |
| `@infix <op> <precedence> <message>.` | An infix operator, grouping to the left. Higher precedence binds tighter. |
| `@infixr <op> <precedence> <message>.` | The same, grouping to the right. |
| `@prefix <op> <message>.` | A prefix operator. Binds tighter than any infix and looser than a send. |
| `@syntax <name>(<params>) => <template>.` | A form. Its arguments arrive unevaluated, so the template may put them somewhere the caller never wrote. |

An operator is written out of `+ - * / < > = ! & ^ % ~ ? \` , run together as far
as they go — so a dialect can declare `<=` without `<` having to stop existing.

**`|` is not among them and cannot be.** It separates a block's parameters from
its body, and a dialect that could spell an operator `|` would be a dialect in
which `{ a | b }` has two readings. `\/` is there to be spent on the operator
that would have wanted it. Solveig settles the same question the same way, and
[says so](https://hansolovkarlsson.github.io/Solveig/docs/GRAMMAR.html):
*ordered choice is what keeps that true*.

**What a module did not declare has no meaning in it.**

```
module.phx:5:14: error: '*' has no meaning in this module
 5 | a := #2 + #3 * #4.
   |              ^
module.phx:5:14: note: a module declares its operators in its header: @infix * <precedence> <message>.
```

An undeclared `+` quietly meaning `add` is the one convenience that would make
every dialect secretly the same dialect.

**The header comes before the code, and the compiler says so when it does not.**
A directive further down is the mistake worth naming precisely, because the file
looks right and the operator simply did not exist for the statements above it.

## A dialect is a file

```
; lib/arith.phx
@infix  *   70 mul.
@infix  +   60 add.
@infix  <   40 lessThan.
@prefix ~      not.
```

```
@language solveig.
@use "../lib/control.phx".

unless(n > #10, "seven is not more than ten":print).
while(i < n, (total := total + i. i := i + #1)).
```

Two lines of header, and everything the body uses comes out of `lib/` —
`control.phx` in turn using `arith.phx`, so the chain is two deep.

**A dialect file holds directives and nothing else.** A statement in one is an
error. That is not a restriction so much as a division: **a dialect provides
syntax, and Solveig's own `@include` provides code**, so a dialect that wants
both ships a `.sol` beside itself and says so. There is no third thing for a
`.phx` to be.

**It is looked for beside the file using it, then in each `-I` directory, then
in `PHOENIX_PATH`** — the order Solveig's `@include` uses, because a program
with its dialect in the same folder should not need a command line to say so.

**A diamond is read once.** Two dialects that both use a third meet it once, so
its declarations are not added twice and cannot collide with themselves. A file
still being read is a cycle, and says so with the chain that got there:

```
y.phx:1:1: error: 'x.phx' is already being read -- @use is a cycle
 1 | @use "x.phx".
   | ^^^^^^^^^^^^
  ... used from x.phx, line 1
  ... used from cyc.phx, line 2
```

## When two dialects collide

**Solveig has already answered this question**, for two files claiming one
global: the later one wins, and the compiler says so rather than letting it
pass. Phoenix follows it, and the four cases differ in *who could have known* —
which is the same distinction Solveig draws when it warns on a claim and not on
an update.

| | |
| --- | --- |
| Both in this module | **An error.** A module contradicting itself in eight lines of header is a mistake, not a choice. |
| This module over a `@use` | **Silent.** Deliberate, local, and both lines are in the file being edited. Overriding an imported operator is a thing a module is allowed to want. |
| A `@use` over this module | **A warning.** Almost certainly the `@use` wanting to be above the declaration rather than below it. |
| Two `@use`s | **A warning.** Neither author knew about the other, which is the case the rule exists for. |

```
b.phx:1:8: warning: operator '+' was already declared by a.phx -- this one wins, and nothing else will say so
 1 | @infix + 55 concat.
   |        ^
  ... used from p.phx, line 3
a.phx:1:1: note: declared here
```

**This is the decision the roadmap had been queuing everything behind**, and the
answer turned out to be *do what Solveig does*. A warning rather than an error
because rebinding is legal and sometimes meant; loud rather than silent because
nothing else will say so.

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
`while`, in `examples/forms.phx`, is four words of declaration and turns two
sets of braces per loop into none.

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
`examples/forms.phx` demonstrates it by printing the two values rather than by
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
and neither would be an error.** `examples/forms.phx` prints them, because that
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
outer.phx:5:7: error: this cannot be assigned to
 5 | outer(#5).
   |       ^^
outer.phx:3:21: note: in the expansion of 'bad', written here
 3 | @syntax outer(x) => bad(x).
   |                     ^^^
outer.phx:5:1: note: in the expansion of 'outer', written here
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

A form sidesteps that for now by being call-shaped: `name(args)` is a shape the
core grammar already had, so declaring one adds a meaning without adding a
production. Richer surface patterns — a form that reads as `unless x then y` —
are the thing that needs the collision question answered first.

Solveig already has the fixed version of this. `@expr(a^2 + b/2)` opens a region
where a hard-coded ladder runs from `|` to `^`, and everything in it is the same
sends written another way. Phoenix is that ladder handed to the module.

## Three fields, and what each carries now

Every node in `phoenix/include/phoenix/tree.h` has them. Two were read by nothing
in 0.1.0 and are read by the expander in 0.2.0, which is what they were put there
for. They are there because each is impossible to add later
without touching every constructor and every rewrite in the compiler.

| | |
| --- | --- |
| `span` | Where in the **surface text** this came from. Read by every diagnostic and by the map. |
| `introduced_by` | For a node an expansion produced, the use that produced it. Walked by `phx_note_expansion` to print the trail above. |
| `scope` | The hygiene anchor: one scope per expansion, stamped on everything a template produced, `0` for what a person wrote. Both directions of capture are decided by comparing two of these. [Binding as sets of scopes](https://users.cs.utah.edu/plt/scope-sets/) (Flatt, 2016) is where it goes — a set rather than a number — when a dialect can be imported and a template can be defined somewhere other than the module using it. |

A tree without them is a tree that has to be rebuilt to get them, and the
expander was written in one sitting rather than three because it did not have to
be. **Hygiene in particular cannot be retrofitted**, which is the lesson every
macro system that tried has to teach — a system that expands without it grows
programs that depend on the capture, and those programs are what make it
impossible to add.

## Building

```sh
make            # -> bin/phoenix. Needs a C11 compiler and make, and nothing else.
make test       # the unit tests, and every example run through solas and solvm
make run        # examples/vectors.phx, compiled and executed
```

**The build needs no Solveig.** `make test`, `make run` and `make examples` do,
because they hand it a file — `SOLVEIG` defaults to `../Solveig` and the version
is checked rather than taken on trust:

```
phoenix: ../Solveig has not been built -- no bin/solas.
      make -C ../Solveig
```

**The examples are compiled and run, not just compiled.** A front end that emits
text can be wrong in a way no unit test sees: Solveig-looking source that
Solveig rejects, or accepts and reads differently. The only witness to that is
the real compiler, so `make test` runs both examples all the way down to SolVM.

## The four examples

| | |
| --- | --- |
| [`examples/vectors.phx`](examples/vectors.phx) | precedence, associativity, a prefix operator, and where a send binds against all of them |
| [`examples/utf8.phx`](examples/utf8.phx) | `integer:asUtf8` out of Solveig's own `lib/text.sol`, written in operators |
| [`examples/forms.phx`](examples/forms.phx) | `unless`, `while` and `swap` declared by the module, and hygiene demonstrated by running rather than by assertion |
| [`examples/dialect.phx`](examples/dialect.phx) | a two-line header, and everything the body reads coming out of `lib/` — with a diamond, read once |

The second one is the argument, and it is Solveig's argument rather than this
project's. The note at the top of `lib/text.sol` says the encoder was first
written with `div(#64)` for a shift and `mod(#64)` for a mask —

> exact, since the bits are disjoint by construction, and nothing like what it
> means. Reading it against the table in RFC 3629 meant translating every line.

Solveig's fix was to grow `shiftRight`, `bitAnd` and `bitOr`, which was right and
which went as far as a fixed syntax can go: the code names the operations now,
and still spells each one as a message send. Phoenix's version declares three
operators at the top of one file and costs the language nothing.

What comes out the other end is the library's own line back again:

```
integer:utf8Tail := { at |
    (#128:bitOr(self:shiftRight(at):bitAnd(#63))):asCharacter }.
```

## What 0.4.0 is not

**A form is call-shaped.** `unless(test, body)` and not `unless test then body`.
That needs a pattern language, and it is the next thing — now that the question
it was waiting behind has an answer.

**Hygiene is still one scope per expansion**, and a template declared in a
`@use`d file did not change that. 0.3.0 said one number would stop being enough
once a template could be declared outside the module using it; it turns out not
to, and the reason is Solveig's rather than Phoenix's. **Globals are one flat
namespace**, so a template's free `total` and a caller's global `total` are the
same variable by construction — there is no second one for a definition context
to have meant. A `scope` becomes a set the day the *substrate* has a module
system, not the day Phoenix does.

Known gaps, each for a reason rather than for lack of time:

| | |
| --- | --- |
| Dictionary literals | `#[a = b]` separates a pair with `=`, and `=` is a character a dialect may declare. That needs a decision, not a default. `dictionary:new` works. |
| Temporaries in a group | `( \| t \| ... )` is Solveig's; Phoenix reads `( expr. expr )` and no temporaries. |
| `@expr` | Deliberately absent. It is the fixed form of what `@infix` generalises, and having both would be having two. |
| A form that reads as a statement | `unless(a, b)` and not `unless a then b`. Next. |
| An installed dialect is not found on its own | `make install` puts `lib/*.phx` beside the binary and nothing looks there. `PHOENIX_PATH` is one line in a profile; Solveig's binaries are told their library path at build time and could be copied. |
| A `@use` path is not normalised | `examples/../lib/control.phx` is what a diagnostic shows, and two spellings of one file are two files. Collapsing `x/../` textually is wrong across a symlink, so it wants `realpath` and a second path to display. |
| Long send chains | A block that will not fit is broken across lines; a chain of sends that will not fit is not, yet. |

## The question that was open

**What stops two dialects' declarations from colliding when their code meets?**
Answered in 0.4.0, above. Racket answers it with modules and scoped bindings and
it was worth reading how — but the answer Phoenix took is Solveig's, because
Solveig had already made the choice for globals and a language should not hold
two philosophies about one question.

Every part of this repository that looked over-careful is why that answer was
cheap to give: the spans were already on the tree, so making them carry a file
was a field and not a rewrite; the map already existed, so it grew a column; the
expansion trail already walked a chain, so it learned to name a file.

**What is open now is smaller and more concrete.** A form is call-shaped and
should not have to be; that wants a pattern language, and a pattern language is
the first thing here that adds a *production* rather than a meaning. It is next
because the collision rule now says what happens when two files add one.

## Licence

MIT, the same as Solveig.
