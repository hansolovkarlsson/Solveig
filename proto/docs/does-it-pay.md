# Does a grammar declared per module pay?

*[targets.md](targets.md) names the question this project exists to answer —
**whether a grammar declared per module is a good idea** — and then leaves it to
be answered somewhere else. Seven programs have answered parts of it, each in
its own README, each quoting the one before. This is the seven of them weighed
together.*

*Four are tabulated below; the fifth, sixth and seventh have sections of their
own, because each was written after this page existed and against the question
this page ended on at the time.*

***And four readers who did not write any of it have since been measured against
the question the seven programs could not touch.** Their sections are at the foot,
and they are the only evidence here not produced by the author of the thing
being judged — see [second-reader.md](second-reader.md).*

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

## What the seven declared

| | operators | forms | dialect | program |
| --- | ---: | ---: | ---: | ---: |
| [`ember`](../programs/ember) — an assembler | 0 | 16 | 18 | 220 |
| [`grammar`](../programs/grammar) — a PEG toolkit | 0 | 8 | 9 | 29 |
| [`digest`](../programs/digest) — SHA-256 | 17 | 3 | 20 | 96 |
| [`ledger`](../programs/ledger) — fixed-point decimal | 10 | 6 | 17 | 44 |
| [`prose`](../programs/prose) — a document | 0 | 7 | 9 | 64 |
| [`basic`](../programs/basic) — a BASIC interpreter | 0 | 15 | 16 | 251 |
| [`bignum`](../programs/bignum) — arbitrary precision, in two modules | 1 | 5 | 5 | 153 |

*Lines are non-blank, non-comment. `program` is the module, `dialect` the file
it uses.*

**The split down the middle went unnoticed until the four were tabulated.**
The two programs about *another language* declare no operators at all and
nothing but forms. The two about a *value domain* declare mostly operators.
`prose` was written afterwards to look for a third case and did not find one —
it declares no operators and seven forms, and a document turns out to be a
domain of steps like the other two. `basic` is the fourth with no operators,
and it is the one that says why the split is not a taxonomy of programs — see
*The sixth program* below.

That is not a coincidence and it has a name already. `ember` found that the call
shape and the pattern shape "divide by what the form *is*, not by taste" — a
pattern "reads as a step in a procedure". So:

> **A domain of steps wants forms. A domain of values wants operators.**

Nobody chose that. Four programs arrived at it independently and two more have
arrived since, and the two halves of Proto's extension mechanism turn out to
serve two different kinds of domain rather than being two spellings of one
thing. **What the sixth adds is a limit on the claim**, not a sixth data point:
it is a taxonomy of domains a *dialect can see*.

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
cannot**, and it remains the one clear instance in seven programs.

**What was still unknown** was a dialect used by *somebody who did not write
it* — every dialect here having been written by the author of the file that uses
it, an hour before, and a notation's real cost being paid by the second reader.

**That was measured on 2026-09-03**, and it is the section at the foot of this
page.

---

## The sixth program, and the ceiling stated properly

The five above are all a **pass over an input**: they walk it from one end to
the other, in the order it is written. [`basic`](../programs/basic) is a BASIC
interpreter, and it is the first with a program counter that can go backwards,
an environment outliving every statement, and statements running a number of
times the source does not say.

**It found the ceiling is one sentence and not two.** `grammar` said a rule
cannot be a form, so a grammar's rules become data, and that was read as a limit
on recursion. It is not about recursion. An interpreter meets the same wall
twice with none in sight:

| what it wants to write | why it cannot |
| --- | --- |
| a **form** per statement kind | which kind it is arrives with the input |
| an **operator** for BASIC's `+` | which operator it is arrives with the input |

> **Notation is fixed when a file is read. An interpreter's every decision is
> made after that.**

So an interpreter uses the least notation of any program here, and for one
reason covering both halves of Proto rather than two reasons covering one each.

**And it dissolves the two-domain question rather than answering it.** BASIC has
a real domain of values — `+` is add-or-concat, exactly what `digest`'s and
`ledger`'s operator dialects are for. It never reaches the header. The
interpreter never writes `a + b` on two BASIC values anywhere: it writes
`binop:value(op, a, b)` where `op` is a *string that came from the input*, and
each branch is a send that already knows its operation. Two `+` survive in 251
lines and both are `pc + #1`.

**A program can contain a domain without being one**, and the split above is a
taxonomy of *domains a dialect can see*. A domain one level down is invisible to
every header there will ever be.

