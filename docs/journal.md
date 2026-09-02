# Journal

*What a day of work on Proto actually consisted of, newest first.*

[CHANGELOG.md](CHANGELOG.md) records what landed, per feature, with the commit
that carried it. [COMPLETED.md](COMPLETED.md) records the case for each piece of
work as it was argued before the work was done. [POSTMORTEM.md](POSTMORTEM.md)
records the failures. Neither of the first two holds the shape of a *day* — what
was picked up and why, what turned out to be wrong, and the decisions that
produced no code because they were decisions.

---

## 2026-09-02 — a directive removed, a survey that was partial, a fifth program, and the bar

**Every number in this entry is at the foot**, and this is the third attempt at
saying why.

The opening first read *five commits, one version*. Corrected to nineteen.
Corrected again with the commit count moved to the foot and the sentence *this
opening carries only what stopped changing* — and then the version range
changed, in the paragraph claiming to have fixed the problem.

So the rule is harder than it looked: **nothing about a running day has stopped
changing, and the only stable thing in a journal entry is its date.** Not the
commits, not the versions, not the range, not the heading. Everything countable
goes at the bottom where it can be written last, and the top carries only what
happened. [POSTMORTEM.md](POSTMORTEM.md) 13 three times over, in the entry that
kept quoting it.

The day opened with *what's next todo?* and built none of the four things that
question was answered with. It closed having closed seven of nine differences
nobody knew were there at breakfast.

### It began as a roadmap review and went somewhere else

The answer to *what's next* ranked the open items and recommended constant
folding: the only entry with a measurement behind it, and the only one where the
case was already made. That item is still untouched tonight.

What happened instead is that Hans asked how the thing works, four times, and
each answer turned into work. **The roadmap describes what is known to be
missing. It has nothing to say about what is unclear**, and unclear is where the
day's whole output came from.

### Two of the questions were misreadings, and both were productive

> Proto runs the rules on the code and replaces the parts that matches?

No — matching happens *during* parsing, inside the reader, against a table the
header built before a statement was read. There is no pass over finished code.

> if the body was a different programming language, then the clash might not
> happen with the `|`, say Pascal for instance?

No — `|` is the *reader's* constraint, not the body's and not the emitter's. A
Pascal compiler written in Proto still cannot declare `|`, and a Proto that
emitted Pascal still could not either, because the ambiguity is in `{ a | b }`
and that is Proto's own syntax.

**Neither misreading is one a document written from the inside would think to
correct.** GRAMMAR.md says what the syntax is; the README argues why. Nothing
said *matching is not a scan*, because nobody on the inside would imagine it
was. Both are now in [what-is-proto.md](what-is-proto.md), kept as the questions
they were rather than rewritten into statements, and the pipeline is drawn four
times in [pipeline.html](pipeline.html) — `3156d26`.

### `@language` went, and a question is what unstuck it

The roadmap had said for nine versions that it should select the reader, or the
emitter, or stop existing. It had not moved because **two of those three depend
on a build this project has already declined** — [targets.md](targets.md)
refuses a second emitter, and a second reader is larger still. The entry was
not waiting on a decision. It was waiting on something that was never coming.

What settled it was Hans asking what `@language Pascal` would actually declare.
The answer is *nothing anyone would expect*, and following that out gives the
argument the roadmap never had:

> `@language solveig.` at the top of `examples/forms.pro` says the body below is
> Solveig. That file declares `+`, `<`, `>`, `unless`, `while` and `swap`. Its
> body is not Solveig and Solveig cannot read it.

The line was false in every file that declared anything, which is every file
worth writing. Removed in 0.10.0 — `eb07046`, [COMPLETED.md](COMPLETED.md) 14.

### The near-miss is the part worth keeping

The first recommendation was **not** to remove it. It was to make it *assert*:
one reader, one emitter, so any name but `solveig` is an error at line 1.
Fifteen lines, touching no `.pro`, and the exact code a selector would need
later. The argument for it was reversibility — asserting is cheap and deleting
is not.

That argument prices a change. It does not ask whether the thing is right, and
the thing was not right. **A directive whose plainest reading is false is not
fixed by checking its spelling.** The reversal came from taking Hans's question
seriously rather than from any new fact.

### One spelling per operation

`\/` had been doing two jobs — logical *or* in `lib/arith.pro`, bitwise *or* in
`examples/utf8.pro` and `programs/digest/sha2.pro` — and `~` two as well,
logical *not* in arith and bitwise *not* in sha2, which is C's meaning. A reader
had to know which file they were in before they could read a line.

