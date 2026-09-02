# Does a grammar declared per module pay?

*[targets.md](targets.md) names the question this project exists to answer —
**whether a grammar declared per module is a good idea** — and then leaves it to
be answered somewhere else. Five programs have answered parts of it, each in its
own README, each quoting the one before. This is the five of them weighed
together.*

*Four are tabulated below and the fifth has a section of its own, because it was
written after this page existed and to answer the question this page ended on.*

Nothing here is new evidence. What is new is that it is in one place, and that
the numbers were re-measured rather than carried across.

---

## The short answer

**It pays per line it removes, and it pays most when it removes a rule rather
than a spelling.**

`programs/grammar` found the first half and it has held for two programs since:
notation earns in a domain that is flat and repetitive and earns little in one
that is small and structured. `programs/digest` found the second half, and it is
the stronger finding — a dialect there is not shorter code, it is **code that
cannot express the mistake.**

Against that: a declared grammar is silent in four ways where a fixed one is
loud, and every silence was found by running a program rather than by reading
the design.

---

## What the four declared

| | operators | forms | dialect | program |
| --- | ---: | ---: | ---: | ---: |
| [`ember`](../programs/ember) — an assembler | 0 | 16 | 18 | 220 |
| [`grammar`](../programs/grammar) — a PEG toolkit | 0 | 8 | 9 | 29 |
| [`digest`](../programs/digest) — SHA-256 | 17 | 3 | 20 | 96 |
| [`ledger`](../programs/ledger) — fixed-point decimal | 10 | 6 | 17 | 44 |
| [`prose`](../programs/prose) — a document | 0 | 7 | 9 | 64 |

*Lines are non-blank, non-comment. `program` is the module, `dialect` the file
it uses.*

**The split down the middle went unnoticed until the four were tabulated.**
The two programs about *another language* declare no operators at all and
nothing but forms. The two about a *value domain* declare mostly operators.
`prose` was written afterwards to look for a third case and did not find one —
it declares no operators and seven forms, and a document turns out to be a
domain of steps like the other two.

That is not a coincidence and it has a name already. `ember` found that the call
shape and the pattern shape "divide by what the form *is*, not by taste" — a
pattern "reads as a step in a procedure". So:

> **A domain of steps wants forms. A domain of values wants operators.**

Nobody chose that. Four programs arrived at it independently, and the two halves
of Proto's extension mechanism turn out to serve two different kinds of domain
rather than being two spellings of one thing.

---

## Where it pays most, measured

`digest` is the one case with an independent comparison, because Solveig has its
own SHA-256 and the two can be counted.

| | |
| --- | ---: |
| `bitAnd` in Solveig's `sha256sum.sol`, in code | 24 |
| of those, `bitAnd(mask)` — the mod-2³² discipline, written by hand | **18** |
| the same discipline in Proto's `sha256.pro` | **0** |
| where it went: masks inside `sha2.pro`'s declarations | **5** |

**Eighteen hand-written masks became five declarations**, and the six remaining
`bitAnd`s in the Solveig version are real algorithm ANDs, which Proto's version
writes as `&`.

That is the whole argument in one table, and the saving is not the thirteen
lines. It is that **after the header, forgetting a mask is not a thing the
program can do.** `+` *is* addition modulo 2³². `ember`'s and `grammar`'s
dialects only ever saved typing; this one enforces a correctness discipline, and
that is different in kind.

**The other end of the range is `ledger`**, and it is honest about it: three of
its functions are `format`, `padLeft` and `padRight`, and none of the three is
money arithmetic. The dialect covers the domain and the program is mostly the
scaffolding around the domain.

---

## What it costs

Four silences, each found by a program and none by a test.

