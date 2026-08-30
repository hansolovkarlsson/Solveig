---
title: Solveig
description: Solveig — a small object-oriented language, its bytecode virtual machine, and the toolkit around it.
---

# Solveig

A small object-oriented language, its bytecode virtual machine, and a REPL —
written in C11, with no dependencies beyond a compiler and `make`.

Everything is an object, including classes, and all work happens by sending
messages to them.

```
a := #45.        ; ':=' binds a name; '#' tags an integer ( bare 45 is a float )
a:print.         ; -- ':' sends a message, '.' ends the statement

xs := [#1, #2, #3].
xs:do({ x | x:print }).        ; -- { } is a block: code as a value
```

There is **no control-flow syntax at all**. `ifTrue`, `ifElse`, and `whileTrue`
are ordinary messages that take unevaluated blocks, which is enough to be
Turing-complete:

```
integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul( self:sub(#1):factorial ) })
}.
#20:factorial:print.      ; #2432902008176640000
```

Written literally those compile to jumps — no block allocated, no frame entered —
while staying ordinary messages you can send any other way.

---

## Start here

- **[Tutorial](docs/TUTORIAL.md)** — build a stock report from nothing,
  meeting each idea at the moment you need it. Start here if you want to be
  writing something.
- **[Guide](docs/GUIDE.md)** — every concept in the language in an order that
  builds, each pointing at a runnable example. Start here if you would rather
  see the shape of the whole thing first.
- **[Reference](docs/REFERENCE.md)** — syntax, semantics, and every built-in
  message, organised for looking things up.
- **[Cheatsheet](docs/CHEATSHEET.md)** — the whole language on one page: the
  syntax, every type and every message it answers, one line each. For when you
  know what you want and not what it is called.

- **[Grammar](docs/GRAMMAR.md)** — the syntax alone, as a grammar: thirteen
  productions and the words they are made of. There are no keywords and no
  control-flow syntax, so the page is short for a reason rather than by being a
  summary.

- **[Pascal on SolVM](docs/PASCAL.md)** — ISO 7185 Standard Pascal, compiled to
  a `.sob`. Written before the compiler: how Pascal's types land on a machine
  that has none of them, where SolVM forces a divergence, and what is built
  when.

- **[SolaBasic cheatsheet](docs/SOLABASIC-CHEATSHEET.md)** — every statement and
  every supplied function of the BASIC dialect, on one page. The
  [reference manual](docs/SOLABASIC-REFERENCE.md) is the full account and
  [the definition](docs/SOLABASIC.md) says where the boundary came from.
- **[Speed](docs/performance.md)** — measured against CPython 3.14 on nine
  matched programs: where it wins, where it loses, and the three defects the
  comparison found that nothing measured from the inside had noticed. Also the
  two textbook optimisations that were built and turned out to be slower. The
  programs are in [comparisons/](comparisons/), and re-run with one command.
- **[Lineage](docs/lineage.md)** — what Solum borrowed from Smalltalk and Self,
  which living languages sit nearest it, and what will surprise you if you
  arrive knowing Ruby, JavaScript or C. Five minutes, and worth them first.

Also: **[Design](docs/design.md)** for the object model and the `.sob` format;
**[The instruction set](docs/BYTECODE.md)** for every opcode SolVM executes;
**[Fetching a method](docs/fetched-methods.md)** for holding a method as a
value; **[One hierarchy](docs/one-hierarchy.md)** for how a method on `object`
reaches a number, and where a value is still not an object; **[Choosing what to do](docs/dispatch.md)** for switch statements, jump
tables and the traps in them; **[Absence](docs/absence.md)** for nil, empty and
unset;
**[The class side and the instance side](docs/class-and-instance.md)**
for the last design question and how it was closed; **[SolaBasic](docs/SOLABASIC.md)** for
the compiled BASIC that targets this bytecode, and where its subset stops, with
a **[reference manual](docs/SOLABASIC-REFERENCE.md)** for writing it;
**[Ideas considered](docs/ideas.md)**
for what was weighed and what was turned down; **[Roadmap](docs/ROADMAP.md)**
for what is left; **[Completed](docs/COMPLETED.md)** for the case behind each
piece of work that is done; and **[Changelog](docs/CHANGELOG.md)** for what has
changed.

## The names

**Solveig** is the project. The language it holds is **Solum**, compiled by
**Solas**, run by **SolVM**, and explored through **Solis**.

*Solveig* is Old Norse — *Sólveig*, from *sól*, "sun", joined to *veig*, usually
read as "strength". Most people who recognise it will recognise it from Ibsen's
*Peer Gynt*, where Solveig is the one who waits.

**SolVM** reads two ways, and both are meant. It is the Sol virtual machine —
and it is *SOLVM*, which is how *solum* was written before the alphabet split V
into two letters. Classical Latin had a single **V** for both the vowel and the
consonant, which is why Roman inscriptions give SOLVM and not SOLUM. So the
machine is not named *after* the language it runs. It is the same word, cut in
stone.

*Solum* was picked for both of its Latin senses, and each of them says something
about the language.

As a noun it is the **ground** — soil, floor, the base a thing stands on. That
is what the machine is to the language it runs, and what the language is to
anything written in it.

