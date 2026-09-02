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
argument**, which is worth more than either. See *Settled by a customer* at the
foot of COMPLETED.md.

## Open, and undecided

**No postfix operators.** Proto has prefix and infix; `x++`, `a[i]` and
`p->f`-in-postfix-position have no spelling at all. `lib/clike.pro` names it as
one of the four things C has that it cannot. Not a rule that could be relaxed —
the extension point does not exist. No customer has been blocked by it.

**A hole's kind is one choice, with no alternation.** `lib/clike.pro` wanted *a
block, or another use of me* for C's `else` and could not say it, so a chain
wants its braces. Worked around; recorded because it is the same shape as
optional parts and would want deciding with them.

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

**A dialect ends at its domain and cannot say where. Two programs now.**
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

Still no proposal. A dialect that could say where it ends would have to say it
per operator and per quantity, which is a type system and a larger thing than
this project is.

**Nine of Solveig's syntactic forms are not Proto's.** Found first as a missing
integer literal, and then, on being asked whether that survey was complete, as
nine. Solveig's grammar for numbers:

```ebnf
integer = "#" [ "-" ] digit { digit }
        | "$" hexdigit { hexdigit }
        | "%" bindigit { bindigit } .
```

`#-5` compiles in Solveig and is an error here. `$FF08` and `%1011` are integers
there and nothing here. [GRAMMAR.md](GRAMMAR.md) says everything but `operator`
is Solveig's own spelling *so that a file can be read by somebody who knows
Solveig without a second set of habits*, and for integers that is false. Found
by `programs/ledger`, the first program here with ordinary negative values, and
it reaches back: `programs/digest` transcribed sixty-four SHA-256 round
constants out of the hexadecimal FIPS 180-4 prints them in, because `$428a2f98`
is not a thing Proto reads.

**The nine sort into five kinds, and none is left undecided:**

| closed in 0.11.0 | |
| --- | --- |
| `#-5` | Nothing else can begin with `#`, so the sign has no second reading to be confused with. |
| `$FF08` | `$` was not a token, an operator character, or anything else. The literal now goes out as written, so a base survives rather than being normalised to decimal. |
| `1e10`, `2.5E-3` | Float exponents, taken only when the digits are actually there — `2 e` is still two tokens. |
| `"\q"` | The escape set, narrowed to Solveig's five. This was the one where Proto was the *permissive* one and therefore the only one that emitted Solveig `solas` rejects. |

| closed in 0.12.0 | |
| --- | --- |
| `#[a = b]` | **Not free after all**, which is the correction this entry owes. The lexer was never the obstacle: Solveig writes `pair = sum "=" expression` and settles the ambiguity by *level*, which Proto cannot copy because a dialect may declare `=` anywhere and `lib/clike.pro` puts it at 10. The rule taken is that **a top-level `=` inside a dictionary is the separator, whatever the header said** — the one place in this language where a context outranks a declaration. It is confined to the top level of a key, so `#[(b = c) = d]` still uses the declared one, which is what makes it a rule rather than `=` being taken away. |

| closed in 0.13.0 | |
| --- | --- |
| `%1011` | **`%` is an operator character here and is not one in Solveig**, which has no `%` at all and can give the whole character to the literal. Proto splits it: a `%` *immediately* before `0` or `1` begins a number, and a `%` before anything else — a space, a `#`, a `2`, another operator character — is the operator it always was. Still no declaration is consulted, so a tool can tokenise a `.pro` knowing nothing about its dialect. |

| already decided | |
| --- | --- |
| `( \| t \| … )` | Temporaries in a group. In *Rough edges* below since 0.1.0; confirmed by running it rather than asserted. |
| `@expr(…)`, `@expr{…}` | Refused, in *Not planned* below. Solveig's fixed infix region is the special case `@infix` generalises. |

| forced, and never written down | |
| --- | --- |
| `-3` | Solveig's scanner gives the sign to the number outside a `@expr` region and treats it as the operator inside one. **Proto cannot have either half.** It has no regions, so it cannot be context-sensitive; and it cannot simply take `-3` as a literal, because then `a -3` stops being a subtraction in every dialect that declares `-`. A prefix declaration is the only reading left. |

**The last one is the interesting one.** Everything above it was a token Proto
could add, and 0.11.0 added four. `-3` is a token Proto **cannot** add without
giving up declarable `-`, which means *everything but `operator` is Solveig's
own spelling* was never achievable and the design chose against it in 0.1.0
without recording that it had. That is the extensible-operator line arriving
from a new direction — not a dialect wanting to change the lexer, but Solveig's
own number syntax being uncopyable while operators stay declarable.

Solveig has no conflict here because its operators are fixed. **Proto's are not,
and this is the extensible-operator line arriving from a direction nothing had
come from before** — not a dialect wanting to change the lexer, but Solveig's
own lexer being something Proto cannot fully copy while its operators stay
declarable.

**`%1011` is the one that cost something, and it is the only spelling here that
did.** A dialect declaring `%` can no longer write `a %0…` or `a %1…` without a
space. Nothing in this repository does — `%` as mod is written `n % #2`, because
mod wants an integer and a bare digit is a float — and the loss is loud rather
than silent, `a %10` becoming a name and then a number, which is not an
expression.

**It is worth naming as a shape.** `||` in 0.9.0 grew the fixed vocabulary and
cost only `{ || … }` out of the *core*; COMPLETED.md 12 held that up as the form
any future request should take. This is the second instance and the first with a
different bill: **growing the fixed vocabulary took something from what a
dialect may declare.** Small, loud, and unused here — but the next one might not
be, and *grow the vocabulary rather than making it declarable* should be read
with that attached.

**Two differences are left and neither is an oversight.** `@expr` is refused;
`-3` cannot be had.

## Waiting on a customer — optional and repeated parts

**Declined twice, and the second time with a reason.**

`programs/ember` wanted neither: no variadic notation, and `if`/`else` as two
declarations was fine.

`programs/grammar` was written partly to settle it, being the program most
likely to want repetition -- EBNF writes `sum = term { op term }` and means it.
It wants repetition and **a repeated pattern part would not have helped**: a
grammar cannot be written as forms at all, because a template cannot declare a
form, so the rules live in a table as data and the repetition wanted is in the
object language rather than in Proto. Both grammars have a `whileTrue` where
EBNF has a brace, and no Proto feature would have removed it.

That is a reason rather than a shrug, and it moves this below whatever the next
program finds.

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

## Rough edges

| | |
| --- | --- |
| Long send chains are not wrapped | A block that will not fit is broken across lines; `a:b(c):d(e):f(g)` is not. |
| Temporaries in a group | `( \| t \| … )` is Solveig's; Proto reads `( expr. expr )`. |
| The map is written only with `--map` | The Makefile always passes it. The default should probably change. |
| A generated name is `t__1` | Legible, and it collides with nothing because the whole module's identifiers are checked. It is still a name a person could have wanted. |
