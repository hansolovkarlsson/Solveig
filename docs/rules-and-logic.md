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
| Shell out to `solvm` while compiling | The tower answers itself, which is the elegant version. It also makes Solveig a build-time dependency, and *the build needs no Solveig* is load-bearing for the argument in the README. |

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

### Unification as the matching engine

Non-linear patterns — `f <x> <x>` matching only when both are the same — and
term rewriting in general. **The same answer as full BNF, for the same reason:**
matching becomes search, search means backtracking, and the diagnostics go.

---

## In order, if any of it is built

1. **Typed holes.** `<body: block>`. No evaluator, no tower, and it is where most
   of the value of "predicates" actually is.
2. **`[ ]` and `{ }`.** Two part kinds in an array the matcher already walks.
   Keeps the LL(1)-by-construction property if an optional part begins with a
   word, which it must for the same reason a pattern does.
3. **A parser toolkit written in Phoenix.** Not a feature. The best test of
   whether any of the above was worth having.
4. Everything else on this page waits for a program that wants it.
