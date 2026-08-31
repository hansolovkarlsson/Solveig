# Rules as BNF, and predicate logic

Asked on 2026-08-31, with 0.5.0 in:

> Will it be possible to write rules as BNF in the future? Is predicate logic
> something that might be part of Phoenix in the future?

Each splits into a question about Phoenix and a question about a program written
in Phoenix, and the two halves have different answers. [targets.md](targets.md)
draws the same line for machine code.

---

## BNF: it is already here, restricted

```
@syntax if <c> then <a> else <b> => c:ifElse({ a }, { b }).
```

is a production, and the grammar it adds is exactly:

```ebnf
primary ::= "if" expression "then" expression "else" expression
```

So the question is not whether rules can be written as BNF. It is **how much of
BNF the restrictions can give up**, and the answer is: most of it, and the part
that is refused is refused for a reason that has been on this page since the
first commit.

| | |
| --- | --- |
| **Alternation** | A separate declaration under the same word. `if <c> then <a>` beside `if <c> then <a> else <b>` is `\|` written as two lines. Costs a line and reads better. |
| **Optionality, repetition** | Not there. `[ ]` and `{ }` are ordinary EBNF and ordinary to add: the matcher already walks a parts array and would gain two part kinds. Wanted before anybody writes `sum of <a> <b> <c>` three times. |
| **Holes naming a nonterminal** | Not there — every hole is `expression`. `<body: block>` is the roadmap's next item, and is the useful half of the whole question. |
| **A rule starting with a nonterminal** | **Refused**, and this is the line. |

## Where it stops, and why

**A production may not begin with a hole**, which rules out left recursion and
therefore rules out writing an expression grammar in `@syntax`. Three things
break at once, and they are the three this project has spent five versions not
breaking.

**The reader would have to guess.** Today a form is found by seeing a word it
knows, and one token decides between every candidate — which is why there is no
backtracking anywhere in the matcher, and why a use that goes wrong can say
`expected 'then' here, in the form 'if'`. A leading nonterminal means trying
alternatives and taking back what was read, and every diagnostic downstream
becomes *nothing matched*.

**Ambiguity would stop being checkable by looking.** `check_distinguishable` is a
linear walk over two arrays, and it reports in the words of the declarations:
*which has a hole where this has a word*. With general productions the same
question is the LR conflict question — decidable for restricted classes, and
reported as *shift/reduce conflict*, which is the kind of message this compiler
exists not to print.

**Composition would stop being safe**, and this is the deep one. Adding an
operator cannot change what an expression that does not use it already meant —
that is why operators came first. Adding a word-led pattern cannot either,
because it only reaches expressions containing that word. **An arbitrary
production can, and invisibly.** The collision rule from 0.4.0 works because a
collision happens at a word, where there is something to point at; two general
productions can collide with nothing in either of them to underline.

**And the case that motivates left recursion is already handled.** `a + b * c`
is left-recursive in every grammar that spells it out, and Phoenix reads it from
a precedence table instead. That is not luck: the operator table is the
composable, decidable fragment of left recursion, and it is why operators were
the first extension point rather than the easiest one.

## The position

**BNF-shaped, and LL(1) by construction rather than by checking.**

Two other systems arrived at the same place from different directions. Rust's
`macro_rules!` fragment specifiers — `$e:expr` — are typed holes, and its rules
about what may follow an `expr` fragment exist for the reason Phoenix bans two
holes in a row: something has to say where the hole ended. Racket's
`syntax-parse` syntax classes are the same idea with far more power, and still
decide a pattern by looking at it rather than by trying it.

## The thing that makes a pattern safe, and what would break it

**A word after a hole works because Phoenix's expression grammar cannot consume
a bare name.** `postfix` takes a name only after `:`, and `infix` takes only
operators — so an expression always stops at a bare `then`, and the pattern
picks it up.

