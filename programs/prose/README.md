# A document, written in Parasol

**Predictions recorded before the program was written.** That is
[conventions.md](../../parasol/docs/conventions.md)'s rule, and this file is committed
before a line of the program exists so the ordering is in the history rather
than in a claim.

## Why this one

[does-it-pay.md](../../parasol/docs/does-it-pay.md) weighs four programs and ends with
the one thing none of them tested:

> Every one of the four is arithmetic or instructions. An assembler, a parser, a
> hash and a ledger: two domains of steps, two of values, and all four
> computational through and through. Nothing here has tested a domain that is
> neither.

This is that domain. A small document language — headings, paragraphs, lists,
quotes — with the document itself written in the dialect and rendered to plain
text.

**And it is the answerable half of a question that was asked the wrong way
round.** *Can Parasol take prose, a poem, a story?* — not as its body, no: a
`.psol` becomes Solveig sends, and a poem has no such translation. But a program
written in Parasol can process anything, and a dialect can be shaped so that
**the document is the program**. Whether that reads as a document, and whether
it earns its notation, is a question with an answer.

## What is new about it

In all four previous programs the dialect helped write the **processing**.
`asm.psol` made the emitter readable; `sha2.psol` made the formulas transcribable.
Here the dialect is used to write the **data** — the document is written in it,
and the code that renders the document uses no notation at all.

That is the sharpest available test of *a dialect pays per line it removes*,
because a document is nearly all lines and nearly no logic.

## What was predicted before it was written

| | |
| --- | --- |
| **1. The dialect writes the data, and that is the finding.** | Four programs used a dialect to make their *code* readable. Predicted: pointing it at content instead is where per-line payment is most visible, because there is no logic to dilute it — and predicted to be worth recording whichever way the number goes. |
| **2. The trailing hole will not bite, and for a reason worth stating.** | `programs/ember` and `programs/grammar` both declared an application as a pattern and had its trailing hole swallow what followed. Predicted **not** to happen here: every content form ends in a literal and answers nothing, so a pattern is the right shape by [GRAMMAR.md](../../parasol/docs/GRAMMAR.md)'s own test — *a pattern if it is a step, a call if its answer is used*. Content lines are steps. Predicted: the rule that caught two programs is easy to follow once the domain makes the answer obvious. |
| **3. Nesting is the wall, and it is `grammar`'s ceiling in a new place.** | A document has structure — a list inside a section, emphasis inside a sentence. A form is one expression and cannot contain content. Predicted: the flat lines get notation and the structure becomes data, exactly as *a rule cannot be a form* pushed a grammar's rules into a table. Predicted to be the clearest instance of the ceiling yet, because a document is *visibly* a tree and the notation will only reach its leaves. |
| **4. It will read closer to a document than sends do, and still read as a program.** | Every line ends in `.`, every string is quoted, and there is no way to have either otherwise. Predicted: the gap between *this looks like a document* and *this is a document* is the honest answer to the prose question, and it is a gap the notation narrows and cannot close. |
| **5. It will pay less than `digest` because the domain has no rule to carry.** | `digest`'s dialect enforced a correctness discipline — `+` *is* addition modulo 2³², and forgetting a mask stopped being possible. A document has no mistake of that kind to prevent. Predicted: this dialect saves typing and nothing else, like `ember`'s and `grammar`'s — and predicted to confirm that **carrying a rule is a property of the domain, not of dialects.** |

## How it is checked

`make test` runs it and diffs against `prose.expected`, which is written by hand
from the document rather than by running the renderer. A program that verifies
itself verifies nothing.

## What it found

Written after. The predictions above were committed in `1ac24fb`, before a line
of the program existed.

### The predictions

| | |
| --- | --- |
| **1. The dialect writes the data** | **Right, and the number is the finding.** `note.psol` is **26 lines of document and 36 lines of renderer.** The dialect reaches 26 of 64 lines and none of the rest — the renderer is ordinary Parasol with no notation at all, exactly as intended. **Even in the most content-heavy program that could be written, the code is larger than the content.** |
| **2. The trailing hole will not bite** | **Right, and the reason held.** Every form ends in a literal and answers nothing, so the pattern shape was right by [GRAMMAR.md](../../parasol/docs/GRAMMAR.md)'s own test and the choice was never in question. **This is the first program where the domain made the shape obvious** — `ember` and `grammar` both got it wrong, and both had forms whose answers were used. |
| **3. Nesting is the wall** | **Wrong, and it is the best finding here.** A form cannot *contain* content, but it can take a **block**, and a block's statements are content forms. `indent { … }` nests to any depth — the document has a two-deep list to prove it — and the structure did not become data. **Solveig's braces carried it.** |
| **4. It reads closer to a document, and still reads as a program** | **Right, and the sharpest instance was not the punctuation.** Every line ends in `.` and every string is quoted, as expected. What was not expected is that **the document cannot wrap.** A paragraph is a string and a string is one line; breaking it wants `:concat(` in the middle of a sentence, and a literal newline changes the text. So `note.psol` is the only file in this repository that runs past eighty columns, and it does so in its content. |
| **5. It pays less than `digest`, having no rule to carry** | **Half right, and the wrong half is worth more.** |

