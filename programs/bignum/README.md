# Arbitrary-precision integers, written in Parasol

**Predictions recorded before the program was written.** That is
[conventions.md](../../docs/conventions.md)'s rule, and this file is committed
before a line of `bignum.psol` exists so that the ordering is in the history
rather than in a claim. `bignum.expected` goes in with it: every answer in it
was produced by `bc`, and none by this program.

```
programs/bignum/bignum.psol  --parasol-->  build/programs/bignum/bignum.sol   the library, in limbs.psol
programs/bignum/calc.psol    --parasol-->  build/programs/bignum/calc.sol     the driver, in lib/arith.psol
                                        @include "bignum.sol"
                            --solas-->  build/programs/bignum/calc.sob
```

Both generated files land in the one directory under `build/`, which is where
an `@include` looks first; `make bignum` builds and runs it.

## Why this one

The seventh program, and the first in **two modules that disagree about what
their operators mean.**

Every program so far is one code module and one dialect file. None has two code
modules whose headers declare `+` differently and then call each other, and
that is the design's own answer to the one roadmap entry with no proposal
against it: *a dialect ends at its domain and cannot say where.*
`examples/vectors.psol` promises that *a second file in the same program may
declare `+` to mean something else, and neither file has to know.* Nothing has
collected on that promise.

A bignum is the natural case. Inside the library, arithmetic is on **limbs**:
integers below a base, with a digit and a carry taken off every sum and product.
Outside it, in the driver, arithmetic is on the numbers themselves, and the loop
counters around them are ordinary integers. The two meet at a call, which is
where the roadmap's silence would either show itself or turn out to be a module
boundary.

It reaches three open items at once:

- **The domain boundary.** If a module boundary is where a dialect ends, the
  entry gets its first proposal without a type system.
- **Constant folding's third customer.** Schoolbook multiplication is a hot
  loop with the base inside it, which is `digest`'s shape and not `ledger`'s.
  The entry moves either way: to a decision, or to a third customer declining.
- **The map across modules.** The library reaches the driver as a *generated*
  `.sol` under `@include`, so an error in it asks which source file the map
  should name. Nothing has had to answer that.

And one question from outside Parasol. Solveig's `ideas.md` records a want for *a
large-number-math library* as one of the reasons its extensions load with
`dlopen`, and this is the first program to find out whether such a library is
an extension at all. An extension is for a capability the machine does not have
and could not reasonably grow, a window or a socket; a bignum is arithmetic on
arrays, which the machine has. **Whether it wants C is a question about speed
and nothing else**, and speed is measured here rather than argued.

## What was predicted before it was written

| | |
| --- | --- |
| **1. The dialect has nothing to invent, and it is the first value domain whose operators are all plain messages.** | `sha2.psol` invented a rule, `+` masked to 2³², and `money.psol` invented one, `*` scaled back down. A limb dialect needs neither: a limb is an ordinary integer below the base, `+` on two of them is Solveig's `add`, and the rule of the domain, *take the digit and carry the rest*, is two forms applied after the arithmetic rather than a template wrapped around it. Predicted: `limbs.psol` declares `base`, `digit(t)` and `carry(t)` and uses `lib/control.psol` unchanged, and **no operator in it is a template.** [does-it-pay.md](../../docs/does-it-pay.md) says the invented kind is the only evidence that a declared grammar does something a fixed one cannot; this program is predicted to be the case where there is nothing to invent, and to pay accordingly less. |
| **2. `lib/arith.psol` serves the driver unchanged, for integers and bignums alike, because `+` names a message and messages dispatch.** | The driver writes `a + b` on two bignums and `i + #1` on a counter with one declaration behind both, `@infix + 60 add.`, since a bignum that answers `add` is added and an integer that answers it is added. Predicted: **the boundary the roadmap could not draw does not arise**, because the domain lives in the object rather than in the header. What traps the scaffolding in `digest` and `ledger` is precisely what those dialects *invented*: a template bakes one domain into one spelling, and dispatch cannot reach into a template. **The operators that pay are the operators that trap**, and this program is predicted to have neither. |
| **3. Folding gets no third customer.** | `base` is a form, so every use of it expands to a literal, and nothing in the loop is *derived* from it: `digit(t)` is `t:mod(#1000000000)` and `carry(t)` is `t:div(#1000000000)`. `ledger` had `scale:div(#2)` because round-half-up wants half a unit; integer arithmetic wants nothing but the base itself. Predicted: **no unfolded constant anywhere in the program**, and the folding entry moves by a customer declining rather than by a measurement. |
| **4. The overflow trap chooses the base, and it is the one place the substrate shapes the program.** | Solveig has one integer, signed 64-bit, trapping on overflow. A limb product plus a limb plus a carry must fit, so the base is the largest power of ten whose square does: 10⁹. Binary limbs would want 2³¹, with a conversion loop to print. Predicted: base 10⁹, chosen so that printing is `join` and reading is `copyFrom`, and the oracle can compare text. And predicted that **nothing in Python's `math` module is missing for this program**: what a bignum wants and Solveig lacks is not a function but a wider product, `mul` answering 128 bits, which no scripting language's integers offer either. |
| **5. `@include` of a generated file works unchanged, and an error in it names the generated file, whose map is beside it.** | Parasol passes `@include` through as a statement, and Solveig resolves it beside the includer, so `calc.sol` includes `bignum.sol` and `solas` compiles both into one chunk. Predicted: an error in the library is reported at `bignum.sol:N`, `bignum.sol.map` takes N back to `bignum.psol`, and no change to Parasol is needed. What is new is the **build**: `calc.sol` depends on `bignum.sol` and the Makefile has never had to order two Parasol modules. Predicted to be one dependency line. |
| **6. It is a library and not an extension, and the number says so.** | Correct in the language, with nothing missing from the machine. Predicted: `1000!` computes in under a second, the hot loop's cost is the `at` and `atPut` sends rather than the arithmetic, and Solveig runs the multiplication **within two orders of magnitude of CPython's built-in `int`** on the same product. If that holds, a bignum belongs in `lib/` as Solveig source and the case for a C extension is nil; if it does not, the case for one is the ratio and nothing more. |