That is load-bearing and nothing currently says so. **If the core grammar ever
gained a postfix keyword** — anything where a bare name may follow a complete
expression — every pattern in every dialect would be at risk at once, silently.
Rust's follow-set rules are stricter than Phoenix's for exactly this reason:
they are future-proofing against their own grammar growing. Phoenix has taken
the more permissive rule and should treat *the core grammar never consumes a
trailing bare name* as a promise rather than an accident.

## A BNF toolkit is a program, not a feature

Solveig's own `ideas.md` already wants one:

> **A parser toolkit** in the manner of lex, yacc, sed and awk — grammars
> written in something like BNF. **The most interesting of these**

That is a program written in Phoenix, needing nothing from Phoenix, exactly as
the BASIC compiler in [targets.md](targets.md) is. It may have a general grammar
engine with backtracking and ambiguity and every other thing refused above,
because **what a program does is not what its compiler's syntax does**.

And it is the better customer for Phoenix than another arithmetic example: a
grammar notation is precisely what a pattern language should be good at, and a
toolkit whose own notation is a Phoenix dialect is this project's premise
pointed at itself.

---

## Predicate logic: three questions wearing one name

### A Prolog dialect written in Phoenix

Yes, and **Phoenix helps with less of it than it looks.** `ideas.md` has already
priced the hard part:

> **Predicate logic** — unification, resolution and backtracking. Wanted:
> coroutines, continuations, and a non-local return, all three of which are
> recorded as **No** further down this page with reasons. It would need an
> explicit trail and choice-point stack instead. […] The sharpest single finding
> on this list and the largest job.

Phoenix changes none of that. What it changes is the notation, and the notation
is genuinely painful without it: `foo(X, Y) :- bar(X), baz(Y).` written as
message sends is unreadable, and it is exactly a pattern-language job. **Real
help with the front end, none with the engine, and the engine is the job.**

### Predicates in the pattern language

Side conditions on when a form applies — `syntax-parse`'s `#:when`, a guard on a
rule. This is a question about Phoenix, and the answer is the interesting one.

**A predicate has to run while compiling, and Phoenix has no evaluator.** That
is deliberate rather than missing: Phoenix emits Solveig source and lets Solveig
run it, which is the whole of why the build needs no Solveig and why a front end
here has no privileged access to anything.

So a guard means one of two things, and both are large:

| | |
| --- | --- |
| Write an evaluator | Phoenix gains a second language, and the question of whether it is the same language as the object language — the tower — has to be answered rather than avoided. |
| Run Solveig while compiling | The tower answers itself. It also makes Solveig a build-time dependency, and *the build needs no Solveig* is load-bearing for the argument in the README. |

**This is the tower question arriving from a third direction.** It came up first
as *is the meta-language the same language*, then in
[targets.md](targets.md) as *should `@language` choose the emitter too*. Today's
answer is that there is no meta-language, only a translator — and a guard is
what would force one.

**The cheap eighty per cent is already the next roadmap item.** A typed hole is a
unary predicate over syntax and needs no evaluator at all: `<body: block>` is
decidable by looking at what was parsed. It buys the part worth having — *`while`
wants a block here*, at the use, instead of a strange expansion further down —
without answering the tower question at all.

---

## If the evaluator is Solveig

*Asked on 2026-08-31, after the page above: whether the evaluator has to run
inside Phoenix, and whether the hosting Solveig already tried for HTTP is the
way to do it. Both answers are yes, and the second is more nearly ready than it
looks.*

### `embed.h` is the door, and it was built for this

`solum/embed.h` opens by naming its three cases:

> a webserver rendering a page per request, an editor evaluating a snippet, **a
> tool scripted in Solum**

Phoenix is the third. And the surface is declared rather than inferred:

> **This is the whole supported surface.** Everything a host needs is declared
> here or in the two headers below it; anything else in `solum/include` is the
> machine's own business and may change without notice.

`sol_compile_source` turns text into a chunk; `sol_vm_run` runs one;
`sol_vm_set_global_text` and `sol_vm_global_text` carry values in and out;
`sol_vm_set_step_limit` and `sol_vm_set_memory_limit` say what a run may spend.