### 3, which was wrong, and what the ceiling actually is

The prediction was `grammar`'s ceiling — *a rule cannot be a form*, so the
recursive part stops being notation and becomes data. It does not happen here.

```
indent {
    item "grammar, a parser: a rule cannot be a form".
    indent {
        item "so the recursive part stops being notation".
        item "and becomes data".
    }.
}.
```

**A form takes a block, a block holds statements, and statements are forms.**
So a document nests as deeply as it likes and the notation follows it down. What
`grammar` hit was narrower than *nesting*: a template cannot **declare** a form,
so a grammar's rules — which are definitions — could not be notation. A
document's structure is not definitions, and it goes through.

**The ceiling is one level lower than predicted, and it is real.** A form cannot
contain *part of a line*. Emphasis inside a sentence, a link in the middle of a
clause, a word in italics — a paragraph is one string, and there is no way to
say `para "text with " emph "this" " in it"` because a pattern's parts are words
and holes, not a sequence of alternating content. So:

> **A form can contain content. A form cannot contain half a line.**

Which is the honest answer to *could Parasol do a markup language*: the block
structure, yes; the inline structure, no, and not by any arrangement of forms.

### 5, and the two kinds of rule

The prediction said a document has no mistake to prevent, so this dialect would
save typing and nothing else, as `ember`'s and `grammar`'s did.

**It does prevent one.** `indent { … }` cannot be left unbalanced — the `in` and
the `out` are the two halves of one template, and a block that is never closed
is not a block. A markup that writes `<ul>` and `</ul>` by hand can drop the
second; this cannot.

**But it did not invent that rule. It borrowed one the host already enforces.**
And that is the distinction the program adds:

| | |
| --- | --- |
| **A rule the dialect invents** | `sha2.psol` declares `+` as addition modulo 2³². Nothing in Solveig enforces that; the dialect made it true, and after the header forgetting a mask is not a thing the program can do. |
| **A rule the dialect borrows** | `prose.psol` declares `indent <b: block>`. Balance is Solveig's — a brace must close — and the dialect only has to spend the hole. |

The borrowed one is free and the invented one is not, and **only the invented
one is evidence that a declared grammar can do something a fixed one cannot.**
So prediction 5 stands where it matters: this dialect pays like `ember`'s.

### What nobody predicted

**`lib/arith.psol` had no `<=`, and this program wanted one.** The renderer was
written as:

```
i := #1.
while i < doc:size + #1 do (
```

because `while i <= doc:size` did not compile. On the morning this program was
written, the question *should `lib/arith.psol` be completed?* was asked and
answered **no**, on the evidence that `<=`, `>=` and `!=` had *no customer at
all* — the two files declaring them were both standalone, and **every one of
arith's five users declared no operator of its own.**

That was true of the five. This was the sixth, and it was the customer.
**The conclusion was right about the evidence and wrong about the future**,
which is what *no customer yet* always means.

**Closed on 2026-09-02 by the second customer.** `programs/basic` wanted `<=`
and `>=` five times and `!=` four, and the family went into `lib/arith.psol`
whole. The renderer reads `while i <= doc:size` now. **A workaround that stayed
in place for one program and one day is the cheapest possible version of the
rule working** — the surface did not grow on this program's evidence alone, and
it grew the moment there was a second.

**And a document turned out to be a domain of steps.** It was picked as a domain
that was *neither* arithmetic nor instructions, to test whether
[does-it-pay.md](../../parasol/docs/does-it-pay.md)'s split — *steps want forms, values
want operators* — had a third case outside it. It does not. `prose.psol` declares
**no operators and seven forms**, which is `ember`'s and `grammar`'s shape
exactly. Each content line is a step that appends; the taxonomy absorbed the new
domain rather than being extended by it.

### What did not come up

Hygiene, the map, `@use` resolution, and the collision rules: nothing, from a
fifth program. **Hygiene has now gone unmentioned by five in a row**, which
remains the only evidence the 0.2.0 argument for shipping it early could ever
have.
