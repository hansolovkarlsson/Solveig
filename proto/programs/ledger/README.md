# A ledger in fixed-point decimal, written in Proto

**Predictions recorded before the program was written.** That is
[conventions.md](../../docs/conventions.md)'s rule, and this file is committed
before a line of `ledger.pro` exists so that the ordering is in the history
rather than in a claim.

## Why this one

The fourth program, and picked to answer two roadmap entries at once.

**[ROADMAP.md](../../docs/ROADMAP.md) wants a second program with a
domain-shaped dialect.** `programs/digest` found that a dialect is right for its
domain and a trap for the scaffolding beside it — `+` meaning *addition modulo
2³²* is correct on every line of SHA-256 and wrong on the loop counter under it.
One program is an anecdote. This is a different domain with the same shape:
money is fixed-point decimal, `*` on two amounts is not integer multiply, and
the loop indices around it are ordinary integers.

**The folding entry wants a second customer.** It has one measurement, from one
program, on one operator. If constants only ever go unfolded in `>>>`, that is a
weaker case than it looks.

And it is a **value type**, which the other three are not — a code generator, a
parser and a hash. If a declared grammar per module only pays for flat
repetitive arithmetic, that is worth finding out from the program that is not
flat.

## What was predicted before it was written

| | |
| --- | --- |
| **1. Naming the scale produces an unfolded constant.** | A fixed-point dialect wants its precision written once, and `@syntax scale => #100.` is how Proto spells that. Round-half-up then wants half a unit, which is `scale:div(#2)` — and expands to `#100:div(#2)`, a send on two literals evaluated once per multiply. Predicted: **digest's `#32:sub(#17)` in a second domain, arrived at from a different direction**, and exactly the second customer the roadmap asks for. |
| **2. `*` is a trap for the scaffolding.** | Declared as fixed-point multiply, `#3 * #2` is `0.06` and not `6`. Predicted to bite in the loop and formatting code the way digest's `+` did, and predicted to be worked around the same way — a send with a comment. **The prediction is that the second instance makes it a pattern rather than an anecdote**, which is all the roadmap entry is waiting for. |
| **3. Yesterday's prediction about the allowlist is wrong.** | Asked what folding would need, the answer given on 2026-09-02 was that a literal-only allowlist would prove too narrow, because the interesting constants look like `scale:mul(#100)` with `scale` a name. Predicted now to be **wrong**: `scale` is a *form*, so it is gone before the folder could ever see it, and what survives expansion is `#100:div(#2)` — all literals, and the cheapest rule reaches it. Recorded because it was written down where somebody can go back and disagree with it. |
| **4. Division wants two meanings and can have one.** | Amount ÷ amount is a *ratio* and unscaled; amount ÷ count is an *amount* and scaled. Both are `/`. A dialect declares one meaning per spelling and cannot dispatch on what the operands turn out to be. Predicted: this bites, the workaround is a form for one of the two, and it is **the sharpest finding against Proto here** — and new in kind, because digest never met it, every operand there being a 32-bit word. |
| **5. The notation pays less than digest's, and formatting is why.** | `programs/grammar` established that **a dialect pays per line it removes**. Money arithmetic is a handful of lines; turning cents into `-12.34` is sign handling, digit padding, and `div`/`mod` that are **floored** in Solveig — `#-1234:div(#100)` is `#-13` and `mod` is `#66`, so the naive formatter prints `-13.66`. Predicted: a real fraction of this program sits outside the notation entirely, and the dialect earns less here than in sixty-four rounds of hashing. |

## How it is checked

`make test` runs it and diffs against `ledger.expected`. The expected figures are
produced independently, in exact decimal arithmetic, and not by this program —
the same discipline `programs/digest` used against `shasum -a 256`. A program
that verifies itself verifies nothing.

## What it found

Written after. The predictions above were committed in `68da051`, before a line
of `ledger.pro` existed.

### The predictions

| | |
| --- | --- |
| **1. Naming the scale produces an unfolded constant** | **Right about the shape, wrong about what it is worth — and that is the finding.** `@syntax scale => #100.` with round-half-up expands to exactly the predicted `#100:div(#2)`, and `percent` to `#100:mul(#100)` twice over. Measured against a hand-folded copy by binary search on `--steps`: **4,258 instructions against 4,250. Eight, or 0.19%.** digest's was 5.4%. |
| **2. `*` is a trap for the scaffolding** | **Right that an operator traps, wrong about which one.** `*` on a non-amount never arose — the loop counter and the array indices use `+`, which needs no scaling. What trapped is `/`. |
| **3. Yesterday's allowlist prediction is wrong** | **Right, and it retracts an answer given the day before.** `scale` is a *form*, so it is gone before a folder could see it; what survives expansion is `#100:div(#2)` and `#100:mul(#100)`, literals throughout. **A literal-only allowlist reaches every foldable site in this program.** |
| **4. Division wants two meanings and can have one** | **Right, and it cost a form.** `/` is amount ÷ count. Amount ÷ amount is `ratio <a> to <b>`, because a spelling gets one meaning and nothing can dispatch on what the operands turn out to be. |
| **5. The notation pays less than digest's** | **Right, and understated.** Three of the program's functions are `format`, `padLeft` and `padRight`, and none of the three is money arithmetic. |

