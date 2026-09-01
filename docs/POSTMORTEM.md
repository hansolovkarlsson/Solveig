# Postmortem

Every defect this project has found in itself, what caused it, and — the part
worth the paper — **what found it**. The tally at the end is the only real
argument for how the work is done.

[journal.md](journal.md) is the narrative; [CHANGELOG.md](CHANGELOG.md) is what
shipped. This is the failures.

## Scope

Fourteen, from two days, in four cohorts that failed for four different reasons:

- **In the compiler** — three, two of which were latent from 0.1.0 and 0.2.0.
- **In the documents** — four: three an edit that reported success and changed
  nothing, and one where no edit was attempted at all.
- **In the programs** — four, found by the first real use of a thing.
- **In the reasoning** — three, where something true was written down as
  something else and had to be retracted.

---

## In the compiler

### 1. `instantiate` did not carry the `form` index

**What.** 0.5.0 gave a macro use an index saying which declaration it matched,
because a word may name more than one form. `instantiate` builds template nodes
by hand and did not copy the new field, so a form used *inside another form's
template* lost it and expansion reported `internal: 'unless' was read as a form
and is not one`.

**Cause.** Two constructors for one node kind. `proto_node_copy` was updated;
`instantiate` was not, and nothing makes them agree.

**Found by** the 0.2.0 test *a form using a form*, on the first run after the
change. The only defect here found by a test written earlier for another
purpose.

### 2. `synchronize` could spin forever — latent since 0.1.0

**What.** After an error the statement loop calls `synchronize`, which halts *at*
a closing bracket without consuming it. That is right when something above is
waiting for it and wrong at the top level, where nothing is: the `)` left over
by any error inside an argument list was read, failed, synchronised to, and read
again. `f(#1 % #2)` with `%` undeclared was enough.

**Cause.** A recovery routine written for one caller and used by two. The
property wanted belongs to the loop — *a pass that reports an error must consume
something* — and was expressed as a rule about brackets.

**Found by a test that was itself wrong.** A new 0.6.0 test omitted the `@infix`
its body needed, took the undeclared-operator path, and hung `make test`. A
correct test would not have found it.

### 3. The pattern diagnostic did not fire when no part was read

**What.** 0.7.0 added *a pattern is made of names and \<holes\>* for
`@syntax mov <d> , <s>`. It only fired once at least one part had been read, so
`@syntax vec { <x> }` still got *needs `=>`*, pointing at the brace and saying
nothing.

**Cause.** The condition tested `parts != NULL` — a proxy for *was this a
pattern* — rather than whether the call shape had been taken.

**Found by** a question about which punctuation a dialect can claim, which meant
running the case rather than reasoning about it.

---

## In the documents

### 4. Three roadmap edits that did nothing

**What.** Between 0.2.0 and 0.5.0, three replacements in `ROADMAP.md` matched
nothing. The file went on calling the expander *next* for four versions after it
shipped, and went on asking the collision question two versions after 0.4.0
answered it. Commit messages said otherwise.

**Cause.** The original was written with em dashes and the replacement with two
hyphens. **A replacement that matches nothing is not an error; it is a no-op
that reports success.** Once the first had failed, every later one was matching
against text that had never existed.

**Found by** the user asking *what's next?*, which meant reading the file rather
than remembering it.

### 5. A `.gitignore` edit that did nothing

**What.** The entry for `programs/ember`'s generated `.s` and `.out` never
landed, so both were staged with the commit.

**Cause.** The same class as 4 — anchored on Solveig's `.gitignore` wording
rather than Proto's.

**Found by** reading `git status --short` before committing.

### 6. A blind global replace mangled a comment

