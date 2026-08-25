# The programs

*The eleven<!--count programs--> files in [programs/](../programs/): what each one does, how to run
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
from one of these ten wanting something the language did not have.

**What this page is not is a description of what Solum is for.** These ten lean
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

## expect — the examples and the documents, checked against what they claim

Runs every file in `examples/` and checks the inline comments that say what each
line prints.

```sh
./bin/solvm programs/expect.sob                      # all of examples/
./bin/solvm programs/expect.sob examples/numbers.sol # one file
./bin/solvm programs/expect.sob programs             # another directory
```

Over `examples/` alone that is 25<!--count examples-files--> files and
475<!--count examples-claims--> claims:

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
run the binaries as a shell would — **830<!--count claims--> claims on every build**, in about
sixteen seconds, and it fails the build if one stops holding.

**And it checks the documentation too.** The guide and the reference carry the
same notation inside ``` fences, and nothing checked those either — they are the
two documents a newcomer actually reads. 353<!--count docs-claims--> claims
across eighteen<!--count docs-documents--> documents,
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
three times, where it has **36<!--count integer-slots-->**: messages were added
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
[expect.sol](../programs/expect.sol) checks 830<!--count claims--> claims
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

`CHANGELOG.md` is the one document skipped — it records what was true at each
release, so its snippets describe past states on purpose.

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
listing that failed leaves a **non-zero status**, so it composes with a shell.

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

The first of the eleven to be an interpreter for another language rather than a
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

It also found [3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done),
which is still open: `INPUT` has to show a `?` and read the answer beside it,
and there is no way to write to standard output without ending the line.

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

## Adding one

There is no template and there should not be. What the eleven have in common is
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
