# Roadmap

What is still outstanding, and what has been refused. Each entry says what would
have to be true before it is worth starting.

The work that is finished is in two places: [CHANGELOG.md](CHANGELOG.md) names
what landed and the commit that carried it, and [COMPLETED.md](COMPLETED.md)
keeps the case for each piece as it was argued *before* the work — the problem,
the options, and why the shape chosen was the one taken. What went wrong on the
way is in [POSTMORTEM.md](POSTMORTEM.md); what a day consisted of is in
[journal.md](journal.md).

**Two items on this page have been declined by a customer rather than by
argument**, which is worth more than either, and one has now been **taken** by
one. See *Settled by a customer* at the foot of COMPLETED.md.

**`lib/arith.pro`'s missing `<=`, `>=` and `!=` left this page on 2026-09-02.**
It is the entry the *one customer is not enough* rule was written down against,
and how it closed is worth carrying. `programs/prose` wanted `<=` and wrote
`while i < doc:size + #1` around it; `programs/basic` wanted `<=` and `>=` five
times and `!=` four. That is **two customers for `<=` and one each for the other
two**, so the bar was met for one of three and the family went in whole.

**The rule was applied and not bent.** An arith with `<=` and no `>=` is a worse
trap than an arith with neither, the missing one being missing for no reason a
reader can see. What the case actually shows is that **a customer count is per
surface, and a comparison set is one surface** — which nothing had had to decide
before. `lib/arith.pro` carries the argument at the declarations, and both
customers were rewritten to use them the same day, which is the check that the
customers were real.

## Open, and undecided

**A logical xor still has no spelling, and now needs one less.** For booleans,
xor *is* not-equals, and the argument for `^^` was that a module using
`lib/arith.pro` had no way to write one at all. It has `!=` since 2026-09-02, so
`a != b` on two booleans is an xor in both shipped dialects and the gap that
argument pointed at is closed. Nothing here has ever needed one.
[REFERENCE.md](REFERENCE.md) records that the spelling would be `^^` if it were
ever declared, so the question stays settled before it is asked.

**No postfix operators.** Proto has prefix and infix; `x++`, `a[i]` and
`p->f`-in-postfix-position have no spelling at all. `lib/clike.pro` names it as
one of the four things C has that it cannot. Not a rule that could be relaxed —
the extension point does not exist. No customer has been blocked by it.

**A hole's kind is one choice, with no alternation.** `lib/clike.pro` wanted *a
block, or another use of me* for C's `else` and could not say it, so a chain
wants its braces. Worked around; recorded because it is the same shape as
optional parts and would want deciding with them.

**Two strangers have been put in front of the workaround and neither paid for
it.** [second-reader.md](second-reader.md)'s second run was designed to force
the chain, and the reader wrote `else { if (…) { … } }` on the first attempt
without trying `else if` once — because `lib/clike.pro` spends eleven lines on
it **at the declaration itself**, naming the silent `{ { … } }` failure and
spelling the fix. Their words: *I would have tried `else if` first if the
dialect file had not spent a paragraph on it.*

> **A limitation explained where it is declared is not a limitation a reader
> pays for. It is one its author paid for once.**

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

**And since 0.17.0 the compiler says it too.** *Once* was once **per dialect**:
`lib/clike.pro`'s author paid it, and the next dialect with a `block` hole has
an author who has not. The hole-kind diagnostic now carries `wrap it in braces
-- '{' before this and '}' after it`, which is the workaround this entry is
about, prescribed at the failure by the only part of the system that reaches a
reader who has read nothing. **It does not make `else if` work and it is not a
step towards alternation** — it makes the wall say how to climb it. See
[COMPLETED.md](COMPLETED.md) 17, which argues why only `block` gets a
prescription.

**Two more readers met a `block` hole afterwards and neither wanted alternation
either.** Run 3 used `lib/clike.pro` and needed no cascade; run 4 **declared a
form with a `block` hole of its own** and reported expecting to need two
declarations for a one-statement and a two-statement body — *the way
`control.pro` needs two for `if` and `if/else`* — and finding one enough. **A
hole that asks for a block does not care how much is in it**, which is the
nearest thing to alternation anybody has actually wanted.