Hans proposed `&&`, `||`, `!` and asked whether `\` was free for the bitwise or.
It is, and it is the right answer: one character, where C writes `|`, which is
the one character a dialect can never have. **The single irregularity left is
forced by the design rather than chosen**, which is the best kind to be left
holding — it points at the constraint instead of hiding it. `b57aa31`.

`!` for bitwise or was proposed and refused on the way, for the same reason
`@language` had gone an hour earlier: `!` reads as *not* everywhere, and
`lib/clike.pro` already declares it prefix-not.

[POSTMORTEM.md](POSTMORTEM.md) 6 is a blind replace of these same operators that
mangled a shell command in a comment — *a rename applied to a file rather than
to a language*. This one ran only on the code portion of each line, never inside
a string or after a `;`, printed all 27 changed lines to be read, and then
proved itself the way that entry wishes it could have: **every generated `.sol`
in the tree is byte-identical across the change.** Same messages; only the
spelling moved.

### A segfault from 0.1.0, found by checking a sentence

`programs/digest/README.md` says composing `sha2.pro` with `lib/control.pro`
collides on four operators. Before repeating that in another document, it was
run. `proto` segfaulted.

`proto_dialect_add_infix` answers the entry a redeclaration displaced, so the
reader can say *previously declared here* — and it looked that entry up
**before** growing the array, so a `realloc` that relocates leaves the caller
reading freed memory. `add_prefix` and `add_macro` had it too. Latent since
0.1.0. `f8b219a`, [POSTMORTEM.md](POSTMORTEM.md) 15.

It hid because it needs three things in one call: a collision, a capacity
crossing, and a realloc that moves rather than extends. Every example and
program in this tree composes dialects that agree. `programs/digest` is the
first thing here with a dialect that redefines `+` — and its README says
composing it collides, having reasoned about it rather than run it.

**And the claim was wrong anyway.** Proto reported nine redeclarations, not
four: the four whose meaning differs, plus two declared identically in both and
three on a different rung. It is seven now, the spelling change having removed
`~` and `\/` from the overlap.

### `make sanitize`, because the tool was already there

The regression check that came with the segfault only guards under a sanitizer:
whether a stale pointer lands on freed memory is the allocator's business, and
in `test_use`'s process it does not. It fails under
`make test SANITIZE="-fsanitize=address"` and is clean with the fix.

Which is the finding that should sting. **That invocation had been in the
Makefile since the first commit and nothing had ever been run under it.** Not a
missing test — a tool sitting in a comment, never picked up. It is a target now
and a standing agreement in [conventions.md](conventions.md), and the suite is
clean under `-fsanitize=address,undefined`.

### The fourth program, which argued against both entries it was written for

`programs/ledger` was picked to answer two roadmap items at once: the
domain-boundary entry wanted a second program, and the folding entry wanted a
second customer. Predictions went in first, in their own commit, so the ordering
is in the history rather than in a claim.

**Both answers went the other way.**

The domain boundary is a pattern now — `digest` trapped on `+`, `ledger` on `/`
— but the second instance narrowed what the entry may promise, twice. **Which
operator turns traitor is not predictable from outside the domain**: this
program predicted `*` and was bitten by `/`. And the boundary is not only at the
domain's edge — `ratio interest to subtotal` answers `0.07` where the exact
value is `0.074995…`, because a ledger has amounts wanting two places and rates
wanting five, and a dialect has one scale to give.

Folding got its second customer and the customer voted against: **4,258
instructions against 4,250 hand-folded. Eight, or 0.19%**, where `digest` was
5.4%. Identical shape, different bill, and the reason is not the dialect — *a
dialect's constants cost per use, and this dialect's uses are outside the loop.*
One measurement had made folding look larger than it is.

### The survey was partial, which is the thing to remember about today

`ledger` found that `#-1225` is an error in Proto and a valid integer in
Solveig. That went into POSTMORTEM.md 16 as a missing integer literal, and it
would have stayed that size if Hans had not asked whether the survey behind it
had been complete.

It had not. Comparing every form in Solveig's grammar against Proto, one file
each, gives **nine divergences out of eighteen**. Four versions came out of that
in an afternoon: the sign on `#-45`, `$FF08`, float exponents and the escape set
in 0.11.0; `#[a = b]` in 0.12.0; `%1011` in 0.13.0.

Three of those are worth keeping past the version numbers.

**`"\q"` was the only one pointing the other way.** Every other difference was
Proto refusing something Solveig takes — a smaller language and an honest error.
That one was Proto *accepting* something Solveig refuses, and emitting it, so a
`.pro` compiled clean and produced a `.sol` `solas` rejected. **Proto emitting
invalid Solveig** is the single failure the map and the run-every-example
discipline exist to prevent, and neither caught it, because no example has a bad
escape.

