# Journal

*What a day of work on Solveig actually consisted of, newest first.*

The [changelog](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. Neither holds the shape of a
*day* — what was picked up and why, what turned out to be wrong, and the hours
that produced no code because they were spent deciding something or checking
that a document was still true. That is what this is for.

---

## 2026-08-25 (night) — the cursor, and two defects it walked into

ROADMAP 5.5 went on the list this morning and came off tonight. The library is
the least interesting thing that happened.

### The plan was the good part

The entry said: write it, convert `json.sol` **only**, and let that say whether
the interface is right before anything else moves. That is a rule against
guessing, and it caught me guessing twice.

The entry's own list was `peek`, `match`, `skipWhile`, `takeWhile`,
`takeUntil`. Converting one file added two more that no amount of staring at
the survey would have produced:

- **`since(start)`**, because `takeWhile` describes a run of *one* kind of
  character and JSON's number is four kinds in a row — sign, digits, fraction,
  exponent — and what the caller wants at the end is the whole span.
- **`take(#n)`**, because `\uXXXX` is exactly four characters and no predicate
  says *four*.

A third came from `html.sol`: **`pos` is written as well as read**, because
scanners backtrack. `&notanentity;` is read all the way to the `;` before being
rejected, and the cursor goes back. That is why there is no `mark` message —
there is nothing for it to do that assigning `pos` does not.

### The number, which is not the one I would have guessed

| | |
| --- | --- |
| five files, code lines recovered | 46 |
| `lib/scan.sol`, code lines spent | 48 |

**It pays for itself and nothing more.** I would have guessed a clear win before
starting, and the entry would have been written to promise one. What it actually
bought is one implementation instead of five — which is the thing the entry
*did* claim, and is worth having on its own, and is not a line count.

`expect.sol` recovered **nothing**, and that corrects the survey rather than the
file. It was counted as four scanning sites; one is cursor-shaped. `wordBefore`
runs backwards, `markersIn` searches for a substring, `asCount` filters every
character rather than stopping at one. Counting scanning by eye had counted
three things that a forward, stopping, character-at-a-time cursor cannot do.

### Two defects, neither in the code being changed

**`json.sol` could not read a newline.** Before converting it I recorded 38
inputs and their output, so the conversion could be *proved* to change nothing.
Two of the 38 were already wrong: `json:escapes` was referenced twice and bound
nowhere, deleted on 2026-08-21 by the commit that wrote the HTML reader, with
the two lines that read it left behind. Four days, four releases, and every
escape but `\uXXXX` raised.

Why nothing caught it is the better half. The library test exercises exactly one
escape — `é` — chosen when the question was whether a code point above
ASCII survived, which is the branch that was never broken. And the documentation
checker's subjects are `examples`, `docs`, `README.md` and `index.md`: **it does
not look at `lib/` at all.** The one thing here that reads code and checks what
it claims has never seen the library.

**And `experiment/prove.sh` built one generation with a different search path
from the others.** `bin/solas experiment/compile.sol` had no `-I lib`, because
the experiment's files only ever included each other; every other invocation in
the script had it. The moment `lexer.sol` included `scan.sol`, the fixpoint
failed — on *file names*, because a `.sob` records the file each line came from
and `lib/scan.sol` reached two ways is two different strings. Both compilers
agreed about every instruction. The asymmetry had been in that script since it
was written and nothing could see it until something crossed it.

---

### Postmortem

1. **The rule in the entry did the work, not the design.** *Convert one file and
   listen* is a rule against guessing, and it produced two messages I had not
   thought of and would not have. The version of this I would have written in
   one go would have shipped an interface that could not express JSON's number.

2. **I would have promised a line-count win.** The 46-against-48 result is the
   sort of number that gets quietly left out of a summary. It is in the entry,
   in the changelog and above, because a library that breaks even is a fact
   about libraries and worth knowing next time one is proposed.

3. **Both defects were found by preparation rather than by looking.** The
   baseline was written to protect a refactor and found a four-day-old bug
   before the refactor started. The proof broke because a conversion crossed an
   asymmetry that had been sitting in a script for weeks. Neither was on
   anybody's list, and neither would have been.

4. **`lib/` is unchecked, and that is now the largest hole here.** Everything
   else this repository has learned to check, it checks. The library is read by
   `test_include.c` for a handful of behaviours and by nothing that reads its
   documentation. `json:escapes` is what that gap produces.

---

### Afterwards: closing the hole, and finding item 4 was wrong

Two more commits after 0.30.0, and the first thing they established is that the
postmortem above is mistaken.

**Item 4 said the largest hole was that the checker never looks at `lib/`.** It
does not, and it barely matters. Across all seven library files there are
**nine** lines that print with a comment, because a library is an implementation
and not a demonstration. Pointing the checker at `lib/` would have gained nine
claims and would not have caught the escapes defect, which lived in a branch no
example exercised. The hole was never *where the checker looks*; it was that
three libraries had nothing to look **at**.

That is a better mistake than it looks, because it is the same one twice in a
day: reaching for the mechanism I had just been thinking about rather than the
question in front of me. In the afternoon it was `grep -c` against a build that
was not running. Here it was *the checker* — the tool I had spent three days
extending — offered as the answer to a problem it does not fit.

So: `examples/scanning.sol` and `examples/commands.sol`, 44 claims, run every
build. `lib/scan.sol` had shipped two hours earlier verified by a harness I
wrote once in a scratch file and deleted; `lib/shell.sol` had never had a test
of any kind.

**And writing them fell into 6.22.** An example of `scan.sol` called `scan.sol`
includes itself. The warning fired, named the shadowed file exactly, and the
file compiled — into a program that fails at run time with `undefined name
'scan'`. It went to a terminal where I had redirected stderr to `/dev/null`.

Which is the fourth time in one day that something passed or failed quietly
because I had silenced what was telling me. That is not a thing to resolve to do
better about; it is a thing to make impossible. **45 shipped files now have to
compile without `solas` saying anything**, where before they only had to
compile. Every one of them passes today, so the check locks in what is already
true — and it was verified by planting a warning and watching it fail, on a
freshly built binary.

The plant taught something on its own: putting `examples/scan.sol` back shadowed
`lib/scan.sol` for `examples/scanning.sol` too, so the reported failure came
from the *neighbouring* file. 6.22's hazard reaches one file further than the
file that has it.

---

## 2026-08-25 (evening) — two names the language did not need

Housekeeping, asked for as housekeeping, and both items turned out to be about
the same thing: a name that had never been looked at since the day it was
typed.

### One idea had two names

`array:at_put` was raised as a style point — everything else is camel case.
Checking it found something sharper than style. Of **125 distinct messages it
was the only one with an underscore**, and it was not merely inconsistent with
the others: `dictionary` had answered `atPut` all along, so the *same idea* had
two spellings depending on which type you sent it to. The C comment beside the
dictionary primitive said so out loud — *the value stored, as `at_put` on an
array does*. The code knew they were one operation and named them differently
anyway.

No alias, because an alias is the second mechanism behind the first that this
language exists to refuse, and because keeping both would have left the
inconsistency in the message index permanently rather than removing it.

The count moved the right way: **124** distinct messages across the same **220**
registrations. Nothing became askable that was not askable before; there is one
fewer way to spell one of the questions.

### The counted loop, and an objection that should not have been accepted

`#1:toDo(#5, block)` and `#1:toByDo(#10, #3, block)`. Three fair complaints:
`toDo` reads as *todo*, `toByDo` wedges `By` into a name that was already a
sentence fragment, and the start value hid in the receiver while the other two
numbers sat in arguments.

The proposal was `[#1,#10,#3]:loop(block)`. I raised one objection to the array
form — that `array` already answers `do`, so `[#1,#10]:do` and the new message
would mean different things on the same receiver — and offered a choice between
accepting that cost and keeping an integer receiver instead. The name I put in
the option was `loopDo`.

**That was the wrong pair of options, and the reply said why.** Nothing else
here announces its block in its name: `repeat`, `collect`, `select`, `inject`
and `whileTrue` all take one without saying so. And `loop` is far enough from
`do` that the confusion I had described as a cost to be accepted simply does not
arise. The objection was real; I offered to trade it away when a better name
removed it for nothing.

```text
[#1,#5]:loop({ n | n:display }).               ; 1 2 3 4 5
[#1,#10,#3]:loop({ n | n:display }).           ; 1 4 7 10
[#10,#7,#0:sub(#1)]:loop({ n | n:display }).   ; 10 9 8 7
```

`loopDo` existed for twenty minutes and no release carried it. What survives of
the trade is the half that is real: arity moved from send time to run time,
because an array of the wrong size can only be caught by looking at it.

### What the checker did while this went on

Removing two messages from `integer` took its slot count from 38 to 36, and
[class-and-instance.md](class-and-instance.md) asserts that number in a *live*
example — `integer:slots:size:print. ; #38`. It failed within a second of the
new primitive being registered, along with two prose markers stating the same
number elsewhere. Nobody had to remember that the document existed.

The message count is stated in four places now, and only one of them is checked.
The other three — the README, the site description, and the repository's
description on GitHub — went **125 → 124 → 123** in one evening, by hand, from
grep, twice.

---

### Postmortem

1. **The same mistake three times in one day, and I only fixed the process on
   the third.** Renaming `at_put` I wrote the file list by hand and missed
   `tests/test_random.c`, which had live Solum in it. Renaming `toDo` I wrote
   the list by hand again and missed three test files and every multi-line call.
   Renaming `loopDo` I finally derived the list with `grep -rl` and missed
   nothing. The follow-up sweep caught the first two, so nothing shipped
   broken — but the sweep was doing the work the list should have done, and it
   is only a safety net because I kept needing one.

2. **I offered a trade instead of looking for a better option.** The
   array-versus-`do` ambiguity was correctly identified and then treated as
   fixed cost, presented as *accept this or take the conservative design*. A
   third option existed and was one word long.

3. **I over-corrected a count from a stale reading.** When the claim total fell
   to 761 I edited four markers to match, then found that the total was only
   761 *because* a claim was failing; fixing the failing claim put it back to
   762 and I had to undo all four. Reading a count taken while something was
   broken, and believing it — a smaller version of the morning's `grep -c` on a
   build that was not running.

---

## 2026-08-25 (afternoon) — installing it, and two verifications that verified nothing

`make install`, `make uninstall`, `make dist`. The interesting part is not any
of them: it is that **two of my checks passed while measuring the wrong thing**,
in a session whose last three postmortems have all been about preferring
measurement to reasoning. Measuring the wrong thing is the failure mode
underneath that one, and it is quieter.

### The defect was known before the work started

It had been measured hours earlier, while answering a different question: an
installed binary, run by bare name off `PATH`, cannot find its library.
`argv[0]` names a directory only when the program was invoked with a path, and
[compiler.c](../solas/src/compiler.c) deliberately refuses to search `PATH`
again to guess. Which is right, and left an installed `solas` with nothing.

The answer is that a path the *install* wrote down is not a guess. Four tiers
now, with the install last so a checkout keeps winning — otherwise testing a
change silently reads the library installed on the machine.

### The rule that became the default goal

The generated header carrying `SOL_LIB_DIR` needs a rule. I wrote it in the
variables section at the top of the Makefile, which is where its comment
belonged, and **make's default goal is whichever target it reads first**.

So bare `make` generated a header, built nothing, and exited **0**.

And the check I ran was `make >/dev/null 2>&1 && echo "build ok"`. It printed
*build ok*. The binaries it then ran were left over from before the change. A
green check, a silent no-op, and a conclusion drawn from neither.

### The counts that counted nothing

The property worth having is that changing `PREFIX` rebuilds what depends on
it, because a binary carrying a stale prefix fails silently. I checked it three
times with `make PREFIX=… | grep -c "compiler.c"` and got **0** every time, and
started reading GNU Make's documentation on generated prerequisites, and the
`.d` files, and `-MP`'s phony header targets.

It was rebuilding the whole time. The zeros came from the broken default goal
above: make was building nothing at all, so of course nothing mentioned
`compiler.c`. Two faults, and the first one made the second one unreadable.

What settled it was `stat -f %m` on the two files, which is a smaller and
duller measurement than the one I had been running, and unlike it, it could not
be satisfied by the wrong thing:

```text
1787663669 build/config.h        1787663669 build/solas/src/compiler.o
--- switch prefix ---
1787663686 build/config.h        1787663686 build/solas/src/compiler.o
```

Then, properly: a `PREFIX` change recompiles all fourteen sources and relinks;
the same `PREFIX` again produces zero lines.

### And the machine turned out to be running make from 2006

`make --version` on this Mac says **GNU Make 3.81**. The Linux runners have 4.x.
That did not cause anything here, but it is worth knowing that the two makes in
play differ by nineteen years, and that the older of them is the one the author
sits in front of.

---

### Postmortem

1. **A check that cannot fail is not a check.** `make && echo ok` passes when
   make does nothing, and `grep -c` on an empty build passes as a zero that
   means what a real zero would mean. Both were written to confirm rather than
   to discriminate.

2. **When a measurement disagrees with a strong expectation, suspect the
   measurement before the theory.** I spent longer than I want to admit
   reasoning about `-MP` phony targets, on evidence produced by a build that
   was not running.

3. **The fix for both was a smaller measurement, not a cleverer one.** File
   mtimes, and the line count of make's output. Nothing about the second attempt
   was more sophisticated than the first; it was just harder to satisfy
   accidentally.

**What is now checked rather than claimed**: that an installed binary finds its
library, and that the tarball builds. Both are in CI, because both are exactly
the kind of thing that is true on the day it is written and quietly false a
month later, and this repository has a list of those.

---

## 2026-08-25 — the sanitizers, and a hang that erased its own evidence

A short day with one lesson in it, and the lesson is about *logs* rather than
about sanitizers.

### The job itself was the easy half

ASan and UBSan over the whole suite, on every push. The design question was
where the flags go, and it was settled by measurement rather than by taste:

```text
make -Bn build/tests/test_threads
  ... -pthread ...

make -Bn build/tests/test_threads CFLAGS="-std=c11 -g"
  ... (no -pthread)
```

`CFLAGS` is `?=` and `test_threads` appends `-pthread` to it, and a
command-line `CFLAGS` stops that append from applying. So the obvious spelling
— `make test CFLAGS="… -fsanitize=…"` — would have linked the one test that
needs threads without them, dropped `-Wall -Wextra -Wpedantic` on the way, and
said nothing about either. A separate `SANITIZE` variable leaves both alone.

Run locally first: clean under clang on macOS, zero reports. Then on Linux with
leak detection, which macOS/arm64 cannot do: **also clean**, in 1m26s. That is
the first time the *whole* suite has been under both sanitizers at once rather
than a pass aimed at whatever had just changed — and the first check of any
kind behind `design.md`'s claim that the language does not leak.

### The half that mattered

The first push to `main` went red, and not from the sanitizers. **The macOS job
hung in `make test` for 25 minutes and was cancelled by its job timeout.** A
re-run passed in 39 seconds.

Then the part worth writing down: **a cancelled job keeps no log.** The
evidence was gone. Twenty-five minutes of a hang, and nothing on the record
saying which test was running when it stopped. I spent the next stretch reading
the suite for candidates — which is exactly the reasoning-instead-of-measuring
that the last three days of postmortems have been about, and here there was no
alternative, because the measurement had been destroyed by the thing that took
it.

So the first fix is not to the hang. It is to the *next* hang: the Test step
carries its own timeout now. A step that times out **fails**, and its log
survives; a job that times out is **cancelled**, and its log does not. `make
test` already names each binary before running it, so the last line will say
which one.

The second fix is the only unbounded wait the suite had — `session_end` in
`test_line.c`, which drives `solis` through a pty. Everything in it is careful:
20ms `select`s, a drain loop that gives up after two seconds. Then it ended on
`waitpid(pid, &status, 0)`, with no `WNOHANG` and no deadline.

**Whether that is what hung is not established, and the commit says so.** It is
the only wait that *could* hang, which is reason enough to bound it. It is not a
diagnosis, and calling it one would be the same move as an entry claiming a
trigger fired when nobody checked.

---

### Postmortem

1. **I let a job cancel itself and lose the only copy of what happened.** The
   20-minute job timeout was written yesterday as a hang backstop, and it works
   as a backstop and destroys evidence doing it. Bounding the *step* instead
   was available the whole time and I did not think of it until the evidence
   was already gone.

2. **A flake was one green re-run away from being invisible.** The re-run
   passed in 39 seconds and turned the whole run green, including the badge. If
   the habit had been to re-run and move on, `main` would look like nothing
   happened, and a 20-minute intermittent hang would still be there.

3. **The fix is honest about not being a diagnosis.** Both the commit and the
   changelog say the hang's cause is unestablished. The temptation to write
   *fixed the hang* was real and would have been the more satisfying sentence.

**What the day is worth beyond the job**: the suite has now been run under both
sanitizers, on two operating systems, under three compilers, with leak
detection, and reports nothing. That was three separate hand-run habits and a
claim in a status line; it is one workflow now.

---

## 2026-08-24 (evening) — the first build on a machine nobody here owns

One workflow, four commits, and the useful part is that **the run found a bug
that has nothing to do with portability and everything to do with nobody having
compiled this with a second compiler**.

### Two predictions, written down before the run

The session had spent the afternoon learning that reasoning loses to
measurement, so the predictions went into the commit message and the pull
request *before* the first run, where they could be scored rather than
remembered charitably:

1. **No `-lm`.** libm is part of libSystem on macOS and a separate library
   everywhere else.
2. **POSIX declarations hidden by `-std=c11`.** Named five files that use POSIX
   functions with no feature-test macro.

Both happened. The first was exactly right, and larger than the grep behind it:
eight math functions failed to link, including `llround` and `log10`, which the
grep had missed. The second was **right about the cause and wrong about the
files** — `strptime` failed inside `builtins.c`, which already declares
`_POSIX_C_SOURCE 200809L` and needed `_XOPEN_SOURCE`. Reasoning from a grep got
the class right and the instances wrong, which is roughly the accuracy the
afternoon would have predicted.

### The one that was not predicted

```text
#define READ_SHORT() (frame->ip += 2, sol_read_u16(frame->ip - 2))

case OP_JUMP:  frame->ip += READ_SHORT();
case OP_LOOP:  frame->ip -= READ_SHORT();
```

GCC: *operation on `frame->ip` may be undefined*. It is. `READ_SHORT()` moves
the ip itself, so the outer `+=` reads and writes an object the right operand
also writes, with no sequence point between them, and C11 does not say which
value the addition started from. **A compiler that loaded the left operand first
would make every forward jump two bytes short** — which is not a subtle
misbehaviour, it is a VM that runs the wrong instruction.

Three cases further down, `OP_EXIT_IF_FALSE` already read the offset into a name
before using it, which is the correct spelling. So the shape was known and two
sites did not have it. Every test has passed on this hardware for the project's
whole life, and nothing in the suite could have found it, because the suite runs
the compiler that happens to choose the order we wanted.

### What the green run is worth

All 762 documentation claims hold under gcc on Linux. Every fenced block in
every document produces the same output on a machine with a different libc, a
different compiler and a different instruction set. That is a stronger statement
about the documents than anything measured here so far, and it came free with a
workflow written for a different reason.

It also settles a claim that had been on the front page since long before today,
and that I had *rewritten into the repository's description this morning* while
it was still unchecked — and, as it turned out, false.

---

### Postmortem

1. **The prediction was right in class and wrong in detail, and the detail was
   the part that mattered for fixing it.** Had the fix been written from the
   prediction alone — feature-test macros added to five named files — it would
   have missed `builtins.c` and fixed three files that did not need it. The run
   named the lines.

2. **My warning count was taken from the wrong command.** After the portability
   fixes I checked `make` for new warnings, saw zero, and pushed. `tests/`
   is built by `make test`, and `test_line.c` had a redefinition warning waiting
   in it. The runner builds everything, so it saw what a habit did not; the
   count now comes from `make && make test`.

3. **A local check cannot find a portability bug, and I knew that going in.**
   No container runtime here, so there was no way to test glibc before pushing.
   The right move was to push and read the answer, which took four runs and
   about fifteen minutes — considerably less than the reasoning it replaced.

**Where this leaves the sanitizers.** ASan and UBSan appear throughout the
changelog as hand-run passes attached to particular commits: 3,205 corruptions
here, `SOLUM_GC_STRESS=1` there. There is no target and nothing that runs them
unprompted, which is precisely the standing the portability claim had this
morning. A compiler warning found one instance of undefined behaviour today. The
class is what UBSan is for.

---

## 2026-08-24 (afternoon) — a feature argued three ways, and the defect the argument found

No language change and no roadmap entry closed. The afternoon was one question
— *should Solum have regular expressions?* — and the useful part is that **three
of the arguments against were wrong, and each one was overturned by a
measurement rather than by a better argument**.

### The argument that was not available

The obvious answer is *no program here has wanted one*. That reading of an
absence was ruled out two days earlier, in the paragraph
[design.md](design.md#what-the-language-is-for) gained when trigonometry was
very nearly argued away by it: **"no program here has wanted X" is a statement
about what has been built, and never a statement about what the language is
for.** So the question had to be settled on shape.

It is also false, which the survey found in twenty minutes.

### What the survey actually found

Every `.sol` file in the repository, read for scanning rather than for patterns:
**about 460 lines of genuine character-class, repetition and alternation work**,
most of it in `lib/html.sol`, `experiment/lexer.sol`, `programs/expect.sol` and
`lib/json.sol` — which carries the canonical JSON number expression written out
by hand.

But what repeats across those files is **not** a pattern.

| idiom | sites | what it is |
| --- | --- | --- |
| `{ pred(peek) }:whileTrue({ step })`, then `copyFrom(start, pos:dec)` | at least 15 | `X+` with a capture |
| `"<set>":indexOf(c):notNil` | at least 12 | a character class |
| `split(x):join(y)` | 2 | replace, which the language does not have |

The first is `takeWhile`; the second is a predicate. Both are methods on
something holding a position, and **five files hand-roll that position
separately**. So the demand is real and it is not demand for a pattern language:
it is demand for a cursor, which is `lib/scan.sol`, writable today, no change to
the VM.

### The shape was decided before anyone chose one

[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) settles how such
a library may be written, and it does not leave two options. A matcher built the
combinator way — a block that returns a block — dies:

```text
makeDigit := { | lo, hi |
    lo := "0". hi := "9".
    { c | c:greaterOrEqual(lo):and({ c:lessOrEqual(hi) }) } }.

makeDigit:value:value("7"):print.
solvm: block outlived the frame it was written in
```

The same matcher built from objects composes today, and a `runOf` over a
`range` answers `#4` for `"8080ab"` on the first try. A cursor holds a position,
position is state, and **the spelling the language allows is the one a cursor
wanted anyway**. That is a limitation doing design work rather than obstructing
it.

### Three things argued wrongly, and how each was overturned

1. **Termination.** I said an engine would be exponential and would punch a hole
   in [3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work). Measured against
   the system `regexec`, the five classic ReDoS patterns — `^(a+)+b$`,
   `^(a|a)*b$`, `^(a|aa)+b$`, `^(a*)*b$`, `^(a?){20}a{20}$` — are **flat through
   n=40**, and matching is linear in input: 77ms at 1MB, 163ms at 4MB, 642ms at
   16MB, 2,562ms at 64MB. Catastrophic backtracking needs leftmost-first
   semantics and backreferences, and POSIX ERE has neither. **The objection was
   about Perl, not about regex.** 3.7's own table has `indexOf` over 64MB at
   0.27s: the same complexity class, ten times the constant — the existing hole
   one primitive wider, not a new one.

2. **A second language in a string.** A fair argument against a *literal*, which
   I then let slide into an argument against a *library* without noticing the
   step. `lib/shell.sol` already carries an entire foreign grammar in a string,
   deliberately, with the bargain written into its own header. The argument does
   not survive its own precedent and was withdrawn.

3. **Small demand.** Implied before the survey, contradicted by it, and it was
   never an argument that was available in the first place — see above.

While measuring, one more thing came out that is worth keeping: **`--steps` does
not bound work inside a primitive.** A program of `system:run(["sleep","2"])`
run under `--steps=6` stopped at 2.021s of wall clock with exit 124 — the limit
fired *after* the two seconds, because the two seconds happened inside one
dispatch. That is exactly what 3.7 says, demonstrated rather than restated.

### If the objection is size, is that not what extensions are for?

The follow-up question, and the honest answer is **no, and yes.**

No, because regex *fails* the trigger in that idea:
[extensions](ideas.md#extensions-a-capability-from-a-binary-rather-than-from-the-vm)
are for capabilities that cannot be written in Solum, and a matcher can be. An
engine would be 800–1,500 lines of C, which would make it the third-largest file
in the repository, against `compiler.c` at 1,718 and the whole front end —
`lexer.c` and `parser.c` together — at 405.

Yes, because it is close to the ideal thing to build the *first* extension
**with**. `regcomp` allocates a `regex_t` that `regfree` must take back, which
makes a compiled pattern the smallest possible test of the one real design
decision in that entry: a foreign cell carrying its own release function, and
whether the hook fires for a program stopped by a limit. A checksum cannot test
that. A database can, and costs a dependency, I/O and a network first.

Both stages come after the build restructure, which is the real work and is
regex-independent: `libsol.a` is a static archive with no `-fPIC`, so as built,
a loaded bundle could not resolve `sol_*` back into `solvm` at all.

### The defect that fell out of a survey about something else

Reading `expect.sol` for scanning idioms found one that was not an idiom.
**Six sites asked `indexOf(suffix):notNil` a question about how a name ends**,
and got back whether the suffix appeared anywhere:

```text
hello.sol.bak    passes as a Solum file
notes.solid      passes as a Solum file
draft.md.orig    passes as a document
a.md.sol         a Solum file, handed to the markdown checker
```

The checker for this repository, quietly checking the wrong things — which is
the fault it exists to catch. Nothing in the tree is named that way today, which
is exactly why it survived nine programs' worth of runs.

It was **left unfixed on purpose** for one commit, rather than folded into a
documentation commit that was about something else, and fixed in the next one
with a four-line `string:endsWith` in the program that needed it. Not by adding
`endsWith` to the language: whether it belongs on `string` for everyone is the
same question `lib/scan.sol` asks, and one program wanting it once is not an
answer. The counts moved from 759 claims to 762, and all three of the new ones
are the ideas entry's own worked example — **the fix itself changed no result**,
which is the point.

---

### Postmortem

**One shape, four times.** Every mistake below is a claim made from reasoning
that a short measurement refuted, which is the same shape as the previous two
days' postmortems.

1. **The termination argument was the strongest thing I said and it was wrong.**
   It was also the easiest to check: five patterns, one C file, ten minutes.
   Ten minutes of measuring would have replaced an hour of arguing from
   half-remembered received wisdom about a different regex flavour.

2. **An argument slid one category sideways without being re-examined.** *A
   second language in a string* is sound against a literal and unsound against a
   library, and I used it in both places. The tell was available the whole time
   — `lib/shell.sol` is in this repository and does the thing being called
   impermissible.

3. **I nearly used an argument that had been explicitly retired two days
   earlier**, in a paragraph written after it nearly cost the language
   trigonometry. Writing a rule down does not make it reach the next argument.

4. **My anchor checker reported nine broken links, and every one was a false
   positive** — my own slugifier mishandling em-dashes in headings. Verified the
   seven new anchors by hand instead. A checker that cries wolf about existing
   text is worse than no checker, and it is not one of the ones that ships.

**What went right, and it was not an argument.** Three of the day's conclusions
came from running something: the combinator matcher's failure, the flat ReDoS
table, and the `sleep 2` under `--steps=6`. The two conclusions that came from
reasoning alone were both overturned. That ratio is the argument for the
repository's whole habit of making documents run.

---

## 2026-08-24 — a spelling the language would not take, and a trigger that had already fired

Two entries closed. The useful part of the first is the twenty minutes between
recommending a shape and finding out the language could not write it; of the
second, that the thing blocking it had stopped being true four releases ago and
nobody had looked.

### What was left, asked and answered

The morning began by asking what was still outstanding, which took reading the
roadmap against the code rather than against its own summary. The answer was
smaller than it looks: one release uncut, **one** buildable limitation with a
program behind it (3.15), one that needs a decision before it can be built
(3.14), six that are consequences documented where a program would meet them,
and eight ideas waiting on triggers that have not fired. The roadmap no longer
says what to build next, and that is deliberate — the way to add to it is to
write a program and find out what it wants.

### The shape was the whole of 3.15

The entry had done the hard half already. It named the limitation, named two
possible answers, and **picked neither**: a fourth argument to `capture`, which
is the smallest thing that works and the least general, or an options bag, which
generalises without new messages at the cost of a shape nothing else here uses.

The bag won on an argument the entry did not contain. There are four things a
caller might want to say, not one, and the fourth is the one nobody had written
down: **there was no way to give a child anything to read, either.** `stdin` was
inherited by both messages and unmentioned in the entry, the reference and the
cheatsheet alike. Four optional things is more than positional arguments can
carry, so the bag was not a preference by then.

### And then the language said no

**I recommended a dictionary. The language has no dictionary literal.**

`dictionary:new`, then `atPut` — and `atPut` answers the value stored rather
than the dictionary, so it does not even chain. Saying one thing costs three
statements at the call site:

```text
opts := dictionary:new.
opts:atPut("stderr", 'discard).
system:capture(argv, opts).
```

That is not a bag anybody would use. What replaced it was already written down:
an **array of alternating name and value**, which is the notation 3.15 itself
sketched, a day before either question was asked. The names are the strings
`capture` already answers with, so a stream is spelled the same going in as
coming out, and a value is a **manner as a symbol** or a **path as a string** —
the type telling them apart, which is what keeps a file called `discard` a file.

The recommendation survived; its spelling did not. I had argued the trade-off
between two shapes without checking whether the language could write the one I
preferred.

### Two decisions in the plumbing worth the words

- **The files are opened before the fork.** A path that cannot be opened is then
  the caller's error to read, rather than a child that silently did nothing.
  They are opened close-on-exec, and the copy `dup2` makes is the only one the
  child carries — `dup2` not passing the flag on is the property that rests on.
- **`'merge` follows stdout to where it is now**, which is `>file 2>&1` and not
  `2>&1 >file`. Those are the two orders a shell distinguishes, the classic way
  to get this wrong, and it falls out for free by doing stdout first.

### The test had to watch its own stderr

`'discard` is the claim whose failure is invisible: output that should not
appear looks exactly like output that appeared somewhere else, and a test that
merely checks the captured string passes either way. So the test points the
**test process's** stderr at a file for the length of the call and reads it back
empty. Three hundred redirected children after it say nothing was left open,
which under a 256-descriptor limit fails loudly rather than quietly.

`bench.sol` is what asked for the entry and is what proves it closed. It had
been taking the noise on purpose — a shell to drop stderr is another fork and
another exec on every measurement, of the same order as the thing being measured
— and its report is clean now, with the failure count untouched, because what
says a command failed was always the status.

### 3.14 was not waiting for what it said it was waiting for

The randomness half of 3.14 had been open since the tenth program, blocked on
one question — **where does the state live** — with four candidates written down
and none picked. It is built now: `random:new` seeded by the machine,
`random:new(#seed)` seeded by you and repeatable, state in the object.

`system` was the candidate to rule out, and the entry had already written the
reason against it: a generator there gives a VM a history, and two runs of one
chunk stop being identical. [embedding.md](embedding.md) does not say so in
those words — what it promises is *one chunk, any number of machines*, and a
chunk holding a generator's state would not be that. In an object, a program
that never
says `random:new` is exactly as deterministic as it was before any of this
existed — and that is a test rather than a claim, run across two VMs.

### The generator was fine; the seeding was invisible

What actually settled the entry was measuring what was already here.
[bench.sol](../programs/bench.sol) had carried Lehmer's for four releases, and
in bulk it was blameless: 100,232 heads in 200,000 flips, and 21 buckets over
210,000 draws spread from 9,799 to 10,157.

Then the seeding, which the entry had described as *the only entropy a Solum
program can reach* without asking what it was worth:

| | before | after |
| --- | --- | --- |
| the first coin flip, over consecutive seeds | `1, 2, 1, 2, …` — **the parity of the start microsecond** | no pattern |
| the first resample index of 21, over 2,000 consecutive seeds | **3 distinct values** of 21 | **21** |

A Lehmer generator's first output moves by the multiplier when its seed moves by
one, and two runs a microsecond apart get consecutive seeds. **Neither half of
that was fixable in Solum**: mixing a seed properly needs the wrapping
multiplication that traps here, and a program cannot reach `/dev/urandom` while
the machine can. With the modulo bias on the way out that is three ways to get
this wrong that a reader cannot see, which is the `sqrt` argument holding more
clearly than it did for `sqrt`.

### The trigger had fired on the day it was written

The entry said it waited for *a program wanting randomness for the work rather
than for how it measures*, and filed `bench.sol` under the second. That is a
misreading of that program: its product is the confidence interval, and the
interval is computed by bootstrap resampling. The randomness is the algorithm,
not the instrumentation.

**A trigger can be written down wrongly and go on looking unfired**, which is a
more useful thing to know than the entry it was attached to. Nothing about the
world had to change for this to become buildable — only somebody re-reading the
condition against the program it was written about.

What [ideas.md](ideas.md) had predicted, years of commits ago, needed no
correction at all: *a random source wants to be a thing you make with a seed you
can name, not a message on `integer`*. That is what got built, word for word.

### A seed you can name makes the documentation checkable

[examples/random.sol](../examples/random.sol) is the twenty-sixth example and
**every number in it is a claim the build checks** — `#3`, `#-2`,
`0.09265158547740904` — because a named seed is a named sequence. A generator
that could only be seeded by the machine would have made that file a page of
prose about what it might print.

### A question about `and` that was not about `and`

The day ended with a question rather than a plan: `a:and(b)` without the braces
is an error when `a` is true and *fine* when `a` is false, so a mistyped line
can sit in a file until the data changes. Should there be a check? Should there
be two spellings, an eager `and` and a short-circuiting `andsc`?

**Measuring it first turned a two-message question into a fourteen-message
one.** The argument was being checked inside the code that *calls* a block, so a
block that was never called was never looked at — and every message that might
not run what it is given had the same hole: both short-circuit pairs, the branch
`ifElse` does not take, a `whileTrue` whose condition is false to begin with, a
`repeat` of zero, `do`/`collect`/`select`/`inject` over an empty collection, and
an `onError` whose block did not fail. `[]:collect(#45)` answered `[]` where
`[#1]:collect(#45)` failed, from one line of source.

That reframed both questions. **The check moves to where the message is
received**, which makes the complaint a function of the program text rather than
of the data, and costs nothing on the inlined path because a literal block
compiles to jumps and is never sent. And the second spelling answers nothing:
twelve of the fourteen have no `and` in them, and two selectors differing only
in whether side effects happen is a quieter bug than the one being removed.

**It caught a line here on the first run**, which is the part worth keeping.
[examples/blocks.sol](../examples/blocks.sol) demonstrates that an argument is
evaluated before the send by handing `ifTrue` a *group*:
`false:ifTrue(("the group ran anyway":display. nil))`. The group runs, prints,
and answers nil — and `ifTrue` took the nil, because a false receiver never
reaches its argument. **The demonstration was standing on the hole it was
standing next to**, in the file whose whole job is to show how blocks work.

### The question about `:=` that a reader will keep asking

The day's last piece is a document rather than a change. Everything in this
language is a message and every message can be overridden — `integer:add := { n
| #999 }` really replaces addition — and `:=` stands outside that. Is it syntax
because it reads better, or because it does something a method could not?

**Answering it by reading the compiler rather than reasoning about it split the
question four ways**, which is the part worth keeping. `a := b` is not one
operation: it compiles to `OP_SET_LOCAL`, `OP_SET_OUTER`, `OP_SET_GLOBAL` or
`OP_SET_SLOT` depending on what the name turns out to be, and only the last has
a receiver anything could be sent to. A local is a numbered slot in a fixed-size
frame, decided while compiling, with no name left at run time. A global is an
ordinary slot on an ordinary object — and **that object has no name in Solum**,
which took one line to check and settled the case:

```text
zzz := #42.
object:respondsTo('zzz):print.       ; false
```

`object` is the root *class*; the one holding globals is a different object and
unreachable. So the alternative spelling is not one the language declines to
offer — there is no receiver to offer it to.

**The fourth form is compiled as a message and then taken back.** `a:b := c` is
parsed as an ordinary send, `OP_SEND b` is emitted, and on seeing `:=` the
compiler rewinds its own write cursor over the instruction. That is as close to
sugar as anything here gets, and it is why `integer:double := { ... }` and
`p:x := #3` are the same sentence.

**And the case against making even that one a message is not about taste.** The
compiler can *see* bindings, and three things depend on it: the warning when two
files bind one name, resolving a name to a frame slot at compile time, and
knowing whether a block reaches out of its frame. A binding arriving as a send
would be invisible to all three. Overriding `add` affects programs that add;
overriding `bind` would affect every assignment ever written, reentrantly.

**It turned up one thing worth recording**, which is why the answer went into
the documents rather than only into the conversation. 2.10 says *reflection
cannot write*; it understates the case. The globals cannot be **read** by
computed name either, since the object holding them cannot be named — `slotAt`
and `perform` take a computed name and a global takes only a literal one. No
program here has wanted otherwise, so it is a note with a trigger rather than an
entry.

### And the same gap asked again, from the other side

The follow-up question was practical rather than theoretical: *`object:slots` is
perfect for seeing what an object answers — where do I print what is in the
global space, or the local one?* Which is the same gap, met by someone trying to
use the language rather than reasoning about it. `object:slots` lists the root
*class*'s fifteen messages and is a reasonable thing to mistake for the globals.

Laying out what actually exists made the answer obvious:

| | list them | read one by name |
| --- | --- | --- |
| locals, from a program | no | no |
| locals, in `solid` | **yes** | yes |
| globals, from a program | no | no |
| globals, in `solid` | **no** | yes |

One empty cell, and the cheap one — the debugger already resolves a global by
name off the root object, so listing is a walk of the same slot list. `globals`
is fifteen lines and no language change, and **a debugger answering what is in
scope needs no admission-rule argument at all**; that is what it is for.

Two things fell out of the slot list's shape rather than needing bookkeeping. A
new name goes on the *front*, so the count of slots taken the moment the
built-ins finish installing is a permanent boundary between what the machine
brought and what the program bound — and the same front-insertion means the list
has to be walked backwards to show bindings in the order they were written.

**The one mistake was in the test, not the code**: asserting that `tripled` did
not appear anywhere in the session, when the breakpoint's own echoed source line
was `#5:tripled:print.`. The listing was right; the assertion was asking a
sloppier question than the one it meant.

---

### Postmortem

**Three mistakes, and two of them were caught by yesterday's work.**

1. **The dictionary I recommended could not be written.** Covered above. The
   pattern is the familiar one from the day before: a claim from reasoning that
   a two-minute check refutes, in this case grepping the cheatsheet for a
   literal.

2. **An untagged fence in `COMPLETED.md` would have run `make`.** The entry's
   illustrative block opens `system:run(["make"], ["stderr", 'discard]).`, and
   an untagged fence is a program — which is exactly what
   [3.16](COMPLETED.md#316-what-the-checker-does-not-check--done) established
   the day before. Written by the same hand that wrote *a reader can see a fence
   that says `text`*, one day later. It is tagged now, and the block that
   demonstrates the dictionary above is tagged for the same reason.

3. **A test asserted the wrong thing about `'share`.** It said
   `capture(argv, ["stdout", 'share])` should change nothing, on the reasoning
   that naming the default is harmless. The implementation refuses the *name*
   `"stdout"` for `capture` whatever the value, because keeping stdout is what
   that message is for. The refusal is right and the test was wrong — but the
   test is what surfaced the question, which is the argument for writing the
   awkward cases down.

4. **Two numbers invented in documentation, both caught.** Writing the reference
   section I put plausible-looking outputs in a fenced block rather than running
   it — `#2` where the generator answers `#0` — and the checker named the file,
   the line and the claim. The same reflex, in a document without a checker,
   is how a reference goes quietly wrong.

5. **Two `make test` runs at once, into one build directory.** The sanitizer
   build and the plain build were compiling the same objects with different
   flags at the same time, which makes both results meaningless. Killed and
   re-run in sequence. The build directory is shared state and nothing enforces
   that.

**What the day's tooling was worth**: the documentation added four claims, which
moved two numbers stated in prose in three different documents, and every one of
them was named by `expect.sol` with the file and the line — a day after the
notation existed. Nothing about that check was manual, and none of those numbers
would have been noticed by reading.

---

## 2026-08-23 (evening) — a page read as a page, a number that says what it counts, and a walk that became a lookup

Three commits after the release, closing two entries — and the shape of the
evening was measuring what a guess had got backwards, twice.

### 54 claims were hiding in plain sight

The checker had a rule that sounded generous: a fenced block that will not run
alone is *reported* rather than failed, because it might continue one further up
the page or show syntax rather than a program. Both are real. **Both are also
true of a block with a typo in it.**

Counting what was inside those blocks settled it — **54 claims in 42 blocks, one
claim in thirteen** — and the split was the opposite of what
[3.16](COMPLETED.md#316-what-the-checker-does-not-check--done) had guessed. The
entry proposed telling *would not compile* from *compiled and then failed* on
the theory that the first was the suspicious one, since that is what had caught
`README.md`'s opening snippet. Ten blocks failed to compile and held **2**
claims between them, all of them shell and REPL transcripts, as harmless as they
looked. Thirty-one compiled and then failed, and held the other **52**.

So the fix was not a filter, it was a reading: **each block that runs joins the
document's context**, and a block that will not run alone is run again on
everything accepted before it. That is what the prose says out loud, since
*continuing the `point` above* can stand 370 lines and ninety blocks after the
`point` in question. It recovers 28 of the 42. The cheap version does not work
and it is worth knowing why: a fixed window of the nearest blocks recovers 24 of
the 54 claims at depth five and **not one more at twenty**, because the distance
is not the problem — what is between them is.

Three things had to be right and each was wrong first. The context cannot be
allowed to satisfy the block's own claims. A complaint is read wherever it
lands, and with stderr merged the streams interleave by buffering rather than by
source, so taking the context's line *count* off the front does not take the
context's *lines* off the front — nine blocks were accepted as having run when
they had produced nothing. And the program has to say it reached the end:
`system:exit` unwinds, which is documented behaviour with a block of its own in
the reference, and once that block joined the context every page below it was a
program that exited before reaching anything, for ninety blocks. A sentinel line
the run must echo is what stopped that.

**Eight blocks were broken**, in documents that have been read for months, and
the one wrong longest was `#45:new(#1):print.  ; #1` — a claim about what the
language *does*, which the language stopped doing, in a document whose first
paragraph promises every snippet has been run.

### A number in a sentence had no notation

The last gap in 3.16 was prose, and the difficulty is exact: a sentence is
neither a comment on a printing line nor a fenced block, so a number in one sat
outside everything `make test` proves. It has a notation now — `<!--count
claims-->`, which renders as nothing — and a name the table does not know is a
**failure**, so a marker cannot be misspelled into silence.

What recounting found is the argument for it. ROADMAP 3.14 said `float` answers
**21** messages; it answers **26**, five releases out of date, and that entry's
whole size argument rests on the number. The reference's message index said 121
across 215 where it is 122 across 216. And a position needs no marker because
the phrase is already one: nine programs open with *the fifth program here*, and
nothing had held that against the order they appear in.

### A global was found by walking a list

The morning's postmortem had turned a question about constants into
[3.17](COMPLETED.md#317-a-global-is-found-by-walking-a-list--done), and the
evening built it. An object with more than a dozen slots keeps an
open-addressed table beside its list, on the interned name pointer.

**What the entry got wrong was where the time was.** It was written about
globals; it is worth more to *sends*, because built-in messages are registered
in order and a new slot goes on the front of the list, so `add` — registered
first and used most — sat 35 slots down `integer`'s list of 38.

The first version was **30% slower** on a shallow send, which is the part worth
remembering. A probe counter said 2.00 probes a lookup, so the table was not the
problem; the table held slot *pointers* alone, so each probe followed one to
read `slot->name` — three dependent loads where a list walk has one. **A short
linked list is not slow**, because an object's slots are allocated together and
the walk reads memory the prefetcher already has. Putting the key in the table
beside the slot took it from 30% to 12%; a stronger hash measured slower and was
thrown away.

The trade is real and it is written down: a send four slots deep is 0.88× and
reading the most recently bound global 0.89×, both intervals entirely below 1.
What makes that the right way round is that the old order was **recency**, so a
library's name was the slowest to read and the program's own the fastest, which
is backwards for the case it matters in.

---

### Postmortem

**Breaking a rule deliberately to check the test would catch it hung the
suite.** A full table makes linear probing spin, and the insert loop had no
bound. It is bounded with an assert now — the failure a test is checked against
should be a message, not a wait.

**And I reported a test as failing to catch a deliberate break when it had
not.** The binary was stale: `make` does not rebuild tests, `make test` does. On
a proper rebuild the break was caught loudly — it breaks `object:new` itself.
The lesson is smaller than the last few but the same shape: I read an old
artifact and reported it as a result.

---

## 2026-08-23 — a square root, a compiler that compiles itself, and six things measured wrong

Three releases. 0.22.0 put `sqrt` in the machine and the whole language on one
page; 0.23.0 made Solum compile itself; 0.24.0 answered four design questions,
built one of them, and found a new limitation by measuring an argument.

### The square root was wrong twice, and the second time was worse

`bench.sol` needed a square root the language did not have, so it wrote one.
Yesterday's entry recorded that the first attempt — twenty fixed iterations of
Newton's method — was wrong at 1e10 and silent about it, and that the fix was to
iterate until the answer stopped moving with a cap of sixty steps.

**The fix was wrong too.** A value above about 1e21 has not finished halving in
sixty steps, so the loop returns `x` divided by 2^60: `sqrt(1e300)` answered
8.67e281 rather than 1e150. Nineteen orders of magnitude, from the version
written to correct the first mistake.

**And 0.21.0 had said it converged.** That release's changelog and its tag both
stated that testing the square root at 1e300 found a bug in the formatter and
nothing wrong with the square root. What had been compared against the C library
was *the digits the formatter produced* — right, once the formatter was fixed —
and never the value they were the digits of. A wrong number can survive being
looked at carefully if what you look at is how it prints. The 0.21.0 entries and
yesterday's journal item now carry that correction where they made the claim.

So `sqrt` is a primitive, and the argument for it is not convenience. `min`,
`max` and `between` came out right the first time and are only
[math.sol](../lib/math.sol); the square root was written twice, wrong twice, and
silent twice. **A thing every program would get wrong the same way belongs in
the machine.**

### One page, and the gaps writing it found

[CHEATSHEET.md](CHEATSHEET.md) is the whole language on one page — every type,
every message, the six rules that bite, and the command lines. Two tests hold it
there: one fails if a message is registered without being listed, the other runs
all 64 examples.

Writing sixty-four examples in one file met every edge the checker has, and
found a third gap for [3.16](COMPLETED.md#316-what-the-checker-does-not-check--done).
**A claim on a line that does not itself print is never read.** `point:show.`
prints from inside the method, so `; #3` beside it is decoration. Six of the
first draft's sixty-eight claims were in that state, including the `repeat` and
`toByDo` loops where only the first of three output lines was ever compared. The
checker reports those lines rather than hiding them, which is why this is a
paragraph in that entry and not a fourth row.

### What the language is for, which had never been written down

Asked about trigonometry, the first answer argued it away partly on the grounds
that the ten programs here are text and process work, so geometry is not what
this language is for. **That reasoning was wrong and was called out**: the
programs describe what has been built, not what the language is. They lean
towards text and processes because they are the tools this project needed while
building the thing that runs them.

[design.md](design.md#what-the-language-is-for) now says the goal outright —
general-purpose — with the rule that follows for reading the roadmap: *no
program here has wanted X* is a reason to wait for one before choosing a shape,
never a reason to rule a direction out. Both documents record the wrong reason
as wrong.

### Solum compiles Solum

Six files, in stages, each with a gate.
[emit.sol](../experiment/emit.sol) wrote a `.sob` by hand — no lexer, no parser,
two chunks byte by byte — because the back end was the half that could have been
impossible. Then the scanner, then the parser and a subset compiler, then blocks
and frames and lexical capture, then the control flow `solas` compiles to jumps,
then `@include`.

The bar throughout was `cmp` against `solas`, not "runs the same", and that bar
earned its keep repeatedly. It caught a chunk's slot count being written twice —
a file four bytes long that ran perfectly well, because nothing reads past what
it needs. It caught constants keyed without their type, so `#45` and `45` shared
a slot: a program that pushes an integer where a float was written, which runs,
and which only a byte comparison notices. It caught a byte taking the line of
the token just consumed rather than the line its construct began on — the two
coincide for one-line statements, which is the whole of `hello.sol`, so an
earlier stage had passed without knowing the rule existed.

**And then it stopped at 42 of 46 files, on depth rather than on any
construct.** The four it could not compile included its own parser and its own
source.

### The cap that was one number pretending to be two

`SOL_FRAMES_MAX` had been left at 64 because `SOL_STACK_MAX` was derived from
it, and a `SolVM` holds both arrays inline and lives on the C stack — including
on threads, where the default is often 512KB. Eight times the frames meant a
machine too big to put on a thread.

**They did not have to be one number.** Frames are 56 bytes each. Sized
separately, 256 frames cost **4% more memory for four times the depth**, and
both ends stay bounds-checked, so nothing became a crash that was not one
before. Recursion went from 62 levels to 254, `evaluator.sol` from 18 brackets
to 83, `lib/json.sol` from 28 levels of nesting to 124 — three programs that had
each written a limit down found it moved — and the compiler compiled its own
source.

The fixpoint: `solas` compiles the compiler; that compiler compiles its own
source to a byte-identical file; that one compiles its own source again,
identical; and it still agrees with `solas` on everything else. Four claims, all
in `make test`.

**Then it was parked.** A second compiler has to be taught every construct the
first one learns, and the proof does not need repeating to stay true. Six files
to [experiment/](../experiment/README.md), off the search path and out of the
suite, with a script that runs the proof again on demand.

### Four questions, one built

`ifElseIf` went into the library: a chain of alternatives written flat, which
`disasm.sol` now uses for its constant tags. Its costs were measured before the
guidance was written — 5.8× a nested chain, three frames a level through a
recursion — so the advice is *flat dispatch yes, recursive descent no* rather
than a preference. It also closed the `switch`/`case` entry, which had refused
this as a library years of commits ago on interface grounds that turned out to
be right: what changed was not the capability but the shape.

Default parameter values, constants, and `forever`/`break`/`continue` were
recorded and not built. Each argument was moved by a measurement rather than an
opinion, and the constants one moved furthest — see below.

---

### Postmortem

**Six things I got wrong, and the pattern in them is the same.**

1. **"The square root converged."** Written into a changelog and a release tag
   on the strength of comparing the formatter's digits against the C library —
   which was checking the printing, not the number. The right check took one
   line and I did not do it.

2. **"An explicit-stack parser unlocks the last four files."** Said at the end
   of a message, unmeasured, as if it followed. It does not: the compiler stops
   at the same depth. Then, correcting it, I said the compiler was "sitting
   immediately behind the parser" — which was *also* unmeasured, an inference
   dressed as a result, and only came out because I was asked whether the two
   statements matched. Splitting the compiler into a library so a tree nobody
   parsed could be handed to it is what settled it. Both claims had reached
   three documents by then.

3. **Chained `ifTrue({...}):ifFalse({...})`** in the include code — the exact
   trap written into the cheatsheet's *six rules that bite* about four hours
   earlier, by the same hand.

4. **A benchmark comparing unequal work.** Trying to separate a library loop's
   block-call cost from its error machinery, I compared `repeat` against an
   inlined `whileTrue` that was doing two more operations a pass, and it came
   out *faster*. The number was meaningless. I threw it away rather than
   reporting it, which is the only part of that worth keeping.

5. **Under-selling an argument by measuring the wrong thing.** Asked whether
   constants would be faster than a global, I measured `r:mul(r):mul(pi)` — an
   expression where the lookup is a fifth of the work — and reported 25ns as if
   that settled it. Pushed on it, isolating the lookup gave 16× in the
   pathological case and, more usefully,
   [3.17](COMPLETED.md#317-a-global-is-found-by-walking-a-list--done): global lookup
   walks a list, linearly, recency-ordered, so the name a *library* bound is the
   slowest to read. **The measurement redirected the question from "should we
   have constants" to "why is a global read O(n)".**

6. **Five changelog entries dated a day ahead**, in a document whose header says
   dates are the day the work was done. Corrected in the same commit as this.

**The theme is one thing said several ways.** Every one of the six is a claim
made from reasoning that a two-minute measurement would have refuted, in a
session whose entire method is measuring. The ones that got caught were caught
by somebody asking, or by a byte comparison, and not by me re-reading what I had
written.

**And a second theme, about the tools rather than about me.** The checker cannot
catch a claim that *stops* being checked. Three instances today: the README
block that failed to compile and was silently skipped; the reference's four
library examples, which stopped compiling when their files moved to
`experiment/` and took 13 claims out of the count with every remaining claim
still holding; and 3.5's own worked example, which said `#62:down` succeeds and
`#63:down` fails and was never a claim at all, because neither line prints. That
is [3.16](COMPLETED.md#316-what-the-checker-does-not-check--done), and it is now the
entry with the most instances behind it.

**What went right is worth the same attention.** Deliberately breaking a rule to
check that a test would fail caught two tests that would have passed on broken
code — the lexer corpus, where 33,000 tokens of working Solum contain no `1e`
followed by a non-digit, and the compiler's constant keying. Working code does
not contain the corners, so a corpus needs a fixture beside it. And the
byte-identity bar found three faults that behaviour tests could not have,
because all three produced files that ran correctly.

## 2026-08-22 (night) — everything written down, and then a benchmark

Two releases' worth of work in one stretch, and both halves ended by finding
something the work itself had put there.

### Finishing the sweep

The documentation checker took one path. It now takes several, so `README.md`
and `index.md` — the first thing anybody reads, and the last two documents
nothing checked — joined the run. The two claim tests became one,
`test_everything_written_down_is_true`, because once everything is checked there
is no distinction left to draw: 589 claims across 40 files, one invocation, one
floor.

**And the front page did not compile.** The opening snippet, four lines that
introduce the language, was missing the `.` after `a := #45`. The checker had
seen it every run and said nothing, because a block that fails to compile is
classified *shows syntax rather than a program* — which is right for the
`$ ./bin/solis` transcript further down the same page, and wrong here. The
category that keeps the tool honest about what it cannot check is also where a
real fault can hide. That is now [3.16](COMPLETED.md#316-what-the-checker-does-not-check--done).

### The cut that found the drift

Bumping the version for 0.20.0 forced a rebuild from clean, and the claim count
came back **588 where it had been 589**. Not a flake — one number on a clean
tree and another on a warm one, every time.

`GUIDE.md` asks `system:modifiedAt("notes.txt")` and no block in it creates that
file; `REFERENCE.md`, further down the alphabet, writes one. Both run in the
sandbox introduced hours earlier, so the guide's block failed on a clean tree and
passed on every run afterwards **off the leftovers of the run before**. The
sandbox that stopped documentation from reaching the repository had quietly
become a way for one run to reach the next.

Worth being blunt about what that meant: every number reported in the previous
session was the warm one. *Everything written down is checked* was true on this
machine and false on a fresh clone until the second `make test`. What made it
invisible is that the second run of anything is the one you look at.

### Program ten, aimed at a gap

Nine programs came before and every one was a job first. [bench.sol](../programs/bench.sol)
is the first written the other way round — pointed at the most conspicuous
absence in the language for a scripting language, which is arithmetic.

It times a command repeatedly, interleaves two of them with a coin flip deciding
the order each round, and answers with a bootstrap interval rather than a
winner. Given the same command twice it says `1.001, interval 0.985 to 1.015`
and *this many runs cannot tell them apart*, which is the test a tool like this
has to pass before its other answers are worth anything.

**The gap is real and it is not the one it looks like.** There is no `sqrt`, no
`min`, no `max` and no randomness — and all four were writable, and all four are
in the file. What the experiment measured is the cost of writing them:

- **The `sqrt` was wrong on the first attempt, and silent.** Twenty iterations of
  Newton's method, on the reasoning that it converges quadratically. `sqrt(2)`
  was right to twelve places; `sqrt(1e10)` answered `100000.000156`. Quadratic
  convergence is what happens *after* the guess is close, and starting from `x`
  itself the first phase is one halving per octave — seventeen of the twenty
  iterations gone before the good part began.
- **The textbook random generator cannot be written in this language at all.** A
  linear congruential generator relies on the multiplication wrapping, and
  integer arithmetic here traps on overflow. Lehmer's works, with a multiplier
  and modulus chosen to stay inside 64 bits — but "write your own" is narrower
  advice than it sounds when the reason is nothing to do with randomness.

That is [3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done),
and [3.15](COMPLETED.md#315-a-childs-streams-cannot-be-redirected--done) came with it: a
child's stderr cannot be discarded, and a benchmark harness is the one program
that cannot buy its way out through `/bin/sh`.

### And the bug under all of it

Testing that hand-written square root at 1e300 printed sixty-three digits and
then binary garbage.

`prim_float_as_string` wrote into a 64-byte buffer and passed `snprintf`'s answer
— the length it *would* have written — on as the length of the result. `snprintf`
truncates rather than overflowing, so nothing was corrupted; instead everything
downstream read 157 bytes out of 64, and `1e150:asString("0.6")` returned a
string whose last 93 characters were the stack behind the buffer. A script can
print them. Reachable from one line of Solum, and in a code path four shipped
binaries use.

Fixed by sizing the buffer for the worst case the spec permits and clamping the
length to it regardless. The other four `snprintf` sites were audited: two
already clamp, two cannot overflow their buffers.

**The shape of this find is the thing to remember.** The bug is in the formatter
and has nothing to do with square roots. It surfaced because a program needed a
function the language lacks, wrote it, and then tested that function at the edges
— and the edges of `sqrt` are where the *printer* had never been. Two absences
compounding: no `sqrt` to use, so one gets written; nobody writes `1e300` into a
document, so nothing had ever formatted one.

### Postmortem

**Five things went wrong today, and four of them were mine.**

1. **I reported warm numbers as if they were the numbers.** Every claim-count
   quoted in the previous session was from a tree that had already run the
   checker once. The property I said was established — everything written down
   is checked — did not hold on a clean tree. I did not think to run it twice,
   and there was no reason not to. The fix is in the tool now; the habit worth
   keeping is that a verification tool must be run *from clean* before its result
   is quoted.
2. **I wrote "each works" about the arithmetic before testing it at scale.** The
   `sqrt` header said so while `sqrt(1e10)` was wrong in the fourth digit. The
   claim was written from the reasoning (Newton converges quadratically) rather
   than from a run, which is exactly the mistake this repository built a checker
   to stop, made in a file the checker does not read.
3. **A bisect that could not find what it was looking for.** Hunting the 588/589
   drift I ran each document twice and diffed — and concluded no file differed,
   which was true and useless, because the dependency was *between* files. It
   took seeding the artifact by hand to locate it. A per-item search cannot find
   a cross-item interaction, and I should have reached for that a step sooner.
4. **An off-by-one asserted rather than computed.** The new format test claimed
   `DBL_MAX` at 40 decimals is 351 characters; it is 350. The assertion caught
   it, which is what assertions are for, but it was arithmetic I did in my head
   next to a `python3 -c` that would have answered it.
5. **A near-miss worth recording**: comparing the VM's output against Python's
   formatting of `1e150`, when what the VM had printed was `sqrt(1e300)` — a
   different double. The two disagreed for a legitimate reason and I nearly
   filed it as a second bug. Checking the exact value directly is what separated
   them.

   > **This was not a near-miss.** Written the next day: the two disagreed
   > because `sqrt(1e300)` was *wrong* — the hand-written square root answered
   > 8.67e281 where the answer is 1e150. Resolving the disagreement by formatting
   > `1e150` directly proved the formatter's digits were right and said nothing
   > about the value, and I recorded that as a false alarm. Item 2 above was
   > therefore still true when this was written: the second `sqrt` was as wrong
   > as the first, by a great deal more.

**What went right is worth the same attention.** Every one of today's findings
came from running something rather than reading it: the drift from a clean
build, the `sqrt` from testing an obvious edge, the formatter bug from testing
the `sqrt`'s edge, the README typo from pointing an existing tool at one more
file. Nothing was found by inspection.

---

## 2026-08-22 (evening) — the last decision, deferred

Six releases and then a conversation rather than a commit.

I had put 6.32 forward four times as the next thing and it had not been picked
each time, so I said so — that if it was parked deliberately I would rather know
than keep re-proposing it. That turned out to be exactly right and the answer
was better than the question: it is parked, and for a reason I had not weighed
properly.

**Every other roadmap entry came from a program wanting something.** 6.32 came
from a *concern* about a use this language does not have. It was raised as "this
could be a thing in future", and I had been treating it as the last item on a
list rather than as a guess about where the project might go. Those are
different kinds of thing and only one of them is urgent.

So it went to the idea box with a trigger — somebody runs a script they did not
write, or embeds the machine where input arrives from a stranger — and the
roadmap is down to section 3, which is restrictions and not work.

**What it produced on the way out is the argument for having kept it open at
all.** Two things came from trying to answer it, both built, neither a
permission: the limits a host may set, and the entire embedding interface. The
second exists only because working out what a permission would *attach to* meant
first writing down what a host may rely on — and that write-down found a
use-after-free in shipped code and a false claim I had made twice.

That is a good record for a question that never got answered.

---

## 2026-08-22 — the first program run by a stranger

One program, and it corrected the release that shipped the day before.

**How the day started: with nothing to build.** The roadmap says so in as many
words — everything is built except one decision, and the way to add to it is to
write a program and find out what it wants. So the first hour went on the one
document yesterday's refresher pass had missed. `docs/ideas.md` exists so an
idea does not have to be re-argued in six months, which only works if the
verdicts are current, and nine rows of its table still said *build it* about
things that shipped. It also claimed four loops were in `lib/control.sol` when
all four had left for the VM. Fixed, with what each guess turned out to be
rather than just a status, because the guesses are the part worth keeping.

**Then the actual job**: [serve.sol](../programs/serve.sol), a CGI-shaped
request handler. `/`, `/search?q=...`, `/note/<name>`, served out of a directory
of files, with seven requests run through itself when no CGI variables are set
so it is testable without a socket.

The point was not the program. Every other program is handed its arguments by
the person who started it; this is the first one handed a path and
a query string by a stranger, which is the case
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
is about and which no program here had ever been.

**What it wanted, in the order it wanted it.**

`fill` is the injection. It is the obvious way to build a page and it inserts
exactly what it is given, and nothing in the language or the libraries escapes
HTML. Then: a template with a value-shaped hole and a fragment-shaped hole
cannot use `fill` at all, because `fill` insists the counts match — which is the
check that makes it trustworthy, so the answer is not to want it weakened. The
marker-and-`split` habit that replaces it is worse, since a marker is a string
and a value can contain one. What survived is an array of pieces joined.

Refusing `/note/../../etc/passwd` turned out to be the easy one, and easy for an
unexpected reason: the language has no path handling at all, so the tempting
wrong answer — clean the name — was not available, and what is left is to say
which names are names. Which is the right answer anyway. A restriction doing
useful work by being a restriction.

**The finding that mattered was not in the program.** It came from running it
the way its own case would: as a guest, with an allowance. A request costs 393
instructions for a note, 465 for the index, 798 for a search. Then, out of
curiosity: how many instructions is reading a large file?

| | steps | time |
| --- | --- | --- |
| `nil:print.` | 4 | — |
| `readFile` of 64MB, then `indexOf` over all of it | **8** | 0.27s |
| the same over 256MB | **8** | 1.10s |

Eight, and eight, and the count does not follow the size. A step is a unit of
dispatch. Yesterday's release counts them and calls it bounding a program's
work, and it is not — it bounds a program that *loops*, which is what it was
built for and is a real thing to bound, but a single message can cost whatever
it likes. The memory ceiling is the same fact from the other side: it is checked
after an allocation, so under a 1MB limit that 256MB read completes and the
program is stopped holding 268 million live bytes.

**Two documents said otherwise and now do not.** `design.md` claimed
instructions were the one thing a program could not hide from, and that the
overshoot was bounded by one instruction. Both are true of time and neither is
true of size. 6.33's own entry claimed it bounded a program's work.
[3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work) is the new entry, and it
is the first in section 3 that was *discovered* rather than chosen — which is
worth the sentence it got in the section intro, because a restriction found and
a restriction decided ask different things of a reader.

**And 6.32 got its first concrete argument** rather than another paragraph of
reasoning. A CGI handler is told what it was asked entirely through
`system:environment` — which 6.32 correctly lists among the messages that
*reveal* the machine. The handler cannot be written without it. So a permission
scheme with one switch per message must grant `environment`, and has then also
granted `AWS_SECRET_ACCESS_KEY`. The permission a webserver cannot do without is
the one that hands over its secrets. That does not settle the shape, but it
rules one out: per-message is not fine enough where the message names something.

**Then the directory split**, which was the day's second thing and came out of
the first. `examples/` had thirty-two files doing two jobs, and adding serve.sol
made that plain enough to act on: seven of them are whole programs written to do
a job, twenty-five are demonstrations of one feature each. They now sit in
`programs/` and `examples/`.

What made it easy is that the split was not mine to draw. Each of the seven had
been opening with *"the fourth program here written to do a job rather than to
show a feature"*, numbered in arrival order, for as long as there had been more
than one of them. The files had been maintaining the distinction all along; the
directories only make it visible in a listing. No file needed a ruling — not
even `stock.sol`, which is a real program and stays put because it exists to be
the tutorial's worked example.

109 paths rewritten, and each of the seven lost the second half of its own
opening sentence, because the directory now says it.

**And the audit the split had asked for**, which `ideas.md` had been carrying
unanswered since the ideas file was written: does every concept the guide names
have a demonstration? The split is what made it answerable, because until today
"an example" and "a program" were the same directory.

Three axes, and the guide came out clean — all 22 sections have a `Run:` pointer
and every pointer resolves. The interesting one was messages: four of 121 were
sent by nothing in `examples/`. Not lost in the move — `values`, `modeOf`,
`setMode` and `setModifiedAt` had *never* had a demonstration, and had been
carried the whole time by `mirror.sol` and `log.sol` happening to need them.
Which is exactly the thing an audit is for and exactly what nobody would notice
by reading.

Both gaps went into the example they belonged in, and then the test got
stricter: message coverage is `examples/` only again. A message covered by
appearing in the middle of two hundred lines of log parsing is not covered for
anybody looking it up.

Then [programs.md](programs.md), because a directory of seven programs with no
page saying what they do is a directory people open once. Every invocation in it
was run before it was written down.

**And then the host**, which was the day's third thing and the one that paid
best. 0.14.0 went out; the obvious next move was the C host, because 6.32 keeps
saying "the restriction has to be settable from C, before the program runs" and
nothing in this repository had ever held a `SolVM` inside another program. The
whole claim was untested.

It took about a hundred lines and **broke on the first run**. Six of seven
requests failed with `undefined name 'lessThan'`, `undefined name 'truncated'`,
`cannot bind 'shiftRight' on boolean` — different built-ins each time, none of
it meaning anything, which is what reading freed memory looks like.

The cause is the nicest kind of bug: a correct-looking thing that is wrong only
in the case it was written for. A chunk records which VM interned its names so a
second machine re-resolves them, and it recorded that machine **by pointer**. A
host serves each request in a function that makes a VM as a local — so every
request's machine sits at the same stack address, and the chunk concluded it had
already done the work. It then went on reading the *freed* previous VM's name
table.

The test for this exists. `test_a_second_vm_reresolves`, written for exactly
this hazard — and it holds both VMs as locals of one function, so they get
different addresses and the pointer comparison works. It was never wrong; it was
just never in the shape that fails.

A serial fixed it, which is one field and one counter. The regression test
builds each VM in a *called* function, which is the thing a host does and the
thing nothing here had done.

The rest of what the host found was more or less what I predicted before writing
it, which is worth noting because it means the predictions were doing work: no
route for the answer back out, a fresh VM per request being the only safe
choice, and ROADMAP 3.6 collecting its second victim. What I did not predict was
the defect. That is the argument for building the instrument rather than
reasoning about the interface.

**Then the contract**, which was the conclusion of the host acted on rather than
filed. The host's finding was that 6.32 could not be decided yet, because a
permission is a promise about what a host may rely on and there was no list of
what a host may rely on. So: `solum/embed.h` as the whole supported surface,
`docs/embedding.md` as the contract in prose, `tests/test_embed.c` holding every
promise on it.

Writing it caught a mistake within the hour, and the mistake was mine from the
day before. I had said twice — in the host's own comments and in the first
version of the embedding page — that a host must call `sol_vm_intern_chunk`
before each run. It does not. `sol_vm_run` calls it and always did; the defect
was *inside* that function rather than in a call somebody could miss. I only
found out because writing "here is what you must do" forces you to check that
each item is true, which reading the same code twice had not.

The four functions added are not new capability — each names two or three calls
a host could already have made. That is the whole idea. Three internal calls in
the right order is not something anybody can rely on, and the gap the host found
first (a run's output going to stdout, where a webserver cannot pick it up) was
never a missing mechanism, only a missing name for one.

The part I am least comfortable with is written down as such: a host and a
script agree on a global name, and nothing checks that they do. That is a
convention wearing a contract's clothes, and saying so seemed better than
dressing it up.

**And the day's last hour on its own leftovers.** The contract had listed four
things as not promised; one of them was a wart rather than a decision — a host
got every failure twice, once in its own log and once on stderr it did not ask
for — so that became a flag and a test that captures the descriptor to prove it.

The other three got numbers. The roadmap says of itself that it is the single
list, and that had quietly stopped being true: `embedding.md` was carrying three
real limitations that appeared in no other document. Numbering them is the sort
of tidying that feels like bookkeeping and is not — it was the *interface
document* that produced them, because stating what a host may rely on forces you
to state what it may not, and that second list is an audit nobody set out to
run.

Worth remembering as a technique: **an interface document is an audit of
everything it declines to promise.** I did not know that going in.

**And then threads, which I had recorded an hour earlier as unknown.** The entry
said what would settle it was a test, not a decision, and there was a specific
reason to suspect the answer: the counter I added this morning to fix the
use-after-free is a `static uint64_t` incremented in `sol_vm_init`, and nothing
synchronises it.

I estimated the window at three instructions in 52 microseconds and expected
collisions to be rare enough to be awkward to demonstrate. **Sixteen threads
building 480,000 machines produced 10,319 duplicates — one in fifty.** I was
wrong by orders of magnitude, and the reason is worth keeping: a contended
increment is not brief, whatever its instruction count says, because the cache
line has to be fought over.

Then the fix worked and the test still failed, which was the better half of the
day. Serials unique, per-thread machines fine — and *sharing a chunk* segfaults,
because running a chunk mutates it. The interned names are cached on the chunk,
keyed to one machine at a time, so two threads free and rebuild that table under
each other. Serialised behind a mutex: 0 failures of 2,400. So it is the sharing
and nothing else.

That one is not a bug to fix. It is per-VM state living on shared data, and
moving it costs a lookup on the hottest path in the machine for a use nobody
has. Recompiling per thread costs milliseconds once. Written down rather than
built.

The thing I keep relearning: **I am bad at estimating how likely a race is, and
good at reasoning about whether one exists.** The existence argument was right
both times. Both magnitude guesses were wrong, and only running it told me.

**And last, the counterweight I had been recommending for six turns and not
taking.** Everything since serve.sol had been about the machine — auditing it,
documenting it, reorganising it, measuring it. Nothing had been *written in the
language* to do a job, which is where every roadmap entry before this run came
from.

So: [disasm.sol](../programs/disasm.sol), a `.sob` reader. The job is real and
`solvm --dump` already does it, which is the point — a second implementation is
how you find out whether a specification is true. Written from design.md and
BYTECODE.md, going to the C only where those ran out.

They ran out five times, and three were the documents being *wrong* rather than
thin:

- BYTECODE.md described every instruction and never said what byte any of them
  was. The test suite checked the description against the header in both
  directions; nothing checked, or supplied, the numbers. You cannot decode one
  instruction from that page.
- design.md said "big-endian" in one section and "little-endian throughout" in
  another, about the same bytes, a hundred lines apart. I read the second and
  decoded every operand backwards. It does not look like a misreading — every
  index came out 256 times too large, which looks like a corrupt file.
- The format table had been missing three whole sections since version 12. Two
  features bumped the format and neither updated the table.

All three are fixed, and the opcode numbers now have a test, which is the part
that lasts.

The two language findings were smaller and both are the language being right:
an i64 with its top bit set cannot be reassembled from bytes because shifting
traps on overflow, and a float has to be decoded by hand because nothing
reinterprets bits. So Solum can write an integer into a file it cannot read
back. That is a consequence of a good decision, and worth knowing.

**What I want to remember about this one**: I nearly did not write it. It was
the option I kept listing last and recommending against my own advice. Six turns
of inward-facing work had produced good things — but the document faults had
been sitting there since version 12 and no amount of auditing the machine found
them, because auditing checks a document against the code and this checked the
document against *someone trying to use it*. Those are different tests.

**And then the same trick again, pointed somewhere else.** The disassembler had
worked by checking a document against somebody trying to use it. `examples/`
carries about four hundred comments claiming what each line prints, and nothing
had ever checked one — the suite compiles every example and never runs one. Same
standing as the format table: true because somebody looked, once.

[expect.sol](../programs/expect.sol) runs them all and checks the claims. Every
one that states a value holds, all 398, which is the boring outcome and the one
I wanted. What it found instead was that three different comment conventions had
grown up unnoticed, because nothing had ever had to *parse* them — the value
alone, an aside after a dash, and an aside with no dash at all.

The temptation was to call two of those wrong and normalise. That would have
been the checker measuring itself, so it learned all three instead. Nine
comments turned out to be glosses rather than claims and now open with `--`.

It is in `make test`, which is the part that lasts: a third of a second, and
changing one `; #5` to `; #6` now fails the build. I checked that it does rather
than assuming, having spent yesterday learning what an unchecked check is worth.

**A note on my own error rate.** I wrote `x:ifTrue({...}):ifFalse({...})` again
here — third time in this session. `ifTrue` answers the block's value, so it
cannot be chained. Three times is not a slip, it is a wrong model I keep
reaching for, and writing it down is the only thing likely to change it.

**Last thing, and the one I would keep if I could keep one.** The disassembler
had reported `<i64 too large to read>` for constants with the top bit set, and I
had written in three places that Solum could write an integer into a `.sob` it
could not read back. The job was to give that a roadmap number.

Writing it down disproved it inside five minutes. Stating a limitation exactly
means checking it, and `(b - 256) * 2^56` reaches every value the shift cannot —
INT64_MIN included. The shift failing was one route failing, and I had read it as
the number being unreachable.

So instead of a limitation there is a defect fixed, three documents corrected,
and 3.12 saying something much smaller and true: no shift can produce a negative
integer, because there is no unsigned type and shifts trap. Which follows from
two decisions worth keeping and costs a line of arithmetic to avoid.

**Twice in two days now.** Yesterday it was `sol_vm_intern_chunk` — I wrote that
a host must call it, in a header and a page, and `sol_vm_run` calls it. Both
errors survived being written into a program's comments *and* a document, and
neither survived being written as a promise. There is something specific about
the register: a comment explains, and a promise invites the question "is that
so?".

**The shape of the day**, which is the thing this file is for: the program was
the instrument, not the result. Seven times over — and once, the writing was:

- **serve.sol found 3.7** by being run as a guest with an allowance, which no
  program here had been, because every earlier one was run by whoever wrote it.
- **The split made the audit answerable**, and the audit found four messages
  that had never had a demonstration.
- **The host found a use-after-free** on its first run, in a path four shipped
  binaries could not reach.
- **Writing the contract found a claim of mine that was false**, because
  "here is what you must do" forces a check that reading the same code twice
  does not.
- **Testing threads found a data race in this morning's fix**, and then a second
  defect the fix could not have touched.
- **Writing a disassembler found three faults in the documents it was written
  from**, two of them shipped since version 12.
- **Checking the examples against their own comments found three conventions**
  where everyone assumed one — and put 398 claims under `make test`.

None of the seven came from reading. Each came from putting the thing in a shape
nobody had put it in before — run by a stranger, run under a limit, run twice at
one address, written down as a promise, run on two threads at once, or handed to
somebody trying to implement it from the documentation alone.

---

## 2026-08-21 — 0.1.0 to 0.13.0

Thirteen releases, 113 commits, 07:31 to 19:04. The project was three days old
at the start of it and had no releases; it ended with a language, four programs,
and one open decision.

**The arc.** Each release came from the same question — *what does a program
that gets written in this actually want?* — and mostly from writing one and
finding out.

| | |
| --- | --- |
| **0.1.0** | the first release |
| **0.2.0** | a failure can be recovered from — `onError`, then `ensure` |
| **0.3.0** | a program can deal with the machine it runs on |
| **0.4.0** | a byte has a number, and the language reads JSON |
| **0.5.0** | an HTML reader, and the frame limit turns out to be about traversal rather than data |
| **0.6.0** | no open design questions left in the language |
| **0.7.0** | the prompt became a place you can work — line editing, history |
| **0.8.0** | a filesystem it has to *change*, and a keyboard |
| **0.9.0** | bits, and the first tools for looking at a program rather than writing one |
| **0.10.0** | a stack trace says which file; the `.sob` format changes for the first time |
| **0.11.0** | a frame slot knows what it was called |
| **0.12.0** | a debugger, and a program can run another program |
| **0.13.0** | a program can be given a limit, and the machine can take it back |

**What the libraries taught us**, which was more than the design did. `lib/json.sol`
found that a byte had no number, and put a price on how value dispatch is
written — a dictionary of blocks costs ten levels of nesting against a chain of
`ifElse`, because each `table:at(c, default):value` is one more frame per level.
`lib/html.sol` found that an array could not be popped, and that the frame limit
is about *traversal* and not about data: it builds fifty thousand levels with a
stack quite happily. `lib/text.sol` broke a program from a distance by claiming
a common global name, ten minutes after the roadmap entry saying that could
happen was written.

**The last four entries came from a different question** — not *what does a
program want* but *how would one be debugged* — and had to be done in order:
`--trace`, then file names in stack traces (a trace that cannot name a file is
misleading rather than thin), then slot names at run time (a debugger that
cannot name a local is most of the work for a fraction of the use), and only
then Solid itself.

### The evening: running somebody else's code

The day ended on one subject, and it arrived as a question rather than a want.

`system:run` landed in 0.12.0 and made the language able to invoke another
program — which is what a scripting language for an OS has to do, and is also
the moment the language became able to do real damage. That prompted the
observation that there might want to be a **safe mode**, and it was recorded as
roadmap entry 6.32 rather than built.

**Then the motivation arrived and moved the entry.** The case was not somebody
running a script they were sent: it was a **webserver** producing pages by
running Solum, where injection could turn untrusted input into code the server
executes, and where the thing choosing the restriction is the server, protecting
itself. Three things fell out of that:

- The chooser is a *program*, deciding once at startup, not a person who might
  forget. So the argument shifts from which default to **where the mechanism
  lives**: it has to be settable from C before the program runs, with a
  command-line flag as one front end over it rather than the thing itself.
- What is untrusted is the **data**, not the file. The server wrote the script.
- `system:exit` came off the dangerous list. It unwinds and answers `SOL_EXIT`
  rather than calling `exit()`, so a script that exits ends itself and the
  webserver stays up. Already right, and worth naming because it is the one an
  embedding would most expect to be wrong.

**And it promoted the caveat that had been buried.** 6.32 ended with *it is not
a sandbox — a restricted script can still loop forever*, which on a command line
is a shrug and in a webserver is the whole server, with nothing dangerous called
and no injection needed. That became 6.33, and 6.33 got built.

The measurement that decided how is worth keeping. The debug hook already
existed and could already stop a running program — Solid quits out of one that
way — so the cheap answer was to reuse it. It does not work:

| loop | iterations | times the host was offered a stop |
| --- | --- | --- |
| `{ ... }:whileTrue({ ... })`, one line | 3,000,000 | 1 |
| `#1:toDo(#5, step)` | 5 | 5 |

The hook is offered when the line or the frame changes, and a loop written
literally compiles to jumps, so neither moves. **What makes `--trace` bearable
makes the program unstoppable.** The counter went into the dispatch loop
instead, which is the one place every instruction has to pass.

Two decisions inside that are worth remembering:

- **Memory is measured after a collection.** Before a sweep the figure counts
  everything ever allocated and not yet reclaimed, so a ceiling read off it
  stops a program for litter rather than for what it holds.
- **A stop cannot be caught**, and `ensure` does not run its cleanup either.
  Both are ways of running more code, and the allowance for running code is
  what ran out. That costs little here only because nothing in this language
  has to be released.

### The hour that produced no feature

The day closed by checking the roadmap against the implementation rather than
against its own prose — every open entry re-tested, not re-read. Nothing needed
moving: `slotAtPut` and `clone` are still absent, `via` still refuses a value
receiver, a capturing block still cannot outlive its frame, recursion is still
exactly 62 levels and 63 is not.

It found four things anyway: two links pointing at 6.33 where it used to live,
one link to a heading that had been reworded without the link following, an entry
(3.3, on verification not promising termination) that the morning's work had
quietly made incomplete, and a note asking that "a later range or slice API"
use inclusive bounds — when the slice half had shipped long since and already
did.

**The lesson to carry**: an entry does not go stale when it is wrong. It goes
stale when the world moves underneath it and it stays technically true, which
is much harder to notice and is why the check has to be against the code.