**So this drops below where it was**, and for the fourth time an entry here has
been answered by a customer declining to need it — the first time by a customer
being *told* in advance rather than by one working it out. What would move it is
a use where the workaround is not merely verbose but **unwritable**, and neither
of the two dialects that wanted alternation has produced one.

**A template's constants are never folded, and it costs what the template
saves.** `@infix >>> 55 => (left:shiftRight(right)):bitOr((left:shiftLeft(#32:sub(right))):bitAnd(#4294967295)).`
expands with `#32:sub(#17)` inside it, evaluated once per use at run time.
`programs/digest` measured both halves on a 4 KB hash, by binary search on
`--steps`:

| | instructions |
| --- | ---: |
| `>>>` expanded as a template | 1,362,533 |
| `>>>` as a method on `integer` | 1,437,417 |
| saved by not calling | 74,884 — 2.03 per rotation |
| spent on the unfolded constant | 73,728 — 2.00 per rotation |

**A form gives back 98% of what it saves**, so *a form is a method that costs
nothing at run time* is not true today. Folding would win 5.4% on that program.

**A second customer, and it argues the other way.** `programs/ledger` names its
precision once — `@syntax scale => #100.` — and round-half-up then wants half a
unit, so `scale:div(#2)` expands to `#100:div(#2)`: the same shape, reached from
a different direction. Measured the same way, against a hand-folded copy:

| | instructions |
| --- | ---: |
| as written | 4,258 |
| every constant folded by hand | 4,250 |
| saved | 8 — **0.19%** |

**A dialect's constants cost per *use*, and this dialect's uses are outside the
loop.** SHA-256 rotates inside sixty-four rounds of every block, so
`#32:sub(#17)` runs 36,864 times on a 4 KB input; a ledger writes `*` and
`percent` once each and keeps writing them once whether it has five
transactions or five thousand,
the loop over them carrying no constant at all.

So the number is 5.4% or 0.19% depending on where the dialect sits, and **one
measurement made this look larger than it is**. What survives is the claim, not
the figure: *a form is a method that costs nothing at run time* is either true
or it is not.

**A third customer, and it declines.** `programs/bignum` has its base in the
inner loop, which is `digest`'s shape, and no send in its generated code has
two literal operands: `digit(t)` is `t:mod(#1000000000)`, and nothing is
*derived* from the base the way `ledger` derived half a unit from its scale. A
folder would find nothing to do. Predicted before the program was written, and
right, so this entry moves by a customer declining rather than by a figure.

**It is not obviously safe, which is why this is an entry and not a patch.**
Folding `#32:sub(#17)` means evaluating a send at expand time, and `integer:sub`
is a slot a Solveig program may assign — run rather than assumed:

```
integer:sub := { other | #999 }.
(#32:sub(#17)):print.               ; #999, and not #15
```

So an expander that folds has decided some sends are safe to run, and has
decided it on behalf of a program it cannot see. That is the same question
[rules-and-logic.md](rules-and-logic.md) asks about guards, one size smaller.
Guards ask *may parsing depend on evaluation*, and are answered no, because
otherwise no tool could read a `.pro` without running it. This asks *may
expansion depend on evaluation*. Both answers today are the same uniform
**nothing runs at expand time**, and folding puts the first hole in it.

### The rule to settle first

**Which sends may be evaluated at expand time, and who is allowed to have
redefined them.** Three shapes, cheapest first, and what each concedes:

