# Journal

*What a day of work on Solveig actually consisted of, newest first.*

The [changelog](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. Neither holds the shape of a
*day* — what was picked up and why, what turned out to be wrong, and the hours
that produced no code because they were spent deciding something or checking
that a document was still true. That is what this is for.

---

## 2026-09-02 (closing) — fifteen commits, two programs, and four checks that had holes

Four entries below this one, and this is the account of the whole day. It ran
from a release cut before breakfast to a heap replacing a linear scan at the
end, and the four entries stay where they are.

### What shipped

| | |
| --- | --- |
| [0.41.0](CHANGELOG.md#0410--2026-09-02) | eighty-one commits and two days of work, tagged and published |
| [diff](../programs/diff.sol) | the twentieth program, and the first that computes rather than recognises |
| [sort](../programs/sort.sol) | the twenty-first, and the first that does not have to hold its input |
| [6.43](ROADMAP.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers-) | a pipe cannot be read whole, and the call that looks as though it can answers `""` |
| [6.44](ROADMAP.md#644-an-instant-cannot-be-written-in-local-time) | an instant cannot be written in local time |
| four rules | in [method.md](method.md), each from something that went wrong here |

The roadmap's open list had been empty for a day and is not any more, which is
the mechanism working rather than an exception to it. Both entries came from
programs, both are about standard input, and neither was predicted by the page
that predicted those programs.

### The day had one lesson and learned it four ways

**Every check here has a shape it cannot see, and the shape is a property of
whoever wrote the check.**

| the check | what it could not see |
| --- | --- |
| an author's corpus | 24 hand-written `diff` cases passed a wrong empty-range rule, and only 7 could have shown it |
| a generator | `sort`'s alphabet had a minus because somebody thought of one and no plus because nobody did |
| every check in the repository | all of them enumerate by extension, so `programs/:=` sat in the tree for two days |
| the checker that reads the file | a link whose text wraps is correct markdown and a published 404 |

**Three of the four were fixed by adding an author rather than by improving a
check.** A generator answered the corpus; real files answered the generator;
`git diff --name-status` against the last tag answered the extension rule. The
fourth was the only one where the existing checker could be taught the fault,
and it was, and it has caught two more since -- both in paragraphs describing
itself.

### And the checks that were slow, silent, or vacuous

Four separate times a check reported nothing and the nothing was wrong.

**A sweep ran for two hours and fourteen minutes** without finishing its first
half and was reported as *still running* three times before anybody asked why.
It was not slow; it was reporting a defect. `sort`'s merge scanned every run's
head, so the cost was `lines x runs`, and forty-nine thousand runs over a
14,707-line file is what that comes to. A heap took it to 3.88 seconds.

**A sweep would have reported success whatever happened**, because its counters
were inside a pipeline's subshell -- with a comment underneath admitting it and
doing nothing about it, in the one file whose whole purpose is to be the check
the corpus is not.

**A fault injection injected nothing**, against a heading `GUIDE.md` does not
have, and the *every claim holds* that came back was about the tree as it
stood. That is the vacuous check, made while demonstrating a check.

**And a finding could not be re-run.** A drifting shrinker produced a pair
where `/usr/bin/diff` appeared to use 232 edits against our 228, which would
have meant the tool was not minimal. 47,991 generated pairs later it was never
above the minimum and the input was gone. *Re-running a wrong experiment is not
evidence* cuts both ways: **a result that cannot be re-run is not one either.**

### Three claims of mine were wrong, and the shape is the same one

- **`sorted`'s stability was going to be reported as undocumented.**
[REFERENCE.md](REFERENCE.md#array) has said it all along, in prose under the
sorting examples. The `grep` found the table row and stopped. - **The `diff`
sweep's *2,400 runs, zero disagreements* was published an hour before any real
file went through it**, and the first pair disagreed. - **The release procedure
said *two fixups* while listing three**, and had for as long as the third
existed.

All three are **an absence asserted from a look that did not cover what it
claimed to**. [design.md](design.md#what-the-language-is-for) rules the
argument from absence out for language features; 2026-09-01 found nothing had
ruled it out for checkers; today found nothing had ruled it out for *documents
about my own work*.

**A fourth was found writing this entry.** Three documents and the program's
own header said *sixteen hand-written cases all agreed with a wrong rule*, and
the corpus had twenty-four -- of which only **seven** could have shown the
fault at all, since it lives in the unified header and the rest never print
one. The number was written from memory of when the cases were added rather
than counted, and the corrected version is the stronger claim: the size of a
corpus was never the point, and the shape of what its author reached for was.

### What the two programs were actually for

**`diff` was predicted to press on the recursion limit, a two-dimensional
array, and quadratic memory. None fired.** What did was the output format,
which the entry named in one sentence and which turned out to be the whole
difficulty. The 3.5 miss is the third of its kind and is a rule now: a
limitation that is written down is known before the implementation is chosen,
so the implementation that meets it is the one nobody writes.

**`sort` was predicted to want a positioned write. It is not there**, and the
reason is worth more than the prediction: an external merge sort writes each
run once and then only reads it, and the output appends. The entry called it
*the mirror of the ranged read* and reasoned from the symmetry of the names. A
write is not the reverse of a read.

**Both predictions were mostly wrong and both programs were worth writing.**
That is the argument for writing the prediction down rather than for making
better ones -- three of the four things `diff` found and both things `sort`
found are on neither list, and none of them would have been noticed by a
program written to confirm a page.

### And the clear-out found three numbers with no apparatus behind them

Asked whether the session could be cleared, the check was *what do the
documents cite that lives only in scratch* -- and three figures did. **44
disagreements in 1,050 runs** and **2,400 runs, zero** are quoted in five
documents and in `diff.sol`; **238 nanoseconds a byte** is quoted twice in
[6.43](ROADMAP.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers-)
and once in `sort.sol`. Every one was measured by a throwaway in a temporary
directory.

[method.md](method.md#and-a-comparison-whose-two-sides-did-not-run-alike-is-not-one-either)
already says it: **a throwaway that measures something the documents will state
is not a throwaway.** `sort`'s sweep was kept because it was written as a
check; `diff`'s was written as a throwaway an hour earlier and its numbers went
into the deliverable anyway. Both are in the tree now, with
`programs/stdin-cost.sh`.

**And keeping the third one found a defect in it.** The minimality mode -- does
the tool ever use more edits than the minimum -- reported **55 pairs of 200**
on its first run, which would have overturned a retraction made this morning.
It was the check: it split a file on newlines and counted the trailing empty
string as a line, so a pair differing only in its final newline came out one
edit cheaper than any diff can manage. Fixed, it reports **0 of 800**, and the
retraction stands.

That is the third time today a check was wrong in the direction of an
interesting finding, and the second time the interesting finding was about the
oracle. **A result that flatters the person holding it is the one to re-run
first.**

### Where it leaves things

Two entries open on the roadmap, both about standard input, and a third
customer for 6.43 measured but not written: `gzip -d`, whose input has no lines
at all -- 264 newline bytes in a 73,572-byte stream, every one of them data.
That is the next program if there is one, and its own prediction is about
something else entirely: the cost of a 32 KB window as 32,768 tagged values,
which is the number the graphics and neural-net directions rest on.

---

## 2026-09-02 (the slow check) — two hours of silence was the finding

`sweep.sh` was left running at full width and reported as *still running* three
times. On the third it had been going **two hours and fourteen minutes** and
had not finished its generated half -- which was the answer rather than the
wait.

### The defect it was reporting by not finishing

`sort`'s k-way merge picked its winner by scanning every run's head, so the
cost was `lines x runs`. The sweep runs `-S 16` over this repository's own
files, and `docs/CHANGELOG.md` is 14,707 lines in 788,815 bytes -- some
forty-nine thousand runs, and a comparison per run per line.

**The scan carried a comment naming the condition that would falsify it**: *a
heap would matter at a few hundred runs*, and *the scan is the trade this
repository keeps making until something measures otherwise*. Something measured
otherwise the same day, and the comment was specific enough to recognise it. A
heap took the file from *did not finish* to **3.88 seconds**, and the whole
sweep from *did not finish* to five and a half minutes.

### The lesson is about the check, not the merge

A heap instead of a scan is an undergraduate correction and would be worth a
line. **What is worth an entry is that the check was working and nobody was
reading it**, because its output was silence, and silence is what a slow check
and a passing check both look like.

[A program that does not stop can still be checked](method.md#a-program-that-does-not-stop-can-still-be-checked--give-it-a-deadline)
already says to give an unbounded program a deadline. This is the same rule
pointed at the *check*, and it is the harder half to remember, because the
check is the thing you trust. The estimate given for this sweep was ten
minutes; the answer was two hours. **A factor of thirteen was news on the first
look and was read as weather on all three.**

And one thing worth keeping on the other side of the ledger: a merge over
forty-nine thousand runs is ordinary at a small budget, and a program holding a
handle per run would have run out of descriptors long before it ran out of
patience. A reader here is a path and an integer, so a large `k` cost only the
scan. **The design that removed the wall is what let the algorithm be the whole
problem.**

---

## 2026-09-02 (sort) — a gap that was not there, and a generator that missed twice

[sort.sol](../programs/sort.sol) is the twenty-first program, chosen off the
Unix survey where its prediction had been written down in August. The
prediction named one finding and the finding is absent.

### A write is not the reverse of a read

The entry said `sort` would want a **positioned write**, because an external
merge sort writes runs to temporary files and `writeFile` replaces where
`appendFile` appends. It called that *the mirror of the ranged read*.

**An external merge sort never writes into the middle of a file.** A run is
produced whole -- read a budget's worth of lines, sort them, write them once --
and then it is only ever read. The output is produced in order, so it appends.
The two writes that exist are the two it needs.

The mirror is where the reasoning went. **The ranged read exists because a
program wants part of a file it did not write**; nothing wants to write part of
a file it is producing, because a producer knows what comes next. The entry
reasoned from the symmetry of the *names*, and the asymmetry is in what the two
operations are for.

And what the k-way merge did want was the ranged read, which was already there:
`k` positions in `k` files at once, with nothing to open, close or use after
closing. **The half the entry worried about is the half that needed nothing.**

### The generator missed both real defects, the same day it missed one for diff

`programs/sort/sweep.sh` runs generated inputs and then this repository's own
files, under twenty-three option forms. It was written **before** any claim was
made about it, which is the whole of what the morning cost `diff` to learn.

Both defects came from the real half. **`-n` must reject a leading `+`** -- the
tool reads `-1` as minus one and `+5` as *zero* -- found on a README line
beginning `+0.2% to +3.4%`. **`-f` folds to upper case, not lower**, which
shows only beside punctuation, found in three README files that begin lines
with `**[`.

**The generated alphabet had a minus in it because somebody thought of one, and
no plus because nobody did.** It had letters and digits and no punctuation
beside them. That is the same shape twice in one day, and it is the argument
for the third rung rather than for a better generator: a generator produces
what its author imagined, one level up. Both are corpus cases now, so the next
reader does not find them twice.

### And the sweep would have reported success either way

Its first draft ran the option forms through `echo "$forms" | while read`,
which puts the loop in a subshell -- so every disagreement it counted was
thrown away when the subshell exited and the script would have printed *nothing
disagreed* whatever happened.

**Worse than that: the first draft had a comment underneath admitting the
counters were lost, and did nothing about it.** The observation was made and
not acted on, in a file whose whole purpose is to be the check the corpus is
not. It is a redirect now, and it was proved by folding down again and watching
it report four.

### The claim that was retracted before it shipped

`array:sorted` is a stable merge sort, and this was going to be the headline --
**stable deliberately, and nothing says so**, an implementation detail and a
promise being the same line of code, which is the shape 6.42 closed for the
bytecode format five days ago.

[REFERENCE.md](REFERENCE.md#array) has said it all along, in prose under the
sorting examples, in almost the words the C comment uses. The paragraph was
written because a `grep` for `sorted` found the table row and the `filesIn`
note and stopped. **An absence asserted from a search that did not cover the
document** -- the argument from absence, for the third time in three days, in a
place nobody had ruled it out.

What is true is smaller and worth keeping: **this is the first program here
that depends on the guarantee.** `-s` is exactly *no last resort, let the sort
keep the order*, and the merge relies on the same promise across runs. Until
now the sentence had no customer.

### Two small things the day also moved

**`oracle.sh` sets `LC_ALL=C` for every tool.** A string here is bytes and
`lessThan` compares them, so a tool run under a collating locale is being asked
a different question -- `apple Apple banana` against `Apple banana apple`. Set
for every tool rather than for `sort`, because the reasoning is about the
language; all five earlier corpora are unmoved.

**And `expect.sol`'s ordinal list ran out.** Its comment says it is *longer
than the list of programs*; it ended at `twentieth` with twenty programs, so
`sort` fired the guard instead of using slack that was not there. The guard
worked, which is the point of it. Five spare now.

---

## 2026-09-02 (diff) — four predictions, one right, and a corpus that agreed with a wrong rule

[diff.sol](../programs/diff.sol) is the twentieth program here and the first
that computes a relationship rather than recognising a structure. Chosen off
[the Unix survey](ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31),
where its prediction had been written down in August.

### The prediction was mostly wrong, and that is the useful half

Four findings named, one held. **3.5 never came near it**: the recursion
belongs to the linear-space variant of Myers, and the greedy forward pass is
two loops. There is **no two-dimensional array**: one array of diagonals and a
ragged trace. The memory is quadratic in the **edits**, not in the files.

**The 3.5 miss is the third of its kind** and that is what makes it worth a
rule rather than a shrug. `basic.sol`, `check_syntax.sol` and `pascal.sol` were
each predicted to hit the recursion limit and each was written in the shape
that avoids it. The prediction is not wrong about the limitation -- it is wrong
about the author. **A limitation that is written down is known before the
implementation is chosen**, so the implementation that meets it is the one
nobody writes, and the prediction is really about which of two algorithms gets
used.
[method.md](method.md#a-predicted-limitation-decides-which-implementation-gets-written)
has it now, with what such a prediction owes: the shape of the program that
would hit it, and whether anybody would write that shape for reasons other than
the prediction.

### The corpus agreed with a wrong rule, and a generator did not

What held was *the output format is the hard part*, and it was the whole
difficulty -- four faults, none findable by reading the algorithm, which was
right on its first run.

**Three came from the corpus. The fourth is the entry.** An empty range in a
unified header is written at the line it follows -- except at the start of a
file that has lines, where it is written at line 1 rather than 0. Sixteen
hand-written cases all agreed with the simple rule, because **every one of them
put its empty range where the simple rule and the real one give the same
answer.** Not one case was wrong; the set was.

A random sweep against the tool -- pairs built from nine possible lines, seven
option forms -- disagreed **44 times in 1,050 runs**. Seven probes afterwards
turned the disagreement into a rule. After the fix: **2,400 runs, six option
forms, files to forty lines, zero disagreements.**

This is
[an author-written corpus tests what its author thought of](method.md#an-author-written-corpus-tests-what-its-author-thought-of)
with a
**generator** as the second author instead of a standard or a stranger. It is
the cheapest second author there is for a tool that already has an oracle:
nothing to find, nothing to read, and it lands on the cases nobody would write
on purpose because it does not know there is a purpose.

### And an hour later the first real file pair disagreed

**The sentence *2,400 runs, zero disagreements* was written an hour before
anything real was put through this.** The first pair — `docs/method.md` at two
revisions, out of this repository's own history — disagreed with the tool.

Both answers are 33 insertions. Where a line inside an inserted block equals
the line at the seam, the insertion can be placed as one run or split around
that line for the same cost; the tool splits and this program does not. On
sixty pairs of real files: **48 byte-identical, 12 not, and all 12 the same
cost.** One pair in five.

**The corpus and the generator were blind in the same direction**, which is the
finding. The sweep was written *because* an author-written corpus tests what
its author thought of — and it mutates one line at a time, where the shape
needed is a **block** inserted whole with a line inside it matching the seam.
That is what editing prose does every time and what nobody constructs on
purpose. It does not reduce either: no window of thirty lines either side
reproduces it, because the tool's algorithm makes a global choice, so it cannot
be a corpus case at all.

[method.md](method.md#an-enumeration-that-looks-complete-is-not-a-proof) had
the shape already, about the four states of a pipe. What is new is that it
happened to the *remedy*: a generator is a second author and it has blind spots
of its own, and the third author has to be data somebody produced for their own
reasons.

So [apply.sh](../programs/diff/apply.sh) asks a different question. It writes
the unified diff, hands it to **`patch(1)`** and compares the result with the
second file — *is this the diff from A to B*, where the oracle asks *is this
the tool's diff*. **60 of 60.** The moment two right answers exist, byte
equality with one of them stops being the check that matters.

**And one reading was retracted on the way.** A shrinker that drifted produced
a pair where the tool appeared to use 232 edits against our 228 -- which would
have meant the tool was not minimal. It did not reproduce: 47,991 generated
pairs later the tool was never above the minimum, and the input that produced
the reading was gone. It is recorded here because the temptation was to keep
the more interesting number, and *re-running a wrong experiment is not
evidence* cuts both ways -- a result that cannot be re-run is not one either.

### And I published six 404s while writing about that exact fault

`site.sh` came back from the deploy with **six `NO BASE`** links, all of them
written in this session. A markdown link whose *text* wraps across a line
publishes as a site-absolute href and 404s: Jekyll rewrites the `.md` target to
`.html` and does not prepend the baseurl. The markdown is correct, and
[method.md](method.md) gained a rule about this class of fault four hours
earlier.

**Nothing local could have caught them**, which is the reason `site.sh` exists
and is also a gap: this half of the fault is visible in the file. `expect.sol`
scans links a line at a time and never asked whether the `[` that opened one
was on the same line as its `](`. It does now — one counter, scoped to `.md`
targets because those are the only ones `jekyll-relative-links` rewrites, which
also disposed of four false positives from `](` inside string literals and
inside this repository's own prose about `](target)`.

**And the first attempt to prove it can fail proved nothing.** The injected
link went in against a heading `GUIDE.md` does not have, so the file was
unchanged and the checker's *every claim holds* was about the tree as it stood
— the vacuous check
[this page already has a rule for](method.md#a-check-that-cannot-fail-is-decoration),
made while demonstrating a check. The second attempt injected against a line that is
there, the checker reported `docs/GUIDE.md:7`, and restoring the file made it
quiet again.

### The oracle turned out to be two things at once

Under `-i`, on input holding **no uppercase at all**, `/usr/bin/diff` picks a
different one of two equally minimal answers than it picks without the flag.
One line `h` against three lines `c h h`: `0a1,2` with the flag, `0a1` and
`1a3` without it, both two insertions. 41 runs in 400 under `-i` and none
without.

**An oracle can be wrong** was already on the page -- it is the argument for
holding `sha256sum` to FIPS 180-4 as well as to the tool. What is new is one
caught being *inconsistent with itself*, where a published standard would have
settled it and there is no standard saying which minimal edit script to print.
So it is pinned as a divergence rather than chased: matching it would mean
reproducing a tie-break the tool does not apply to itself.

### Two entries, both about standard input, neither predicted

[6.43](ROADMAP.md#643-a-program-cannot-read-standard-input-whole-and-the-call-that-looks-as-though-it-can-answers-)
is a want and a defect in one. The want: nothing reads standard input whole.
`readLine` drops the terminator and folds `\r\n`, so it cannot say whether the
last line ended with a newline; `readKey` is exact and is 4.2 MB/s against 84.
The defect: `readFile("/dev/stdin")` works from a redirect and answers `""`
from a pipe -- **neither the contents nor an error**. The size comes from
`fseeko(SEEK_END)`, a pipe refuses the seek, and the initial `0` is
indistinguishable from an empty file. The function already refuses a directory
and already checks a negative size; a failed seek is the case between them that
nothing looks at.

[6.44](ROADMAP.md#644-an-instant-cannot-be-written-in-local-time) is smaller
and is the
[stty](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done)
shape again: a unified header carries a local time, every route out of an
instant here is UTC, and the workaround is a fork of `date +%z` that is **not
even exact** -- the offset is the one in force now, so a file older than the
last clock change prints an hour out.

### And the harness grew two things it should have had

[oracle.sh](../programs/oracle.sh) ran one input because every tool it had been
asked about read one. `diff` takes two, so a case may carry a `first:` section.
And `diff` is the first program here whose **exit status** is documented
behaviour -- 0, 1, 2 -- so the status is compared alongside the bytes now,
**for every program the harness runs**. All four existing corpora still pass
under both changes, which is the only reason to believe the second one is not
just noise waiting to happen.

---

## 2026-09-02 (0.41.0) — a release, and the file no check here could see

Eighty-one commits and two days of work — 2026-08-31 and 2026-09-01 — went out
as 0.41.0. Six roadmap entries, three new messages, a regular expression
engine, the nineteenth program, three checks that nothing had held before, and
a contract for a second producer of `.sob`. [releasing.md](releasing.md) was
followed end to end, and unlike 0.40.0 it needed no correction on the way — the
two steps that release added to it are what caught what they were written for.

### The stray, and why nothing here could have found it

**`programs/:=` had been in the tree since 2026-08-31.** 117 kilobytes,
byte-identical to [pascal.sol](../programs/pascal.sol), committed by accident
in `f30bc5d` — almost certainly a shell line where a token became a filename.
It survived two days, fifty-four commits, a day of documentation auditing and
every `make test`, and it would have shipped inside `solveig-0.41.0.tar.gz`,
because `make dist` archives `HEAD`.

**Nothing here was ever going to see it, and the reason generalises.** Every
check in this repository enumerates by extension. `expect.sol` counts
`solFilesIn:value("programs")` and reads `.md`; the link checker walks
markdown; `site.sh` fetches published pages; the test suite compiles what the
`Makefile` names. A file with no extension, in a directory every one of those
checks inspects, is invisible to all of them at once — so *nineteen programs*
stayed true and correct while the directory held twenty files.

**What found it was `git diff --name-status v0.40.0..HEAD`**, run to write the
release notes rather than to look for anything. That is the only view here that
asks what a release *adds* to the tree, as opposed to what the tree says about
itself. It cost four seconds, and it is the first step in
[releasing.md](releasing.md#first-look-at-what-the-release-adds) now, with the
rule in [method.md](method.md#and-every-check-here-enumerates-by-extension).

It is the same shape as the four checks with holes recorded on 2026-09-01, and
one step worse: those checks looked at the right things and stopped short. This
one is a class of object no check here has ever enumerated. **An enumeration
that looks complete is not a proof** — [method.md](method.md#an-enumeration-that-looks-complete-is-not-a-proof)
says that about the four states of a pipe, and it turns out to apply to the set
of files as readily as to the set of cases.

### The page, opened

0.40.0's lesson was that the markdown can be provably right and the page a
reader sees still wrong, because GitHub renders release notes with hard line
breaks. Both fixups went in — markers stripped, paragraphs unwrapped, links
absolutised at the tag and each of the six confirmed 200 rather than trusted —
and then the rendered page was fetched and counted rather than read: **fourteen
paragraphs and zero `<br>`**, against the forty-one breaks across eight
paragraphs that 0.40.0 published.

Worth saying plainly what that check is and is not. It reads the renderer's
output, which is the artefact, and that is the point of it. It is still not a
pair of eyes on the page, and if GitHub's markup were wrong in a way that
produced no `<br>` this check would say nothing. **What it can fail on is the
one fault that has actually happened here**, which is the standard the rest of
these checks are held to.

`site.sh` was then run against `origin/main` once Pages had rebuilt: 31 pages,
1,602 headings, 1,311 internal links, nothing to look at.

**And the procedure said *two fixups* while listing three.** Written when there
were two, never counted again, and found only because renaming the heading made
the link checker report the one link into it — which is the stale sentence this
repository has now recorded four days running, in the document that warns about
it.

---

## 2026-09-01 (closing) — fifty-four commits, and the day this repository got a reader

Thirteen entries below this one, numbered first to thirteenth, and they stay
where they are. **Two of them called themselves the day's closing account and
were not**, which is the shape the 2026-08-31 close already recorded and is now
a habit rather than an accident: the third and the fourth carry a line saying so
where the label used to. Their text is unchanged — being wrong about whether a
day is over is worth a note rather than a silent edit. This is the account of
the whole of it.

### What shipped

| | |
| --- | --- |
| [3.23](COMPLETED.md#323-nothing-checks-the-pages-that-are-actually-published--done) | the published pages, checked — [site.sh](../programs/site.sh) |
| [6.41](COMPLETED.md#641-a-path-that-stops-existing-is-an-error-rather-than-an-answer--done) | a path that is not there answers nil, and `tail -f` survives a rotation |
| [6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done) | `system:fileId`, and the line `tail -f` was losing |
| [6.42](COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done) | opened from outside, and closed the same day |
| [lib/re.sol](../lib/re.sol) | POSIX basic and extended, groups and back-references; `pattern.sol` retired |
| [programs/awk.sol](../programs/awk.sol) | the nineteenth program, ten cases agreeing with the tool |
| [docs/PRODUCING.md](PRODUCING.md) | what a producer must get right beyond the grammar |
| a link check, a grammar check, a site check | three things nothing had held before |

144 messages, up from 143. The roadmap's open list emptied four times.

### The day had one lesson and learned it eight ways

**Every real defect came from comparison against something this repository did
not write. None came from a test written from what its author believed.**

- `tail -f` died on a rotation — found by driving it against `/usr/bin/tail`.
- `sed` read `\(` as two literal parentheses and its header said it would not —
  found by running the form the header described.
- `getline < "file"` parsed as a comparison and read standard input — the same
  defect, ten hours later, in a file written after the rule about it.
- Eleven links were 404s on the published site — found by reading rendered
  `href`s, not by any check.
- 263 changelog headings had not reached the site since 0.20.0 — found by
  counting what the site rendered against what the file held.
- `solas` emitted bytecode its own verifier refused — found by generating
  programs until it refused, while writing limits down.
- The dictionary literal's limit was half what its message implied — the same
  way.
- And an outside reader found four more in an afternoon.

### Five throwaways were wrong, each reproducibly

The morning's fence rule invented a finding. The afternoon's man-page
measurement ran two experiments as one and had me write *the page is wrong about
its own flag* in bold. The evening's link checker reported *0 dead* on a site
with ten 404s. A single-run 15% was noise. A benchmark pattern was the worst
case and I reported it as typical.

**None of the failures was in the thing being measured.** [method.md](method.md)
gained three rules from that, and the third is the one that generalises: *a
throwaway that measures something the documents will state is not a throwaway.*

### And four checks of mine had holes

The link checker skipped links with no fragment, on my reasoning that *nothing
here has got one wrong* — three had been broken all along. The same checker
could not see the hole deleting a file made. `expect.sol` accepted any claim
whose first token matched, so `; #5` satisfied `#5 anything at all`. And
`site.sh` reported phantom faults three times, which I answered with a
five-second retry — a guess, wrong within the hour, when the deploy status was
sitting in an API.

**Twice the stated reason was an argument from absence.**
[design.md](design.md#what-the-language-is-for) rules that out for language
features. Nothing had thought to rule it out for checkers, and that is the
sentence to carry.

### The outside reader is the thing that actually changed

Three questions, one afternoon, no expertise required — and they moved a
cheatsheet row, a notation, a checker's matching rule, a grammar nothing had
verified, a compiler emitting invalid bytecode, a limit off by a factor of two,
one sentence standing for thirty-two faults, and a format version that was a
habit rather than a promise.

Every check here was written by the person whose work it checks. That is the
structural fact the day exposed, and no amount of care inside the repository
substitutes for somebody who does not already know what the answer is supposed
to be.

### Where it leaves things

The roadmap is empty. Two candidates are parked on a decision rather than on
work: `solex` and `yax`, the lex and yacc pair emitting Solveig, whose
discussion was deliberately deferred until awk existed — it does now; and
predicate logic, which [ideas.md](ideas.md#programs-that-would-press-on-something)
has recommended since August as the sharpest single finding still available.

---

## 2026-09-01 (thirteenth) — a promise that already existed, and an entry that closed the day it opened

The last call in
[6.42](COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done):
does `.sob` owe a second producer a stability promise? The answer was *format 15
refuses 14*, and the interesting part is that no code changed.

### The rule was there and had never been stated

`if (version != SOL_SOB_VERSION)` is an equality, so a build reads exactly its
own format and refuses everything else in both directions. Handing `solvm` a
file claiming 13 and one claiming 15 refuses both, which is what the decision
asks for and what the reader has always done.

**So the work was to say it.** That distinction is worth keeping: an
implementation detail and a promise can be the same line of C and are not the
same thing to somebody building against it. Phoenix could read the source and
see the equality; it could not know whether that was a rule or an accident, and
a rule nobody has written down cannot be relied on because it can change without
anybody noticing they have broken it.

### Three of four recommendations corrected by building them

The entry made four calls. Document before splitting: right, and the document
found `SOL_MAX_LOCALS` at 256 against a `u8` `slot_count`. Split by who is at
fault: wrong, the sites are one condition each. A directory of malformed `.sob`
files: wrong, they cannot be written without patching a valid file. A stability
promise: wrong that it was work.

Three of four narrowed or reversed. **That is not an argument against scoping**
— every one of them was close enough that the work started in the right place,
which is the whole job of a scoping. It is an argument for writing the calls
down *separately* from the analysis, because a recommendation that is wrong is
only visible as wrong if it was written where the correction can sit beside it.

### What the outside user was worth, counted at the end

One person, reading the documents for an afternoon and asking three questions:

| | |
| --- | --- |
| a cheatsheet row that omitted a newline | fixed |
| a comment convention that reads as a claim | documented where readers look |
| a checker accepting any claim whose first token matched | 22 comments converted, rule is equality |
| a grammar nothing had ever held to the compiler | 15-construct corpus, in `make test` |
| `solas` emitting bytecode its own verifier refused | `SOL_MAX_LOCALS` 256 → 255 |
| a dictionary limit off by a factor of two | written down for the first time |
| one sentence standing for thirty-two faults | thirty-two sentences, thirteen pinned |
| a format version that was a habit | a promise |

None of it needed him to be an expert. It needed him not to already know what
the answer was supposed to be.

---

## 2026-09-01 (twelfth) — the corpus, and three shapes that were wrong before they were built

The last of [6.42](COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done)
bar a decision. Seventeen cases pin thirteen diagnoses, and the interesting part
is that this is the **third** recommendation in the entry that building
corrected.

### Three calls, three corrections

**Document or split first?** The entry said document, and that was right — but
writing the document is what found `SOL_MAX_LOCALS` at 256 against a `u8`
`slot_count`, which no amount of describing it would have.

**How far does the split go?** The entry said *split by who is at fault*, two
buckets. The sites turned out to be one condition each, and bucketing them would
have discarded the part a producer uses. Thirty-two sentences.

**Where does the corpus live?** The entry said a directory of malformed `.sob`
files, here rather than there. Building it showed the files cannot be written at
all without patching bytes of a valid one, since `sol_chunk_save` refuses a
chunk that will not verify — and that a producer does not want our broken files
anyway. It wants its own diagnosed.

Three recommendations, all made from reading the code carefully, and all three
narrowed or reversed by writing the thing. That is not an argument against
scoping: each was close enough that the work started in the right place, which
is the whole job. It is an argument against treating a scoping's *recommendation*
as settled, and the entry now records each correction beside the call it
corrected.

### What the corpus actually protects

Not the verifier — that was already covered, by cases written to harden it
against a crafted file. What is new is that each case says *which* fault it
means, so the value is against a different failure: two diagnoses quietly
merging, or one being reworded, six months from now when nobody remembers that
a producer outside this repository is reading them.

All nine conversions passed first time, which is worth noting because it is the
only evidence that the sentences I wrote match the sentences the verifier
emits. Had I written the document and the code without the assertions, nothing
would have held them together.

---

## 2026-09-01 (eleventh) — the verifier learns to say which

One sentence became thirty-two. `bytecode is internally inconsistent` was the
whole of what a chunk could say about itself, and for a compiler in this
repository that was right: its output is checked byte-for-byte against a second
implementation, and whoever reads the message has the source open.

An outside producer changed what the message is for. Phoenix emits `.sob`
directly, so the verifier is the first thing that tells it whether its back end
works — and *you are wrong* is not a useful answer to a code generator whose
bugs are precisely jump targets, stack heights and slot counts.

### The design question answered itself by being asked properly

[6.42](COMPLETED.md#642-a-second-producer-of-sob-has-no-contract-to-build-against--done)
had flagged a compatibility problem: the result codes are public, something may
be reading them, and splitting an enum is a breaking change.

Looking at who reads them settled it. Four `main.c` files and `builtins.c` all
do `!= SOL_SER_OK` and then ask for a message; the only code that distinguishes
values is the test suite, and fifteen of those assert `MALFORMED` exactly. So
the codes did not need to move at all — what was missing was not a finer code
but a sentence, and a sentence can be an out-parameter.

`sol_chunk_load_why` beside `sol_chunk_load`, the old one a wrapper passing
NULL. Nothing changed for any existing caller. **The compatibility question was
answered by not needing an answer**, which is worth remembering the next time
one comes up: the shape of the fix is decided by who consumes the thing, and
that is a grep rather than a judgement.

An out-parameter and not a file-static string, because `system:load` is
reachable from a thread and two threads verifying two chunks would have shared
it. That cost about forty lines of threading a parameter through five functions,
and it is the difference between a fix and a fix with a race in it.

### Checked by fuzzing rather than by claiming

Every byte of a working `.sob`, set to five values, and the messages counted:
**twelve distinct diagnoses where there had been one**, and the counts are
lopsided in a way that is itself informative — 157 truncations, 30 line-run
faults, 21 bad opcodes, and exactly one each for *does not end in HALT or
RETURN* and *the file runs do not cover the code exactly*.

That is the check the entry could not have had before the split, and it is most
of the design for the conformance corpus that is left: it enumerates which
faults a corrupted byte actually reaches, which is not the same set as the ones
a generator writes.

### The recommendation was too coarse and the entry says so

*Split by who is at fault* was the call I wrote yesterday afternoon — a producer
bug against a damaged file. Writing it found the sites are already one condition
each, and grouping them into two buckets would have discarded exactly the part
that helps. A recommendation made from reading the code and corrected by editing
it.

---

## 2026-09-01 (tenth) — the first outside user, and five things his questions moved

Somebody who did not write this language started emitting `.sob` from outside
it. Three questions over an afternoon, none of them a bug report, and every one
of them moved something.

### The questions were about documents and the answers were about checks

**`display` writes a newline** and the cheatsheet said so for `print` on the row
above and not for `display`. **`; tick tick tick` on a line that prints three
lines** is this repository's comment notation, which he correctly diagnosed and
still lost time to, because it is documented inside `expect.sol` and nowhere a
reader would look.

Both are documentation. What made them worth the afternoon is what checking the
second one found: `satisfies` accepted any claim whose *first token* matched the
output line. `; #5` would have satisfied `#5 anything at all`. The checker had a
standing hole underneath a convention nobody had questioned, and it took an
outsider being confused by the convention to find it.

**Twenty-two comments moved to the `--` form and the rule is equality.** That is
the fourth checker hole this day, and the first one somebody else found.

### And nothing had ever held the grammar to the compiler

*Is `solum.bnf` current?* Answering it needed a sweep nobody had run, because
the only check on the grammar held it against `GRAMMAR.md` — two documents
written by hand from one understanding.

It is current: 94 of 94 shipped files, 15 constructs including the two he
thought were missing, and agreement with `solas` on 9 of 10 malformed programs.
Both constructs he doubted went in on 29 and 30 August, which is the likelier
story — a copy taken before then.

There is a corpus now, one file per construct, in `make test`. It would have
answered his question in two seconds instead of a conversation.

### Writing the document is what found the defects

[PRODUCING.md](PRODUCING.md) is the thing he actually needed and it is two
pages. The rule I set myself was to trigger every rule before writing it down
and to find every limit by generating programs until `solas` refused, rather
than by reading a header.

That is the whole reason it found anything. **`SOL_MAX_LOCALS` was 256 and the
format writes `slot_count` as a `u8`**, so 254 parameters were accepted and 255
produced a chunk `solas`'s own verifier refuses — reported with the one sentence
that stands for thirty-five faults. A compiler emitting invalid bytecode, and
the diagnosis hiding which fault it was, from the person best placed to fix it.
That is 6.42's argument arriving as an instance of itself.

And a dictionary literal takes 127 pairs where its message implies 254, because
it lowers to `dictionary:of` and the ceiling is the argument list's. An array
takes 255. The same limit counted two ways, and neither number written down.

### What an outside user is worth

Every check in this repository was written by the person whose work it checks.
The corpus was, the claims were, the grammar's only comparison was against its
own twin. Today one person reading the documents for an afternoon found a
cheatsheet omission, a notation that misleads, a checker accepting false
claims, a grammar nothing verified, a compiler emitting bad bytecode and a limit
off by a factor of two.

None of that needed him to be an expert. It needed him not to already know what
the answer was supposed to be.

---

## 2026-09-01 (ninth) — awk, and the same defect twice in one day

The nineteenth program is written and ten of its cases agree with the awk on
the machine. It was built in four stages and each one ended by holding the
result against `/usr/bin/awk` rather than against what I expected.

### The predictions were right and unimportant

The scoping named three things awk would want. Full ERE was already built, so
the prediction's whole value was that it got the *order* right. The lenient
numeric read is nine lines and wanted nothing new. `%e` and `%g` are written in
the program, which is where a format belongs.

**The thing that actually pressed was not on the list.**
[3.2](ROADMAP.md#32-no-non-local-return) was wanted three separate times in one
file, and I wrote `^` three times before remembering it is not there. An
interpreter dispatching on a tag is the shape that wants to answer and leave;
without it, `evalBinary` guards every arithmetic branch against having already
settled `~`, and five unwinding statements become five flags.

That is the second real customer for an entry that has had one since August,
and it arrived without being predicted by an entry that was predicting exactly
this kind of thing.

### The same defect, twice, ten hours apart

This morning `sed` was found to read `\(` as a literal parenthesis: a valid
script came out inverted, silently, and its header said it would be refused.

This evening `getline line < "file"` was found to parse as `getline line` and
then a comparison with the filename. It read standard input, threw the answer
away, printed nothing and exited 0.

**Both were found by running the form rather than by reading the code**, and
both were in a place a note said was not implemented. The note is the tell: a
sentence saying *this is not written* is a sentence nobody has run, and in a
program that parses something, "not written" and "quietly means something else"
are the same syntax.

So the rule the day already produced —
[a claim in a header is a case waiting to be written](method.md#an-author-written-corpus-tests-what-its-author-thought-of)
— fired twice before it was a day old, and the second time in a file I had
written after writing the rule.

### What the oracle found that I would not have

Six defects, five of them from comparison rather than from a test. `-F:` joined
to its flag. `run` calling `setDefaults` after the command line had set `FS`,
which only showed on the one flag in three that had input to act on. `re.sol`
not exporting `lastEnd`, which no earlier caller had wanted. `truncated` asked
before its own magnitude guard. And `ln(1e30)/ln(10)` landing at
29.999999999999996, which put one number in thirteen on the wrong side of a
switch.

Not one of those would have been in a test I wrote from what I believed the
program did.

---

## 2026-09-01 (eighth) — the library, and a checker that could not see its own hole

`lib/re.sol` is built and `lib/pattern.sol` is gone. The decision that unblocked
it was one sentence — *the patterns here are ones we write, not a stranger's* —
which is what chose Solum over an extension, and everything below follows from
having a customer rather than an argument.

### The corpus proved it, and nothing else could have

Sixty cases agreed before the swap and **sixty-two after**, because the two
added to `differ/` an hour earlier — the ones written to document a gap — now
agree with the oracle. The harness said it in its own words: *AGREES, the
divergence has gone, and the file still claims it.*

That is the whole argument for holding a program against a tool somebody else
wrote, arriving as a sentence the harness prints rather than as a principle.

### What measuring caught, twice, before it was written down

**A claim about depth.** Having made the matcher iterative I typed *a thousand
stars in one pattern cost nothing*, then ran it: `call depth exceeded`, in the
**emitter**, which walks a tree. A sequence built as `cat(cat(a,b),c)` is as
deep as the pattern is long, so 220 characters was the limit where
`pattern.sol` compiled two thousand. Making a sequence a list fixed it, and the
honest number is 48 nested groups.

**And a difference against the old file.** 4,485 comparisons produced 28
disagreements, all one shape: `pattern.sol`'s `endOfMatchAt` ignored `^`. The
oracle sided with the new engine, and no shipped caller could reach the
difference — but it is the third thing that file got wrong today, after `\(` as
a literal and the header that denied it.

### The checker could not see the hole it made

Deleting `pattern.sol` left nineteen links pointing at it. **This morning's link
checker reported none of them**, because I had scoped it to links carrying a
`#` and written the reason into the entry: *a missing file is a different
question and nothing here has got one wrong.*

That was false when it was written. The sweep found **three links broken all
along** — two in `experiment/` naming `sob.sol` beside them when it lives in
`lib/`, and `tail.sol` naming `follow.sh` beside it when it is in `tail/`.

So the scope was not narrow, it was wrong, and wrong in the direction that hides
things: a dead anchor lands a reader at the top of the right page, and a dead
path lands them nowhere. It checks paths now, 2,162 of them, and I broke one to
watch it fail before believing it.

**Twice in one day a check I wrote had a stated limitation that turned out to be
a hole**, and both times the stated reason was *nothing here has got that
wrong*. That is an argument from absence, which
[design.md](design.md#what-the-language-is-for) rules out for language features
and which nothing had thought to rule out for checkers.

---

## 2026-09-01 (seventh) — an evening of scopings, and the defect at the end of them

Four pieces of work that were all one argument: awk, `lib/re.sol`, a throwaway,
and a shipped defect that only turned up because the argument kept going.

### Two scopings, and both were argued with

**awk was proposed and written up as *not next*.** Its largest demand is full
POSIX ERE, and the entry that would supply it already had a customer —
`sed.sol` refuses `\(...\)` — so writing awk to justify the library was the
wrong order. That much held.

**What did not hold was the framing.** Leading with `sed` as *a* customer
invited a fair question: if the second customer is awk, and awk waits for the
library, what unblocks what? Nothing, on that framing — and it was the wrong
framing. `edit.sol` uses the same engine for `/` and is the second customer, and
the worse one, because it does not refuse. awk is the third and unblocks
nothing.

**And the August regex entry has never deferred for want of demand.** It surveys
460 lines of hand-rolled scanning and calls the demand real. What it declines is
the *extension*. But it lives in a section where deferral means *waiting for a
second customer*, and nothing flagged it as the exception, so at a glance it
said the reverse of what it meant. Flagged now.

### The throwaway, and three of my own numbers

Two hundred lines: ERE to Pike's instruction set, run by a loop with a backtrack
stack. Semantics identical to `/usr/bin/awk` on all six cases, compared by
`diff`. Leftmost-longest free. The exponential real and fixed by a visited set
for 20–30%.

Then three corrections, all mine:

- **The headline number was the worst case.** `[a-z]*ing` opens with a starred
  class so nothing can be skipped. Typical patterns are 25–30× the tools, not
  190×, and `pattern.sol`'s leader searches a 4,269-line buffer in 0.008 s.
- **"3.7 belongs to the C route" was overreach.** `grep` is flat on both
  dialects; the exponential is a property of a hand-written backtracker, not of
  regular expressions — which is what the parent entry said and I claimed to
  have refuted.
- **And the trigger question was better than my answer.** *Can be written in
  Solum* is not *is usable by the thing that wants it*, and
  [6.34](COMPLETED.md#634-a-program-cannot-ask-how-big-the-terminal-is--done)
  settled that distinction in August: `stty size` was always reachable at 7 ms
  an ask and became a primitive anyway, because *the absence was never the
  finding, the price was*. Price fires triggers here. The open question is now
  **who chooses the pattern**, which is sharper than *how fast*.

### And then the defect

Checking that `sed` really refused what its header said it refused — one command
— it did not. `s/\(ab\)c/YES/` substituted the wrong line and skipped the right
one, silently, and had done for the life of the file.

**Sixty cases in the corpus and not one used `\(`.** The oracle is the check
this repository trusts most precisely because it can find what nobody thought to
look for, and it is written by the same person who wrote the program. That is
the rule the day ends on, and it is in
[method.md](method.md#an-author-written-corpus-tests-what-its-author-thought-of):
write cases for what a program says it *will not* do, because every *this is
refused* in a header names an input nobody has tried.

### The count for the day

Five throwaways wrong, each reproducibly, and none of the failures in the thing
being measured. Three roadmap entries opened and closed. Two scopings written
and both improved by being disagreed with. One shipped defect, found by pulling
on the second of them rather than by any check.

---

## 2026-09-01 (sixth) — the list is empty, and the trigger never fired

Three entries were open this morning. All three closed today, which has not
happened before: 6.41, 3.23 and now
[6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done).

### The trigger did not fire, and the entry says so

One customer and one flag, for two days, exactly as written. `system:fileId`
was built on instruction rather than because a second caller arrived. A list
that quietly becomes right about its own admission rule is worth less than one
that records being overruled, so the entry records it.

**What moved was the case, not the trigger** — and this is the part worth
carrying. The entry said a rotation makes `tail` print from the wrong offset.
Driving it first, as this day has now done four times, said something worse:

| | |
| --- | --- |
| `/usr/bin/tail -F` | `AAAA` `BBBB` `CCCC` |
| `tail.sol -f` | `AAAA` `CCCC` |

A five-byte log replaced by a five-byte log. `BBBB` was written and never
appeared — no error, no notice, no exit status. **A gap that loses data
silently is a different argument from one that misprints**, and it was
measurable on the day the entry was written, by the person who wrote the entry,
in about ninety seconds.

That is the fourth time today that driving the thing beat reasoning about it,
and the second time the *argument* for a piece of work turned out to be
understated rather than wrong.

### What the build did not have to decide

**6.41 had already settled the absent-path question**, which was the one design
problem `fileId` would otherwise have had: a follower asks every poll, and a
rotation takes the path away for a moment. Nil, on the precedent set this
afternoon. Built in the other order, `fileId` would have been a message whose
only caller exited 1 before it could call it — which is what the reordering was
for, and it is pleasant to see it pay.

**And the shape held.** `fileId` over `sameFile`, a value a program can keep
rather than a boolean about two paths it cannot hold across the moment one of
them stops existing — argued on 2026-08-31 and not revisited. Two days is long
enough for a scoping to be wrong, and this one was not.

### Two small things found on the way

**A stale `.sob` reported a code fault.** The new `follow.sh` scenario came back
DIFFERS on its first run, and the difference was a build: I had compiled
`tail.sol` to a temporary path and the harness runs `programs/tail.sob`. It now
refuses to run on a `.sob` older than its source. `*.sob` is not tracked, so
nothing else would have caught it, and the failure reads exactly like a fault in
the program.

**`intmax_t` was arriving through some other header.** It compiled clean here
and would not necessarily elsewhere. `<stdint.h>` is included explicitly now —
a front page that says *no dependencies, portable C11* does not get to rely on
what a platform happens to pull in.

### Where the day ends

Six entries, eleven commits, three roadmap entries opened or closed, and the
open list empty. Every one of the three was closed by driving a program rather
than by reading about it, and three separate throwaways were wrong along the
way — two this morning and evening, and the man-page measurement this
afternoon. None of the failures was in the thing being measured.

---

## 2026-09-01 (fifth) — the check shipped, and found something else on the way in

The day's fifth entry, and the third to follow one that called itself the last.

[3.23](COMPLETED.md#323-nothing-checks-the-pages-that-are-actually-published--done)
was scoped this evening and built the same evening, on the four calls answered
as recommended: [site.sh](../programs/site.sh), beside the other oracles,
headings and anchors over one fetch, named in
[releasing.md](releasing.md#what-the-document-checker-does-not-cover).

### It found its own best argument while being written

Not by running — by *reading*. Writing the fetch loop meant looking at the
rendered `href`s, and one of them was `/docs/releasing.html#...` where every
other was `/Solveig/docs/...`. Nine distinct URLs, all 404.

**A markdown link whose text wraps across a line loses the site's baseurl** when
Jekyll rewrites its `.md` target to `.html`. Eleven such links; ten published.
The markdown is correct, `expect.sol` passes on all of them, and the local link
check built this morning says they are fine — because locally they *are* fine.

The first hypothesis was wrong and the correction is the useful part. A quick
regex said twenty-seven links had a newline in their text, and only nine were
broken, so the rule looked more complicated than it was. The regex was the
problem: `[^\]]*` across a document with brackets in tables matches far more
than a link. Tightened to reject brackets inside the text, it found exactly
eleven — and nine distinct URLs, which is what the site showed. **A detector
that disagrees with the artefact is usually the detector.**

### And the scoping's own throwaway had a hole

It reported *0 dead* on a site with ten 404s in it, because it only checked
links whose target it had already fetched — and a link with a wrong base
resolves to a page that was never fetched, so it was skipped in silence.
Checking that a link's **anchor** exists and checking that its **address** does
are two questions, and the entry had only asked one.

That is twice in a day that a throwaway measuring something real was itself
wrong, in a way that reproduced. This morning's ran two experiments as one; this
one skipped what it could not resolve. Neither failure was in the thing being
measured.

### What each branch actually catches

The entry's first draft said the heading branch had been reproduced by pointing
`SOURCE_REF` at an older commit. **That was written before it was run**, and
running it produced *extra* rather than *lost* — a healthy site cannot make that
branch fire in the direction that matters.

Held against the broken page saved that morning instead: the source at `1cfa39f`
has 316 headings by this rule, and the page GitHub actually served rendered 64.
So the branch catches the `<if-statement>` fault, which stops rendering
outright.

**And it would not have caught the stray fence on its own.** A ``` at the start
of a line moves both counts together — 316 where the fixed file has 327 —
because the rule reads fences the way the renderer does. That fault's signature
is the eleven headings that fall inside a fence, which is what `expect.sol`
reports locally, and where the number went 1 to 12. Two checks, one fault each.

Writing that down took three attempts and each was shorter than the last, which
is the shape of a claim being narrowed to what was measured.

---

## 2026-09-01 (fourth) — the check that found the day's worst fault, scoped

> **Written as *really closing*, which it also was not.** Nine more followed.

Four entries. The one below calls itself the day's closing account and was wrong
about that, in the same way and for the same reason the 2026-08-31 one was: a day
is not over because the work in front of you is.

[3.23](COMPLETED.md#323-nothing-checks-the-pages-that-are-actually-published--done) is
scoped and not built. It is the comparison that found this morning's fault —
the published pages against the markdown they were built from — and it is the
first entry in section 3 whose case is a fault that shipped rather than an
argument about one.

### Why it is a roadmap entry and not an idea

[ideas.md](ideas.md) is what was considered and turned down. This was not turned
down; it is outstanding work with a clear shape, which is what
[ROADMAP.md](ROADMAP.md) is the single list of. The precedent is exact:
[3.16](COMPLETED.md#316-what-the-checker-does-not-check--done) and
[3.21](COMPLETED.md#321-a-changelog-hash-is-written-by-hand-and-nothing-checks-it--done)
were both entries about this repository's own verification and both got 3.x
numbers.

### The design problem is not the network

It is **what the check compares against**. The site renders `origin/main`, not
the working tree, so a published page held against a local file reports every
unpushed edit as a fault and the check is noise inside a day. It has to read the
source with `git show origin/main:docs/X.md`.

The throwaway that found the morning's fault did not do that. It was right
because it happened to run just after a push, which is the same kind of luck as
the day's other mistake and is worth writing down beside it.

The second cost is not the fetching either: `extensions/net` has no TLS, so
either shape ends up at `curl` through `system:capture`. What makes the Solum
version the more expensive one is that the anchor rule lives inside
`expect.sol`, and writing it again would be two copies of one function — the
trigger this repository built `replace` on. A Solum version means moving that
rule to `lib/` first, which is a good change and a different one.

### And two live wrong claims that this check would not have caught

Both found while writing the entry, and both named in it so that it is not sold
on evidence it does not cover — it checks that markdown *renders* as what it
says, not that prose is *true*.

- **`_config.yml` said 141 messages** where the language answers 143 — the
  site's own description, stale across two releases, and published in the header
  of every page. Fixed. It is not a document to `expect.sol`, which
  [releasing.md](releasing.md#what-the-document-checker-does-not-cover) already
  says in the section written about exactly this file.
- **The repository description on GitHub** still says *the Solum language*, *136
  messages* and *15k lines of C11* — the 0.36.0 rename, inverted, still standing.
  `_config.yml` was corrected for that and GitHub was not. It is not in the
  repository, so nothing here can reach it; it is 20,240 lines of C now, and
  143 messages.

Both want the marked-count mechanism extended past `docs/`, which is cheaper
than 3.23 and is a different entry. Neither is argued for here.

---

## 2026-09-01 (third) — the scoping was right, its measurement of the oracle was not

> **This entry was written as the day's closing account and was not it.** Ten
> more followed. The label is corrected to its place in the order rather than
> the text, which stands as written — being wrong about whether a day is over
> is the same mistake the 2026-08-31 close recorded, and making it twice is
> worth a line rather than a silent edit.

Three entries for the day. This one is the account of the whole of it, and the
two above are left where they are — including the section in the evening entry
that is wrong, which is annotated in place rather than rewritten, because what
is interesting about it is that it reproduced four times.

### What shipped, over the day

| | |
| --- | --- |
| a link check in [expect.sol](../programs/expect.sol) | 1,329 links against 1,502 headings, in `make test` |
| two rewrapped lines in `CHANGELOG.md` | 263 of its headings had not reached the published site since 0.20.0 |
| [6.41](COMPLETED.md#641-a-path-that-stops-existing-is-an-error-rather-than-an-answer--done) | opened, scoped and closed |
| `fileSize` and `modifiedAt` answer **nil** for a path that is not there | and go on raising for one that cannot be looked at |
| `tail -f` survives a rotation | two scenarios in [follow.sh](../programs/tail/follow.sh) that ended the run before today |

**Everything above came from running something rather than reading it**, and
that is the whole of the day's shape. The link checker was written because a
heading moved; it was the *site* comparison that found the fault. 6.41 exists
because `tail` was driven through a rotation before anything was designed for
6.39. And the day's own mistake was the one measurement taken by a throwaway
that nothing checked.

### The mistake, and what caught it

The afternoon's scoping said BSD's `tail -f` follows the **name** across a
rename, that `-F` therefore buys only retry-after-removal, and — in bold — that
the man page is wrong about its own flag. All three were wrong. `-f` follows the
**descriptor**: after a rename it goes on reading the renamed file, and `lsof`
on the running process shows it holding the old one open.

**The throwaway ran both flags in one script**, and it reproduced. Four times,
at two timings, which is what made it convincing. Reducing it to a single flag
made the wrong answer disappear, and the mechanism was never worth chasing
further than that.

What caught it was [follow.sh](../programs/tail/follow.sh), on the first run
after two new scenarios went in — because the harness runs the two sides under
**one** set of conditions and the throwaway ran them under two.
[method.md](method.md#a-check-that-cannot-fail-is-decoration) already says a
comparison whose two sides came from the same source is not a comparison. This
is the other half of the same rule and it was not written down: **a comparison
whose two sides did not run alike is not one either.** It had been applied to
every check in this repository and not to the throwaway that measured the
oracle those checks compare against.

The sequence, twice in one day: a wrong throwaway produced a finding, the
finding was chased, and something real came out of it — the fence fault this
morning, the reordering this afternoon. Both times the throwaway's own claim was
false. That is worth naming as a pattern rather than as two accidents.

### 6.41 was scoped and built the same day, which is not the rhythm here

The rule is that scoping stops and building is a separate instruction, and it
held: the scoping was written, the calls were asked for, and building waited for
the word. What made the gap short is that the scoping had nothing left to decide
— the question was *which of two shipped messages is wrong*, not what to add.

Two of the four path messages already answered rather than raised. `fileExists`
and `isDirectory` have swallowed a failed `stat` since they were written, and
`fileSize` and `modifiedAt` raised. Nothing had ever stated that as a rule
because there was no rule; there were two habits.

The one decision with an argument on both sides was **EACCES**, and it is on the
raising side. Absence is an answer; a permission that stops the question being
asked is not one, and a program told nil would conclude a file is gone when it
is sitting there. The test asserts both halves and skips the permission one
under root rather than asserting it falsely.

### What is still not there

[6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done)
is the same size it was this morning, and the list is back to one open entry.
`tail` now survives a rotation and gets the *fast* one wrong: a replacement that
appears before the next poll never shows the path absent, so the file is judged
by its size — smaller reads as a truncation and restarts, right by luck because
a fresh log is empty; equal or larger prints from the wrong offset. That is
identity, and it is 6.39 exactly. Its trigger has still not fired.

The other thing with a case and no home is the check that found the morning's
fault: **the headings the published site renders, counted against the headings
in the file**. It caught a page that had been broken for ten days and twenty
releases. It needs the network, and `expect.sol` reads files and runs programs.

---

## 2026-09-01 (second) — an hour on 6.39 that produced a different entry

The instruction was to work on
[6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done),
file identity. The hour produced no code, two roadmap entries and a correction
to a shipped program's header, and 6.39 is not the one that came out of it.

### The first thing was to drive the customer, not to design for it

6.39 exists because `tail -F` wants it. So before anything was designed, the
thing that wants it was run: `tail -f` against a file, and a rotation performed
underneath it from another shell.

```sh
$ ./bin/solvm tail.sob -f x.log &
$ mv x.log x.log.1
one
tail: cannot measure 'x.log'      # exit 1
```

**It does not fail to follow the rotation. It dies on it.** `tail:follow` polls
`system:fileSize` once per file per interval and `fileSize` raises when the path
is gone — so a log rotation, or a plain `rm`, ends the program with status 1.
`/usr/bin/tail` waits and picks up the replacement.

That is [6.41](COMPLETED.md#641-a-path-that-stops-existing-is-an-error-rather-than-an-answer--done),
and it is **the entry 6.39 was standing in front of**. Following a rotation has
two halves — surviving a path that is not there, and noticing the file behind it
changed — and only the second one is 6.39. The first needs no new kind of value.
It is a defect in a shipped message.

[method.md](method.md#a-scoping-can-be-wrong-about-the-order-not-only-the-answer)
already had this shape written down. It is the second time it has fired, and
both times the way it was noticed was the same: run the thing rather than read
about it.

### Two of the four path messages already disagree with the other two

`fileExists` and `isDirectory` swallow a failed `stat` and answer false. A path
that is not there is not an error to them, it is the answer. `fileSize` and
`modifiedAt` raise. The four get asked about the same thing in the same breath.

The decision taken: `fileSize` and `modifiedAt` answer **nil** for a path that
is not there, and go on raising for a real failure. It is what `getenv` answers
for an unset name and what `terminalSize` answers off a terminal.

**And nil does not fix `tail` on its own**, which is the reason 6.41 says so out
loud. With nil, the poll reaches `now:lessThan(sizes:at(i))` and raises
*'lessThan' expects integer, got nil* — a worse message, further from the cause.
What nil buys is that the program can *say* what a vanished path means to it.
The message and the program are one unit of work, not two.

### The measurement that corrected the entry, and the man page it corrected

> **This section is wrong, and is left standing because it is the day's
> subject.** The table below and the paragraphs under it were written from a
> throwaway that ran both flags in one script, and they say `-f` follows the
> name. It does not: it follows the descriptor, exactly as the man page says.
> That was caught the same evening by
> [follow.sh](../programs/tail/follow.sh), which runs the two sides under one
> set of conditions, and settled by `lsof` on the running process. The corrected
> table is in
> [6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done)
> and the account is in the entry below this one. Rewriting it here would delete
> the only interesting thing about it, which is that it reproduced four times.

`system:fileId` was going to answer a string, "most likely", because device and
inode "do not fit an integer on every platform". Measured: `dev_t` here is a
**signed** four-byte integer and `ino_t` an unsigned eight; on Linux both are
unsigned eight. `/dev/null` has a **negative** device number. So the string is
right, and whatever formats it has to be sign-correct — a detail that would
otherwise have been found by a crash.

Then the `-F` behaviour itself, driven rather than read:

| | `-f` | `-F` |
| --- | --- | --- |
| renamed away, new file at the path | follows the **new** file | follows the **new** file |
| appended to the **old** inode after the rename | ignores it | ignores it |
| removed, then recreated later | prints nothing more, keeps running | follows the **new** file |

**The only difference `-F` makes on this machine is retry after a removal.**
`-f` already follows the name across a rename — which its own man page implies
it does not, describing the close-and-reopen-on-new-inode as `-F`'s.

The first run of that contradicted the page and the right response was to
distrust the run. It reproduced with two seconds between every step, and
`x.log.1` really did receive the bytes `-f` ignored. `-F` is in no standard to
appeal to: POSIX specifies `-f` and stops.

### What was not done

No C, no message, no `-F`. The scoping is the deliverable and building is a
separate instruction, which is
[what this repository says](method.md#scope-before-building-and-the-decision-is-separate)
and is the rule that made the hour worth spending: an implementation of 6.39
started at the
top of it would have shipped a message whose only caller exits 1 before it can
call it.

6.39's trigger is also unchanged and still has not fired — one customer, no
second one — and the entry now says that working on it produced two entries and
no code.

---

## 2026-09-01 (first) — a checker built off its trigger, and the two faults it did not find

One instruction: build the link checker. It is built, it is in `make test`, and
it reports nothing — and almost none of the day's value is in it.

### What shipped

| | |
| --- | --- |
| a link check in [expect.sol](../programs/expect.sol) | 1,313 links against 1,496 headings, with a floor in `tests/test_cli.c` |
| two fixes in `CHANGELOG.md` | a stray ``` fence and a `<if-statement>` at the start of a line |
| [the ideas entry](ideas.md#nothing-checks-that-a-link-points-at-a-heading-that-exists) | moved to the built section, saying its trigger never fired |

### The trigger did not fire, and that is the first thing to write down

The entry asked for **a second heading move that took links with it** before
this was worth building. There has not been one. It was built because it was
asked for, which is a perfectly good reason and is not the reason the entry
named — and the entry now says so, because a trigger nobody records failing is a
trigger that decides nothing.

### The throwaway found something, and it was not what it said

A first version in Python, twenty lines, reported exactly one finding:
`docs/CHANGELOG.md:7470`, a link to `#0170--2026-08-22` naming no heading. The
heading is plainly there at line 7517.

Chasing that turned up **two real faults in the file, both of them markdown that
renders as something other than what it says**:

- Line 7008 had wrapped so that ``` began a line. That is a code fence. It turns
  380 lines of prose into a code block and eleven headings into nothing.
- Four thousand lines above it, an inline code span had wrapped so that
  `<if-statement>` began a line. kramdown reads that as a raw HTML block and
  stops rendering markdown from there to the end of the file.

Fetching the published page settled it rather than arguing from the spec:
**64 of the changelog's 327 headings reached the site**, and had not since
0.20.0 — ten days and twenty releases. Every other page checked clean, all
thirty of them, which is what made the two lines findable at all.

### And then the finding turned out to be an artefact

The throwaway closed a fenced block on **any** line beginning with ``` . The
renderer closes one only on a **bare** fence. Under the correct rule the parity
after line 7008 comes out different, the 0.17.0 heading is not inside a block,
and **that link is fine** — the shipped checker reports nothing on a tree with
both faults still in it, which was tested by putting them back.

So the sequence was: a wrong check produced a wrong finding, and chasing the
wrong finding found two right ones. That is luck, and it is worth naming as
luck. [method.md](method.md#a-check-that-cannot-fail-is-decoration) already says
a test that fails for the wrong reason misleads as far as one that cannot fail;
what this adds is that it can also mislead *usefully*, and the temptation is
then to write it up as though the check worked. It did not. **What found the
faults was a different comparison entirely** — the headings the published site
renders, counted against the headings in the file — and that one needs the
network and is not in `expect.sol`.

### What the check is, and the one decision inside it

Every heading in `docs/`, the two pages at the root and every `.sol` header
becomes the anchor GitHub would give it; every link carrying a `#` is either in
that set or it is a finding. Links with no fragment are counted and not checked.

**The load-bearing decision is that fences are tracked, by the renderer's rule.**
Ignoring them would give a superset of the real anchors — safe in the sense that
it can only miss a finding and never invent one — and it would also make the
program disagree with the page a reader lands on, which is the only thing a link
is about. The number of headings that fall inside a fence is reported and has a
ceiling in the test, because it is the one part of this with no other witness: it
is 1 today, and it is 12 the moment that wrapped paragraph comes back.

### Held against something somebody else wrote, for once literally

Both implementations dumped their anchors and their resolved links, sorted:
**1,487 anchors and 1,309 links, identical, character for character.** One uses
an alphabet string and a hand-written walk and resolves `..` with an array as a
stack; the other uses `isalnum`, a regular expression and `os.path.normpath`.

Two of the four failure demonstrations are worth keeping. A reworded ROADMAP
heading was caught in five places across four files at once — the scenario the
entry was written about. Re-breaking the changelog was caught by *nothing*,
which is how the artefact was found.

### What is left, and it has no trigger yet

The check that actually worked is not in the repository: **compare the headings
the published site renders against the headings in the file**. It found a page
that had been broken for ten days, and it would have found it on any day of
those ten. It needs the network, which nothing here does, and `expect.sol`
reads files and runs programs. Written down without a trigger on purpose,
because the case for it is a fault that already happened rather than one that
might.

The smaller local version — a line at column 0 beginning with `<` outside a
fence — has two candidates in the whole tree and one of them is `README.md`'s
logo, which is the shape this repository defers.

---

## 2026-08-31 (closing) — a day of working code, and eleven wrong sentences about it

Seven entries for one day. This one is the account of the whole of it, and the
mid-day postmortem three entries down is left where it is because it called
itself the day's and was wrong about that too.

**The first draft of this paragraph said *six entries, which has not happened
before*, and both halves were wrong** — there are seven, and 2026-08-30 and
2026-08-26 had thirteen each. Which is the day's subject arriving inside the
entry about it, so it stays: a count in prose is a claim, and this one took one
`grep` to check and had not been.

### What shipped, over the day

| | |
| --- | --- |
| `programs/sed.sol`, `programs/tail.sol`, `programs/sha256sum.sol` | the sixteenth, seventeenth and eighteenth programs |
| `system:readFile(path, from, count)` | and [3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done) closed with it |
| `system:sleep`, `system:isTerminal` | the 142nd and 143rd messages |
| [6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done) | opened, and gated on a second customer |
| [6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done) | opened and closed |
| `programs/oracle.sh` | written for `sed`, generalised by `tail`, then twice more by `sha256sum` |
| `tail/follow.sh`, `sha256sum/vectors.sh`, `sha256sum/check.sh` | three checks of three different kinds |
| a defect fixed in `lib/pattern.sol` | and two in shipped programs |

**Everything above is downstream of one decision taken in the first half hour**:
hold a program against the tool already on the machine rather than against a
transcript its own author recorded. The mid-day postmortem argues that and it
still holds.

### The thing worth taking from the day

**No program was wrong. Ten sentences about them were.**

Every check passed. `sed`, `tail` and `sha256sum` each did their job; the
corpora agreed; the vectors agreed; `make test` was green all day. What kept
failing was the *prose* — the comments, entries and notes describing what had
been measured and what had been decided — and it failed ten times.

They are not all one shape, and separating them is the useful part. Listed so
that *eleven* is a number a reader can check rather than one to be trusted:

**Stale — true when written, and the world moved underneath.**

1. `pattern.sol`'s worked example, which could not show the defect standing
   beside it.
2. 3.22's trigger, *nothing here has a file that does not fit* — a fact about
   this repository's inputs rather than about the world.
3. Four count markers on past releases, which a moving total would have
   silently rewritten.
4. [ROADMAP.md](ROADMAP.md)'s own summary, *nothing is on it*, while an entry
   was being added to it.
5. The mid-day postmortem, which counted the entries above it and called itself
   the day's.

**Never checked at all** — worse, and the day's larger half.

6. *A blank line is not a malformed line in either tool*, which had asked
   neither. Both count it.
7. *The size makes no measurable difference*, of a chunk size nobody had timed.
   It is out by 62%.
8. *A fifth of the program was a method call* — the figure from the line above
   the right one. It is a third.
9. *The first check here that does not depend on another implementation*, which
   [the NBS suite](../programs/basic/conformance.sh) had been for months.
10. *The seventh file of the flag idiom*, which was a different limitation and a
    count the cited entry had explicitly stopped keeping.

**Incomplete, and reading as complete.**

11. `keyWaiting`'s *exact rather than approximate*: three pipe states enumerated
    correctly, and a pipe has four. This one had shipped as a defect in two
    programs, and is now
    [its own rule](method.md#an-enumeration-that-looks-complete-is-not-a-proof).

Two more were caught inside the writing rather than after it — a claim about
what GNU coreutils does with `-` in a checksum list, on a machine with no GNU
coreutils to ask, and the entry-count above. Neither shipped, and both are the
same shape as the eleven.

### What caught them, every time

**Doing the thing again, never reading it again.** Eleven for eleven. The six
from the evening, with what actually caught each — the day's earlier five went
the same way, and the
[mid-day postmortem](#2026-08-31-postmortem--the-day-an-oracle-was-pointed-at-this-language-and-four-sentences-fell-over)
says so in its own words: *making the file, running the case, moving the
number*.

| the sentence | what caught it |
| --- | --- |
| a blank line is not malformed | running `-c -w` on a list with one |
| no measurable difference | timing five chunk sizes |
| the first check of its kind | opening `conformance.sh` |
| the seventh file | opening the entry it cited |
| a fifth of the program | re-measuring three variants of the shipped file |
| exact rather than approximate | building the replacement and comparing answers |

Not one was found by rereading. That is not a claim about carelessness — several
had been read many times by somebody looking for exactly this — it is a claim
about what reading can do. **A sentence about a measurement contains no
evidence.** It reads as well when it is wrong.

### And one thing nothing here checks

Closing 6.40 moved its section from [ROADMAP.md](ROADMAP.md) to
[COMPLETED.md](COMPLETED.md), and four links written that morning went on
pointing at the old anchor. A sweep for the rest found two more, one of them
naming a heading in a different file than the one it lived in. All six are
fixed, and the sweep now reports zero.

**[expect.sol](../programs/expect.sol) checks a great deal and not this** — it
runs every block, recounts every marked number, holds `GRAMMAR.md` against
`solum.bnf`, checks that each changelog entry names a commit. A link is the one
cross-reference nothing verifies, in a repository whose filing system *is*
moving headings between files when an entry closes.

Not built: it is once, and a dead anchor lands a reader at the top of the right
file rather than nowhere.
[Deferred with a trigger](ideas.md#nothing-checks-that-a-link-points-at-a-heading-that-exists)
— a second heading move that takes links with it, which is a release away.

### Two rules the day put in method.md

**[An enumeration that looks complete is not a proof.](method.md#an-enumeration-that-looks-complete-is-not-a-proof)**
*Three cases, all correct* reads exactly like *all the cases*, and nothing marks
the edges. Ask what states the thing has from its own side and count them.

**[Replacing something that works is how you find out what it was doing.](method.md#replacing-something-that-works-is-how-you-find-out-what-it-was-doing)**
The `keyWaiting` paragraph was never audited because there was no reason to
audit it: the program worked. It got audited only because a new message had to
answer the same question and the two answers had to be compared. **An expression
nobody has a reason to doubt is an expression nobody checks.**

### What went right, and it is the trigger rule twice

**6.40 was a note before it was an entry.** `tail` could have argued it onto the
roadmap in the afternoon — one program, a real gap, a willing page — and wrote a
note with a named trigger instead. `sha256sum` fired it four hours later and the
promotion cost one sentence. The rule's cost is visible every time it refuses;
its payment is invisible, and this is what the payment looks like.

**And it held three times against being fired.** 6.39 stayed shut: one customer,
and `mirror` turned out not to want it. The NUL-in-a-path question was scoped and
left, with an exact workaround. `-flto` stayed deferred even though `sha256sum`
is genuinely slow at `-O2`, because 20% off 1.08 MB/s changes nothing about a
program three orders of magnitude from the C tool.

### What is next

[6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done)
is the only open entry and its trigger has not fired. The
[Unix survey](ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31)
still has `diff` (two inputs at once), `gzip -d` (array-heavy work, and the
sequel to the number `sha256sum` produced), `sort` (which would fire the
positioned-write trigger) and `unzip -l`.

## 2026-08-31 (late) — a message built to retire a paragraph, which fixed a defect nobody knew about

One entry, opened in the evening and closed the same night, and the useful part
is not the message.

### What shipped

`system:isTerminal('input)`, `('output)`, `('error)` — the 143rd message,
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done).
Three tests, an example, and a defect fixed in
[tail.sol](../programs/tail.sol) and [sha256sum.sol](../programs/sha256sum.sol).

### The entry arrived the way the list would like everything to

`tail` found in the afternoon that `keyWaiting(0.0)` answers *is standard input
a terminal* by accident. It could have been argued into a roadmap entry on the
spot — one program, a real gap, and a page willing to take it. It was written
down as a **note with a named trigger** instead: *a second program wanting it*.

`sha256sum` was the second program four hours later, for the identical
collision. The promotion cost one sentence, because the reasoning was already
written.

**That is the trigger rule paying in the direction that is hardest to see.**
Refusing to open an entry is invisible when it works; the only evidence it ever
produces is a promotion that costs nothing, and this is one.

### And then the thing it was built for turned out not to be the point

The case for the entry was **entirely about spelling**. Both programs worked;
both carried a paragraph explaining why a message about *reading* answers a
question about *terminals*; two paragraphs explaining one accident is
[5.5](COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done) in prose.
There was no defect. The entry said so, and so did both programs, in the words
*a workaround that is exact rather than approximate*.

**It was not exact.** The reasoning behind that word ran: an idle terminal
answers false, a pipe with data answers true, a pipe at its end answers true.
Three cases, and every one of them is correct.

**There is a fourth.** A pipe that is open, empty and **not yet finished**
answers false — exactly as an idle terminal does, because *is there a byte right
now* is equally false of both. So:

```text
{ sleep 1; printf 'a\nb\n'; } | solvm tail.sob
```

printed the demonstration and threw the input away, and `sha256sum` did the
same, for as long as either program has existed.

**Nothing here was ever going to catch that.** A pipeline typed at a prompt or
written into a corpus has its first byte ready before the program starts, so the
fourth case does not occur anywhere anybody would look. It needs a *slow writer*,
which is not a thing one constructs except on purpose. It was found by asking
what the old spelling had actually been answering — which is a question you only
ask when you are replacing something, and is the argument for replacing things
that already work.

### The lesson, which is not about terminals

**An enumeration of cases is a proof only if it is complete, and there is no
notation for the difference.** *Three cases, all correct* reads exactly like
*all the cases*, and the second is a much stronger claim than the first.

The check that catches it is not more care with the prose. It is to go and ask
what states the thing actually has, from the thing's own side rather than from
the list: **a pipe has four states**, and the fourth — no data, no end — is the
one nobody thinks of because it is the one that does not stay still. Every
example in this repository has the pipe already finished or already full.

That is the same shape as
[a sentence that was true when written](method.md#a-sentence-that-was-true-when-written-is-not-checked-by-anything),
one step earlier: not a claim that has gone stale, but a claim that was never
quite what it appeared to be, and that reads as complete because nothing in the
sentence marks where its edges are.

### Postmortem

**What went right.** The note-with-a-trigger cost one sentence to promote, and
the promotion was decided by a program rather than by anyone changing their
mind. And the three tests were written to be able to fail: a pseudo-terminal on
one descriptor at a time, all three symbols asked each time, nine answers of
which three are true and each a different one. A test that only ever saw one
stream answer would have passed with two of them swapped.

**What went wrong.** Nothing in this session — the defect was already shipped,
in two programs, described in three documents as not being one.

**What is worth carrying.** *Replacing something that works is how you find out
what it was doing.* The paragraph being retired had been read many times and
never audited, because there was no reason to audit it: the program worked. The
audit only happened because the message replacing it had to answer the same
question, and the two answers had to be compared.

## 2026-08-31 (night) — the first inner loop that is arithmetic, and the number it produced

The morning's survey had said what to write next and why, so this was the
shortest decision of the day: `sha256sum`, first off the list, chosen because
it is **not a text tool wearing a Unix name**. Sixty-four rounds of shifts,
masks and additions per sixty-four bytes and two syscalls a file, against
seventeen programs that all spend their time in `split`, `indexOf` or the
kernel.

### What shipped

`programs/sha256sum.sol`, the eighteenth program, with three checks —
`oracle.sh`'s corpus, a `-c` script, and one holding it against FIPS 180-4.
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done)
opened. A new section in [performance.md](performance.md), a paragraph in
[REFERENCE.md](REFERENCE.md), a rule in [method.md](method.md), and a scoping in
[ideas.md](ideas.md) that was not built. **Nothing was built in the machine**,
which is not the same as nothing being asked for: one entry opened and one
question was scoped and left, and `tail` had asked for `system:sleep` in the
afternoon and got it.

### The number, and how it stopped being an estimate

The question the survey said this program existed to ask was *what does this
interpreter cost per arithmetic operation when there is nothing else going on*.
The first answer available was 1.08 MB/s, which is a fact about SHA-256 rather
than about the machine, and the second was a count of sends done by hand down
the source, which is a fact about how carefully somebody counted.

**The third came from a flag that was not put there for this.** `solvm
--steps=N` stops a program after N instructions and exits 124 — built so that a
runaway program can be bounded — so the *smallest N that lets a run finish* is
that run's exact instruction count, and twenty-eight runs of a binary search
find it.

| bytes hashed | instructions | blocks | per block |
| ---: | ---: | ---: | ---: |
| 0 | 14,671 | 1 | |
| 64 | 28,049 | 2 | 13,378 |
| 640 | 147,767 | 11 | 13,302 |
| 6,400 | 1,344,947 | 101 | 13,302 |

13,302 per 64-byte block, and **flat from ten blocks to a hundred** — which is
what says the figure is the loop and not the setup, and is why the table has
four rows rather than one. 208 instructions per byte; the same search on a
megabyte answers 217,955,855 against 217,954,715 predicted, which is the fit
confirmed to five figures. Ten megabytes in 9.30 s: **234 million instructions a
second, 4.3 nanoseconds each.**

**The lesson is about the flag rather than the hash.** Every number in
[performance.md](performance.md) is a ratio, against CPython or against an
earlier Solveig, and the absolute cost of an instruction had never been asked
for because nothing needed it. It was reachable the whole time, exactly, with a
tool already in the box and used for something else.

### Three predictions from the survey, and how each came out

- ***Not impossibility*** — held. A 64-bit integer holds the sum of five 32-bit
  values with fifty-nine bits to spare, so mod-2³² arithmetic is exact and the
  mask is a narrowing.
  [3.12](ROADMAP.md#312-no-shift-can-produce-a-negative-integer) never comes
  near: the largest shift moves a value under 2³² left by thirty places. **That
  is luck rather than design** — SHA-512 rotates a 64-bit word and could not be
  written this way at all.
- ***The number*** — held, and produced something better than expected, above.
- ***An ergonomic report on the mask*** — held. It reads as bookkeeping, and the
  reason is not that it is hard: it is that it is not in the standard, so every
  line a reader wants to check against FIPS 180-4 carries a term FIPS 180-4 does
  not have. Twenty-three of them.

### And a third of the program was a method call

`rotr(x, n)` is the one thing SHA-256 does that the language has no message for.
Written as a method on the hash object it reads the way the standard writes it,
and it is called ten times a round.

| | a megabyte | |
| --- | ---: | ---: |
| `rotr` as a method everywhere | 1.36 s | |
| written out in the sixty-four rounds | 1.10 s | 1.24x |
| written out in the message schedule too | 0.92 s | **1.48x** |

**The arithmetic is identical in all three, and so is the digest out of all
three.** What the method cost was a frame and a return — **32% of the readable
version's running time**, nineteen points of it in the rounds and thirteen in
the schedule. That is a bigger single number than anything in the profiling that
led to the two interpreter changes on 2026-08-30 — and it is not lookup, which
[the inline cache entry](ideas.md#an-inline-cache-at-the-send-site) measured at
9.7% of the benchmark that asked for it. It is the call.

**This paragraph first said *a fifth*, and the review pass caught it**, which is
worth keeping because of *how* it was wrong rather than that it was: a fifth is
the rounds-only step, 1.24x, and it was quoted as though it were the whole. Two
numbers on one line, and the smaller one carried. Re-measuring on the shipped
file rather than on the evening's throwaway is what made the error visible,
which is the same rule as everywhere else on this page — check the thing that
ships.

The shipped program is the third row, with the first written out in a comment
above it and the measurement beside it. **A helper named for what it does is
right almost everywhere and wrong in the one loop that runs thirteen thousand
instructions per sixty-four bytes**, and a program that had not been measured
would have shipped the first row and run at two thirds the speed for a reason
nobody would have looked for.

### The check that does not depend on anyone else being right

`sed` and `tail` were held against `/usr/bin/sed` and `/usr/bin/tail`, and that
was the decision that made the morning. It has a limit that was not visible
until a program had a second kind of authority available: **an oracle can be
wrong in the same direction as anything derived from it.**

SHA-256 has numbers printed in a standard. `programs/sha256sum/vectors.sh` runs
five of them, including a million times `a`, and they were printed before this
language existed.

**This is the second time that has been done here and the first time it was
noticed as a kind**, which is the correction this entry earns. `basic.sol` is
held against the [NBS Minimal BASIC Test Programs](../programs/basic/conformance.sh),
208 programs written at the National Bureau of Standards in 1980, and they found
seven defects that eighty-three author-written claims had not. The draft of this
paragraph called `vectors.sh` the first of its kind and was wrong — caught by
going to look rather than by remembering, which is the only way this sort of
claim ever gets caught. What is genuinely new is smaller: a digest is a string,
so the comparison runs by machine, where the NBS programs print what a correct
result looks like for a person to read. The oracle then earns its keep on a *different* class of
fault: a NUL lost, a high byte sign-extended, a chunk boundary landing inside a
block, a warning that says "1 line is" where the other says "2 lines are". **Two
checks that fail for different reasons are worth more than two that fail for the
same one**, and that is now in [method.md](method.md).

It earned itself twice inside ten minutes.

**Once against this program.** The `-c` code dropped every empty piece of the
split, under a comment saying *a blank line is not a malformed line in either
tool*. That sentence had not been tried. It is false: `/sbin/sha256sum -c -w`
numbers a blank line and counts it. The comment was written by somebody thinking
about the trailing newline and generalising from it — the fifth instance in two
days of
[a sentence that was true about the thing in front of the writer](method.md#a-sentence-that-was-true-when-written-is-not-checked-by-anything).

**Once against itself.** In `-c` mode the oracle reports a missing file as
`sha256sum:  nosuch.txt: ...`, two spaces, having kept the separator that stood
in front of the name in the list. Matching an oracle byte for byte is a means
and not the point, so `check.sh` records it as a divergence rather than copying
it.

**And a third difference that is not one**, worth knowing before the next of
these is written: captured with `2>&1` the two tools interleave the `WARNING`
line and the per-file lines differently, because the oracle's standard output is
block-buffered when it is a file and its warning is not. Both streams are
identical when kept apart. `programs/oracle.sh` merges them, which is one of two
reasons a `-c` corpus could not have lived there.

### Two triggers, and the honest one is the second

**The `isatty` note fired**, and it is the rule working in the direction that is
hardest to see. `tail` found in the afternoon that `keyWaiting(0.0)` answers *is
standard input a terminal* by accident, and wrote it down as a **note with a
trigger** rather than arguing it into a roadmap entry on the spot: one caller,
an exact workaround. `sha256sum` hit the identical collision — the house rule
says demonstrate on input you carry, `... | sha256sum` says read standard input,
both are an empty command line — and the promotion to
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done) cost
one sentence, because the reasoning was already on the page.

**Writing that entry then found the machine had the other half too.**
`system:terminalSize` calls `ioctl` on standard *output* and answers nil when it
fails, so `terminalSize:notNil` is `isatty(1)` today. The note had predicted
`keyWaiting` "cannot answer at all" about output — right about `keyWaiting`,
wrong about the machine. Checked through a pseudo-terminal both ways rather than
read out of the source, which is what turned it from a guess into a sentence.

**The second trigger was not a trigger and was scoped instead.** A `-z` checksum
list has entries ending in a NUL, and reading one found that **a path with a NUL
in it is silently a different path**: a Solum string is length-counted and may
hold one, a path handed to the operating system may not, and every filesystem
message answers about the prefix. The program printed
`h.txt<NUL>e258...  w.txt: OK` — **with the right digest**, because `fileExists`
and `readFile` had quietly agreed with each other about a file nobody asked
about.

A wrong answer that agrees with itself is the expensive kind, and this language
usually refuses rather than guessing. But the workaround here is exact — cut the
name at the first NUL, which is what a filename *is*, and the oracle does the
same — so the entry went to [ideas.md](ideas.md#a-path-with-a-nul-in-it-is-silently-a-different-path)
with a trigger and the check that would refuse it was not written. What *was*
written is the sentence in [REFERENCE.md](REFERENCE.md), because the paragraph
next to it says a NUL is a byte like any other and is about a file's contents,
and nothing said the path is the one string in the system that stops.

### The review pass, which found more than the writing did

Reading the day's own work back before calling it finished, against the code
that ships rather than against the notes.

**A headline number was wrong by a factor.** *A fifth of the program was a
method call* should have said *a third*: a fifth is the rounds-only step and it
was quoted as if it were the whole. Both numbers were on the same line of the
evening's notes and the smaller one carried. Re-measuring the three variants of
the *shipped* file — rather than the throwaway they were first measured on —
is what made it visible, and it also moved every rate a little: 1.08 MB/s
rather than 1.04, and 234 million instructions a second rather than 227,
because the first megabyte timing had startup in it and three samples.

**A claim of being first was not checked and was false.** `vectors.sh` was
called the first check here that does not depend on another implementation being
right. It is the second: `basic.sol` is held against the
[NBS Minimal BASIC Test Programs](../programs/basic/conformance.sh), 208 files
written in 1980, which found seven defects that eighty-three author-written
claims had not. The real difference is narrower and more useful — a digest is a
string, so the comparison runs by machine, where the NBS programs are written
for a person to read.

**A defect, found by trying the case rather than by reading it.** A directory
named inside a `-c` list was reported as *No such file or directory*, where the
same directory named on the command line was reported as *Is a directory* — the
oracle's answer in one place and not the other. `fileExists` deliberately
answers false for a directory, so `isDirectory` has to be asked first; one of
the two copies of that three-line decision had been corrected during the
writing and the other had not. **That is
[5.5](COMPLETED.md#55-five-programs-each-wrote-the-same-cursor--done) at a scale
it was not written about**: not five programs over weeks, but two blocks in one
file in one afternoon. There is one `path:complaint` now.

**And `differ/` was empty, which was itself a claim.** The corpus said 21 cases
agree and said nothing about anything that does not — while `-Q`, `--binary`
and `--tag` all diverge, and nobody had written them down. The last two are the
interesting ones: **the tool's usage line is a true sentence about a smaller
thing than the tool.** `/sbin/sha256sum` says `[-bctwz]` and also answers to ten
long options it never mentions, three of which have no short form. This file's
header had quoted that usage line as though it bounded the tool. Three
`differ/` cases now, so the subset is something that fails rather than a
sentence nobody rechecks.

**A comment that said *measured* and was not.** The chunk size carried "the size
makes no measurable difference — at one megabyte a second the read is not what
this program is waiting for", which reads like a measurement and was a
plausible-sounding guess. It is wrong: 64 bytes a chunk is **62% slower** than
64 kilobytes on a megabyte.

The reason is the better half. **A ranged read costs about 30 microseconds
whatever it reads** — one byte and sixty-four kilobytes measure the same,
because the cost is the `fopen` — while `fileSize`, `fileExists` and
`modifiedAt` cost **0.65**, having only to `stat`. Forty-five times, and having
no handle means every call pays it again.

**That is the price of the shape 3.22 chose, and the second caller is what found
it.** `tail` was written to check the call and reported that it wanted nothing,
which holds — it reads once or twice per invocation and an open per call is
invisible at that rate. This one streams and pays it 16,384 times a megabyte.
The chunk size stops being an arbitrary constant and becomes the thing that
amortises the open.

**And it does not reopen the decision**, which is the part worth being careful
about. Plain C doing the same `fopen`, `fread` and `fclose` on the same file
measures 28 microseconds, so the cost is the machine's and a handle would move
it rather than remove it — while buying back exactly the lifetime the entry
refused. What it argued for was a sentence, now in
[REFERENCE.md](REFERENCE.md#a-range-of-a-file) and in
[3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done).

**And one check was shown to fail rather than assumed to.** `pipenames:` is the
escape added to `programs/oracle.sh` for a program that names its input: the
pipe's output must be the file's with the path replaced by a dash. That is only
worth having if it can fail, so it was made to — a `sha256sum` whose
standard-input path drops its last partial chunk is a defect *no other check
here would see*, since the named-file route is untouched and the oracle is never
asked about the pipe. It is reported on most of the corpus at once. **What would
have to be broken for this to fail** is a question with an answer now, rather
than a hope.

**What the pass says about the day.** Every one of the five came from doing the
thing rather than re-reading the note about it — re-measuring, going to look at
`conformance.sh`, running `-c` on a directory, typing `--tag`, timing a chunk
size instead of asserting one. None would have
been caught by reading more carefully, which is the same conclusion this page
reached twice already this week and is apparently a lesson that needs learning
on each new kind of work.

### Postmortem

**What went right.** The survey did its job: an entry written before the program
predicted three things and all three held, which is the first time that has
happened here with nothing left over. The program compiled and produced all
three FIPS vectors on its **first** run, which says the arithmetic was never the
risk — every hour of the evening went on the plumbing, the options and the
checks, and that is the correct ratio for a specified algorithm.

**What went wrong, and it is the same shape as this morning.** A comment
asserting what "either tool" does, written without running either tool. It cost
nothing because the oracle caught it in the same session; it would have shipped
otherwise, and it is the fifth instance in two days.

**What was nearly missed.** The `-z` NUL case was found by a check written for
completeness rather than by suspicion — a two-entry `-z` list, added to `-c`
because it was cheap. The failure it exposed printed `OK`. The review pass then
found five more, above, one of them a number in the headline and one of them a
comment that said *measured* about something nobody had measured.

**What is worth carrying.** *Measure the helper.* The rotate cost a third of the
program and looked like the most obviously correct line in the file. Nothing
about reading it would have raised the question; the only reason it was asked is
that this program has one loop and a stopwatch pointed at it.

## 2026-08-31 (postmortem) — the day an oracle was pointed at this language, and four sentences fell over

**This was written as the day's postmortem and the day was not over**, which is
left as it stands because the entry is about exactly that failure. It counted
*three entries above this one* and there are now five; it said the day *ended*
with two roadmap entries closed and one opened, and the day went on to write an
eighteenth program, open and close a sixth entry, and find six more sentences of
the kind this entry is about. The closing account is
[at the top](#2026-08-31-closing--a-day-of-working-code-and-eleven-wrong-sentences-about-it).

The day began with *there are a bunch of Unix tools we could try to make and see
if they add anything*, and by this point had two roadmap entries closed, one
opened, a defect fixed in a shipped library, and a new message on `system`. What
connects them is one decision taken in the first half hour.

### What shipped

`programs/sed.sol` and `programs/tail.sol`, the sixteenth and seventeenth
programs. `system:readFile(path, from, count)` and
[3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done) closed with it.
`system:sleep`, the 142nd message. A defect fixed in `lib/pattern.sol`.
`programs/oracle.sh`, and `programs/tail/follow.sh`.
[6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done)
opened. A survey of which tool to write next, in
[ideas.md](ideas.md#which-unix-tool-next-and-what-each-would-press-on--surveyed-2026-08-31).

### The decision that made the day

**Hold the program against the one already on the machine**, rather than against
a transcript.

That is not a new idea here — [sola](../programs/sola.sol) does it with
QuickBASIC and [pascal](../programs/pascal.sol) with `fpc` — but both of those
oracles have to be installed, and `sed` and `tail` have been on every Unix since
before this project's author was born. The cost was three lines of shell, and it
paid in ninety seconds.

**Everything else in the day is downstream of it.** The `pattern.sol` defect, the
BSD blank-line-before-a-heading, the confidence to say `tail` asked for nothing —
none of those is available to a program checked against what its author expected.

### Four sentences that were true when written

This is the part worth carrying, and it is the second day running that the
postmortem has come out this way.

**`pattern.sol`'s worked example** stood beside the defect and could not show it.
`s/x*/-/g` over `abc` is correct under both the rule that was there and the rule
that was missing, because the star never matches a character in `abc` and so no
match has an end for a later empty one to land on. Careful, correct, and blind by
construction.

**3.22's trigger** said *a program with a file that does not fit*, and *nothing
here has one*. That was a fact about this repository's inputs rather than about
the world, and it had been sitting in the entry for weeks. A sparse file is 3 GB
and 8 KB of disk. Four seconds.

**Four count markers** sat on statements about past releases, so a moving message
count would have quietly rewritten what 0.38.0 answered. `releasing.md` states
that exact rule and had never been applied to the README's own history. Unnoticed
for four releases because the number happened not to move.

**And the roadmap's own summary** said *nothing is on it* while an entry was
being written into it — found while writing this.

Four instances of one shape in one day: **a statement that stays technically true
while the world moves underneath it**. Yesterday's postmortem said the same about
five documented claims of which four were wrong. It is now in
[method.md](method.md#a-sentence-that-was-true-when-written-is-not-checked-by-anything)
rather than being rediscovered a third time.

### What was got wrong, and in what order

**A scoping recommended the wrong order**, and the correction came from a
question rather than a test — *the idea of writing tail was to figure out how to
handle large files?* Yes, and the evidence had already arrived without any tail.
A `tail` on the whole-file read cannot call the thing it is meant to be asking
about, so the program meant to inform the design was the one guaranteed not to.

**A prediction was right about an absence and wrong about its price**, by
reasoning from `stty` at 7 ms an ask to a fork at 2.23 ms without noticing that
one happens per keystroke and the other per second. A cost is an operation *and a
rate*.

**Two checks were written wrong before they were written right**, both mine and
both in the shell: one passed `$args` unquoted in zsh, which does not word-split,
so a multi-file comparison reported a difference that was the harness; one used
`\(...\)` in a pattern language whose own header says it has no groups. Neither
reached a document, and both are the hazard `method.md` already names — a check
that fails for the wrong reason misleads as far as one that cannot fail.

### The honest accounting on what the programs found

**sed found a great deal**: a library defect, a price for reading files whole, a
bit `readLine` cannot report, and two limitations that cost nothing.

**tail found almost nothing, and that is the result rather than a
disappointment.** It was written to check a call rather than to ask for one, and
the call wanted no change of any kind. The scoping had deliberately kept *it
found nothing* on the table as an available answer, which is the only reason that
sentence is worth anything now.

**One thing tail did find had nothing to do with files**: no arguments means two
things in that program and in no other here, and the nearest thing this language
has to `isatty` turned out to be `keyWaiting(0.0)` — which works *because* of the
answering-true-at-end-of-input property that is a nuisance everywhere else.

### What is set up for tomorrow

Nothing is half-built. The survey in `ideas.md` names `sha256sum`, `diff` and
`gzip -d` with a prediction apiece, and says why the three of them are the axes
nothing here has touched: pure arithmetic, an algorithm over two inputs, and
array-heavy work. It also names the ones worth skipping and why, which is the
half of a survey that usually goes unwritten.

**The counter-argument is in it too**, because it belongs there: every text tool
added makes *there is no geometry anywhere near this language* truer and more
misleading at once, and two of the three recommendations are numeric experiments
wearing a Unix tool's clothes.

---

## 2026-08-31 (evening) — a prediction that was right about the absence and wrong about the price

`tail` shipped in the afternoon without `-f`, and the entry said why: no
`system:sleep`, `keyWaiting` cannot stand in for one, and **the finding would be
the price** of forking `/bin/sleep` — the way the terminal's size turned out to
be reachable through `stty` at 7 ms an ask, where the absence was never the
finding and the cost was.

The question that started the evening was *what's required to build `tail -f`?*
The honest way to answer it was to measure rather than to repeat the entry, and
measuring changed the answer.

### The half that held

`keyWaiting` cannot do it. Twenty asks of `keyWaiting(0.5)`:

| standard input is | twenty asks take |
| --- | --- |
| an idle terminal | 10.02 s — it genuinely waits |
| a pipe at its end | 56 microseconds — it spins |
| a pipe with something in it | 32 microseconds — it spins |

So a follow loop built on it works at a prompt, wakes on every keystroke, and
burns a core in every script, pipeline and service manager. Predicted, confirmed,
and now with numbers rather than reasoning.

### The half that did not, and how it went wrong

A fork of `/bin/sleep` measured **2.23 ms**. At a one-second poll that is
**0.22%** — perfectly livable. `tail -f` would have shipped on `shell:run` with
nothing to report.

**The prediction was not wrong about the numbers; it never had any.** It was
wrong about the *analogy*. `stty` was a fork **per keystroke**; this is a fork
**per second**. The entry reasoned from one to the other because both are *a
fork where a syscall would do*, and did not notice that the two differ by four
orders of magnitude in how often they happen. A cost is not a property of an
operation; it is a property of an operation and a rate, and the entry carried
only the first half.

That is the transferable part, and it is worth more than the feature: **when an
entry argues by analogy to a measured case, the thing to check is whether the
rate carried over, not whether the mechanism did.**

### So the case had to be remade

`system:sleep` was built anyway, on a weaker and truer argument: waiting is one
call to the kernel, a program should not have to start a process to do it or
depend on where a system keeps its `sleep`, and of the twenty-eight messages on
`system` it was the only obvious hole — `clock` and `time` could say how much
time had passed and nothing could spend any.

**Being right for the reason expected would have been worth less than finding out
the reason was wrong**, and the entry keeps both halves rather than being tidied.

### `-f` cost nothing else

Everything it needed was already there. `fileSize` notices growth without
reading; the ranged read from the morning collects exactly the new bytes, so a
poll is two syscalls and a short read rather than a re-read of the file. Five
seconds following an idle file costs 0.00 s of CPU, which is what `/usr/bin/tail`
costs.

### And the check the scoping said was impossible

The scoping left `-f` out partly because *an oracle cannot check a program that
does not stop*. That was true and was not a reason. **Give it a deadline**:
start both tails, feed the files on a schedule, stop them, compare what each
managed to write. Fifteen lines of shell.

**It earned itself on the fourth of six scenarios.** BSD `tail` puts a blank line
before the **first** heading when it is following, and does not when it is not.
That is not arbitrary — with `-f` the headings go on arriving, so the first is
one of a series rather than the top of a page — and nothing but a check that runs
the real thing would have found it. A day that had already been about oracles
finding what authors do not think to look for, finding it a third time.

### The smallest thing, and not the least

The message count moved for the first time in four releases, and that exposed
three Status paragraphs in `README.md` and one in `index.md` carrying the
**live-count marker on statements about past releases**. A count that moved would
have quietly rewritten what 0.38.0 and 0.39.0 answered.

[releasing.md](releasing.md) already states the rule, in as many words: a number
with a count marker is a *live* number, and a historical statement must not carry
one. It was written for the GitHub release page and never applied to the README's
own history. **It went unnoticed for four releases because the number happened not
to move** — which is the shape this project has now met three times in two days: a
thing that is technically true, and stays true, until the world moves underneath
it.

---

## 2026-08-31 (afternoon) — a wall measured in four seconds, and a program written to check rather than to ask

The morning's sed closed by saying [3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done)'s
trigger had still not fired: *a program with a file that does not fit*, and
nothing here had one. The afternoon began by asking which Unix tool to write
next, and ended with that entry closed and its first caller written.

### The four seconds

The plan was `tail`, on the grounds that it is the tool where reading a file
whole stops being a cost and becomes a wall. Before writing the scoping I made
the wall, to state it exactly rather than assert it. A **sparse file** is three
gigabytes of holes and eight kilobytes of disk:

```text
/usr/bin/tail -n 3   0.003 s, and the right three lines
system:fileSize      #3221225623, immediately
system:readFile      '...' is too large to read into a string
```

**The language could measure that file and not read a byte of it.** That is not
a cost, an inconvenience or a design tension; it is a wall, and it cost four
seconds and no disk to produce.

*Nothing here has a file that does not fit* had been in the entry for as long as
the entry had existed, and it was a fact about this repository's inputs rather
than about the world. Anybody could have made one at any time. Nobody had,
because nobody had needed to.

### The scoping was written, and then the scoping was wrong

`tail` was scoped into ideas.md's *Programs that would press on something*, with
a subset, three predictions and four calls — and it recommended writing the
program first and deciding the language change afterwards, because a program
asks and a page does not.

**The correction came from a question rather than from a test**: *the idea of
writing tail was to figure out how to handle large files?* Yes. And the evidence
for that had already arrived, above, without any tail.

What was wrong with the order is sharper than it being unnecessary. **A `tail`
written on the whole-file read cannot call the thing it is meant to be asking
about.** It would re-prove a measured wall and say nothing about whether
`readFile(path, from, count)` is the right shape, because it could not use it.
The program meant to inform the design was the one program guaranteed not to.

So the question splits: *whether* was settled and *what shape* wants a caller,
and a caller has to come after the call exists. Both recommendations are kept in
the entry rather than the first being overwritten, which is what that section
already does for predictions.

### The call, and the comment that decided it

The primitive is small — the old function already sought to the end and told the
position to size the file, so the ranged form is that function at one arity or
three. What was not small was the one real decision: **should a range that runs
past the end clamp or refuse?**

The language has both conventions. `first(#n)` and `last(#n)` clamp; `copyFrom`
refuses. So it looked like a matter of taste.

**It was settled by a comment already sitting in the function**, which is the
part worth carrying:

> *A short read is a failure rather than a shorter string: `fopen` on a
> directory succeeds on some systems, and reading one does not.*

Right for a whole-file read and **wrong for a ranged one** — a range that comes
up short is describing the end of the file, and the string that comes back says
its own size, so nothing is hidden. The policy that was there could not carry
over, which turns *clamp or refuse* from a preference into a fact about what the
two calls mean. `ferror` still catches the directory either way.

The other argument for clamping was a race — a file's size can change between
the `fileSize` and the read — and it survived contact: see below.

### Then the program, and it asked for nothing

`tail` is 223 lines and every one of them was written against a call that already
existed. Twenty-nine corpus cases byte-for-byte against `/usr/bin/tail`, each run
both by name and by pipe, seven more by hand for the several-file headings, and
the same commands on the 3 GB file. All identical. `tail -n 3` holds about two
megabytes whatever the file is.

**And it asked for nothing.** No extra argument, no convenience, no different
rule at the edges. The scoping had deliberately kept *it found nothing* on the
table as an available answer, and for the file API that is what it is — which is
worth a paragraph precisely because a page of findings is easy to write and a
clean bill is not.

### The three things it did report

**The predicted price was real and something already here paid it.** The entry
said a range's cost is that a record spanning two chunks becomes the caller's
problem. It is — and `split` counts a chunk's newlines while `join` puts back
exactly what `split` removed, so the offset of the last few lines inside a chunk
is arithmetic rather than a second search. Twelve lines. The entry had guessed
`scan.sol` would be the shape; `scan.sol` is a cursor over one string and never
came into it.

**The race argument for clamping was used, not just cited.** Two of the four
places this program reads ask for a whole chunk and take what comes, and both
are the ones that stream. Had a short range been refused, every chunk would have
had to ask `fileSize` and take a minimum first — the caller re-deriving a number
the call already had, with the race in the gap.

**And the finding that has nothing to do with files.** No arguments means two
different things in `tail` and in no other program here: the house rule says
*demonstrate on input you carry*, and `... | tail` says *read standard input*.
The same empty command line, two meanings.

`system:keyWaiting(0.0)` separates them, and it is **the nearest thing this
language has to asking whether standard input is a terminal**. It answers *is
there a byte right now*, and it is documented as true at the end of input — so a
pipe says true whether it is full or finished, and an idle terminal says false.
**That property is a nuisance in every other program and is exactly what was
wanted here.** Checked through a pseudo-terminal in both directions, because a
branch that cannot be reached from this harness is a branch nobody has run.

### Two smaller things worth keeping

**3.2 cost more this time, and in a different shape.** sed met *no non-local
return* as an early exit from a loop and reported honestly that it cost nothing.
`tail` meets it as a **guard** — three routines opening with a test for an empty
file, a zero count, a line number of one — and a guard with no `return` wraps the
whole body in an `ifElse` and closes with a brace at the far end. Still small.
Worth recording because the entry treats the two shapes as one thing and they
are not.

**The harness generalised on its second caller**, which is the ordinary way round
here: `programs/sed/oracle.sh` became `programs/oracle.sh` and takes the tool's
name. Nothing in it was ever sed's. It needed exactly one new escape, for `-v`,
where the heading names the input and a pipe has no name — and that escape buys
silence rather than a weaker check, so the case file has to earn it in prose.

### What the day was

Two entries closed and one program written to check rather than to ask, which is
not this project's usual direction and was right once. The thread running through
both halves of the day is the same: **the morning found that a documented example
was in its own blind spot by construction, and the afternoon found that a
documented trigger was a fact about our inputs rather than about the world.**
Both had stood for weeks. Both took seconds to falsify once somebody went and
looked instead of reading.

---

## 2026-08-31 — a Unix tool written to see what it would ask for, and the answer arrived in ninety seconds

The day began with a general proposal — *there are a lot of Unix tools we could
make and see whether they add anything* — and one of them picked, which is the
right shape for this: a program is the only thing here allowed to say the
library is short of something, and sed is a program with an unusually good
witness sitting on the same machine.

### Scoping it was worth the five minutes

Three sizes were put up. **The everyday half** — addresses, `s p d q = y a i c
{ }`, `-n -e -f` — was chosen over all of POSIX sed and over a bare `s///`
filter. The reasoning for the two that were refused is worth keeping.

*All of POSIX* adds the hold space and branching, and those are not more
commands: they are what make sed a stream **language** rather than a filter, and
they want a pattern space that is a two-line window and a program counter that
can jump. That is a different program under the same name.

*Bare `s///`* was refused for the opposite reason. `pattern.sol` already has the
matcher and the substituter, so a read loop around `replaceAllIn` is eighty
lines that exercise nothing — **it would have told the project nothing it did
not know**, which is the only test a program here has to pass before it is worth
writing.

### The oracle was the decision that mattered

Everything else about this day followed from one choice: hold it against
`/usr/bin/sed` rather than against a transcript.

[sola](../programs/sola.sol) makes that argument for QuickBASIC and
[pascal](../programs/pascal.sol) for `fpc`, and both say the same thing — a
check written by the author of the code can only catch what the author thought
to check. What is new here is the price. Those two want DOSBox or a Free Pascal
install; this oracle has been on every Unix since 1974 and is three lines of
shell away.

Sixty cases that must agree, three that must not, **and every one of them run
twice** — once with the input named as a file, once with it arriving on a pipe.
That second run is not thoroughness. `system:readLine` reads standard input a
line at a time and a named file is read whole and split, so the two ways into
this program are genuinely different code, and a stream editor that answered two
ways about the same bytes would be wrong exactly where one route could not look.

### Ninety seconds

The first run of the oracle reported twelve differences. Eight were the harness
or the cases — BSD sed refusing `-e 'a\' -e 'text'`, wanting `q;` before a `}`,
my own test written with `\(...\)` in a program whose header says it has no
groups. **Three were real divergences** and went into `differ/` with their
reasons. And one was this:

```
s/o*/-/g   on "alice   42  ok"

  sed:   -a-l-i-c-e- - - -4-2- - -k-
  ours:  -a-l-i-c-e- - - -4-2- - --k-
```

An extra dash, once, next to the only `o` on the line. It is a defect in
`pattern.sol` — reproduced immediately without sed in the picture, which is what
established whose it was:

```
pattern:on("o*"):replaceAllIn("aoc", "-")   ; "-a--c-", and every sed says "-a-c-"
pattern:on("o*"):countIn("aoc")             ; #4, and there are three
```

The star matches the `o`, and then matches **nothing** at the position the `o`
ended on, which is the same position seen twice. One condition, missing.

### What makes this one worth writing down

The rule beside it was there and was correct: a zero-width match must not stand
still, or the loop never terminates. The library's header explains that rule at
length and demonstrates it:

```
pattern:on("x*"):replaceAllIn("abc", "-")   ; -a-b-c-
```

**That example is the single case that cannot show the difference.** In `abc`
the star never matches a character, so no match ever has an *end* for a later
empty one to land on, and the rule that was present and the rule that was
missing agree at every position. Telling them apart needs a pattern that matches
something — and the example was written by the person who wrote the code, to
show the rule they were thinking about.

So this is not *the documentation was thin*. The documentation was careful,
correct, and had a worked example, and the worked example was in the blind spot
by construction. **The oracle made the argument for oracles**, on its own first
run, about itself. It took a stranger's program to pick a case the author would
not have picked.

The fix went into `substitutionIn` and again into `countIn`, which walks the
text separately and on purpose; each comment now names the other. Four cases
into [examples/matching.sol](../examples/matching.sol) so the checker holds it,
and the editor's 181 scripted sessions still pass — `edit.sol`'s `:s` goes
through the same code and has had the same defect for as long as it has existed.

### Two prices, measured rather than guessed

**A file cannot be read a line at a time**
([3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done)), and this is the
first program here that can put a number on it, because it does identical work
by both routes:

| input | lines | named file | standard input |
| --- | --- | --- | --- |
| 618 KB | 20,000 | 5.3 MB | 2.5 MB |
| 6.4 MB | 200,000 | 32.3 MB | 2.5 MB |

The stream is flat at 2.5 MB whatever the size. The file route is about **4.7
times the file**, where the entry says twice — twice is right for `readFile`
alone, and a line-oriented program holds a string object per line as well, which
the entry does not cover.

**And the trigger has still not fired.** 3.22 says it is *a program with a file
that does not fit*, and nothing here has one: this read 6.4 MB without
complaint. A stream editor that reads its input whole is embarrassing rather
than broken. The entry's *price* was wrong for this shape of program; whether to
pay it is unchanged, and saying so is the entry's own standard.

**The second price is one bit.** `system:readLine` answers a line without its
terminator and there is no way to ask whether there was one, so a file whose
last line carries no newline keeps that through the file route and cannot
through a pipe. Rather than hide it, three oracle cases carry a `pipediffers:`
line and the harness checks the difference is *exactly one newline* — a
divergence that is declared, bounded, and would fail if it grew.

### Two limitations that cost nothing, which is also a finding

[3.2](ROADMAP.md#32-no-non-local-return), no non-local return: `d` and `q` are
early exits from a command list, and the runner threads a verdict symbol through
its loop. Three lines longer than a `return` and no harder to read.

[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame), blocks that
cannot outlive their frame, **never came up at all** — because a compiled script
here is *data*, a command being slots rather than a closure. That is the shape
`pattern:item` already had and the shape this file reached for without deciding
to. A sed built as one block per command would have met 3.1 on its first line,
and the reason it was not built that way is that the file it was copying from
had already paid that lesson.

Reporting a limitation that did not bite is worth as much as reporting one that
did. A roadmap where every entry is a complaint is a roadmap nobody trusts.

---

## 2026-08-30 (postmortem) — the day the documents were audited by being used

Nine entries above this one, and the day had no plan. It began with a question
about Python's strings and ended with 0.40.0 on GitHub. What connects the two is
worth more than either.

### What shipped

`#["key" = value]`, a dictionary literal, over a `dictionary:of` built the hour
before it. `string:startsWith` and `string:endsWith`. An editor that had been
writing half a character to disk since the day it was written. Four constant
tables converted to the new literal and two deliberately left alone. 0.40.0,
released, verified and published.

### What the day actually was

**Five sentences standing in the documentation were tested. Four were wrong.**

`ensure` already existed where a gap was assumed. Decorators are writable, but
not the obvious way — a block pulled out of a slot has no receiver. A file's
memory edge is twice the file, and the doubling is `readFile`'s own
buffer-then-copy rather than the copy that `mirror.sol` blamed. *Nothing is
slower* was wrong by three orders of magnitude, because a search that fails has
read the whole string and failing is the case a prefix test exists for. And the
backtrace is not missing but discarded, one line after the error object is built.

**Not one was found by a program failing.** They were found by going to check a
sentence before repeating it.

Then the same thing happened to my own work. A guard I had just written against
a collector hazard was guarding against nothing, and `object.c` said so beside
the code. A comparison I ran twice could not have failed either time. A release
page passed every check on its markdown and rendered wrong anyway.

### The count, since counting is the point

| what was checked | wrong |
| --- | --- |
| documented claims tested | 4 of 5 |
| checks that could not have failed | 2 |
| findings that were artefacts of the check, not faults | 3 |
| entries in ideas.md corrected by measuring them | 4 |

The middle two rows are the ones I would not have predicted at the start of the
day, and they are the same failure wearing two faces: **a check that cannot fail
and a check that fails for the wrong reason mislead exactly as far as each
other.** One says everything is fine when nothing was examined; the other says
something is broken when nothing is.

### What was written down as a result

[method.md](method.md) exists now, which it did not this morning. The practices
this project runs on — a program asks rather than a document, the throwaway
before the design, scope before building, check the thing and not a picture of
it, check against what ships — were real, were followed, and were written
nowhere. Each is recorded with the occasion that taught it, because that is the
only reason to trust any of them.

[releasing.md](releasing.md) gained two steps from being followed once.
[ROADMAP.md](ROADMAP.md) gained [3.22](COMPLETED.md#322-a-file-is-read-whole-or-not-at-all--done),
a limitation that had been true and unstated for the life of the project, and
[2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only) now has a floor under
it rather than an open question.

### The thing worth keeping

Every document here is prose about work, and prose about work goes stale exactly
like any other prose. `expect.sol` executes a thousand claims on every build and
that is why the numbers can be trusted — but it can only check a claim it can
*run*, and *nothing is slower* is not one of those. Neither is *the guard is
needed*, or *the page renders*, or *this comparison compares two things*.

**The gap between what a checker can execute and what a document asserts is
where every one of today's errors lived.** Nothing closes that gap except
somebody going and looking, and the cheap version of that is refusing to write
*because X* until X has been run once.

The day cost nine journal entries and produced one release. It also produced a
document explaining how the work is done, which is the part that will still
matter when the release is four versions old.

---

## 2026-08-30 (0.40.0) — a release, and a procedure that learnt two things from being followed

[releasing.md](releasing.md) exists because two of its steps were learnt by
getting them wrong. Following it end to end got two more things wrong, in places
it had not covered, and both were found the same way as everything else today:
by doing the thing and looking at the result rather than reading the description
of it.

### The five examples that differed, and did not

The compatibility check compiles every example with the previous release's
compiler and this one and compares the bytes. It reported **five differing**,
which would have gone into the release notes as an incompatibility.

They do not differ. The 0.39.0 binary was unpacked in a temporary directory, so
it resolved `lib/` relative to *itself* — and an `@include` records the
library's path in the chunk, so the same library code carried a different name.
Copy the old `solas` beside the new one and it is 34 of 34 byte-identical.

The procedure already said *run both machines from the same working directory*,
for a different reason: four examples read the filesystem. It says it about the
compilers now too, for this one.

### Eighteen thousand lines, since before the last release

The procedure says a release is a good moment to read the front page as a
stranger would, because the checker recounts prose it can execute and a figure
inside a sentence is not one. Read it, and both `README.md` and `_config.yml`
have been claiming **18k lines of C11** while the count was 19,004 when 0.39.0
shipped and 19,126 now.

Not caused by this release — already wrong when the last one went out, and the
same failure as the site description that sat at *123 messages* through a rename.

### The page that rendered wrong, and could not have been read wrong

The one worth the entry.

The procedure has two fixups for the release body, and both were applied and
verified: the count markers stripped, since a release page is a historical
statement nothing recounts; and the links absolutised at the tag rather than at
`main`, checked by confirming `docs/ideas.md` exists at `v0.40.0` rather than by
trusting the string.

Then the page was opened.

**GitHub renders release notes with hard line breaks.** Every document here is
wrapped at 79 columns and each of those became a literal break — 41 across 8
paragraphs, a narrow ragged column inside a wide box, snapping mid-sentence at
*not to be / true*. It was published that way.

**The markdown was correct.** Every check on it passed and every check was
honest: 31 code spans intact, three italics right, one link absolute, no markers
left. There was nothing to find by reading, because there was nothing wrong with
what was read. The defect lived entirely in what the renderer did with correct
input.

That is the difference between checking a thing and checking a *picture* of it —
a lesson this repository already learnt about pixels, where it is written down as
[there is no oracle for a pixel](#2026-08-30-the-evening--a-demo-that-showed-the-measurement-was-of-the-wrong-thing).
It turns out to apply to a page of prose, where nobody expected to need it: the
markup can be provably right and the thing a reader sees still wrong. The
procedure now says: **open the page.**

### Two false alarms on the way, and one of them was the thread

*The tarball is missing from the page* — it is not. GitHub loads the assets
lazily and they are not in the initial HTML; the API says `uploaded`, 3,214,782
bytes, and the download URL answers 200.

*The third italic is missing* — it is not. It renders as
`<em>expected<br> digits after '#'</em>`, and the whitespace-normalising search
did not strip the `<br>`.

The second false alarm is how the real defect was found: the `<br>` I kept
tripping over **was** the symptom. But reporting either as a fault would have
been worse than not checking at all. **A test that fails for the wrong reason
misleads exactly as far as one that cannot fail**, and today has now produced
both kinds — two vacuous checks this morning, two false alarms this evening.

### The release notes describe the release, and then describe cutting it

The changelog says five claims standing in the documentation were tested and
four were wrong, and not one was found by a program failing. Cutting the release
found two more of exactly that kind — in the document that describes how to cut
it.

A procedure is prose about work, and prose about work goes stale like any other
prose. The only thing that keeps it true is somebody following it and noticing
where it stops matching what happens.

---

## 2026-08-30 (using it) — four tables converted, two that refused, and a check that could not fail

The literal existed for an hour and had no callers, which the entry that shipped
it said out loud. Putting it to work was the honest test, and the interesting
results were both negative.

### The tables that declined

`html.sol` has four constant tables and only two of them wanted a literal.
`entities` and `implied` converted cleanly. `void` and `raw` are **sets** —
nothing reads the value, and `true` stands in for a membership the language has
no type for:

```
"area base br col embed hr img input link meta param source track wbr"
    :split(" "):do({ name | html:void:atPut(name, true) }).
```

As a literal that is fourteen `= true`s. The split string is *better*, and it is
better for a reason worth naming: it is a list of names and it looks like one,
where a dictionary literal would spend half its width saying the same nothing
fourteen times.

So the note went into the file, because the obvious next thing a reader does is
finish the job. And the observation that came with it is the one I did not
expect: **a dictionary literal makes the missing set more visible, not less.**
Before today those tables looked like dictionaries built the only way there was.
Now they are the ones that had to be explained.

That is the first new argument the set entry has had in a while, and it arrived
from building something else.

### A check that could not fail

I compared html.sol before and after by recompiling a probe against each and
diffing the output. It said *identical*, which was true and meaningless:
`@include` resolves while compiling, so the probe's `.sob` had the old library
baked into it and I ran the same bytecode twice.

Recompiled properly the output really is identical, and the bytecode is 203
bytes smaller — fifteen `atPut` statements were fifteen global loads and fifteen
sends, where each literal is one of each.

**This is the second vacuous check today.** The first compared an editor
transcript against a path that no longer existed, and passed for the same
reason: nothing in it could have gone wrong. Both had the same shape, and it is
worth writing the shape down rather than the two instances — **a comparison
whose two sides came from the same source is not a comparison.** The editor one
was two runs of one binary; this one was two runs of one `.sob`.

The habit that has been catching wrong sentences in documents all day catches
this too, and it is the same question in both cases: *what would have to be
broken for this to fail?* If the answer is nothing, the check is decoration.

---

## 2026-08-30 (the literal) — a literal built, and a question asked twice on purpose

The entry before this one ended by refusing to convert `run` and `capture` to
dictionaries, and the refusal came with a promissory note: *if the literal is
ever built, this conversion is worth asking again.* It was built an hour later,
so it was.

### The half of the proposal that was never needed

The idea arrived as `@dict[key = value]` **plus** moving `@expr`'s equality to
`==` so that `=` was free. The second half was the interesting one to take
apart, because it looked like a prerequisite and was not.

`=` is scanned unconditionally; what it means is decided by whoever is parsing.
The lexer's mode flag exists for one operator and `lexer.h` names it — `-`.
So inside a region `=` is equality, outside one it is a stray operator, and
inside a dictionary literal it is the literal's own, and none of the three ever
meets another because each carries its own delimiters. The whole cost was one
flag on the compiler, saved and restored around the key so that nesting works.

Spending `==` would also have cost coherence: `:=` assigns and `=` compares here,
which is one convention, and keeping `:=` while taking `==` is half of C and half
of Pascal.

### A bracket, not a brace

The one place this parts company with the languages a reader arrives from.
Python, Ruby, JavaScript and Perl all write a table in braces. Here `{ }` is a
**block** — code — and `[ ]` already means a collection written out. So `#[` it
is, and the familiar spelling was the wrong one to borrow.

`#[` being a single token is what makes it free: a digit was the only thing that
could ever follow a `#`, so `#[` was a lexical error in every file ever written
here and can be given a meaning without taking one away. `# [` with a space is
still refused, and the old complaint now points at the new thing.

### The grammar files were agreeing with each other and not with the compiler

`make test` says *GRAMMAR.md and solum.bnf agree on N productions*, and they did
— both silently missing the literal I had just implemented. The check is
agreement between two documents, not agreement with the code.

What caught it was the other check: `check_syntax` runs `solum.bnf` against real
files, and it rejected `examples/dictionaries.sol`. That needed two fixes, and
the second was a lesson the compiler had not needed. In the BNF the key must be
a `sum` rather than an `expression`, or it swallows the `=` that ends it —
`comparison` is where `=` lives in that grammar. Nothing is lost, since a
comparison is only legal inside a region and a region is a `primary`.

**Two documents agreeing is not the same as either being true.** The BNF is only
honest because something runs it against files that must parse.

### Asking the same question twice, and getting a better answer

Yesterday's refusal of the `run`/`capture` conversion rested on two grounds:
thirteen characters a call site, and a lost error. The literal was built for
independent reasons, and it demolished the first ground — thirteen became two.

So the question was re-asked with the ground gone, and the answer is still no,
on the half that never depended on spelling: a dictionary deduplicates on the
way in, so `'capture' is given "stderr" twice` would arrive as one setting and
be obeyed. **An argument bag is not a degenerate dictionary.**

That is a better refusal than yesterday's. Yesterday's had two reasons and one
of them was about typing; today's has one reason and it is about meaning. A
verdict that survives losing half its argument is worth more than the one that
had two.

---

## 2026-08-30 (last) — a literal proposed, a message built, and a guard taken back out

Proposed: `@dict[key = value, ...]`, with `@expr`'s equality moved to `==` so
that `=` was free for it. Two halves, and taking them apart was most of the
value.

**The freeing was not needed.** `=` is scanned unconditionally and given meaning
by the parser's context — the lexer's mode flag exists for one operator and
lexer.h names it, `-`. Regions carry their own delimiters, so `@expr(...)` and a
`@dict[...]` could never have overlapped. And spending it would have cost
coherence: this language assigns with `:=` and compares with `=`, which is one
convention; keeping `:=` while taking `==` is half of C and half of Pascal, and
strands `<>` into wanting `!=`.

**And the literal turned out to be sugar over a message that did not exist.**
`[#1, #2, #3]` has no opcode — a global load and a send of `of` — and times the
same as writing `array:of` by hand. So the array literal is *itself* a spelling,
and the order was obvious once that was measured: build `dictionary:of`, and let
use rather than taste decide the literal later.

### The guard that was not guarding anything

The first draft rooted the new dictionary against the collector, reasoning that
`sol_dict_put` grows its entries and growth allocates.

It does allocate. It cannot collect — and object.c already said so, in a comment
sitting beside the code doing it: *calloc and free rather than a heap
allocation, so nothing can be collected in the middle of the rebuild.*

What is worth recording is how that was found. The root was removed, the build
re-run, and 200 dictionaries and a 120-pair one driven under `SOLUM_GC_STRESS`
— which found no difference, because there was none to find. **A guard against a
hazard that is not there is worse than no guard**: it costs nothing at runtime
and it tells the next reader the hazard exists, which is a false thing written
in the most trusted place a false thing can be.

That is the day's habit applied to my own code rather than to the documents. It
had already caught four wrong sentences in the docs; this is the fifth, and I
wrote it an hour earlier.

### Built with no caller, and saying so

Every `dictionary:new` in this tree is an accumulator filled a key at a time, or
a named table of blocks. Neither is the inline shape, so nothing here calls the
new message except the demonstration in the example that teaches dictionaries.

The usual bar on the ideas page is *a program asked*. This was built because a
literal would compile to it and because it was asked for — which is a different
and weaker reason, and the entry says so rather than dressing it up. The honest
test is whether the next options bag written reaches for it.

---

## 2026-08-30 (later) — a survey that kept correcting the page it was written on

Started as a question with no task in it: *are there features in Smalltalk,
Ruby or Python we might want?* The useful answer was that
[lineage.md](lineage.md) already says ideas.md carries that survey, and names
the languages it covered — Smalltalk, Self, Io, Lua, Ruby. **Python is not among
them**, because when that was written Python was not in the project. It is now,
as nine benchmark pairs. It arrived as a stopwatch and was never asked what it
has.

Writing that survey, and then chasing four of its five open items, produced the
day's actual shape: **five claims in the documentation were tested and four of
them were wrong.** Not one of them was found by a program failing. They were
found by going to check a sentence before repeating it.

### The four

**`ensure` already existed.** Went looking for a `finally` gap in the survey and
found the feature shipped. Half an hour saved by grepping before writing.

**Decorators are writable, but not the way anyone would first write them.**
`counter:slotAt('bump):value` answers *nil does not understand 'count'*, because
`value` runs a block with **no receiver** and a method's `self` is bound by the
*send*. The working idiom reinstalls the original under a second name and sends
it. The error is the part worth documenting, not the recipe.

**A file's edge is not where its own program assumed.** mirror.sol had said for
weeks that a large copy *holds it in memory twice* and that it is worth knowing
where the edge is rather than discovering it. Nobody had looked. It is 2 GB
hard, and twice the file transiently — but the doubling is `readFile`'s own
buffer-then-copy, not the copy: `writeFile` streams from the string it was
handed, so a copy peaks exactly where a bare read does. The rule is twice the
largest *file*, not twice the largest pair.

**Named arguments were refused after being recommended.** The survey called this
the one item with a customer and said the options array's pairing is *positional
and silent*. Every way of getting it wrong is caught, each by name, with the
alternatives listed. One case is silent and is a deliberate trade the reference
had already reasoned about — a string is always a path, which is what keeps a
file called `discard` a file. Then the spellings settled it: `name:` is not a
free slot but an existing valid parse, `:` being the send operator, so
Smalltalk's own spelling is the one this language cannot have.

**And the backtrace is not missing, it is discarded.** `append_stack_trace` runs
at raise time; `onError` builds the error from the message and clears the trace
on the next line. The capture is already bounded and already paid for — a
microsecond, flat at stack depths 0, 30 and 200. What is missing is a reader:
fifty-nine `onError` sites, and every handler that wants to say *where* tracks
its own position, because a stack trace answers *where in the code* and they are
all asking *where in the input*.

### The one that was built, and what it broke

`startsWith` and `endsWith`, deferred the day before with one customer. Counting
found three programs, nine call sites, and **two independent copies of
`endsWith`** — and expect.sol's copy carries a note saying its absence had
already produced a defect. The deferral's reasoning, that `indexOf` is the same
question and no slower, is wrong by 2000× on the case a prefix test exists for:
a search that fails has read everything.

**Including the new library into expect.sol broke expect.sol**, and that is the
best thing that happened today. It reports `integer:slots:size` as the number of
messages an integer answers; text.sol puts two methods on `integer`; the figure
moved 37 to 39 and the checker caught its own contamination on the first run.
The rule was written nowhere: **a program that measures a class cannot measure it
after loading a library that extends it.** scan.sol had never shown it, binding
an object and adding nothing to a built-in.

### What this says about the practice

Four of five wrong, and every one wrong in the same direction: a plausible
sentence written next to the code it describes, never run. The repository has
`expect.sol` precisely because prose goes stale — and `expect.sol` only checks
prose that *makes a claim it can execute*. "Nothing is slower" is a claim; it
is not one the checker can see.

The cheap habit that caught all five is not a tool. It is refusing to write
*because X* in a document until X has been run once.

---

## 2026-08-30 (late) — a question about Python, and the defect that answering it found

No task today, a question: *Python has unicode strings and Solveig is ascii-8?*
Roughly right, and the honest answer needed the second half spelled out — a
string here is bytes, 0 to 255, with no encoding attached, which is `bytes` and
not `str`. Nothing in the VM interprets a byte except the two ASCII case ranges
and the digit parsing.

**Then: "so this area is a bit undeveloped at the moment?"** Also roughly right,
and the interesting part is that the two halves are in completely different
states. The byte layer is not undeveloped at all — twenty-five messages, regular
expressions, a scanner, JSON, HTML. The Unicode layer is one direction of one
conversion: `integer:asUtf8` encodes, and **nothing in the tree decodes**.

### Three documents pointing at a decision none of them owned

`$character` literals defer to *what a string is*. Roadmap 2.13 files it as a
restriction rather than a question. performance.md says the strings row does not
compare like with like and leaves it. Three pointers, no entry — so the ask was
to write one, which is where the day stopped being about documentation.

### The write-up went looking for a customer and found a live defect

An entry recommending that strings stay bytes needs a program that has actually
been hurt by that, or it is an argument with itself. The editor was the obvious
place to look, because its own notes say **a tab is one byte and eight columns,
and everything that positions a cursor holds both numbers at once**.

An `é` is two bytes and one column. Same sentence, numbers reversed. Driven with
scripted keys, `$x` on `café` wrote `caf` and a lone `0xC3` to disk — half a
code point, silently — and the escape it drew for `$` on `café x` was `ESC[1;7H`
when the `x` is in column six.

**Four days of building that editor never asked the question its own design note
had already framed.** Not a subtle bug: it corrupts a file, in the program whose
whole job is not corrupting files. It survived 165 scripted sessions because
every one of them is ASCII.

**This week has run the other direction twice** — a throwaway program correcting
a document, on the SDL present policy and again on the graphics entry. This is
the same trade in reverse, and the reverse is the cheaper one: the throwaway had
to be written, while the document only had to insist on a real example instead of
a plausible one. Going and getting that example is a test nobody wrote, and it
cost the time it takes to type `$x`.

### The proposal, and the program that answered it

Asked next: a `text` type beside `string`, with `$"unicode text"` making one.

It is better than it sounds, and the entry says so at length before objecting.
Its polarity is Python 2's rather than Python 3's — bytes stay the default —
and Python 2's version failed on *implicit coercion*, which this language
already refuses on principle. And it is the only design where `copyFrom` cannot
split a code point, which is genuinely stronger than what I had recommended;
that went into the entry as a correction, not a footnote.

**What killed it came from the same program.** The coherent version decodes at
the boundary, and decoding needs an answer for a byte that is not valid UTF-8:
raise, and an editor cannot open a Latin-1 file; substitute U+FFFD, and it
silently corrupts on write — worse than the bug being fixed. vi opens anything.
So the editor would decline to hold the new type, and a type the real programs
decline to hold is a type that rots.

The proposal and its refutation both came out of the same afternoon's evidence,
which is the most useful thing that happened today.

### Two guesses at a sigil, two collisions

`$` is the hexadecimal prefix. `&` was the next guess and is logical *and*
inside `@expr`. Both were forgotten in the asking, and it is worth knowing why:
between the bases and the infix work, the lexer's switch takes twenty-six
characters, and with `;` for a comment and `\` inside a string that is
twenty-eight of the thirty-two ASCII punctuation marks. Four are left — `!`,
`?`, `_` and a backtick — and `_` belongs to identifiers while a backtick fights
the prose it would be written in.

**The page spells it `!` now**, so that a future reading of the argument is not
also a puzzle about which `$` is meant. A spelling is the cheapest thing in that
entry to change, which is exactly what happened to it.

### The fix, and an estimate wrong by a factor of five

The entry had said the editor needed *nine lines in `expand`*. It needed
seventeen definitions and four new helpers.

`expand` was barely one of them — it draws the bytes, so the column count had to
move out into a `widthOf` beside it, and `visible`, which sliced the drawn text
with a `copyFrom` because a column was a byte, became a walk. What the estimate
got right is the part the decision rests on: `isTail` really is
`bitAnd(#192):equals(#128)`, and nothing in the language moved.

Two places carried the weight, and both already existed. One loop in `clamp`
makes *a cursor is never inside a character* true for every command at once. One
`add` in `operateChars` turns an inclusive motion's last character into a range,
which is `d$`, `de`, `dfx` and `x` in a single line.

**And insert mode had to be exempt.** `readKey` delivers an `é` as two separate
keys, so the column must be allowed to stand between them while it is typed.
That exemption is the sharpest evidence in the entry for keeping the invariant in
the program rather than in a value — a `text` type could not have had it.

### The regression the test suite could not have caught

`a` and `p` were correct before this work and broken by it. On the old editor
`$` landed on the last *byte*, so appending after it happened to be the end of
the line — right by accident. Fixing `$` to land on the lead byte turned that
accident into `caf` + `0xC3` + `Z` + `0xA9`.

All 165 existing sessions passed at every stage of the change, because they are
ASCII and could not see it. What caught it was running a probe by hand after
each step instead of trusting the green suite — and the reason to distrust it
was knowing *why* those tests are green, which is not the same as knowing that
they are.

Sixteen sessions were added; eleven fail on the editor as it stood. That number
is the one worth recording: five of the sixteen would have passed before the fix
and are regression guards rather than reproductions, and saying which is which
is the difference between a test suite and a pile of assertions.

### And what did not change

A string is still bytes. `size` still counts them, `"café":size` is still 5, and
text.sol still has no decoder — the fix never wanted one. The screen transcript
is byte-identical, sideways-scrolling tab line included.

The recommendation arrived as evidence rather than as an argument: the program
that finally asked for Unicode asked for it locally, in the two places facing a
screen, and answered itself with three sends the language already had. The
trigger for a language change is now a *second* program copying those three
sends — not the inconvenience of having to.

---

## 2026-08-30 (night) — a canvas for GTK, and two bindings answering one question opposite ways

Asked for a circle example in solveig-gtk after the SDL one. **It was not an
example request, it was a capability request wearing one**: that binding had no
drawing at all. Seventeen messages, every one a widget — window, label, button,
box, `onClick`, `onKey`, `every` — and its README listed *no drawing area* among
what is missing. So there was nothing to write the example against.

The gap was named in the repository, which is the whole reason a README lists
what it does not do.

### The throwaway went first again, and again it was the design that needed it

Ninety lines of C, built, loaded, thrown away. The engineering was never in
doubt; **the design question was what a block draws with**, and it has a sharp
edge. A `cairo_t` is alive only for the length of one draw callback, so handing
one to the program hands out something that dangles the moment the block
returns — and a program that *stored* it would corrupt memory rather than get an
error, which is the worst kind of interface.

So the context is not published. It is held in the binding for exactly as long
as it is valid, and `colour` and `circle` ask for it; outside a draw block they
answer *'circle' outside a draw block — there is nothing to draw on*. That is a
different trade from every other message here, which takes its receiver openly,
and the file says so: the alternative cannot be made safe, not that an implicit
receiver is nicer.

The throwaway is what settled that it *is* safe rather than plausible. Calling
`gtk:circle` from outside a draw block was the first thing tried.

### The claim that was waiting to be tested

solveig-gtk's README has said since the day it was written that **the expensive
work was per-toolkit rather than per-function, and it is done** — widget
lifetimes, the main loop re-entering the VM, callbacks surviving collection,
limits still applying. *A new message is a primitive, an arity check and a line
in `sol_extension_init`.*

**The canvas is the first thing to arrive since that was written, and it is a
harder case than the ones the claim was made about** — not another widget but a
new *kind* of callback, one GTK drives on its own schedule. It needed nothing.
The draw callback re-enters through the retain registry and `fire()` exactly as
`onClick` and `every` do. The only new plumbing was a `GDestroyNotify`, because
`set_draw_func` does not take the GClosure notify the signal handlers use.

A prediction written down in advance, and the first case that could have
falsified it did not. That is worth more than the feature.

### The same request, and the two bindings disagree correctly

**A circle is one message in GTK and six lines of Solveig in SDL.** Cairo has
`cairo_arc`. SDL's renderer has rectangles and lines, so `circles.sol` there
works a disc out a row at a time — half the width of each row being the square
root of `r² - dy²`.

Neither is a defect in the other, and **the extension surface was deliberately
not grown in SDL** when a program finally asked for a circle: one customer
satisfied in six lines of the language is not a trigger, and a circle is a shape
every later back end would have had to match with nothing to match it by. Cairo
already has one, so GTK publishes it. Each binding says what its toolkit has.

That is
[no back end naming itself the general case](ideas.md#extensions-a-capability-from-a-binary-rather-than-from-the-vm)
turning up in something much smaller than a main loop, which is where a
principle is easier to violate without noticing.

**And the two examples are the same program and look nothing alike.** In SDL the
loop belongs to the program: move, draw, present. In GTK there is no loop —
`every` moves the balls and says the picture is stale, `onDraw` answers with a
picture whenever GTK wants one, and `gtk:run` is where the program waits.
Nothing in the GTK one presents, clears, or thinks about a buffer, because the
frame is the toolkit's business. Two files, one behaviour, no shared vocabulary.

### Looked at, and what looking found

Following [the evening's
lesson](#2026-08-30-the-evening--a-demo-that-showed-the-measurement-was-of-the-wrong-thing):
the window was captured mid-run, twice, a second apart. Four antialiased discs,
in different places in the two shots.

It found one flaw that reading would not have. **The physics used the size the
canvas was asked for, while `onDraw` is handed the size that actually
arrived** — so dragging the window bigger would have left the balls bouncing off
an edge that was no longer there. The draw block records the real size now, and
the example says why, because that gap between requested and actual is a thing
about GTK rather than a thing about this program.

The README's counts were re-derived rather than adjusted: 30 distinct `gtk_*`
functions called against 26, plus three cairo ones, and 23 messages against 17.

### Postmortem — the whole day

**Four things went wrong and three of them were the same thing: a check that
looked like it covered the output and did not.**

**A defect shipped, and Hans found it by running the program.** The Mandelbrot
example drew bands of noise. Three checks had passed before it was committed —
the arithmetic rendered as ASCII, the program run and timed, the colours
recorded as they were passed to `sdl:fill` — and **every one of them tested the
inputs to the drawing calls** while the defect lived entirely on the other side.
`sdl:present` does not preserve the buffer, and nothing that stopped short of
the pixels could have said so. A graphics program's output is a picture; the
check has to be the picture.

**A finding was written into two documents one step too early.** *The present
policy is worth more than a year of interpreter work on this program* came from
timing two renders against each other. Neither of them drew the Mandelbrot, so
the comparison measured what two call patterns cost and not two ways of drawing
the same thing. It was struck the same evening. **The measurement was real and
the conclusion was not**, which is the failure mode `ideas.md` was built to
catch and did not, because the number was true.

**Then the same lesson again, in the shape that gets past looking.** The circle
example's first version sent every ball off in the same direction. Two sampled
frames showed them clustered — and nearly explained it away, because the two
happened to be about one bounce period apart, and a periodic system sampled at
its own period looks stationary. **Looking is necessary and is not sufficient**:
a still frame answers whether a thing is drawn correctly, and only a measurement
over the whole run answers whether it moves correctly. What settled it was the
range each ball covers, which is a question about the trajectory rather than
about two moments of it.

**And `make` reported success without having rebuilt anything.** `CFLAGS` is not
a prerequisite, so setting it on an up-to-date tree relinks the previous build
and says nothing. Caught by looking at the binary's timestamp rather than by
anything that would have failed — the same shape as the week's Makefile
visibility check, which is the second time this has been the thing.

**What went right is worth the same paragraph.** The throwaway went first twice
and earned it both times. Against SDL it found in ten minutes that `present`
costs 8.3ms, which no amount of reading the header produces. Against cairo it
answered the only question that mattered — whether a drawing context could be
published safely — by trying the failure case first, before a line of it was
written into the real file. **Both times the engineering was never in doubt and
the design was**, which is the pattern this project keeps rediscovering: build
the smallest thing that settles the question, and let it correct the design.

**And the day's one refusal held.** A language change was proposed, scoped in
full, recommended — and not built, because no program wanted a screen. The
entry it produced is longer than the feature would have been and is the more
useful artefact.

---

## 2026-08-30 (the evening) — a demo that showed the measurement was of the wrong thing

Asked for a Mandelbrot example for solveig-sdl — a demo rather than a probe,
written in Solveig, to show the extension off. It found that the afternoon's
headline finding had been written down one step too early, and the step that was
missing is the oldest one there is: **look at the output**.

### What was wrong

The example rendered coarse to fine and presented every 16ms, exactly as
[the afternoon's probe](#2026-08-30-evening--the-foundation-exercised-and-a-question-that-answered-itself)
recommended. On screen it was bands of RGB noise with recognisable fragments of
fractal floating in it.

**`sdl:present` does not preserve what was drawn.** The buffer it hands back for
the next frame holds undefined memory, not the picture just shown. So a frame
that is not drawn in full cannot be shown at all: presenting every 16ms puts up
the strip drawn since the last present and stale video memory everywhere else,
which is precisely what the noise was. The bands in the screenshot were the
16ms windows.

Confirmed rather than assumed, in thirty lines of C against SDL's Metal
renderer: clear to red, present, then read back a pixel nothing has drawn into.
It is not red. That took two minutes and settles a question no amount of staring
at the Solveig would have.

### The measurement was real and the conclusion was not

The afternoon's table has three rows. The first — the arithmetic with no
graphics at all, 1.59s against 1.07s — is untouched, and the 1.49x it reports
still stands. **The other two were both drawing a corrupt picture.** Presenting
per row and presenting every 16ms are two ways of getting it wrong, and timing
them against each other measures what the call pattern costs rather than two
ways of drawing the same thing.

So *the present policy is worth more than a year of interpreter work* has been
struck out of both documents. What replaces it is sharper:

**The policy is not present less often. It is present only a frame that is
complete** — five presents on this program rather than a hundred and eighty. The
cost of getting it wrong is not a slow picture; there is no picture.

**And it makes the SolaBasic verdict firmer.** The afternoon said a faithful
`PSET` would run at 120 pixels a second on this surface. That was the optimistic
reading. A present keeps nothing, so `PSET` after `PSET` accumulates no picture
at all — each would show its own dot on a field of undefined memory. QBasic
assumes a screen that *stays drawn*. A renderer of this shape has none, so
immediate mode is not slow here, it is absent, and any `SCREEN` built on this
would have to buffer a frame and decide for itself when the frame is done. The
entry that recorded a "no" now records a better reason for it.

### What the example does instead

Five passes, 16×16 blocks down to 1×1, each one covering every pixel, each one
presented only when it is complete. The first frame is up in about ten
milliseconds and each replaces it, so it still feels progressive without ever
showing a partial frame — and the passes still drain the event queue between
rows, so a click abandons immediately. An abandoned pass is simply not shown.

Verified by making the program record what it draws and wiping the record on
every present, exactly as the real buffer is wiped: **five frames, zero undrawn
pixels in any of them.** Then by looking at two of them.

### And a third example, which is the trigger rule pointed at a surface

Asked for a bounce-style circle example after the Mandelbrot. `bounce.sol` moves
a square because a square is what `sdl:fill` draws; **there is no `sdl:circle`**,
so the interesting half of the request was what to do about that.

The program draws it. For each row of a disc, half the width is the square root
of `r² - dy²`, and that row is one `sdl:line` — six lines of Solveig, about sixty
calls for a ball of thirty. The extension was deliberately not grown to hold a
`circle`, and the reason is the one this project uses everywhere else: **a
program had finally asked, and one customer satisfied in six lines of the
language is still not a trigger.** A `circle` message would also have been a
shape every later back end had to match, and a Plan 9 `draw`-style binding has
no circle to match it with. `ideas.md` had left this open as *Bresenham in
SolaBasic, on the trigger rule, since no program has asked yet*. One asked, and
the answer did not change — which is the entry doing its job rather than the
entry being tested.

**The verification was done the way the noise taught.** The discs were recorded
as they were drawn and looked at as images: round, correctly coloured, five
sizes. The bounce invariant — every ball entirely on screen, `r ≤ x ≤ width - r`
in both axes — was asserted across nine balls for 1,200 frames, at zero
violations. A single ball covers 20..620 by 21..459 in a 640×480 window, which
is exactly `[r, size - r]`.

**And it caught a second defect that looking alone had nearly missed.** The first
version gave every ball the same sign of velocity, so they set off together and
spent the opening seconds piled in one corner. Two sampled frames, 150 and 450,
both showed the balls clustered — and *nearly explained it away*, because those
two are about one bounce period apart for the commonest speed, so a periodic
system sampled at its own period looks stationary. **Sampling an animation is a
check with a blind spot exactly where the motion is.** What settled it was
measuring the range each ball covers over a long run, which is a question about
the whole trajectory rather than about two moments of it.

### The part worth carrying

**Three verifications ran that afternoon and none of them could have caught
this.** The arithmetic was checked by rendering it as ASCII — correct. The demo
was checked by running it and timing it — it ran. The colours were checked by
recording what was passed to `sdl:fill` — correct. Every one of them tested the
program's *inputs to the drawing calls*, and the defect lived entirely on the
other side of those calls.

**And the circle example added the second half of the same lesson**: looking is
necessary and is not sufficient. Two frames of a bouncing animation are a
picture, and they still nearly hid a defect, because the sample interval
happened to match the motion's period. The check has to match the *shape of the
claim* — a still frame answers "is this drawn correctly", and only a measurement
over the whole run answers "does it move correctly".

A graphics program's output is a picture, and the check has to be the picture.
`screencapture` is refused this machine's screen, so the way through was to have
the program write a PPM and convert it — which cost about as much as one more
round of theorising and, unlike the theorising, ended the question. **The
repository already knew this**: `oracle.sh` exists because eighty-three claims
in `basic.sol` caught none of the seven defects the NBS suite found, since they
check what the author thought to check. This was the same lesson in a medium
that makes it obvious, and it arrived one commit after an entry arguing that
graphics cannot be checked by comparing printed bytes.

---

## 2026-08-30 (evening) — the foundation exercised, and a question that answered itself

Asked whether it was a good time to implement SolaBasic's graphics statements
over the SDL2 extension, *and* to give the new optimisations a workout. The
second half is what the day turned out to be about, and the first half never
happened — which is the trigger rule working rather than the day going wrong.

**The premise was wrong, and checking it was the first useful thing.** The
question was framed as *we stopped SolaBasic at graphics because we did not have
the foundation for it with extensions*. Nothing in this repository ever said
that. [SOLABASIC.md](SOLABASIC.md#never--the-pc) puts `SCREEN`, `PSET`, `LINE`
and `CIRCLE` under **Never — the PC**, beside `PEEK` and `CALL INTERRUPT`, and
the *not yet* table that does hold deferred work has never mentioned them.
Stage 7 was the last stage and it is done. **SolaBasic did not stop at graphics;
it finished without them, on purpose**, and the boundary is CB80's rather than
this compiler's.

That is worth a paragraph because the correction is what made the rest of the
day cheap. A parked stage gets resumed. A boundary gets *reversed*, and the
reversing needs a better reason than an afternoon's enthusiasm — which the
document predicted, having said in its own opening that the trouble with a
vendor dialect is that the subset boundary is drawn by whoever is writing the
compiler, on the day they are writing it.

### The throwaway went first, and found the thing no reading would have

Half an afternoon, nothing tracked changed. solveig-sdl builds clean against
0.39.0 — `SOL_EXTENSION_ABI` is still 1 and the restricted export surface took
nothing it uses, so a bundle written for 0.36.0 still draws. That was the check
the whole question rested on and it passed in ten minutes.

Then two measurements, and the second one is the day's finding. Both are parked
in [experiment/graphics-probe/](../experiment/graphics-probe/) beside the
extension probe from the week before, for the reason that directory exists —
proved, kept, and built by nothing:

- **An extension send costs 205ns against an ordinary send's 55ns.** 200,000
  `sdl:fill` calls in 41ms; 200,000 ordinary four-argument sends in 11ms. So
  a per-pixel graphics API across `dlopen` is affordable, which was the thing
  most likely to have killed the idea outright.
- **`sdl:present` costs 8.3ms, because it is vsync-locked.** Two hundred of them
  is 1.66 seconds.

**The second is a language problem wearing an implementation problem's
clothes.** QBasic graphics is immediate-mode: `PSET` draws and you see it. SDL
is double-buffered, and the buffer is shown by a call that waits for the
display. A faithful `PSET` would present after every statement — **120 pixels
per second**, so a program drawing a circle would take a minute to do it. No
amount of reading the SDL headers produces that sentence; running two hundred
presents in a loop produces it immediately.

### What the optimisations did, on a program chosen to be unkind to them

Same Mandelbrot, 320×200, 400 iterations, both VMs built `-O2`:

| | 0.38.0 | 0.39.0 |
| --- | --- | --- |
| the arithmetic alone, no graphics | 1.59s | **1.07s** |
| drawn, presenting once per row | 2.20s | 1.90s |
| drawn, presenting at most every 16ms | — | **1.29s** |

**1.49x**, on a loop whose every operand is a global — which is
[4.5](COMPLETED.md#45-a-global-is-a-hash-lookup-and-a-receiver-check-is-a-call--done)'s
exact case, met by a program written after it landed and not written to flatter
it. It is a larger gain than any of the nine CPython pairs recorded last week.

**The two drawn rows have since been corrected, and the correction is the more
interesting half.** Writing a real example the same evening and *looking at it*
showed neither of them ever drew the Mandelbrot: `sdl:present` does not preserve
what was drawn, so presenting per row shows one row of fractal and stale video
memory everywhere else, and presenting every 16ms shows one strip. Both numbers
are honest measurements of what those call patterns cost, and neither is a
measurement of two ways of drawing the same picture. The day's lesson was
written down one step too early — see [the evening's
entry](#2026-08-30-the-evening--a-demo-that-showed-the-measurement-was-of-the-wrong-thing).

### The question answered itself when it was put back

The scoping went into [ideas.md](ideas.md#graphics-in-solabasic-through-the-sdl2-extension)
with a recommendation — an opt-in `'$GRAPHICS` metacommand, so the cut line
survives unamended — and three decisions that were not mine to take. The first
was whether to have the module at all or move the boundary honestly.

Explaining that choice turned up the argument that should have been first.
**There is no oracle for a pixel.** Every SolaBasic feature is held against a
real QuickBASIC 4.5 under DOSBox, and the harness compares printed bytes;
graphics print nothing. Graphics would be the first part of the language checked
only against transcripts its own author recorded — which is the precise failure
`oracle.sh` exists to prevent, and which its own header describes.

And putting the choice back as *is there a SolaBasic program you want to write
that needs a screen?* got the honest answer: it had really only ever been about
exercising the foundation. **So the trigger never fired and nothing was built.**
`SCREEN` stays under *Never — the PC*, three documents keep a promise they were
making, and the entry records a verdict of no with the measurements attached.

**The part worth carrying**: both halves of the day were already paid for before
the language question was settled. The foundation was exercised by Solum
programs talking to `sdl:` directly, which needed no compiler change, no
metacommand and no amended boundary — and which is also, it turns out, the
cheapest way to get a picture on a screen out of this project. The language
change would have bought a syntax for something that already worked.

---

## 2026-08-30 (the release) — 0.39.0, and what a week of measuring cost

The release itself was the short part: four files, a tag, a page. What is worth
recording is the shape of the two days behind it, because it is not the shape
this project usually has.

**Every other release here came from a program asking for something.** That is
the trigger rule, and it has been right for thirty-eight of them: somebody wrote
`manifest.sol` and the language grew a JSON reader, somebody wrote the editor
and it grew `replace`. This one came from a *question* — how fast is this
compared to Python — asked out of curiosity with no program behind it.

It found three defects in a week. A heap object allocated for every character
read, and again for the literal it was compared against. A hash lookup for every
read and every write of a global, which is every top-level script and every line
typed at the prompt. And three predictable branches sitting in a different
translation unit from their only caller, costing a function call on every send
in every program ever run here.

**None of them was hard. All of them had been invisible from the inside**, and
the reason is the same reason the trigger rule works: a project measured against
itself gets steadily better at what it already believed mattered. Nothing here
had ever believed `string:at` mattered.

### The two that were refused are worth more than the three that landed

An inline cache at the send site was written into `ideas.md` as *most of the
recursion gap*, confidently, on no evidence. It profiles at **9.7%** of that
benchmark. Computed-goto dispatch — the textbook answer, which this repository's
own JIT entry had put at 10–20% on the strength of the folklore — is **slower**
than the `switch` on every benchmark, because clang tail-merges the twenty-one
dispatch sites back into one and leaves the code size behind.

Both were rejected on measurements taken *after building them*. The entries keep
the disassembly and the profile rather than the verdict, so the next person
starts from the numbers.

### Postmortem

**Four things went wrong this week and three of them were the same thing.**

**A test that passed against the broken version, twice.** The global-slot cache
needed a test that the cache is dropped when a chunk moves to a second machine.
The first one passed against code with the invalidation deleted, because the
`calloc` beside it handed back a fresh table anyway. Later, the visibility
check: removing `-fvisibility=hidden` from the Makefile and re-running `make`
proved nothing, because editing a Makefile does not rebuild the objects — the
flag was still in the binary under test. Both were only found by breaking the
code on purpose and being surprised that nothing complained. **A test that has
never been seen to fail is a hypothesis.**

**A number asserted without measuring, in a document whose whole purpose is to
stop that.** `ideas.md` exists so that a rejected idea does not have to be
re-argued — and it carried *an inline cache would close most of the recursion
gap* for a day, written by the same hand that had just finished insisting on
measurement. The correction is in the entry rather than replacing it.

**Two changes that were each harmless alone and cost 8.5% together**, on the one
benchmark that used neither. Instruction cache, not work — no reasoning about
instruction counts would have found it, and it was only visible because every
benchmark was re-run after every change rather than the ones expected to move.

**And the front page said 0.3.0.** For thirty-five releases. The document
checker recounts prose in `docs/` and reads `README.md` and `index.md` for
claims — but a version number in prose is not a claim it knows, and
`_config.yml` is not a document to it at all, so the site description told every
search engine that Solveig was *the Solum language*, backwards since 0.36.0.
**A guard's coverage is a thing to know rather than assume**, and this one had
been assumed for a month.

### What the week leaves

The machine is about 13% ahead of CPython 3.14 on nine matched programs where it
started level, the export surface is 29 declared symbols where it was 146
accidental ones, and `comparisons/` holds the programs so the figures can be
re-run rather than believed. One candidate is left unbuilt and written up:
`-flto`, worth 5–29%, now a decision about its own costs rather than something
that silently breaks extensions.

And the trigger rule survives with a footnote. A program still asks for most of
the work. But *a question asked from outside* found three things in a week that
thirty-eight releases of asking from inside had not, and that is worth knowing
the next time there is nothing obvious to build.

## 2026-08-30 (evening) — a surface nobody chose

The performance work had left one candidate unbuilt: `-flto`, 5–29% across the
suite for no source change, refused because it deletes the extension ABI. Asked
whether fixing that would *fix* a problem or *cause* one, the honest answer
turned out to be that it fixes one which exists already and has nothing to do
with LTO.

**`bin/solvm` exported 146 `sol_*` functions. `extend.h` names 23. The two
bundles in this repository use 13 between them.** The gap is not slack, it is
the parser, the lexer, the REPL's line editor and the bytecode reader — every
function in `libsol.a` that happened not to be `static`, because that is what
whole-archive linking gives you.

The Makefile's comment records the previous step of the same problem: four
binaries exporting 100, 118, 133 and 118 different accidental sets, fixed into
one set of 139 and described as "a surface somebody chose". It made them agree.
It did not make them chosen.

**And this repository came within one hand-check of the failure.** This morning's
work made `sol_slot_accepts` a `static inline`, which took it off the export
table — 147 to 146. I checked it against `extend.h` by hand and nothing was
owed. Nothing in the build checked, and nothing would have said a word if the
answer had gone the other way. A third party's extension would have stopped
loading on upgrade with `symbol not found in flat namespace` and no clue as to
why it ever worked.

### Declared at the function, not in a list

`SOL_API` on each export, `-fvisibility=hidden` on everything else. The
alternative was an export list beside the linker, and the Makefile objects to
hand-kept lists in three separate places — rightly, because they go stale. A
marker on the declaration cannot: it is deleted by whoever deletes the function.

Two details worth keeping. `used` as well as the visibility, because the two
answer different questions — whether a symbol may be *seen* from outside, and
whether it may be *discarded* for having no caller inside. Every one of these
has no caller inside; that is precisely what makes it an ABI. And the flag is
deliberately not on the bundle rules: `sol_extension_init` is the bundle's own
symbol, and hiding it would mean every extension source anywhere needed a new
annotation to keep working.

### The review, and the gap that had been waiting for it

Seventy functions were hidden that the header did not name and that were not
obviously the compiler or the line editor. Most sorted themselves — the whole
host API goes, because a host links the library statically and visibility costs
a static caller nothing.

**Six were promoted, and the first three had been asked for in writing.**
[extensions.md](extensions.md) had recorded that the surface carried no way to
build a dictionary — the language's own convention for an answer with fields —
so `net` answers an object with `host`, `port` and `text` instead. That entry
ended *either the list grows a dictionary or extensions answer objects; what
should not happen is each bundle deciding quietly.* Declaring the surface is
what finally made somebody decide. `sol_dict_new`, `sol_dict_put` and
`sol_dict_get` are promised now, with `sol_type_name` beside them — rule 1 asks
a primitive to say what it was given, and the function for saying it was
withheld.

`net` is not rewritten. An object with three named slots is a good answer, and
changing a shipped surface to use a newer call is churn. The next bundle has the
choice this one did not.

### Both directions, both broken on purpose

`test_the_promised_surface_is_exported` already existed and carried a comment
saying it was weaker than it looked and had never caught anything — true, since
the lookup succeeded whether or not the link was right. Hidden visibility makes
it load-bearing: a hidden symbol is absent from the dynamic table however many
callers it has in the test file. The other direction had never been testable at
all, and is new.

Both were verified the way this morning taught: break it and watch. Take
`-fvisibility=hidden` out and the new test names `sol_chunk_init`,
`sol_compile`, `sol_parser_init` and `sol_lexer_init` as reachable. Drop
`SOL_API` from `sol_dict_new` and the old one says so. **The first attempt at
the first of those passed against the broken build** — editing the Makefile does
not rebuild the objects, so the flag was still in the binary I was testing. A
negative result from a stale binary is worth exactly as much as a test that
passes against broken code.

And a real bundle proved the whole path end to end: a separate `.so`, compiled
with nothing but `-Wl,-undefined,dynamic_lookup`, loaded by the shipped `solvm`,
building a dictionary and naming a type through the new surface.

**What it does not do is turn LTO on.** That is now a decision about LTO's own
costs — slower links, inlined frames in a profile, a wider gap between the `-g`
build developed against and the one shipped — rather than something that
silently breaks every extension. Which was the point of separating the two.

## 2026-08-30 — the hot loop, and a test that tested nothing

*What could be done to make it faster?* — asked the morning after the CPython
comparison, and answered by profiling rather than by reading the C, because the
day before had just finished recording what happens when you do the other thing.

**The profile that mattered was of a real program.** Six benchmarks, and then
[basic.sol](../programs/basic.sol) interpreting 39,000 BASIC statements —
2,774 lines of Solveig with objects, methods and dictionaries, doing a job
rather than being timed. The dispatch loop 55%, name lookup 13%, and **the
per-send receiver check 12.6%**, which is as much as the lookup and had never
been suspected of anything.

Four candidates came out of it. Two got built.

### The one that was a missing keyword

`sol_slot_accepts` asks three predictable questions — is there a primitive, does
it take any receiver, does the type match — and it lived in `object.c` while its
only caller lived in `vm.c`. So every send in every program paid a function call
across a translation unit for three branches. `static inline` in the header, and
it is 1.4% to 6.5%.

### The one the benchmarks had been hiding

The bigger one came from a suspicion about the benchmarks themselves. In the
integer loop's profile `sol_object_lookup_interned` was 218 samples against
`run_frames`'s 304, which is far too much lookup for a program that sends
`add` and `inc` and nothing else — and the reason is that `i` and `sum` are
**globals**, because the loop is written at a script's top level. Every read is
a hash of the root object and every write is another.

The same loop with the counter as a block temporary instead — an array index,
differing in nothing else — is **1.255×** faster, and the lookup falls from 218
samples to 25. That is not a benchmark artifact to correct for; it is every
top-level script and every line typed at the REPL.

**A chunk remembers where each of its globals lives now**, and what makes that
safe is a fact about this language rather than a general one: a slot is malloc'd
on its own and linked, and *nothing removes one*. ROADMAP 3.10 writes that down
as a problem — a machine cannot be reused because nothing unbinds — and read
from here it is the guarantee that makes the address good forever. The table
rides beside the interned names and is emptied by the same serial, so there are
two caches and one invalidation.

### And then they were slower together than apart

Both in, and every benchmark improved except deep recursion, which lost **8.5%**
— a program that touches no global at all, paying for a change it does not use.
Neither half did that alone: the inlined check gave `fib` 1.011, the cache gave
0.996, and the two together gave 0.922 with the interval nowhere near 1.

Nothing had been added to that program's path, so it was not work. It was
**instruction cache**: a bigger switch body, and the hot cases falling
differently across it. Moving the two slow paths — the first look at a name, and
the failure — out of the loop and into functions of their own fixed the
regression and made everything else faster at the same time. `fib` 0.922 to
1.003, and `loop` 1.251 to 1.284.

**A dispatch loop is a cache-resident thing, and code that runs once per site
does not belong in it.** No amount of reasoning about instruction counts finds
that, because every version does the same work.

### The test that tested nothing

The invalidation needed a test, and the first one passed against code that had
lost the property. Deleting the `free` of the cache changed no answer, because
the `calloc` beside it ran anyway and handed back a fresh table — so the test
was asserting something the broken version still did.

The break that bites is a cache that genuinely *survives* a change of machine,
and against that the test fails on the second machine of twenty. Each one binds
a different value; a VM is a local, so the second very likely lands on the
first's freed address, which is exactly the case 4.3's serial was introduced
for.

**A test that passes against the broken version tests nothing, and the only way
to find out is to break it on purpose.** That is the day's transferable part.
The suite has other tests of this shape — the extension root that was proved by
removing it — and this is one more.

The suite's geometric mean against CPython 3.14 went **1.02 to 0.885**, ahead on
five of nine. Two candidates are left and both are written down: computed-goto
dispatch, which is the 55%, and keeping the exported symbol surface under LTO,
which is 5–29% currently traded away for the extension ABI. Neither is a
language change, which was yesterday's finding and is still the shape of this.

## 2026-08-29 (evening) — measured against somebody else's language

The day ended with a question rather than a task: *how does this compare to
Python for speed?* Nothing here had ever been measured against another
implementation. Every number in this repository is Solveig against an earlier
Solveig, which tells you whether a change helped and nothing at all about where
the whole thing stands.

Nine matched programs — a tight integer loop, recursion, array growth, a
dictionary, join/split, a character scan, float arithmetic, object allocation,
and `collect`/`select`/`inject` — each pair verified to print the same answer
before either was timed, then run through `programs/bench.sob` at twenty-one
interleaved rounds apiece.

**Solveig came out level with CPython 3.14**: geometric mean 1.09, median
benchmark 1.03. Ahead on float (0.60), array (0.69), the integer loop (0.72) and
the higher-order pass (0.75); behind on the dictionary (1.29), join/split
(1.64), recursion (2.03) and the character scan (2.13). Startup is 3.1 ms
against 21.8 ms and Solas compiles about four times as fast as CPython's
compiler.

That is a stranger result than it sounds, and the shape of it is the whole
finding. **Where it wins it wins on representation** — an integer is sixty-four
bits in a register where CPython's is a heap object allocated and freed every
pass — and **where it loses it loses on tuning**, thirty-five years of it. Only
one of those is a thing to do something about.

### The benchmark that was a bug report

The worst of the nine was the character scan, and it was the one worth chasing
because a microbenchmark that loses to a *tuned* implementation says nothing,
while one that loses to a *cheaper* one says where the cost is. Taking the read
out of the loop and running the rest separated them:

| | with `s:at(i)` | without it | so the reads cost |
| --- | --- | --- | --- |
| Solveig | 1.32 s | 0.87 s | **0.45 s** |
| CPython | 0.62 s | 0.52 s | 0.10 s |

Half a second of allocation and collection over nine million characters, to look
at bytes the machine already had. `string:at` ended in `sol_string_new`, and
there is no character type, so every read made a cell.

**And then the other column turned out to be the same fault.** 0.87 s against
0.52 s for a loop that was supposed to be doing nothing — because `"o"` in the
condition is a literal, and OP_STRING builds a literal fresh on every
evaluation. A scan comparing each character to a constant was making *two*
strings a pass. That is the last open bullet of
[1.3](COMPLETED.md#13-strings--done), written a month ago, which said interning
would fix it and would need a weak table so long literals can still die.

### The bounded case does not need the unbounded mechanism

The entry was right about the general case and it is why 1.3 has sat open. It is
also why the fix here is four lines: **there are 256 byte values and there will
never be more.** A table that size can be strong. It is six kilobytes held for
the life of the machine, and holding it is exactly the thing that makes the
second read free — where the symbol table beside it has to be weak, because a
program can intern a million names and a table that kept them would be a leak
with a table around it.

Two decisions inside that are the ones worth remembering:

- **The test went into `sol_string_new`, not into `string:at`.** One byte is
  then the machine's copy as a property of the machine, rather than something
  two primitives remember to do — and it catches `asCharacter`, `copyFrom(#i,
  #i)`, a `split` that yields one character, an extension calling the same
  entry point, and the literal, which was half the win and was not on the list
  the benchmark suggested.
- **Filled on first use, not at startup**, because
  [3.10](ROADMAP.md#310-a-vm-cannot-be-reused-across-runs) already measured a
  third of a request going on building a machine. Five hundred and twelve
  allocations in `sol_vm_init` would be paid by every request to buy bytes most
  programs never read. Hello-world says the build is unmoved: `1.004 times,
  interval 0.973 to 1.026`, which is the tool refusing to call it a difference.

The scan went 1.371 s to 0.758 s, and 2.13× CPython to 1.22×. The suite's
geometric mean went 1.09 to 1.02. Join/split, dictionaries, object allocation
and VM construction are all unmoved — the tool says it cannot tell them apart,
four times, which is the answer a change like this has to be able to give about
everything it did not aim at.

### What the measurement did not find

The recursion gap is real and is not a bug: eighteen million sends, each a name
looked up through a proto chain, against an interpreter that inlines a
Python-to-Python call and rewrites a monomorphic call site after a few passes.
An inline cache at the send site would close most of it, and that is a change to
what *one way to call something* means in the machine — a design question, not
an optimisation, and it goes in `ideas.md` before it goes anywhere.

The dictionary and join/split gaps are somebody having spent years on
`str.split`. There is nothing structurally wrong there to fix, which is a
different and much less interesting kind of gap, and confirms from the outside
what the editor's substitute pass found from the inside: **a library's speed
lives at the boundary with the primitives.** That boundary is in the same place
in both languages. What differs is how much has been tuned on the far side.

**And the flag was worth more than any of it.** All of the above is an `-O2`
build. `make` builds `-g` with no optimiser, and that binary is 2.1× to 4.6×
slower — it loses all nine. Nothing is wrong with a debug default, but the
binaries in `bin/` are not the ones any of these numbers describe, and a timing
quoted without its build is a timing that means nothing.

## 2026-08-29 (later) — the question a program could not ask

The ask was a small one: *a standalone tool that prints the exposed messages in
a `.sob` or a `.so`, unless there is an easy option already.* The honest answer
to the second half was **no, but three things get you part of the way, and each
is missing a different half** — `solvm --dump` gives the instructions and leaves
you to read `SETGLOB` off them by eye; `solid`'s `globals` gives the names and
not the messages; and `slots`, `exports` and `respondsTo` give the whole surface
exactly, if you already know the name to ask.

That third row is where the day's one real constraint sat, and it was already
written down: **`globals` is the one question a program cannot ask itself.** The
globals are slots on an object with no name in the language, so neither `slots`
nor `perform` reaches them. Which settles the shape before any of it is
designed — this could not have been `programs/exports.sol` beside `disasm.sol`,
where by every other measure it belonged. It has to hold the root object, and
two things in this tree do: a host, and the debugger.

### The throwaway that changed the design

A hundred-line throwaway, written to answer one question: parse the file, or run
it?

Parsing is the safer answer and was the one to beat. Collect every
`OP_SET_GLOBAL` in the top-level chunk and you have the names, with no side
effects and no risk. It is also **wrong**, and the file that proves it is
`lib/text.sob`: it binds no global at all. It hangs `utf8Tail` and `asUtf8` on
`integer`, so a reader of `SETGLOB` prints an empty report for a library with
two messages in it and gives no sign that it has failed. And a `.so` has no
bytecode to read in the first place — an extension's surface exists only after
`sol_extension_init` has run, so the static answer does not merely miss that
case, it has nothing to open.

So: load it and look. Snapshot what the machine held, load the bundle or run the
chunk, and diff — the globals for what was bound, and every built-in class's
slot count for what was extended. Both file kinds land in the same place, which
is why one mechanism reads both.

The cost is stated rather than hidden: **it runs the file.** Pointing it at
`programs/tools.sob` shells out to `du` and `git` before it prints a word, and
`extensions/net/client.sob` spent six seconds trying to reach a server that was
not there. For a library — which binds its names and stops, because that is all
a library does — this is nothing. For a program it is the whole program. The
help text says so in two lines.

### The bug in the report I had already written

The throwaway found that `lib/json.sob` shipped a `scan` with no `exports`
boundary while `lib/json.sol` said it should have one, and I wrote that up as a
finding before checking one thing: `.gitignore` has `*.sob`, and `make install`
copies `lib/*.sol`. **Nothing in `lib/` is tracked, built by `make`, or
installed.** Sixteen of them differ from a fresh compile on this machine and not
one of them ships. It was a stale artefact from someone running `solas` by hand
in May, and the correct size of the finding is *delete them*.

Worth keeping as the lesson rather than the fact: a diff against the working
tree is not a diff against what is published, and I had the second one available
the whole time in the form of `git ls-files`.

### Where it went, and the hazard that was closed rather than survived

`solid --exports`, a mode of the debugger — not a fifth binary, which would have
needed a name and a paragraph in the README's name story for a capability solid
already has. The case is
[6.38](COMPLETED.md#638-nothing-says-what-a-compiled-file-exports--done). Not `solas`, which would need `dlopen` to read a `.so` and is
[promised never to have it](extensions.md#who-decides).

One thing in it was nearly right by luck. The report holds an `SolObject *`
across the run, and a file may rebind the name an extension bound — at which
point the object measured before has no root left and the collector may take it,
leaving a pointer into freed memory. It passed under ASan and GC stress on the
first try, which proves the collector did not get to it that time and nothing
more. The name is looked up again now and the two pointers compared before
either is read: a comparison, never a dereference. Equal means the slot still
holds it, and holding it is what keeps it alive.

**Passing the sanitiser is not the same as being safe from what the sanitiser
looks for.** The test that would have caught it did not exist until after the
reasoning did, which is the right order and not the usual one.

### Postmortem

Four things, and the first two are the same mistake looked at from opposite
ends.

**The design was decided by a throwaway and not by reasoning**, which was the
right order and is not the order I would have taken unprompted. Reading the
bytecode is the better idea on every axis you can name from an armchair — no
side effects, nothing to bound, works on a file that would fail if run — and it
is wrong for a reason no amount of thinking about it surfaces: `lib/text.sob`
binds nothing at all. A hundred lines found that in about a minute. The rule
this repository already had is *the throwaway comes before the design*, and it
paid here in the only way that counts, by killing the design I would otherwise
have written up as a recommendation.

**And then I skipped that step for a claim about the repository.** The same
throwaway reported sixteen stale `.sob` files and a `lib/json.sob` shipping a
`scan` with no export boundary, and I wrote it into a report as a real defect
before running `git ls-files`. `.gitignore` has `*.sob`; nothing in `lib/` is
tracked, built by `make`, or installed. The finding was correct about the bytes
and wrong about everything that made it matter. **A diff against the working
tree is not a diff against what is published**, and the check that would have
told me so took four seconds and was not run because the finding was interesting.

**The sanitiser passed on code that was wrong.** Holding an `SolObject *` across
the run is a dangling pointer the moment a file rebinds the name an extension
bound, and ASan with `SOLUM_GC_STRESS=1` said nothing — the collector did not
reach that object on that run. Had I stopped at green, it would have shipped and
would have failed on somebody else's file. What found it was writing the header
comment: saying *the report holds an object across the run* out loud is what made
the next sentence obviously false. **Passing the check is not the same as being
safe from what the check looks for**, and the test that guards it now was written
after the reasoning rather than before, which is the right order and the rarer
one.

**The trigger was a sentence, and that is new.** Every entry in section 6 of the
roadmap arrived because somebody wrote a program and found out what it wanted;
this one arrived because somebody asked a question, and the question named the
thing exactly. The rule *a program asks for the work, not a document* is still
the better source and is not the only one — the roadmap says so now. Worth
noticing that the question was **also** partly an answer: *unless there is an
easy option to do that already* is the half that turned into the three-row table
of what nearly worked, and the three-row table is what determined that the tool
had to live in the debugger.

## 2026-08-29 (after the release) — the consumer that was not in the tree

Moving `make dist` into `dist/` was the smallest change of the day: a variable,
a `mkdir`, an ignore rule, and four tarballs relocated. `make test` passed, the
document checker passed, and it was committed and pushed.

**It broke CI**, and it broke the one job that neither of those checks can see.
The `install + dist` workflow builds the tarball and then extracts it —
`tar xzf solveig-*.tar.gz` at the repository root, where there is now nothing.
A step that cannot find its input fails for the wrong reason, and it would have
failed on the next push whether or not anything was wrong with the release.

It was found by asking *is anything left over today?* rather than by the machine,
which is the part worth keeping. **A change to where a build artefact goes is a
change to every consumer of it, and the consumers are not all in the tree.** The
Makefile, the ignore file and the README were all updated together, because all
three are here; the workflow was not, because looking at it did not occur to
anyone who had just finished looking at everything else.

### And then the fix found something CI could not have

The obvious repair is to move the glob: `dist/solveig-*.tar.gz`. Rehearsing it
here is what showed why not. CI starts from a clean checkout with exactly one
tarball; this tree keeps four, one per release since 0.35.0 — and a glob that
matches four hands `tar` the first as the archive and the other three as member
names to extract *from* it. Three lines of *not found in archive*, and a green
run in CI regardless, for as long as CI never keeps two.

So the step takes the path from the rule that writes it — `make dist` already
echoes it — and stops caring where that is. **The local rehearsal caught what CI
could not, on the same afternoon CI caught what local could not.** They fail in
opposite directions: a fresh checkout hides what an old one shows, and one
machine hides what three show.

### What CI was actually for, this time

Green on all five jobs, and two of them were carrying a real question rather
than a habit.

| | |
| --- | --- |
| `ubuntu-latest / gcc`, `ubuntu-latest / clang`, `asan + ubsan` | **the first Linux build of `net.so`**, which had existed only on macOS until this run. `make all` builds the bundle now, and `make test` depends on it, so the datagram round trip, the foreign cell and the collector root were exercised on three configurations rather than one |
| `install + dist` | the corrected path, end to end: build the tarball, extract it, build from it |

The bundle needed no change to compile under either Linux compiler or under the
sanitisers, which is what the extension mechanism promised and had so far only
demonstrated for bundles built somewhere else.

### The lesson, which is a narrow one

The day's other findings were all *a statement true where it was written and
false where it ended up*. This one is the same sentence about code: a rule that
writes a file is a contract with whoever reads it, and grepping the tree for
`tar.gz` would have found the workflow in one second. The check is cheap and the
habit is not automatic, which is exactly the kind of thing this journal is for.

## 2026-08-29 (the release) — 0.38.0, and three statements that were true somewhere else

**Two things that add no messages.** 141 messages, unchanged; `.sob` format 14,
unchanged; a notation and a bundle, and neither of them the machine. Tagged,
tarballed, and a release page that is Latest.

Nothing was built to cut it, and the hour still produced findings — all three of
the same kind, and the same kind the day opened on. A statement that is true in
the place it was written and false where it ends up.

### The compatibility check, and the false positive it starts with

0.37.0 was built from its tag and both compilers pointed at this tree's
examples. Thirty of thirty-four came out byte-identical. **Four did not, and
none of the four is a difference between the compilers**: each includes a
library, and a `.sob` carries the file table that
[6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done) put there,
so each recorded the absolute path where *that* build found `control.sol`.
`/tmp/sol037/lib/...` against `/Users/...`, fifty-one bytes, and the instruction
streams identical when disassembled.

**So the check has to compare instructions and not bytes the moment an include
is involved**, and the reason is a feature working exactly as intended: a trace
names the file, so the file's name is in the artefact. Worth writing down before
the next release repeats the alarm.

### The clean half, which is the better story

The interesting run was the other one. A program using `@expr{...}` was compiled
here and its bytecode handed to **0.37.0's machine**, which ran it and printed
`#3` — a machine that has never heard of the notation, running a program written
in it. Then 0.37.0's compiler was handed the same source and refused it:
*expected '(' after '@expr'*.

That is the whole claim of a notation, demonstrated by two binaries rather than
asserted by a test: the language grew and the machine did not have to. 0.37.0
was the other side of the same coin — `replace` kept the format compatible while
a program using it still needed a machine that had it — and having the pair one
release apart is worth more than either statement alone.

### The release page is not a document in this tree

Two things were true in the changelog and would have been false on the page.

**A `count` marker is a live number**, and a release page is a historical
statement. That is the mistake the 0.37.0 work found in the changelog and fixed
for two entries; publishing is where it would have come back, because nothing
recounts a page on GitHub and nothing there would have said so. Stripped.

*Writing that sentence with the marker spelled out in it broke the build*, which
is the joke the notation is entitled to: a comment that says *recount the number
before me* means that wherever it appears, and prose about it is not an
exception. There is no escape for one and there does not need to be — the
notation is described in [programs.md](programs.md) and does not have to be
quoted to be explained.

**And relative links do not resolve from a release page.** `[NET.md](NET.md)`
is correct inside `docs/` and a 404 from `/releases/tag/v0.38.0`. Both were
rewritten to absolute URLs *pinned at the tag* rather than at `main`, so the
page goes on describing what this release shipped after the documents move
underneath it.

Neither is a large thing. Both are the day's shape again: a sentence that stops
being true by being moved rather than by being wrong.

### And the tarballs

Four had accumulated in the repository root, one per release since 0.35.0,
because that is where the rule had always written them and nobody minds the
first one. They are in `dist/` now, ignored as a directory rather than only by a
`*.tar.gz` pattern.

`make clean` does not take `dist/`, and the Makefile says why where the rule is:
a tarball is a release artefact and not an intermediate one, and cleaning before
a rebuild should not delete the thing you were about to publish. An omission
nobody explained would read as an oversight in six months.

### The shape of the day

Nine commits. Two documents corrected against the code, one notation, one
extension with two programs and a reference page, three journal entries before
this one, and a release. Nothing opened or closed on the roadmap, which after a
day that added infix blocks and a networking bundle is the part worth noticing:
**the list stays empty because the work keeps arriving from programs rather than
from the list.**

## 2026-08-29 (the extension) — sockets, and a postmortem on the entry that predicted them

Two Solveig programs talk to each other now. [net](NET.md) is UDP over IPv4 in
five messages, built by `make` into `build/extensions/net.so` and loaded by
nobody unless a host names `--extension=`; `extensions/net/server.sol` holds a
counter and `client.sol` moves it. The VM is the size it was, which is the point
rather than a side effect.

**The decision that shaped it was not mine.** The recommendation on the table
was an extension on a narrow ground — a socket in the VM pre-empts
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine) by
granting every script networking whether the host meant to or not. The answer
that came back was a wider one: *keeping the core VM small is in itself an
important goal, and rarely used features can be extensions.* Same conclusion,
different reason, and the wider reason is the one that will decide the next
three of these.

### The postmortem: what the entry predicted

[The networking entry](ideas.md#networking-and-sending-code-to-a-machine-that-is-already-running)
was re-read and rewritten yesterday morning, hours before any of this. Holding
the work against it is the cheapest audit there is, because the predictions were
written down before anyone knew they would be tested this week.

| predicted | what happened |
| --- | --- |
| *The question is no longer what a socket costs but where one belongs* | Held. The whole discussion was placement, and the code took an afternoon |
| *How a program waits on one of two things is the entry* | **Held, and it was the design's centre.** `waitFor` is the message the other four are shaped around |
| *`connect`, `bind`, `listen` and `accept` are an afternoon* | Untested. UDP needed none of them, which is why UDP came first |
| Trigger: *two machines that need to talk* | Fired sideways — *can we pull the probe's socket out and have two programs talk?* is the same want, one step short of the wording |

**And the one it did not have.** Nothing in that entry, or in the probe's
README, or in any of the arguments about placement, said that **a packet must
say who sent it**. The probe read with `recv`; the first client and server
written against it could not answer each other; and the working code I wrote to
demonstrate the problem had the client encode its own port *inside the message*
so the server could parse it out. That is a protocol invented to route around a
missing field, which is what a missing field looks like from inside a program.
Five minutes of writing found what a day of writing about it had not.

**The half it got right, it got right for a smaller reason than the true one.**
The entry said waiting was unanswered because there is one thread and
concurrency is refused. True, and not the sharp end. A blocking read stops the
*dispatch loop* — which is where `--steps` counts and where `--memory` is
checked — so a program waiting on a peer that never speaks is a program no limit
can reach, for as long as the silence lasts. That is
[3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work) at full stretch, and I only
joined it up while writing the primitive. The entry now says so, and 3.7 gained
the instance: **the width of that hole is something a bundle chooses**, and this
one chose a timeout.

### The GC proof, and the half that failed usefully

`packet_new` allocates three cells and roots the object, because `sol_string_new`
collects and a cell held in a C local is not a root. Removing the push and
running the suite under `SOLUM_GC_STRESS=1` answers *object does not understand
'notNil'* — an object swept between being made and being filled. Load-bearing,
demonstrated, restored.

**The two string roots I had also written were not needed, and finding that out
was the better half of the exercise.** Rule 3 says nothing may hold a heap
pointer across an allocation, and `sol_object_define` looks like one — so the
roots went in by reading the rule. They pass with the roots and pass without
them, and the reason is checkable rather than lucky: `define` takes its slot
from `malloc` and interns its name in the VM's permanent table, neither of which
the collector touches. So the string is stored before anything can collect.

Two lines that assert something untrue are worse than no lines, and the only way
to tell them apart was to take them out and then go and read why the run still
passed. **A passing stress run is an answer, not a failed proof.**

### Three findings that were not the feature

| | |
| --- | --- |
| **The extension surface has no dictionary** | The language's convention for an answer with fields is one — `system:terminalSize` gives `"rows"` and `"columns"` — and the promised surface carries `sol_object_new` and `sol_array_new` and nothing that builds a dictionary. A packet is an object. Either the list grows one or extensions answer objects, and what should not happen is each bundle deciding quietly, so it is in [extensions.md](extensions.md) rather than only in that directory |
| **`sol_foreign_handle` has a NULL trap** | It answers NULL for a released cell, which cannot be told from a handle that *is* NULL — and descriptor 0 is a real descriptor. `net` stores `fd + 1`. Standard input is never a socket today, which is exactly the kind of reasoning that stops being true on the machine where the program was started with its input closed |
| **There is no `startsWith`** | `server.sol` wanted it and wrote `text:indexOf("add "):equals(#1)`. Deferred in [ideas.md](ideas.md#startswith-and-endswith) with the verdict a truncating divide has and for the same reason: one customer, and a workaround that is exact rather than approximate |

### The method, running at speed

The probe was written on the 28th to press on the extension mechanism, and its
socket existed only because *a graphics toolkit, a hand-written maths library and
a socket* was the shape of the claim being tested. It falsified an entry it had
nothing to do with, then seeded the bundle that answers it, then failed at the
first real use in a way that named the missing field. Three jobs, none of them
the one it was written for.

Nothing on the roadmap opened or closed. Two of its entries gained an instance,
one document became true again, and the language answers exactly the messages it
did yesterday.

## 2026-08-29 (the rest of it) — three questions with one shape, and the one that built something

The morning found a document resting on a fact that had stopped being true. The
afternoon was three questions doing the same thing from the other side: each one
inferred a restriction the language does not have, and each inference came from
the same place — **a character doing two jobs looks like it must have cost
something**.

| | |
| --- | --- |
| *`~a \| b` must read as `~(a \| b)`* | It does not. `~` binds tighter than `&` and `\|` already |
| *`@expr` needs a block form to reach a loop's condition* | It does not. A region is lexical, so the whole loop already fits in one |
| *`\|` being an operator must block parameters inside a region* | It does not. Parameters and temporaries are matched before a body is |

Three wrong premises, and two of them produced something anyway. That is the
part worth writing down, because the instinct on being told *your premise is
wrong* is to drop the question, and twice that would have been the wrong move.

### The one that corrected a document

`~` is looser than a comparison, so `~a = b` is `~(a = b)`, and the reason on the
record was that this is *the call BASIC and Pascal make*. BASIC yes —
`SOLABASIC-REFERENCE` puts `NOT` below the comparisons and above `AND`, which is
this ladder exactly. **Pascal no.**
[pascal.bnf](../programs/check_syntax/pascal.bnf), in this repository, has
`factor = ... | "not" factor` — the tightest level there is. Pascal sides with C
and would read `(~a) = b`, which is the reading the question arrived at
independently.

So the citation was half wrong, its counter-example had been in the tree since
the Pascal grammar went in, and nothing found it because **nothing checks a claim
about another language**. `expect.sol` runs the blocks and recounts the numbers;
a sentence about what Pascal does is neither.

The verdict did not move — the words say *not a equals b* and BASIC agrees — so
what changed is the support, from two languages to one language and the words.
Narrower and true. Four live sites, and I missed one of them on the first pass
and caught it a commit later, which is its own small lesson about grepping for a
phrase rather than for the claim.

### The one that built something anyway

The block form of `@expr` was asked for because a loop's condition is a block and
the marker had to go inside it. The premise was that this was the only way; the
region is lexical, so `@expr( { j < #5 }:whileTrue({ ... }) )` had always worked
and converts the body too.

**And the question survived its premise**, on evidence nobody had assembled:
every use of `@expr` in this repository outside the example was inside a block
with the marker pushed in — `tick.sol`, `game.sol`, `both.sol`, three programs
written the day the notation shipped for reasons that had nothing to do with it.
The wrap was available to all three and taken by none. Then the argument that is
not taste: `-` is the one token whose meaning the mode changes, so a region has
semantic width, and reaching a block by wrapping the send that takes it widens
over the receiver and every other argument.

The entry was written first with a recommendation to **try the sentence before
the notation** — perhaps the wrap was undocumented rather than rejected. The
sentence was tried and lost in ten minutes: rewritten both ways, the wrap makes
a reader hold an open region across a send and its argument list and closes on
`) )`.

### What the entry did not predict, which is the whole finding

It named one hard part: handing the lexer's mode back at the closing brace,
where `@expr(...)` controls both of its delimiters and a block's `}` is consumed
somewhere else. That was one value threaded through `block_body` — *the mode
that should hold once the block is closed* — and it took fifteen minutes.

**The hard part was the inlining.** `{ ... }:whileTrue({ ... })` written
literally compiles to jumps, and the probes that decide so compared against
`TOK_LBRACE`. So the first working version of `@expr{...}` parsed, ran, answered
every question correctly, and quietly emitted a real send with two blocks in it.
Twenty-nine bytes against fifty, and a frame per pass.

Nothing that tested what it *answered* could have caught that. It was caught by
the one test that compares bytes, which exists because the notation's claim is
that the bytes are the chain's bytes — and the claim turns out to mean more than
it says. **A notation that stops inlining is a second semantics**, whatever
number it hands back.

The fix has a detail worth keeping. The probes read a block in either spelling,
and they set the *probe's* mode while doing it: scanning `@expr{ x - 1 }` under
the file's mode gives *'-' must be followed by digits*, an error token, which
reads as **not inlinable** — so the region would have lost the jumps exactly
where its body used the operator that makes a region worth having. The failure
would have been silent, correct, and slow.

`check_syntax` — the other implementation of this grammar — accepts the extended
example, so both admit the form. That is the second time this week the two
implementations were worth having against each other.

### The one that produced nothing, correctly

The third question proposed `\` for parameters and temporaries inside a region,
to free `|` for `or`. Parameters already work, so the proposal bought exactly one
shape: a block whose body *begins* `ident |`. `@expr{ more | failed }:whileTrue`
is a block taking `more`, and it fails at run time with *'block' takes 1
argument, got 0* — a real cost, and a message that does not name its cause.

Not worth a character. A region-only spelling would recreate the corner the
region was built to avoid — a block written differently inside than outside,
so moving one in or out means editing it — and two spellings everywhere is what
this language has refused three times with the same sentence. Ten minutes, one
verified answer, nothing written down. **An idea that dies from being checked
against the code cost less than the entry explaining why it was deferred would
have.**

### The shape of the day

Two commits of documentation, one feature, one idea closed by measurement. The
through-line is that **a wrong premise is not a wasted question**: what makes one
productive is whether checking it turns up something the asker did not have, and
twice it did — a citation nobody would have verified, and a notation whose case
was better than the reason given for it.

## 2026-08-29 — an entry that outlived its reason

**The morning's question was what is on the list, and the answer was still
nothing.** [ROADMAP.md](ROADMAP.md) has no open work — section 2 has no design
question, section 6 is built, and section 3 holds the restrictions the language
lives under rather than a queue. What is left is [ideas.md](ideas.md)'s deferred
entries, each waiting on a trigger nobody has pulled.

So the hour went to reading those against the tree, which found two stale
things. **The difference between the two is the whole of this entry.**

### One was a sentence

The at-a-glance row for extensions said the foreign cell and the callback
registry were *still open*, and that a block held by foreign code is swept with
the failure silent. Both were built on 2026-08-28, the registry's token is the
fix for exactly that failure, and the entry's own table says so fourteen hundred
lines further down. A summary contradicting the thing it summarises, and it took
one rewritten row.

Nothing catches that. `expect.sol` recounts a number carrying a marker and runs
a fenced block; a table of verdicts disagreeing with the entries under it is
prose about prose, and reading is the only instrument there is.

### The other was a conclusion

The networking entry opened on a fact — *there is no socket anywhere in this
repository* — and deduced from it that a client and server pair means new
primitives in the VM. The fact stopped being true yesterday.
[ext_net.c](../experiment/extension-probe/ext_net.c) is a UDP extension: a
`<socket>` foreign cell, no `close` at all, and the collector doing the closing.

**And it was not a demo, which is why it is evidence rather than an exception.**
It was the argument for `SolForeign` — the first version handed a descriptor
back as a plain integer, so nothing closed it when a program was stopped, it
went uncounted against `--memory`, and a program could invent one and pass it to
`close`. Opening real sockets through it is also what found that bytes are the
wrong currency for a scarce resource. The file that falsified the entry is the
same file that shaped the mechanism which falsified it.

**The verdict survived and its argument did not**, which is the finding. Defer
is still right, but not for the reason written down: sockets no longer cost new
primitives, so the case had to be made again from what exists. And the
extensions precedent does not reach them. `dlopen` won for GTK on a
combinatorial argument — two toolkits, most programs wanting neither, every pair
of them a build — plus a dependency that would have cost *no dependencies beyond
a C11 compiler and `make`*. There is one sockets library, everyone who wants
networking wants the same one, and POSIX costs nothing. **The recommendation
came out the same and the reasoning is entirely different**: a socket in the VM
grants every script networking whether the host meant to or not, which pre-empts
[6.32](ideas.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
rather than answering it. Inward later is easy; back out is not.

That is the case for re-reading rather than patching, made concretely. Swapping
*new primitives in the VM* for *an extension* would have produced a true
sentence resting on nothing.

### What the probe had been hiding

The new half of the entry is the part neither document had. `net:poll` is
non-blocking and ran from a frame loop SDL owned — **the graphics library did
the waiting**, and while the socket lived inside a game nobody had to notice
that. A server owns its own loop. Waiting is what this machine has no answer
for: a blocking read stops the only thread there is, there is no second one
([3.11](ROADMAP.md#311-a-chunk-cannot-be-shared-between-threads)), and
concurrency is recommended against on the grounds that it changes the whole VM.

`connect`, `bind`, `listen` and `accept` are an afternoon. **How a program waits
on one of two things is the entry**, and no amount of extension mechanism
supplies it.

### The lesson, one turn further than it was

The 21st's closing line was that an entry goes stale not when it is wrong but
when the world moves underneath it and it stays technically true. This refines
it: **the sentence was merely old, and the conclusion drawn from it was false.**
A reader acts on the conclusion. A premise that has quietly stopped holding
leaves every deduction above it standing, looking exactly as it did when it was
sound, and no checker in this repository can see the difference.

There is a filing lesson under it too. The evidence was written on the 28th and
filed under extensions; the entry it falsified sits in a different section of
the same document, and a day passed with nothing connecting them. Reading both
in one sitting is what joined them, which is an argument for the re-read being a
habit rather than an occasion.

Nothing shipped and nothing closed. One entry says something different now, and
the difference is what it would take to be wrong about it.

## 2026-08-28 (the close) — a name, a mark, three releases, and the language grew by one

The day that began with *how do we get GTK in without putting it in* ended with
two toolkits in two repositories, the language renamed, and one message added
because a program asked for it. What follows is the closing account; the four
entries below this one are the work as it happened.

### The name

**Solveig is the language now. Solum moved down a layer** to name the machine,
its bytecode, and the ground a program is finally laid on — which is what
`solvm` had been saying all along, SOLVM being how *solum* was written before
the alphabet split V into two letters.

Nothing in the source tree was renamed. `solum/`, `SOLUM_VERSION`, `.sob` and
every `sol_*` call describe the layer they always sat in, and each is *more*
accurate for the word having moved to meet it.

Three paragraphs of the etymology needed real work rather than substitution, and
the one that mattered was `sōlum` meaning **only** — the design principle. It
looked orphaned by the move, and it was not: the dispatch loop is where "one
kind of thing, one thing that happens to it" is *enforced* rather than intended.
A language with a second mechanism could not be run by that machine without
being given one. The principle was always kept in the ground.

### The mark

One disc, parted: *sól* above the line, *solum* below. It is the naming decision
rather than a decoration of it, and it is *only* one shape, which is the other
sense of the word.

Two things it is built to survive, and both were mistakes in the first drafts.
**The gap is geometry rather than paint** — a white line across a disc works
only on white. And in the site header the ground half is `currentColor`, so it
follows the theme while the sun half never changes.

It was drawn, rendered and *looked at*, three rounds. The first produced a
weather icon, a bullseye, and a bar in front of a circle. A spoked sun-wheel was
never drawn: it is the obvious way to draw a Nordic sun and it is close to a
symbol other people have ruined.

### Three releases

0.36.0 and 0.37.0 cut, and **0.35.0 backfilled** — it had a tag and no release
page, so the run went 0.36.0 → 0.34.0. Its tarball turned out byte-identical to
the one made on release day, same SHA-256, so what is published is the original
rather than a reconstruction of it.

Each release's compatibility claim was **earned rather than asserted**, by
building the previous one from its tag and running each compiler's output on the
other machine. 0.37.0 needed the claim in two halves, which is the part worth
keeping: bytecode is compatible both ways *and* a program using the new message
needs a machine that has it. The format being compatible and the language having
grown are different facts and conflating them would have been the easy sentence.

### The port, and the message it asked for

Solveig's 1,766-line editor now runs in a window. Of those lines the diff removes
33 and adds 114, most of them comments: the buffer, the motions, the undo stack
and the whole of `:s///` are the file as it was.

**The loop inverts, and that is the only part that is not mechanical.** The
terminal version owned its loop — draw, block on a key, act. GTK owns the loop
and calls in, so the body turns inside out and `gtk:run` is where the program
waits. Nothing above the driver knows.

And **the port is shorter where the terminal was hardest.** `escape` cannot be
told from the first byte of an arrow by a byte reader, which is why
`system:keyWaiting` exists and why `edit:escapeWait` is fifty milliseconds. GTK
delivers a decoded key, so `decode`, `decodeEscape` and `escapeWait` are gone —
along with `system:terminalSize`, a message this language added *for* that
program, which a window has nothing to ask.

It wanted one thing the language did not have: `string:replace`, three times in
one line, to escape markup. The workaround was exact, so the port shipped
without it and the absence was written down. Then 0.37.0 added it, and the port
uses it. **141 messages.**

### Postmortem

1. **The entry told me the method and had never been made to follow it.**
   ideas.md's extensions entry closed by saying *write one throwaway extension,
   fifty lines, build it, load it, find out what the path actually wants — an
   afternoon of that would settle more than another page of this.* It had been
   extended twice instead. The afternoon happened today and it falsified two of
   the entry's own claims, found a bug the design could not have predicted, and
   settled the mechanism. **A page that recommends a method and does not use it
   is a page arguing with itself**, and the tell was that it kept getting
   longer.

2. **Three bugs, and every one was found by a program rather than by reading.**
   The block a collection swept between callbacks. The collector that never ran
   because a socket weighs forty bytes. The free-list field that meant two
   things. None was visible in review; each took a program that abused the
   thing. The registry bug is the sharpest: it was caught by
   `test_releasing_twice_is_not_an_error`, the case that looked least worth
   writing.

3. **A check that cannot fail teaches nothing, and looks identical to one that
   works.** The version gate in the extension Makefiles compared a shell's
   process id against zero for an hour, because `$$$$1` in a Makefile becomes
   `$$1` and the shell eats it. Against a current checkout a broken gate and a
   working one are the same. It was caught only by running it against a real
   0.35.0 built from its tag — the same old build already sitting there for the
   release compatibility check, which is the argument for keeping such things
   around.

4. **Writing the second one is what tests the first.** solveig-sdl needed no
   change to the mechanism, and the useful part is that it is *unlike* GTK: SDL
   hands a program a frame and gets out of the way, so it uses no callbacks and
   none of the retain registry. That is evidence for two decisions taken on
   argument when there was only one back end to argue from — that the registry
   is a service rather than a shape, and that no back end names itself the
   general case. **The temptation was to give SDL a `run(block)` so the two would
   match**, which would have destroyed exactly the evidence that made writing it
   worthwhile.

5. **A live count inside a historical sentence is a small trap.** The recount
   rewrote *"0.36.0 — 140 messages, unchanged"* into 141, which was true of
   neither the release nor the sentence. Markers belong on statements about now.
   History gets plain numbers.

6. **The suite drove the whole doc tail and was better at it than I was.** It
   demanded the reference entry, the index row alphabetised, an example that
   actually sends the new message, and five separate counts — including two
   wrapped in bold that the obvious pattern missed. Every one of them was a
   thing I would have shipped wrong.

## 2026-08-28 (after all that) — the second back end, which was the experiment

**SDL2, and the point of writing it was not SDL2.** The extension entry closed
yesterday with a claim that had never been tested: *SDL2 after that changes
nothing about any of the four steps, which is the whole claim.* One back end
cannot show that. Two can, and only if the second is allowed to be unlike the
first.

**It needed no change to the mechanism**, and one name added to a list.

### The two bundles look nothing alike, and that is the result

GTK owns the loop and calls into the program: `gtk:run`, `gtk:onClick`, and
every block it holds kept alive across collections. SDL hands the program a
frame and gets out of the way: no `sdl:run`, no callback, nothing registered
anywhere, and the loop is an ordinary `whileTrue`.

**The temptation was to give SDL a `run(block)` so the two would match**, and
this page's own advice is what argued against it — a back end that borrows
another's vocabulary makes every later back end emulate a toolkit it has nothing
to do with. That advice was written when there was one back end and nothing to
check it against.

So two decisions taken on argument now have evidence:

- **The retain registry is a service, not a shape.** solveig-sdl uses none of
  it. Had callbacks been the shape of an extension, every file there would be
  working around the interface rather than using it.
- **No back end names itself the general case.** `gtk:` and `sdl:` share no
  vocabulary and neither had to pretend to be the other.

### What it found

One gap, which is one more than nothing and far fewer than a redesign:
`sol_symbol_intern` was reachable and unpromised. An extension answering *what
happened* — a key, a click — wants a symbol for the kind immediately, because
`event:kind:equals('quit)` compares by identity and is cheap enough to run every
frame. It is promised now.

**A dictionary is still deliberately not promised**, and refusing to add it is
the same discipline: `sol_dict_new` exists, nothing has needed keys built at run
time, and promising an interface before something has used it is exactly how the
accidental surface happened in the first place.

### The field that earned itself

`footprint` went into the foreign cell on reasoning: without it `--memory` would
measure the pointer rather than the texture. Nothing had tested that, because a
socket has no honest footprint and a GTK widget's is the driver's business.

An SDL window does. A 1024×768 screen is about 3MB of pixels, and it declares
so:

```
solvm: stopped: the memory limit of 2097152 bytes was reached, with 3179480 live
```

**A limit measures the window rather than the handle to it**, and an extension
declaring nothing would have let that program open a thousand.

### And the close path, tested this time

Yesterday's GTK bug was in the one path a test could not take — clicking the
close button — and the reasoning that let it ship was that the click path was
*the same as the handler path*, which it was not.

SDL closed that differently: it turns `SIGTERM` into an `SDL_QUIT` event, so a
`kill` on the process runs the program's own quit path and it prints its frame
count on the way out. 218 frames at 55fps, and the quit handled by the same code
a window close would use. Not a substitute for a person clicking, and much
better than an argument that it would probably work.

## 2026-08-28 (last) — GTK: the page replaced by an afternoon, then built, then a currency error

**No code shipped, and the day's most useful hour was spent proving a document
wrong.** The question was how to get GTK into the language without putting it in
the VM — with SDL2 named as the reason it must not go in, since two window
toolkits cannot both be in a core that has one of anything.

### The argument that decided the mechanism, before any of the probing

[ideas.md](ideas.md#extensions-a-capability-from-a-binary-rather-than-from-the-vm)
had treated embedding and `dlopen` as two routes to the same place. The question
came with the constraint that separates them, and it is arithmetic: a host is a
**binary**, so *n* capabilities is 2<sup>n</sup> binaries and every new library
re-multiplies the ones already there; a bundle is a **file**, so *n*
capabilities is *n* files and the combination is picked when the program runs.
GTK with big-number arithmetic, or without it, is one host or two — and the
third library makes it eight.

**Nothing here had needed a combinatorial argument before**, which is why the
entry had not made it. This is the first want that is a *set* of wants, and it
settles the mechanism on its own.

### Then the entry's own closing instruction, which it had never been made to follow

It ends by saying the first move is not any of the design above it: *write one
throwaway extension, build it, load it, and find out what the path actually
wants — an afternoon of that would settle more than another page of this.* So
that is what happened, and it settled five things, three of which the page had
guessed wrong. It is parked in
[experiment/extension-probe/](../experiment/extension-probe/).

**The build blocker the page named does not exist.** It said `libsol.a` is
static, nothing is exported, and *a loaded bundle could not resolve `sol_*` back
into `solvm` at all*. `bin/solvm` exports 100 `sol_*` symbols today, because
Mach-O executables export their globals without being asked, and adding
`-Wl,-export_dynamic` changed the count not at all.

**The real one is quieter and is worse for being quiet.** A symbol is exported
only if the executable already *referenced* it, because a linker takes objects
out of an archive on demand. So `sol_object_define_primitive` is there and
`sol_vm_set_global` is not — the second lives in `embed.c` and no front end
calls it. The probe's first load died on exactly that. **The surface an
extension could link against was not a decision anybody took**; it was a side
effect of which objects a front end happened to pull out of the archive, it
differs between the four binaries, and it would change on the day one of them
stopped calling something. An `extend.h` promising a surface determined that way
promises nothing. One flag fixes it — `-force_load`, or `--whole-archive` and
`-rdynamic` on Linux — rather than the change to how the project ships that the
page had proposed.

**The half everyone would expect to be hard is free.** A GLib main loop calling
back into the VM needed nothing built: `sol_vm_call_block` re-enters from a
`g_timeout_add` callback exactly as it does from `array:do`, an error inside a
callback formats a trace that names the `gtk:run` line beneath it, and when the
loop quit the statement after `gtk:run` ran.

### The finding that was worth the whole afternoon

A block handed to GTK as `gpointer user_data` lives in a C struct. `mark_roots`
walks the value stack, the frames, the eight temporaries and the class objects,
and that struct is none of them. Under `gc_stress`:

```
#1
probe: callback failed: 'block' takes 1 argument, got 0
```

The first tick ran, the collection between ticks swept the block, and the second
tick called whatever now occupied the cell — the inner `{ x | x:asString }` from
the same script. **The failure is an arity complaint about a block the program
never registered anywhere.** Not a crash. Nothing pointing at the collector.
Four lines putting the block somewhere `mark_roots` already walks, and the same
binary under the same stress runs clean.

**Which means the foreign cell that entry designs is half a mechanism.** All of
its reasoning is about what an extension hands *out* and how that gets released.
It says nothing about what an extension holds *onto* — and a database would
never have shown this, because SQLite does not call you back. The two named
customers were SQLite and SDL2, and the whole design had been done against the
one that could not reveal the problem.

### The lesson, which is the same one as the hour that produced no feature

That earlier hour found that an entry goes stale not when it is wrong but when
the world moves underneath it and it stays *technically* true. This is the other
way an entry rots: **written from reading, never run, and confidently specific.**
*Nothing exported* and *the fix is to build `libsol` shared* are both the kind of
sentence that sounds measured. Neither was. The tell, in hindsight, is that the
entry itself said what to do about it — write the throwaway first — and then the
page kept being extended instead.

**Nothing was built** at the point that was written. The recommendation is in the
entry, in an order where each step can be falsified before the next: the link
change with `extend.h` and an ABI handshake and a loader *flag* — not a message,
and emphatically not an `@link` directive, which would put `dlopen` inside Solas
— then the foreign cell, then the callback registry, then GTK, out of tree, as
the first bundle worth having.

### And then the first two steps were built, the same day

`solvm --extension=probe.so program.sob` works. `extend.h`, `extend.c`, the ABI
handshake, the flag on `solvm`, `solis` and `solid`, [extensions.md](extensions.md), a
contract test and a real bundle. The whole of it is a header, ninety lines of C
and two argv cases; the language did not change and neither did `.sob`.

**Three things are worth keeping from the building rather than from the design.**

**The Makefile comment is longer than the Makefile change**, and rightly. The
change is one flag. The reason is a paragraph nobody would reconstruct: not that
nothing was exported — a Mach-O executable exports its globals unasked and
`-export_dynamic` changes nothing — but that a linker takes objects out of an
archive on demand, so the surface was whatever each front end happened to
reference. 100, 118, 133 and 118 symbols across four binaries that link the same
library.

**The first version of the test was wrong in the same way the entry had been.**
It asked, from inside the test binary, whether the promised symbols were
reachable — and passed against a deliberately broken build, because the test
binary calls `sol_vm_set_global` on its own account and so pulls in the very
object whose absence was the bug. The check has to be made from *outside* the
program that exports them, which means a real bundle handed to `bin/solvm`. That
now lives in `test_cli.c`, and against the old link it fails with `symbol not
found in flat namespace '_sol_vm_set_global'`.

The lesson is narrower than *test the real thing*. It is that **a test written
by the same reasoning that produced the bug inherits the bug**, and the tell is
that it passed the first time it was run. The dlsym check was kept anyway, with
its comment rewritten to say what it actually holds — a list of names, not a
link — because a weak test that says so is worth more than no test and much more
than one that overstates itself.

**Two conventions were found by the suite rather than by reading.** `make test`
refused a twenty-fourth document while `programs.md` still said twenty-three,
and refused `PENDING` where the changelog wanted lowercase `pending`. Both took
a minute, and both are the kind of thing a person would have shipped wrong.

### And then the foreign cell, which was designed right and scheduled wrong

`SolForeign` went in the same day: a socket or a window as a value the machine
holds and gives back, with `release` called from `free_cell` — the one function
both the sweep and `sol_gc_free_all` go through, so one line closes a socket the
program dropped *and* one it was still holding when a limit took it away. That
was the design as argued weeks ago and it survived contact.

**What did not survive was an assumption nobody had written down**, and only a
real resource could have shown it. The test suite was green. The demonstration
program worked. Then a loop opening five thousand sockets died at 256:

```
solvm: udp: no socket
```

**The release path was fine. The collector had simply never run.** A foreign
cell is forty bytes however scarce the thing it holds, so two hundred and fifty
sockets is ten kilobytes against a sixty-four kilobyte threshold — the heap had
no reason to collect, and the process ran out of the resource that was actually
scarce while holding almost no memory at all.

So bytes are the wrong currency for a descriptor, and foreign cells got a
pressure count of their own. The same program now opens five thousand under a
ceiling of two hundred and fifty-six.

**The tempting wrong fix is worth naming**, because it was available and looked
reasonable: tell extension authors to declare a large `footprint` for a scarce
resource. That would have worked, and it would have made every `--memory` figure
a lie — a number that means *bytes* being set to something else in order to buy
scheduling. The honest fix costs five lines and leaves both numbers meaning what
they say.

**Two things about how it was found.** It was not found by the test suite, which
was green throughout, and it was not found by the demonstration, which opened
three sockets. It was found by asking *what would a program that abuses this do*
and then writing that program — five lines, and the only reason it existed is
that the entry this all came from says to build the throwaway before trusting
the design. That instruction has now paid twice in one day: once on the block
the collector swept, and once here.

### The registry, and a bug in the place that looked safest

The callback registry was the smallest of the four steps and the only one where
the *shape* of the API was the whole decision. It hands back a token rather than
a value, and the reason is narrow: the collector does not move cells, so keeping
a `SolValue` would work — right up to the moment somebody releases it, at which
point a cached value answers a plausible wrong block and a token answers
*false*. **The registry can tell you that you are wrong.** A design that could
not would have reproduced the morning's silent misdispatch one layer up, with
the collector no longer to blame for it.

Which is also why a token carries a generation and not just an index. Release
slot five, retain into slot five, and an old token would otherwise resolve
confidently to the new value.

**And the bug was in the field that carried it.** `next_free` meant both *in
use* and *end of the free list*, both spelled `-1`, so releasing into an empty
free list wrote `-1` and marked the slot live again — after which a second
release answered true and put the slot on the list twice. Two states in one
field.

It was caught by `test_releasing_twice_is_not_an_error`, which is the case that
looked least likely to fail when it was written: releasing twice is obviously
harmless, and writing a test for obviously-harmless is exactly the habit that
pays. The fix is a `bool in_use` beside the index, which cannot be conflated
with anything.

**The probe closed the loop.** `probe_ext_gtk.c` — the file that found the
sweeping problem in the morning — was rewritten onto the registry, and its
`#ifdef PROBE_ROOTED` is gone. The program that produced `'block' takes 1
argument, got 0` prints five ticks and `"done"`, under the same stress, with
nothing conditional left in it.

### The fourth step, which is a different repository

`solveig-gtk` exists, alongside this one and built by nothing in it. That
placement *is* the feature: the front page says *no dependencies beyond a C11
compiler and `make`*, CI checks it on three platforms, and it is still true
because the toolkit is somewhere else.

Fourteen messages, and the two things nobody could settle by argument both hold.
A GTK signal handler re-enters `sol_vm_call_block` exactly as `array:do` does.
And `g_object_ref_sink` turns GTK's floating reference into one the extension
owns and the foreign cell releases, while a parent taking a child adds its own —
so widget lifetimes and the collector agree instead of competing, which was the
half I would have bet against.

**The result worth keeping is that `--steps=400` stops a program with a window
open, mid-loop, and exits 124** with the trace naming the block and the
`gtk:run` line beneath it. That is not free and it is not obvious: it works
because every handler checks `had_error` after calling back into the language,
which is rule 4, which existed only because the probe found it that morning. A
loop that did not look would keep calling into a machine already stopped, and
`--steps` would be a suggestion for any program that opened a window.

**One path a test here cannot take**: a human clicking the button. It is the
same handler path the timer takes, and the timer is verified — worth saying
rather than leaving the gap unmarked.

So the entry that started the day is closed. What it asked for on 2026-08-25 —
*somebody wants a capability that cannot be written in Solum and is not worth
putting in the VM* — was asked on the 28th and answered the same day, in the
order that page set, with the throwaway first and the design second. Which is
the method the page recommended and had never itself been made to follow.

And the corrected sentence went into `design.md` rather than being left to age.
*"Nothing has to be released"* is still true, but for a sharper reason than it
used to be: a resource has a release now, and it was never the program's to run
— which is exactly why an uncatchable stop still costs nothing.

## 2026-08-28 (night) — nine operators, three decisions, and a checker that was right twice

**The region grew to `= <> < > <= >= ~ & |` and stopped being called `@math`.**
Which is the part worth writing down first: the name went wrong the moment the
scope changed, and it was hours old, so changing it cost a `sed` and a test
rename. In six months it would have cost a deprecation. **The cheap moment to
rename a thing is the moment you notice it is misnamed**, and that moment is
usually the one where it feels too trivial to bother.

**Eight of the nine characters were free.** `= < > & ~` all answered *unexpected
character*, which is the same finding the arithmetic operators produced in the
afternoon and the reason this kept being cheap: a language with no operators has
an entire punctuation table sitting unused.

### The one that was not free

`|` already opened a block's parameters and a group's temporaries. I could have
declined it and shipped `&` alone, which would have been worse — an asymmetric
`and` with no `or` beside it is a gap a reader trips over rather than a
restriction they respect.

What made it work is a rule that was already there: **parameters and temporaries
are matched before a body is.** So a `|` reaching the operators is one standing
where an operator may stand, and `{ a | b }` is still a block taking `a`, inside
a region exactly as outside. The compiler and the grammar do the same thing for
the same reason — ordered choice on one side, parse order on the other.

It is still a rule with a *position* in it, which this language mostly refuses,
and the entry says so rather than presenting it as free. The honest summary is
that the position was already load-bearing and this made it carry a second load.

### The checker was right twice, and I was wrong first both times

**Once on the operator list.** I wrote `"=" | "<>" | "<" | ">" | "<=" | ">="`
and check_syntax refused it: *in `<operator>`, `'<'` is written before `'<='` and
would always win — the longer one has to come first.* An ordering bug in an
ordered-choice grammar, which the hand-written lexer never had because it peeks
for the second character. **The two implementations fail differently, so holding
them against each other catches what neither would catch alone.**

**Once on a fixture.** `a := #1 & #2.` had been a test that *both* the compiler
and the grammar refuse a file. `&` is an operator now, so the grammar admits it
and only the compiler refuses — which is exactly the row GRAMMAR.md already
carries about things refused by the compiler rather than by the page. The
tempting fix was to swap the fixture for another mistake and move on. What went
in instead is the swap **plus** an assertion that `a := #1 & #2.` is refused by
`solas` and accepted by the grammar, because that is now a documented property
and a property nothing asserts is a property that will drift.

### And the two calls that were judgement rather than mechanics

**`~` is looser than a comparison**, so `~a = b` is `~(a = b)`. That is what the
words say — *not a equals b* — and what BASIC and Pascal read. C binds `!`
tightest and would have read `(~a) = b`, so this is the one place in the region
where a C habit misleads, and it is called out in the reference and the example
rather than left to be discovered.

**Comparison does not chain**, and the nice part is that this is not a check.
`comparison = sum [ op sum ]` — an optional tail rather than a repeated one —
and the grammar says it structurally, the way `send` says that `o:at(#1) := #2`
is not a way of storing into a collection. `a < b < c` would compare a boolean
to `c`, and refusing it while compiling beats failing while running.

### The shape of the day

A guard nobody asked for, two entries written before any code, a notation, its
prefix form, and then nine more operators and a rename. **The entries were
written first and that is why the implementations had almost nothing to decide**
— every argument that mattered had already been had on paper, and the three
things that came up during the work were the three the paper could not have
predicted: that a lexical region is describable in five productions rather than
eight, that restricting a rule can cost more than generalising it, and that an
ordered-choice grammar has an ordering the lexer does not.

---

## 2026-08-28 (evening) — the grammar as a design tool, and a limit that cost more than no limit

**A report from use, not a program: equations are hard to write here.** Which is
a weaker trigger than this repository usually acts on, and both entries written
today say so rather than dressing it up. Two options were on the table — a
compile-time notation, or a second language whose output Solum could use — and
the scoping took the morning while the notation took the afternoon.

**Refusing the second one was most of the value.** Phoenix is buildable: three
compilers here already target `.sob`, `pascal.sol` did eight stages in a day,
`lib/sob.sol` writes the format so the back end costs nothing. So the question
was never *can we*, and answering the one that was actually asked meant noticing
that a language whose distinguishing feature is infix arithmetic is a few
thousand lines answering a question a notation answers in two hundred. What the
entry keeps instead is the half with no precedent at all: every hosted language
here produces a *closed program* — no `exports`, a `HALT` at the end of the
chunk, Pascal's globals prefixed so they cannot collide — and whether `.sob` is
a language-neutral object format has never been asked.

### The grammar turned out to be a design tool

**The first draft of the notation was wrong, and the grammar is what said so.**
I put the arithmetic ladder inside a `math` production of its own, which is the
obvious shape: a region has its own rules, so give the region its own
productions. Then `(a/2):sin` needed a math-flavoured group, and an argument
needed a math-flavoured argument list, and a block body needed a math-flavoured
body — the whole expression grammar again, eight productions, on a page whose
virtue is being short.

**The rule I had implemented was better than the grammar I was writing for it.**
A region is *lexical*: it covers everything inside it. Written once at the top
of `expression`, the ladder says exactly that in five productions and the nested
cases come free. GRAMMAR.md and `solum.bnf` went from agreeing on 23 productions
to agreeing on 29.

That is the thing worth carrying: **the grammar is checked, so it is not
documentation, it is a second opinion.** Nothing else in the day would have
asked whether the region's rule could be stated once instead of eight times.

### The limit was more expensive than no limit

**The proposal was to add `sin(x)` for the float type only, to keep the scope
small. Scoping it is what would have cost something.** A blessed list of names
has to appear in `solum.bnf` as word literals, and `check_syntax` reserves every
word-shaped literal a syntactic rule mentions — so it answers
`reserved against <identifier>: cos sin`, and *there are no reserved words at
all* stops being true. `test_cli` asserts that report carries no such line. The
general rule costs nothing there, `identifier` not being a word.

I checked that by running it rather than by reasoning about it, which took two
minutes and reversed the answer. **The safe-looking version was the costly one**,
and there was no way to see that from the shape of the proposal.

### An objection can dissolve instead of being overruled

I had held the prefix form back that morning, in writing, for a stated reason:
`f(x)` to `x:f` breaks on `float:atan2`, which is class-side, and on `pow`,
which takes an argument. Both are **two-argument**. A prefix form that takes
exactly one has no two-argument form for them to break — so the rule became one
sentence with no exceptions rather than a rule with two carve-outs.

```
@expr( 1 + 2 * 3 ):print.               ; 7
@expr( sqrt(9.0) + 1 ):print.           ; 4
```

Changing a position I had written down the same morning is worth doing plainly
and worth separating from being overruled: the premise stopped applying, and the
entry says which of the two happened.

### Two smaller things

**A guard caught a regression I would not have looked for.** Making `+` a token
changed `1e+` from scanning as float, identifier, error to float, identifier,
`'+'`. `test_lexer` failed on it immediately. That fixture exists because the
self-hosting work found that 33,000 tokens of working Solum contain no `1e`
followed by a non-digit — working code does not contain the corners — and
somebody wrote the corners down anyway. The program is rejected either way and
by the same message, so what moved is where the complaint comes from.

**And the marked counts moved five times today**, each one a failing build until
I edited the sentence. This morning's entry argued that a number changing faster
than its page does not belong on the page, and a claim count that moves on
nearly every documentation edit looks like a counterexample. It is not, and the
distinction is sharper than what I wrote then: *a claim count moves when the
documents change, which is exactly when somebody is editing them anyway.* A
changelog hash count moves when a **commit** happens, which is never when
somebody is looking at `programs.md`. The rule is not about how fast a number
moves. It is about whether it moves at a moment when somebody is already there.

---

## 2026-08-28 (later) — a hash nothing checked, and the number I nearly wrote down

**The entry was a day old and the guard took an afternoon**, which is the ratio
this repository keeps arguing for: 3.21 was written down yesterday morning
rather than fixed on the spot, and everything the writing settled was still
settled today.

The origin is worth keeping straight. Every changelog entry names the commit it
landed in, and a commit cannot carry its own hash — so the entry goes in saying
`pending` and a follow-up commit substitutes the real one. That substitution
failed once: the PRINT USING entry of 2026-08-26 carried a literal `%s` where
its hash belonged, survived two days and every `make test` in between, and was
found while cutting 0.35.0 **by a person reading the page**. Nothing was looking
for it, because nothing had ever been asked to look.

**The rule had to be fitted to the page, not the page to the rule.** My first
version read the first backticked token after the em dash, which is what 242 of
the 244 headings look like. The other two are not shaped like the rest: one
names two commits joined by `and`, and one names a commit and no date. Both are
right as they are. A rule that read only the first token would have been a rule
those two entries had to be rewritten to satisfy, and rewriting the subject so
the checker is happy is the checker measuring itself. So it reads *everything*
backticked after the **last** em dash — last, because a title may contain an em
dash of its own, and several do.

That is the same lesson `expect.sol` already carries in a comment about the
three comment conventions the examples turned out to use, learned again in a
different corner. It seems to be the standing hazard of writing a checker: the
first draft always encodes what you assumed the subject looked like.

**The blind spot is stated rather than hidden.** A heading that loses its em
dash and everything after it is indistinguishable from a section heading
*inside* an entry — and five headings are genuinely that. There is no rule that
separates them, so both counts are reported and the second one moving is visible
to whoever reads a run. Reporting a gap is not as good as closing it, but it is
much better than a silence.

**The stronger version was declined, exactly as written down.** Asking git
whether the hash names a real commit catches a well-formed hash that is simply
wrong, which the substitution can produce. It would couple `expect.sol` to a
repository — it reads files and runs programs today, and a tarball with no
`.git` in it checks clean. The interesting part is that building the weaker one
produced no new argument in either direction. The entry had done the thinking a
day early and the implementation had nothing to add to it, which is the case for
writing these down rather than deciding them at the keyboard.

**And then the sin, committed while documenting the cure.** The run says how
many entries name a commit, and I wrote that number — 244 — into the changelog
entry, into COMPLETED.md, and into a comment in `expect.sol`. Three documents,
by hand, stating a count that changes with the *next* changelog entry. That is
precisely the failure 3.16 was about and precisely what this guard was being
built to stop, and I did it in the same hour, in the prose describing it.

Taking them out clarified something about the marker notation that had not come
up before — and the clarification cost a failing run of its own, because writing
the marker into a sentence *is* writing a marker, and the checker duly reported
that nothing counts the empty name I had put in it. So: the count comment is for
a number that moves *rarely* — how many programs there are, how many slots
`integer` has — because a marked number that has moved is a failing build until
somebody edits the sentence. A number that
moves on every commit cannot be marked; it can only be reported by the run, or
not stated. So the rule is not *mark every number in prose*. It is: a number
that changes faster than the page does does not belong on the page.

A journal entry is the exception, and this sentence is why: 244 today is a
record of a day rather than a claim about now, which is the whole difference
between this file and the other two.

**Verified by breaking it four ways** — a literal `%s`, an eight-character hash,
a heading with the hash cut out and the date left behind, and a `pending`. Three
failures and one accepted-and-counted, then the page restored. `test_cli` got a
floor beside the ones for claims, counts, positions, SolaBasic blocks and
grammar productions, because a guard that quietly stops finding anything to
check is a guard that has stopped.

The first thing it watched was its own entry: the changelog said `pending` from
the feature commit until the follow-up landed, and the run said so out loud each
time in between. Which is the state a release cut had been finding by eye.

---

## 2026-08-28 — five libraries, four boundaries, and one that should not have one

**3.20 was meant to be an afternoon of applying a finished feature to five
files.** It was not, and the first library made that clear: `scan` is a
*prototype*. `scan:on` answers a new cursor, and every cursor a program holds is
one of those. Drawing a line on `scan` would have hidden the prototype's default
`src` and left every real cursor's text public — protecting nothing anybody
holds.

So the feature shipped yesterday was half a feature and the only way to find
that out was to use it. Boundaries are inherited now: an object under one is its
export list whether it drew the line or got it from its prototype. Which
immediately broke every constructor, because `scan:on` runs with `scan` as its
self and fills in a cursor that is not `scan` — so a second rule went in, that a
method on a prototype may reach into an object made from it. Only downward.
Reaching up into a prototype by name stays refused.

Both rules are one sentence each and neither was in the design I wrote out
yesterday evening. I had reasoned about inheritance and got it exactly backwards:
I checked that a *child's* method could reach what it inherited, which works,
and never asked what a *parent's* method could reach, which is where every
library actually lives.

**Then the libraries, and three findings.**

`html` binds two objects, not one — a parser and the node prototype a read
answers — and they need separate lines with the inner drawn first, since `html`'s
own boundary otherwise puts `element` outside it and refuses the very next
statement. That is the ordering rule from last night arriving in practice about
twelve hours after being written down.

`html:element` publishes `add` and `at`, which were meant to be private. The
parser builds the tree from outside an element: the factory is a method on
`html`, and a node delegates to `html:element` rather than to `html`. Same shape
as `json:quote` — public in fact, and nothing had said so.

And the one worth the whole exercise: **`html` was reaching into `scan`'s
internals.** It sliced a cursor's own text with
`self:cur:src:copyFrom(start, self:cur:pos:sub(#1))`, where `scan:since(start)`
says the same thing and had existed since `scan` was written. Nothing had
stopped it, so nothing had noticed — and `since` is not an obscure corner of
`scan`, it is one of the fifteen messages the reference documents. The boundary
did not prevent a bug there. It found a place where an API had been bypassed and
quietly reimplemented, which is the thing an export boundary is actually for.

**`shell` got no boundary and that is the finding for it.** Four slots, all four
the API. A line listing everything hides nothing, and a boundary that hides
nothing is exactly the decoration this project rejects when a reflection walks
around one. Five libraries, four boundaries, and one honest *no*.

### Postmortem

Two days, one arc: a question about whether one `.sob` could load another, and
everything that turned out to be behind it — `system:load`, its once-only
memory, the debugger's view of it, `exports`, and the five libraries.

1. **The question was worth more than a request would have been.** It arrived as
   *is this feasible, would it need different memory blocks?* — and the honest
   way to answer was to build the smallest thing that would settle it before
   saying anything. That produced a thirty-line C host, which produced the
   answer (the separation already existed; only the globals were ever shared),
   which produced the feature. Had it arrived as *build system:load* I would
   have started from the design instead of from the premise, and the premise was
   the part that was wrong.

2. **ROADMAP 3.6 was reached by experiment rather than by reading.** Freeing the
   loaded chunk segfaulted in `sol_vm_call_block`, exactly as the entry says it
   would. I had read that entry — I quoted it in the same session — and still
   did not predict the crash until ASan printed it. **A limitation you can
   recite is not the same as one you have felt**, and the second is what makes
   you design around it.

3. **The house GC check ended in deletion, for the first time.** The rule here
   is to prove a new temporary root is load-bearing by removing it and showing
   the ASan report. I removed it expecting a crash and got a clean suite:
   `serialize.c` is handed no VM, so loading cannot allocate anything the
   collector knows about. The check earned its place by contradicting the person
   running it, which is the only way a check ever earns anything. The root came
   out and the comment now says why there is nothing to guard.

4. **Two performance bugs, one shape, and only measurement found either.** The
   first version of the boundary built the sender's `self` on every send for a
   test that discards it whenever the slot is exported — 8.7% of a send-only
   loop. The assignment path did the same with a walk up the prototypes. Both
   read as obviously cheap and both were the most expensive line in the change.
   **Cheap-looking work on the hot path is where the cost is**, because nobody
   measures what they already believe.

5. **I got the inheritance rule exactly backwards in design.** I reasoned about
   privacy and inheritance for several paragraphs, and what I checked was that a
   *child's* method could reach what it inherited. It can. What I never asked was
   what a *parent's* method could reach — and that is where every library lives,
   because a constructor runs on the prototype and fills in an object that is
   not itself yet. The rule that was missing is one sentence long. **A design
   pass that only tests the case you thought of is a design pass that agrees
   with you.**

6. **The same feature shipped half-finished twice, and use found both.** No
   once-only memory, defended in the changelog as a choice; and a per-object
   boundary that would have protected `scan`'s prototype and left every real
   cursor public. Neither survived contact with a second user of the feature,
   and neither would have been caught by rereading the design. **The first real
   use is the design review**, and shipping before it is how you find out what
   you decided without noticing.

7. **The boundary's best find was not a bug.** `html` sliced a cursor's own text
   where `scan:since` says the same thing and had existed since `scan` was
   written. Nothing was broken; the two are the same slice. What the boundary
   found was an API that had been bypassed and quietly reimplemented, in a file
   whose author had read the other file's documentation. **A boundary is a
   question — "did you mean to reach in here?" — and it gets asked in places
   nobody would think to look.**

8. **A green suite can be green for the worst possible reason.** `examples/load.sol`
   loaded `examples/library.sob`, bytecode is gitignored, nothing built it, and
   it existed only because I had compiled it by hand while testing. It passed
   all day and would have failed on any fresh clone. It was found by writing a
   *second* example of the same shape, not by anything looking for it. The fix
   is four lines of Makefile; the check that mattered was `rm -f examples/*.sob`
   and running the suite twice.

9. **Two refusals, and they were work too.** Declared dependencies is the fourth
   job a module system does, and the reasoning against it — `@include` already
   *is* a declaration; ordering and cycles are already settled; it would be a
   fourth mechanism where three reach — took longer to write than a small
   feature would have taken to build. `shell` got no boundary for the same kind
   of reason: four slots, all four the API, and a line listing everything hides
   nothing. **Recording why something should not exist is cheaper now than
   deciding it again later from a blank page**, which is the argument this
   repository has been making about `ideas.md` since it started.

10. **The repository asked for four things I had not thought to write**, and
    named each by file and line: an example that sends the new message, an entry
    in the reference's index, a line in the cheatsheet, and six counts that had
    moved. Then `expect.sol` could not read the word *thirty*. Every one of those
    is a guard somebody wrote after being burned, and together they are the
    reason a day of language changes ends with the documents true rather than
    with a note to fix them later.

---

## 2026-08-27 (night) — an example that found a bug in the morning's work

**Asked for an example of `system:load`, and the first thing to settle was
whether one was wanted at all**, since `examples/load.sol` had gone in with the
feature. It teaches the mechanics: what it never shows is the difference that
outlives all the others. `@include` needs a literal string, because the file is
found while the includer is being compiled and a name holding one has no value
yet. `system:load` is a message, so the name is an expression — and a program
can run a file it worked out while running.

So `plugins.sol` names none of the files it runs. It looks in a directory,
finds the compiled modules, loads each and uses it. The two modules draw export
boundaries, which ties this morning to this evening: reaching into a module
whose name nobody wrote down is exactly the case where you would rather not be
able to.

**And writing it found that this morning's example was broken for everybody but
me.** `examples/load.sol` loads `examples/library.sob`. Bytecode is gitignored,
nothing in the Makefile built it, and it existed on this machine only because I
had compiled it by hand while testing. On a fresh clone the example fails and
`make test` fails with it. It had been green all day for the worst possible
reason.

The fix is four lines of Makefile — every example compiled to bytecode,
wildcarded rather than listed, for the reason the install rule beside it already
gives about hand-kept lists going stale. What matters more than the fix is how
it was checked: `rm -f examples/*.sob` and then `make test`, twice, rather than
trusting that a rule which looked right was right. Thirty-four files rebuilt and
the suite passed.

**The header of `load.sol` had been wrong in the same way** and nobody would
have noticed until they typed it. It said to compile `load.sol` and run it,
which was never enough: compiling the file that loads does not compile the file
it loads. It says `make` now, and says why — which turns a papered-over
assumption into the first thing loading asks of you that including does not.

A day that shipped four features ended by finding that the first one's example
had never worked anywhere but here.

---

## 2026-08-27 (evening) — the half that needed a new concept

**`ideas.md` had said for years why this could not be built**, and quoting it
back was the right place to start: privacy "needs something the language has not
got: slots cannot be removed and `slots` lists everything, so it would be a new
concept rather than a use of existing ones."

Half of that was true. It *is* a new concept — a slot now carries a bit saying
whether anything outside may reach it. What was wrong was the unstated
conclusion that a new concept is therefore too expensive. It came to one
message and one rule.

**The design took longer than the code.** Three questions decided it.

*Where does the check go?* The cheap answer is compile time — solas already
keeps `BoundName {name, file}`, so it could refuse `json:digits` in a file that
did not bind `json`, at no runtime cost. It does not hold: it cannot see through
`perform` or through `x := json`, and as of this morning a library can arrive
already compiled through `system:load`, from someone who never saw your names —
which is the exact trigger `ideas.md` names for wanting this at all. A boundary
that only exists while compiling is not one for the case that motivated it. So:
run time, at dispatch, beside `receiver_suits`, which already refuses a resolved
slot to a receiver that does not qualify.

*What does inside mean?* The frame doing the sending is running with the
receiver as its own self. That one sentence gives inheritance for free — the
comparison is against the *receiver*, not against whichever object in the chain
holds the slot, so a child's method reaches what it inherited and a sibling does
not. It also puts a program's top level outside everything, which is the intent
rather than an accident.

*May an outsider add a slot?* I nearly allowed it, on the reasoning that a name
that does not exist cannot be private. It is the wrong reasoning: binding a name
that happens to collide with something private would quietly overwrite a slot
the binder is not allowed to read, which is the original accident wearing a hat.
Making the export list the whole external surface removes the case instead of
handling it.

**Then the ways around it.** `slots` I had gated from the start. `slotAt` I had
not, and it answered a private slot's value straight out. `respondsTo` I had not
either, and its own comment in `builtins.c` makes the argument against me:
answering true for something a send would refuse "would make `respondsTo`
disagree with sending". `perform` came free, since it goes through
`sol_vm_send`. A boundary any one of those walks around is decorative.

**Drawing the line on the real library found something.** `json` publishes
`read` and `write`, so I exported two names, and the library broke — because
`string:asJson := { json:quote(self) }` is a method on *string*, where self is a
string, so its call back into `json` arrives from outside. `quote` and `keyText`
had to be exported too. They were public in fact before they were public on
purpose, and nothing had ever said so. That is the feature paying for itself on
its first real use: what it makes visible is the API you actually have.

**And the cost was 8.7% until it was measured.** The first version built the
sender's self on every send and handed it to a check that discards it whenever
the slot is exported — which is nearly always. Testing the bit first, so the
value is not built unless the bit is clear, brought it to where thirty runs
cannot separate the two builds, on a send-only loop or on a real program. I
took the measurement against a worktree built at the previous commit rather
than against a remembered number, and ran it in both directions, because the
first run's variance was high enough to be suspicious. It was real, and then it
was not.

**And the last row was closed by deciding not to build it.** Declared
dependencies is the fourth job a module system does, and with three done it was
the obvious next thing. It should not be built, and the reasoning is now in
`ideas.md` rather than left as an empty cell.

The short of it: `@include "json.sol".` *is* a declared dependency — it stands
alone, it comes first, it names what the file needs, and the compiler acts on
it. What a module system adds is separating the declaration from the fetching,
which pays when a thing must be found among alternatives or resolved against a
version. Neither exists here. And the mechanical job dependency graphs are
usually computed for — ordering, and cycles — is already settled by once-only
loading in both mechanisms, without anyone declaring anything.

The one real gap is recorded so the trigger is legible: a `.sob` does not say
what it needs, because `@include` leaves no trace in bytecode and `system:load`
is a message. That costs nothing today and would start costing something the
moment anybody ships compiled Solum and wants to know what to load first. So
the trigger is packaging, which is a different trigger from the two that opened
the other rows — those turned on somebody else *writing* a library, this one on
somebody else *distributing* one.

Three features and a refusal, which is a better day's work than four features.

---

## 2026-08-27 (later) — a question about memory, answered by not needing any

**The day started as a question, not a request.** *Is it feasible to import a
precompiled `.sob` into a program — would that require different memory blocks
or something?* The honest way to answer was to try it before saying anything, so
the first hour produced no feature at all: a `lib.sol` binding a block, a value
and a method on `integer`; a `main.sol` using all three without including
anything; and a thirty-line C host calling `sol_chunk_load` and `sol_vm_run`
twice on one machine.

It printed all three. **The premise of the question was the thing to answer**:
no separate memory is needed, because the separation already exists. Every chunk
carries its own names, constants, code and slot count, and `SolFrame` has
recorded which chunk it belongs to since blocks were written — that is why a
block defined in one file was always callable from another. The only shared
thing is the globals, and that sharing is not an accident to be worked around
but the mechanism: `OP_GLOBAL` resolves by name at run time, which is why
`main.sob` compiles perfectly well alone and fails only when run.

**The one real constraint showed up when I freed the chunk**, which segfaulted
under ASan in `sol_vm_call_block` — ROADMAP 3.6, exactly as written, reached by
experiment rather than by reading. Loading into a `sol_code_new` cell instead
ran clean. `bytecode.h` had said so all along: a code cell is "ready to compile
or **load into**".

So the answer was *yes, and most of it exists*; the missing piece was a way to
reach it from inside Solum. Hans asked for that next, sharing globals the way
`@include` does.

**The implementation is two functions and neither is clever.** `sol_vm_call_chunk`
is `sol_vm_run`'s nested twin, and it is defined by what it does *not* reset —
the error state, the step budget, the frames and the stack all belong to the run
underway. `prim_system_load` loads, verifies, and calls it. `run_frames` already
took a base frame index, because `sol_vm_call_block` needed re-entrancy years
before this did.

**Both bugs were lifetime, and both were found by tests rather than by reading.**

The first is the one worth keeping. `sol_chunk_load` initialises the chunk it is
given — it must, since `solvm` hands it a bare one — and initialising clears the
owner `sol_code_new` had just set. Every method loaded afterwards inherited that
nothing, so every block the file defined pointed at a chunk the collector would
not root. Without `SOLUM_GC_STRESS` it passed. With it, `greet:value("world")`
came back as `'(null)' takes 0 arguments, got 1` — an arity read out of freed
memory. It is the kind of bug that would have shipped, because the happy path is
genuinely happy until a collection lands in a two-instruction window.

The second I put there myself. I held the chunk across the nested run with a
temporary root, forgetting that the temporary roots are eight deep with an
`exit(1)` on top — so a file loading itself killed the process at depth nine,
with no message. Dropping the root before the guest runs fixed it, because a
frame executing a chunk roots it; the limit became the machine's own 256 and the
ending became `call depth exceeded`, which is a failure a program can see.

**And then the root turned out to be unnecessary at all.** The house rule here
is to prove a new GC root is load-bearing by removing it and showing the ASan
report. I removed it expecting a crash and got a clean run — under ASan, under
`gc_stress`, the whole suite. The reason is good: `serialize.c` is handed no VM,
so it cannot allocate anything the collector knows about, and a string constant
stays chunk-owned bytes until `OP_STRING` makes a string of it. Solis roots its
submission because compiling allocates. Loading does not. The root came out and
the comment now says why there is nothing to guard. **The check earned its
place by contradicting me**, which is the first time it has.

**The repository asked for four things I had not thought to write.** The build
refused the feature until `system:load` was sent by an example, listed in the
reference's index, listed in the cheatsheet, and counted correctly in six
documents — and it named each one in turn, by file and line. Adding
`examples/load.sol` moved counts in `COMPLETED.md`, `programs.md`, `TUTORIAL.md`
and `index.md`, and one of them wanted the word *thirty*, which `expect.sol`
could not read: it knew `numberWords` to twenty and `tensWords` for hyphenated
pairs, so it read *twenty-nine* and *thirty-one* but not the round number
between them. Six lines fixed that.

**What it deliberately did not do — for about an hour.** I shipped it without a
once-only memory and wrote the reasoning down: `@include` is keyed by where a
file lands on disk, a message has no such key, and a message that silently
declined to do its work the second time seemed the stranger thing. Hans read
that and asked for the memory. He was right, and the argument against it was
thin in a way that is worth recording: once-only is not a convenience laid on
top of loading, it is *what makes loading composable*. Without it, two files
that each need the same library have to agree between themselves about who asks
for it — which is precisely the arrangement `@include` exists to spare people.

The fix is small and mostly borrowed. The identity is the realpath, as
`@include`'s is, so three spellings of one file are one file; the list belongs
to the machine rather than to a compilation, which is the only real difference
between them. The file is written down *before* it runs, and that one ordering
choice is what makes a cycle end rather than recurse — the same thing `@include`
means when it says a cycle ends on purpose. It is written down only after it is
known to load and verify, so a file that was never usable is not remembered as
one that was.

**The answer became a boolean**, which the codebase argued for rather than me:
`makeDirectory` already answers true for one it made and false for one that was
there, and that is the same question about the same kind of idempotence. It
keeps a second load from being a silence.

**Removing a runaway removed a test.** The frame-limit case was a file loading
itself, and once-only means it cannot nest at all any more. Rather than lose the
coverage — that path had a real bug in it a few hours earlier, the eight-deep
temporary roots and their `exit(1)` — the test now generates a chain of three
hundred distinct files. It still ends in `call depth exceeded`.

**And one fence could not be checked**, which was worth learning rather than
working around. `expect.sol` runs a block from a document in a scratch directory,
deliberately: documentation shows how to delete things, and one `writeFile`
snippet had once put a file back into the repository that a commit had removed.
So a fence cannot load a `.sob` by relative path. The demonstration moved to
`examples/load.sol`, which is run from the root and is checked; the fence in the
reference is tagged `text`, which is what that program asks for when a block is
a sketch rather than a program.

**And then the debugger, which turned out to be an afternoon of writing tests
for things that already worked.** Hans asked for "the same for solid" after the
same question about solis, where the answer had been that it works for free.
Solid was the more interesting bet: a loaded chunk brings its own file and its
own line table, so the debugger has to follow a stack that spans two files that
were compiled separately.

It follows it. `step` goes in, `next` goes over, `finish` comes back out,
`where` names each frame's own file, `list` finds the loaded source, and a
breakpoint set in a file that has not been loaded yet fires when it is. The best
of them is the failure case: an error inside a loaded file stops in that file
with the loading frame underneath and both files' globals readable. None of it
needed a change, because `sol_vm_call_chunk` pushes an ordinary frame and Solid
was written against frames rather than against the program.

**Which left the question of what the deliverable is when nothing is broken.**
Five tests, because behaviour that works by construction is behaviour nothing is
holding in place. One of them covers the case loading makes ordinary rather than
exotic — a library shipped as bytecode with no source beside it, where `list`
says `cannot read` and everything else keeps working.

Two blemishes looked at and left alone. A loaded chunk's last step lands on a
line one past the end of its file, and so does an ordinary script's: that is how
`HALT` is attributed, not something loading introduced. And both frames say *in
script*, which is true of both — the file names already tell them apart, and
changing the label would be a cosmetic edit to shared code for a distinction the
line above it already makes.

The one real omission the afternoon found was in the morning's work: the
reference's contents never listed *Loading a compiled file*. Fixed, and every
in-document anchor checked rather than that one.

**What it still does not do.** There is no namespacing, so the last binding of a
name wins in silence — 3.10 arriving from a third direction, now between files
compiled separately that never saw each other. Loading twice is no longer one of
the ways that happens; two different files claiming one name is untouched. And
the memory itself is a second list nothing shortens, beside the globals, which
is the same leak this entry is a face of.

---

## 2026-08-27 (Pascal) — eight stages, and a compiler that agrees with a real one

**A Pascal compiler, in eight stages, between 07:49 and 12:19.** What follows is
the day in the order it happened; the postmortem for the whole of it is at the
bottom.

Stage 1 first: it compiles, it runs, and five programs produce the same bytes as
`fpc -Miso`.

**The oracle was installed before the compiler was started**, which is the
reverse of SolaBasic, where it arrived at stage 7. It paid immediately — before
a line of the compiler existed it established that `fpc -Miso` accepts both
Pascal files this repository already ships, which is the first evidence
`pascal.bnf` describes Pascal rather than this project's idea of it. And it
supplied every default field width, so the write routine was written against
measurements rather than guesses.

**The type checker is the difference from `sola.sol`.** That compiler's header
says everything a SolaBasic program computes is a Double, and one numeric type
needs no analysis. Two need all of it, because Solum refuses `#1:add(1.0)` and
there is no implicit conversion anywhere in the machine to lean on. So every
expression rule answers a *type*, and that answer is the whole of the checking —
there is no tree to walk afterwards.

**`mod` came free and `div` cost nine instructions**, which is exactly the
reverse of SolaBasic. ISO wants a non-negative remainder for a positive divisor,
which is floored, and the machine floors. ISO wants division truncated toward
nought, and the machine floors. Two languages wanting opposite things from one
machine, and each getting one of them for nothing.

### The verifier says one thing and means several

Two mistakes both produced `bytecode is internally inconsistent` and nothing
else. A jump offset measured from the wrong place — `OP_JUMP_IF_FALSE` is five
bytes where `OP_JUMP` is three, because it carries the selector it was inlined
from, and the C compiler's own `patch_jump` has a comment saying exactly that. A
scratch slot handed out one past the end of the frame, because slots count from
nought and I wrote the size.

Both were found the same way: bisect a working program down to the construct
that breaks. That is the only tool that message leaves, and it is enough — but
it is worth noticing that the verifier knows which slot was out of range and
does not say.

**Stage 3 produced a third one**, and this time bisecting found nothing, because
*every* procedure failed. The disassembler did: it reads a `.sob` without
verifying it, and it showed the block's instructions correctly and every one of
them at **line 0**. A method's line runs have to cover every byte of it, and I
closed the top-level chunk's and not each method's. Three different mistakes,
one message — and the useful lesson is that `disasm.sol` is the tool for this
and not bisection, because it reads the file the verifier refused.

### A claim written down before it was checked, and wrong

The compiler's header said `fpc -Miso` diverges from the standard, answering
`-1` for `-3 mod 2` where ISO requires a non-negative remainder. It came from
reading the oracle's output on the first day and it was **wrong**. Pascal's sign
belongs to the whole *term*, so `-3 mod 2` is `-(3 mod 2)`, and `-1` is correct
in both. Asked with a variable holding `-3`, both answer `1`.

**A compiler for a language whose grammar it has just read is exactly the place
to misread precedence**, and being the author of the grammar file is no
protection at all — it may be the opposite. The note stays in the header rather
than being deleted, because the mistake is more instructive than the correction.

That is the second time in two days a number or a claim went into a comment
before it was measured. The first was two performance figures wrong by a factor
of four. Nothing forces the guess; the check takes a minute; and a claim in a
comment reads exactly like a checked one.

### Stage 2, and a type that is two things at once

`const`, `type`, enumerations, subranges, `case`, `repeat`, `for`, `goto`, and
seven of the required functions. Ten programs agree with `fpc -Miso` where five
did.

**The whole stage turned on splitting one word into two.** Stage 1 had a type as
a symbol — `'integer`, `'real` — and stage 2 cannot: an enumeration is an
integer to the machine and a `Colour` to the language, and a subrange of `char`
is a character to the machine and a `1 .. 20` to the language. So a type is an
object with a `run` and a `kind`, every check reads `kind`, every emitted
instruction reads `run`, and `ord` of an integer emits nothing at all.

That is a small idea and it removed every difficulty the stage had. It is also
the idea I would have got to eventually by patching `'enum` into the symbol
comparisons one site at a time, and the reason it went in cleanly is that stage
1 was small enough to rewrite rather than extend.

**`repeat` was the one real defect**, and it is a good one. `OP_JUMP_IF_FALSE`
only jumps forward and `OP_LOOP` is unconditional, so *loop while this is false*
cannot be written as one instruction — the false case has to jump over an exit
and into the loop back. Spelled the way the sentence reads, the loop inverts:
`repeat i := i + 1 until i >= 3` leaves `i` at 1. It printed `1` where `3` was
expected and everything else in a twenty-line test was right, which is exactly
the kind of wrong that a transcript catches and reading does not.

### Stage 3, and the pass I did not want to add

Procedures, functions, `var` parameters, recursion, `forward`. Thirteen programs
agree with `fpc -Miso` where ten did.

**The `var` parameter is where the single pass died.** The box is settled
prior art — `sola.sol` says *by reference is a box, and the variable is the
box* — and Pascal makes the callee's half trivial, because `var` is declared
rather than inferred. The caller's half is not trivial at all: whether `g` needs
boxing depends on whether *any* procedure anywhere passes it by reference, and
the procedure that does may be declared after the one that reads it. By then the
read is emitted.

I looked at three answers. Box every variable: correct, simple, and an
allocation plus two sends on every access in every program to buy a case most
programs never use. Copy in and copy out: a different language the moment two
parameters name one variable. Parse twice: the first pass fills the set, its
output is thrown away, and the second emits with the answer in hand. The third
is what `sola.sol` does in four passes and I had been quietly proud of not
needing.

**It cost about fifteen lines.** `compile` calls `parseOnce` twice. Everything
else already reset itself between units, so there was nothing to unpick — which
is a fact about stage 1 having been small, not about foresight.

### Stage 4, and two predictions that held

Nested procedures. This is the stage the design rested on and the one both
predictions were written for, and there is not much of a story: it worked.

A nested procedure is a block made inside its parent's activation, kept in a
slot of that frame. `OP_BLOCK` captures the frame it was made in; `OP_OUTER
depth slot` reads out along the lexical chain. That is a static link, and
Pascal's scoping is static links. **Nothing was added to the machine**, which
was prediction two.

The part that felt like it should have been hard and was not: recursion of the
*enclosing* procedure. Each activation of `Nest` makes its own `Show`, bound to
its own frame, because the block is created by the parent's own code and not
once at load time. `3 2 1 1 2 3` came out right the first time it ran.

**And these are the first blocks this repository has ever produced that capture
their home.** `sola.sol` says in its own comments that flag 2 would mean
reaching out of its own frame *and nothing here ever does* — which is how the
prediction was made. The disassembler now prints `captures` on four nested
procedures and not on the two enclosing them, and a test asserts both halves.

The one real mistake was mine and not the machine's: a leftover
`entry:at(#3):equals('global)` from stage 3, where that field had become a
*level* and `'global` a symbol it could never equal. It made a global passed by
reference emit `LOCAL 0` — the reserved slot — so the callee dereferenced nil.
Changing a representation and leaving one reader behind is the oldest mistake
there is, and the thing that caught it was the oracle: thirteen programs had
agreed the run before.

### Stage 5, where the machine's one collection had to be two languages' worth

Arrays and records, and they are the same thing underneath — a Solum array, with
the compiler holding the difference. A field is an index it worked out; a
subscript is the Pascal index less a lower bound it also worked out. That part
was easy and stayed easy, including an array indexed by an enumeration, by a
character range, and by `boolean`.

**The two things that needed emitting rather than assuming were both about a
Solum array being a reference.** Making one has to be a loop, because a size is
a compile-time constant and a program may ask for a thousand — so the code grows
with nesting and not with size. And assigning a whole one has to *copy*, as deep
as the type goes, or two Pascal names would be one thing. Neither is difficult;
both are the sort of thing a compiler gets wrong by not thinking about them, and
the test that catches the second is three lines.

**The designator is the part I would have got wrong without writing it down
first.** A read leaves the value and a store stops one step short, leaving the
container and the index — and knowing which is wanted before the last step is
emitted is the only lookahead any of it needs. A whole variable with no
selectors is a third case, because a store into one has no container at all.

**Two mistakes, both caught by the oracle rather than by me.** `hi - lo` on a
subrange of `char` asked a string for `sub` — the ends are held as characters,
because that is what the source wrote and what a `case` label has to compare
against. And `array [boolean]` wanted a boolean's ordinal, which on this machine
is a jump; the index step now asks `emitOrd`, which was already written for
`ord` and already handled all three cases. **The second is the better one: the
code to do it right existed and I had written a narrower thing beside it.**

### Sets, and the machine correcting a plan written before it

Half of stage 6. `set of T`, the constructor, `in`, the three combining
operations and the four comparisons; files are the other half and are next.

**The plan was wrong and the machine said so in one line.** PASCAL.md, written
before any compiler, said a set would be an array of integers with one bit per
member — the obvious representation, and the one every Pascal uses. It meets
ROADMAP 3.12: `1 shiftLeft 63` overflows, because SolVM's integers are signed
and there is no unsigned type to borrow. A 64-bit word would have to be a
63-bit word, or the top bit handled apart from the other 63 everywhere it is
touched.

Checking that took one four-line program and it was the first thing I did.
**The plan was three days old and had never been executed**; a representation is
exactly the kind of decision that reads as settled and is not.

So: an array of booleans. Membership becomes one index, which is what a program
writes most, and a `set of char` costs 256 booleans instead of four integers.
Everything else was a loop either way, so the bits would have bought memory and
nothing else — which is the part that made the trade easy once the shift had
been tried.

**The one real bug was `>=`.** `a >= b` is `b <= a`, so the operands are
exchanged — and I exchanged the *names* before the stores, which meant the
stores put them back. Three of the four comparisons were right and that one
answered `<=`. The fix is a line moved rather than changed, which is the shape
of mistake that survives reading.

### Reading, and the difference between a gap and a decision

The other half of stage 6. `read`, `readln`, `eof`, `eoln` — on standard input
and nowhere else.

**That last part took longer to decide than to build.** PASCAL.md had files down
as a stage, and the obvious reading is that anything less is unfinished. But ISO
leaves the binding between a name in a program heading and a file on disk to the
implementation, and `file of T`'s representation on disk likewise — so a program
that opens either has no answer `fpc` and this compiler could be *expected* to
share. **A divergence nobody can check is a divergence nobody should write**,
and the honest move was to name both in the document with that reason rather
than build something the oracle would have to be told to ignore.

Standard input is fully specified, and a program that filters text is what a
Pascal program mostly is.

**Three bugs, and two were the same one.** The machine's only conditional jump
is `JUMP_IF_FALSE`, so *leave when this is true* has to be written as *leave when
its negation is false*. Spelled the way the sentence reads, `readln` stops at the
first character that is **not** a line marker — which is the one it is standing
on — and then steps again, so everything after it is shifted by one character and
the output looks nearly right. I have now made that mistake twice: `repeat` in
stage 2 was the same shape.

The third was better. `c:indexOf(" \t\n\r")` where `" \t\n\r":indexOf(c)` was
meant — asking a one-character string whether it contains all four spaces, which
is always no, so nothing was whitespace and the first token read was the whole
file. **A send takes its receiver from the stack and reads like an argument list
on the page.** That is the one place this language's *everything is a message*
stops helping, and it will not be the last time I write the arguments in the
order the sentence has them.

### Pointers, and a representation one case too narrow

Stage 7. Cells, `new`, `nil`, `dispose`, and a binary tree that inserts, walks
in order and measures its own depth.

**The whole stage is one finding, and it is about stage 3.** A `var` parameter
has been a one-element cell since procedures arrived — `sola.sol`'s answer, and
I took it because it was settled prior art. It is enough for BASIC, where the
only thing that can be passed by reference is a whole variable.

`Insert(t^.left, k)` is the first line of the first program anybody writes with
pointers, and the storage it names is *element two of the record `t` points at*.
**No cell can alias that.** Stage 5 had met the same wall from the array side
and written it down as *stage 8: the box goes over, and an element has none* —
which reads like a missing feature and was a representation one case too narrow.

A reference is a container and an index now. It names a whole variable's cell,
an array's element and a record's field with one shape, and a whole variable
carries its pair from declaration, so passing one costs *nothing* at the call
that it did not cost before.

**What I nearly shipped instead was a hack.** The call site needs `array` pushed
before the container and index, and I first emitted it, then removed three bytes
again when the argument turned out to be a whole variable. It worked, and it
depended on `emitGlobal` being exactly three bytes long. One line of lookahead —
*is there a selector after this name* — replaced it. **Un-emitting is a sign the
decision was taken in the wrong order**, not a technique.

### Stage 8, and a Pascal compiler that agrees with a real one

The last stage: the eight required functions, `page`, and a field width worked
out while running. **Twenty-one programs produce the same bytes as `fpc -Miso`,
and three more must not.**

2,841 lines, 19% comment, eight stages between 07:49 and 12:19, and a 291-line
document written before any of it.

---

### Postmortem

1. **Installing the oracle first changed what the work was.** SolaBasic got its
   oracle at stage 7 and took five defects from it against none from twelve
   transcripts. This one had `fpc` before it had a lexer, and the first thing it
   said was that `pascal.bnf` — written days earlier for a different program —
   accepts what real Pascal accepts. Every default field width, `round`'s
   direction, `div`'s truncation and `mod`'s sign came out of *asking* rather
   than out of reading the standard and hoping. **A second implementation is
   worth more at the start than at the end**, because at the start it decides
   things and at the end it only checks them.

2. **The plan was wrong twice, and both times about a representation.** A set
   was to be bit-words; `1 shiftLeft 63` overflows, so it is booleans. A `var`
   parameter was a one-element cell; `Insert(t^.left, k)` names element two of a
   record, so it is a container and an index. Neither was a missing feature —
   both were a shape that fitted every case I had thought of and one I had not.
   **A representation reads as settled long before it is.**

3. **The same mistake three times, in three stages.** `JUMP_IF_FALSE` is the
   machine's only conditional jump, so *leave when this is true* has to be
   written *leave when its negation is false*. `repeat` in stage 2 ran once;
   `readln` in stage 6 landed one character late; and each time the program was
   correct enough to look right. I know the rule and I have written it down, and
   I will write the loop the way the sentence reads again.

4. **`internally inconsistent` means at least four things.** A jump offset from
   the wrong place, a slot past the end of a frame, a method's line runs not
   covering its code, and — nearly — a stack that did not balance. Bisecting a
   working program down to the breaking construct found the first two. It found
   nothing for the third, because *every* procedure failed; `disasm.sol` found
   that one, by reading the file the verifier had refused. **The tool for a
   refused file is the one that does not verify it.**

5. **The type checker was not optional and I nearly treated it as a chore.**
   Solum refuses `#1:add(1.0)`, so a compiler for a language with an implicit
   conversion has to know every expression's type before it writes a byte. That
   is the whole difference from `sola.sol`, whose header says *everything a
   SolaBasic program computes is a Double*. One numeric type needs no analysis;
   two need all of it — and once the analysis exists, enumerations, subranges,
   sets and pointers cost almost nothing, because they are all *kinds* over the
   same handful of runtime shapes.

6. **Deciding what not to build took longer than building.** External files and
   `file of T` are out, and the reason is not effort: ISO leaves their binding
   and representation to the implementation, so a program that uses one has no
   answer `fpc` and this could be *expected* to share. **A divergence nobody can
   check is a divergence nobody should write.** That sentence is the most useful
   thing the oracle taught, and it is about scope rather than about defects.

7. **The machine needed nothing added.** Not one instruction, not one message,
   not one roadmap entry. Eight stages of a statically typed language with
   nested procedures, sets, pointers and files onto a dynamically typed
   message-sending machine, and the only thing that had to change was
   `expect.sol` learning to feed standard input. `OP_OUTER` turned out to be a
   static link; a capturing block turned out to be Pascal's own scoping rule.
   **Both of those were written down as predictions before the stage that
   settled them**, which is the only reason either counts for anything.

8. **And the number that says it: 254.** A recursive Pascal function reaches
   exactly the depth a plain Solum recursion does — so a Pascal call costs one
   frame and nothing else, with no wrapper and no bookkeeping frame between it
   and an `OP_SEND`. I had *predicted* "something like 250" and never measured
   it, and it sat in `ideas.md` for a day looking like a fact. It was close by
   luck. **The exact number says something the guess could not**: that the
   compiler adds nothing at all, which is the strongest claim on any of these
   pages and took one program and four minutes to earn.

## 2026-08-27 — a document that was already there

Asked for a reference document for SolaBasic. There is one: 1,016 lines,
statement by statement, with what the compiler says when it refuses.

**So the first thing was to find out whether it was still true**, which is a
cheaper question than it sounds — the compiler's keyword table is in its source,
and comparing it against the document is a loop. It named every user-facing
keyword but one. `DEFLNG` is the fourth `DEF` statement and the reference listed
three; the definition had all four, so this was drift between two documents
rather than a hole in either idea.

**The audit is worth more than the finding.** One missing keyword out of eighty
is a good result for a hand-written reference, and knowing *that* is what made
the next decision easy: the gap was not in the reference at all. Solum has both
a full reference and a one-page cheatsheet; SolaBasic had the reference and the
definition and no one-pager. That is what got written.

**The first draft of the cheatsheet failed its own coverage check**, on `LET`
and on `AS LONG` — the same check that had just been run against the reference,
turned around and pointed at the new page. Writing a document by reading another
document loses whatever the second one was thin about, and the only defence is
to check both against the thing they describe.

**Every claim on the page was run before it was written down.** One listing
exercises all of them, and it caught nothing — which is the outcome to hope for
and not the reason to skip it. The claims about `PRINT`'s spacing are the ones
that would have been wrong: a number is a sign character, then the digits, then
a trailing space, and no amount of reading the reference tells you whether you
have transcribed that correctly.

### And then the examples were made to check themselves

That listing was mine and ran once. The seventy ```basic blocks in the three
documents had never run at all, which is the same gap `expect.sol` closed for
`examples/` and had left open in the one corner it could not reach: a fenced
block naming a language is skipped, and SolaBasic is a language this repository
*defines*.

**The convention had to be different, and BASIC's output is why.** Everywhere
else here a claim is a comment on the line that printed it. `PRINT 42` writes a
space where a minus would go, then the digits, then a trailing space — leading
spaces are what a print zone is made of and a comment cannot show them, and a
trailing space in a comment is invisible and would not survive the first editor
to touch the file. So the expectation is a ```text block under the ```basic one,
and the fence keeps the leading spaces. Trailing whitespace is ignored on both
sides, and that one thing is left to `programs/sola/*.out`.

**Forty-one of the seventy are not checked and are counted instead**, which is
this program's rule about itself: sixteen print nothing, thirteen name a label
or a `SUB` from the prose around them, three loop for ever on purpose, and one
reads from the terminal so its ```text is a session rather than an output.

**The outputs were generated and then read, one at a time, against the prose
above each one.** That is the step that mattered, and it found five examples
that only ever demonstrated half of themselves: an `IF ... ELSE` that always
took the `ELSE` because its variable was never assigned, an `ELSEIF` chain and a
`SELECT CASE` that both fell through to the last arm, and a loop printing twenty
lines where three say the same thing. Not one of them was *wrong*. **An example
nobody runs cannot report that it is demonstrating the wrong branch** — it is
correct, and it is teaching the reader the least interesting thing it could.

Generating an expectation from a run is the failure this repository has already
written up once, as *a transcript recording what a program does rather than what
it should*. The defence is that reading the prose is the check, and the five
above are what reading it produced.

### And the grammar page, which had no examples to check at all

Asked for the same treatment for GRAMMAR.md. It has no runnable Solum in it —
four blocks of grammar productions and one of block-forms written with an
ellipsis — so there was nothing to run, and the interesting thing was what the
page *claims* instead.

**It opens by saying it is the same grammar as `solum.bnf`.** That is the
largest claim on it: everything else there is one production, and that sentence
is all of them at once. Nothing held it. Comparing them found eleven productions
already identical, and the rest differing for two quite different reasons —
vocabulary, which is drift, and prose, which is the point of the page.

**So the two were given one vocabulary, and the document's won.** `name`, `hex`
and `bin` in the grammar became `identifier`, `hexdigit` and `bindigit`; the page
gave up its typographic ellipsis for the `..` the notation actually uses, and its
notation table gained a row for that and for the backslash, so it now describes
the notation completely rather than nearly.

**And it found `primary` with its alternatives in a different order in each
file.** No token can match two of them, so nothing was wrong and nothing would
have gone wrong — which is precisely why it had survived. The grammar took the
document's order.

Twenty-three productions are compared now and two are named as prose. The two
are `string` and `comment`, which say *any character but a quote* where the
notation says `! '"'`, and naming them in the report is the difference between
excusing something and hiding it.

**A global search-and-replace corrupted a block on the way through.** Changing
`…` to `..` across the page also changed it inside the block-forms, turning
`{ a | … }` into `{ a | .. }` — which is not the language and is not what the
line was ever about. An assertion in the next edit caught it. **A replacement
narrow enough to describe in one sentence is not necessarily narrow enough to
run**, and the only reason this did not ship is that the following step happened
to touch the same text.

## 2026-08-26 (evening) — a checker that is told what to check

Two commits, 16:47 to 17:44. 1,591 lines of program, 32% of it comment; 185
lines of Pascal grammar; six `.pas` files that exist to be checked, two of them
correct; 171 lines of test.

Asked for a program that reads a BNF file and a source file and reports lex and
syntax errors: `check_syntax.sob pascal.bnf myprog.pas`. It became the
fourteenth program, and it is the first here whose *input* is a language
definition rather than a language — hand it
[pascal.bnf](../programs/check_syntax/pascal.bnf) and it checks Pascal, hand it
something else and it checks that.

**The first hour went on the frame limit, before any of it was written.** A
tree-walking matcher recurses once per node of the grammar against a machine
with 254 frames, so the question was whether a recursive design was viable at
all or whether it had to be an explicit stack machine from the start. Two probe
programs answered it: a node method that iterates its children with `do` reaches
126 levels, and the same method iterating with an inlined `whileTrue` and an
index reaches 252. The block call was the whole difference.
[lib/control.sol](../lib/control.sol) had already written the rule down — three
frames a level for `ifElseIf`, use the staircase inside a recursion and the
dispatch outside it — and this program follows it exactly: `ifElseIf` appears
once, in the grammar's own lexer, and nowhere in either matcher.

That is an hour that produced no code and settled the design.

### The afternoon went to `letter`

The first Pascal file read as a stream of `letter` and `digit` — 130 syntax
errors in a file with nothing wrong with it. `letter` and `identifier` both
match `T`, longest-match ties go to the rule declared first, and `letter` is
declared first. It is obvious written down and it was not obvious at all with a
correct grammar, a correct file and a screen of nonsense between them.

The fix is a `%fragment` directive saying which lexical rules are helpers rather
than tokens. The part worth having is the *warning* that goes with it — a token
kind that no syntactic rule can match and that is not skipped can do nothing but
produce a syntax error, so it is reported. Three of the program's five grammar
checks exist for the same reason: **every one of them catches a grammar that is
wrong in a way that blames the wrong file.** Left recursion arriving as `call
depth exceeded` against the Pascal file is the sharpest of them.

### What was measured, and what the measurement corrected

Inlining a rule's alternation into the reference that names it should save one
frame of three per level of grammar — a third of the depth. It saved a sixth: 16
levels of nested `begin … if` became 19, and 25 nested parentheses became 28.
Most of Wirth's Pascal rules have a *sequence* for a body rather than an
alternation, so most never had the middle frame to save.

A measurement of the matcher predicts a third. Only a measurement through a real
grammar gives a sixth, and that is the whole argument for `programs/` existing
separately from `examples/`, arriving again from a new direction.

### Two documents were wrong before anything was added to them

`expect.sol` refused the count markers the moment `programs/` had fourteen files
in it, and named three places still saying thirteen — two in `design.md`, one in
`COMPLETED.md` — that had nothing to do with this program and would not have been
found by reading. `programs.md` itself said *these twelve* on a page describing
thirteen, which is the drift that entry was built for and which no marker was
attached to. Both are fixed.

The other document to change was [ideas.md](ideas.md), which had a parser toolkit
down as the most interesting thing on its list because the answer would be
informative either way: it would give
[3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) its first
customer, or show that a non-combinator design is fine. **It is the second, and
3.1 never came up** — not because it was worked around, but because the design
that avoids it is the design that is right. The combinator shape is the one 3.1
refuses and it was never reached for.

### What it asked the language for

**Nothing.** No roadmap entry, no `COMPLETED.md` entry, no message added. That
is unusual enough here to be worth stating, since
[programs.md](programs.md) says in as many words that nearly every roadmap entry
after the first dozen came from one of these programs wanting something.

It is not evidence that the language is finished. It is evidence that this
program was the *fourteenth* rather than the fourth: every awkwardness it would
have reported had already been reported and answered by something earlier.
[scan.sol](../lib/scan.sol) was there for the grammar's own lexer.
[control.sol](../lib/control.sol) had already measured `ifElseIf` at three frames
a level and written down where not to use it. `onError` catching `call depth
exceeded` — the property this program's whole depth story rests on — was
established by [evaluator.sol](../programs/evaluator.sol), the second program
here, and has been true ever since. **A program that asks for nothing is standing on what the ones
before it asked for**, and the only honest way to read the silence is that the
bill was already paid.

### The defects were in the halves nobody was looking at

Six worth recording, and only one of them is in the matcher.

| | |
| --- | --- |
| `letter` beats `identifier` | longest-match ties go to declaration order, and helpers are declared first |
| `symbol = "." \| ".."` | ordered choice inside a rule is not longest match across rules |
| `function Area;` | after `forward`, the real definition repeats neither parameters nor result type |
| a binary file | 1,673 error lines, and one of them 4,000 bytes wide |
| the token dump | larger than the test's buffer, so the program took a `SIGPIPE` |
| `system()` is not `printf` | `%%` in a C string reached the shell as `%%`, and three grammars were nonsense |

**The last two are the test and not the program**, which is the ratio
[the editor's postmortem](#2026-08-26-the-editor-finished--a-postmortem) put at three in four and which held
again here.

**The binary file is the one worth having.** Nothing was meant to hand this a
Mach-O executable, and doing it found two real defects: a report is not a report
at 1,673 lines, and the line shown under an error is not always a line. The fix
caps the lexical errors at twenty, escapes every unprintable byte, and windows
the shown line — **budgeted in rendered columns rather than in bytes**, because a
byte that escapes to `\x1b` is four columns wide and a 96-byte window is a
384-column line with the caret nowhere near what it points at.

### Then the checker was pointed at this language

The obvious next grammar, and the one with an oracle: fifty-seven `.sol` files
that have to keep checking clean. **Fifty-six do**, and the fifty-seventh is the
frame limit rather than a disagreement.

**The grammar came out of `solas/src/lexer.c` and `solas/src/compiler.c`**, not
out of the documentation, and the reason is that there was nothing to copy. The
only grammar written down anywhere is the sketch at the top of
`solas/include/solas/parser.h`, and it says of itself that it goes as far as
`design.md` pins it down — no blocks, no arrays, no symbols, no temporaries, no
slot assignment. Half the language. So the whole of it is written down now,
twice: [solum.bnf](../programs/check_syntax/solum.bnf) for the checker and
[GRAMMAR.md](GRAMMAR.md) for a person.

**Twenty-eight edge cases were settled by asking `solas` rather than by reading
it.** Whether a group may be empty, whether `a := b := c` nests, whether `1e` is
one token or two, whether a trailing comma is allowed in an array literal,
whether a string may span lines. Reading the C gives an answer and running it
gives *the* answer — and one of them disagreed. `optional_declarations` carries
a long comment about the top-level restriction on temporaries being gone, which
reads as though `| t |` may now open a script; it may not, because no rule calls
that function there. What the comment is about is a *group* written at the top
level, which does work. **A comment describing a repair is not a description of
what is reachable.**

**The finding is that a real file reaches the depth limit.**
`experiment/lexer.sol` holds a 24-level nested `ifElse` staircase, the deepest
expression here, and against this grammar the checker manages 13 nested blocks.
Every earlier measurement on [3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels)
needed a generator to reach the limit; this one was already sitting in the
repository. And the shape that does it is the shape
[control.sol](../lib/control.sol) *tells you to write* — a staircase instead of
`ifElseIf`, precisely to save frames. Both are right: it saves frames in the
program doing the dispatching and costs them in anything that walks the result
as a tree.

### Two defects found by pointing things at large input

**The token dump was quadratic**, and the comment above the offending block
predicted it without noticing. `lineColumnIn` counts newlines from the start of
the file, and the note beside it argues for that on the grounds that a run wants
four line numbers, one per message. `tokens` mode wants one per *token*, and on
the largest file here that is **seventeen and a half minutes to list the tokens
of a file it checks in under four seconds** — 1,052 seconds against 3.85.
Tokens are in order, so the dump carries the line and makes one pass, and the
1,052 becomes 3.6.

**The number is the reason this is in the journal rather than only in the
changelog.** The first measurement of it used a 1,766-line file and said "over
two minutes", which is bad enough to fix and not bad enough to be interesting. A
quadratic is only itself at size, and the file that shows it is the biggest one
to hand.

**And `expect.sol` would have crashed rather than reported.** Its list of ordinal
words has to be extended by hand when a program is added; when it is not, the
failure is `index #14 is out of bounds for an array of size 13` — a crash, in
the checker, on the run that exists to report the mistake. It surfaced here only
because a stale `.sob` was lying around with the old list still in it, which is
the sort of luck that is not a plan. Guarded, and the list runs to twentieth.

### And then the trade that had been recorded got taken

The depth limit had been written down three times as a known cost and once as a
thing to build if it ever mattered. It mattered the moment the checker was
pointed at this language: `experiment/lexer.sol` nests `ifElse` 24 deep and the
tree walker could not read it.

**So the matcher is LPeg's instruction set now** — `Call`, `Ret`, `Choice`,
`Commit` — compiled once and run by a loop, with the stack in arrays. 2,000
levels of nesting check where 13 did. The whole of what the old matcher did
wrong was to keep its stack somewhere it did not own.

**The verification was the old matcher.** Both were run over every file here and
every error case with the output compared byte for byte — 63 runs, and the only
two that differed were the two that had been too deep. That is the comparison
worth having: not that the new one works, but that it does not quietly do
something else. One of the two is `check_syntax.sol` itself, whose new dispatch
staircase the old matcher could not read.

**It cost 38% of the running time**, and the two attempts to get that back are
the part worth recording. Reordering the dispatch staircase by frequency —
`matchRange` was eighth, and a range is what a lexical grammar is mostly made of
— bought 2.4%. Spelling out the hottest comparison rather than calling it, and
folding its literal at compile time, bought 1.3%. I had written "worth a tenth"
and "worth a fifth" into the comments *before* measuring, and both were wrong by
a factor of four or more. They came out again.

---

### Postmortem

1. **The interesting outcome was the one where nothing happened.**
   [ideas.md](ideas.md) had this program down as the most interesting thing on
   its list because it would either give
   [3.1](ROADMAP.md#31-capturing-blocks-cannot-escape-their-frame) its first
   customer or show the restriction was livable — and it is the second, having
   never come near it. A design that never *reaches* a limitation says more
   about that limitation than one that works around it, and it is much harder to
   notice, because there is no moment where anything goes wrong. **Predictions
   are worth writing down mostly for the times they are answered by silence.**

2. **Every grammar check exists because a wrong grammar blamed the wrong file.**
   That is the whole architecture of the checking half, and it was not planned —
   each of the five arrived as a bug report against Pascal for a mistake in the
   BNF. Left recursion surfaces as `call depth exceeded` against the `.pas`.
   A missing `%fragment` surfaces as 130 syntax errors in a correct file. **When
   a tool takes two inputs, the hard part is not finding the fault, it is
   attributing it** — and every message that names the wrong input is worse than
   no message, because the reader goes and stares at the innocent file.

3. **The measurement corrected the reasoning rather than the number.** Inlining
   a rule's alternation should save one frame of three per level of grammar; it
   saved one of six. The mechanism was exactly as predicted and the *population*
   was not — most of Wirth's Pascal rules have a sequence for a body, so most
   never had the middle frame to save. A measurement of the mechanism tells you
   what the mechanism costs; only a measurement through real input tells you
   what it costs here. **That is the same argument `programs/` exists on**, and
   it arrived this time from inside an optimisation rather than from a missing
   feature.

4. **The afternoon went to a tie-break I already knew the rule for.** Longest
   match, ties to the rule declared first — stated in the program's own comments
   before the bug, and it still took an afternoon, because the rule was right
   and the *classification* was missing: nothing had said which lexical rules
   were tokens and which were spare parts. **A silent default in a lookup is the
   thing to make explicit**, and `%fragment` plus a warning is a small price for
   never seeing that screen again.

5. **The program was pointed at input it was never meant to read, and that paid
   twice.** A binary file is not a use case; it is what happens when somebody
   types the wrong filename, which is a thing that happens far more often than
   any use case. Both defects it found — the unbounded report and the unbounded
   line — are about *volume* rather than about parsing, and neither could have
   turned up on a `.pas` file of any size. **Test the wrong input, not just the
   large one.**

6. **`control.sol`'s comment was worth more than `control.sol`.** The design
   decision that set the depth budget — staircase inside the recursion,
   `ifElseIf` outside it — was made in the first hour by reading a measurement
   somebody had already taken and written down beside the thing it was about. It
   cost nothing to reuse and would have cost an afternoon to rediscover.
   **A measurement is worth writing where the next person will be standing when
   they need it**, which is not the changelog.

7. **A corpus you did not write is worth more than a test you did.** The Solum
   grammar was checked against fifty-seven files, not one of which was written
   with it in mind, and that is the only reason to believe it. The four
   deliberate mistakes I *did* write test what I already thought; the
   thirty-eight examples test what I had not thought of. **When a program takes
   a description of something as input, the something already in the repository
   is the test.**

8. **A design note about how often something is wanted is a claim about every
   future caller.** `lineColumnIn` counts from the start of the file, and the
   comment beside it says why that is free: four line numbers a run, one per
   message. That was true, and stayed true, and then `tokens` mode wanted one
   per token and made it quadratic — with the justification sitting three lines
   above the call. **The note did not stop me because I had written it**, which
   is the failure mode of a comment addressed to somebody else.

9. **I wrote two performance numbers into comments before measuring them, and
   both were wrong by a factor of four.** "Worth a tenth of the running time"
   and "worth a fifth" — the real figures were 2.4% and 1.3%. Nothing forced me
   to guess; the measurement took a minute and I did it afterwards, to confirm
   what I had already written down. **A number in a comment reads exactly like a
   measured one**, which is what makes writing an unmeasured one a different
   kind of mistake from being wrong out loud. The whole repository is built on
   comments being true, and these two would have shipped.

10. **The limit did not move, it moved somewhere better.** Compiling a grammar
   still recurses, so a deep enough *grammar* still runs out of frames. That is
   worth as much as the removal: it is now a property of the file the author
   wrote, reported the same way every run and before any input is read, instead
   of a property of the input, discovered on the one file that happened to be
   deep. **When a limit cannot be removed, moving it to the input somebody
   controls is most of the value.**

11. **Two documents were wrong before a line was added to them.** `expect.sol`
   refused the count markers the instant `programs/` held fourteen files and
   named three places still saying thirteen, in `design.md` and `COMPLETED.md`,
   that had nothing to do with this work. That is the entry doing exactly its
   job — and the one drift it could not catch was `programs.md` saying *these
   twelve* on a page describing thirteen, because no marker was attached to it.
   **A checker finds what it was told to look at**, and the gap in its coverage
   is invisible from inside it.

## 2026-08-26 (SolaBasic) — a language in an afternoon, and the thing that held it honest

Forty commits between 10:28 and 16:31, twenty of them the changelog follow-ups
this repository pairs with every landing. A compiler for a BASIC dialect:
4,778 lines, 23% comment, and 2,230 lines of documentation beside it.

**The day did not start with a plan, it started with a question** — whether a
QBasic could be compiled to bytecode at all — and the first hour produced no
code. It went on finding out that there *is* a standardised structured BASIC,
that it is ECMA-116 and free to read, that it still requires line numbers, that
it is 176 keywords across five optional modules, and that nobody appears to have
built a conforming implementation. So the standard route was closed, and the
boundary had to be borrowed from somewhere else: CB80, Digital Research's 1982
compiler, which produced an intermediate file run by a separate runtime and is
this design fifty years early.

That hour is the reason the dialect has its own name and a written boundary
rather than being "QBasic, roughly".

### The spec was written first, and it still went wrong

[SOLABASIC.md](SOLABASIC.md) was written before any compiler, frozen when one
started, and every change to it since is dated and reasoned in its own change
log. That discipline is the whole of what a standard would have given, and it
worked for eight stages of features.

It did not work for `:`. *Lexical structure* has said "`:` joins statements on
one line" since the day it was written, and the compiler refused it — through
every stage, while the divergence list was being checked against a real
QuickBASIC by machine. **A definition promising what the implementation does not
do is the same failure as a transcript recording what a program does rather than
what it should**, and this one lasted longer than any of them. It was found by
going looking for it rather than by anything failing.

### The stages were done in the wrong order on purpose

Stage 3 — `GOTO` and labels — went first, because it is the claim everything
else stands on: `GOTO` cannot be written in Solum, which has no control-flow
syntax, so the whole case for compiling rather than translating rests on
`OP_JUMP` existing. That was measured before a compiler existed, by
hand-assembling a chunk with a backward jump to an arbitrary offset and a
forward one over dead code, and by breaking it two ways to check the verifier
would notice. It did, at load, as a message.

Stage 2 then turned out to be stage 3 with a stack on top — every structured
statement is the same hole punched in the code, filled when the closing line
turns up instead of when a label does. **Doing them the other way round would
have made that a thing to notice afterwards.**

### The oracle changed what the work was

Until 14:22 everything was held to transcripts this compiler had recorded of
itself. That is precisely the failure [basic.sol](../programs/basic.sol)'s header
describes at length — eighty-three claims that caught none of the seven defects
the NBS suite found — and the first run against a real QuickBASIC 4.5 under
DOSBox proved it on the spot: `PRINT (1 < 2)` printed `truD`, and **one of the
eleven green transcripts had recorded `truD` as the correct answer.**

Two things about getting there are worth keeping. Homebrew installs DOSBox as a
cask, so nothing lands on the `PATH` and it looks uninstalled. And `BC.EXE`
wants CR LF and says nothing when it does not get it: a file with Unix line
endings compiles, links, produces a `.EXE`, and that `.EXE` prints nothing at
all — which looks exactly like output that cannot be redirected, and cost an
hour of looking at the wrong thing.

### What found what

| | |
| --- | --- |
| the QuickBASIC comparison | **5** defects |
| writing the runtime and real programs *in SolaBasic* | **7** |
| twelve recorded transcripts | **0** |

The second row is the surprise. `PRINT`'s rules, `INPUT` and the file statements
are written in SolaBasic and compiled into any program that uses them, and
building them that way found three defects in what stages 4 and 5 had already
shipped — `DIM SHARED` on a plain variable doing nothing, a procedure
zero-initialising the module's shared variables, a `FUNCTION` of no arguments
read as a variable. **Writing a real program in the language kept finding what
testing the compiler did not.**

Three programs at the end were written for that reason alone: a sales report,
Conway's Life, and a word count. They found two things, two things, and nothing
— and the nothing is the useful one, because the word count was aimed at the
string functions, where all the hand-emitted clamping lives.

### The question that was best answered "no"

Late on, integer division came up: it floors, where BASIC truncates, and would
`divRounded` fix it? It would not — rounding disagrees with truncation in *both*
directions, so it would have fixed nothing and broken the positive case that
already worked. What that question did produce was better than a new message: the
workaround in the compiler was going through a float divide, which is exact for
neither, and `9007199254740993 \ 1` came out one short. **A workaround that looks
like a performance trade and is quietly a correctness one** — replaced with an
identity that stays in integers, and the message that would make it one send is
deferred in [ideas.md](ideas.md) with one customer named.

### What to carry

**A trigger written down beats a plan.** `ON ERROR` was the entry I twice
thought was about to be needed, and twice a real program did not need it — it
writes the file it reads. Both times I would have built it on my own say-so and
been wrong about why. The entries that *did* get built — `INPUT` into an array
element, multi-dimensional array parameters — were built because a listing
wanted them that morning.

**And the thing that holds a language honest is somebody else's implementation.**
Twenty programs match QuickBASIC byte for byte and five differ exactly where the
definition says they should, so the divergence list is no longer prose: a
program in `differ/` that starts agreeing means the list has gone wrong. That is
what an afternoon of building a harness bought, and it is worth more than any
feature that went in after it.

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

It is [6.36](COMPLETED.md#636-readline-and-readkey-did-not-share-an-input-buffer--done)
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
`at` ends* — has been in [lib/pattern.sol](../lib/re.sol) since the hour it
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

Into [lib/pattern.sol](../lib/re.sol), on the search path, and the argument
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