**What.** Renaming `&&` to `/\` in `emberc.pro` was done with an unanchored
substitution and caught a shell command inside a header comment:
`> fizzbuzz.s && cc fizzbuzz.s` became `/\ cc`. The comment is how somebody runs
the thing by hand.

**Cause.** A rename applied to a file rather than to a language.

**Found by** grepping for the old spelling after the commit had already gone out.

### 13. A number that was true when it was written — 2026-09-01

**What.** `ROADMAP.md` said `@language` had been inert *eight versions in*. The
changelog had nine, 0.1.0 through 0.9.0. The sentence was written at 0.8.0, and
0.9.0 landed beside it without disturbing it.

**Cause.** A new class in this cohort, and the reason the cohort is now four.
Defects 4, 5 and 6 are edits that ran and did the wrong thing. **Here no edit
was attempted at all** — the number was a fact about a second document, correct
on the day it was written, with nothing in either file to notice when the other
one moved. `edcf4a0` the day before was the same shape, a heading left over a
body that had been rewritten under it, and it was fixed without being recorded
here.

**Found by** counting the versions in `CHANGELOG.md` while writing a changelog
entry — that is, by having to state a number that the roadmap had already
stated, and comparing them.

**What is real.** A cross-document fact has no owner. `9` lives in
`common.h`, the version list lives in `CHANGELOG.md`, and the sentence that
counts them lives in `ROADMAP.md`; nothing links the three, so the count is
correct only until the next release. The cheap defence is the one that caught
it: any claim about *the state of another document* is re-derived when it is
read, not trusted.

---

## In the programs

### 7. `skip <cls: literal>` was typed from the author's examples

**What.** `programs/grammar`'s toolkit typed five holes `literal` because every
use imagined was a literal. The first real grammar wrote `skip blank`, naming a
string it had bound, and was refused by its own toolkit.

**Cause.** A kind is a promise extracted from the *caller*. Typing it from the
uses you have imagined makes a dialect narrower than the thing it is for.

**Found by** the first grammar written with it, four minutes after it existed.

### 8. `peekAt(#2)` was off by one

**What.** `programs/ember`'s lexer produced `<` and `=` as two tokens instead of
`<=`.

**Cause.** `scan:peekAt(#0)` is `peek`, and the code assumed one-based.

**Found by** printing the token stream and reading it, before the parser existed.

### 9. Six precedence bugs in one file

**What.** `t:kind == 'op:and({ … })` sends `and` to the *symbol*, because sends
bind tighter than operators. Six of them in `emberc.pro`.

**Cause.** The standing cost of putting operators on a language whose core is
sends. Nobody's defect.

**Found by** running it — every one of them at run time, because they are type
errors and not syntax errors. **This is the finding that became 0.7.0**: the
right answer was to declare `and` and `or` as operators, which needed operator
templates, which did not exist.

---

## In the reasoning

### 10. The `else` branch that silently did nothing

**What.** `lib/clike.pro` first declared `if <c> <t: block> else <e>` untyped so
that `else if (…)` would chain, with the template wrapping: `c:ifElse(t, { e })`.
When the branch is *already* a block that gives `{ { … } }`, and the outer block
answers the inner one rather than running it. The else branch did nothing.
`examples/clike` printed `#54` where `#40` was right. It compiled, it ran, and
nothing failed.

**Cause.** A template cannot branch on what its hole turned out to be, and a
hole's kind is one choice with no alternation — no way to say *a block, or
another use of me*. Wanting both, the first draft took neither.

**Found by** working the arithmetic out by hand rather than trusting that a
program which ran had run correctly.

### 11. A finding published twice that was not a finding

**What.** `programs/ember` reported that a form's trailing hole swallows a
postfix send; `programs/grammar` reported that it swallows an infix operator.
Both were written up as limitations of Proto, with a sketch of a fix, in two
READMEs and two commit messages.

**Neither was a limitation.** A call ends at its closing parenthesis, so
anything after it applies to what it answered. `emit`, `at`, `eat`, `skip`,
`take` and `apply` are applications and belonged in the call shape.

**Cause.** `programs/ember`'s own README states the rule — *a pattern for
something that reads as a step, a call for something that reads as an
application*. `programs/grammar` was written afterwards, by the author of that
sentence, and got it wrong in five forms. **The rule was in a program's note and
not in `GRAMMAR.md`**, where somebody choosing a shape would look.

**Found by** re-checking a claim before recommending a feature built on it.

**What is real**, and is now the entry: choosing the shape wrongly is *silent*.
Both readings are legal, so nothing at the declaration can warn.

### 12. A precedence declared on the wrong rung

**What.** `programs/digest/sha2.pro` declared `*` and `%` at 60, the rung `+` is
on. `at + i * #4` therefore parsed as `(at + i) * #4`, and the message schedule
read the wrong bytes of every block.

**It compiled, and it ran.** What stopped it was `index #65 is out of bounds for
an array of size 64`, four calls deep in generated Solveig, pointing at a line
of `.sol` that no one wrote.

**Cause.** A module declares its own ladder, so there is no ladder to be wrong
against — `@infix * 60` is as legal as `@infix * 70` and means something
different. `lib/arith.pro` puts `*` at 70 and this file did not copy it, being
standalone on purpose.

**Found by** running it. No test could have: the file is its own authority on
what its operators bind like.

**What is real**, and it is 11's shape one level over: choosing a *precedence*
wrongly is as silent as choosing a *form's shape* wrongly, and for the same
reason — both readings are legal, so nothing at the declaration can warn. The
difference is that a wrong shape usually fails at the use, and a wrong
precedence computes a different number and keeps going.

### 14. A name doing two jobs, read as doing one — 2026-09-01

**What.** Told the project was renamed Phoenix -> Proto to mark a prototype
restart, the first pass renamed the repository and left the language alone:
`phx_`, `Phx`, `PHX_` and `.phx` were held back on the reasoning that *Proto*
described the project and *Phoenix* was still the name of the thing being built.
That distinction was written down as a standing note. It survived about an hour,
until Hans said the language was Proto too.

**Cause.** "Phoenix" named two things — a repository and a language — and the
instruction was about one of them without saying which. Renaming a repository
and renaming a language are both ordinary readings of *rename the project*. The
error was not picking the wrong one; it was **recording the pick as settled** in
a durable note instead of asking a question that would have cost one line.

**Found by** Hans stating the intent plainly in the next message.

**What is real**, and it is why this is written down when it cost nothing: an
inference and a fact are indistinguishable once they are in the same document.
The note read like something Hans had said. Defect 11 is the same failure with
the roles swapped — there, a claim was published where somebody could go back
and disagree with it, and that is what saved it. **An inference is recorded with
the question it answered, or it is asked instead.**

---

## The tally

| What found it | |
| --- | --- |
| A test written earlier, for something else | **1** |
| A test that was itself wrong | **1** |
| Writing a real program in the language | **4** |
| Checking output by hand rather than trusting a clean run | **2** |
| Reading a document because somebody asked a question about it | **2** |
| Re-checking a claim before acting on it | **1** |
| `git status` before a commit | **1** |
| Having to restate a number another document already stated | **1** |
| The user saying plainly what had been inferred | **1** |

**Two of fourteen were found by tests, and one of those two was a broken test.**
Four came from the three programs written in the language, and three more came
from reading something rather than running it.

The unit tests are worth having — 108 of them, and they caught 1 immediately —
but they check what was thought of. **What found the rest was a customer, or a
second look.** That is the argument for `programs/`, for recording predictions
before writing a program, and for the rule that a finding gets retracted in
place rather than edited away: 11 exists because 7 and 9 were written down where
somebody could go back and disagree with them.

**The two from 2026-09-01 were both found by a person rather than by a check**,
which is the first time that is true of a pair, and the day did not produce a
line of compiler code. Neither is a defect in Proto. Both are defects in how a
claim gets recorded: one document asserting a fact about another, and an
inference written down in the voice of an instruction.