| | |
| --- | --- |
| **An allowlist, over literal receivers only** | Fold a send whose receiver and arguments are all literals and whose selector is on a fixed list — `add`, `sub`, `mul`, `shiftLeft`, `bitAnd`. Nothing with a name in it, so `#32:sub(#17)` qualifies and `x:sub(#17)` never does. Small, and it reaches the case that motivates the entry. **It concedes a guarantee Proto cannot check**: a program that reassigns `integer:sub` gets one answer from folded code and another from unfolded, and nothing will say so. |
| **Fold only what the module provably does not reassign** | Sound, and it does not apply. The reassignment may live in a `.sol` reached by `@include`, which Proto passes through without reading — by design, since a dialect provides syntax and `@include` provides code. Undecidable at exactly the boundary this project put there on purpose. |
| **Expand-time arithmetic that is not Solveig** | Keep *nothing runs at expand time* exactly as it stands, and give a template a separate notation for computing on its holes. Correct, and it costs a second language inside the first — the tower [rules-and-logic.md](rules-and-logic.md) spends its length refusing. |

**The first is the only cheap one, and it is cheap because it moves a guarantee
onto the programmer.** It would be the first time Proto says *this is correct
unless you did something Proto cannot see*, and every rule on this page is the
other way round: a `.pro` means what it says, by reading it. That is the
decision, and it is not a decision about performance.

**What would make it worth starting.** A second program wanting it — one
customer is not a reason to grow a surface, which is
[conventions.md](conventions.md)'s standing rule and Solveig's before that — or
a decision that *a form is a method that costs nothing at run time* is worth
making true for its own sake. **The number is small and the claim is not**: 5.4%
on one program is not an argument, but a sentence in the README that is 98% true
is a different kind of debt.

**A dialect ends at its domain and cannot say where. Three programs now, and
the third had no trap, which is the first proposal.**
`programs/digest` declares `+` as addition modulo 2³², right for every line of
SHA-256 and a trap for the loop counters beside it — `shift - #8` at zero is
`#4294967288` and the loop never ends. `programs/ledger` declares `/` as
rounding to the nearest hundredth, right for splitting a bill four ways and
wrong for taking `-1225` apart into `-12.25`, which wants the floored whole part
and remainder. Both write those lines with sends and a comment.

**A pattern rather than an anecdote, and the second instance narrowed it
twice.** The trapping operator is not predictable from outside the domain —
`ledger`
predicted `*` and was bitten by `/` — so nothing here should promise that a
dialect's danger is findable by inspection. And the boundary is not only at the
domain's *edge*: `ratio interest to subtotal` answers `0.07` where the exact
value is `0.074995…`, because a ledger has amounts wanting two places and rates
wanting five, and a dialect has one scale to give. **The same dialect can be
wrong for a second quantity inside its own domain.**

A dialect that could say where it ends would have to say it per operator and
per quantity, which is a type system and a larger thing than this project is.

**`programs/bignum` was written on 2026-09-13 to find the boundary, in two
modules whose headers were meant to disagree about `+`, and found there was
none to find.** Its values are objects, so `+` is `add` and the receiver
decides; the library's `*` is an integer product on one line and a bignum
product two methods down under one declaration, and the loop counters beside
the domain are as safe as the domain. The proposal is not a feature: **a
dialect traps its scaffolding exactly when its domain's values are the
substrate's own**, because then a template on the spelling is the only place
the rule can go and a template cannot look at its receiver. A 32-bit word and
an amount in hundredths are integers, so `digest` and `ledger` had to invent
and were bitten; a bignum is not, so nothing was invented and nothing bit. The
question to ask before writing a domain dialect is therefore *are its values
the substrate's own*, and if they are, the trap is certain and the workaround
is the one both programs used. [does-it-pay.md](does-it-pay.md) has the
argument under *The seventh program*.

## Waiting on a customer — optional and repeated parts

**Declined three times, and the last two with the same reason.**

`programs/ember` wanted neither: no variadic notation, and `if`/`else` as two
declarations was fine.

`programs/grammar` was written partly to settle it, being the program most
likely to want repetition -- EBNF writes `sum = term { op term }` and means it.
It wants repetition and **a repeated pattern part would not have helped**: a
grammar cannot be written as forms at all, because a template cannot declare a
form, so the rules live in a table as data and the repetition wanted is in the
object language rather than in Proto. Both grammars have a `whileTrue` where
EBNF has a brace, and no Proto feature would have removed it.

