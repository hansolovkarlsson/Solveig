# Arbitrary-precision integers, written in Proto

**Predictions recorded before the program was written.** That is
[conventions.md](../../docs/conventions.md)'s rule, and this file is committed
before a line of `bignum.pro` exists so that the ordering is in the history
rather than in a claim. `bignum.expected` goes in with it: every answer in it
was produced by `bc`, and none by this program.

```
programs/bignum/bignum.pro  --proto-->  bignum.sol       the library, in limbs.pro
programs/bignum/calc.pro    --proto-->  calc.sol         the driver, in lib/arith.pro
                                        @include "bignum.sol"
                            --solas-->  calc.sob
```

## Why this one

The seventh program, and the first in **two modules that disagree about what
their operators mean.**

Every program so far is one code module and one dialect file. None has two code
modules whose headers declare `+` differently and then call each other, and
that is the design's own answer to the one roadmap entry with no proposal
against it: *a dialect ends at its domain and cannot say where.*
`examples/vectors.pro` promises that *a second file in the same program may
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

And one question from outside Proto. Solveig's `ideas.md` records a want for *a
large-number-math library* as one of the reasons its extensions load with
`dlopen`, and this is the first program to find out whether such a library is
an extension at all. An extension is for a capability the machine does not have
and could not reasonably grow, a window or a socket; a bignum is arithmetic on
arrays, which the machine has. **Whether it wants C is a question about speed
and nothing else**, and speed is measured here rather than argued.

## What was predicted before it was written

| | |
| --- | --- |
| **1. The dialect has nothing to invent, and it is the first value domain whose operators are all plain messages.** | `sha2.pro` invented a rule, `+` masked to 2³², and `money.pro` invented one, `*` scaled back down. A limb dialect needs neither: a limb is an ordinary integer below the base, `+` on two of them is Solveig's `add`, and the rule of the domain, *take the digit and carry the rest*, is two forms applied after the arithmetic rather than a template wrapped around it. Predicted: `limbs.pro` declares `base`, `digit(t)` and `carry(t)` and uses `lib/control.pro` unchanged, and **no operator in it is a template.** [does-it-pay.md](../../docs/does-it-pay.md) says the invented kind is the only evidence that a declared grammar does something a fixed one cannot; this program is predicted to be the case where there is nothing to invent, and to pay accordingly less. |
| **2. `lib/arith.pro` serves the driver unchanged, for integers and bignums alike, because `+` names a message and messages dispatch.** | The driver writes `a + b` on two bignums and `i + #1` on a counter with one declaration behind both, `@infix + 60 add.`, since a bignum that answers `add` is added and an integer that answers it is added. Predicted: **the boundary the roadmap could not draw does not arise**, because the domain lives in the object rather than in the header. What traps the scaffolding in `digest` and `ledger` is precisely what those dialects *invented*: a template bakes one domain into one spelling, and dispatch cannot reach into a template. **The operators that pay are the operators that trap**, and this program is predicted to have neither. |
| **3. Folding gets no third customer.** | `base` is a form, so every use of it expands to a literal, and nothing in the loop is *derived* from it: `digit(t)` is `t:mod(#1000000000)` and `carry(t)` is `t:div(#1000000000)`. `ledger` had `scale:div(#2)` because round-half-up wants half a unit; integer arithmetic wants nothing but the base itself. Predicted: **no unfolded constant anywhere in the program**, and the folding entry moves by a customer declining rather than by a measurement. |
| **4. The overflow trap chooses the base, and it is the one place the substrate shapes the program.** | Solveig has one integer, signed 64-bit, trapping on overflow. A limb product plus a limb plus a carry must fit, so the base is the largest power of ten whose square does: 10⁹. Binary limbs would want 2³¹, with a conversion loop to print. Predicted: base 10⁹, chosen so that printing is `join` and reading is `copyFrom`, and the oracle can compare text. And predicted that **nothing in Python's `math` module is missing for this program**: what a bignum wants and Solveig lacks is not a function but a wider product, `mul` answering 128 bits, which no scripting language's integers offer either. |
| **5. `@include` of a generated file works unchanged, and an error in it names the generated file, whose map is beside it.** | Proto passes `@include` through as a statement, and Solveig resolves it beside the includer, so `calc.sol` includes `bignum.sol` and `solas` compiles both into one chunk. Predicted: an error in the library is reported at `bignum.sol:N`, `bignum.sol.map` takes N back to `bignum.pro`, and no change to Proto is needed. What is new is the **build**: `calc.sol` depends on `bignum.sol` and the Makefile has never had to order two Proto modules. Predicted to be one dependency line. |
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

Written after.