### 1 is the finding, and it is against the roadmap entry that asked for it

The folding entry wanted a second customer. It has one now, and **the second
customer argues the other way.**

| | instructions |
| --- | ---: |
| as written | 4,258 |
| with every constant hand-folded | 4,250 |
| saved | 8 — 0.19% |

The shape is identical to `>>>`; the cost is not, and the reason is not the
dialect. **A dialect's constants cost per *use*, and this dialect's uses are
outside the loop.** SHA-256 rotates inside sixty-four rounds of every block, so
`#32:sub(#17)` is evaluated 36,864 times on a 4 KB input. Here `*` and `percent`
are each written once, and stay written once whether the ledger has five
transactions or five thousand — the loop over transactions uses `+`, which
carries no constant at all.

So folding is worth 5.4% on a program whose dialect is in its inner loop and
0.19% on one whose dialect is not. **That is a smaller claim than one
measurement made it look**, and it means the case for folding rests on *a form
is a method that costs nothing at run time* being true, rather than on the
number. Which is where [ROADMAP.md](../../docs/ROADMAP.md) had already put it,
for a different reason.

### 2, restated the way the program actually found it

The dialect's `/` **rounds to the nearest hundredth**, which is right for
splitting a bill four ways and wrong for taking a number apart. Turning `-1225`
into `-12.25` needs the *floored* whole part and remainder, so `format` writes:

```
v:div(#100):asString:concat("."):concat(pad2:value(v:mod(#100)))
```

— `div` and `mod` as **sends**, with a comment saying why, which is precisely
what `programs/digest` does with `shift:sub(#8)` and for a structurally
identical reason. **Two programs, two domains, same shape: the dialect is
correct for the domain and wrong for the code that presents it.** That is the
second instance the roadmap wanted.

It differs in one way worth recording. digest's trap was `+`, and predictable
from the mask. This one was predicted on `*` and landed on `/`. **Which operator
turns traitor is a property of the domain and cannot be guessed from outside
it** — so the entry should not promise that a dialect's danger is findable by
inspection.

### 5, and the part the oracle exposed

`ratio interest to subtotal` answers `0.07`. The exact value is
`0.07499537750385208…`, and two places cannot hold it.

Nothing is wrong: the dialect has one precision, amounts want two places, and a
rate wants four or five. **This is the domain-boundary finding again, but inside
the domain rather than at its edge** — not *the dialect is wrong for the
scaffolding*, but *the dialect's own constant is wrong for another quantity in
the same domain*. A ledger has amounts and rates; one `scale` serves one of
them.

### What nobody predicted

**`#-1225` is not a literal in Proto, and is one in Solveig.** Solveig's grammar
says so plainly:

```ebnf
integer = "#" [ "-" ] digit { digit }
        | "$" hexdigit { hexdigit }
        | "%" bindigit { bindigit } .
```

Proto implements the first, without the sign, and neither of the other two.
`#-5` compiles in Solveig and is an error here; `$FF08` and `%1011` are
integers there and nothing here. [GRAMMAR.md](../../docs/GRAMMAR.md) says
everything but `operator` is Solveig's own spelling, *so that a file can be read
by somebody who knows Solveig without a second set of habits* — and for integers
that is not true.

**A ledger is the first program here with ordinary negative values.** A hash has
none, an assembler none, a parser none. Four programs is what it took.

**And it reached back and bit the third one.** `programs/digest` writes the
SHA-256 round constants as `#1116352408, #1899447441, …`. FIPS 180-4 prints them
as `428a2f98, 71374491, …`, and Solveig would have taken `$428a2f98` unchanged.
Sixty-four constants converted by hand, in the program whose first prediction
was *the formulas will transcribe*. They did. The constants did not, and nobody
noticed because nobody tried.

**One spelling may be both infix and prefix.** `@infix - 60 sub.` beside
`@prefix - negated.` is legal and reads correctly — `#10 - -#5` is
`#10:sub(#5:negated)` — because the two tables are separate and position
decides. Nothing in the repository had done it; `lib/arith.pro` uses `!` for the
prefix and `-` for the infix, so the case never arose.

### What did not come up

Hygiene, `@use` resolution, the map, and the collision rules: nothing, from a
fourth program. The collision rules could not come up — `money.pro` is
standalone for digest's reason, which this program confirms rather than extends:
`@use "arith.pro"` after it silently buys integer `*` in place of fixed-point
`*`, and a ledger that multiplies wrongly still runs.

**Hygiene has now not been mentioned by four programs in a row.** It went in
with forms in 0.2.0 rather than after, on the argument that a system which
expands without it grows programs that depend on the capture. Four programs
never noticing is what that argument predicted, and is the only evidence it
could ever have.
