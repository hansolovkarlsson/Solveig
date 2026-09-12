# A BASIC interpreter, written in Proto

```
programs/basic/basic.pro  --proto-->  basic.sol
                          --solas-->  basic.sob
examples/fizzbuzz.bas     --solvm-->  the output
```

```sh
make basic
solvm programs/basic/basic.sob programs/basic/examples/primes.bas
solvm programs/basic/basic.sob                    # no file: a prompt
```

Line numbers, `LET`, `PRINT`, `INPUT`, `IF`/`THEN`, `GOTO`, `GOSUB`/`RETURN`,
`FOR`/`NEXT`/`STEP`, `END` and `REM`. At the prompt, `RUN`, `LIST`, `BYE`, and
a numbered line replaces the line with that number.

**This is not a Proto feature.** It is a program written in Proto, and the
`.bas` files are data it reads while it runs — no header anywhere has an
opinion about them. [docs/targets.md](../../docs/targets.md) separates the two
questions and this is the one it left without a program.

**Predictions recorded before the program was written.** That is
[conventions.md](../../docs/conventions.md)'s rule, and this file is committed
before a line of `basic.pro` exists so that the ordering is in the history
rather than in a claim.

## Why this one

The sixth program, and the first that is not a pass over its input.

**Every program here so far runs once and stops.** `ember` turns source into
assembly, `grammar` turns text into a tree, `digest` turns bytes into a digest,
`ledger` turns transactions into a report, `prose` turns a document into text.
Each walks its input from one end to the other, and the order it walks in is the
order the input is written in.

An interpreter is not that. It has a **program counter that can go backwards**,
an environment that outlives every statement, and statements that run a number
of times the source does not say. [does-it-pay.md](../../docs/does-it-pay.md)
weighs five programs — five, on the day this was written — and closes on what is
still unknown; a run-time state machine is not on that list, because until now
nothing here had one.

**And it is the first program with two domains in one file.** does-it-pay's one
general finding is that

> A domain of steps wants forms. A domain of values wants operators.

Five programs arrived at that independently and every one of them is on one side
of it — `ember`, `grammar` and `prose` declare no operators at all, `digest` and
`ledger` declare mostly operators. An interpreter has both at once: the dispatch
over statement kinds is a domain of steps, and BASIC's own values — a number or
a string, with `+` meaning two different things — are a domain of values. **The
rule has never been asked to hold twice inside one dialect.**

**It is also the half of [targets.md](../../docs/targets.md) that was never
written.** That page answered a question about a BASIC *compiler* in 2026-08-31
and answered it in the abstract, because no such program existed. The
interpreter is the cheaper half of the same question and settles the same
confusion with something that runs.

## What was predicted before it was written

| | |
| --- | --- |
| **1. The dispatch cannot be notation, and this is `grammar`'s wall one level over.** | `programs/grammar` found that a template cannot declare a form, so a grammar's rules stop being notation and **become data**. An interpreter's core is *given a statement kind, run the right code*, and the prediction is that it stays a chain of `if kind == 'let then …` exactly as `ember`'s `genStmt` is, with no form removing a line of it. The reason, predicted in advance: **notation is chosen when the program is written and a dispatch is chosen when it runs.** If that is right it is the sharpest statement of the ceiling yet, because it names *why* rather than *where*. |
| **2. The value dialect will be declined, not worked around — and that is new.** | `digest` and `ledger` both declared an operator that was right for the domain and a trap beside it, and both **worked around it with a send and a comment**. BASIC's `+` is add-or-concat, which is exactly an operator's job; the interpreter's own `+` counts a program counter, a token index and an array index. Predicted: the traps outnumber the uses so heavily that `+` is **never declared at all**, and the domain boundary kills the dialect instead of being papered over inside it. **A third instance of a known finding, in a shape neither of the first two had.** |
| **3. So the dialect declares forms and no operators.** | Follows from 2, and puts this program on `ember`'s side of the split. Predicted count: seven or eight forms, no operators — which would make it the fourth of six programs to declare none, against a taxonomy that says a program with a value domain should want them. **The prediction is that the taxonomy is right about the domain and wrong about the program**, because a program can contain a domain without being one. |
| **4. `<=` and `>=` get their second customer, and it is the interpreter rather than BASIC.** | [ROADMAP.md](../../docs/ROADMAP.md) has `lib/arith.pro` missing `<=`, `>=` and `!=` with one customer — `programs/prose`, which writes `while i < doc:size + #1`. Predicted: this program wants them too, in bounds checks and in the `FOR` loop's limit test, and **not** for BASIC's own `<=`, which is a token the lexer reads and has nothing to do with any module's header. Two customers settles a live entry; that the second one wants it for a different reason than expected is the part worth recording. |
| **5. A REPL costs one block, and the reason is BASIC's and not Proto's.** | `system:readLine` and the same parse-one-line path give an interactive mode with no second parser, because a line-numbered BASIC **has no construct that spans lines** — `FOR` and `NEXT` are two statements, not a bracket. Predicted: the file driver and the prompt driver differ by their loop and nothing else, and **this is a property of the interpreted language rather than a thing Proto did**, which is precisely the sort of credit that lands on the wrong layer if nobody writes it down first. |
| **6. Proto helps with less of this than it looks.** | [rules-and-logic.md](../../docs/rules-and-logic.md) says exactly this about a Prolog dialect and it should be said here too. The hard parts of an interpreter are the environment, the return stack and the value model, and **not one of the three is notation.** Predicted: the dialect covers the leaves — reading a token, storing a variable, jumping — and the three hard parts are ordinary Proto with no notation over them, in the proportion `ledger` found, where three of its functions were formatting and none of the three was money. |

