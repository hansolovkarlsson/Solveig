# A document, written in Proto

**Predictions recorded before the program was written.** That is
[conventions.md](../../docs/conventions.md)'s rule, and this file is committed
before a line of the program exists so the ordering is in the history rather
than in a claim.

## Why this one

[does-it-pay.md](../../docs/does-it-pay.md) weighs four programs and ends with
the one thing none of them tested:

> Every one of the four is arithmetic or instructions. An assembler, a parser, a
> hash and a ledger: two domains of steps, two of values, and all four
> computational through and through. Nothing here has tested a domain that is
> neither.

This is that domain. A small document language — headings, paragraphs, lists,
quotes — with the document itself written in the dialect and rendered to plain
text.

**And it is the answerable half of a question that was asked the wrong way
round.** *Can Proto take prose, a poem, a story?* — not as its body, no: a
`.pro` becomes Solveig sends, and a poem has no such translation. But a program
written in Proto can process anything, and a dialect can be shaped so that
**the document is the program**. Whether that reads as a document, and whether
it earns its notation, is a question with an answer.

## What is new about it

In all four previous programs the dialect helped write the **processing**.
`asm.pro` made the emitter readable; `sha2.pro` made the formulas transcribable.
Here the dialect is used to write the **data** — the document is written in it,
and the code that renders the document uses no notation at all.

That is the sharpest available test of *a dialect pays per line it removes*,
because a document is nearly all lines and nearly no logic.

## What was predicted before it was written

| | |
| --- | --- |
| **1. The dialect writes the data, and that is the finding.** | Four programs used a dialect to make their *code* readable. Predicted: pointing it at content instead is where per-line payment is most visible, because there is no logic to dilute it — and predicted to be worth recording whichever way the number goes. |
| **2. The trailing hole will not bite, and for a reason worth stating.** | `programs/ember` and `programs/grammar` both declared an application as a pattern and had its trailing hole swallow what followed. Predicted **not** to happen here: every content form ends in a literal and answers nothing, so a pattern is the right shape by [GRAMMAR.md](../../docs/GRAMMAR.md)'s own test — *a pattern if it is a step, a call if its answer is used*. Content lines are steps. Predicted: the rule that caught two programs is easy to follow once the domain makes the answer obvious. |
| **3. Nesting is the wall, and it is `grammar`'s ceiling in a new place.** | A document has structure — a list inside a section, emphasis inside a sentence. A form is one expression and cannot contain content. Predicted: the flat lines get notation and the structure becomes data, exactly as *a rule cannot be a form* pushed a grammar's rules into a table. Predicted to be the clearest instance of the ceiling yet, because a document is *visibly* a tree and the notation will only reach its leaves. |
| **4. It will read closer to a document than sends do, and still read as a program.** | Every line ends in `.`, every string is quoted, and there is no way to have either otherwise. Predicted: the gap between *this looks like a document* and *this is a document* is the honest answer to the prose question, and it is a gap the notation narrows and cannot close. |
| **5. It will pay less than `digest` because the domain has no rule to carry.** | `digest`'s dialect enforced a correctness discipline — `+` *is* addition modulo 2³², and forgetting a mask stopped being possible. A document has no mistake of that kind to prevent. Predicted: this dialect saves typing and nothing else, like `ember`'s and `grammar`'s — and predicted to confirm that **carrying a rule is a property of the domain, not of dialects.** |

## How it is checked

`make test` runs it and diffs against `prose.expected`, which is written by hand
from the document rather than by running the renderer. A program that verifies
itself verifies nothing.

## What it found

*Written after the program, not before. Nothing here yet — the file above this
line is the whole of what was known when it was committed.*
