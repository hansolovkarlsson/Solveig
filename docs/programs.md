# The programs

*The fifteen<!--count programs--> files in [programs/](../programs/): what each one does, how to run
it, and what it found. [examples/](../examples/) is the other directory — one
file per concept the [guide](GUIDE.md) names, each written to show a feature.
These were written to do a job.*

**Two used to be here and are not.** `emit.sol` and `compile.sol` taught Solum
to compile itself, which it now does — its own source, to a fixpoint. They live
in [experiment/](../experiment/) with the four libraries they used, off the
search path and out of `make test`, because keeping them in step with `solas`
taxed every change to the real compiler and the proof does not need repeating.
[experiment/README.md](../experiment/README.md) has the account.

That distinction is the reason for the split, and it is not cosmetic. **A
program written to show a feature is written after the feature and to suit it,
so it can never report that the feature was awkward.** These can, and did:
nearly every entry the [roadmap](ROADMAP.md) gained after the first dozen came
from one of these fifteen wanting something the language did not have.

**What this page is not is a description of what Solum is for.** These fifteen lean
towards text and processes because they are the tools this project needed while
building itself, and the language is meant to be general —
[design.md](design.md#what-the-language-is-for) says so, and says what happened
the once that was forgotten.

Each is a single `.sol` file with its reasoning in its own comments. This page
is the map; the file is the argument.

## At a glance

| | does | run it |
| --- | --- | --- |
| [log](../programs/log.sol) | reads an access log and reports on it | `solvm log.sob [logfile]` |
| [evaluator](../programs/evaluator.sol) | tokenises, parses and evaluates arithmetic | `solvm evaluator.sob` |
| [manifest](../programs/manifest.sol) | reads JSON, describes it, queries it, writes it back | `solvm manifest.sob [file.json] [path]` |
| [page](../programs/page.sol) | reads HTML and reports on it | `solvm page.sob [file.html] [tag]` |
| [mirror](../programs/mirror.sol) | copies one directory tree into another | `solvm mirror.sob [src] [dst] [dry]` |
| [tools](../programs/tools.sol) | reports on a directory by running other programs | `solvm tools.sob [directory]` |
| [serve](../programs/serve.sol) | answers one HTTP request | `PATH_INFO=/ solvm serve.sob` |
| [disasm](../programs/disasm.sol) | reads a `.sob` file and says what is in it | `solvm disasm.sob [file.sob] [brief]` |
| [expect](../programs/expect.sol) | checks the examples and the documents against their own claims | `solvm expect.sob [dir or file]...` |
| [bench](../programs/bench.sol) | times a command, and says whether two of them really differ | `solvm bench.sob [runs] [cmd] [-- cmd]` |
| [basic](../programs/basic.sol) | runs a BASIC listing | `solvm basic.sob` |
| [edit](../programs/edit.sol) | edits a file on the screen, in the manner of vi | `solvm edit.sob [file]` |
| [sola](../programs/sola.sol) | compiles SolaBasic to a `.sob` | `solvm sola.sob [prog.bas] [out.sob]` |
| [check_syntax](../programs/check_syntax.sol) | reads a grammar, then checks a file against it | `solvm check_syntax.sob [grammar.bnf] [source]` |
| [pascal](../programs/pascal.sol) | compiles ISO 7185 Pascal to a `.sob` | `solvm pascal.sob [prog.pas] [out.sob]` |

Every one runs with no arguments at all, on input it supplies itself. That is
deliberate — a program you have to feed before it will say anything is a program
you will not run.

Compile first. All of them:

```sh
for f in programs/*.sol; do ./bin/solas "$f"; done
```

or one at a time, which is what each file's own header shows:

```sh
./bin/solas programs/log.sol && ./bin/solvm programs/log.sob
```

`solas` writes the `.sob` beside the source, so `programs/log.sol` becomes
`programs/log.sob`. Bytecode is gitignored and is not shipped.

---

## log — an access log, read and reported on

**The first of these, and the reason the directory exists.**

Reads a log of six space-separated fields and reports the totals, the busiest
paths, the status breakdown and the slowest requests.

```sh
./bin/solvm programs/log.sob                      # a built-in sample
./bin/solvm programs/log.sob path/to/access.log   # your own
```

**It expects its input to be damaged**, because real input is. Three lines of
the built-in sample are broken in different ways and the report says so and
carries on rather than stopping at the first.

That half was written after `onError` existed and found two things. Surviving a
bad *line* is not the same as surviving a bad *file* — a file of pure rubbish
leaves nothing to report on, and the summary fell over on the empty array the
first time it met one. And the division of labour that makes a report readable
is that the machine says *what* went wrong, naming the offending text, while the
program says *where*, because only the program is counting lines.

**What it asked for and got**: a [dictionary](REFERENCE.md#dictionary) and array
slicing. Both were built because this program could not be finished without
them.

## evaluator — a calculator

Tokenises, parses and evaluates arithmetic, with parentheses, unary minus, and
an error message that names the position.

```sh
./bin/solvm programs/evaluator.sob
```

```
2 + 3 * 4 = 14
(2 + 3) * 4 = 20
1 + -- expected a number at 4
1 + + 2 -- expected a number at 5, got '+'
2 $ 3 -- unexpected '$' at 3
1 / 0 -- division by zero in 'div'
```

Deliberately a different shape from `log.sol`, which is line-oriented — read
text, split it, tally it. This one recurses, builds a tree of objects, and has
to say something useful when its input is wrong.

**What it found**: the [frame limit](ROADMAP.md#35-recursion-is-limited-to-about-254-levels),
and that it is catchable. A recursive-descent parser spends about three frames
per level of bracket nesting, so it manages 83 brackets deep — 18 when it was
written, against a cap of 64 frames rather than 256. Running out of
frames arrives at `onError` like any other failure and the program carries on
after it, which is what makes the limit a limit rather than a crash.

## manifest — a JSON file, described, queried and written back

Reads a JSON document, prints its shape, pulls out a value by dotted path, and
writes it back out.

```sh
./bin/solvm programs/manifest.sob                            # a built-in sample
./bin/solvm programs/manifest.sob path/to/file.json          # your own
./bin/solvm programs/manifest.sob file.json server.port      # one value from it
```

The parser is [lib/json.sol](../lib/json.sol), on the search path, so the
program says `@include "json.sol".` and not where it lives. Splitting it that
way was the point: a JSON reader is library code, and the program above it is
what finds out whether the library is any good.

It is called `manifest.sol` and not `json.sol` because **a file that includes a
library of its own name finds itself on the search path first** — and, a file
being compiled once, that include quietly does nothing. That is
[6.22](COMPLETED.md#622-a-file-that-includes-a-library-of-its-own-name-silently-does-nothing--done),
and it took about a minute to fall into.

**What it found**: that a byte had no number — `asByte` and `asCharacter` exist
because of this program and `lib/json.sol` — and a price on how the value
dispatch is written. Dispatching on the first character through a dictionary of
blocks costs one more frame per level than a chain of `ifElse`, which is
18 levels of JSON nesting against 28.

## page — an HTML file, read and reported on

Reads an HTML document and reports its title, outline, links, images without alt
text, and everything wrong with the markup.

```sh
./bin/solvm programs/page.sob                          # a built-in sample
./bin/solvm programs/page.sob path/to/page.html        # your own
./bin/solvm programs/page.sob page.html img            # dump one kind of element
```

The parser is [lib/html.sol](../lib/html.sol), on the search path.

**It cannot fail on bad input, because bad input is the normal case.** `log.sol`
skips a bad line and `lib/json.sol` refuses a bad document — both right for
their format. HTML is generated, served, and wrong, so a reader that stops is no
use. The parser recovers and keeps a list, and the program prints that list as
part of the report rather than as an error.

**What it found**: that the frame limit is about *traversal*, not about data.
The tree is built against a stack rather than by recursion, which reads a
document nested 50,000 deep — and then walking it back down recursed and capped
at 28 again, so `text`, `find` and `findAll` are written with a stack too. Also
that an array could not be popped or asked what it holds, which a stack notices
immediately; `removeLast` and `indexOf` are
[6.23](COMPLETED.md#623-an-array-cannot-be-popped-or-asked-what-it-holds--done).

## mirror — one directory tree copied into another

Lists both trees, compares them, and copies what differs — carrying each file's
mode and modification time across.

```sh
./bin/solvm programs/mirror.sob                              # built-in sample trees
./bin/solvm programs/mirror.sob source destination           # your own
./bin/solvm programs/mirror.sob source destination dry       # say, do not do
```

**It does not delete.** A destination file with no counterpart in the source is
reported and left alone, because a mirror that deletes is a different and much
more dangerous tool and an example is a bad place to hide one.

The first of these to *write* to the filesystem rather than read it, and the
ordinary job that needs the whole set at once — list, test, measure, make, copy.

**What it found**, and it is the richest of the seven:

- **`modifiedAt` answered whole seconds**, so within one second "is the source
  newer?" was always no and a file edited just after a run was never copied. The
  filesystem records nanoseconds and `time` holds nanoseconds; only that message
  was rounding, in the middle of them.
- **A copy could not keep the original's time**, so the test had to be *newer
  than* rather than *the same as* — which misses a source replaced with an older
  copy of itself. `setModifiedAt` was built for this.
- **The executable bit was lost**, because a copy here is `readFile` then
  `writeFile` and neither carries a mode, so a backup of anything holding
  scripts was not runnable. `modeOf` and `setMode` were built for this.

The last two are [6.26](COMPLETED.md#626-a-files-mode-and-time-cannot-be-read-or-set--done),
which this program is the whole case for.

And one thing that is *not* a gap: a whole-file copy is fine at this size and not
at every size. `readFile` answers the file as one string, so a mirror of
something large holds it in memory twice. Worth knowing where the edge is rather
than discovering it.

## tools — a directory reported on by running other programs

Reports how many files a directory holds, how big it is, what kinds, and what
version control has to say — by asking `du`, `find`, `git` and friends, each of
which already exists and is better than anything worth writing here.

```sh
./bin/solvm programs/tools.sob             # the current directory
./bin/solvm programs/tools.sob path/to/it  # another one
```

```
  size    49M
  .sol    105 files
  .c      47 files

  git     bb05f65
  changed 10 files
```

The first of these to do most of its job by asking something else to do it,
which is what a scripting language is for.

**What it shows**: why `capture` answers the status beside the output. A command
that is not installed answers 127 with nothing to say, and one that failed may
still have printed something — so output alone cannot be believed, and the
status is what says whether to. It also uses [lib/shell.sol](../lib/shell.sol),
which is on the search path.

## serve — one HTTP request, answered

A CGI-shaped request handler: `/`, `/search?q=...` and `/note/<name>`, served
out of a directory of files.

```sh
./bin/solvm programs/serve.sob                                     # seven requests, self-run
PATH_INFO=/search QUERY_STRING=q=limit ./bin/solvm programs/serve.sob
PATH_INFO=/note/limits ./bin/solvm programs/serve.sob
PATH_INFO=/ ./bin/solvm --steps=100000 --memory=8M programs/serve.sob
```

With no CGI variables set it runs seven requests through itself and prints each
response, so it is testable without a socket. The last four of those are the
attacks: a reflected script tag, a name that is only dots, a traversal spelled
with escapes, and a name carrying the quote that would break out of an `href`.

**The first of these whose input does not come from whoever ran it.** Every
other program here is handed its arguments by the person who started it; this
one is handed a path and a query string by a stranger, which is the case
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
is about.

**What it found**:

- **`fill` is the injection.** It is the natural way to build a page and inserts
  exactly what it is given, and nothing in the language or `lib/` escapes HTML.
  The safe twin of `fill` is the one with the worse name.
- **A template with two kinds of hole cannot use `fill` at all**, since it
  insists the placeholders and the values come to the same number. The
  marker-and-`split` habit that replaces it is worse, because a marker is a
  string and a value can contain one. What is left is an array of pieces joined.
- **A permission per message is not fine enough.** A CGI handler is told what it
  was asked entirely through `system:environment`, so a scheme that can only say
  yes or no to that message must say yes — and has then handed over every secret
  the server process holds.
- **A limit bounds dispatch, not work.** Running it as a guest with an allowance
  found that `readFile` of 256MB and a scan of all of it is eight instructions,
  the same eight as for 64MB. That is
  [3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work), and it corrected two
  documents that said otherwise.

## disasm — a `.sob` file, read and disassembled

Reads a compiled Solum file and prints its header, tables and instructions —
offsets, lines, opcodes, operands and jump targets — recursing into every method
and block.

```sh
./bin/solvm programs/disasm.sob                    # compiles itself a sample
./bin/solvm programs/disasm.sob path/to/file.sob   # your own
./bin/solvm programs/disasm.sob file.sob brief     # header and tables only
```

**The first to read a binary format, and the first to read one this project
defines.** `solvm --dump` already disassembles, so this is a *second*
implementation — which is the point, because a second implementation is how you
find out whether a specification is true. It was written from
[design.md](design.md#the-sob-file-format) and [BYTECODE.md](BYTECODE.md),
going to the C only where those ran out. They ran out five times.

**What it found in the documents**, all three now fixed:

- **BYTECODE.md never said what byte an opcode is.** It described every
  instruction and the test suite checked that description against the header in
  both directions — and the mapping from byte to instruction lived only in the
  order of a C enum, so a reader with the page in front of them could not decode
  one instruction. The page carries the numbers now and
  `tests/test_bytecode.c` checks them.
- **design.md contradicted itself about byte order.** Its instruction-set
  section said a side-table index "is a big-endian u16", correctly. Its `.sob`
  section said "little-endian throughout", which was true of every table in the
  file and false of the operands inside the code. A reader after the file format
  lands on the second. Getting it backwards does not look like a misreading, it
  looks like corruption — every index 256 times too large.

  *Settled rather than documented, in the end.* The order was collapsed into one
  pair of shifts and then flipped: as of `.sob` format 14 the operands are
  little-endian too, and the sentence is simply true. This program's own two
  decoders had to be edited by hand, nothing checking them against the C — and
  comparing its output against `solvm --dump` is what confirmed both sides had
  moved.
- **The format table was missing three sections and a constant tag** — the file
  table, the file-run table and the slot names, plus tag 3 for a boolean. They
  arrived with 6.27 and 6.28, which bumped the format to 12 and then 13; the
  table was not bumped with them. It also did not separate the file's header
  from a chunk's body, so *"then that method's chunk, recursively"* read as
  though the whole thing recurred.

**And two about the language**, neither a defect:

- **No shift can produce a negative integer**, there being no unsigned type:
  `shiftLeft(#56)` on a byte of 128 or more is a value larger than an i64 holds,
  and the language traps rather than wrapping. The trap is right.

  *This was first written up as "Solum can write an integer into a `.sob` that it
  cannot read back", and that was wrong.* Arithmetic reaches what shifting
  cannot — `(b - 256) * 2^56` is the same number by a route where every step
  fits — and the disassembler reads INT64_MIN correctly. The claim was made on
  the strength of one route failing and disproved by trying to write it down as
  [3.12](ROADMAP.md#312-no-shift-can-produce-a-negative-integer).
- **A float has to be decoded by hand**, one bit-field at a time, because
  nothing reinterprets an integer's bits as a float. `readFloat` is IEEE-754
  binary64 written out in Solum. It works — `2.5` comes back `2.5`.

**Checked against the oracle**: identical offsets, opcodes, operands and jump
targets to `solvm --dump` over eight files and 7,673 instructions, including
`lib/json.sol` and `lib/html.sol`.

### The neighbour that could not be a program

The obvious next thing to write here is the other question about a `.sob` — not
*what instructions are in it* but *what does it export*, which is what anybody
asks of a library they did not write. It is not in this directory and cannot be,
and the reason is worth recording on the page about what belongs here.

**The globals are slots on an object with no name in the language**, so neither
`slots` nor `perform` reaches them: a program cannot list what it has bound, let
alone what a file it loaded bound. Whatever answers that question has to hold the
root object, which is C. It shipped as
[`solid --exports`](REFERENCE.md#what-a-file-exports) — a mode of the debugger,
because the debugger is the other thing here that holds the root, and its
`globals` command is the same question asked from a prompt.

**disasm could have faked it and would have been wrong**, which is the more
useful half. Collecting every `SETGLOB` out of the top-level chunk is a dozen
lines from where this program already stands — and `lib/text.sob` binds no global
at all, hanging `asUtf8` on `integer` instead, so that report would be confidently
empty for a library with two messages in it. The surface has to be read by
loading the file, not by reading it. See
[6.38](COMPLETED.md#638-nothing-says-what-a-compiled-file-exports--done).

## expect — the examples and the documents, checked against what they claim

Runs every file in `examples/` and checks the inline comments that say what each
line prints.

```sh
./bin/solvm programs/expect.sob                      # all of examples/
./bin/solvm programs/expect.sob examples/numbers.sol # one file
./bin/solvm programs/expect.sob programs             # another directory
```

Over `examples/` alone that is 30<!--count examples-files--> files and
559<!--count examples-claims--> claims:

```text
21 files with expectations, 402 claims checked
72 lines print without saying what, and are not checked
2 runs ended with a non-zero status, which is what a documented error does

every claim holds
```

The two numbers in the sentence above the block are recounted on every build;
the block itself is a transcript, and a transcript is the one thing here nothing
can check. That is the shape of the remaining gap, in miniature.

**The narrowest customer of the eleven — this repository — and a real job all the
same.** `examples/` carries about four hundred comments of the form
`#2:add(#3):print.  ; #5`, and until this existed nothing checked one of them.
The suite compiles every example and never ran one, so those comments were true
because somebody looked, once, at the time — the same standing the `.sob` format
table had when [disasm](#disasm--a-sob-file-read-and-disassembled) found it
three sections out of date. They are also the first thing a newcomer reads.

**It is in `make test` now**, in `tests/test_cli.c` with the other tests that
run the binaries as a shell would — **1007<!--count claims--> claims on every build**, in about
sixteen seconds, and it fails the build if one stops holding.

**And it holds one document against a file rather than against a run.**
[GRAMMAR.md](GRAMMAR.md) opens by saying it is the same grammar as
[solum.bnf](../programs/check_syntax/solum.bnf) in a form a person reads, and
that is the largest claim on the page — everything else there is one production,
and that sentence is all of them at once. Every production is now compared
character for character, once runs of whitespace are collapsed, so a rule that
gains an alternative in one file and not the other fails rather than drifting.
**Twenty-three agree and two are prose**, `string` and `comment` being written
*any character but a quote* where the notation says `! '"'`; those two are
counted and reported rather than skipped quietly, so the excusing is visible.

Aligning the two to make the comparison possible found `primary` listing its
alternatives in a different order in each file. Harmless — there is no token two
of them could both match — and exactly the drift the check exists for, since the
next reordering might not be.

**And it checks the SolaBasic documents, which are in another language
entirely.** [SOLABASIC.md](SOLABASIC.md), its
[reference](SOLABASIC-REFERENCE.md) and its
[cheatsheet](SOLABASIC-CHEATSHEET.md) carry seventy ```basic blocks, and a
fenced block naming a language was the one thing this checker skipped — so a
repository that defines a dialect, ships a compiler for it and writes three
documents about it was checking all three by eye.

**The expectation is a ```text block under the ```basic one, not a comment on
the line**, and the reason is BASIC's own output: `PRINT 42` writes a space
where a minus would go, then the digits, then a *trailing* space. Leading spaces
are what a print zone and `TAB` are made of and a comment cannot show them; a
trailing space in a comment is invisible and the first editor to touch the file
would strip it. Inside a fence the leading ones survive. So trailing whitespace
is ignored on both sides and leading whitespace is not — the trailing space
after a number is held instead by `programs/sola/*.out`, which `test_cli`
compares byte for byte.

**Twenty-nine of the seventy are checked, and the rest are counted rather than
guessed at.** Sixteen are declarations that print nothing, thirteen name a label
or a `SUB` that lives in the prose around them rather than in the block, three
loop for ever on purpose — that being what a backwards `GOTO` looks like — and
one reads from the terminal, so what is shown under it is a *session* and not an
output. That last one is told apart by reading the statement rather than by the
run failing: `INPUT #1, a` takes from a file and is fine.

**Writing them down found five examples that only ever demonstrated half of
themselves.** A one-line `IF ... ELSE` whose variable was never assigned took
the `ELSE` every time; an `ELSEIF` chain and a `SELECT CASE` both fell through
to the last arm; and a counted loop printed twenty lines where three would have
said the same thing. None was *wrong* — each is now assigned a value that lands
on the arm it is there to show. **An example nobody runs cannot report that it
is demonstrating the wrong branch.**

**And it checks the documentation too.** The guide and the reference carry the
same notation inside ``` fences, and nothing checked those either — they are the
two documents a newcomer actually reads. 446<!--count docs-claims--> claims
across twenty-six<!--count docs-documents--> documents,
and two more on `README.md` and `index.md` — the front pages, which were the
last two things nothing checked.

**A block from a document runs in a scratch directory**, because this executes
documentation and documentation shows how to delete things — one block with
literal arguments put back a file a commit had deliberately removed. A shipped
example is not moved: those run from the repository root by convention.

That half found two things. The guide showed a stack trace reading
`[line 1] in block`, a format that predates
[6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done) adding the
filename — the illustration was never updated when the format changed. And
[class-and-instance.md](class-and-instance.md) said `integer` has 24 slots,
three times, where it has **37<!--count integer-slots-->**: messages were added
and the count was not.
That number is safe to state now precisely *because* it is checked.

**A block that does not run is a failure**, and that is a change: it used to be
a count. The reading was that such a block continues one further up or shows
syntax rather than a program — both true, and both also true of a block with a
typo in it. Counting what was in them found **54 claims in 42 blocks**, one
claim in thirteen, none of them checked and none of them reported.

Two things emptied the category. **A page is read as a page**: a block that will
not run alone is run again on everything the document established before it, so
the reference's *continuing the `point` above* reaches a `point` 370 lines back.
That accounts for 28 of the 42. And **a block that is not a program says so**,
with a word after its fence — a `text` tag for a session or a sketch, `sh` for
a shell transcript, `c` for C, the last two of which the documents were already
writing. That accounts for 14. The remaining 8 were broken.

The escape hatch is deliberately the visible one: a reader can see a fence that
says `text`, and cannot see a silence in a count.

**And it recounts what the prose says about this repository.** A sentence is
neither a comment on a printing line nor a fenced block, and a number in one has
no notation saying what it counts — so it is given one, which renders as nothing
and leaves the sentence as it was:

```text
[expect.sol](../programs/expect.sol) checks 1007<!--count claims--> claims
```

Each name is recounted from the repository as it stands. A name the table does
not know is a failure, so a marker cannot be misspelled into silence. A
program's *position* needs no marker, because the phrase is already one: nine of
the eleven open with `The fifth program here`, and the headings on this page put
them in that order.

That found `float` answering 26 messages where ROADMAP 3.14 said 21 and rested
an argument on it, the reference's index saying 121 messages across 215
registrations where it is 122 across 216, and the sample output above, which had
been showing 398 claims for a while.

`CHANGELOG.md` is the one document whose *blocks* are skipped — it records what
was true at each release, so its snippets describe past states on purpose.

**Its headings are read, though, for the commit hash each one names.** An entry
cannot carry its own hash, so it goes in saying `pending` and a follow-up commit
substitutes the real one — and until [ROADMAP
3.21](COMPLETED.md#321-a-changelog-hash-is-written-by-hand-and-nothing-checks-it--done)
nothing asked whether that had worked. Once it had not: an entry carried a
literal `%s` where its hash belonged for two days, through every `make test`,
and was found by a person reading the page. Everything backticked after a
heading's last em dash must now be seven hexadecimal characters or the literal
`pending`. It does not ask git whether the commit exists, which would couple
this program to a repository — it reads files and runs programs today, and a
tarball with no `.git` in it checks clean.

**What it found**, once every block was actually being run: the guide asking
`point:slots` for slots that page never defined, and `p:perform('show)` for a
method nobody had written; the reference binding `integer:slotAt('poly)` where
`poly` appears nowhere else in the document; a `lines` counter used and never
initialised; a `point:slots` answer that had gone stale when the section above
it gave `point` an `asString`; and, in `class-and-instance.md`,
`#45:new(#1):print. ; #1` — a claim about what the language does that the
language stopped doing, in a document whose own opening line says *every snippet
here has been run*.

Every claim that states a value now holds — all 729. What the first pass turned
up instead was that the examples used **three conventions** for these comments
and nobody had noticed, because nobody had had to parse them:

```
; #5                      the value alone
; #7 -- and why           an aside after a dash
; #8 distinct words       an aside with no dash at all
```

The checker learned all three rather than declaring two of them wrong, which is
the choice worth recording: a checker that insists on a convention its subject
never agreed to is measuring itself. Nine comments were glosses rather than
claims — a timestamp that changes every run, a duration at the clock's floor,
`; midnight` beside a time — and those now open with `--`, which the checker
reads as an aside claiming nothing.

**What it deliberately does not do** is demand line-for-line agreement. A claim
must appear in the output *after* the one before it, because one statement can
print many lines. The cost is that a claim could be satisfied by a later
coincidental match; the benefit is that it works on files with loops in them,
which is most of them.

---

## bench — how long does it take, and is the difference real?

Runs a command many times and reports the shape of what came back; given two
commands, says whether the difference between them survives the noise.

```sh
./bin/solvm programs/bench.sob                       # 20 runs of `solvm --version`
./bin/solvm programs/bench.sob 20 ls -l              # one command
./bin/solvm programs/bench.sob 40 cmd a -- cmd b     # two, interleaved
```

```
A:  ./bin/solvm nothing.sob
  runs     40
  min         2.372 ms
  median      2.617 ms
  p90         2.852 ms
  max         3.477 ms
  mean        2.656 ms  +/- 0.233

B:  ./bin/solvm expect.sob index.md
  runs     40
  min        16.755 ms
  median     17.683 ms
  p90        18.219 ms
  max        18.735 ms
  mean       17.695 ms  +/- 0.462

A / B    0.148 times, 95% interval 0.145 to 0.151
         A is faster
```

**Written to press on a gap rather than to do a job that happened to need one**,
which makes it the odd one out here. Every program before it was a job first.
This one starts from a fact about the repository: it has been quoting timings
for six releases — 40.5µs to build a machine, 121µs for a request, 279µs to
compile a chunk — and every one of them was taken by hand, once. A number taken
once is a sample of one, and the run above shows why that matters: the maximum
is 47% above the minimum on a quiet machine.

**Two commands are interleaved, and a coin decides which goes first each round.**
A machine drifts over the course of a minute — something else starts, the CPU
warms and throttles — so timing all of A and then all of B measures the minute.
Strict alternation is better and is still a pattern: anything on the machine
with a period of two runs lines up with it exactly.

**The interval is a bootstrap, and it is what makes the answer honest.** Timings
are skewed — bounded below by the work and unbounded above by whatever else
happened — so the tests that assume a normal distribution do not apply. Instead
it resamples both sets two thousand times and reports where the middle 95% of
the ratios fell. If that interval contains 1, the right answer is *this many
runs cannot tell them apart*, and it says so rather than reporting a winner.
Given the same command twice it answers `1.001, interval 0.985 to 1.015` — which
is the test the tool has to pass before any of its other answers are worth
reading.

**What it found is [3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done)
and [3.15](COMPLETED.md#315-a-childs-streams-cannot-be-redirected--done).** There was no
`sqrt`, no `min`, no `max` and no randomness in the language, so this file
carried all four. Writing them is easy; **getting them right is not**, and the
square root here was wrong twice, each time silently: first as twenty fixed
iterations, right to twelve places at 2 and wrong in the fourth digit at 1e10,
and then — in the version written to fix that — as a capped loop that answered
`8.67e281` for `sqrt(1e300)`. All four are the language's now: `sqrt` is a
message a float understands, `min`, `max` and `between` are in
[math.sol](../lib/math.sol), and the generator this file carried is
`random:new` — which was built because **measuring the one here found what was
wrong with it**. The generator was fine; the seeding was not, and neither half
of that was fixable in Solum. Two runs a microsecond apart got consecutive
seeds, and the first coin flip was then exactly the parity of the start time
while the first resample index of 21 took three values out of 21.

**And testing that square root at 1e300 found a bug in the VM.** Formatting a
float with a fixed number of decimals wrote into a 64-byte buffer and then used
`snprintf`'s answer — the length it *would* have written — as the length of the
result, so `1e150:asString("0.6")` returned 157 characters of which 93 were the
stack behind the buffer. Fixed, with the buffer sized for the worst case the
format spec allows and the length clamped to it regardless.

**The two faults hid each other.** The 1e300 test was read as showing a
formatter bug and a square root that had converged, because the digits were
checked against the C library and matched. They were the right digits of the
wrong number. A test that compares how an answer *prints* is not a test of the
answer.

## basic — an interpreter for another language

Reads a BASIC listing and runs it. The dialect is **ECMA-55 Minimal BASIC
(1978)**, chosen because a published standard means what counts as finished is
settled by somebody other than the author of the interpreter — twenty statements
and eleven supplied functions, and no room to declare victory early.

```sh
./bin/solvm programs/basic.sob
```

```text
HELLO, WORLD
 14 
 20 
 2.5 
-7 
 42 
 0 
A              B              C
 1  2  3 
COUNT:  99 
```

Those spaces are the standard rather than an accident. A number is written as a
sign character — a minus, or a space when it is not negative — then the digits,
then a trailing space, which is why BASIC output has its airy look and why a
negative number lines up under a positive one.

**The whole language is here** — all twenty statements and all eleven supplied
functions — and it runs about **420,000 BASIC statements a second**. `LET`,
`PRINT`, `REM`, `END` and the expression grammar; `GOTO`, `IF-THEN`,
`FOR/NEXT`, `GOSUB/RETURN`, `ON-GOTO`, `STOP`; then text, arrays, `DIM`,
`OPTION BASE`, `DATA`/`READ`/`RESTORE`, `INPUT`, `DEF FN`, `RANDOMIZE` and the
functions. It also takes a listing of its own:

```sh
./bin/solvm programs/basic.sob programs/basic/wave.bas
```

Given a file it runs only that — the demonstrations it carries are skipped,
because a tool asked to run your listing should not print its own first. A
listing that failed leaves a **non-zero status**, so it composes with a shell,
and says why on **standard error**, so a redirect keeps the two apart.

**And it has a prompt**, which is the interface BASIC actually had:

```sh
./bin/solvm programs/basic.sob --repl
./bin/solvm programs/basic.sob --repl programs/basic/sieve.bas
```

One rule and six commands. A line beginning with a number goes into the program,
a line that does not happens now, and a number on its own deletes that line —
which is how a line is removed when the only editor you have is the line you
type again. `LIST`, `RUN`, `NEW`, `LOAD`, `SAVE` and `BYE` are the rest.
`programs/basic/session.in` is a recorded session and `session.out` the
transcript it must still produce.

`PRINT` shows **six significant digits** with no nought before the point, which
is what BASIC shows and what Solum does not — `1/3` is `0.3333333333333333` in
Solum and `.333333` here. A million comes out as `1E+06`, which looks like a
defect and is the standard: seven digits to the left of the point is more than
six significant digits can describe.

Four of the listings in `programs/basic/` carry a **recorded transcript**
compared byte for byte on every build. That is what the claims in comments
cannot be — `programs/` is not one of the documentation checker's subjects, and
the output of a BASIC program is exactly where a comment goes stale unnoticed:
print zones, six digits and the trailing space after every number are invisible
to a reader and all load-bearing.

**It is checked against a suite somebody else wrote.** The
[NBS Minimal BASIC Test Programs](../programs/basic/conformance.sh) are 208
programs written at the National Bureau of Standards in 1980 to test an
implementation against ANSI X3.60-1978, the standard ECMA-55 mirrors — a US
government work, public domain, and the only test of this interpreter not
written by its author. `programs/basic/conformance.sh` fetches and runs them;
it is not part of `make test`, because it needs the network and because the
suite is written for a person to read rather than for a machine to score.

**It found seven defects, and none of them had been caught by the eighty-three
claims in the file** — `DATA` being raw text rather than tokens, a datum having
no type until a `READ` takes it, `DEF` needing no parameter, `NEXT` having to
search the loop stack, `FOR` having to nest dynamically through `GOSUB`, `DIM`
being a declaration rather than a statement, and exceptions that report and
carry on. Those claims check what the author of the interpreter thought to
check, which is exactly what an external suite is for.

**One thing here is not the standard, and it is written down in the file rather
than left to be found.** ECMA-55 makes a space insignificant outside a string,
so `FORI=1TO10` and `PRI NT` are both legal BASIC; here they are not. Fixing it
means a tokeniser that knows where it is in the grammar — `FORI` is `FOR I` only
because a statement begins with a keyword — which is a different design rather
than a missing branch.

A BASIC program is a graph rather than a sequence, and its edges are line
numbers, so all of them are followed in three passes at load: a jump becomes an
array index instead of a search of the listing, a jump to a line that does not
exist is reported before the program prints anything, and a `FOR` finds its
`NEXT`. That last one is what lets a loop with an empty range skip its body —
it already knows where the body ends.

The first of these to be an interpreter for another language rather than a
tool for this one. It holds a second language's whole state — a variable table,
a program counter, a listing — and what makes it different from the other
programs here is that it is judged against a specification: either a listing
gives the answer the standard says, or the interpreter is wrong.

**What it found**: the trigger
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done) had been holding
open. That entry held `pow`, `log`, `exp` and trigonometry, waiting for *a
program that wants an angle*. Six of Minimal BASIC's eleven supplied functions
are `SIN`, `COS`, `TAN`, `ATN`, `EXP` and `LOG`, and `^` needs `pow` — so this
was not a program that would like an angle, it was one that could not be
finished without them, and could not decide to want fewer: they are in the
standard it is measured against. For two days `^` raised rather than being
stubbed with repeated multiplication, an operator right for `2^3` and quietly
wrong for `2^0.5` being the same silent failure that entry already recorded
twice. Then the decision was taken and all eleven landed at once.

It also found [3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done):
`INPUT` has to show a `?` and read the answer beside it, and there was no way to
write to standard output without ending the line. `system:write` closed that the
same day, and it is half of what [edit](#edit--a-file-on-the-screen) needed
before it could draw anything at all.

**And a happier finding, about line numbers.** They are usually a joke, and here
they are what makes the job possible. `SOL_FRAMES_MAX` caps recursion at about
254 ([3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels)), and a
tree-walking interpreter for a modern language spends frames in proportion to
how deeply its *source* nests — so it would run out of machine before it ran out
of program. A line-numbered BASIC never nests: the run loop is a program counter
over a sorted table of lines, and `GOSUB` and `FOR` are explicit stacks in
arrays, which is heap rather than frames. The only recursion is in the
expression parser, and it runs once at load rather than once per execution.

---

## edit — a file on the screen

**The twelfth, and the first that draws.** Every other program here writes a
line at a time and reads a line at a time; this one owns the screen, puts the
cursor where it wants it, and redraws the whole of what you are looking at
between one keystroke and the next.

A modal editor in the manner of vi, in about fourteen hundred lines — two
fifths of them comment, which is where its arguments are.

```sh
./bin/solvm programs/edit.sob                 # a buffer it writes for itself
./bin/solvm programs/edit.sob notes.txt       # your own file
```

`h j k l` and the arrows move, `w` and `b` by word, `0` and `$` to the ends of a
line, `gg` and `G` to the ends of the file, ctrl-f and ctrl-b by a screen.
`i a I A o O` begin insert, `x` deletes a character, `r` replaces one, `~` swaps
its case, `J` joins two lines, `e` goes to the end of a word and `fx tx Fx Tx`
find a character on the line.
`d`, `y` and `c` take a motion — `dw`, `ce`, `d$`, `dj`, `dG`, `d'a`, and
`dd`/`yy`/`cc` for whole lines — `p` and `P` put back what they took, `ma` marks a place and `'a`
and `` `a `` go to it, `u` and ctrl-r undo and redo, `.` does the last change
again, and a count repeats: `3j`, `2dd`, `d2w`, `10G`, `3p`, `3.`.
`/pattern` and `?pattern` search forwards and back, `n` and `N` do it again,
and `:s/find/replace/` changes what they find — `/g` for every match on the
line, `:%s` for every line in the file.
`:w`, `:w name`, `:q`, `:q!`, `:wq` and a bare number to go to that line. Escape
leaves insert mode, with the caveat below.

**It was written to find one thing, and the thing was written down first.**
[ideas.md](ideas.md#programs-that-would-press-on-something) predicted, before
this file existed, that an editor would want *the terminal's size* and find
nothing to ask. That is exactly what happened, in the first hour, and it is
[6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done):
`system:terminalSize` now, closed the same day it was raised.

**What made it an entry was a measurement rather than the absence.** The number
was always reachable — `stty size` through a shell — at 7.0ms an ask, which is a
fork, an exec and a pipe per keystroke if a program measures each time it draws.
So the editor measured once at startup, and every window resized after that was
a window it drew wrong until it was restarted. One ioctl is about a microsecond,
so it now measures on every frame and the resize notification the language has
not got stops being something anybody needs.

**And it confirmed a warning that had only ever been theoretical — then got it
fixed.** [examples/keys.sol](../examples/keys.sol) had said since the day
`readKey` landed that a byte-level reader cannot tell the escape key from the
start of an escape sequence, since telling them apart needs a read that gives up
after a few milliseconds. Nothing had ever bound that key, so the warning stood
untested. A modal editor binds it to the most frequent action there is, and
escape stopped taking effect until the *next* key arrived.

That is
[6.35](COMPLETED.md#635-a-read-that-gives-up--done): `system:keyWaiting(0.05)`,
*is a byte coming?* — and nothing follows an escape that fast except a machine.
The editor asks, and leaves insert mode there and then. **The warning was
right, it was written by a program that was not annoyed by it, and it waited for
one that was.**

**Three smaller things it found**, none of them worth an entry:

- **An array cannot have an element put into the middle or taken out of it.**
  `add` appends and `removeLast` pops, so `o` and `dd` rebuild the array around
  the change. That is one pass over the lines per line inserted, which for a
  file anybody edits is nothing, and it is why the two are one method each here
  rather than one call each.
- **`system:write` flushes**, which is what makes one frame one call. A redraw
  that arrived in pieces would be a redraw you can watch happening.
- **A tab is one byte and eight columns**, and everything that positions a
  cursor has to hold both numbers at once. That is not the language's doing —
  every editor ever written has this — but it is where most of the arithmetic
  in this file went.

**Searching came a day later, and most of it is a library.**
[lib/pattern.sol](../lib/pattern.sol) is regular expressions in the subset vi
searches with — `.`, `*`, `[abc]`, `[^a-z]`, `^`, `$` and `\` — and the editor
is `/`, `?`, `n`, `N` on top of it. What the program added to the library was
the part a matcher cannot know: **a file here is not one string.** It is an
array of lines and the cursor is a row and a column, so a search is a walk over
lines, and `^` and `$` mean the ends of a *line* without anybody having decided
that they should. Both directions wrap and say when they did, because a search
that comes back round to where it started looks exactly like one that found
something new. And a pattern that will not compile puts its complaint on the
bottom line rather than ending the editor.

**And substitution came with it.** `:s/find/replace/` is the search plus
`replaceAllIn`, with `&` in a replacement standing for what was matched and the
delimiter being whatever character follows the `s` — so
`:s#/usr/bin#/usr/local/bin#` needs no escaping. It is deliberately *not*
`/find/replace/`: `/src/lib` is a good search for a pattern with a slash in it,
so a bare `/a/b/` would mean deciding that some searches are silently
substitutions. vi put substitution on the colon line for that reason.

The report is **counted rather than compared** — *17 substitutions on 9 lines* —
because the number of lines whose text ended up different is a smaller number
and a wrong one: replacing `a` with `a` changes nothing and is still a
substitution. And `:%s` is the first thing here that can change a hundred lines
at once with **still no undo**, which is what the count and `:q!` are for.

**And then it was made to be vi rather than to look like it.** The notation is
`[count] operator [count] motion`, where any of the three may be absent — and an
editor that implements that as a table of keys is a pile of special cases, one
row per pair. So there are two dictionaries and one dispatcher: a **motion**
answers a *place* and moves nothing, an **action** does something, and the
dispatcher decides which a key is and whether an operator is waiting for a place
to work over. `dw`, `3dw`, `d3w`, `d$`, `dj`, `dG`, `y'a`, `2yy` and `3p` are
then all the same code. Adding `e` or `f` later is one line in the motion table
and no change anywhere else, which is the test of whether the grammar was
implemented or imitated.

The motions are **the ones the cursor uses**: an operator runs `wordForward` and
puts the cursor back, so `dw` and `w` cannot disagree about where a word ends.
That is also where the one bug of the rewrite lived — a *cursor* may not stand
past the last character of a line and a *range end* must be able to, which is
what `dw` on the last word of a file needs and what the clamp did not know.

A **place** carries how it should be read: whole lines or a piece of text, and
whether the character it lands on is inside the range. `dj` is two whole lines,
`d$` includes the last character, `dw` does not include the first character of
the next word. And an exclusive motion that ends in the first column ends at the
end of the line before instead — the real vi rule, and what stops `dw` on the
last word of a line from dragging the next line up into it.

One unnamed register, holding either lines or a piece of text, and **which of
the two decides what `p` does** — `yy p` copies a line below this one, `yw p`
copies a word after the cursor. A mark is a row and a column, and the row moves
when the text does: `insertLine` and `removeLine` shift the marks below them,
and a mark on a line that is deleted is dropped rather than left pointing at
whatever moved into its place.

**And undo is one array copy per change**, which is the finding worth having out
of this program's third day. A change is remembered by keeping the **whole
buffer**, which sounds extravagant and is not: a line is a **string**, a string
cannot be changed, so a copy of the array of lines shares every line with the
buffer it came from. The copy is one pointer per line and the text is never
copied at all.

Measured, because the claim is exactly the kind that is believed and wrong: ten
thousand lines of ten characters and ten thousand lines of a *thousand*
characters snapshot in **0.095ms and 0.078ms** — one measurement twice. A
hundred times the text costs nothing, which is what sharing looks like from
outside.

That is why this is a stack of buffers rather than a list of inverse operations.
*How to undo a delete* is the design a mutable-string language is pushed
towards, and it is a second implementation of every command — one to do it and
one to undo it, with the second exercised only when something has already gone
wrong. The price here is array slots instead: a hundred states of a
ten-thousand-line file runs under `--memory=16M` and not under 15M.

**Every change goes through three methods** — `setLineAt`, `insertLine`,
`removeLine` — so a command cannot forget to be undoable. And **a change is one
keystroke, except in insert mode**, where everything typed between `i` and
escape is one: that boundary is drawn in the dispatcher rather than in the
commands, which is what makes `u` after a typed paragraph useful rather than
infuriating.

**And `.` repeats the keys rather than a description of them.** The other way is
to remember *what was done* — an operator, a motion, a count, some inserted
text — and do it again, which is a second description of every command that can
change the text and a second place for them to disagree. Keys are what the
editor already understands, so feeding them back in is the same path they took
the first time and `.` cannot drift from what it repeats.

**What counts as a change is what undo already decided.** `remember` is called
by the three methods that alter the text, so it is the one place that knows
whether a command changed anything; it sets a flag for `.` on the way past. A
command that only moves the cursor records nothing, and neither does `yy` — a
yank is not a change, which is vi's rule and falls out here rather than being
written down. Colon commands are left out on purpose: `:s/a/b/` changes the text
and `.` does not repeat it, here or in vi, because a colon command takes a line
of its own syntax and can name a range.

**It found one bug, and it was the first command able to.** `.` dispatches keys
of its own, and the count was being cleared *after* an action ran rather than
before — so the `3` of a replayed `3x` joined the count still pending and `x3.`
deleted the whole line. An action that runs other commands has to start from a
clean state, and nothing before `.` had ever run one.

**And then it was measured on a file worth the name**, which nothing here had
done: 50,000 lines, 2.3 MB. Loading, moving to the end, searching, editing and
undoing are all 0.03–0.05 s — and `:%s/alpha/ALPHA/g` across the whole file took
**7.7 seconds**, which is not slow, it is a hang.

Two things were wrong and both were the program's rather than the language's.
The matcher tried a match at **every position of every line**, where a pattern
beginning with a plain literal can ask `indexOf` — a primitive, scanning in C —
where the next candidate is. And the editor walked every line **twice**, once to
count the matches for its report and once to replace them. The library answers
both in one walk now, the way `capture` answers `"output"` and `"status"`.

**7.7 s to 2.4 s**, with the same 32,818 lines changed and all 136 behaviour
checks unmoved. The remaining cost is the matcher itself, which is Solum, and
that is the honest floor: `string:indexOf` scans those 50,000 lines in 0.007 s,
and the same scan written as a loop here takes 0.85 s. **A library's speed lives
at the boundary with the primitives**, and the way to be fast is to hand the
scanning back across it.

**And its behaviour is pinned by a hundred and sixty-five scripted sessions.**
[programs/edit/checks.sol](../programs/edit/checks.sol) writes a file, feeds the
editor a string of keys through a pipe and compares what was written against
what those keys should have done. It runs in `make test` and takes under a
second, and it exists because four days of building this produced one defect per
feature — the clamp that let `dw` leave the last character of a file, the count
cleared after an action rather than before, `c$` eating the space in front of
the cursor. Every one of those is a line in that file now.

**What it does not do**: no `U` — vi's *undo every change on this line* is a
different mechanism, not a level of this one. No `;` and `,` to repeat an `f`,
no named registers, no line ranges beyond `%`, and `J` joins without inserting
the space vi inserts — that rule has exceptions in it, and a rule with exceptions should
be wanted by somebody before it is written — `:1,5s/a/b/` is a parser this has not
got. Each of those is more of the same rather than more of the language, and
this program was written to ask the language a question.

---

## sola — a compiler for another language

Reads a [SolaBasic](SOLABASIC.md) program and writes a `.sob`. The file it
produces is run by `solvm` with nothing of this program present, which is the
difference between it and [basic](../programs/basic.sol) — that one *interprets*
another language, this one **compiles** one.

```sh
./bin/solvm programs/sola.sob                        # the demonstration
./bin/solvm programs/sola.sob prog.bas [prog.sob]    # a file
```

```text
i = 1
i = 2
i = 3
i = 4
i = 5
counted to 5
```

**All eight stages** of [SOLABASIC.md](SOLABASIC.md), and every one of them held
against a real QuickBASIC 4.5 rather than only against transcripts this compiler
recorded of itself. Stage 3 —
`GOTO` and labels — went first, because it is the claim the whole design rests on
and the document says to reach it in week one rather than week six. Stage 2 is
the structured half, stage 4 is procedures, and
[SOLABASIC-REFERENCE.md](SOLABASIC-REFERENCE.md) is what the three of them add up
to for somebody writing the language rather than reading about it.

**The claim is that `GOTO` cannot be written in Solum.** There is no
control-flow syntax here — a loop is a message send — so a translator from BASIC
to Solum *source* would have to compile every statement into a block, put the
blocks in an array, and dispatch on a label variable. That is a full send per
statement, which is roughly what `basic.sol` already pays as a tree-walker: a
slower interpreter wearing a compiler's name. In bytecode, `GOTO` is `OP_JUMP`
and `OP_LOOP`.

**And the verifier cooperates, which had to be checked rather than assumed.**
SolVM requires the paths into an instruction to agree on stack height. Every
SolaBasic statement compiles at depth 0 and ends with a `POP`, so a label is a
depth-0 merge point *by construction* and an arbitrary jump between statements
needs no analysis at all. That was measured before the compiler was written, by
hand-assembling a chunk with a backward jump to an arbitrary earlier offset, a
forward jump over dead code, and a conditional between them — and by breaking it
two ways to check the test could fail:

| | |
| --- | --- |
| a jump into the middle of an instruction | refused at load, exit 65 |
| a jump to a point at a different stack depth | refused at load, exit 65 |

The second is the one that matters, because it is what a compiler that got
clever would emit. **The depth-0 discipline is load-bearing rather than tidy.**

**The opcode is not known when the jump is emitted**, which is the whole of the
back end here. Forward is `OP_JUMP` and backward is `OP_LOOP` — two opcodes,
because the machine has no signed offset and the verifier relies on everything
else moving forwards — and which one a `GOTO` is depends on where its label
turns out to be. Both are three bytes, so three zero bytes go down as a
placeholder and a fixup list remembers where. Nothing moves afterwards, so no
offset already computed can be invalidated by a later patch, which is the trap in
every backpatching scheme that emits a short jump and grows it.

**A label is a string of characters, not a number.** That is CB80's rule taken
over whole, and it is what lets an old listing through unaltered: labels need not
ascend, need not be present, and nothing here ever sorts one.

```basic
100 PRINT "at one hundred"
GOTO 50
30 PRINT "never"
50 PRINT "at fifty, which is written after one hundred"
END
```

**And it is 45 times faster than the tree-walker.** The same counting loop —
200,000 iterations, two statements each — is 1.54s under `basic.sol` and 0.034s
compiled, both including VM start. [SOLABASIC.md](SOLABASIC.md) predicted
"roughly an order of magnitude" and was too modest; the entry that says so is in
that document's own change log, which is what it is for. It is still *a much
faster interpreter* rather than *compiled* — SolVM has no arithmetic
instruction, so a SolaBasic `+` is one `OP_SEND` and not an add.

**Stage 2 needed nothing the back end did not already have**, and that is the
finding rather than the feature. A `GOTO` needs a hole punched in the code and
filled in when its label turns up; `IF`, `SELECT CASE`, `FOR`, `DO` and `WHILE`
need exactly the same hole, filled in when their *closing line* turns up
instead. So the whole of stage 2 is one stack of open blocks, each frame holding
the holes it still owes an answer to. **The structured half of the language is
the unstructured half with a stack on top** — and doing stage 3 first is what
made that visible rather than lucky.

**The blocks are a stack and the statements stay flat**, which is the decision
worth arguing about. A parser building a tree is the other way and it is the
wrong way here: BASIC's blocks are not written as nesting, they are an opening
line and a closing line, and half the errors worth reporting are the two failing
to match. A stack has the mismatch in its hand —

```text
DO
NEXT i        →  line 2: NEXT closes the DO opened on line 1
```

— where a tree would have refused to parse and had less to say about why. It is
also what makes `EXIT FOR` reach the right loop: the innermost `FOR`, not the
innermost block, so an `EXIT FOR` inside an `IF` inside the loop is a search
down the stack rather than a walk over a tree.

**And a jump still goes wherever it likes.** `GOTO` out of a loop from inside an
`IF` works, and a label placed just before `NEXT` is how BASIC spells what a
later language calls `continue` — both in [escape.bas](../programs/sola/escape.bas),
because the two halves meeting is the thing worth a transcript.

**Stage 4's expensive item cost less than billed, because of how it is
represented.** QBasic passes by reference — assigning to a parameter assigns to
the caller's variable — and [SOLABASIC.md](SOLABASIC.md) called that the most
expensive thing in the language. It is a **one-element array**: a variable ever
passed by reference is kept in one *always*, so the call hands the array over and
the callee's `atPut` reaches the caller's storage. No wrapping at the call site,
no copying back, no temporary to keep alive across it, and nothing to get wrong
when the call is recursive. The part that was as billed is deciding *which*
parameters — a fixed point, because a parameter is by reference when its
procedure assigns to it or hands it on to something that does, and that chains.

**A procedure is a block, and it never captures its home frame** — every name it
uses is its own slot or a global — so [3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame)
never bites. [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) does:
a call is a real frame, recursion stops around 254 levels, and the trace names
the *BASIC* procedure and the *BASIC* line when it happens. SOLABASIC.md
predicted that before the compiler existed.

**Stage 1 is the type system, and types have to be settled before a byte is
emitted.** A conversion is an instruction acting on the top of the stack, so
widening an Integer has to happen *after* it is pushed and *before* the value
beside it — by which time it is far too late to discover it was needed. The tree
is typed in a pass of its own and emitting is a second walk that already knows
where the conversions go. **There is no boolean type**, as the language
definition says: a comparison is `-1` or `0` used as a number, so `NOT`, `AND`
and `OR` are bit operations and still read correctly.

**A supplied function is emitted where it is called**, because there is nowhere
to put a library — the `.sob` is the whole program and none of `lib/` is in it.
So `SGN` is a scratch slot and two conditional jumps, `LEFT$` clamps with two
comparisons before `copyFrom` is allowed near it, and `LTRIM$` is a loop. All of
it the same jumps a `SELECT CASE` compiles to.

**And 3.1 caught the compiler.** A helper here built the block that emits a
one-send builtin and stored it in a table — and that block read the helper's
parameters, so it captured a frame that had already returned.
[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) says a block
that reads its home frame cannot outlive it, and the machine said exactly that:
*block outlived the frame it was written in*. The table holds a symbol and a
selector now.

**`PRINT`'s rules were brought forward out of stage 6**, because stage 7 is a
comparison against a real QuickBASIC and it cannot compare anything while every
line differs in its spacing. A number is a sign character, the digits, and a
trailing space; `,` moves to the next zone of 14 and `;` moves nowhere; a
separator at the end of a line holds it open; the margin is 80.

**And the runtime for it is written in SolaBasic**, compiled by this same
compiler and emitted into any program that prints. That is not a flourish: those
rules are a line buffer, three loops and a decision about a leading nought, and
each of them is easier to read as BASIC than as a sequence of `emit` calls —
which is what `SGN` had to be, and what got `SGN` wrong the first time. It costs
a reserved prefix: names beginning `SOLA` belong to the runtime.

**Writing it turned up two things the compiler had wrong**, which is the argument
for writing the runtime in the language rather than around it. `nextIs` compared
a token's text without its kind, so the string literal `"-"` answered yes to
*is the next token a minus* and `T$ = "-" + MID$(T$, 3)` would not parse. And
`CALL` was missing from the statements a one-line `IF` may hold, so
`IF x > 80 THEN CALL Wrap` was refused. Neither was reachable from anything in
this repository until a real program was written.

**Stage 5's by-reference was free, which is the opposite of what a scalar
cost.** A Solum array *is* a reference, so `Sort(n(), 6)` hands the array over
and the callee's `atPut` writes the caller's storage because it is the same
array — no box, no analysis, nothing to keep alive across the call. And the
bounds being constant means most of the index arithmetic happens while
compiling: `a(i)` is `i - low + 1`, and a second dimension multiplies by a
stride the compiler already knows.

**Every subscript of a multi-dimensional array is checked, and a
one-dimensional one is not.** One out of range would otherwise land on a
*different element* rather than off the end — `a(1, 9)` in an eight-by-eight is
index 9, which is `a(2, 1)` — and answering the wrong element quietly is the one
thing this must not do. A one-dimensional array has nowhere for a bad subscript
to go except outside the array, and the machine refuses that itself.

**And it is compared against a real QuickBASIC**, which is the only check here
that can find something nobody thought of — everything else this compiler is
held to is a transcript recorded by its own author. **Twenty programs match byte for
byte**, five differ exactly where the language definition says they should, and
the comparison has found **four real defects that the transcripts did not** —
one of which a transcript had recorded as correct.

**And `PRINT USING` was built the other way round**, which is what having an
oracle is for: twenty-one formats went through QuickBASIC 4.5 *first*, and the
formatter was written to reproduce what came back rather than to reproduce what
somebody remembered. Every case matched on the first comparison but one, and
that one was this compiler disagreeing with itself — `PRINT USING` writing an
exponent with `E` where plain `PRINT` already wrote `D`.
[oracle.sh](../programs/sola/oracle.sh) runs a corpus in two halves:
`oracle/agree/`, which must produce the same bytes under both, and
`oracle/differ/`, which must not and says at the head of each file why. **That
turns the divergence list from prose into something that can fail** — a program
in `differ/` that starts agreeing means the divergence has gone and
[SOLABASIC.md](SOLABASIC.md) is now wrong about it.

**The verdict is not in.** The harness needs a QuickBASIC and this repository
has no dependencies beyond a C11 compiler and `make`; it keeps that by saying
what it needs rather than fetching it. Both of its paths were exercised with
SolaBasic standing in as its own oracle — every `agree/` matched and every
`differ/` was reported as having lost its divergence, which is exactly what that
arrangement should produce — so the mechanism is not taken on trust either.

**What is not here** is what the language definition marked *not yet* from the
start: random-access files, `ON ERROR`, `TYPE`, `REDIM`, `OPTION EXPLICIT`, and
`:` between statements on one line.

## check_syntax — a grammar, and a file held against it

Reads a grammar written in Wirth's EBNF, then reads a second file and says where
it stops agreeing with it. **The grammar is the program**: hand it
[pascal.bnf](../programs/check_syntax/pascal.bnf) and it checks Pascal, hand it
[solum.bnf](../programs/check_syntax/solum.bnf) and it checks Solum.

```sh
./bin/solvm programs/check_syntax.sob                              # the demonstration
./bin/solvm programs/check_syntax.sob grammar.bnf source.pas       # a file
./bin/solvm programs/check_syntax.sob grammar.bnf source.pas tokens  # the token stream
./bin/solvm programs/check_syntax.sob grammar.bnf                  # the grammar alone
```

```text
programs/check_syntax/missing-semicolon.pas:13:3: syntax error: expected ';', 'else' or 'end', found 'n', reading <if-statement>
    13 |   n := n + 1;
       |   ^
programs/check_syntax/missing-semicolon.pas: 1 error
```

**Two dialects, because "a file written in BNF" means the older one at least as
often.** Wirth's notation — `expression = term { "|" term } .` — is the one the
Pascal report uses and the one that describes itself. The older shape —
`<expression> ::= <term> | <expression> "+" <term>` — has angle brackets, `::=`,
no terminator and one production per line. Both are read by the same reader: a
production ends where the next one starts, which is a name followed by a
definition symbol, so the `.` is optional rather than required.

**A grammar has two halves and has to say where the seam is.** Pascal's syntax is
written over tokens and says nothing about how characters become them; Wirth's
report gives the lexical rules in the same notation, so both live in one file
with `%syntax` naming the line between. That seam is declared rather than
guessed, because `identifier` and `expression` look alike and a checker that
guesses wrong reports a correct file as broken — which is the worst thing this
program could do.

**Three extensions, and no more.** Wirth's notation cannot describe a lexer: it
has no range, no negation, and no way to write a tab. So `"a" .. "z"` is a range,
`! factor` is one character provided that does not match, and `"\n"` is what it
looks like. All three are refused in a syntactic rule, where they would be asking
a question about characters in a place that has only tokens.

**Where the error is reported from is the whole difficulty.** A backtracking
matcher fails at the top, at position one, with everything it tried rolled back —
`myprog.pas:1: does not parse` is a sentence about the program that printed it.
So the position is the **furthest token any terminal ever failed at**, recorded as
the match goes and never rolled back, and the message lists what was wanted there.
The innermost rule that had already *consumed* something is named too, which is
what turns `reading <multiplying-operator>` into `reading <if-statement>`.

**The reserved words are derived, not declared.** `begin` tokenises as an
identifier, so `x := begin` would otherwise parse. Every word-shaped literal in
the syntactic half is reserved against the token kind it would tokenise as, which
recovers Pascal's 35 keywords from pascal.bnf without a list anywhere.

### Solum, against itself

[solum.bnf](../programs/check_syntax/solum.bnf) is the whole of this language —
thirteen syntactic rules and nine token rules — and
[GRAMMAR.md](GRAMMAR.md) is the same grammar written for a person to read.

It was taken from `solas/src/lexer.c` and `solas/src/compiler.c` rather than
from the documentation. **The only grammar written down anywhere was a sketch**,
at the top of `solas/include/solas/parser.h`, which says of itself that it goes
only "as far as docs/design.md pins it down" — it has no blocks, no arrays, no
symbols, no temporaries and no slot assignment.

**Fifty-six of the fifty-seven `.sol` files in this repository check clean**,
and the fifty-seventh is a depth limit rather than a disagreement — see below.
Every example and every library file is swept on each test run, which is what
stops the grammar from quietly narrowing: none of those thirty-eight files was
written with it in mind.

Three things the grammar makes visible that prose does not.

**There are no reserved words**, and the tool reports this by having none to
report. It reserves every word-shaped literal a syntactic rule mentions, and
this grammar mentions none: `nil`, `true`, `object` and `self` are ordinary
identifiers that happen to be bound. A test asserts the absence.

**`.` separates rather than terminates**, uniformly — required between two
statements, optional after the last, in a file, a block and a group alike.

**`:=` may follow a send that took no arguments and not one that took some.**
That is how a slot is bound, and `o:at(#1) := #2` is not a way of storing into a
collection. The grammar says so structurally, by putting both possibilities
inside `send` rather than after the chain, and `solas` and this checker refuse
the same file at the same column.

### What it found

**Every diagnostic it has about grammars came from a grammar being wrong in a way
that blamed the wrong file.** That is why the checking half is as large as the
matching half.

| | |
| --- | --- |
| `letter` and `digit` are not tokens | the first Pascal file read as a stream of them |
| `symbol = "." \| ".."` never produces `..` | ordered choice inside a rule is not longest match across rules |
| `<expr> ::= <expr> "+" <term>` | left recursion, which a PEG cannot do at all |

The first is the sharpest. `letter` and `digit` are lexical rules and they are
not tokens — they are what the token rules are made of — and nothing about their
shape says so. Both they and `identifier` match `T`; longest-match ties go to the
rule declared first; `letter` is declared first. The report was 130 syntax errors
in a file with nothing wrong with it. There is a `%fragment` directive to say
what was meant, and a warning — *a token kind no syntactic rule can match* — for
when somebody forgets it.

The third would otherwise arrive as `call depth exceeded` **against the subject
file**: a sentence about Pascal when the mistake is in the BNF. It is found by
reading the grammar, before anything is matched.

**The one measurement that had to be taken twice.** Line and column are computed
from a byte offset by counting newlines from the start of the file, on the
argument that a run wants four of them — one per message — and that carrying a
line through every token and every node is a field on everything for a saving
nobody would notice. That argument is right about errors and was **wrong about
the token dump**, which wants one per token. On the largest file here —
`programs/sola.sol`, 4,778 lines and 31,887 tokens — it took **seventeen and a
half minutes to list the tokens of a file it checks in under four seconds**.
Tokens arrive in order, so the dump carries the line instead and makes one pass
over the source: 1,052 seconds became 3.6, which is 270 times. **A design note that says how often something is wanted is a
claim about every caller, including the one written afterwards.**

**What it will not do is revisit a choice.** This is a PEG: `a | b` tries `b`
only if `a` failed, and a choice that succeeded is not reconsidered when the rule
containing it fails later. That costs nothing on an LL(1) grammar, which Wirth's
Pascal is and most published grammars are. Where it costs something — an
alternative that is a proper prefix of a later one — the case is exactly
detectable and is reported as a grammar warning rather than left to mis-parse
quietly. The rest is stated in the file's header, because a limitation a program
does not admit to is one its user discovers as a wrong answer.

**The depth limit is gone, and the numbers are why it went.** The matcher was a
tree walk — one Solum frame per node of the grammar, against a machine with 254 —
and the limits were measured through real grammars rather than guessed:
**19 levels of nested `begin … if` and 28 nested parentheses** against
pascal.bnf, **13 nested blocks** against solum.bnf. A grammar rule is not one
frame: one level of a language's own nesting costs about four rule references
and a reference costs two frames, so the multiplier is the grammar.

**What settled it was a file somebody had already written.**
`experiment/lexer.sol` holds a 24-level nested `ifElse` staircase, the deepest
expression in this repository; `solas` compiles it and the checker could not
read it. Every earlier measurement on
[ROADMAP 3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) needed a
generator to reach the limit. And the shape that did it is the shape
[control.sol](../lib/control.sol) *recommends* — a staircase written instead of
`ifElseIf`, precisely to save frames. Both are right: a staircase saves them in
the program dispatching and costs them in anything walking the result as a tree.

**So the matcher is an explicit stack machine.** The grammar compiles once to a
flat instruction list — `Call`, `Ret`, `Choice`, `Commit`, and terminals, which
is [LPeg](https://www.inf.puc-rio.br/~roberto/docs/peg.pdf)'s instruction set —
and the stack lives in Solum arrays rather than in the machine's frames.
Backtracking is a stack entry instead of an unwind: popping to a choice point
discards every call made since it, which is exactly what recursion was doing for
free. **2,000 levels of nesting now check in both languages**, and what bounds
depth is memory.

| | |
| --- | --- |
| `a \| b` | `Choice L1 ; <a> ; Commit L2 ; L1: <b> ; L2:` |
| `[ a ]` | `Choice L1 ; <a> ; Commit L1 ; L1:` |
| `{ a }` | `L1: Choice L2 ; <a> ; LoopCommit L1 ; L2:` |
| `! a` | `Choice L1 ; <a> ; FailTwice ; L1: Any` |

**It cost 38% of the running time** — `programs/sola.sol` went from 3.79 seconds
to 5.25 — and two attempts to get that back are worth 3.7% between them.
Reordering the dispatch staircase by frequency bought 2.4%, and spelling out the
hottest comparison rather than calling it bought 1.3%. Both were predicted to be
worth much more. The loop's cost is the instruction fetch and the sends inside
an arm, not the comparisons that choose the arm, and **an interpreter written in
this language pays for its dispatch and cannot get it back by hand**.

**What is left of the limit moved somewhere better.** Compiling a grammar still
recurses over its tree, so a grammar nesting brackets a few hundred deep still
runs out of frames — a property of the *grammar file*, reported identically
every run and before any subject is read, rather than a property of the input
discovered on the one file that happened to be deep.

**The verification was the old matcher.** Both were run over every `.pas` and
`.sol` file here and every error case, and the output compared byte for byte:
63 runs, and the only two that differed were the two that used to exceed the
depth limit. One of them is `check_syntax.sol` itself — the staircase
dispatching the machine's instructions is deep enough that the matcher this
replaced could not read the program that replaced it.

## pascal — a compiler for a language with a standard

Reads ISO 7185 Standard Pascal and writes a `.sob`. The second compiler here,
and the first with a **real one to disagree with**: `fpc -Miso`, run beside it
by [oracle.sh](../programs/pas/oracle.sh).

```sh
./bin/solvm programs/pascal.sob                        # the demonstration
./bin/solvm programs/pascal.sob prog.pas [out.sob]     # a file
./programs/pas/oracle.sh                               # against a real Pascal
```

```text
    22    12    85
     3     2
    -3     3
```

**All eight stages**, and [PASCAL.md](PASCAL.md) says what is deliberately not
here and why.
The `program` heading, `var`, `const`, `type`, assignment, expressions, `write`
and `writeln` with field widths, `begin`/`end`, `if`, `while`, `repeat`, `for`
in both directions, `case`, `goto` with labels, enumerations, subranges, and
`ord`, `chr`, `succ`, `pred`, `odd`, `abs` and `sqr`; and `procedure`,
`function`, value and `var` parameters, recursion, `forward`, nested procedures
with uplevel access, arrays, records, `with`, sets, reading standard input,
pointers, and the standard's required functions. **Twenty-one programs produce
the same bytes as `fpc -Miso`, and three more must not** — each of those
exercises a divergence the document records, so the divergence list is
something that can fail.

**A type has two kinds, and that is most of stage 2.** `run` is what the machine
is holding — an integer, a float, a one-character string, a boolean — and `kind`
is what Pascal thinks it is. An enumeration is an integer at run time and a
`Colour` at compile time; a subrange of `char` is a character at run time and a
`1 .. 20` at compile time. Every check is on `kind` and every instruction
emitted is chosen by `run`.

**Where SOLABASIC.md is a language definition, [PASCAL.md](PASCAL.md) is a
conformance statement**, and that is the whole difference. `sola.sol` had to
draw its own boundary because no standard for a QBasic exists. Pascal has one,
so what the page draws instead is the mapping onto SolVM's value model, the
divergences, and the stages.

**A type checker is not optional here.** Solum refuses `#1:add(1.0)` — there is
no implicit conversion anywhere in the machine — so a compiler for a language
that *has* one cannot avoid knowing the type of every expression it emits. `i /
2` needs an `asFloat` on `i` and `i div 2` needs none, and that has to be
settled before a byte is written. `sola.sol`'s header says *everything a
SolaBasic program computes is a Double*: one numeric type needs no analysis, and
two need all of it.

### What it found

**And the verifier says *internally inconsistent* and not which slot.** Two
mistakes produced that and nothing else: a jump offset measured from the wrong
place — `OP_JUMP_IF_FALSE` is five bytes where `OP_JUMP` is three, because it
carries the selector it was inlined from — and a scratch slot handed out one
past the end of the frame. Both were found by bisecting a working program down
to the construct that broke, which is the only tool that message leaves you.

**`mod` is free and `div` is not, which is the reverse of SolaBasic.** ISO says
`i mod j` is non-negative for positive `j` — a *floored* remainder, and SolVM's
is floored, so `mod` is one instruction. ISO's `div` truncates toward nought
where SolVM floors, so it compiles through `abs` and a sign. SolaBasic wanted
exactly the opposite of both, and got them from the same machine.

**Booleans are jumps, not sends.** The machine's `and` and `or` take *blocks*,
being short-circuit; Pascal's are ordinary operators. `OP_JUMP_IF_FALSE` and a
boolean constant do it in four instructions with no block allocated — and the
standard permits the short-circuit that falls out, because evaluation order for
these is the implementation's.

**A field width is a compile-time string.** `writeln(i:6)` emits the constant
`">6"` and one `asString`, so a write is a `GLOBAL system`, the value, one send
and a `SEND write`. No runtime formatter and no prelude — which is the other
thing `sola.sol` needed and this does not.

**The oracle earned its place twice on the first day.** A program in `differ/`
was called `MaxInt`, and a program's own name is an identifier in scope — so
`maxint` meant the program and `fpc` asked for a `.` where the `)` was. And a
claim written into this compiler's header before it was checked — that `fpc`
answers `-1` for `-3 mod 2` where ISO wants a non-negative result — **was
wrong**: Pascal's sign belongs to the whole term, so `-3 mod 2` is `-(3 mod 2)`,
and asked with a variable holding `-3` both answer `1`. A compiler for a
language whose grammar it has just read is exactly the place to misread
precedence.

**`repeat` needs both jumps, and written the way it reads it runs once.**
`OP_JUMP_IF_FALSE` only goes forward and `OP_LOOP` is unconditional, so looping
while a condition is *false* cannot be one instruction: the false case jumps
over an exit and into the loop back. The obvious spelling — jump over the loop
when false — inverts the loop, and a `repeat ... until i >= 3` runs its body
exactly once and looks almost right.

**A `var` parameter cost the compiler its single pass.** The box is
`sola.sol`'s answer and Pascal is the easier half of it — `var` is *declared*
where QBasic made that compiler infer it. What is not easier is knowing which of
the *caller's* variables need boxing, because a variable read in one procedure
may be handed to a `var` parameter by another declared after it, and by then the
read is emitted. So the source is parsed twice and the first answer is thrown
away. Boxing every variable instead would cost an allocation and two sends on
every access in every program, to buy the case where one is passed by reference.

**A method's line runs have to cover every byte of it**, and forgetting to close
the last one is a file the verifier calls *internally inconsistent* — with the
disassembler showing every instruction at line 0, which is the only visible sign
of what is wrong. That is the third distinct mistake to produce that one
message.

**Stage 4 settled two predictions written before it was started**, and both
held. A nested procedure is a block made **inside its parent's activation** and
kept in a slot of that frame, so `OP_BLOCK` captures the right frame and
`OP_OUTER depth slot` reaches the right variables. **The machine needed nothing
added** — that instruction takes a depth and a slot, which is a static link by
another name. And
[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) turns out to be
Pascal's own scoping rule rather than a limitation on it: a nested procedure may
not be called after its parent returns, and a capturing block may not outlive
its home, and those are the same sentence.

The blocks it emits are **the first in this repository to set the capture
flag**. `sola.sol` has never emitted one, SolaBasic having no nested
procedures — and its header says so, which is how the prediction was made.

**An array and a record are the same thing at run time**, and the whole
difference is what the compiler knows. Both are a Solum array; a record's field
is an index worked out while compiling, and an array's subscript is the Pascal
index less its lower bound, folded the same way. Neither is a dictionary and
neither carries its shape. **Making one is a loop**, so the emitted code grows
with how deeply a type nests rather than with how big it is — a program may
declare a thousand of something and the compiler knows the number.

**And assigning a whole array or record copies it**, which the standard says and
the machine does not: a Solum array is a reference, so without the copy two
names would mean one thing. The copy is as deep as the type goes, because a
record of arrays is still one value in Pascal.

**A set is an array of booleans, and the plan said bit-words.** That plan met
[3.12](ROADMAP.md#312-no-shift-can-produce-a-negative-integer): `1 shiftLeft 63`
overflows, because SolVM's integers are signed and there is no unsigned type to
borrow, so a 64-bit word would have to be a 63-bit word or have its top bit
special-cased everywhere. A boolean each makes **membership one index** — the
operation a program writes most — and costs a `set of char` 256 booleans rather
than four integers. Everything else is a loop over the span either way, so the
bits would have bought only memory.

**Reading is on standard input only, and that is a decision rather than a
gap.** ISO leaves the binding between a name in a program heading and a file on
disk to the implementation, so a program that opens an external file has *no
answer the oracle could compare against* — and a divergence nobody can check is
a divergence nobody should write. `file of T` is out for the same reason: its
representation on disk is the implementation's too.

**And two of the three bugs in it were the same bug.** `JUMP_IF_FALSE` is the
only conditional jump the machine has, so *leave when this is true* has to be
spelled *leave when its negation is false* — and `readln` written without the
`not` stops at the first character that is **not** a line marker, which is the
one it is standing on. The other was `c:indexOf(" \t\n\r")` where
`" \t\n\r":indexOf(c)` was meant, so nothing was ever whitespace and the first
token was the whole file.

**Pointers made the `var` parameter grow up, and that is the finding of stage
7.** A reference began as a one-element cell — `sola.sol`'s answer, and enough
for BASIC, where the only thing that can be passed by reference is a whole
variable. Pascal's `Insert(t^.left, k)` is the idiom a tree is built with, and
the storage it names is *element two of the record `t` points at*. **No cell can
alias that.** So a reference is a container and an index, which names either
exactly — and a whole variable carries its pair from the moment it is declared,
so passing one costs nothing at the call. The restriction stage 5 had written
down as *stage 8* turned out to be a representation that was one case too
narrow.

## Adding one

There is no template and there should not be. What the fifteen have in common is
only this:

1. **It does a job somebody would want done**, rather than exercising a feature.
   The job is what makes the language answer honestly.
2. **It runs with no arguments**, on input it carries, and takes real input when
   given it.
3. **Where the language was awkward, the comment says so** rather than working
   around it quietly. That comment is the whole point — it is the draft of a
   roadmap entry, and several became one.
4. **It is registered in `tests/test_compile.c`**, which verifies every shipped
   `.sol` and fails if one is added without being listed.

What it does *not* have to do is demonstrate a message. That is `examples/`'s
job, and a test holds it to it: every built-in message must be sent by something
in `examples/`, so a program is free to reach for whatever it needs without that
counting as coverage.
