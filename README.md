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
| `@language <name>.` | What dialect this module is written in. Recorded and not yet acted on: 0.1.0 has one reader. |
| `@infix <op> <precedence> <message>.` | An infix operator, grouping to the left. Higher precedence binds tighter. |
| `@infixr <op> <precedence> <message>.` | The same, grouping to the right. |
| `@prefix <op> <message>.` | A prefix operator. Binds tighter than any infix and looser than a send. |

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

## Why operators, and only operators, in 0.1.0

Because a precedence table composes and a grammar rule does not. **Adding an
operator cannot change what an expression that does not use it already meant.**
Adding a production can, silently, and two libraries that each add one can
collide in a way neither author can see. That is the open question at the bottom
of this page, and statement forms wait behind it.

Solveig already has the fixed version of this. `@expr(a^2 + b/2)` opens a region
where a hard-coded ladder runs from `|` to `^`, and everything in it is the same
sends written another way. Phoenix is that ladder handed to the module.

## Three fields that carry nothing yet

Every node in `phoenix/include/phoenix/tree.h` has them, and two of them are read
by nothing in 0.1.0. They are there because each is impossible to add later
without touching every constructor and every rewrite in the compiler.

| | |
| --- | --- |
| `span` | Where in the **surface text** this came from. Read by every diagnostic and by the map. |
| `introduced_by` | For a node an expansion produced, the form that produced it — so an error can say *in the expansion of `unless`, from here* rather than pointing at code nobody has read. Always `NULL` today, because nothing expands yet. |
| `scope` | The hygiene anchor. [Binding as sets of scopes](https://users.cs.utah.edu/plt/scope-sets/) (Flatt, 2016) is the intended answer, and a set is what this becomes — an index into a scope table rather than the bare `0` it holds today. |

A tree without them is a tree that has to be rebuilt to get them. **Hygiene in
particular cannot be retrofitted**, which is the lesson every macro system that
tried has to teach.

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

## The two examples

| | |
| --- | --- |
| [`examples/vectors.phx`](examples/vectors.phx) | precedence, associativity, a prefix operator, and where a send binds against all of them |
| [`examples/utf8.phx`](examples/utf8.phx) | `integer:asUtf8` out of Solveig's own `lib/text.sol`, written in operators |

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

## What 0.1.0 is not

**It is a front end, not yet a meta-language.** There are no macros, no
user-defined statement forms, and no expander — so nothing yet introduces a node,
which is why `introduced_by` is always `NULL` and `scope` is always `0`. What
exists is the substrate those need: a tree that can carry them, a map that can
find them, and diagnostics that report where somebody was looking.

Known gaps, each for a reason rather than for lack of time:

| | |
| --- | --- |
| Dictionary literals | `#[a = b]` separates a pair with `=`, and `=` is a character a dialect may declare. That needs a decision, not a default. `dictionary:new` works. |
| Temporaries in a group | `( \| t \| ... )` is Solveig's; Phoenix reads `( expr. expr )` and no temporaries. |
| `@expr` | Deliberately absent. It is the fixed form of what `@infix` generalises, and having both would be having two. |
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