**`#[a = b]` was mis-sorted as free and was not.** The lexer was never the
obstacle. Solveig settles what `=` means in a key by precedence *level*, which
Proto cannot copy because a dialect may declare `=` anywhere — `lib/clike.pro`
puts it at 10. It needed a rule saying **a context shadows a declaration**, the
first in this language, confined to the top level of a key so that
`#[(b = c) = d]` still uses the declared one.

**`%1011` cost something, and it is the first spelling here that did.** `||` in
0.9.0 grew the fixed vocabulary and took only `{ || … }` out of the *core*, and
COMPLETED.md 12 held that up as the shape any future request should take. This
is the second instance with a different bill: **growing the fixed vocabulary
took something from what a dialect may declare.** A module declaring `%` can no
longer write `a %1` without a space. Small, unused here, and loud — and the next
one might be none of those.

**And `-3` cannot be had at all.** Solveig's scanner gives the sign to the
number outside a `@expr` region and treats it as the operator inside one. Proto
has no regions and cannot take `-3` as a literal either, because then `a -3`
stops being a subtraction in every dialect that declares `-`. So *everything but
`operator` is Solveig's own spelling* was never achievable, and 0.1.0 chose
against it without recording that it had.

### And a last hour of putting things back the way they should have been

Asked whether `lib/arith.pro` should be completed with the bitwise operators:
**no**, and the tree makes the case rather than taste. Bitwise has one usable
customer rather than two — `sha2.pro` cannot share a file, its `<<` being masked
and the file standalone because it redefines `+` — and the two existing
customers chose different rungs for `&` and `>>` against their own neighbours.
`<=`, `>=` and `!=` have no customer at all: every one of arith's five users
declares no operator of its own.

The neighbourhood turned up something else, though. **Seven templates were
standing in for messages Solveig already had** — `notEquals`, `lessOrEqual`,
`greaterOrEqual`, and a `not` that `arith.pro` had been spelling plainly all
along while `clike.pro` wrapped it. `digest` runs 920 instructions fewer, and
what is left in `clike.pro` is three templates, each one a message cannot be.

### Somebody built the thing that could not be built

A second session, running against this same working copy, made a branch and
declared `|` as an infix operator. It worked: two hunks in `reader.c`, **no
change to the lexer**, the whole suite green, every block form intact, and an
example whose commented values all came out right.

**Three documents said that was impossible**, in nearly the same words, and I
had said it twice more during the day. `README.md`, `lex.c` and
[COMPLETED.md](COMPLETED.md) 12: *`{ a | b }` would have two readings, and
naming the ambiguity does not decide it.*

**Two questions had been run together and given one answer.** *May `|` join the
operator characters?* — no, and that stands, because characters in that set run
together and a `|` there would make `|=` a spelling. *May `|` be declared?* — a
different question, a bar being a token of its own that a parser may look up
without it entering the set at all.

And the resolution was already in the language. `{ a | b }` is a parameter and a
body **by rule**, and `{ (a) | b }` escapes — which is `#[(b = c) = d]` in a
different bracket, **landed four hours earlier the same day.** The mechanism was
in that morning's commit message and the argument against `|` was not re-read in
its light.

**The cause was misattributed in both directions**, which is the part worth
keeping. Entry 12 blamed the ambiguity and stopped. The session that built it
reported removing *Solveig's* constraint and had removed nothing of Solveig's —
`lex.c` untouched, and Solveig has the identical `{ a | b }` and settles it the
identical way. What stands in the way of `|` is **Proto's own block syntax**.