`programs/basic` met both again and declined both from the far side. BASIC's
`PRINT a, b, c` is a repetition and its `STEP` clause is an optional part, and
they are `while opIs(",") do …` and `if wordIs("STEP")` in an ordinary parser —
**in the interpreted language, one level below anything a header can reach.**
Same reason as `grammar`'s, arrived at from a domain with no grammar in it.

That is a reason rather than a shrug, and it moves this below whatever the next
program finds. **Three programs have now been offered the feature and none has
wanted it**, which is the strongest form of evidence this project collects.

**`if <c> then <a> else <b>` is a second declaration rather than an optional
tail**, which is honest and costs a line. Repetition — a form taking a list —
has no spelling at all, and wants one before anybody writes `sum of <a> <b> <c>`
three times.

Two more part kinds in an array the matcher already walks. **The property to
keep is that an optional part begins with a word**, for the reason a pattern
does: it is what lets one token decide whether the part is there, and it is what
keeps the matcher free of backtracking.

**Then a guard, and the evaluator it needs is Solveig.** `solum/embed.h` was
built for it — one of the three cases it names is *a tool scripted in Solum* —
and `embed/host.c` already wrote the loop: compile one script once, run it many
times, each under its own allowance. Compile the guard once, run it per use, and
`serve_one` becomes `check_one`.

It costs *the build needs no Solveig*, which is real. It does not cost *no
privileged access*, which is the claim that matters: `embed.h` is a declared
surface, and using it is the mirror of solveig-sdl using `extend.h`. **The rule
to fix before any of it is written: a guard validates, it does not select** —
otherwise parsing depends on evaluation and no tool can read a `.pro` without
running it.

0.6.0 is the reason this is not urgent. The five kinds cover what a guard would
mostly have been used for, and they cover it without an evaluator.
[rules-and-logic.md](rules-and-logic.md) argues the whole of it.


## Retracted

**A form's trailing hole swallowing what follows was written up twice as a
limitation and is not one.** `programs/ember` reported it for postfix sends and
`programs/grammar` for infix operators, and both were the same mistake: a form
declared as a pattern when it was an application. A call ends at its closing
parenthesis and has no such behaviour.

The sketch of a fix that went with it -- a trailing hole binding at `unary`
precedence, declared per form -- described a feature nothing needs. It is not on
this page any more.

**What the two programs really found is that choosing the shape wrongly is
silent.** A pattern where a call was meant parses, quietly takes what came
after, and fails at run time in generated code if it fails at all. Nothing at
the declaration can say otherwise, both readings being legal. The rule is now in
[GRAMMAR.md](GRAMMAR.md) under *Which shape a form should have*, which is where
somebody choosing one would look; it had been in a program's README, which is
not.

## Not planned, and why

**A dialect that changes the lexer.** The line between a fixed token stream and
a declared grammar is where this design sits. An extensible grammar over fixed
tokens can still be parsed by something that has not run the file's own
declarations, and every editor, formatter and `grep` downstream depends on that.
Forth and TeX moved the line and became languages no tool can read without
executing them. If it moves, it moves at the module boundary and nowhere else.

A `@token` directive binding a spelling to a named token was proposed against
this and refused in 0.9.0: it would not have crossed the Forth line, the header
still being read rather than run, but it crosses a nearer one — today any tool
can tokenise any `.pro` without knowing what a dialect is. The want behind it
was real and `||` answers it, by growing the fixed vocabulary rather than by
making the vocabulary declarable. That is the shape any future version of this
request should take. See COMPLETED.md 12.

**A rule that begins with a nonterminal.** Left recursion, and therefore an
expression grammar written in `@syntax`. The reader would have to guess,
ambiguity would stop being checkable by looking, and composition would stop
being safe -- and the case that motivates it is already read from the precedence
table. [rules-and-logic.md](rules-and-logic.md) argues all three.

**Emitting bytecode, or machine code.** Proto would then own the `.sob` format
and Solum's instruction set, and reimplement what Solas already does. The one
thing it would buy — errors from Solas landing on Proto source — the map buys
instead. [targets.md](targets.md) works the question through, including what a
native back end would actually cost and why a program *written in* Proto can
already emit anything it likes.