### What it bought anyway

Fifteen forms used ninety-three times, and the clearest of them is the counter:
`fallThrough`, `step` and `jump to` are the only places a position moves, so
two `+` on integers survive in the whole interpreter. **That is locality and not
enforcement** — nothing stops a hand-written `pc := pc + #2`, where `sha2.pro`
makes forgetting a mask impossible. The one clear instance of a dialect carrying
an *invented* rule is still `digest`'s, and it is now one in six.

### And it is the first program that needed hygiene

`take`'s template has a temporary `t`; `parseAtom` has a local `t` and calls
`take` into it. The generated source renames the template's, so the parser keeps
its token. **Nobody noticed while writing it**, which is exactly what the
argument for putting hygiene in with forms in 0.2.0 predicted, and the only
evidence that argument could ever have.



## The seventh program, and why the invented kind traps

Every value domain here had been Solveig's own integer wearing a rule: a
32-bit word, an amount in hundredths. [`bignum`](../programs/bignum) is a value
domain whose values are **objects**, and it is in two modules that were meant
to disagree about `+`, to find where a dialect ends. They did not disagree.
`limbs.pro` is five lines, declares no operator, and takes `lib/control.pro`
unchanged; the driver takes the same file and adds `^`. One `@infix + 60 add.`
adds two limbs in the library and two bignums in the driver, and inside the
library one `*` is an integer product on one line and a bignum product two
methods down.

**So the first domain dialect with nothing invented is also the first with no
trap**, and the two facts are one. `digest`'s `+` and `ledger`'s `*` are
templates because their values are integers and a rule on an integer has
nowhere to live but the spelling; a template cannot look at its receiver, so
the rule reaches the loop counter beside the domain as surely as the domain.
A bignum's rule lives in `big:add`, dispatch reads it off the receiver, and the
header has nothing to add.

> **A dialect traps its scaffolding exactly when its domain's values are the
> substrate's own, because then the spelling is the only place the rule can
> go.**

That narrows the table above from the other side. The invented kind is the only
evidence that a declared grammar does something a fixed one cannot, and it is
also the only kind that costs a silence: the two are the same property. A
domain that is an object gets its notation from arithmetic's spellings for
free and gets nothing else from the header, which is why this dialect pays
least of the seven: five lines, and what they buy is `digit(t)` and
`carry(t)`.

**And it measured the other question, the one from outside.** Solveig's own
`ideas.md` wants *a large-number-math library* one day. This one is 126 lines
of generated Solveig, correct against `bc`, and 170× slower than CPython's
`int` at `1000!`, 44 instructions per limb product with the one-based index
arithmetic costing as much as the array access. It is a library. The ratio is
what a C extension would buy, and nothing has waited for it yet.
---

## The second reader, measured

[second-reader.md](second-reader.md) has the design, the six predictions
committed before the run, and the full result. What it changes here:

**The notation cost nothing, and that is the headline.** A reader who had never
seen the language wrote a correct program **on the first compile-and-run**,
taking `=`, `%`, `&&`, `while`, nested `if` and the precedence rungs from one
example and one table, and never opening the README in full.

**And they declared an operator of their own, unprompted, in that first
program** — `@infix ++ 55 concat.`, at a precedence chosen to sit under `+`,
mixed into a module that also `@use`s a dialect. The claim this project exists
to test is that a programmer can declare notation. The first stranger to touch
it did, unasked, and got it right.

**Every cost was on the other side of the compiler**, which turns the cost table
above inside out. Seven programs found four silences, and all four are things a
*dialect* does — a wrong precedence, a hole's shape, a domain boundary, a hole
named twice. **A reader met none of them.** What they met was:

| | |
| --- | --- |
| **A dialect is documented and its substrate is not** | `asString` appears **nowhere** in anything a stranger is given; `display` and `concat` once each, one of those as filler inside a warning example. Every non-syntactic decision was guess-then-run, and `string does not understand 'show'` names a wrong message without naming a right one. |
| **`print` is a repr and the example taught it wrongly** | Seven string `:print`s in `examples/clike.pro` and the output of none shown; its only two output comments are on integer prints, where `print` and `display` are indistinguishable. **The example demonstrated the message exactly where its trap is invisible.** |

Both are fixed. Neither is about notation at all.

> **A declared grammar's cost to its author is the dialect. Its cost to a reader
> is the substrate.** Seven programs measured the first and could not have found
> the second, because an author already knows what sends exist.