The work was reverted, not kept: it arrived uncommitted in a shared checkout and
what it costs had not been looked at. [ROADMAP.md](ROADMAP.md) is that looking,
and carries the reason not to hurry — 0.13.0 had just settled the repository on
`\` for bitwise or *because* `|` was unavailable, and a spelling should be
changed once. [POSTMORTEM.md](POSTMORTEM.md) 18.

**It also came within half an hour of being swept into a commit of mine.** The
edit landed at 11:59 and my last `git add -A` was 11:30. Two sessions in one
working copy is a hazard that cost nothing today by timing alone.

### The question this project exists to answer, finally written down

[targets.md](targets.md) has said since 0.1.0 that the only thing this project
exists to find out is **whether a grammar declared per module is a good idea**,
and then left it to be answered elsewhere. Four programs had answered parts of
it, each in its own README, each quoting the one before — and *a dialect pays
per line it removes* appeared in four program folders and **nowhere in `docs/`
or the README.**

[does-it-pay.md](does-it-pay.md) is the four weighed together, with the numbers
re-measured rather than carried across. Tabulating them showed something no
single program could have:

| | operators | forms |
| --- | ---: | ---: |
| ember, grammar — about another *language* | **0** | 16, 8 |
| digest, ledger — about a *value domain* | 17, 10 | 3, 6 |

**A domain of steps wants forms. A domain of values wants operators.** Nobody
chose that; four programs arrived at it independently, and `ember` had already
found the reason without knowing it was one — a pattern *reads as a step in a
procedure*.

Re-counting also corrected `digest`'s own README in both directions. It claimed
Solveig writes twenty-three `bitAnd`s by hand and Proto writes none. Solveig's
file has 24 in code, of which **18 are `bitAnd(mask)`**; Proto's has **0 masks
and one** `bitAnd`, a byte extract. **Eighteen hand-written masks became five
declarations** — the finding survives and the figures did not.

### And a fifth program, for the one thing four had not tested

`does-it-pay.md` ended by asking for a domain that was neither arithmetic nor
instructions. [`programs/prose`](../programs/prose) is that: a document
language, with the document itself written in the dialect. It is also the
answerable half of a question asked the wrong way round earlier — *can Proto
take prose?* Not as its body; but a dialect can be shaped so the document **is**
the program.

**It found no third category.** No operators, seven forms — `ember`'s shape
exactly. A document is a domain of steps and the taxonomy absorbed it.

**One prediction was wrong and it was the best finding.** Nesting was predicted
to be the wall. It is not: a form takes a **block**, a block holds statements,
and statements are content forms, so `indent { … }` nests to any depth and
Solveig's braces carry the structure. The real ceiling is a level lower —
**a form can contain content; a form cannot contain half a line.** Emphasis
inside a sentence has nowhere to go, because a paragraph is one string.

**And it split *carrying a rule* in two.** `indent { … }` cannot be unbalanced,
but the dialect borrowed that from Solveig rather than inventing it. `sha2.pro`
invented its own. **Only the invented kind is evidence that a declared grammar
does something a fixed one cannot**, and it is still the single clear instance
in five programs.

It also reversed an answer given the same morning. `lib/arith.pro` has no `<=`,
and the renderer wanted one. Asked at eleven whether arith should be completed,
the answer was no — *no customer at all*, every one of arith's five users
declaring no operator of its own. This is the sixth user and the customer. **One
is still not enough**, which is the rule that kept the bitwise operators out on
the same day; the roadmap records it so the second customer settles it.

### The bar, landed, and a spelling changed twice

The retraction earlier in the day said `|` could be declared and did not do it.
Asked for an example, the honest answer was that the current build refuses one —
so a scratch copy was patched to demonstrate it, and the demonstration made the
case for finishing it properly.

**0.14.0 is the bar, and `\` retired in the same commit.** The rule is the one
`#[k = v]` already had, and the reason the two went together is the whole
argument for waiting a version:

