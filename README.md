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

**A generated name avoids every identifier in the module**, collected by lexing
the source rather than by walking the tree. A caller who already has a `t__1`
gets `t__2`, and two expansions of one form never agree by accident. After
expansion no identifier exists that was not either in that set or generated
against it, which is what makes *fresh* mean fresh rather than probably fresh.

**What this does not yet buy.** A template's *free* references are not protected:
if a template mentions `error` and the use site has a local called `error`, the
template gets the local. That is referential transparency, it needs full scope
sets and name resolution, and `scope` is on every node so that the day it
arrives it is a change to the expander. Today `scope` holds one scope per
expansion, which is what the renaming needs and no more.

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
| `scope` | The hygiene anchor: one scope per expansion, stamped on everything a template produced, `0` for what a person wrote. [Binding as sets of scopes](https://users.cs.utah.edu/plt/scope-sets/) (Flatt, 2016) is where this goes — a set rather than a number — when free references need protecting too. |

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

## The three examples

| | |
| --- | --- |
| [`examples/vectors.phx`](examples/vectors.phx) | precedence, associativity, a prefix operator, and where a send binds against all of them |
| [`examples/utf8.phx`](examples/utf8.phx) | `integer:asUtf8` out of Solveig's own `lib/text.sol`, written in operators |
| [`examples/forms.phx`](examples/forms.phx) | `unless`, `while` and `swap` declared by the module, and hygiene demonstrated by running rather than by assertion |

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

## What 0.2.0 is not

**A form is call-shaped.** `unless(test, body)` and not `unless test then body`.
The surface a form presents is the next thing to grow, and it waits behind the
collision question below.

**Hygiene is one scope per expansion**, not scope sets. It stops a template's
binders capturing a caller's names, in both directions between two expansions of
the same form. It does not give a template referential transparency over its free
names — see *Hygiene* above.

Known gaps, each for a reason rather than for lack of time:

| | |
| --- | --- |
| Dictionary literals | `#[a = b]` separates a pair with `=`, and `=` is a character a dialect may declare. That needs a decision, not a default. `dictionary:new` works. |
| Temporaries in a group | `( \| t \| ... )` is Solveig's; Phoenix reads `( expr. expr )` and no temporaries. |
| `@expr` | Deliberately absent. It is the fixed form of what `@infix` generalises, and having both would be having two. |
| A form that reads as a statement | `unless(a, b)` and not `unless a then b`. Needs a pattern language, and needs the collision question answered before it is worth having one. |
| Long send chains | A block that will not fit is broken across lines; a chain of sends that will not fit is not, yet. |

## The open question

**What stops two dialects' declarations from colliding when their code meets?**

Today nothing has to: a dialect is a file's header, files do not share headers,
and there is no way to import one. That is a real answer for 0.1.0 and it stops
being one the moment `@language` names something a library can publish — which
is the next thing worth building and the reason it is not built yet.

Racket answers it with modules and scoped bindings, and it is worth reading how
before answering it differently. Every part of this repository that looks
over-careful — the spans, the two unused fields, the map — is there because that
answer will be easier to give to a compiler that already has them.

## Licence

MIT, the same as Solveig.