## How it is checked

`make test` runs `calc.sob` and diffs its output against `bignum.expected`. Every
line in that file was printed by `bc` before this program existed, including
the one that says how many digits `1000!` has, which is the largest number the
program computes and the one it does not print in full. A program that verifies
itself verifies nothing.

The measurement in prediction 6 is by binary search on `solvm --steps`, the
method `digest` and `ledger` used, and by wall clock against `python3` for the
same `1000!`.

## What it found

Written after. The predictions above were committed in `3ba0380`, before a
line of `bignum.psol` existed. The program compiled clean the first time, and
its first run agreed with `bc` on every line.

### The predictions

| | |
| --- | --- |
| **1. The dialect has nothing to invent** | **Right.** `limbs.psol` is five lines: `base`, `width`, `digit(t)`, `carry(t)` and a `@use` of `lib/control.psol`. No operator in either module is a template. It is the first value domain here with nothing invented, and the first whose dialect collides with nothing. |
| **2. `lib/arith.psol` serves both, because messages dispatch** | **Right, and it reaches further than predicted.** One `@infix + 60 add.` adds two bignums in `fibonacci` and two limbs in `big:add`. Inside `bignum.psol` itself, `result * b` in `pow` is a bignum product and `ai * b:at(j)` in `mul` is an integer one, under the same declaration in the same file. The two-module split was designed to find where a dialect ends, and the answer is that **this dialect does not end anywhere**: both modules could have shared one header without a collision. Mixing the types fails loudly in both directions, `'add' expects integer, got object` one way and `integer does not understand 'limbs'` the other. |
| **3. Folding gets no third customer** | **Right.** No send in either generated file has two literal operands. `rem * base` expands to `rem:mul(#1000000000)`, which has a name in it and nothing a folder could reach. |
| **4. The overflow trap chooses the base** | **Right.** Base 10⁹, and the inequality that fixes it is the comment on `big:mul`. Nothing in Python's `math` module was wanted; what was wanted was a wider product, which no scripting language's integers offer either. Python's own `int` keeps 30-bit digits in C for the same reason this file keeps nine decimal ones. |
| **5. `@include` of a generated file works, and an error names it** | **Right.** A message misspelled in the library's copy under a scratch directory reported `[bignum.sol:27] in block` over `[calc.sol:16] in block`, one frame per generated file, and each file's map beside it took the line back: `bignum.sol:27` to `bignum.psol:55`, `calc.sol:16` to `calc.psol:51`. Parasol was not changed. The Makefile gained the three rules every program has and one extra prerequisite, `calc.sob` depending on `bignum.sol` as well as `calc.sol`. |
| **6. A library and not an extension, and the number says so** | **Right about the kind, wrong about the number.** `1000!` takes 40 ms at `-O2` and 190 ms at the default `-g` build; CPython's `int` takes 0.24 ms for the same product. That is **170×**, not two orders of magnitude, and the claim about where the cost sits was wrong too. See below. |