### It has to be in-process, and not for tidiness

Shelling out to `solvm` per guard is possible and is the wrong shape, for three
reasons that are about the work rather than the aesthetics.

| | |
| --- | --- |
| **How often it runs** | A guard runs while parsing, once per use of a form. A process per call is not a design. |
| **What crosses the boundary** | A guard takes a *syntax object* — a subtree with spans and scopes — and answers yes or no. In process that is a value handed over. Across a process it is serialise-and-reparse, which means inventing a wire format for trees: a second language nobody asked for. |
| **Limits and failures** | `sol_vm_set_step_limit` means **a guard that loops forever fails the compile instead of hanging it**, which is the difference between a feature and a footgun. `sol_vm_error_message` and `sol_vm_error_trace` hand the failure back so it can be attributed to the guard's own span. |

### The webserver is the same loop

`embed/host.c` already wrote it. That file is

> the webserver from that entry with the sockets taken out: **compile one script
> once, run it many times — once per request — each run under its own
> allowance**, and see what comes back

Compile the guard once. Run it once per use. Each under its own allowance.
`serve_one` becomes `check_one` and very little else changes. **This is not an
analogy — it is the same loop, already built once and already tested.**

### What it costs, and what it does not

**It costs the build.** `bin/phoenix` would link `libsol.a`, and *the build needs
no Solveig* — in the README, in the Makefile's header, and in the first commit
message — stops being true. That is a real loss and the reason not to do it
casually.

**It does not cost the principle.** The claim was never *no dependency*; it was
**no privileged access**, because a front end reaching into Solas's internals
proves only that Solveig's author can write one. `embed.h` is the opposite of
internals: a declared, versioned, tested surface with an explicit statement of
what is not in it.

**And it completes a pair.** solveig-sdl is Solveig calling into C through
`extend.h`; Phoenix with guards is C calling into Solveig through `embed.h`. Two
halves of one arrangement, both through doors somebody wrote down.

### The rule to write down before the code

**A guard validates. It does not select.**

If a guard decides *whether a form matches*, parsing depends on evaluation, and
no tool can read a `.phx` without running it. That is the line this whole design
has held — the line Forth and TeX crossed — and a guard is a quiet way to cross
it.

If a guard runs *after* a form has matched, and may only reject it with a
message, then the matcher stays LL(1) by construction, the reader still never
guesses, and only **diagnostics** become dynamic. `swap <a> and <b>` can still
check that both holes are places; `while <t> do <b>` can still refuse a literal
condition.

**This is invisible once the evaluator is there and irreversible once dialects
depend on it**, which is why it is written here rather than decided later.

### Then the tower closes

Once `embed.h` is in, a guard may be written in *Phoenix*: compiled to Solveig
by the path that already exists, then embedded and run. The language's
compile-time written in the language, and cheap, because the only new part is
the door.

That is what the name was about.

### Unification as the matching engine

Non-linear patterns — `f <x> <x>` matching only when both are the same — and
term rewriting in general. **The same answer as full BNF, for the same reason:**
matching becomes search, search means backtracking, and the diagnostics go.

---

## In order, if any of it is built

1. **Typed holes.** `<body: block>`. No evaluator, no tower, and it is where most
   of the value of "predicates" actually is.
2. **A handful of named predicates.** `place`, `literal`, `block`, `name`. All
   decidable by looking at what was parsed, so still no evaluator, and between
   them they cover most of what is left.
3. **`[ ]` and `{ }`.** Two part kinds in an array the matcher already walks.
   Keeps the LL(1)-by-construction property if an optional part begins with a
   word, which it must for the same reason a pattern does.
4. **Solveig guards through `embed.h`.** Only when a real program wants
   something the first two cannot say — the rule `lib/text.sol` used on itself:
   one customer, satisfied in six lines, is not a reason to grow a surface.
   Validation and not selection, whenever it comes.
5. **A parser toolkit written in Phoenix.** Not a feature. The best test of
   whether any of the above was worth having.
6. Everything else on this page waits for a program that wants it.