> 0.13.0 had settled the repository on *one spelling per operation*, with `\`
> for a bitwise or **because `|` could not be had**. Landing the bar alone would
> have changed one spelling twice in two versions.

**A spelling should be changed once**, and this one was changed twice — the
second time deliberately, in one commit, with the table ending as C's exactly
and nothing substituted. The two gaps the demonstration had — `@prefix |`
accepted and inert, and a stray bar with the wrong diagnostic — were closed
before it landed rather than after.

The lexer was never touched. `|` is still `PROTO_TOK_BAR` and still not an
operator character, so a tool can tokenise any `.pro` knowing nothing about its
dialect — the property [COMPLETED.md](COMPLETED.md) 12 was written to defend and
does defend correctly, even though the conclusion drawn beside it was wrong.

### A table cell that misled its first reader

The one-spelling table had an em-dash in the logical-xor cell, meaning *there is
not one*. Its first reader read it as a proposed operator and asked whether
logical xor was a minus sign.

**That is the table's fault and not the reader's**, and the answer turned out to
be more interesting than the correction. There is no symbol to have — C has no
`^^`, Java and Python reuse `^`, Pascal uses a keyword — and Solveig's boolean
understands only `not`, `and`, `or`, `ifTrue`, `ifFalse` and `ifElse`. What
there *is* is `!=`: for booleans, xor and not-equals are the same operation,
which is why nobody invents a symbol for it.

So **`lib/clike.pro` has had a logical xor since it declared `!=`**, and nobody
noticed — including me, that afternoon, while replacing that very template with
the direct message. And if it were ever spelled as its own operator it would be
`^^`, for the reason Hans gave when the answer reached him: the single character
is the bitwise one and the doubled one is the logical one, as `&` is to `&&`.
Recorded, and **not declared**, because nothing has wanted one.

### What the tests did today

Nothing, and mostly that was the job. The suite held at 58, 6, 34 and 10 while
the spelling change went through, which is precisely what a spelling change
should do to it — **a control, not a detector**. It ended at 58, 6, 60 and 11:
the segfault added one, and the new spellings twenty-six.

### The numbers, written last

**Thirty-one commits, counting the two that write and correct this line — a
number cannot count itself and has to be told to. Five versions, 0.10.0 to
0.14.0. A fifth program. And not one finding from a test.**

Two misreadings, by a person asking. One dead directive's real argument, by a
person asking what it would mean. One nine-version-old segfault, by declining to
repeat a sentence without checking it. Eight of the nine syntactic differences,
by a person asking whether the first survey had been complete. One
impossibility, by somebody building the thing that could not be built. And one
misleading table, **by its first reader asking what a dash meant.**

Every one by a person or a program, and the tally has two rows it did not have
this morning: *being asked whether a survey had been complete*, at two, and
*somebody building the thing that could not be built*, at one.

**Three documents arrived that had no home before**:
[REFERENCE.md](REFERENCE.md), the page you look a spelling up in;
[does-it-pay.md](does-it-pay.md), the answer to the only question the project
exists to ask; and `programs/prose/README.md`, a document about a document.

Those are the day's real output. The five versions were the easy part — four of
them closed differences nobody knew were there at breakfast, and the fifth
landed a thing three documents had called impossible.

**And the day closed with a sweep**, which found four more stale things: a
version heading four releases behind, a *Known gaps* row for something that
landed in 0.12.0, a folding claim carrying one measurement when there are two,
and this page's own count in two other documents. **None of them was the work.
All of them were a document describing yesterday's version of itself**, which is
the failure this journal spent the day committing and correcting, and the only
reliable defence found for it is to read everything once at the end.

## 2026-09-01 — the project changed its name, and nothing else

A rename is a strange thing to give a journal entry. This one gets one because
the reason was outside the repository, and because the checking was the whole of
the work.

### It was renamed twice, and the first one was wrong in an interesting way

Hans had already moved folder and repository to **Phoenix Proto** before the
session opened, to mark the tree as a prototype restart. The session's first job
was small: the local `origin` still pointed at the old URL, redirected by GitHub
and working, and would have broken the day somebody else claimed the name.

Then the decision changed — drop the qualifier, and the name is **Proto**, plain.
The prototype framing is the honest description of the thing rather than a
modifier on a name that was leaving anyway.

**The discarded step is what made the second one clear.** The first pass had
deliberately left `phx_`, `Phx` and `.phx` alone, on the reasoning that "Proto"
marked a restart of the *project* and not a rename of what was being built — the
language was still Phoenix. That distinction was written down as a standing note
and had to be deleted the same day. It was a real reading of a real instruction
and it was wrong, which is the argument for asking rather than inferring when a
name is doing two jobs.

### The name had been promised to something else, in writing, three days earlier

`hansolovkarlsson/Solveig`, `docs/ideas.md:4451`: *Trigger: wanting a library
that Solum consumes and that is not written in Solum. Nothing has wanted one.
The name, should it happen, is Phoenix.*

Dated 2026-08-28 — three days before this project had an expander. The idea it
names is genuinely a different language: it earns its place by publishing a
**library** Solum consumes, and that entry refuses in advance *a nicer skin on
this one*. Proto emits a program's source.

So the collision was real and had been sitting in two repositories at once, with
the unbuilt idea holding the name by reservation and the shipped compiler holding
it by use. The rename ends that. **The reservation in `ideas.md` was left exactly
as it stands**, which is the point of having gone and read it before rewriting
anything — a search-and-replace across two repositories would have taken it.

### What the rename was checked against

`conventions.md` says **every text replacement asserts its match**, and three of
the recorded defects are that rule being skipped. So the suite was run green
first, to have a number rather than an impression to compare against. Afterwards
it reported the same 58, 6, 34 and 10 checks over the same ten examples and
programs, with no new warnings.

Two checks were worth more than the suite, and neither is a test:

**The diff is 1,435 insertions against 1,435 deletions.** A pure respelling
cannot be any other shape. A replacement that swallowed a line would show up
here and nowhere in the tests, because the tests only run what still compiles.

**The ambiguous matches were looked for before the `sed` ran, not after.** Every
`.phx` in the tree turned out to be a file extension; there was no bare `PHX`;
and the only odd identifier among the hundred and thirty-six was `has_phx` in
`default_output_path`, which compares `length - 4` against `".phx"`. `.pro` is
also four characters, so that line survived **by luck rather than by design** —
worth writing down, because `.proto` would have broken it silently and only the
examples would have caught it.

### One thing it cost

`git log --follow` no longer walks `lex.h` past today on its own. That header is
dense enough in identifiers that respelling them all dropped it under git's 50%
similarity threshold, so it records as a delete and a create where the other
thirty-five moves record as renames. The history is not gone —
`git log --follow --find-renames=30%` walks it back through 0.4.0 to the first
commit — but the default is now wrong for one file in thirty-six.

### A stale number, found and then fixed

**ROADMAP.md said `@language` was inert "eight versions in".** The changelog has
nine, 0.1.0 through 0.9.0: the sentence was written at 0.8.0 and 0.9.0 landed
under it without disturbing it. It is the same failure as the heading in
`edcf4a0` — a number true when written and not re-read when the thing beside it
moved — and it is the third time this document set has been caught holding one.

It went in here as *found and not fixed*, on the reasoning that the day's job
was a rename and this is a correction to an argument rather than to a spelling.
Hans asked for it the same hour, so it reads **nine** now. The identical phrase
in the 2026-08-31 entry below is deliberately untouched: eight was true on the
day that entry describes.

### The afternoon: putting what only the session knew into the documents

`conventions.md` opens by saying its contents are written down *so that neither
depends on anybody remembering them*. The rename made that concrete in a way
that had already gone wrong once without being noticed.

Standing notes had been accumulating in a per-directory store keyed by the
project's path on disk. Renaming the folder moves the key. **The previous
rename, the day before, had already orphaned three of them** — that Solveig's
README does not link here and why, that Solveig findings get written up in a
shape liftable into that project, and that `scratch/` is not to be read — and
nothing announced it. They were live rules that had quietly stopped applying to
anything, and they were only found because today's rename was about to do it
again.

All three were already in `conventions.md`, which is why nothing was actually
lost, and which is the argument for that file existing. The one that was **not**
written down anywhere is now the fourth standing agreement: *the name Phoenix
belongs to a different project*, with the consequence that costs something if
forgotten — **Solveig's `ideas.md` entry is that project's reservation and is not
to be rewritten.** A search-and-replace across two repositories would have taken
it, and would have looked like tidying.

Two defects went into [POSTMORTEM.md](POSTMORTEM.md), 13 and 14, and neither is
a defect in Proto. **13** is the stale version count: a number correct on the day
it was written, in a document that had no way to notice when the document it
described moved — a fourth kind in the *In the documents* cohort, where the
other three are edits that ran and did nothing and this one is no edit at all.
**14** is the Phoenix-Proto misreading, recorded although it cost nothing,
because what it cost *could* have been large: an inference written into a
standing note is indistinguishable from something Hans said. Both were found by
a person rather than by a check, which is a first for a pair.

[COMPLETED.md](COMPLETED.md) 13 keeps the case — the three extension schemes
that were on the table, and why full-word identifiers with a short `.pro`
extension beat being consistent.

**Adding 13 and 14 immediately produced a fourth copy of 13.** Three live
documents said *three of twelve recorded defects* are the unasserted-replacement
mistake, and the total went wrong the moment the count did. Bumping them to
fourteen would have bought a year, maybe. They say *three of the recorded
defects* now: the fraction is the point, the denominator was never load-bearing,
and `POSTMORTEM.md` is the one file allowed to know it. The identical sentence
in the 2026-08-31 entry below keeps its *twelve*, being a record of a day.

The first attempt at that removal deleted the word and left the preposition —
*three of recorded defects* — in two files. Caught by reading the result rather
than trusting the three assertions that had all correctly reported one match
each. **A replacement asserting its match proves it fired, not that it was
right**, which is defect 6 in miniature and the reason that rule has a second
half.

### What is still open

The folder is `~/Projects/Proto` now, moved at the end of the day rather than
during it: a directory cannot be moved out from under the session working inside
it.

Nothing on the roadmap moved. A rename is not progress on any of it, and the two
decisions that are Hans's — what `@language` should select or whether it should
stop existing, and whether Solveig's README links here now that the hold is met —
are open exactly as they were yesterday.

## 2026-08-31, later — a question about `|`, and the third program

The day did not end where the entry below says it did.

### It started by reading the documents rather than remembering them

The session opened with *check the documents and list tasks*, which is the same
move that caught the four-versions-stale roadmap in `5bf83af` — and it caught a
smaller version of the identical thing. `ROADMAP.md` still had a section headed
**Next — optional and repeated parts** over a body explaining that the item
*moves below whatever the next program finds*. The body had been updated when
`programs/grammar` declined the item; the heading was four words of the old plan,
left standing.

A heading outliving its section is the cheap form of the failure that document
set exists to prevent, and somebody skimming headings reads it as current. It is
`edcf4a0`, and the section is called *Waiting on a customer* now, borrowing the
vocabulary already at the foot of COMPLETED.md.

### A confusion that was worth having

The question was why `|` could not be an operator, and the proposal was a
`@token` directive: name a token, bind a spelling to it, and let `@infix` name
the token instead of the characters. It was refused, and working out *why* took
longer than the feature that came out of it.

The proposal does not reach the blocker. What stops `|` is not that `@infix`
cannot spell it — `\/` needs no help and declares fine — it is that
`{ a | b }` has two complete legal readings once `|` means something, and the
declaration is not on that line to disambiguate them. **A collision between core
syntax and declared syntax happens at the use, and no spelling of the
declaration reaches it.** The split the proposal wanted already existed:
`PROTO_TOK_OPERATOR` is spelling only and `@infix` is meaning, so the real question
was never *how does a file name a token* but *which spellings are in the
vocabulary*.

So the vocabulary grew. **`||` is two bars and not a bar** — the lexer takes it
before the bar, hands it to every dialect and lets none of them declare it, and
`{ a || b }` was already an error so nothing legal was taken. The one casualty
was `{ || … }`, an empty temporary list that emitted nothing and appeared
nowhere. That is 0.9.0, and `lib/clike.pro` stopped apologising for `\/`.

**What made it cheap was checking rather than reasoning.** Both risky cases were
compiled before the change was written. One of them turned out to be a real cost
and the other turned out to be already-illegal, and neither was obvious from
reading the parser.

### The third program, and the first one that measured anything

`programs/digest` — SHA-256 — was chosen because Solveig's own `sha256sum` wrote
the gap down in its findings: *`@expr` has no bit operators, so the one file here
that is nothing but shifts, xors and masks is the one file that cannot use the
notation at all.* Proto's ROADMAP has claimed the answer to that since 0.1.0
with nothing to point at. Same algorithm, same substrate, one file with a fixed
infix region and one that declares its own.

Five predictions, recorded first. Three right, one right and duller than hoped,
**one wrong** — and the wrong one is the whole value of the program.

The claim was *a form is a method that costs nothing at run time*, since a
template expands rather than calls. It is not true. Measured by binary search on
`--steps`, the way Solveig's own program measured its version: the template
saves **2.03 instructions per rotation** by not calling, and spends **2.00**
recomputing a `#32:sub(#17)` that nothing folds. **It gives back 98% of what it
saves.** Two predictions that were written as separate lines turned out to be one
finding with the numbers meeting in the middle.

