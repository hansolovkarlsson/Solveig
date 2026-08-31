# Postmortem

Every defect this project has found in itself, what caused it, and — the part
worth the paper — **what found it**. The tally at the end is the only real
argument for how the work is done.

[journal.md](journal.md) is the narrative; [CHANGELOG.md](CHANGELOG.md) is what
shipped. This is the failures.

## Scope

Eleven, from one day, in four cohorts that failed for four different reasons:

- **In the compiler** — three, two of which were latent from 0.1.0 and 0.2.0.
- **In the documents** — three, all of them an edit that reported success and
  changed nothing.
- **In the programs** — three, found by the first real use of a thing.
- **In the reasoning** — two, where something true was written down as something
  else and had to be retracted.

---

## In the compiler

### 1. `instantiate` did not carry the `form` index

**What.** 0.5.0 gave a macro use an index saying which declaration it matched,
because a word may name more than one form. `instantiate` builds template nodes
by hand and did not copy the new field, so a form used *inside another form's
template* lost it and expansion reported `internal: 'unless' was read as a form
and is not one`.

**Cause.** Two constructors for one node kind. `phx_node_copy` was updated;
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
rather than Phoenix's.

**Found by** reading `git status --short` before committing.

### 6. A blind global replace mangled a comment

**What.** Renaming `&&` to `/\` in `emberc.phx` was done with an unanchored
substitution and caught a shell command inside a header comment:
`> fizzbuzz.s && cc fizzbuzz.s` became `/\ cc`. The comment is how somebody runs
the thing by hand.

**Cause.** A rename applied to a file rather than to a language.

**Found by** grepping for the old spelling after the commit had already gone out.

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
bind tighter than operators. Six of them in `emberc.phx`.

**Cause.** The standing cost of putting operators on a language whose core is
sends. Nobody's defect.

**Found by** running it — every one of them at run time, because they are type
errors and not syntax errors. **This is the finding that became 0.7.0**: the
right answer was to declare `and` and `or` as operators, which needed operator
templates, which did not exist.

---

## In the reasoning

### 10. The `else` branch that silently did nothing

**What.** `lib/clike.phx` first declared `if <c> <t: block> else <e>` untyped so
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
Both were written up as limitations of Phoenix, with a sketch of a fix, in two
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

---

## The tally

| What found it | |
| --- | --- |
| A test written earlier, for something else | **1** |
| A test that was itself wrong | **1** |
| Writing a real program in the language | **3** |
| Checking output by hand rather than trusting a clean run | **2** |
| Reading a document because somebody asked a question about it | **2** |
| Re-checking a claim before acting on it | **1** |
| `git status` before a commit | **1** |

**Two of eleven were found by tests, and one of those two was a broken test.**
Three came from the two programs written in the language, and three more came
from reading something rather than running it.

The unit tests are worth having — 103 of them, and they caught 1 immediately —
but they check what was thought of. **What found the rest was a customer, or a
second look.** That is the argument for `programs/`, for recording predictions
before writing a program, and for the rule that a finding gets retracted in
place rather than edited away: 11 exists because 7 and 9 were written down where
somebody could go back and disagree with them.