**`@expr`.** Solveig's fixed infix region is the special case of what `@infix`
generalises. Supporting both would be supporting two.

**A signed bare number — `-3` rather than `#-3`.** Solveig's scanner gives the
sign to the number outside a `@expr` region and treats it as the operator inside
one. **Proto can have neither half.** It has no regions, so it cannot be
context-sensitive; and it cannot simply take `-3` as a literal, because then
`a -3` stops being a subtraction in every dialect that declares `-`. A prefix
declaration is the only reading left, and `#-3` — where nothing else can begin
with `#` — is why the *integer* keeps its sign.

This is the extensible-operator line arriving from a direction nothing had come
from: not a dialect wanting to change the lexer, but **Solveig's own number
syntax being uncopyable while Proto's operators stay declarable.** It means
*everything but `operator` is Solveig's own spelling* was never achievable, and
0.1.0 chose against it without recording that it had.
[COMPLETED.md](COMPLETED.md) 15 has the whole survey — nine differences, seven
closed across 0.11.0 to 0.13.0, and this one and `@expr` left.

## Rough edges

**Filed severities on this list are guesses until somebody checks one.** A
fifth row lived in `README.md` saying a `@use` path is not normalised, that
`examples/../lib/control.pro` is what a diagnostic shows, and that two spellings
of one file are two files — filed as cosmetic, with `realpath` already named as
the fix. It was checked on 2026-09-04 and the second clause was the whole
defect: the same string comparison decided whether a file had been read, so a
diamond spelled two ways warned that a file collided with itself and a cycle
spelled two ways was reported as *nested more than 64 deep*.
[POSTMORTEM.md](POSTMORTEM.md) 24.

**The sentence was right and the severity was wrong**, because the entry
described what a diagnostic *shows* and never asked what else compared those
strings. **What makes a rough edge cheap to leave is exactly what makes it cheap
to file without looking.**

**A second row has since been checked, and it also matters.** Run 4 of the
reader experiment produced the failure this project names as the one that kills
syntax-extension systems — `solvm` reporting `undefined name 'total'` at
`banner.sol:8`, a line in the **generated** file, after seven lines of correct
output. **No map had been written**, because the map is opt-in. With one, the
recovery is exact: generated `8:5` is source `10:5`, the line the reader wrote.

**The mechanism works and was switched off**, and that is the whole argument for
changing the default: a map costs one file and nothing else, and the invocation
that omits it is the shortest one — which is the one a person types.

**It is not settled, and the reason is [POSTMORTEM.md](POSTMORTEM.md) 27**: the
reader was *told* to invoke it without `--map` by the experiment's own prompt,
which differs from `README.md`'s quickstart. So the cost of the minimal
invocation is measured and the likelihood of a reader choosing it is not. **The
next run uses the published invocation**, and that is what would settle it.

The two rows still unchecked are long send chains and `t__1` names; temporaries
in a group is a stated absence rather than a severity guess. A fifth row was
added on 2026-09-13 and checked the day it was found.

| | |
| --- | --- |
| Long send chains are not wrapped | A block that will not fit is broken across lines; `a:b(c):d(e):f(g)` is not. |
| Temporaries in a group | `( \| t \| … )` is Solveig's; Proto reads `( expr. expr )`. |
| The map is written only with `--map` | The Makefile always passes it, and so does `README.md`'s quickstart. **A reader run reached the failure the map exists for, with no map written** — see below. |
| A generated name is `t__1` | Legible, and it collides with nothing because the whole module's identifiers are checked. It is still a name a person could have wanted. |
| A generated line is a span | A `while` body or an `if` arm is emitted on one line, and a run-time trace carries a line and no column, so the map, exact to the column, cannot narrow it. Checked on `programs/bignum`: 16 of the library's 103 generated lines carry more than one source line, four at worst. Either Proto keeps a line break inside an expanded hole, or Solveig's trace gains the column its compile errors have. Neither built; `solveig-notes.md` 4 is the second half. |