That is now a roadmap item with a measurement attached, and deliberately not a
patch: folding a send at expand time means deciding which sends are safe to run,
and `integer:sub` is a slot a Solveig program may assign. It is the guard
question one size smaller, and it gets the same treatment.

**What the program found that nobody predicted** was three things, and the best
of them is that **a wrong precedence is silent**. `*` was declared on `+`'s rung,
`at + i * #4` became `(at + i) * #4`, it compiled, it ran, and it failed as an
array index four calls deep in generated code. A module declares its own ladder,
so there is no ladder to be wrong against. It is defect 11's shape one level
over: both readings legal, nothing at the declaration able to warn.

The other two: **a dialect ends at its domain and cannot say where** — `+`
masking to 32 bits is right for SHA-256 and a trap for the loop counter beside
it — and **0.4.0's collision rules got their first real customer**, four
collisions against `lib/control.pro`, reported exactly as designed, and the
answer was to not compose.

### What was written down rather than built

Three things went into the documents and not into the compiler. **Constant
folding in the expander** is now a roadmap entry with a measurement instead of a
patch, because folding a send means deciding which sends are safe to run.
**A dialect ends at its domain and cannot say where** is recorded with no
proposal at all, because one program is an anecdote. And the `@token` refusal is
in ROADMAP under *a dialect that changes the lexer*, where the next version of
that request will be read — with a note that the want was real and `||` is the
shape an answer should take.

