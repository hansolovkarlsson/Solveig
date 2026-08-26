# Journal

*What a day of work on Solveig actually consisted of, newest first.*

The [changelog](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. Neither holds the shape of a
*day* — what was picked up and why, what turned out to be wrong, and the hours
that produced no code because they were spent deciding something or checking
that a document was still true. That is what this is for.

---

## 2026-08-26 (the editor, finished) — a postmortem

Eleven commits. The first at 18:43 on the 25th, the last at 09:44 on the 26th,
and **ten of them inside three hours and forty-seven minutes** of one morning.
1,766 lines of editor, 44% of it comment; 429 lines of matcher; 771 lines of
checks. It edits itself, which is the only acceptance test a text editor has.

### What it was for, and what it got

The rule this repository runs on is *write a program and find out what the
language wants*. [ideas.md](ideas.md) had predicted, in writing and before the
first line, that an editor would want **the size of the terminal** and find
nothing to ask.

It wanted four things, and the prediction named one of them:

- **[6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done),
  `system:terminalSize`** — predicted, and found in the first hour.
- **[6.35](COMPLETED.md#635-a-read-that-gives-up--done), `system:keyWaiting`** —
  the oldest known gap in the language, written down twice and never fixed
  because nothing had bound the escape key.
- **[6.36](COMPLETED.md#636-readline-and-readkey-did-not-share-an-input-buffer--done)**
  — found by *reading the code beside* 6.35, where a comment claimed a problem
  was handled that never had been.
- **[6.37](COMPLETED.md#637-indexof-cannot-say-where-to-start--done),
  `indexOf(s, #from)`** — wanted by the matcher the editor's search needed, and
  by `expect.sol` independently.

And it gave [3.2](ROADMAP.md#32-no-non-local-return) its first real customer: a
dispatcher that wants to stop a *method* rather than a loop, which is what that
entry is actually about and what neither library citing it had wanted.

### What went wrong inside it

One defect per feature, near enough, and they have one shape between them.

| | |
| --- | --- |
| `visible` | `copyFrom` refuses a start past the end — a screen scrolled right past a short line |
| `clamp` | a cursor may not stand past the last character; **a range end must** |
| `keyWaiting` | a terminal in canonical mode holds what is typed, so a poll between two reads sees nothing |
| the count | cleared *after* an action ran, so `.` replaying `3x` made it `33` |
| `c$` | clamped before the mode changed, so a change ate the space in front of it |

**Three of those five are the same sentence in different clothes** — one piece
of state meaning *where you are* and another meaning *where you may be* — and
each appeared the moment a second customer for that state turned up. Not one of
them was visible when the state was written; every one was obvious the moment it
broke.

---

### Postmortem

1. **The prediction was right and the finding was not what it predicted.**
   *Nothing lets a program ask the terminal its size* was true, and the number
   was always reachable through `stty` — at 7ms an ask, which is a fork per
   keystroke. **The absence was never the finding; the price of the workaround
   was.** A prediction that names the right thing is enough to make the work
   quick even when it is wrong about why the thing matters.

2. **I started with a table of keys and had to throw it away.** The first
   version bound `dd` as a two-key special case beside `gg`, which is what a key
   table does to vi. The notation is `[count] operator [count] motion` and it is
   a *grammar*; the rewrite made `dw`, `3dw`, `d3w`, `y'a`, `2yy` and `3p` one
   mechanism with no cases. **When a program is imitating something well
   designed, find its grammar before writing its table.**

3. **Every fix that worked was "make there be one of something."** One
   `wordForward`, run by both `w` and `dw`. Three methods that change the text,
   so nothing can forget to be undoable. One window over standard input. `.`
   repeating *keys* rather than a description of keys. The alternative — keep
   two things in step — never once turned out to be the right answer. When two
   places must agree, the question is not how to keep them agreeing but why
   there are two.

4. **Roughly three of every four failing checks were the check.** Across two
   hundred or so, the ratio never moved. That is the argument for writing the
   expectation before the code: a wrong expectation costs a minute of reading,
   and a real defect turns up in the same minute. It is also a warning about
   trusting one's own sense of what a command *should* do — vi's rules are
   forty years old and mine were four minutes old.

5. **The tests nearly did not survive.** A hundred and sixty-five sessions lived
   in a scratch directory for four days. Had the editor been called finished one
   commit earlier they would have been deleted with the job, and the record of
   every defect above would have gone with them. **A test harness needs a home
   in the repository on the day it is written, not the day the work ends.**

6. **I recommended a change on the weakest number I had.** `indexOf(s, #from)`
   was worth 4% on the workload that asked for it, where I had said ten. The
   real arguments were that the copy it replaced is *quadratic in the length of
   a line*, and that a second program's code got shorter. I led with a benchmark
   because a benchmark is easy to quote, and the shape of the cost and the
   second customer were both in hand before I said anything.

7. **The measurement that mattered most was the one nobody asked for.** Nothing
   in four days had opened the editor on a file bigger than its own four-line
   sample. Fifty thousand lines: everything interactive instant, and `:%s`
   across the file a **seven-second hang**. A program tested only on the input
   it ships with is untested at the size people have.

8. **The language helped more than it hindered, and the ledger is short.**
   Against: no early return, which cost a flag in the dispatcher. In favour:
   strings that cannot change, which made undo a stack of whole buffers and one
   array copy per keystroke — the design a mutable-string language cannot afford
   and would have replaced with a second implementation of every command. The
   254-frame limit, which this file expected to meet, never bit once.

9. **It stopped finding language gaps three changes before it stopped being
   built.** Marks, undo and `.` each found only the editor's own bugs. That is
   the signal to look for: **when a program starts finding only its own
   defects, it has said what it has to say**, and everything after that is
   craft rather than evidence.

---

## 2026-08-26 (tenth, and the editor is finished) — the rest of the alphabet

`c`, `e`, `f`, `t`, `F`, `T`, `r`, `~`. The last of what somebody who knows vi
reaches for, and all of it fitted into tables that already existed: two motions
in the motion table, four prefixes in the prefix list, one operator in the
operator list, two actions. That was the claim made when the grammar went in —
*adding `e` or `f` later is one line in the motion table and no change anywhere
else* — and it held, which is the only way that claim ever gets checked.

### Two of vi's rules came with `c`

**`cc` empties the lines rather than removing them.** Changing a line and
deleting one are different: the cursor has to have somewhere to type. And **`cw`
is `ce`** — changing a word does not swallow the space after it, where deleting
one does. That is vi's oldest special case, it looks arbitrary written down, and
it is not: what you type next needs somewhere to sit.

### The clamp, a third time

`c$` ate the space in front of the cursor.

The cursor was being clamped to the end of the shortened line *before* the mode
changed to insert — and a cursor may not stand one past the end of a line where
an insert may. **That is the same distinction that let `dw` leave the last
character of a file two days ago**, and the same one that made a range end
different from a cursor position the day before that. Third disguise, same
sentence, and I still did not see it coming.

Something to carry: when one piece of state means *where you are* and another
means *where you may be*, every command that changes the mode is a place they
can disagree. There is no way to make that impossible in this design; the honest
mitigation is that all three were caught by a check written before the code.

### The tests moved into the repository, which is what finished it

A hundred and sixty-five sessions had accumulated over four days in a scratch
directory: keys in, expected file out. On the fifth day they would have been
worth nothing.

[programs/edit/checks.sol](../programs/edit/checks.sol) is those sessions as a
Solum program — write a file, feed the editor keys through a pipe, compare what
was written. It runs in `make test` in under a second, and it is a program
rather than a shell script because that is what this repository writes its tools
in, and because `readKey` reading a pipe exactly as it reads a terminal is what
made the editor testable from its first hour.

**Every defect the four days produced is a line in it**: the clamp that let `dw`
leave the last character, the count cleared after an action rather than before,
`c$` and the space. One defect per feature, every one caught by a check written
before the code, and roughly three of every four failures along the way were the
check rather than the editor. That ratio is the argument for writing the
expectation first — a wrong one costs a minute of reading, and a real defect is
found in the same minute.

### What the editor was for

It found three things the language did not have — the size of the terminal, a
read that gives up, and (by standing next to the second one) two readers that
did not share a buffer. It gave 3.2 its first real customer. It taught
lib/pattern.sol where a library's speed lives, and it produced a primitive on
its last day but one.

And it stopped finding language gaps three changes before it stopped being
built, which is the signal I would look for again: when a program starts finding
only its *own* bugs, it has said what it has to say.

---

## 2026-08-26 (ninth) — a primitive that was worth building for the wrong reason

`indexOf(s, #from)`. I said before building it that it would be worth about ten
per cent on the workload that asked for it. It was worth **four**, which is
noise, and it was still the right thing to build. Both halves of that are worth
writing down.

### What the measurement actually said

| | before | after |
| --- | --- | --- |
| substitution over 50,000 short lines | 2.35 s | 2.25 s |
| one 80,000-character line, common leader, no match | 0.14 s | **0.05 s** |

The first line is the workload that produced the complaint, and on it this
change does nothing. The second is where the copy was never a constant factor:
**copying the tail at every candidate is quadratic in the length of a line**, so
the cost hides completely on lines of forty characters and becomes the whole
cost on lines of eighty thousand. A megabyte on one line — minified JSON,
generated code, a log line nobody wrapped — would have been twenty seconds.

So the case for it was never the number I quoted. It was the *shape* of the
number, and I had that in hand before building it and still led with the wrong
one.

### The better argument was not about speed at all

`programs/expect.sol` walks the *count* markers in a line — the HTML comments
that say what a number in prose is counting. It used to
do that by cutting the line down after each marker and cutting it again to find
the closing `-->`, with arithmetic carried along to translate positions in the
offcut back into positions in the line. It now walks an index over one string:
four lines shorter, one variable fewer, and no copies.

**A primitive that lets a program say what it means removes the bookkeeping that
saying it another way required.** The speed is a side effect; the code that
stops existing is the point. I think that is the better test for whether a
message is missing, and it is not the test I applied when I recommended this
one.

### And the rule that decided it

Two shipped files had written the same workaround. That is the number this
repository has used before — 6.19 and 6.23 were both papercuts two files had
tripped over — and it is a better trigger than a benchmark, because a benchmark
measures the case you thought to measure and two independent workarounds measure
what people actually reach for.

---

## 2026-08-26 (eighth) — the first big file, and where a library's speed lives

The editor has been finished for an hour and had never been opened on anything
bigger than the four-line sample its own tests use. So: fifty thousand lines,
2.3 MB, generated.

Loading it, going to the end, searching, editing, undoing — 0.03 to 0.05
seconds, all of it. Then `:%s/alpha/ALPHA/g` across the whole file: **7.7
seconds.** That is not slow. That is a hang, and it is the sort of thing a
program only tells you when you give it work of the size somebody would actually
have.

### Both faults were the program's, which is worth saying

The instinct after a number like that is to blame the interpreter. It was not
the interpreter.

**The matcher tried a match at every position of every line.** A pattern
starting with a plain literal can only match where that character is — so work
that character out once, when the pattern is compiled, and ask `indexOf` where
the next candidate is. `indexOf` is a primitive: it scans in C.

| | before | after |
| --- | --- | --- |
| `alpha` over 50k lines | 2.45 s | 1.08 s |
| `zeta` over 50k lines | 2.20 s | 0.27 s |

The spread between those two is the interesting part. The win is not the
scanning, it is **the verifying that no longer happens**: `zeta` has few false
candidates and `alpha` has many, and the matcher still has to check each one it
lands on. So the optimisation is worth most exactly where a search is worth
least, which is a pleasing sort of unfairness.

**And the editor walked every line twice** — `countIn` for the report, then
`replaceAllIn` to do the work. That second walk was two seconds of the seven.
The library answers both in one walk now, in a dictionary, the way `capture`
answers `"output"` and `"status"`. I had argued for the count on the grounds
that comparing texts would under-report a substitution that replaces something
with itself; that argument survives, and paying for it twice did not.

**7.7 s to 2.4 s.** Same 32,818 lines changed, all 136 behaviour checks unmoved.

### Where a library's speed lives

This is the number to keep:

    string:indexOf over 50,000 lines          0.007 s
    the same scan written as a Solum loop     0.854 s

**A hundred and twenty times.** Everything a library written in this language
does in a loop over characters is paying that, and the way to be fast is not to
write a tighter loop — it is to find the primitive that already does the walking
and hand the work across the boundary to it. The leader is exactly that trick:
it does not make the matcher faster, it makes the matcher run less often.

I do not think that is special to Solum. It is what every regular expression
engine in a scripting language does — Python's `re` scans in C for a literal
prefix for the same reason — and it is the sort of thing you can only see once
you have measured the two sides of your own boundary.

---

## 2026-08-26 (seventh) — `.` and the bug that only a command running commands could find

The last piece of vi's grammar the editor did not have. Two ways to build it,
and the choice is the whole entry.

### Repeat the keys, or repeat a description of the keys

The tidy-sounding design is to remember **what was done** — an operator, a
motion, a count, the text that was inserted — and do it again from that record.
It is also a second description of every command that can change the text, kept
in step with the first by hand, and exercised only when somebody presses `.`.
Two descriptions of one thing, which is the shape three of the last four
findings in this editor have taken.

So: **repeat the keys**. The dispatcher already turns keys into changes, and
feeding the recorded ones back through it is the same path they took the first
time. `iX` and escape, `3dw`, `o` and two lines of typing, `p` — one mechanism,
no cases. vim does the same thing and I suspect for the same reason.

### The recording rule was already written

What is a change? Undo answered that yesterday: `remember` is called by the
three methods that alter the text, so it is the one place that knows. It sets a
flag on the way past, and the dispatcher — which already knows where a command
begins and ends, because undo needed that too — saves the keys when a command
finishes having set it.

Two things fell out rather than being decided. **`yy` is not repeatable**,
because a yank changes nothing and never reaches `remember`; that is vi's rule
and I did not write it. And **an insert is repeated whole**, because the group
stays open until escape, so the keys recorded run from `i` to escape with the
typed text in the middle.

### The bug

`x3.` deleted the whole line.

`.` is the first thing in this editor that **runs other commands**. The count
was being cleared *after* an action ran rather than before it, which nothing had
ever noticed because no action had ever dispatched a key. So when `.` replayed
its `3`, the count still pending was `3`, and `count * 10 + 3` is 33 — `x33.`
and `x3.` did the same thing, which is what made it obvious.

The fix is three lines: take the count, clear it, then run the action with what
was taken. **An action that runs other commands has to start from a clean state,
and the only way to be sure of that is to leave one behind.**

Worth noticing that this is the same class of bug as the clamp two days ago: one
piece of state serving two readers who disagreed about when it applied. The
editor keeps finding them, and it keeps finding them at the moment a second
customer appears.

### Four of eighteen

Four of the eighteen new checks failed on the first run, and **three were the
check**: `J` here joins without a space where vi inserts one (a real difference,
now written down rather than assumed); `.` after a `:%s` repeats the `x` at the
cursor the substitution left, which is correct and not what I had typed as the
expectation; and one where I doubled a `%` for a `printf` that does not need it.

The fourth was the count. That ratio is now the norm across seven changes, and
the reason it is worth reporting is that it costs nothing: a wrong expectation
takes a minute to read and a real bug is found in the same minute.

---

## 2026-08-26 (sixth, and last) — one window, and the third time the same fix worked

[6.36](ROADMAP.md) was filed an hour ago and is closed. The entry said the fix
was *one buffer both readers take from*, sixty lines, and its own argument. It
was ninety, and the argument turned out to be worth having.

### Where the buffer lives was the only real decision

Standard input is **one file descriptor** however many machines are pointed at
it. A buffer on the VM would divide what the operating system does not, and two
VMs in one process would each read ahead into their own — which is a worse
version of the bug being fixed. So it is a module, `solum/src/stdin.c`, and the
window is the process's.

The one place that touches the per-VM world: `sol_vm_init` forgets whatever is
held. Without it a test that replaces stdin between cases inherits the previous
case's read-ahead, and every test in this suite does exactly that.

### Everything that reads standard input now goes through one door

`system:readLine`, `system:readKey`, `system:keyWaiting` — and **both of Solis'
readers**, which is the part I had not planned. The reference has said since it
was written that *the program and the prompt are reading the same input*, and
behind a pipe that was not quite true: the prompt read a block ahead with
`fgets`, so a script asking for a key got whatever was left of it. It is exact
now. `sol_input_read_line` lost its `FILE *` parameter on the way — it reads
standard input, which is the only argument it was ever given.

**And `keyWaiting` had to learn about the window**, or one buffer would have
been worse than two: it would have answered *nothing is coming* while holding
the byte. That is the shape of thing that makes a good fix into a subtle bug,
and it was in the entry because writing the entry is what found it.

### The third time in three days

`readKey` is four lines now. The termios dance, the `read`, the end-of-input
check — all of it moved into the module, and what is left is *take a byte, or
nil*.

This is the third change running whose fix was **making there be one of
something**:

- one `wordForward`, run by both `w` and `dw`, so a motion and an operator
  cannot disagree about where a word ends;
- three methods that change the text, so a command cannot forget to be undoable;
- one window over standard input, so two readers cannot disagree about what has
  been typed.

Each was found as a *disagreement between two things that should have been one*,
and in each case the fix removed the second one rather than teaching the two to
agree. I do not think that is a coincidence, and it is worth carrying: when two
places have to be kept in step, the question is not *how do we keep them in
step* but *why are there two*.

### A gift nobody asked for

A line may hold a NUL now. `fgets` plus `strlen` ended a line at the first one
and threw the rest of the line away — silently, of course. Taking the line by
length makes `readLine` agree with `readFile`, which has kept NULs since the day
it was written. It was not the point of the change; it fell out of not using
`fgets`, and it is the best thing in it.

### What was left alone, deliberately

Reading ahead still reads ahead: four kilobytes from a pipe or a file. It only
matters when another **process** wants the same input — a program that reads a
line and then hands standard input to a child with `run` may find the child
short of what the window is holding. That was true of stdio's buffer before and
is true of this one now. The difference is that it is this repository's
behaviour to describe rather than the C library's to discover, and it is written
down in the reference beside the guarantee it qualifies.

---

## 2026-08-26 (fifth) — the oldest gap, and the bug that was hiding beside it

`system:keyWaiting(seconds)` — *is there a byte to read, waiting up to that long
for one*. Fifteen lines of `poll`, and the most interesting hour of the five.

### The gap had been written down twice and was still there

[6.10](COMPLETED.md#610-waiting-for-a-single-key--done) closed with a paragraph
headed *what it cannot do*. [examples/keys.sol](../examples/keys.sol) said it
again on the same day, and ended with *"worth knowing before writing anything
that binds the escape key on its own"*. Both were right. Neither mattered,
because nothing in this repository bound the escape key — and a warning nobody
has been annoyed by is a warning that never gets acted on.

The editor bound it to the most frequent action a modal editor has. That is the
whole mechanism by which this got built: **the warning waited for somebody to be
annoyed by it.** Worth remembering the next time an entry closes with a list of
what it cannot do — that list is a queue, and it is sorted by who turns up.

### The interface was the decision, and it was about nil

The obvious shape is `readKey(seconds)`, answering the byte or nil. It has a
collision in it that is easy to miss: **nil already means the end of input**, and
that is how every read loop in this language finishes, the editor's included.
Overload it with *nothing yet* and a program can no longer tell *there is nobody
there* from *they have not typed yet* — the first final, the second normal, and
a loop that confuses them either spins for ever or stops early.

So: a question, answering a boolean, with `readKey` untouched. Two messages with
one meaning each rather than one message with two. And the pair is coherent at
the end of input — `keyWaiting` says true and the `readKey` after it says nil:
*there is something to read, and what is there is the end.*

### The bug that every test in the repository would have missed

Fifteen lines of `poll` went in, the editor used it, and the arrow keys stopped
working.

**A terminal in canonical mode holds what is typed until a newline.** `readKey`
sets non-canonical mode for the length of one read and puts it back — so between
two reads the terminal is canonical again, and a `poll` there is told nothing has
been typed however much has. An arrow's `[` and `B` sit in the driver's line
buffer, invisible.

**All 118 of the editor's checks passed. Every C test passed.** They read through
a pipe, and a pipe has no line discipline — there is no mode for it to be in, so
nothing under a pipe can show this. It was found by driving the editor through a
**pseudo-terminal** and pressing an arrow, which is now how it is tested: the
suite makes its own pty, writes `[B` with no newline, and asks. Remove the
raw-mode dance from the primitive and that one test fails while everything else
in the suite passes.

The lesson is not *test on a terminal*. It is that **the thing a pipe cannot
have is the thing a pipe cannot test**, and every interactive feature here has
been tested through one since `readKey` landed. That is a class of blind spot,
not an incident.

### And the bug hiding next to it

While reading `readKey` to copy its termios dance, its comment said buffered
input from `readLine` was *"kept from disagreeing by flushing what stdio holds
before going underneath it."*

There is no flush. There cannot portably be one — `fflush` on an input stream is
undefined in C. `readLine` reads a block ahead through stdio and `readKey` reads
the descriptor, so this loses "XY" and says nothing:

```text
printf 'one\nXY\n' | solvm program.sob     # readLine → "one";  readKey → nil
```

It is [6.36](ROADMAP.md#636-readline-and-readkey-do-not-share-an-input-buffer)
now, the only open entry on the roadmap, with a test pinning the loss so that
fixing it is a decision rather than an accident. The fix — one buffer both
readers take from — is sixty lines and its own argument, and it landed on the
same day as the message that made it visible. One at a time.

**It is the first entry that arrived from reading rather than from wanting.**
Every other one on that list came from somebody wanting something and not
getting it. This came from somebody being told, by a comment, that they already
had it — which is the failure mode of a repository that writes its reasoning
down: the prose is load-bearing, and a sentence that describes an intention as
though it were the behaviour is worse than no sentence at all.

---

## 2026-08-26 (the same morning, still) — undo, and what an unchangeable string is worth

Four entries dated today, and it is not yet seven in the morning. This one is
`u`, and it took less time than any of the three before it for a reason worth
writing down.

### The design was decided by a property of the language

A change is remembered by **keeping the whole buffer**. Written down like that
it sounds extravagant — ten thousand lines copied because somebody pressed `x` —
and it is not, because a line here is a **string** and a string cannot be
changed. A copy of the array of lines shares every line with the buffer it came
from: one pointer per line, and the text is never touched.

Measured, because that is exactly the kind of claim that gets believed and is
wrong:

| buffer | a snapshot |
| --- | --- |
| 10,000 lines × 10 characters | 0.095 ms |
| 10,000 lines × 1,000 characters | 0.078 ms |

One measurement twice. A hundred times the text costs nothing, which is what
sharing looks like from outside — and 0.09ms per keystroke on a ten-thousand-line
file is a number nobody will ever notice.

**The alternative would have been a list of inverse operations** — *this delete
took these three lines from line 40*, and undo puts them back. That is the
design a language with mutable strings pushes you towards, and it is a second
implementation of every command: one to do it, one to undo it, with the second
one exercised only after something has already gone wrong. Twice the commands
and half the testing. Here it buys nothing, and the reason it buys nothing is a
language decision made long before there was an editor.

The price is stated rather than hidden: a hundred states of a ten-thousand-line
file runs under `--memory=16M` and not under 15M. Sixteen bytes a line a state.

### Two things that make it hard to get wrong

**Every change to the text goes through three methods** — `setLineAt`,
`insertLine`, `removeLine` — and those three are the only callers of `remember`.
A command that forgot to be undoable would have to change the text without
changing a line. That is the same instinct as yesterday's *one `wordForward`, run
by both `w` and `dw`*: the way to stop two things disagreeing is to have one of
them.

**Where a change begins and ends is the dispatcher's business, not the
commands'.** A key arriving in normal mode closes the group; the next thing that
touches the text opens a new one; insert mode does not close it. So one
keystroke is one undo, and everything typed between `i` and escape is one undo,
and no command had to be told either.

### The boring result

Twenty-two checks, and every one of them passed the first time — the first
change in four that surprised me at all. Three days of this editor have produced
one bug per feature, each in the place where two ideas met (a cursor and a
range; a claim and the file it described). This one has no such place: the state
is copied whole and put back whole, and there is nothing for two ideas to
disagree about.

That is worth noticing rather than celebrating. **An architecture that cannot go
wrong in an interesting way is the one to prefer**, and the way to recognise it
in advance is that it has fewer joints — not that it is cleverer.

---

## 2026-08-26 (last thing) — the editor stops imitating vi and starts implementing it

Asked for: marks, `y`, `d`, `p`, and a leading number. Those five are not five
features. They are one grammar, and the editor did not have it — it had a
dictionary of keys, each doing its own thing, with `dd` as a two-key special
case bolted on beside `gg`.

    [count] operator [count] motion

Any of the three may be absent. With no operator the motion moves; with no count
it happens once; an operator standing where its own motion would go means whole
lines, which is what `dd` and `yy` are. **A table of keys needs a row per
pair** — `dw`, `dj`, `d$`, `dG`, `2dd`, `y'a` — and the table is the wrong
shape for the language it is trying to speak.

So the key handling was rewritten: two dictionaries and one dispatcher. A
**motion** answers a *place* and moves nothing; an **action** does something;
the dispatcher works out which a key is and whether an operator is waiting for a
place to work over. Everything asked for fell out of that, and so did `d2w`,
`2d3w`, `dG`, `10G` and `3p`, none of which was written down anywhere.

### The trick that kept it short

**The motions are the ones the cursor already used.** An operator runs
`wordForward` and puts the cursor back afterwards — that is the whole of
`placeAfter` — so `dw` and `w` cannot disagree about where a word ends, because
there is one `wordForward` and it is the same code both times.

That is also where the one bug of the rewrite lived, and it is a good one: **a
cursor may not stand past the last character of a line, and a range end must be
able to.** `dw` on the last word of a file left the last character behind,
because the motion clamped itself to a place a *cursor* may occupy. One function
was serving two different notions of "where you are allowed to be" and had never
been asked to tell them apart, because until today nothing measured a range.

### Three booleans that are most of vi

A place carries how it should be read. `linewise`: `dj` is two whole lines, not
the tail of one and the head of another. `inclusive`: `d$` takes the last
character and `dw` does not take the first character of the next word. `home`:
`G` and `'a` land on the first non-blank rather than keeping the column.

And one rule copied from the real thing rather than invented: **an exclusive
motion that ends in the first column ends at the end of the line before
instead.** Without it, `dw` on the last word of a line drags the next line up
into it — which is a thing vi has never done and which nobody would think to
test for. It is four lines and it is the difference between an editor that
behaves and one that surprises you twice a day.

### Marks move, or they lie

A mark is a row and a column. The row has to move when the text does: a mark
below the line you delete comes up with it, and a mark **on** the line you
delete is dropped rather than left pointing at whatever slid into its place.
`insertLine` and `removeLine` are the only two places lines shift, so both call
`shiftMarks` and that is the whole mechanism. The version without it is not
broken in any way you would notice for an hour, which is exactly why it was
worth doing on the first day rather than the second.

`''` — where you last jumped from — is the mark nobody has to remember to set,
and it is one line in `G`, `gg` and the mark jumps.

### 3.2 got its first real customer

[3.2, no non-local return](ROADMAP.md#32-no-non-local-return) has been carrying
a note that two shipped libraries cite it and **neither wanted what it offers**:
both wanted to stop a `whileTrue`, which is the smaller
[3.13](ROADMAP.md#313-a-loop-is-left-by-its-condition-or-by-failing).

The dispatcher wants the entry itself. `dd` having been handled, nothing after
it in the method applies — it wants to *leave the method*, and a block answers
its last expression, so it carries a `done` flag and wraps everything after the
first branch in `done:ifFalse({ ... })`. This is the local case rather than the
non-local one, and the shape is worth naming because every dispatch table has
it: a chain of *this key, else that key*, growing one nesting level per branch.

### And the checks were wrong four times again

Four of the forty-three new cases failed on the first run; **three of them were
the check and not the editor.** `y$` yanks to the end of the line and not the
word under the cursor. A mark on a deleted line leaves the cursor where it was,
so the `x` after it lands somewhere the expectation had not thought about. And
twice I typed a key sequence into the harness that was not the one I meant —
including one with a space in it, and a space is a motion.

The fourth was the clamp. That ratio is the argument for writing the expectation
down first: three of the four failures cost nothing but a re-read, and the
fourth was a real defect found in the same minute.

---

## 2026-08-26 (later) — substitution, and a sentence that was wrong the day it was written

The search went in, and the next thing anybody wants after finding something is
changing it. Asked for as `/find/replace/`; built as `:s/find/replace/`, and the
reason is worth the paragraph.

### Why not the syntax that was asked for

`/src/lib` is a perfectly good search for a pattern with a slash in it, and the
editor has to be able to run it. A bare `/a/b/` is the same keystrokes, so
accepting it means deciding that a search containing a delimiter is *silently* a
substitution instead — the failure being that the file changes when you meant to
look at it. vi put substitution on the colon line for that reason, forty years
before this, and the delimiter is free there because `s` says what follows it:
`:s#/usr/bin#/usr/local/bin#` needs no escaping at all.

So: `:s/a/b/`, `:s/a/b/g` for the line, `:%s/a/b/g` for the file, `&` in a
replacement standing for what was matched.

### The sentence

Yesterday's commit wrote, in the editor's own file and again on
[the programs page](programs.md), that substitution was missing because *the
library answers only where a match begins, which is the one place it was left
deliberately short*.

That was false when it was written. `endOfMatchAt` — *where a match beginning at
`at` ends* — has been in [lib/pattern.sol](../lib/pattern.sol) since the hour it
was written, two screens above the sentence saying it was absent, with its own
comment explaining why it was kept separate. Building substitution today needed
**nothing added to the matcher**: `replaceIn` is `findFrom` and `endOfMatchAt`
in a loop.

Nothing caught it, and nothing could have.
[expect.sol](../programs/expect.sol) checks what a line **prints**; there is no
notation for *this file does not contain X*, and a claim about an absence is
exactly the claim that goes stale silently — the thing said to be missing turns
up, or is added, and the sentence stays technically about a version of the file
nobody has any more. It is
[3.16](COMPLETED.md#316-what-the-checker-does-not-check--done)'s subject in a
form that entry did not have: not a claim the checker skipped, but a claim it
has no way to express.

**The cheap lesson**: a sentence that says why something is *not* here should
name the thing it would need, and then somebody rereading it can look. This one
did name it, which is how it was caught within a day — by writing the feature it
said was impossible and finding the message already there.

### Two smaller things

**The colon line had to be cut in two.** Every other command is a word and an
argument, so `runCommand` split on spaces; `s/a b/c d/` is one word and four
spaces and means nothing under that rule. Substitution is recognised first and
takes the whole line as its own syntax, and the rest is unchanged. Two methods
where there was one, which is the shape the moment two syntaxes share a prompt.

**A zero-width match has exactly one answer that terminates.** `s/x*/-/g` over
`abc` is `-a-b-c-`: the match that consumed nothing carries the character it
stood on across and moves one further. Getting that wrong is an editor that
hangs, and getting it *nearly* right is one that drops a character. It was
written down as a rule before the loop was written, and the loop was right first
time; `sed` agrees, which is the check that mattered.

---

## 2026-08-26 — a search, and a prediction of my own that did not hold

The editor could not find anything, and `/` in a vi-shaped editor does not mean
*substring*, it means *pattern*. So the day was a regular expression engine and
about forty lines of editor on top of it.

### Where it went, and why not into the editor

Into [lib/pattern.sol](../lib/pattern.sol), on the search path, and the argument
is [manifest.sol](../programs/manifest.sol)'s from months back: *a JSON reader is
library code, and the program above it is the thing that finds out whether the
library is any good.* A matcher is the same kind of thing. The editor is now a
customer of it rather than the owner of it, and the parts that turned out to be
interesting are all on the library side.

It includes [scan.sol](../lib/scan.sol) to read the pattern, which makes it the
third library to do that and the first to be written *after* the cursor existed
rather than having written its own first.

### The prediction I made and got wrong

I expected [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) to bite,
and to bite on the **pattern**: the textbook matcher recurses once per pattern
character, and a repository that keeps saying *recursion is about 62 levels here*
suggests `/somewhere in a long sentence` would die on its own length.

Measured, both halves of that are wrong. Each nested call in this matcher is
**one frame**, not the four a method recursing through a chain costs, so the
ceiling is 250 rather than 62 — and the design that walks ordinary items in a
loop never recursed on pattern length in the first place. **250 stars in one
pattern work and 251 does not**, which is not a pattern anybody writes.

What the measurement did find is a different danger, and a much better one. The
textbook `*` recurses over the **text** — *match the rest here, or take one more
character and try again* — and then the depth is the length of the line being
searched. A pattern is something the person types and keeps short; a line is
whatever is in the file. The 2,001-character line I tested on would have wanted
two thousand frames and gets two. **The entry to guard against was never the one
the entry is written about**, and the only way to find that out was to write the
thing and count.

### Two smaller things

**A Solum library cannot answer one message at two arities.** A dictionary has
`at(key)` and `at(key, default)`; `find(text)` and `findFrom(text, at)` are two
names for one idea because a block has one parameter list and a slot holds one
block. Primitives get the overload, Solum does not. Not a limitation worth an
entry — the two names read fine, and any single-arity language has this — but it
is the first time the difference between what a primitive may do and what a
library may do has shown up in an interface rather than in performance.

**The cheatsheet's library table was missing `scan.sol`.** It has been shipped
since 0.30.0, and the one-page index of the whole language never listed it. Two
files went in today: the missing one and the new one.

### The checks that failed were the checks

Three of the fifteen editor search cases failed on the first run and all three
were my expectations rather than the editor: `/b*e` matches "beta" at the **first**
character and not the second, because a star that can match nothing still leaves
the match starting where the pattern started; and `findLast(text, #2)` on a
match at position 1 answers 1, which is what *before position two* means. Writing
the expectation down first is what turned all three into thirty seconds of
reading rather than a debugging session, and it is the second day running that
the thing written before the work was the thing that made the work quick.

---

## 2026-08-25 (later still) — an editor, and a prediction that held

Ten directions went into [ideas.md](ideas.md) an hour before this, four of them
programs with a **prediction written above each** — what it would find, recorded
before it was written, so that *it found nothing* would stay an available answer.
This is the first of the four taken, and it is the one whose prediction was about
an absence already confirmed rather than guessed at: **an editor will want the
terminal's size and find nothing to ask.**

It did, in its first hour. But the finding that came out of writing it is not the
one that went in, and the difference is the whole value of having written the
program rather than reasoning about it.

### The program first, with the workaround in it

[programs/edit.sol](../programs/edit.sol) is a modal editor in the manner of vi:
`h j k l` and the arrows, `w` and `b`, `0` and `$`, `gg` and `G`, `i a I A o O`,
`x`, `dd`, `J`, and a colon line with `:w`, `:q`, `:q!`, `:wq` and a bare number.
664 lines. It is the twelfth program here and **the first that draws** — every
other one writes a line and reads a line.

The first version measured the screen the only way there was: `stty size` through
a shell, parsed out of `capture`. That was deliberate. Writing the program around
the absence is what put a number on it, and the number is what turned a
missing feature into an entry:

| asked | each ask |
| --- | --- |
| `stty size` through `/bin/sh` | 7.0 ms |
| `stty size` with no shell | 2.3 ms |
| `system:environment`, which cannot answer it at all | 0.0002 ms |
| the ioctl, once it existed | about 0.001 ms |

**7ms is a fork, an exec and a pipe per keystroke** for an editor that measures
every time it draws. So the first version measured once at startup, and any
window resized after that was drawn wrong until the editor was restarted. That is
the real finding: not *the size cannot be reached* — it always could — but *the
price of reaching it decides the design of the program around it*.

`COLUMNS` and `LINES` are shell locals and are not exported, so the environment
answers nothing. `tput lines` is worse than useless: down a pipe it answers the
terminfo default, confidently and wrongly, which is a wrong number wearing the
clothes of a right one.

### The message, and the four small decisions in it

[6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done) was
raised and closed the same day, because it was work rather than a decision.
`system:terminalSize` answers a dictionary of `"rows"` and `"columns"`, or nil.

- **One message for both numbers.** Two asks can straddle a resize and compose a
  screen that never existed — an old width with a new height.
- **A dictionary**, the way `capture` answers `"output"` and `"status"`. An array
  would be two integers in an order the reader has to remember, and rows and
  columns are precisely the pair everybody remembers backwards.
- **Nil rather than 24 by 80.** A default is a lie a program cannot see through,
  and what to do without a screen belongs to the program. The editor picks 24 by
  80 *in its own file*, where a reader can see the choice being made.
- **The output's size, not the input's**, because that is where the drawing goes.
  It is also what makes a full-screen program testable: standard input can be a
  script while standard output is a real terminal.

And the one it deliberately does not do: **there is no notification that the size
changed.** A resize is `SIGWINCH` and this language has no signals. It does not
need them at a microsecond an ask — the editor measures at the top of every
frame, so a resize is wrong for one frame instead of until a restart. **The cheap
ask is what makes the missing signal not matter**, and at 7ms that sentence would
have been false and the entry would have had to answer a much larger question.

### What the editor confirmed, having been the first to bind the key

[examples/keys.sol](../examples/keys.sol) has said since it was written that a
byte-level reader **cannot tell the escape key from the start of an escape
sequence**, and it could only ever say that in the abstract: nothing had bound
the escape key to anything. A modal editor binds it to the most frequent action
there is.

What it costs, exactly: press escape in insert mode and nothing happens. Press
the *next* key and both happen at once — the escape leaves insert mode, and the
byte after it is acted on as a normal-mode command. The editor keeps that byte
rather than dropping it, which is one line more than the example does and the
difference between a lost keystroke and a late one. Nothing is misread. The
screen simply waits, and no amount of care in this program can make it not wait.

Three smaller things, none of them filed:

- **An array cannot have an element put into the middle or taken out of it**, so
  `o` and `dd` rebuild the array around the change. One pass per line inserted,
  which for a file a person is typing into is nothing.
- **`system:write` flushes**, so one call is one frame — the language already
  right about something the program would otherwise have had to work around.
- **A tab is one byte and eight columns**, and everything that positions a cursor
  holds both numbers at once. Not the language's doing; where most of the
  arithmetic in the file went.

### Two things about testing a program that draws

**The GC root is load-bearing, and was proved so rather than assumed.** The
message allocates three things — a dictionary and two key strings — and the
dictionary is live while the strings allocate. Removing its temp root and
running the new stress case under ASan reports a heap-use-after-free inside
`sol_dict_put`. Put back, silent. That check has never once been skipped here and
has never once been wasted.

**The suite makes its own terminal.** `posix_openpt`, `grantpt`, `unlockpt`, a
`TIOCSWINSZ` of a size the test chose, and `dup2` over standard output for the
length of one run — so *there is a screen and it is 31 by 101* is arranged rather
than inherited. `openpty` would have been three lines shorter and wants `-lutil`
on Linux, which the front page's *no dependencies beyond a C11 compiler and make*
does not allow. A real terminal is never 31 by 101, which is the point.

The editor itself is held to a **recorded transcript**, the way `basic` is: a
scripted stream of keys and every byte that reached the terminal. That is
deterministic only because standard output is a pipe there, `terminalSize`
answers nil, and the editor's own fallback decides — the fallback earning its
keep as a test fixture as well as an honesty measure.

**The first session recorded was too tidy to catch a crash.** Twenty-two
behaviour checks and a transcript, all on lines of a dozen characters, and none
of them ever scrolled the screen sideways. Pressing `$` on a long line with a
short one under it took the editor down: a line that ends *before* the scrolled
screen begins asks `copyFrom` for a start past the end of a string, and that is
an error rather than an empty answer — where a start past the *end* argument,
which is the case the short lines exercised, answers `""` quite happily. The
session has a tab-indented line running past the eightieth column in it now, so
the recorded screen covers both of the things a screen does to a line it cannot
show as it is.

**And the transcript found something the moment it was recorded.** It differed
from the run inside `make test` by exactly **eight bytes**, because the test
writes into `build/tests/cli` and the recording had been made in `build/tests` —
four characters, in the two lines that are *not* padded to the width of the
screen. Everything else in a frame is padded or truncated to the terminal's
width and is therefore insensitive to what it says; the message line is not. A
recorded screen is a test of where the test puts its files as much as of what the
program draws, which is worth knowing before the next program that draws.

---

## 2026-08-25 (last thing) — a question answered no, which found two bugs anyway

0.34.0 went out, and then the day ended on three questions and no new capability.
Two of them were answered *no*, and one of those two was the most productive
thing in the hour.

### The release, and a tag in the wrong place

Cutting it found the three unreleased changelog entries in **oldest-first order**
in a file that is newest-first everywhere else. Each had been inserted directly
above the previous version heading rather than at the top, so each new entry
landed *below* the one before it. Three entries is small; the habit is not, and
it would have gone on doing that for ever.

Then the journal was asked for before the tag, which is the right order and left
`v0.34.0` pointing at the journal commit rather than at the one titled
*Release 0.34.0*. The content is right — the tarball contains the entry
describing the release — and the tag no longer sits on the commit named for it.
Not worth re-tagging, worth writing down.

### Octal: no, and here is what asking found

*"Perhaps we need a prefix for octal codes too? Or maybe it's too rarely used."*

The second half was right, and the reasoning matters more than the answer. `$`
and `%` went in because there was a **documented gap with a program behind it**:
`asBase` could print hex and binary and nothing could read one back. That gap is
closed. Octal's remaining case is Unix file modes, this repository has exactly
one site that writes one, and it is an example rather than a program. Binary
covers it and covers it better — `%111101101` shows *why* 755 means what it
does, where `&755` only repeats what you already knew.

The counter-argument deserved a fair hearing: 2, 8 and 16 are a conventional
trio, and 3.14's lesson was that half-sets invite the rest one at a time. It does
not hold, and the difference is worth keeping: **3.14's extra messages were
justified by correctness** — a hand-written `asin` is wrong near ±1 — and there
is no correctness argument here. `#493` is exactly right, only unreadable.

**But going to look found two things stale.** `examples/files.sol` still said
*"There is no octal literal in this language — an integer is written #493"*,
which is a sentence describing precisely the gap `%` had closed the day before.
`examples/numbers.sol` reached for `"111":asInteger(#8)` in a comment where
`%111` now does. The commit that added the literals had updated the reference's
file-mode passage and missed the two examples saying the same thing.

### A trigger, measured rather than remembered

Asked what was next, the useful move was to check the one deferred idea with a
**measurable** trigger: splitting the reference, which fires *when the message
reference is longer than everything above it*.

```text
above the message reference   2,220 lines   (was ~1,910)
the message reference         1,026 lines   (was ~700)
```

Both halves grew and the ratio barely moved. Not fired — and now checked against
a number instead of a feeling, which is the whole reason that entry chose a
measurable trigger over a judgement.

### And a scope, for the shape nothing has taken

Every program here reads input, does its job and forgets. `changed.sol` would
report what has been added, removed or modified in a directory **since the last
time it was run** — the purest form of state outliving a process, since a run
with no memory cannot answer the question at all.

The prediction on the record before any of it is written: **the file API is
whole-file only** — no handles, no seek, no partial read — so a store is read
with `readFile`, all of it or none. And a positive prediction too:
`makeDirectory` answers true if it made one and false if a directory was there,
which is a test-and-set, and is the only atomic lock the language has.

---

### Postmortem

1. **A change landed in three places out of five.** The literals commit updated
   the reference where it described the gap and missed two examples describing
   the same gap in the same words. What would have caught it is a grep for the
   *claim* — "no octal literal" — rather than for the feature. I searched for
   where the feature would be used and not for where its absence was written
   down.

2. **The answer was no and the work was real**, which is worth noting because
   the temptation with a proposal is to treat building it as the productive
   outcome. Going to look at whether octal was wanted is what found the stale
   passages; agreeing and adding `&` would have shipped a third prefix and left
   both sentences wrong.

3. **Inserting above the wrong anchor built a habit**, not a mistake. Each
   changelog entry went above `## 0.33.0` because that was the nearest landmark,
   and each was individually reasonable. The file's ordering is a property of
   the whole, and no single edit was in a position to notice.

---

## 2026-08-25 (evening) — a suite written by strangers, and a number that left

0.33.0 shipped at 15:52. What followed was the only hour of the day that
produced no new capability and changed my mind about more than any of the
others: someone else's tests were run against a program I had called finished.

### A number that could not be checked, and so went

3.13 counted the loops in this repository that carry a boolean whose only job is
to stop them. Nine, it said, in four places — the entry, its own decision table,
`ideas.md` twice — and it had been nine when it was written and was not any more.
`basic.sol` alone had added two.

Two numbers earlier the same day had gone the other way: `index.md` said nine
programs and the README said 123 messages, and both got **markers**, because the
checker can recount them from the running machine. This one cannot. *A loop
carrying a flag* is a property of source text, not of the machine, and a grep
cannot tell one from an ordinary counted loop — my first attempt at recounting
returned **sixty**, which is how I know rather than assume.

So it was deleted. The entry names the files the shape appears in and says
outright that the count is gone on purpose, so its absence reads as a decision
rather than an oversight. The argument never rested on the number: it rests on
the shape recurring, which it does, and on almost none of those files saying
anything about it, since a complaint is somebody noticing and silence is an
idiom.

**The rule that fell out of it** is worth keeping, because three unchecked
numbers in one day got three different answers: *a number that cannot be checked
and does not carry the argument is better deleted than corrected.*

### Then the suite

I had said, twice and without being asked, that every test of `basic.sol` was one
I wrote — that they check the interpreter does what I *read* ECMA-55 to say
rather than what it says, and that the NBS conformance suite was the only
instrument that would settle it. Asked to do it, the first honest step was to
find out whether the suite could be had at all, because reproducing it from
memory would have been fabricating a standards document and worse than useless.

It exists: 208 programs written at the National Bureau of Standards in 1980,
public domain, typed back in by somebody who kept them. Running all 208 took
about three minutes.

**Sixteen disagreements, and every one was mine.**

```text
DATA is raw text          an unquoted datum runs to the next comma and may
                          hold anything but one. Reading it with the tokeniser
                          refused a fifth of the suite.
a datum has no type       until a READ takes it. I decided at DATA time, which
                          is exactly backwards.
DEF needs no parameter    DEF FNM=123, referenced as a bare FNM.
NEXT searches the stack   a listing may GOTO out of an inner loop.
FOR always pushes         two loops may run on one variable through GOSUB.
DIM is a declaration      the suite references arrays before dimensioning them.
exceptions that continue  TAB(0) uses 1, carries on, and must say so.
```

Sixteen became five, and the five want a person at a keyboard the harness cannot
offer.

### The one that was mine in a different way

`FOR always pushes`. The rule I had written was that reaching a `FOR` whose
control variable is already looping abandons the old frame — and I had written a
comment justifying it, about a listing that jumps back into its own loop and
would otherwise grow the stack for ever.

That listing is one **the standard already forbids**. The rule was a repair for a
problem nobody has, and it broke three programs the standard allows: an outer
`FOR I1` calling a subroutine that runs its own `FOR I1` is *dynamic* nesting
through `GOSUB`, and one of the suite's tests is named for it.

I invented a rule, documented it convincingly, and it was wrong in exactly the
direction inventing rules is wrong.

### And two literals, which were asked for rather than found

`$FF08` and `%10101100`. Sugar: one case in the scanner, one branch in the
compiler, no opcode and no message. The gap turned out to be written down
already — the reference's own page on file modes said *"Solum has no octal
literal"* and then showed the round trip through `asBase` as the way round it, a
language that could print hex and binary and could not read one back.

Two things were refused on purpose. No `#` in front, because that tag exists to
say which of two readings `45` has and `$FF` has one. No sign, because these are
for looking at bits and the language already declines to reach a negative that
way.

And one guard earned itself twice over: a digit the base does not use ends the
literal with an error rather than starting the next token. Without it `%1012` is
the binary `%101` followed by the float `2` — two good tokens, a wrong reading,
no complaint. `$FF.5` needed the same treatment and I only noticed because I
tried it: it compiled, ran, printed `5` and said nothing.

---

### Postmortem

1. **I called it finished, and it was eleven kinds of wrong.** Not carelessly —
   `basic.sol` carries eighty-three claims, four recorded transcripts and a
   dozen C assertions, and I had gone back over it once already when asked
   directly. None of that caught any of the seven. Tests written by the author
   of a thing check what the author thought to check, and there is no amount of
   care that converts one into the other.

2. **The rule I invented was the worst finding, and it read the best.** It had a
   justification, a named failure mode, and a comment explaining the trade. All
   of that was reasoning about a case the standard had already ruled out, and
   none of it was reading the standard. A confident comment is not evidence.

3. **Getting the suite was the part that could have gone wrong silently.** The
   temptation was to write "NBS-style" tests from memory of what Minimal BASIC
   requires. They would have passed, they would have looked like validation, and
   they would have been the same author checking the same assumptions with a
   more official-sounding name on them.

4. **I read the index instead of the programs, and nearly reported two things
   wrongly.** The suite's own summary labels P054 and P008 as ERROR and
   EXCEPTION tests, which made them look like failures to fix. Their text says
   otherwise: P054 passes if a processor documents what it does, and P008 wants
   a message *and* a substituted value. A one-line label is not the test.

---

## 2026-08-25 (late) — the third entry closed, and the prompt BASIC always had

0.32.0 shipped at 13:18 with one entry open. It was shut by 14:51, and the rest
of the day was giving BASIC the interface it actually had in 1964.

### system:writeError, and the thing the question was not about

[3.19](COMPLETED.md#319-a-program-cannot-write-to-standard-error--done) posed
itself as a naming question — its own message, or a destination argument on
`write`. That part was easy: a destination would make the common case carry an
argument it never wants, and two names read as the two streams a process has.

**The part that mattered was the one nobody asked.** What must *not* happen is a
second `display`. That message and `print` are about rendering a value and they
serve every type; a variant of each pointing elsewhere is precisely the second
mechanism behind the first that this language exists to refuse. There is one way
to reach standard error and it is spelled as writing, not as displaying.

It also fixed a bug I had not been looking for.
[examples/reading.sol](../examples/reading.sol) had been putting its *nothing on
standard input* complaint on standard output for as long as it has existed,
mixed in with the numbered lines that are its actual result. Nobody had noticed
because until that afternoon there was nowhere else to put it.

**And one test failed in a way that was the entry in miniature.** It compared
the merged streams with `2>&1` and broke the moment they were separated — both
because the two now carry different things, and because merging them puts them
in the wrong order, stdout being block-buffered down a pipe where stderr is not.
The test had been passing for an hour by asserting the thing the entry existed
to stop.

### The prompt

A line beginning with a number goes into the program; a line that does not
happens now. That is the whole rule, and it is why the language looks the way it
does — line numbers are not decoration on a file, they are how you say *where
this goes* to a machine with no editor.

**Two things had to come apart.** The four load-time passes need the whole
program, because a `GOTO` cannot be resolved until every line exists, and a file
supplies that at once. A prompt does not: `10 GOTO 100` before line 100 exists is
an ordinary thing to type. So entering a line now only parses it — which catches
a syntax error where it was typed, as BASIC does — and `RUN` links.

That is the cost of yesterday's optimisation arriving where it was always going
to. **The thing that makes a jump an array index is the thing that makes an edit
invalidate one.**

### The frame that LIST cost

`LIST` has to show back what was typed, and the parser had been throwing the text
away. Keeping it put one more call between reading a line and parsing it, which
stands on the stack while the expression parser recurses beneath — and the
deepest listing this reads went from **60 brackets to 59**.

I would have shipped that without noticing. What caught it is that the number is
a *running claim* in the file rather than a sentence about it: the demonstration
at the bottom runs `deep:value(#60)` and prints what happens, so it stopped
printing ` 3` and started printing `call depth exceeded`. A comment saying "it
reaches 60" would have stayed true-looking for ever.

### Four mistakes, one shape

Driving the prompt by hand found that every error it reported carried a line
number, and the number was whatever line had run last:

```text
LOAD "missing.bas"  ->  line 99: there is no file missing.bas
```

Line 99 had nothing to do with it. That is the fourth of these in two days, and
they are all the same shape — a value that was correct where it was set and
meaningless where it was read.

---

### Postmortem

1. **The same anchor mistake twice in one day.** Moving an entry to
   `COMPLETED.md` changes its heading, and I wrote links pointing at the new file
   with the *old* anchor — before the move, so my repointing pass did not see
   them. Once for 3.18 and once for 3.19, two hours apart. The link checker
   caught both, which is the system working; needing it twice for one lesson is
   not.

2. **Four "true sentences about the wrong thing" in two days.**
   `'floor' is out of integer range` from taking a logarithm of infinity;
   `SIN is not an array` from a name falling down the wrong branch of a fork;
   `line 0:` for a line with no number; and now `line 99:` for a file that does
   not exist. Every one is a value read in a context that was not the one it was
   set in. They are not typos and they are not carelessness in the message — they
   are the message being *given* something stale, which means the fix is never in
   the wording.

3. **I dated two changelog entries a day forward.** Writing them late in a long
   session, I assumed the date had rolled; every commit says 2026-08-25. Caught
   only because writing this journal meant reading the commit dates, which is an
   accident rather than a check.

---

## 2026-08-25 (cutting 0.32.0) — three numbers nothing was checking, and a status that lied

Cutting a release here is version, changelog heading, README, `design.md`, tag,
push, tarball. The interesting part was that doing it carefully found three
things wrong, none of which any test could have found.

### Reading the pages a newcomer reads

The version bump takes five minutes. What took the hour was reading
[index.md](../index.md) and the README as though arriving at them.

**index.md said there were nine programs, and listed nine.** There have been ten
since `bench.sol` and eleven since `basic.sol` — wrong for two releases, on the
page that is the front door. It also said *thirty-two files in two directories*,
a sum of two numbers that had both moved.

**The reason is the interesting part: that sentence had no marker.** Every other
count of its kind carries one — the number, then an HTML comment naming what it
counts — and the checker recounts it on every build. This one did not, so nothing ever looked. The fix is
the marker, not the number. The sum is gone rather than corrected, being a third
number no marker can check.

**And the README's own first paragraph said 123 messages**, where there were 135.
That is the number this repository gets wrong most often: the journal three
entries down records it going 125 → 124 → 123 in one evening, by hand, from grep,
twice. The reference's index has been held to the registry by a test all along.
Nothing held the prose to the index.

So `messages` is a marker now too, and the checker computes it rather than
reading it off a page. A name a class holds is a **message** when it is built in
and a **slot** when it has a value, and `slotAt` tells them apart by refusing the
first kind and answering the second — without that, `system:arguments` and
`error:message` count as messages and the total is two too high. Verified by
writing the wrong number down and watching the build fail, which is the only way
to know a check checks anything.

### A question found the third one

*"Can the BASIC load .bas files and run them now?"* — a factual question with a
one-word answer, and demonstrating it rather than asserting it turned up this:

```text
$ solvm basic.sob broken.bas ; echo $?
line 20: there is no line 999
0
```

**A listing that failed exited zero.** A missing file exited 1 correctly; a
broken listing reported its error and then claimed success, so
`solvm basic.sob x.bas && ...` ran the next thing after a program that never
worked. The cause is that one block ran both the demonstrations inside the file
and the listing named on the command line, and swallowing the error is right for
the first and wrong for the second.

Fixing it turned up a second: `PRINT` buffers a line and ends it, so a listing
that failed halfway through one had already produced text that nothing wrote.
The `A` in `10 PRINT "A";` was being dropped silently. Same class of thing —
buffering that is invisible until it is not.

### And then the diagnostic itself was on the wrong stream

Which is [3.19](COMPLETED.md#319-a-program-cannot-write-to-standard-error--done),
raised an hour after the roadmap had emptied. Both workarounds were measured
before the entry was written, because 3.18's whole value was that its workaround
was *worse than the gap*. These are not: `/dev/stderr` is Unix-only and spells
the thing as writing a file, and a shell costs five milliseconds a line to write
a line. Ugly rather than wrong, which makes it a smaller entry, and that
distinction is the entry's most useful sentence.

---

### Postmortem

1. **index.md was wrong for two releases because I never gave it a marker.** Not
   a number I got wrong — a number I never arranged to have checked, in a
   repository whose whole apparatus for this already existed and which I had used
   that same morning on four other sentences. The marker system is only as good
   as the discipline of reaching for it, and I did not.

2. **A direct question found the exit status, and no test would have.** That is
   the third time in two days: *is it done*, *can it load files*, and before
   those the `ifElseIf` question. Every one found something real. The tests here
   check what I thought to check, and a question from outside is the only
   instrument that reaches what I did not.

3. **I described this project's own release process wrongly, from memory.** I
   said the rhythm was *wait for CI green on the tag*; the workflow triggers on
   pushes to `main` and not on tags at all, so pushing the tag fired nothing.
   The substance was fine — the tagged commit was already green — but I stated a
   procedural fact about this repository without checking it, in a session that
   had already caught me doing exactly that about `lib/`.

---

## 2026-08-25 (midday) — finishing it, and being asked whether it was finished

The morning ended with 3.14 decided and eleven messages in the machine. The rest
of the day was the two things that decision unblocked, and then a question that
turned out to be worth more than either.

### system:write, and a question that had a wrong-looking right answer

[3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done)
came down to where the message goes: `system:write`, beside `readLine`, or
`string:write`, beside `display`. The argument that settled it is that `print`,
`display` and `asString` are a trio about **rendering a value** — the literal
form, the text, and the text as a value — and a `write` is not a fourth member
of that. It is about a **destination**, and the destination is where `readLine`
already lives.

**The entry had not thought of the thing that mattered most.** Text with no
newline after it sits in a line-buffered `stdout` until one arrives — which for
a prompt means until after the answer has been read. The primitive has to flush,
and the entry that spent a paragraph on where the message should live said
nothing about that. It was found by running the thing rather than by reasoning
about it.

`INPUT` got more than it asked for: whatever a `PRINT` left open now goes out
without a newline before the `?`, so a prompt the listing wrote and the `?` the
interpreter writes land on one line. Two days of `TWO NUMBERS?` on its own line
became `TWO NUMBERS? 3, 4`.

### The number format, and the oldest trap in it

BASIC shows six significant digits and no nought before the point. Solum prints
the shortest text that reads back as the same double, so `1/3` is
`0.3333333333333333` — right, and not what BASIC shows.

Getting the decimal exponent needed `log`, which had landed three hours earlier.
And it walked straight into the thing every language walks into:
`log(1000000)/log(10)` is **5.999999999999999**, whose floor is 5, which would
print a million with its digits counted from the wrong place. The fix is the one
everybody arrives at — work it out, then look at what you got and correct it —
and it is worth recording that having the primitive did not save me from the
trap the primitive exists to avoid elsewhere.

A million prints as `1E+06`, which looks like a defect and is the standard:
seven digits to the left of the point is more than six significant digits can
describe.

### Transcripts, because comments cannot do this job

`programs/` is not one of the documentation checker's subjects, so every claim in
`basic.sol`'s comments is true because somebody looked. For most programs that is
tolerable. For this one it is not: print zones, six significant digits and the
trailing space after every number are invisible to a reader and all load-bearing.

Four listings in `programs/basic/` have a recorded `.out` beside them now,
compared byte for byte on every build. `wave.bas` is there for a second reason —
3.14 spent its life waiting for *"a plotter, a simulation, anything with
coordinates or a waveform"*, and until that morning this interpreter could not
run one.

### And then: "so the BASIC interpreter is done?"

I had said *finished* twice. Asked directly, I went and looked, and it was not.

**`PRINT 1/0` failed inside the formatter** with `'floor' is out of integer
range` — a true sentence naming a Solum primitive the listing never sent, from
`digits` taking the logarithm of an infinity. The fix is not in the formatter.
Solum reaches `infinity` and `nan` rather than trapping, which is IEEE and right
for Solum; the standard makes both an error a listing is told about. So the check
went where the value is *made*, and division by zero is named separately, because
`0/0` is `nan` and `1/0` is `infinity` and neither message would say what
happened.

**And one deviation from the standard was undocumented**, which is worse than
the deviation. ECMA-55 makes a space insignificant outside a string, so
`FORI=1TO10` and `PRI NT` are legal BASIC and neither runs here. Nothing said
so, while the file said in several places that it implements the standard.

---

### Postmortem

1. **I called it finished twice without checking.** Not a guess that turned out
   wrong — a claim made from the inside, about a program measured against an
   external document, without going back to the document. The two things a
   direct question found had been there for hours.

2. **The undocumented deviation is the worse of the two.** A gap that is written
   down is a known limit; the same gap unwritten, in a file that says four times
   that it follows a standard, is the file being wrong about itself. Everything
   else this program does — refusing to stub `^`, refusing `LOG(0)`, naming the
   dialect in error messages — was about not letting a reader believe something
   untrue, and this was the one place I had let one.

3. **The formatter bug was reachable by the shortest program that could reach
   it.** `PRINT 1/0` is four tokens. It was never tried, because the demos were
   written to show things working, and 83 of them are still not a test suite —
   they are a description of the parts I thought to describe.

4. **Having `log` did not save me from `log`.** Three hours after landing
   trigonometry with a long argument about how hand-written argument reduction
   fails silently, I wrote a decimal exponent by logarithm and had to be caught
   by the same class of error at the same magnitude. The primitive removes the
   hard part; it does not remove the arithmetic around it.

---

## 2026-08-25 (after the release) — a BASIC interpreter, and the two things it asked for

0.31.0 went out at 09:13 with the roadmap empty and a note saying so. By 12:20
there were two entries on it, one of them was closed, and the language had eleven
messages it did not have at breakfast. None of that was planned; all of it came
from writing one program.

### Why BASIC, and why a standard

The ask was an interpreter. The choice that mattered was **ECMA-55 Minimal BASIC
(1978)** rather than a BASIC of my own, and the reason is that a published
standard decides what *finished* means without the author of the interpreter
having a vote. Twenty statements, eleven supplied functions, and no room to
declare victory early.

The scoping found something pleasing before a line was written. Line numbers are
usually a joke, and here they are the whole reason the job fits:
[3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels) caps recursion near
254, and a tree-walking interpreter for a modern language spends frames in
proportion to how deeply its *input* nests — it would run out of machine before
it ran out of program. A line-numbered BASIC never nests. The run loop is a
program counter over a sorted table, `GOSUB` and `FOR` are explicit stacks in
arrays, and the only recursion is an expression parser that runs once at load.

It reads 60 brackets deep, measured rather than asserted, and no BASIC anybody
writes comes near.

### The operator that refused for two days

`^` is in the language and could not be implemented. Solum had no `pow`, and both
ways round it are wrong: repeated multiplication answers integer exponents only,
and `exp(y * log x)` needs two more functions that were also missing. So it
raised, and named the entry.

That was the right call and it was not a comfortable one — a stub that is exact
for `2^3` would have passed every test anybody writes. It is exactly the shape
[3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done) already recorded
twice, in two hand-written square roots that were plausible and silent and wrong.

**The trigger fired by accident, which is what makes it good evidence.** BASIC
was picked for being a different *shape* from the other ten programs, not for
wanting arithmetic. It turned out to want six functions and an operator because
they are on the page of the standard, and — the part that made it a harder case
than the plotter that entry imagined — **there was no version of the program that
wanted less.** A plotter that wanted one angle could have been written to want
none. An interpreter is measured against a document it did not write.

### Being shown a library I had not read

Stage one's dispatch comment said there were two ways to write a statement
dispatch: a dictionary, or a staircase of `ifElse` nineteen levels deep. It was
answered with a question about `ifElseIf` — which is in `lib/control.sol`, in
this repository, with a worked example and its own cost analysis.

I had reached into that same directory for `scan.sol` an hour earlier.

The recovery was better than the miss. That file states its own price — *use it
for a flat dispatch and not inside a recursion* — so both halves got measured
rather than quoted:

```text
plain recursion    251 levels     1 frame per level
one block call     125 levels     2
through ifElseIf    83 levels     3
```

Which settles more than the question asked. **A primitive could remove one of
those two extra frames and no more**, because the action block has to be entered
and that is a frame. The speed floor came out the same way: 0.08s for a chain,
0.49s through `ifElseIf`, and **0.15s for the four block calls alone** — so about
3.3x is available, and 2x the inlined chain is the wall.

The tokeniser took it: flat, not recursive, a third more load time and no depth
at all. `primary` and `evaluate` kept their staircases: 60 brackets against 39.

### And then a hot loop arrived and finished the argument

`control.sol` said a primitive would need *a program running it per iteration of
something*. Stage two grew one that afternoon, because every `IF` in a running
listing goes through one dispatch. I wrote it with `ifElseIf` first:

```text
20,000 iterations, IF and GOTO      0.30s   ifElseIf
                                    0.246s  staircase
```

**Twenty-two per cent of the whole interpreter, for six arms.** It went back to
the staircase.

So both edges of that library's niche are now measured, and the niche is narrow:
out of the recursive dispatches on depth, out of the hot one on speed, and where
a hot dispatch has many arms it wants a dictionary rather than either. That is
the sharpest thing anybody knows about whether the VM should take it over, and it
points both ways — a program reached for it and had to give it up, which is what
happened to the four loops before they were built in; but what it gave it up for
was a six-arm staircase that reads perfectly well.

### The interpreter runs at 420,000 statements a second

Ten times the scope's estimate, and the argument for having parsed once at load
rather than once per pass. Three passes over the listing before anything runs: a
jump becomes an index instead of a search, a jump to a line that does not exist
is reported before the program prints anything, and `FOR` finds its `NEXT`.

**[3.2](ROADMAP.md#32-no-non-local-return) never came up**, which is worth
recording because it sounds like it should have been the whole problem — a
language with no non-local return interpreting one whose defining feature is
`GOTO`. Every jump is an assignment to a counter and a flag saying the counter
already moved. Nothing is unwound because nothing was wound.

### What INPUT found

BASIC prompts with `?` and reads the answer typed beside it. This cannot:
`display` and `print` are the only ways a Solum program has to write, and both
end the line. That is
[3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done).

**The workaround is worse than the gap, and that is the part worth having.**
`system:writeFile("/dev/stdout", "? ")` writes without a newline and looks like
the answer. It opens a second stream on the same file, so when the output is not
a terminal the two buffer differently:

```text
one            what the program printed, in order
two? four? one
three          what came out of a pipe
five
```

Works by hand, silently reorders the transcript the moment anything is
redirected. Same shape as the square roots again: fine under the test anybody
runs, wrong under the conditions nobody thinks to try.

### Eleven, not seven

3.14 was discussed rather than assumed, and the discussion changed the answer.
Seven messages were *wanted*; eleven went in, because `asin`, `acos` and `atan2`
fail the same test `sqrt` failed — written by hand, `asin(x)` is
`atan(x / sqrt(1 - x*x))`, which divides by zero at the ends of its own domain.
`pi` is the one member that fails no test at all and went in anyway, so that a
language with `sin` and `cos` is not one where every program starts by writing
out a constant.

The three questions that entry had parked for weeks took about ten minutes once
there was a program forcing them, and two were settled by BASIC rather than by
taste. `pi` is `float:pi` and not a third global, on the argument `math.sol`
already makes about names a program is entitled to want.

**The size worry turned out to be the small part.** Eleven primitives are eleven
lines of C. The afternoon went into the four things a new message obliges, each
held by a test: an example that sends it with a checked claim, the reference's
type table, the message index, the cheatsheet. That is the right place for an
afternoon to go.

---

### Postmortem

1. **I wrote `^` for a non-local return.** Fifteen compile errors at once, in a
   session where I had read
   [3.2](ROADMAP.md#32-no-non-local-return) and cited it in a comment. Not a
   knowledge gap — a habit from another language firing while I was thinking
   about something else.

2. **I did not read the library I was writing about.** The dispatch comment
   presented a choice between two options when the repository contained a third,
   documented, with measurements. Reaching for `scan.sol` from the same directory
   an hour earlier makes it worse rather than better: I treated `lib/` as a place
   to take one thing from rather than a place with things in it.

3. **I invented a heading convention and nearly shipped it.** Marking 3.14 with
   `— **decision**` matched no entry in the document and would have broken 22
   inbound anchors. My own link check caught it, which is the system working —
   but the check ran because I ran it, after writing the thing it caught.

4. **My scope was wrong about the size of the language it was scoping.**
   "Nineteen keywords" was repeated in four places for two days; there are
   twenty. `OPTION BASE` was found by running out of statements to implement and
   going back to the standard to see what was left, which is not a method.

5. **I was caught by the oldest trap in the language I was implementing.** The
   `ON GOTO` demonstration fell out of its loop and straight into its own
   subroutines, printing `one` a fourth time. Correct BASIC, badly written
   program — and I had to read my own interpreter's output twice before
   believing it was right and the listing was wrong.

6. **`SIN(0)` said "SIN is not an array".** A true sentence about the wrong
   thing: the blocked names were absent from the function table, so they fell
   down the array branch of a fork and were refused for being more than one
   letter long. The kind of message that costs somebody an afternoon in the
   wrong file.

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
