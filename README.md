# Solveig

A small object-oriented language, its bytecode virtual machine, and a REPL.

**Documentation: <https://hansolovkarlsson.github.io/solveig/>** — a
[tutorial](https://hansolovkarlsson.github.io/solveig/docs/TUTORIAL.html) that
builds one program from nothing, a
[guide](https://hansolovkarlsson.github.io/solveig/docs/GUIDE.html) to every
concept, and the
[reference](https://hansolovkarlsson.github.io/solveig/docs/REFERENCE.html).

Everything is an object, including classes, and work happens by sending
messages to them:

```
a := #45.        ; -- ':=' binds a name; '#' tags an integer ( bare 45 is a float )
a:print.         ; -- ':' sends a message, '.' ends the statement

xs := [#1, #2, #3].            ; -- sugar for array:of(#1, #2, #3)
xs:do({ x | x:print }).        ; -- { } is a block: code as a value
```

## The names

**Solveig** is the project. The language it holds is **Solum**, compiled by
**Solas**, run by **SolVM**, explored through **Solis**, and taken apart with
**Solid**. The program is `bin/solvm` and its sources are under `solum/` -- the
same word in two hands, as below.

*Solveig* is Old Norse -- *Sólveig*, from *sól*, "sun", joined to *veig*, which
is usually read as "strength", though the second element is not settled and has
also been glossed as "draught" or "power". It is still an ordinary given name
across Norway, Sweden, and Denmark. Most people who recognise it will recognise
it from Ibsen's *Peer Gynt*, where Solveig is the one who waits, and from
Grieg's setting of her song.

**SolVM** reads two ways, and both are meant. It is the Sol virtual machine --
and it is *SOLVM*, which is how *solum* was written before the alphabet split V
into two letters. Classical Latin had a single **V** standing for both the vowel
and the consonant; U is a much later invention, which is why Roman inscriptions
give us SOLVM and not SOLUM. So the machine is not named *after* the language it
runs. It is the same word, cut in stone.

*Solum* was picked for both of its Latin senses, and each of them says something
about the language.

As a noun it is the **ground** -- soil, floor, the base a thing stands on. That
is what the machine is to the language it runs, and what the language is to
anything written in it.

As an adverb, *sōlum*, it means **"only"**, and that is the design principle
rather than a decoration. There is only one kind of thing here: everything is an
object, classes included. There is only one thing that happens to it: a message
is sent. No operators, no control-flow syntax, no second mechanism behind the
first. *Only* is the whole idea.

Those are two different words, and the sun is a third. Latin tells them apart by
vowel length -- *solum* the ground has a short o, *sōlum* "only" has a long ō
from *sōlus*, "alone", and *sōl*, *sōlis*, the sun, is a root of its own. They
are not one word wearing three hats. They are three words that happen to look
alike, chosen for what each of them says.

*Solidus* is a fourth, and the debugger's. It is Latin for **firm, whole,
sound**, usually taken back to a root meaning "whole" -- the one behind *salvus*,
"safe" -- and unrelated to either the ground or the sun however alike they look.
A debugger is the tool for finding out whether a program is sound, standing on
ground the language calls *solum*. It is also *sol-interactive-debugger*, which
is the sort of coincidence a name should be chosen for.

The sun is what ties them together. It is the single body everything else in the
system turns around, and the one thing this planet's life has always depended on
-- alone in the sky, central, and the reason anything else works. A language in
which there is only one kind of thing, and only one thing you can do to it, is
named after that on purpose. *Solis* is "of the sun". And *Solveig* carries it
into Norse: *sól* joined to *veig*, the strength of the sun -- the same star, in
a different language.

## Layout

| Path      | What                                                             |
| --------- | ---------------------------------------------------------------- |
| `solas/`  | **Solas** -- the compiler: source text to bytecode                |
| `solum/`  | **SolVM** -- the virtual machine, built as `bin/solvm`               |
| `solis/`  | **Solis** -- the REPL: reads until the input could compile        |
| `solid/`  | **Solid** -- the debugger: breakpoints, stepping, and locals      |
| `docs/`   | [GUIDE.md](docs/GUIDE.md), [TUTORIAL.md](docs/TUTORIAL.md), [REFERENCE.md](docs/REFERENCE.md), [design.md](docs/design.md), [BYTECODE.md](docs/BYTECODE.md), [ROADMAP.md](docs/ROADMAP.md), [COMPLETED.md](docs/COMPLETED.md), [CHANGELOG.md](docs/CHANGELOG.md), [journal.md](docs/journal.md), [programs.md](docs/programs.md), [embedding.md](docs/embedding.md), [lineage.md](docs/lineage.md) |
| `tests/`  | Test suite                                                        |
| `examples/` | One `.sol` demonstration per concept the guide names            |
| `programs/` | Whole `.sol` programs, each written to do a job -- [what each does](docs/programs.md) |
| `embed/`  | A C program that holds a `SolVM` -- see [embedding.md](docs/embedding.md) |
| `lib/`    | The library that ships with the language, found on the search path |

Each component keeps its public headers in `<component>/include/<component>/`
and its implementation in `<component>/src/`. `solum/include/solum/bytecode.h`
is the contract between the compiler and the VM -- it is the one file both
sides include, so the instruction set is defined exactly once.

## Build

```sh
make          # builds bin/solas, bin/solvm, bin/solis, bin/solid
make test     # builds and runs the test suite
make clean
```

No dependencies beyond a C11 compiler and `make`.

## Status

**0.20.0** — a testing release; no code changed and `.sob` files are format
version 14, unchanged. **Everything this repository writes down about what it
prints is now checked on every build** — 589 claims across 40 files, where
before the suite compiled every example and ran none of them. It found a stale
stack trace in the guide, a slot count nine releases out of date, **an opening
snippet on this page that did not compile** — the four lines that introduce the
language were missing a `.` — and, in the checker itself, an answer that
depended on how many times it had been run.

**0.19.0** — a documentation release; no code changed and `.sob` files are
format version 14, unchanged. The roadmap now has **nothing left to decide**:
6.32, whether a script should run with less than the whole machine, was deferred
rather than taken and moved to [ideas.md](docs/ideas.md), being the only entry
that ever came from a concern rather than from a program.
[docs/lineage.md](docs/lineage.md) is new and places the language among
Smalltalk, Self, Io, Lua and Ruby — read it first if you already write another
language. Surveying what those have that this might want produced exactly one
roadmap entry, and it came from this repository's own programs:
[3.13](docs/ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing), a
loop is left by its condition or by failing, with nine of 69 loops here carrying
a boolean whose only job is to stop one.

**0.18.0** — **`.sob` format 14, so recompile**: a file built by 0.17.0 or
earlier is refused with *unsupported bytecode version*, and the remedy is
`solas` again, which costs nothing since a `.sob` is derived from a `.sol` that
is still there. Nothing about the language changes. A `.sob` had been a
little-endian container holding a *big-endian* instruction stream — two
conventions arrived at separately and never compared until
[disasm.sol](programs/disasm.sol) decoded both in one program and got the
operands backwards. The order now lives in two constants rather than thirteen
places, which made the flip a two-character edit; and the thing that caught the
one reader `make test` cannot check was comparing that program's output against
`solvm --dump` over 5,737 instructions.

**0.17.0** — two programs that read this project's own work, and the four faults
they found in it. [disasm.sol](programs/disasm.sol) disassembles a `.sob`, which
is a *second* implementation of a format that had one — and that is how you find
out whether a specification is true. `BYTECODE.md` had never said what byte an
opcode is, `design.md` said both "big-endian" and "little-endian throughout"
about the same bytes, and the `.sob` format table had been missing three sections
since version 12. All fixed, and the opcode numbers now have a test.
[expect.sol](programs/expect.sol) runs every example and checks the comments
saying what each line prints — nothing ever had, and all 398 hold; it is in
`make test` now. No language change and no API change: `.sob` files are format
version 13, unchanged since 0.11.0.

**0.16.0** — a data race fixed, and threads settled by measuring. The serial a
machine is stamped with in `sol_vm_init` was incremented non-atomically, so two
threads building one at once could be handed the same number — 16 threads
building 480,000 machines collided **10,319 times**, one in fifty. It matters to
anybody embedding on more than one thread and to nobody else; `solvm`, `solas`,
`solis` and `solid` each build one machine on one thread and could not reach it.
**0.14.1 and 0.15.0 both carry the bug.** What is now tested and promised is one
VM and one chunk per thread — a chunk cannot be shared, since running one mutates
it. Also `sol_vm_set_error_reporting`, so a host can keep failures out of stderr
and in its own log, and two things measured rather than guessed: a fresh VM per
request is a third of a request, and compiling a script is 279µs paid once. No
language change; `.sob` files are format version 13, unchanged since 0.11.0.

**0.15.0** — embedding is a documented interface.
[solum/embed.h](solum/include/solum/embed.h) is the whole supported surface a C
program holds a `SolVM` through, [docs/embedding.md](docs/embedding.md) is the
contract, and [tests/test_embed.c](tests/test_embed.c) holds every promise it
makes. Six functions, none of them new capability — each names two or three
calls a host could already have made, which is the point, since three internal
calls in the right order is not something anybody can rely on. What is
deliberately *not* promised is stated as plainly as what is. Written **before**
deciding what permissions a host may impose, because a permission is a promise
about what a host may rely on and there was no list of that. No language change;
`.sob` files are format version 13, unchanged since 0.11.0.

**0.14.1** — a use-after-free, found by the first program to embed the machine.
A chunk recorded which VM had interned its names by pointer, so a host that
builds a VM per request — every one at the same stack address — had its second
request reading the freed first machine's name table. `SolChunk.interned_for` is
a serial now, which is a type change in a public header and nothing else.
`solvm`, `solas`, `solis` and `solid` each build one VM and could not reach it;
`.sob` files are unchanged. Also [embed/host.c](embed/host.c) and
[docs/embedding.md](docs/embedding.md), which are what found it.

**0.14.0** — the shipped files divide in two: `examples/` holds one
demonstration per concept the guide names, `programs/` holds seven whole
programs each written to do a job. The split was already drawn in the programs'
own headers; [docs/programs.md](docs/programs.md) says what each does and how to
run it. The seventh, [serve.sol](programs/serve.sol), is a CGI-shaped request
handler and the first program here whose input does not come from whoever ran
it — which found that **a limit bounds dispatch, not work**: `readFile` of 256MB
and a scan of all of it is eight instructions, the same eight as for 64MB, so
0.13.0's limits stop a program that loops and do not bound the cost of one
message. That is [3.7](docs/ROADMAP.md#37-a-limit-bounds-dispatch-not-work), and
two documents that claimed otherwise now do not. No language change: `.sob` files
are format version 13, unchanged from 0.11.0.

**0.13.0** — a program can be given a limit. `solvm --steps=N` bounds how many
instructions it may execute and `--memory=N` how much it may hold at once, with
`sol_vm_set_step_limit` and `sol_vm_set_memory_limit` for a program embedding
the machine — which is the case that wanted them, a webserver having no ctrl-c
to fall back on. **A stop cannot be caught**: `onError` does not see it and
`ensure` does not run its cleanup, since both are ways of running more code and
the allowance for running code is what ran out. A stopped program exits 124. What
they bound is a program that *loops*, which 0.14.0 had to go on to say. The
matching question — whether a script should also be able to run with less than
the whole *machine* — is recorded on the roadmap and not answered. `.sob` files
are format version 13, unchanged from 0.11.0.

**0.12.0** — a debugger, and a program can run another program. `bin/solid`
stops a program where it is running, or where it broke, and shows the frames and
their locals by name. `system:run` and `system:capture` invoke other programs,
taking an **array of arguments rather than a command line** so that a filename
is never read as syntax; `lib/shell.sol` is there when pipes and globs are the
point. Also `string:trim`, because every tool pads its output. `.sob` files are
format version 13, unchanged from 0.11.0.

**0.11.0** — a frame slot knows what it was called, so `solvm --trace` names its
arguments and anything looking at a frame can say `average` rather than `slot
3`. The compiler always knew and threw it away once the index was emitted.
Another `.sob` format change, 12 to 13 — **recompile the `.sol`** — costing
+0.2% to +3.4%. One entry left on the roadmap, and it is the debugger.

**0.10.0** — a stack trace says which file, and the `.sob` format changes for
the first time since 0.1.0 to carry that. It was misleading rather than merely
thin: a chunk holds every included file's code, so a bare line number named a
line in a file nobody had recorded and read as a line of the one you were
looking at. **A `.sob` from an earlier release is refused rather than misread —
recompile the `.sol`.** `solvm --version` says which format a build speaks.

**0.9.0** — bits, and the first tools for looking at a program rather than
writing one. `solvm --trace` writes the call tree, and because conditionals and
loops compile to jumps a three-hundred-thousand-turn loop adds nothing to it.
`solis --interactive` runs a file and stays at the prompt with what it left —
after a failure too, which works because a script's own names are globals and
survive the unwind. Bit operations and shifts, which `lib/text.sol` had been
writing as `div` and `mod` for want of them, and `inc` and `dec`, which are
three in ten of all the arithmetic here.

**0.8.0** — a program can deal with a filesystem it has to change, and with a
keyboard. `modeOf` and `setMode` so a copy keeps the executable bit,
`setModifiedAt` so it keeps its time, `makeDirectory` answering whether it made
one, and `readKey` for a program that wants a keypress rather than a line. Every
one of them was asked for by a program rather than planned —
[mirror.sol](programs/mirror.sol) copies a directory tree and found a defect in
`modifiedAt` on the way. The reference has a contents and an index of all 110
messages. The roadmap is empty.

**0.7.0** — the prompt became a place you can work: ↑ and ↓ through what you
have typed, ← and → within the line, the readline bindings, and history kept in
`$HOME/.solis_history` so it is still there tomorrow. It reads a line exactly as
it used to through a pipe or a file, and needs nothing installed either way. The
language itself is unchanged, and with this the roadmap has nothing left on it
to build — only the restrictions it keeps on purpose.

**0.6.0** — no design questions are left open. The last one, whether the class
side and the instance side should be separate objects, is closed by drawing the
line between them with the receiver each message requires rather than by
splitting anything: `respondsTo` now agrees with sending everywhere, and an
instance can no longer answer for its class. The compiler also warns when two
files claim one global name, there being no module system to stop them. The one
behaviour change is that `[#1]:new` and `[#1]:of(...)` are refused rather than
answering.

**0.5.0** — the language reads formats it was not built for. `lib/json.sol` and
`lib/html.sol` are a JSON reader and an HTML reader written in Solum, on the
search path. The HTML one **does not fail on bad input**, because bad input is
what HTML is: it recovers and reports what it recovered from. Building it turned
up where the recursion limit really lives — not in the data, but in how you walk
it — and `array:removeLast`, `array:indexOf` and an ordering on symbols, each
from a workaround that was already shipped. `.sob` files were format version 11,
unchanged since 0.1.0, so one built then runs here; everything added since is a
primitive or a library rather than an opcode. `solvm --version` says which
format a build speaks.

The language is settled enough to write programs in.
[programs/log.sol](programs/log.sol) is one written to do a job rather than to
show a feature — it reads an access log, tallies it, ranks it and reports — and
[lib/json.sol](lib/json.sol) and [lib/html.sol](lib/html.sol) are a JSON reader
and an HTML reader written in Solum, on the search path so a program says
`@include "html.sol".` and nothing about where it lives.

It is 0.1 rather than 1.0 because [the restrictions in the
roadmap](docs/ROADMAP.md#3-known-limitations) are real and deliberate: no
non-local return, a capturing block tied to the frame it was written in,
recursion to about 62 levels, and text is bytes rather than characters. Each is
documented where a program would meet it.

Recovering from a failure was on that list until 0.2.0.

Source text goes through the scanner, compiler, and dispatch loop:

```
$ ./bin/solis
> a := #45.
> a:add(#5):print.
#50
> a:print.
#45
> #45:add(1.5).
solvm: 'add' expects integer, got float (no implicit coercion)
```

Arithmetic is strict: integers and floats never coerce, and integer overflow
traps rather than wrapping.

Built in: `integer`, `float`, `string`, `symbol`, `boolean`, `nil`, `block`,
`array`, `dictionary` and `object`, all delegating to `object` so that
everything is an object in the type graph as well as in the slogan. Strings
split and join, arrays fold and slice, and a dictionary keeps values under keys.
A program reads and writes files, reads its input, times itself, stops with a
status, and is split across files with `@include`.

Compiling to a file and running it separately works too:

```
$ ./bin/solas examples/hello.sol      # writes examples/hello.sob
$ ./bin/solvm examples/hello.sob
#45
```

`.sob` files are little-endian and independent of the host, and are verified
before they run -- every instruction has to fit, every operand index something
that exists, every jump land on the start of an instruction, and the last
instruction stop the machine. See [docs/design.md](docs/design.md) for the
layout, [docs/BYTECODE.md](docs/BYTECODE.md) for the instruction set.

They are **not** portable across releases: the format carries a version, a build
reads only its own, and an older file is refused with `unsupported bytecode
version` rather than misread.

A method is a name bound on a class, just as a variable is a name bound in the
globals -- so it uses the same `:=`. The right-hand side is evaluated, and a
slot holding a block is what makes a method:

```
> integer:double := { self:mul(#2) }.
> #21:double:print.
#42
> integer:poly := { a, b | self:mul(a):add(b) }.
> #10:poly(#3, #7):print.
#37
```

A slot holding anything else is data, evaluated once when bound. And because
`:=` evaluates, a method can be computed rather than written out:

```
> maker := { { self:mul(#2) } }.
> integer:double := maker:value().
> #21:double:print.
#42
```

See [examples/methods.sol](examples/methods.sol).

Braces make a block -- code as a value. Control flow is then ordinary message
sending, with no control-flow syntax in the language at all:

```
> #5:lessThan(#10):ifElse({ #100:print }, { #200:print }).
#100
> i := #0.
> { i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
> i:print.
#5
```

Which is enough to be Turing-complete:

```
integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul( self:sub(#1):factorial ) })
}.
#20:factorial:print.      ; #2432902008176640000
```

`and` and `or` take a block for the same reason, so the answer can be settled
without running it:

```
> x := #3.
> x:greaterThan(#0):and({ x:lessThan(#10) }):print.
true
```

Written literally, all of those compile to jumps -- no block allocated, no frame
entered -- while staying ordinary messages you can send any other way. See
[examples/blocks.sol](examples/blocks.sol).

## License

MIT -- see [LICENSE](LICENSE).

[docs/GUIDE.md](docs/GUIDE.md) is the tour: every concept in the language, in an
order that builds, each pointing at a runnable example. Start there.

[docs/REFERENCE.md](docs/REFERENCE.md) is the language reference: syntax,
semantics, and every built-in message.

[docs/lineage.md](docs/lineage.md) places it: what it borrowed from Smalltalk
and Self, what Io and Lua are near it, and what to expect if you arrive knowing
one of those. Worth a read before the tour if you already write another
language.

The full list of what is left -- open design questions, known limitations, and
unbuilt work -- is in [docs/ROADMAP.md](docs/ROADMAP.md).

See [docs/design.md](docs/design.md) for the object model,
[docs/BYTECODE.md](docs/BYTECODE.md) for the instruction set, and
[docs/CHANGELOG.md](docs/CHANGELOG.md) for what has changed.
[docs/journal.md](docs/journal.md) is the day-by-day account: what was picked
up and why, including the hours that produced no code.