| | found by |
| --- | --- |
| **Choosing the form's shape wrongly is silent.** A pattern where a call was meant parses, quietly takes what came after, and fails at run time in generated code. Both readings are legal and nothing at the declaration can say otherwise. | `ember`, then `grammar` — the same bug twice, the second time by the author of the sentence that says how to choose |
| **A wrong precedence is silent.** A module declares its own ladder, so there is nothing for `@infix * 60` to be wrong against. `digest` put `*` on `+`'s rung, compiled, ran, and failed as an array index four calls deep. | `digest` |
| **A template naming a hole twice evaluates it twice.** `>>>` expands `left` four times. Proto has hygiene and no way to say *bind this once*. | `digest` |
| **A dialect ends at its domain and cannot say where.** `+` as addition modulo 2³² is right for every line of SHA-256 and a trap for the loop counter beside it; `/` as rounding to the nearest hundredth is right for splitting a bill and wrong for taking a number apart. | `digest`, then `ledger` |

And two more that only the fourth program could find, because it was the first
with a value type rather than a machine word:

**One precision is not enough.** `ratio interest to subtotal` answers `0.07`
where the exact value is `0.074995…`. A ledger has amounts wanting two places
and rates wanting five, and a dialect has one scale to give. The domain boundary
is not only at the domain's *edge*.

**A spelling gets one meaning.** Amount ÷ amount is a ratio; amount ÷ count is
an amount. Both are `/`, and nothing can dispatch on what the operands turn out
to be. One of the two has to become a form and read worse for it.

---

## What it cannot do at all

**A rule cannot be a form.** `grammar` is the sharp case: a template cannot
declare a form, so a grammar's rules cannot be notation. They go into a table as
data, and `apply 'term` is a lookup. `ember`'s README had said *notation is not
recursive even when the program using it is*; `grammar` is the counterexample
that says what happens next — **the recursive part stops being notation and
becomes data.**

That is the ceiling. Everything a dialect can do, it does to one expression at a
time.

---

## And a claim that was true and is not

**A form is not a method that costs nothing at run time.** It was predicted to
be, and `digest` measured it: a template saves 2.03 instructions per rotation by
not calling and spends 2.00 recomputing a constant nothing folds — **98% given
back**. `ledger` then measured the same shape at **0.19%** rather than 5.4%,
because a dialect's constants cost per *use* and `ledger`'s uses sit outside its
loop.

Two measurements, and the second argues against the first's significance. The
case for folding rests on the claim being made true, not on the number.
[ROADMAP.md](ROADMAP.md) carries it.

---

## The fifth program, and what it settled

The four above were all arithmetic or instructions, and this page used to end by
asking for a domain that was neither. [`prose`](../programs/prose) is that: a
document language, with the document itself written in the dialect.

**It found no third category.** No operators, seven forms, and every content
line a step that appends — `ember`'s and `grammar`'s shape. The taxonomy
absorbed the new domain instead of being extended by it.

**It found the ceiling one level below where `grammar` left it.** A form takes a
block and a block holds statements, so a document nests as deeply as it likes
and the notation follows it down; Solveig's braces carry the structure.
`grammar`'s wall was narrower than *nesting* — a template cannot **declare** a
form, and a grammar's rules are definitions. A document's are not. What a form
still cannot do is contain *part of a line*:

> **A form can contain content. A form cannot contain half a line.**

Emphasis inside a sentence, a link mid-clause: a paragraph is one string, and no
arrangement of words and holes reaches inside it. That is the answer to *could
Proto do a markup language* — the block structure yes, the inline structure no.

**And it split "carrying a rule" in two.** `prose.pro`'s `indent <b: block>`
cannot be left unbalanced, because a block cannot be left unclosed. But the
dialect did not invent that rule; it borrowed one Solveig already enforces.
`sha2.pro` invented its own — nothing in Solveig makes `+` mask to 2³². **Only
the invented kind is evidence that a declared grammar does something a fixed one
cannot**, and it remains the one clear instance in five programs.

**What is still unknown** is smaller than it was. The measure has held across
five domains and the ceiling is now described rather than guessed at. What no
program has yet tried is a dialect used by *somebody who did not write it* —
every dialect here was written by the author of the file that uses it, an hour
before, and a notation's real cost is paid by the second reader.