## How it is checked

`make test` runs `fizzbuzz.bas`, `primes.bas` and `greet.bas` — the last fed a
fixed `Ada` and `36` on standard input, so `INPUT` is checked and the run is
still deterministic — and diffs the three against `basic.expected`.

The expected output is worked out by hand from the BASIC source and not
captured from a run, which is the discipline `programs/digest` and
`programs/ledger` both use: **a program that verifies itself verifies
nothing.**

## What it found

Written after. The predictions above were committed in `92be288`, before a line
of `basic.pro` existed.

### The predictions

| | |
| --- | --- |
| **1. The dispatch cannot be notation** | **Right, and it turned out to be the larger half of a finding rather than a finding.** `exec` is ten comparisons on a symbol and a fallthrough, and not one form in `interp.pro` removes a line of it. But the reason predicted for it — *notation is chosen when the program is written and a dispatch is chosen when it runs* — covers prediction 2 as well, which was not expected, and the two are one thing. See below. |
| **2. The value dialect will be declined, not worked around** | **Right about the outcome and wrong about the reason, and the real reason is worth more.** Predicted: `+` goes undeclared because the interpreter's own counting outnumbers BASIC's adding. Actual: **there is nothing to declare it for.** The interpreter never writes `a + b` on two BASIC values anywhere — it writes `binop:value(op, a, b)`, where `op` is a *string that came from the input*, and each branch of `binop` is a send that already knows its operation. Two `+` survive in 251 lines and both are `pc + #1`. So this is **not** a third instance of the domain-boundary finding; it is a different finding wearing its clothes. |
| **3. Forms and no operators** | **Right about the shape, wrong about the number, by half.** Predicted seven or eight; there are **fifteen**, used ninety-three times. Zero operators, which makes this the fourth of six programs to declare none. The taxonomy is right about the domain and wrong about the program, as predicted — a program can contain a domain without being one. |
| **4. `<=` and `>=` get their second customer, and it is the interpreter** | **Right, in both halves, and the entry was taken the same day.** Five uses of `<=` and `>=`, every one of them the interpreter's own bounds test — the `FOR` limit and `pc <= program:size` — and four of `!=`. BASIC's own `<=` is a two-character token `twoCharOp` reads at run time and is never an operator this module declares. The count came out **two customers for `<=` and one each for `>=` and `!=`**, so the bar was met for one of three; the family went in whole, because an arith with `<=` and no `>=` is a worse trap than an arith with neither. **A customer count is per surface, and a comparison set is one surface** — which is the thing this case decided that nothing had had to decide before. This program was rewritten to use them the day they landed, and so was `programs/prose`. |
| **5. A REPL costs one block** | **Right, and the credit goes where it was predicted to go.** The file driver and the prompt driver differ by their loop and share every other line. It is BASIC's doing: nothing in the language spans a line, so `addLine` is the whole of both. |
| **6. Proto helps with less of this than it looks** | **Right.** Sixteen lines of dialect against 251 of program. The forms cover the lexer's character tests, the parser's cursor and the three moves on the counter. They touch **none** of the environment, the return stack or the value model, which are the three things that make this an interpreter. |

