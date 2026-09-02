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

*Written after the program, not before. Nothing here yet — the file above this
line is the whole of what was known when it was committed.*