### 6, measured

| | instructions |
| --- | ---: |
| `1000!`, 999 multiplications by one limb | 11,291,573 |
| one product of two 100-limb numbers | 444,565 |
| per limb product, the inner loop | **44** |

Forty-four instructions per limb product, by binary search on `--steps`, and
the disassembly says what they are: fifteen sends, of which four touch the
array (`at` twice, `atPut`, `size`) and **eleven are arithmetic**. Four of the
eleven are `i + j - #1`, computed twice, once to read and once to write; two are
`digit` and `carry`; the rest are the product, the two additions, the counter
and its test. **The one-based index costs as much as the array access it
indexes**, which is not what prediction 6 said the cost was.

| `1000!`, five runs averaged | seconds |
| --- | ---: |
| Solveig, `-O2` | 0.040 |
| Solveig, default `-g` build | 0.19 |
| CPython 3 `int` | 0.00024 |

So the answer to the question from outside Parasol is in two halves. **A
large-number library is a library**: this one is correct with nothing missing
from the machine, it is 126 lines of generated Solveig that `@include` reaches,
and a program that wanted it in Solveig's `lib/` would have it by copying a
file. **The case for a C extension is the ratio and nothing else**: 170× is
real, and it is also 40 ms, and no program here has waited for it. An
extension in the shape of `extensions/net`, a global `big` holding primitives,
is what that ratio would buy when a program is measured waiting, and not
before.

### What the two modules actually found

The roadmap entry this was written against says *a dialect ends at its domain
and cannot say where*, and it had two programs behind it: `digest`'s `+` masked
to 2³² and `ledger`'s `*` scaled back down, each right for its domain and a trap
for the loop counter beside it. This program has the same shape, a domain with
scaffolding around it, and **no trap**, and the difference is not the module
boundary. It is what the domain's values are.

A limb is a Solveig integer. A bignum is an object. `+` on the first is the
integer's `add`, and `+` on the second is `big:add`, and the header did not
have to know which because the receiver knows. `digest` and `ledger` could not
do that: a 32-bit word and an amount of money are *also* Solveig integers, so
the only place their rule could live was a template on the spelling, and a
template cannot look at its receiver. That is the whole mechanism:

> **A template bakes a domain into a spelling. Dispatch reads the domain off
> the receiver. A dialect traps its scaffolding exactly when its domain's
> values are the substrate's own, because then the spelling is the only place
> the rule can go.**

`basic` found that a program can contain a domain without being one, because
its domain arrives with the input. This is the other half: a program can *be*
a domain without needing a dialect for it, because its domain is an object.
The dialects that pay, the invented ones [does-it-pay.md](../../docs/does-it-pay.md)
counts as the only evidence, are the ones that trap, and for one reason.

### What nobody predicted

**A run-time trace names a line, and a generated line is a span.** Parasol emits
the body of a `while` on one line, so `bignum.sol:27` is source lines 54 to
57 and the map, which is exact to the column, cannot narrow a report that has
no column. Sixteen of the library's 103 generated lines carry more than one
line of the module, every one a loop body or an `if`. A four-line span is a
recovery, and it is not the exact one the map was built to give. Two fixes,
neither built: Parasol could keep a source line break inside an expanded hole,
or Solveig's trace could carry a column the way its compile errors already
do. [ROADMAP.md](../../docs/ROADMAP.md) has the row, and
[solveig-notes.md](../../docs/solveig-notes.md) the second half.

**`n(#2)` had to be a form.** In Solveig, `f(x)` on a name is `x:f`, so a block
called that way is a message the integer does not understand. Two characters in
a header, and the reason is in the comment, but it is a spelling a reader of C
or Python will write first.

**Nothing in Solveig bit.** Objects with slots assigned after `object:new`,
`error:raise` in a method, `fill` asking an object for `asString`, arrays of
arrays: the seventh program is the third in a row to record that the substrate
did not surprise it. The count is worth keeping because `ember` predicted the
opposite and was wrong.

### What did not come up

Hygiene, the collision rules, `@use` resolution: nothing, from a seventh
program, and the collision rules could not, this being the first domain dialect
with nothing to collide. Optional and repeated parts were not wanted. A hole's
kind was not needed. Division of one bignum by another was not written, because
nothing asked for it, and it is the first thing a second customer would.