**And the proxy flattered it.** The design said in advance that a session with
no context still knows Smalltalk, so anything produced untraceable to a document
counts as an assist and the bias runs one way. It ran that way: `concat` and
`asString` were guessed correctly from **zero** documentation. A reader without
that background does not guess them. **So the one real finding is worse than the
run makes it look**, which is the correction the design was built to allow.

**What is still unknown**, and it is the only thing left on this page's list:
the *other* half of a second reader's cost — reading somebody else's Proto a
year later. This measured learning a notation once. There is no year-old Proto
and no second author, so nothing can measure the rest yet.

*A second run followed, below, and did not change that.*


### And a second reader, run to force the one rough edge

The first run never reached `lib/clike.pro`'s known rough edge, so a second was
designed around it: a three-way classification, which in C is `else if`.

**The reader never wrote the chain.** They wrote the nested braces on the first
attempt, correct output first compile-and-run, no diagnostic emitted at any
stage — because the dialect file explains the limitation in eleven lines **at
the declaration itself**.

> **A limitation explained where it is declared is not a limitation a reader
> pays for.**

**Run 3 narrowed this on 2026-09-04, and it needed narrowing.** The
`print`-is-a-repr trap is explained at the line it is about and the third
reader read that comment, quoted it back, wrote `:print` anyway and paid the
cycle. **The rule holds for a refusal and not for a silence**: `else if` is
something a reader must choose to type, so a warning read beforehand removes
the option; `:print` compiles, runs, and looks right, so the warning describes
something they cannot recognise until they already have it.

> **A warning prevents a failure you would have chosen. It does not prevent one
> you would have walked into believing you had succeeded.**

It is kept rather than replaced, because it is true of what it was measured on.
[POSTMORTEM.md](POSTMORTEM.md) 26 is why it should not have been stated wider
than that on one reader.

**And it measured the first run's two fixes.** Both were one line, neither
touched the compiler, and the second run is the control: six `does not
understand` probes became **zero**, and the `print`-is-a-repr trap that cost run
1 a cycle was caught before it fired. The reader named `REFERENCE.md`'s new
*What is not here: the messages* section as *the decisive signpost*.

Which sharpens the rule this page ended on rather than replacing it:

> A declared grammar's cost to its author is the dialect, and its cost to a
> reader is the substrate — **and both are paid in documentation, not in
> syntax.** Two one-line sentences removed every cost the first reader met.

**Neither of the first two readers opened the README.** One grepped it after
the fact, one never opened it at all. Six programs' worth of evidence sat behind
a front page that neither stranger read.

**That was acted on, and the third reader measured the fix the same day.**
`README.md` gained a *Where to start* section on 2026-09-04 — twenty-five lines
naming the dialect file, the example and the reference, opening with *Not here.*
Run 3 opened the front page **first**, met that section, went where it pointed,
and *stopped reading README past that point and did not go back to it later.*

**Which is the front page working rather than the front page being skipped**,
and it is the first evidence any of it has ever been load-bearing. The entry
point is still the dialect file, the example and the reference — a front page's
job is to be read once, briefly, and left.

## What four readers say about the diagnostics, which is nothing

**No reader has ever seen one.** Four runs, four tasks, and the two built
specifically to force an error produced none — the first stopped by the eleven
lines `lib/clike.pro` spends at its `else` declaration, the second by
`examples/dialect.pro` showing a one-statement body wearing braces.

**The costs a reader actually met came from three places, and Proto's
diagnostics are not among them:**

| | |
| --- | --- |
| the example | supplied *nearly 100%* of run 3's program, by its author's account, and taught run 4 the braces it copied |
| the dialect file | supplied the shape of the form run 4 declared, from `repeat <n> times <b: block>` |
| **Solveig's runtime errors** | got run 4 out of the one real failure in four runs, *from the message alone* |

**Run 4 met the failure this whole project is built against** — `solvm` naming
`banner.sol:8`, a line in a generated file, after seven lines of correct output
— and **the map that recovers it had not been written**, being opt-in. The
substrate's error text was good enough to self-diagnose without it.

> **A declared grammar's cost to a reader is paid in the substrate, and so is
> the rescue.** Four readers have been served by Solveig's documentation and
> Solveig's diagnostics at every point where this project's own would have had
> to work.

That is the sharpest thing four runs have to say, and it is not what any of
them was designed to ask.