### 1 and 2 are one finding, and it is the sharpest statement of the ceiling yet

`programs/grammar` found that a template cannot declare a form, so a grammar's
rules stop being notation and **become data**. That was read as a limit on
*recursion*. It is not. This program hits the same wall with no recursion in
sight, twice, on both halves of Proto at once:

| what the interpreter wants to write | why it cannot |
| --- | --- |
| a **form** per statement kind | which kind it is arrives with the input |
| an **operator** for BASIC's `+` | which operator it is arrives with the input |

> **Notation is fixed when a file is read. An interpreter's every decision is
> made after that.**

Which makes an interpreter the program that can use the least notation of any
here, and for one reason rather than two. `binop` is the case to look at: BASIC
genuinely has a domain of values, `+` genuinely means add-or-concat, and
`digest`'s and `ledger`'s dialects are exactly what that asks for — and **an
operator has nothing to attach to**, because the operator being applied is a
string in a table and not a token in a file.

**This is why the two-domain question in *Why this one* has no answer.** The
rule that a domain of steps wants forms and a domain of values wants operators
was never asked to hold twice inside one dialect, because the value domain
never reached the dialect at all. It is in the interpreted language, one level
down, where no header can see it.

### The dialect took the counter arithmetic with it

Not predicted, and the clearest thing the forms bought. `fallThrough`, `step`
and `jump to` are the only places a counter moves, and each is one word:

| | in basic.pro |
| --- | ---: |
| `+` on the interpreter's own integers | **2** |
| both of them | `pc + #1`, saving a return address |

*(Counted before `<=`, `>=` and `!=` reached `lib/arith.pro` on the strength of
this program; the comparison sends became operators the same day and the `+`
count did not move.)*

Every other increment in a 251-line interpreter is inside a template.

**It is not `digest`'s finding, and the difference is worth keeping.** `sha2.pro`
makes forgetting a mask *impossible*, because `+` is the only way to spell
addition and the mask is inside it. Nothing stops this program writing
`pc := pc + #2` by hand: `fallThrough` is a **name for a step**, not a rule
that cannot be broken. The saving is locality — three ways for a counter to
move, each in one place, each one word — and it is the ordinary kind of win
that `ember` and `grammar` reported. The one clear instance of a dialect
carrying an *invented* rule is still `digest`'s, and it is still one in six
programs.

### A form's word and a message selector do not collide

`interp.pro` declares `@syntax step => tp := tp + #1.` and `basic.pro` sends
`s:step` to a `scan` cursor six times in the lexer. Both are right, and the
generated source shows it — `tp := tp:add(#1)` where the word stands alone,
`s:step` where it follows a colon.

A selector is never in primary position, so the matcher never looks there.
Nothing in the repository had tested it, and the README's rule that *a word in
a pattern is not reserved anywhere else* was written about **variables**. It
holds for selectors too, and now something depends on it.

### The first program that depended on hygiene

Five programs in a row never mentioned it. This one needed it and still did not
notice.

`take`'s template is `{ | t | … }:value`. `parseAtom` is `{ | t, n | … }` and
its body says `t := take`. The generated source is:

```
t := { | t__5 | t__5 := toks:at(tp). tp := tp:add(#1). t__5 }:value.
```

The template's temporary is renamed and the parser keeps its own `t`. Without
hygiene that expands to `t := { | t | … }:value` and the parser loses the token
it just read, four lines before it reads `t:kind`.

**Nobody noticed while writing it**, which is exactly what the argument for
putting hygiene in with forms in 0.2.0 rather than after predicted — and, being
a thing that does not happen, the only evidence that argument could ever have.

### What did not come up

The collision rules, `@use` resolution and the map: nothing, from a sixth
program. The collision rules could not — `interp.pro` is this program's and
nothing else uses it.

Optional and repeated parts were **declined a third time.** BASIC's `PRINT a, b,
c` is a repetition and a `STEP` clause is an optional part, and both are in the
*interpreted* language: they are `while opIs(",") do …` and `if wordIs("STEP")`
in an ordinary parser. No Proto feature would have removed either, for the same
reason `programs/grammar` gave — the repetition wanted is in the object language
and not in Proto.