`docs/solveig-notes.md` gained a third entry: **the machine counts instructions
and will not say how many.** `--steps=N` stops a run, so the count exists; a run
that finishes reports nothing, and the exact figure costs 28 executions of a
binary search. Two of the three suggested fixes are one `fprintf`.

### The number, again

Twelve defects now, and still **two found by tests**. Four have come from
writing programs in the language. The third program cost an afternoon and moved
one roadmap item from a claim to a measurement, which is what the first two did
and is the reason there will be a fourth.

## 2026-08-31 — the whole of it: nineteen commits, eight versions, and two programs that disagreed with the roadmap

The day began with a question rather than a task: *a meta-language, with
compiler directives designing the syntax of the language above it.* It ended
with 0.8.0, two real programs, three shipped dialects, and a retraction.

### What shipped

Proto 0.1.0 through 0.8.0. `lib/arith.pro`, `lib/control.pro`,
`lib/clike.pro`. `programs/ember`, a compiler from a small language to ARM64
assembly. `programs/grammar`, a grammar toolkit. Five design notes:
[targets.md](targets.md), [rules-and-logic.md](rules-and-logic.md),
[solveig-notes.md](solveig-notes.md), and this document set. 5,187 lines of C11,
103 unit checks, five examples and four programs run by `make test`.

### The first hour was spent not writing code