As an adverb, *sōlum*, it means **"only"**, and that is the design principle
rather than a decoration. There is only one kind of thing here: everything is an
object, classes included. There is only one thing that happens to it: a message
is sent. No operators, no control-flow syntax, no second mechanism behind the
first. *Only* is the whole idea.

Those are two different words, and the sun is a third. Latin tells them apart by
vowel length — *solum* the ground has a short o, *sōlum* "only" has a long ō
from *sōlus*, "alone", and *sōl*, *sōlis*, the sun, is a root of its own. They
are not one word wearing three hats. They are three words that happen to look
alike, chosen for what each of them says.

The sun is what ties them together. It is the single body everything else in the
system turns around, and the one thing this planet's life has always depended on
— alone in the sky, central, and the reason anything else works. A language in
which there is only one kind of thing, and only one thing you can do to it, is
named after that on purpose. *Solis* is "of the sun". And *Solveig* carries it
into Norse: *sól* joined to *veig*, the strength of the sun — the same star, in
a different language.

## Status

**0.3.0** — a program can walk the filesystem, know what day it is, and be run
directly as a script. `.sob` files are format version 11, unchanged since 0.1.0.

Working: the scanner, the single-pass compiler, the re-entrant dispatch loop
with call frames, blocks with lexical capture, message-based control flow, a
mark-sweep collector over objects, blocks and compiled code, and the `.sob`
format with its verifier.

The language is Turing-complete, does not leak, and has strings, arrays,
dictionaries, symbols, user-defined objects, reflection, sorting, formatted
output, and conversions between every pair of types that has an unambiguous one.
A program reads and writes files, reads its input, times itself, stops with a
status, and is split across files with `@include`.

It is 0.1 rather than 1.0 because [the restrictions in the
roadmap](docs/ROADMAP.md#3-known-limitations) are deliberate and documented: no
non-local return, a capturing block tied to its frame, recursion to about 254
levels, and text is bytes.

Arithmetic is strict throughout: integers and floats never coerce, and integer
overflow traps rather than wrapping.

```sh
make          # builds bin/solas, bin/solvm, bin/solis
make test     # builds and runs the test suite
```

```sh
./bin/solas examples/hello.sol      # writes examples/hello.sob
./bin/solvm examples/hello.sob
./bin/solis                         # a prompt; input may span lines
```

`.sob` files are little-endian and portable, and are verified before they run.

## Examples and programs

Two directories, and the split is what each was written for.

**`programs/`** — fifteen<!--count programs--> whole programs, each written to do a job and using
whatever the language turned out to have. They are where nearly every roadmap
entry after the first dozen came from: somebody wrote one and found out what it
wanted. [programs.md](docs/programs.md) says what each does, how to run it, and
what it found.

| | |
| --- | --- |
| [log](programs/log.sol) | reads an access log and reports on it |
| [evaluator](programs/evaluator.sol) | tokenises, parses and folds an expression |
| [manifest](programs/manifest.sol) | reads a JSON file, queries it, writes it back |
| [page](programs/page.sol) | reads an HTML file and reports on it |
| [mirror](programs/mirror.sol) | copies one directory tree into another |
| [tools](programs/tools.sol) | does its job by running other programs |
| [serve](programs/serve.sol) | answers one HTTP request, without being injected |
| [disasm](programs/disasm.sol) | reads a `.sob` file and says what is in it |
| [expect](programs/expect.sol) | checks every example against its own comments |
| [bench](programs/bench.sol) | times a command, and says whether two really differ |
| [basic](programs/basic.sol) | runs a BASIC listing — an interpreter for ECMA-55 |
| [edit](programs/edit.sol) | edits a file on the screen, in the manner of vi |

Two of them run on [lib/json.sol](lib/json.sol) and
[lib/html.sol](lib/html.sol) — a JSON reader and an HTML reader written in
Solum. The last one is an interpreter for another language, and is where the
mathematics in 0.32.0 came from.

**`examples/`** — thirty-five<!--count examples--> demonstrations, one for every concept the
[guide](docs/GUIDE.md) names:
[hello](examples/hello.sol),
[binding](examples/binding.sol),
[stock](examples/stock.sol),
[numbers](examples/numbers.sol),
[values](examples/values.sol),
[blocks](examples/blocks.sol),
[methods](examples/methods.sol),
[objects](examples/objects.sol),
[arrays](examples/arrays.sol),
[strings](examples/strings.sol),
[symbols](examples/symbols.sol),
[format](examples/format.sol),
[reflect](examples/reflect.sol),
[strictness](examples/strictness.sol),
[library](examples/library.sol),
[include](examples/include.sol),
[system](examples/system.sol),
[reading](examples/reading.sol),
[files](examples/files.sol),
[dictionaries](examples/dictionaries.sol),
[loops](examples/loops.sol),
[errors](examples/errors.sol),
[walk](examples/walk.sol),
[time](examples/time.sol),
[keys](examples/keys.sol),
[random](examples/random.sol),
[scanning](examples/scanning.sol),
[commands](examples/commands.sol),
[matching](examples/matching.sol).
