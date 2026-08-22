# Journal

*What a day of work on Solveig actually consisted of, newest first.*

The [changelog](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. Neither holds the shape of a
*day* — what was picked up and why, what turned out to be wrong, and the hours
that produced no code because they were spent deciding something or checking
that a document was still true. That is what this is for.

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
[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
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