The opening question was answered with prior art — Racket, Terra, Forth, Rebol,
Seed7 — and one decision was pressed on before anything else: **where syntax is
allowed to change.** Three positions were laid out; the middle one, per-module
declared grammar, was chosen, and it is the reason every later decision was
cheap. A file's syntax is settled by that file's own header, so a tool can parse
it by reading it top to bottom and never has to run anything.

The second decision was where Proto lives. Solveig existed already, and
solveig-sdl's Makefile had written the rule down about itself — *this is an
extension, so it is not part of Solveig* — so Proto went beside it rather than
inside it. That was argued from something stronger than tidiness: a front end
with privileged access to the compiler it targets proves only that Solveig's
author can write a front end for Solveig.

`solas/include/solas/compiler.h` decided the rest. `sol_compile(source, chunk)`
is single-pass with no tree, so Proto owns one, and that settles what Proto
is: a second compiler that happens to target Solveig.

### Three things went into 0.1.0 that nothing used

Spans on every node, `introduced_by`, and `scope`. Two of the three were read by
nothing at all. They went in because each is impossible to add later without
touching every constructor — and the return came fast: 0.2.0's expander was
written in one sitting rather than three, and 0.4.0's *a span carries its file*
was a field rather than a rewrite.

### The collision question, and the answer that was already written

From 0.2.0 onward everything queued behind one question: what happens when two
dialects declare the same operator. Racket answers it with modules and scoped
bindings and it was worth reading how — but Solveig's `REFERENCE.md` had already
answered it for two files claiming one global. *The later wins, and the compiler
warns rather than letting it pass.* And it warns on a **claim** and not on an
**update**, which is a distinction about who could have known.

Applied to syntax that gives four cases, and 0.4.0 shipped them. **A language
should not hold two philosophies about one question**, and the hour spent
reading Solveig's reference was the cheapest hour of the day.

### The roadmap had been lying for four versions

Asked *what's next?*, the file was read rather than remembered, and it still
called the expander *next* — four versions after it shipped — and still asked the
collision question two versions after it was answered. Three edits between 0.2.0
and 0.5.0 had matched nothing and reported success; em dashes against two
hyphens.

Fixed in `5bf83af`, which says so in its own subject line. The method changed
with it: every replacement asserts its match now, and it caught two more the
same day.

### Then the programs, which is where the day turned

Six versions in, nothing had been written in the language. `lib/text.sol` over
in Solveig states the rule — *one customer, satisfied in six lines, is not a
reason to grow a surface* — and its converse is what the project had been
ignoring.

`programs/ember` was written with five predictions recorded first. Three right,
one did not bite, **one wrong**: Solveig was predicted to bite first, most likely
3.1, and did not bite at all. Two things nobody predicted, and one of them —
six hand-written `(a == b):and({ … })` because `&&` could not be declared —
became 0.7.0 the same afternoon. That is the whole argument for `programs/` in
one example: the feature was found by a program, not by thinking about features.

`programs/grammar` was written second, and deliberately: it is the program most
likely to want repetition, which the roadmap had wanted for four versions with
nobody asking. It wants repetition, and **a repeated pattern part would not have
helped** — a grammar cannot be written as forms at all, so the repetition wanted
is one level down. The item was declined a second time, with a reason instead of
a shrug. 3.1 bit this time, exactly as predicted, and cost four lines because it
was predicted.

### And the day ended by taking something back

Both programs had reported that a form's trailing hole swallows what follows.
Asked *what's next?* again, the plan was to build the fix — and checking the
claim first showed there was nothing to fix. Both had declared an application as
a pattern. A call ends at its closing parenthesis; `ember`'s own README states
the rule, and `grammar` was written afterwards by the author of that sentence
and broke it in five forms.

The retraction is `d90ea08`. What is real is smaller and better: **choosing the
shape wrongly is silent**, both readings being legal. The rule moved from a
program's note into `GRAMMAR.md`, where somebody choosing a shape would look —
which is the most likely reason it was not followed.

### What was decided and not built

`@language` still records a name and acts on nothing, eight versions in. It is
the only inert directive and it should either select something — a reader, or an
emitter, as [targets.md](targets.md) argues — or stop existing. That is a
decision, not a build.

A guard on a rule was designed and not built: `solum/embed.h` is the door, and
the rule to fix before writing any of it is that **a guard validates, it does not
select** — otherwise parsing depends on evaluation and no tool can read a `.pro`
without running it. [rules-and-logic.md](rules-and-logic.md) carries the whole
argument.

### The number worth keeping

Eleven defects, and **two were found by tests** — one of those two by a test that
was itself wrong. Three came from writing programs, three from reading something
rather than running it, and one from re-checking a claim before acting on it.
The tally is in [POSTMORTEM.md](POSTMORTEM.md), and it is the reason the next
step is more likely to be a third program than a ninth feature.
