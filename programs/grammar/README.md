# A grammar toolkit, written in Phoenix

Grammars written down and then run, in the manner of yacc — a rule is a
declaration, and parsing is what the declarations do.

**Not a Phoenix feature.** A second program, written for the reason the first
one was: `docs/rules-and-logic.md` lists it as the last step and says why.

> **A parser toolkit written in Phoenix.** Not a feature. The best test of
> whether any of the above was worth having.

Solveig's own `docs/ideas.md` wants one too, and calls it *the most interesting
of these*. It is the on-the-nose test: a grammar notation, written in a language
whose entire claim is that notation can be declared. If patterns, typed holes
and operator templates do not help **here**, they do not help.

## Why this one and not another code generator

`programs/ember` pressed on notation for a flat domain — instructions in a list.
This presses on the two things nothing has asked for yet, so that the roadmap
stops guessing about them:

| | |
| --- | --- |
| **Repetition** | `sum = term { ("+" \| "-") term }` is EBNF's own shape. A pattern has no repeated part, and this is the program that would want one. |
| **Alternation** | `expr = a \| b`, and a hole that accepts one of several kinds. `lib/clike.phx` wanted the second and worked around it. |

Both are on the roadmap with **no customer**. After this they will have one or
they will have been declined twice.

## What was predicted before it was written

| | |
| --- | --- |
| **1. A grammar is recursive and forms are not.** | A template may mention only forms declared above it, so `expr` cannot refer to a rule defined below it. `programs/ember`'s README recorded *notation is not recursive even when the program using it is* and marked it "did not bite". **A grammar is the counterexample**, and this is predicted to be the sharpest finding here. |
| **2. Repetition will be wanted within an hour.** | And the workaround will be an explicit loop, which is what the notation existed to remove. |
| **3. Solveig's 3.1 will bite this time.** | A combinator is a block that outlives the frame it was written in, which `lib/scan.sol` says is refused. Predicted: the toolkit is pushed to a non-combinator design, exactly as `scan.sol` was, and that is the answer rather than the defeat. |
| **4. Rules will be keyed by symbol, not by name.** | A template cannot build a selector out of a hole, so `rule <n: name>` cannot become `parser:<n>`. Predicted spelling: `rule 'sum is { ... }`, a literal, with a table doing what recursion cannot. |
| **5. The notation will be worth less here than in ember.** | An assembler is a hundred one-line statements and notation pays per line. A grammar is a dozen rules. Predicted: the win is smaller and the finding is about *where* a dialect pays. |

Predicted **not** to find: anything wrong with hygiene, `@use`, or the map.
Three programs' worth of use and no complaint from any of them.

## What it found

Two grammars run: `examples/calc.phx` evaluates `100 / 5 - 3 * 4` with
precedence, and `examples/sexpr.phx` parses `(a (b c) d)` into nested arrays.
`make test` diffs both.

### The predictions

| | |
| --- | --- |
| **1. A grammar is recursive and forms are not** | **Right, and sharper than predicted.** It is not that a rule cannot mention a later rule — it is that **a rule cannot be a form at all.** A template cannot declare a form, so `rule 'expr is { … }` can only put a block in a table, and `apply 'term` is a lookup. Ember's README said *notation is not recursive even when the program using it is*; a grammar is the counterexample, and the answer is that the recursive part stops being notation and becomes data. |
| **2. Repetition wanted within an hour** | **Right about the want, wrong about the level.** Both grammars have `{ … }:whileTrue({ … })` where EBNF writes `{ }`. But a *repeated pattern part in Phoenix would not have helped*, because the grammar is data and not forms — the repetition wanted is in the object language. **The feature is declined a second time, and now with a reason rather than a shrug.** |
| **3. Solveig's 3.1 will bite** | **Right, and it cost nothing because it was predicted.** `makeAdder := { n \| { x \| x:add(n) } }` is refused — *block outlived the frame it was written in* — so combinators are out and the rules live in a table, exactly as `lib/scan.sol` was pushed. Confirmed in four lines before the toolkit existed. |
| **4. Rules keyed by symbol** | **Right.** `rule 'expr is { … }`, because a template cannot build a selector out of a hole. |
| **5. The notation is worth less here** | **Right, and it is the useful one.** Ember has ~15 forms over ~200 lines of assembly emission; this has 8 over ~30 lines of grammar. **A dialect pays per line it removes**, so notation for a flat repetitive domain earns more than notation for a small structured one — and the second still reads better, it just saves less. |

### The one that was not predicted

**A form's trailing hole swallows infix operators, not only postfix sends.**

```
at "*" \/ at "/"        ; is  at ("*" \/ (at "/"))
```

Ember found that `emit(A):add(B)` puts the `:add` inside the hole. This is the
same rule reaching further: a hole takes an *expression*, and an infix operator
continues one, so **nothing written after a form can ever apply to the form's
result.** Both grammars are full of parentheses that exist only for this.

The shape of a fix, recorded rather than built: a prefix operator's operand is
parsed by `unary` and not by `expression`, which is why `~a + b` is `(~a) + b`.
A form's trailing hole could bind the same way — but `unless x then y + z`
plainly wants the whole sum, so it cannot be one rule for every form. **It would
have to be declared**, and that is a design question rather than a fix.

### And one about typed holes

`skip <cls: literal>` was typed that way because every use in the author's head
was `skip " \t\n"`. The first real grammar wrote `skip blank`, naming a string
it had bound, and was refused by its own toolkit.

**A kind is a promise extracted from the caller, not a description of the
author's examples.** Only `<b: block>` survived in `peg.phx`, because the table
stores a block and anything else would store a value. The other five were the
author guessing.
