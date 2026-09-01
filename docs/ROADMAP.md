# Roadmap

What is still outstanding, and what has been refused. Each entry says what would
have to be true before it is worth starting.

The work that is finished is in two places: [CHANGELOG.md](CHANGELOG.md) names
what landed and the commit that carried it, and [COMPLETED.md](COMPLETED.md)
keeps the case for each piece as it was argued *before* the work — the problem,
the options, and why the shape chosen was the one taken. What went wrong on the
way is in [POSTMORTEM.md](POSTMORTEM.md); what a day consisted of is in
[journal.md](journal.md).

**Two items on this page have been declined by a customer rather than by
argument**, which is worth more than either. See *Settled by a customer* at the
foot of COMPLETED.md.

## Open, and undecided

**`@language` records a name and acts on nothing.** Eight versions in, it is the
only inert directive, and every `.phx` writes `@language solveig.` as a ritual —
in the directive the README uses to argue that a tool can tell what language a
file is in. It should select the *reader*, or the *emitter* as
[targets.md](targets.md) argues, or stop existing. **A decision rather than a
build**, and not one to take unasked.

**No postfix operators.** Phoenix has prefix and infix; `x++`, `a[i]` and
`p->f`-in-postfix-position have no spelling at all. `lib/clike.phx` names it as
one of the four things C has that it cannot. Not a rule that could be relaxed —
the extension point does not exist. No customer has been blocked by it.

**A hole's kind is one choice, with no alternation.** `lib/clike.phx` wanted *a
block, or another use of me* for C's `else` and could not say it, so a chain
wants its braces. Worked around; recorded because it is the same shape as
optional parts and would want deciding with them.

## Waiting on a customer — optional and repeated parts

**Declined twice, and the second time with a reason.**

`programs/ember` wanted neither: no variadic notation, and `if`/`else` as two
declarations was fine.

`programs/grammar` was written partly to settle it, being the program most
likely to want repetition -- EBNF writes `sum = term { op term }` and means it.
It wants repetition and **a repeated pattern part would not have helped**: a
grammar cannot be written as forms at all, because a template cannot declare a
form, so the rules live in a table as data and the repetition wanted is in the
object language rather than in Phoenix. Both grammars have a `whileTrue` where
EBNF has a brace, and no Phoenix feature would have removed it.

That is a reason rather than a shrug, and it moves this below whatever the next
program finds.

**`if <c> then <a> else <b>` is a second declaration rather than an optional
tail**, which is honest and costs a line. Repetition — a form taking a list —
has no spelling at all, and wants one before anybody writes `sum of <a> <b> <c>`
three times.

Two more part kinds in an array the matcher already walks. **The property to
keep is that an optional part begins with a word**, for the reason a pattern
does: it is what lets one token decide whether the part is there, and it is what
keeps the matcher free of backtracking.

**Then a guard, and the evaluator it needs is Solveig.** `solum/embed.h` was
built for it — one of the three cases it names is *a tool scripted in Solum* —
and `embed/host.c` already wrote the loop: compile one script once, run it many
times, each under its own allowance. Compile the guard once, run it per use, and
`serve_one` becomes `check_one`.

It costs *the build needs no Solveig*, which is real. It does not cost *no
privileged access*, which is the claim that matters: `embed.h` is a declared
surface, and using it is the mirror of solveig-sdl using `extend.h`. **The rule
to fix before any of it is written: a guard validates, it does not select** —
otherwise parsing depends on evaluation and no tool can read a `.phx` without
running it.

0.6.0 is the reason this is not urgent. The five kinds cover what a guard would
mostly have been used for, and they cover it without an evaluator.
[rules-and-logic.md](rules-and-logic.md) argues the whole of it.


## Retracted

**A form's trailing hole swallowing what follows was written up twice as a
limitation and is not one.** `programs/ember` reported it for postfix sends and
`programs/grammar` for infix operators, and both were the same mistake: a form
declared as a pattern when it was an application. A call ends at its closing
parenthesis and has no such behaviour.

The sketch of a fix that went with it -- a trailing hole binding at `unary`
precedence, declared per form -- described a feature nothing needs. It is not on
this page any more.

**What the two programs really found is that choosing the shape wrongly is
silent.** A pattern where a call was meant parses, quietly takes what came
after, and fails at run time in generated code if it fails at all. Nothing at
the declaration can say otherwise, both readings being legal. The rule is now in
[GRAMMAR.md](GRAMMAR.md) under *Which shape a form should have*, which is where
somebody choosing one would look; it had been in a program's README, which is
not.

## Not planned, and why

**A dialect that changes the lexer.** The line between a fixed token stream and
a declared grammar is where this design sits. An extensible grammar over fixed
tokens can still be parsed by something that has not run the file's own
declarations, and every editor, formatter and `grep` downstream depends on that.
Forth and TeX moved the line and became languages no tool can read without
executing them. If it moves, it moves at the module boundary and nowhere else.

**A rule that begins with a nonterminal.** Left recursion, and therefore an
expression grammar written in `@syntax`. The reader would have to guess,
ambiguity would stop being checkable by looking, and composition would stop
being safe -- and the case that motivates it is already read from the precedence
table. [rules-and-logic.md](rules-and-logic.md) argues all three.

**Emitting bytecode, or machine code.** Phoenix would then own the `.sob` format
and Solum's instruction set, and reimplement what Solas already does. The one
thing it would buy — errors from Solas landing on Phoenix source — the map buys
instead. [targets.md](targets.md) works the question through, including what a
native back end would actually cost and why a program *written in* Phoenix can
already emit anything it likes.

**`@expr`.** Solveig's fixed infix region is the special case of what `@infix`
generalises. Supporting both would be supporting two.

## Rough edges

| | |
| --- | --- |
| Long send chains are not wrapped | A block that will not fit is broken across lines; `a:b(c):d(e):f(g)` is not. |
| Dictionary literals | `#[a = b]` separates a pair with `=`, which a dialect may declare. Needs a decision rather than a default. |
| Temporaries in a group | `( \| t \| … )` is Solveig's; Phoenix reads `( expr. expr )`. |
| The map is written only with `--map` | The Makefile always passes it. The default should probably change. |
| A generated name is `t__1` | Legible, and it collides with nothing because the whole module's identifiers are checked. It is still a name a person could have wanted. |
