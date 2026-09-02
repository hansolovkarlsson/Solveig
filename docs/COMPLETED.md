# Completed roadmap items

*The case for each piece of work as it was argued before the work was done — the
problem, what the options were, and why the shape chosen was the one taken. This
is where a roadmap entry goes when it is finished, rather than being deleted.*

What actually landed, and when, is in [CHANGELOG.md](CHANGELOG.md), which names
the commit for each. What is still outstanding is in [ROADMAP.md](ROADMAP.md).
What went wrong on the way is in [POSTMORTEM.md](POSTMORTEM.md).

The numbers are the original ones and are never reused.

---

## 1. A tree of Proto's own — done, 0.1.0

**The problem.** Expansion and hygiene both want a tree, and Solas has none:
`sol_compile(source, chunk)` runs the parser straight into the emitter, one
pass, nothing in between.

**The options.** Borrow Solas's AST — there is none. Add one to Solas — changes
Solveig to suit Proto, and single-pass is the right shape for a compiler with
fixed syntax. Own one.

**Why this shape.** Owning a tree is what makes Proto a compiler rather than a
preprocessor, and it settles what Proto *is*: not a bolt-on to Solas, but a
second compiler that happens to target Solveig.

## 2. Spans, and the map — done, 0.1.0

**The problem.** A language whose syntax is declared per module has one
characteristic way of failing: somebody writes one thing, is shown an error
about another, and cannot get from the second back to the first. Every macro
system that became unusable became unusable that way.

**Why it was first and not later.** A tree without spans is a tree that has to
be rebuilt to get them. The map cost a column and a file; retrofitting it would
have cost the tree.

**What it bought later.** When `@use` made a module several files, making a span
carry its file was a field rather than a rewrite (7).

## 3. Operators before anything else — done, 0.1.0

**The problem.** Which extension point to build first.

**Why operators.** A precedence table *composes*: adding an operator cannot
change what an expression that does not use it already meant. A general grammar
rule can, silently. Operators are the composable, decidable fragment of the
thing, which is also why the case that motivates left recursion — `a + b * c` —
never needs left recursion here.

## 4. The expander — done, 0.2.0

**The problem.** A form is not a method: its arguments arrive unevaluated, so
the template may put them somewhere the caller never wrote. That is the whole of
what a form buys and a method cannot do it.

**Why hygiene came in the same commit.** A system that expands without hygiene
grows programs that depend on the capture, and those programs are what make
hygiene impossible to add. Not a schedule — a one-way door.

**Why the call shape.** `name(args)` is a shape the core grammar already had, so
declaring a form added a *meaning* without adding a *production*. A production
can change what a program without it already meant, and that could wait until
the collision rule existed (7).

**Termination, without a counter.** A template is read under the header as it
stood at its own line, so form N can mention only forms below N and the highest
index strictly falls. A property of the header reading top to bottom.

## 5. Referential transparency — done, 0.3.0

**The problem.** Renaming a template's binders stops a form capturing what its
caller passed. The other direction was open: a template's *free* `total` landing
inside a caller whose temporary is also `total`.

**Why it is not a resolver.** Solveig's own rule made it one pass — only
parameters and `| … |` temporaries are locals, everything else is a flat global
— so the frames are the blocks and a name that is neither needs no protecting.
Reading `REFERENCE.md` before designing is most of why this fit in one file.

**Why the caller's local gives way.** The template cannot be renamed, reaching
the global being the whole of what it meant, and a local is a thing no other
frame can see.

## 6. Diagnostics that name the form — done, 0.2.0, extended 0.6.0

**The problem.** The characteristic failure of a macro system is an error about
code nobody wrote.

**The shape.** `introduced_by` on every node an expansion produced, and a walk
of the chain. Extended in 0.6.0 so a hole can say what it accepts, which moves
`swap #1 and b` from *this cannot be assigned to* after expansion to a message
at the line somebody wrote.

## 7. Two dialects meeting — done, 0.4.0

**The problem.** The one everything else queued behind. A dialect was a file's
header and there was no way to import one, so nothing could collide; that stops
being an answer the moment a library can publish a dialect.

**The options.** Racket answers it with modules and scoped bindings, and it was
worth reading how.

**Why Solveig's answer.** Solveig had already decided it for two files claiming
one global — the later wins, and the compiler says so rather than letting it
pass — and **a language should not hold two philosophies about one question**.
The four cases differ in who could have known, which is the same distinction
Solveig draws when it warns on a claim and not on an update.

**What it did not cost.** Hygiene. 0.3.0 predicted one `scope` number would stop
being enough once a template could be declared outside the module using it. It
does not, because globals are one flat namespace, so a template's free `total`
and a caller's global `total` are the same variable by construction.

## 8. A form that reads as a statement — done, 0.5.0

**The problem.** `unless(test, body)` says what it means; `unless test then body`
says it the way the language it is imitating does.

**Why it waited.** It is the first thing here that adds a *production*, and a
production is what can change what a program without it already meant. It waited
for 7 to say what happens when two files add one.

**Why no backtracking.** A hole is parsed once and shared by every candidate
still standing, so two forms can only part company at a word — and the
declaration refuses any pair that would have parted company anywhere else.

## 9. A hole that says what it wants — done, 0.6.0

**The problem.** Every hole took an expression and could not say otherwise, so a
bad use expanded into Solveig that failed somewhere further down.

**Why these five and not a guard.** `expression`, `name`, `literal`, `block`,
`place` are all decided by *looking* at what was parsed. None needs an
evaluator, and Proto has none on purpose — see
[rules-and-logic.md](rules-and-logic.md).

**Why checked after expansion.** A hole filled by another form is then checked
against what that form *became*.

## 10. An operator that stands for a template — done, 0.7.0

**The problem.** `@infix` named a message and could not template; `@syntax`
templates but must begin with a word, which an infix operator does not.
Short-circuiting fell exactly between them, and six versions had not noticed
because nothing had tried.

**What tried.** `programs/ember`, which wrote `(a == b):and({ … })` by hand six
times.

**Why it is a form.** An operator with a template is registered as one, so
hygiene, provenance and the trail arrive from the expander rather than from a
second implementation of each.

## 11. Two holes in a row when the second is a block — done, 0.8.0

**The problem.** `if (c) { … }` needs two adjacent holes.

**Why the ban was wrong as stated.** It said *no boundary between them*. A block
is a primary, consumed only where an operand may start, so an expression always
stops at the `{`. The rule is really about **greed** — given `<a> <b>` and
`f x + y` the first hole takes the sum — and a delimited hole has no such
problem.

**Why it could not have been done sooner.** A hole could not say it was
delimited before 9 gave holes kinds.

## 12. `||` without a declarable lexer — done, 0.9.0

**The problem.** `|` is the one spelling a dialect cannot have, so
`lib/clike.pro` declared C's *or* as `\/` and wrote a paragraph apologising for
it beside a `&&` that needed no apology.

**The option that was proposed, and refused.** A `@token` directive naming a
token and binding a spelling to it — `@token TOK_PIPE2 "||".` — so that `@infix`
could name the token rather than the characters. Refused for two reasons. It
does not reach the problem: what stops `|` is not that `@infix` cannot spell it
but that `{ a | b }` would have two readings, and naming the ambiguity does not
decide it. And it costs the property the whole design sits on from a new
direction — not the Forth one, since a `@token` header is still read rather than
run, but the practical one: **today any tool can tokenise any `.pro` without
knowing what a dialect is**, and a declarable token stream makes every future
formatter, highlighter and `grep` implement the directive before it can lex.

**And the same proposal in quotes, refused for the same reason.** The follow-up
was `@infix "|" 25 or.` — quote the spelling in the *declaration* so that it
cannot collide with the `|` in the code. It does not, and that is the point: the
declaration was never ambiguous. `@infix \/ 25 or.` needs no quotes and compiles
today; so does `@infix || 25`. **The two readings collide at the use, where
nobody writes quotes.** After any spelling of that declaration the code below
still says `{ a | b }`, bare, and that text is then both a block with parameter
`a` and body `b` and a block whose body is `a | b` — two complete legal parses
of one line, with the declaration nowhere on it. Quoting a declaration cannot
reach a line the declaration is not on. If the quotes are instead meant to make
*new* spellings lexable, they are `@token` wearing different clothes: the lexer
would have to read the header before it could lex the body.

**Retracted on 2026-09-02: one sentence above claims more than it can.**
*"Naming the ambiguity does not decide it"* is true of naming and was written as
though it were true of everything. **A rule decides it**, and Proto had the
mechanism before anybody looked: `{ a | b }` is a parameter and a body **by
rule**, in every module, and a declared `|` is an operator in every position a
block is not reading a bar of its own. Escaped one bracket down, `{ (a) | b }`,
exactly as `#[(b = c) = d]` escapes the dictionary rule of the same shape landed
in 0.12.0 — *four hours before this was disproved, and by the same argument.*

Demonstrated by a working change: two hunks in `reader.c`, no change to the
lexer at all, the whole suite green and every block form intact. It was not kept
— see [ROADMAP.md](ROADMAP.md), which records what it would cost — but the
claim it disproves does not depend on keeping it.

**What still stands, and it is most of the entry.** `@token` and the quoted
spelling genuinely do not reach the problem, for the reason given: the
declaration was never ambiguous, and a quote cannot reach a line the declaration
is not on. And `|` is still not an *operator character* and cannot become one —
what changed is that it need not be one to be declarable, being a token in its
own right that the parser may look up. The property the entry defends —
**any tool can tokenise any `.pro` without knowing what a dialect is** — is
untouched, which is why the demonstration never went near `lex.c`.

**And the cause was misattributed all along, in both directions.** This entry
blamed the ambiguity and stopped; a later reading blamed Solveig and was worse.
Neither is right. What stands in the way of `|` is **Proto's own block syntax**,
which Solveig shares and settles the same way. Nothing about `|` was ever
Solveig's constraint to remove.

The three things being run together are worth separating, because the confusion
is natural and the names do not help: the **character** in the source, the
**token** the lexer makes of it, and the **declaration** that gives a token's
text a meaning. Quoting changes only how the third is written. The collision is
between the first two, and the lexer resolves it without consulting any
declaration at all — which is the property that lets a tool tokenise a file it
knows nothing about.

**The shape taken instead.** `||` in the *fixed* lexer, taken before the bar,
belonging to every dialect and declared by none. The split the proposal wanted
already existed — `PROTO_TOK_OPERATOR` is spelling only and `@infix` is meaning —
so the question was never *how does a file name a token* but *which spellings
are in the vocabulary*.

**Why it was safe, checked rather than assumed.** A block looks for a **lone**
bar in each of the three places it allows one, so `{ a | b }` and
`{ x | | t | t }` never see the new token; `{ a || b }` was already an error, so
nothing legal was taken. The one casualty, found by compiling it rather than by
reasoning about it: `{ || … }` parsed as an empty list of temporaries and emitted
nothing. It is `{ | | … }` now, it appeared nowhere, and it is the only thing
this cost.

## 13. The name — done, no version, 2026-09-01

*Not a roadmap item; it was never on that page. It is here because the case was
argued with options before the work, which is what this file keeps.*

**The problem.** "Phoenix" named two things. This project used it, and Solveig's
`docs/ideas.md` had reserved it three days earlier — *a second language whose
output Solum uses*, closing *the name, should it happen, is Phoenix* — for a
language that would publish a **library** Solum consumes. That entry explicitly
refuses *a nicer skin on this one*, so the two are not the same idea and cannot
share a name. The shipped compiler held the word by use; the unbuilt idea held
it by reservation, in writing, in another repository.

**The intermediate step, and why it was wrong.** The first move was to
*Phoenix Proto*, marking this tree as a prototype restart, with the language
still called Phoenix. That distinction did not survive an hour — see
[POSTMORTEM.md](POSTMORTEM.md) 14. The prototype framing is the honest
description of the thing, not a modifier on a name that was leaving anyway.

**The options, on the one choice that was not mechanical.** The identifier
scheme is a strict three-case prefix — `Phx` types, `phx_` functions, `PHX_`
macros — so respelling it is arithmetic. The extension is not:

| | |
| --- | --- |
| `Proto`/`proto_`/`PROTO_`, files `.proto` | Consistent to a fault. `.proto` belongs to Protocol Buffers. |
| `Pro`/`pro_`/`PRO_`, files `.pro` | Keeps the three-letter abbreviation `phx_` had. `Pro` reads as marketing. |
| **`Proto`/`proto_`/`PROTO_`, files `.pro`** | **Taken.** Full word where a person reads it, short extension where a tool does. |

**Why `.pro` and not `.proto`.** Linguist and most editors key on the extension,
so every module in this tree would have been highlighted as protobuf — under a
README whose opening argument is that *a tool can tell what language a file is
in*. Losing that on the extension, of all things, would have been the wrong
place to be consistent. `.pro` is also four characters, which is why
`default_output_path` — it compares `length - 4` against the suffix — came
through untouched. That was luck, and is recorded as luck.

**What it cost**, which is one thing. `lex.h` is dense enough in identifiers
that respelling them all dropped it under git's 50% rename threshold, so it
records as a delete and a create where the other thirty-five moves record as
renames. `git log --follow --find-renames=30%` still walks it back to the first
commit; the default no longer does, for one file in thirty-six.

**What it did not cost.** Nothing in the language changed. The suite reported
the same 58, 6, 34 and 10 checks over the same ten examples and programs, and
the diff was 1,435 lines out against 1,435 back in — the only shape a pure
respelling can have.

## 14. `@language`, removed — done, 0.10.0

**The problem.** It was the only directive that did nothing. It parsed, recorded
a name and a span in `ProtoDialect`, and nothing in the tree ever read either —
not `emit.c`, not `unit.c`, not `main.c`. No test named it; `tests/test_use.c`
used `@language solveig.` ten times purely as header filler. It enforced exactly
one rule, that a module declares at most one, which by way of `@use` also made
it an error in a dialect file — the first thing `programs/digest` got wrong.

Three properties that should not coexist: it was **optional** (`module = {
directive } { statement }` makes every directive optional, and the name is `NULL
if unstated`), it was **ignored**, and it was **universally written**. That is
the definition of a ritual.

**The options.** The roadmap had said it should select the reader, or the
emitter, or stop existing.

*Select the emitter* is blocked by [targets.md](targets.md), which had already
refused to build a second one. *Select the reader* is larger still. So the item
had not sat for nine versions because it was hard to decide — it had sat because
two of its three options depended on a build this project has declined, and the
entry could not move.

*A fourth option was proposed and rejected:* make it **assert** — one reader,
one emitter, so any name but `solveig` is an error at line 1. Fifteen lines,
touches no `.pro`, and it is the code a selector would need later. The argument
for it was reversibility: asserting is cheap and deleting is not.

**Why this shape.** Because the reversibility argument prices the change and
does not ask whether the thing is right, and the thing is not right.

Read `@language <name>.` at the top of a file and it plainly says *the body
below is written in `<name>`*. **That reading is false in every file with a
header.** `examples/forms.pro` said `@language solveig.` and then declared `+`,
`<`, `>`, `unless`, `while` and `swap`; its body is not Solveig, and Solveig
cannot read it. The reading under which the line was true — *the substrate is
Solveig* — is the same for every `.pro` there will ever be and is already
carried by the extension. A directive whose most natural reading is false is not
fixed by checking its spelling.

And the thing that could one day differ between two files is the **output**, for
which `@language` is the wrong word. targets.md had already reached for the
right one in its own sentence — *"Proto targets ARM64" is a line in a file* — so
if a second emitter is ever built, what gets added is `@target`, naming what it
selects.

**What it cost.** Nine `.pro` files, ten fixtures in `tests/test_use.c`, the
`HEADER` and `LANG` prefixes in two more, three spots in the README, one
production in GRAMMAR.md, the parse branch in `reader.c`, and `name` and
`declared_at` in `ProtoDialect`.

**What it did not cost.** The suite reports the same 58, 6, 34 and 10 checks
over the same ten examples and programs. The map test needed only its `/* line N
*/` comments renumbered: a directive emits nothing, so removing a header line
moves no generated line.

**Two things were deliberately not done.** No tombstone branch in `reader.c`
saying *`@language` was removed in 0.10.0* — the generic error already names
exactly what the header takes, and carrying the name of a deleted directive for
no customer is the same mistake in miniature. And the test that checked
*language declared twice* was replaced rather than deleted, by one for the
branch that now catches it: an unknown directive, which nothing had tested.

**What replaced its one real rule.** That a `@use`d file is read into the header
of the module using it — which `programs/digest` noted the old diagnostic
enforced sideways without ever stating — is stated in the README under *A
dialect is a file*, where somebody would look for it.

## 15. Solveig's spellings, closed as far as they close — done, 0.11.0 to 0.13.0

**The problem.** [GRAMMAR.md](GRAMMAR.md) said everything but `operator` was
Solveig's own spelling, *so that a file can be read by somebody who knows
Solveig without a second set of habits*, and [README.md](../README.md) went
further: a module declaring nothing *reads exactly as Solveig does today*.
Comparing every form in Solveig's grammar against Proto, one file each, gives
**nine divergences out of eighteen**. Both sentences were false, and a person
who knows Solveig met the first of them at `#-5`.

**How it was found is half the entry.** `programs/ledger` found *one* of the
nine — `#-1225`, at the second line of its data, a ledger being the first
program here with an ordinary negative value. It was written up as a missing
integer literal and would have stayed that size. The other eight came from being
asked whether that survey had been complete. It had not been, and nothing except
the question would have said so.

**The options.** Close what closes and restate the claim, or restate the claim
and close nothing. The second was never serious once the list existed: four of
the nine cost nothing at all, and one of them was a defect rather than a gap.

**Why this shape.** The nine sorted into five kinds, and sorting them was most
of the work:

| | |
| --- | --- |
| **Free** — `#-45`, `$FF08`, `1e10` | Nothing in Proto objected. Nothing else may begin with `#`, `$` was not a token at all, and a float simply stopped at its fraction. |
| **A defect, not a gap** — `"\q"` | The only difference pointing the *other* way. Proto took any character after a backslash; Solveig has five escapes. So a `.pro` compiled clean and emitted a `.sol` `solas` refused — **Proto emitting invalid Solveig**, which is the single failure the map and the run-every-example discipline exist to prevent, and which neither caught because no example has a bad escape. |
| **A parse rule** — `#[a = b]` | Called free on the strength of the lexer and was not. Solveig writes `pair = sum "=" expression` and settles the ambiguity by *level*; Proto cannot copy that, a dialect being free to declare `=` anywhere and `lib/clike.pro` putting it at 10. |
| **A lexical split with a bill** — `%1011` | `%` is an operator character here and is not one in Solveig, which has no `%` at all. |
| **Already decided, or impossible** — `( \| t \| … )`, `@expr`, `-3` | A rough edge, a refusal, and a thing that cannot be had. |

**The two that were decisions, and what each conceded.**

`#[a = b]` took the rule that **a top-level `=` inside a dictionary is the
separator, whatever the header said** — the first place in this language where a
context outranks a declaration. What keeps it a rule rather than `=` being taken
away is that it stops at the first bracket: `#[(b = c) = d]` still uses the
declared one. It is a *parser* rule, so nothing about tokenising a `.pro`
without knowing its dialect changed.

`%1011` took the rule that **a `%` immediately before `0` or `1` begins a
number**, and everything else is the operator. No declaration is consulted, so
again the tokenising line held. **But this is the first spelling here that took
something from what a dialect may declare**: a module declaring `%` can no
longer write `a %1` without a space. Entry 12 above held `||` up as the shape
any future request should take — *grow the fixed vocabulary rather than making
the vocabulary declarable* — and `||` cost only `{ || … }` out of the core. This
is the second instance of that shape and the first to bill a dialect. Small,
unused in this repository, and loud when it bites. **The next one might be none
of those, and 12 should be read with this attached.**

**And one that cannot be closed, which is the finding under all of it.** `-3` is
a literal in Solveig, whose scanner gives the sign to the number outside a
`@expr` region and treats it as the operator inside one. Proto can have neither
half: no regions, and taking `-3` as a literal would stop `a -3` being a
subtraction in every dialect that declares `-`. So the claim was **never
achievable**, and 0.1.0 chose against it without recording that it had. That is
the extensible-operator line arriving from a direction nothing had come from —
not a dialect wanting to change the lexer, but *Solveig's own number syntax
being uncopyable while operators stay declarable*.

**What it cost.** `a %0…` and `a %1…` without a space, in any module declaring
`%`. Nothing in the tree writes that — `%` as mod is `n % #2` throughout,
because mod wants an integer and a bare digit is a float.

**What it did not cost.** Any part of *a tool can tokenise a `.pro` without
knowing what a dialect is*. Both new rules consult the source and no
declaration, and the dictionary one lives in the parser. The suite went from 34
reader checks to 60, and every example and program builds byte-identical output
where the spelling did not change.

## 16. A declared `|`, and the spelling convergence it forced — done, 0.14.0

**The problem.** `README.md`, `proto/src/lex.c` and entry 12 above all said a
dialect cannot declare `|`, because `{ a | b }` would then have two readings.
Entry 12 put it as *naming the ambiguity does not decide it*. That was wrong,
and [POSTMORTEM.md](POSTMORTEM.md) 18 is how it was found: a second session
built the thing and it worked.

**Two questions had been run together.** *May `|` join the operator characters?*
— no, and that stands, because a character in that set runs together with its
neighbours and a `|` there would make `|=` a spelling. *May `|` be declared?* —
a different question entirely, since a bar is already a token of its own and a
parser may look one up without it ever entering the set.

**The options.** Leave it, on the strength of the entry above; or take the rule.
There was no third, once the demonstration existed.

**Why this shape.** A block settles its parameters and its temporaries with a
bounded lookahead — `looks_like_names_then_bar` — that consults no dialect and
never has. So the collision is exactly one production wide:

```
{ a | b }        a parameter and a body, in every module, declared bar or not
a | b            an or, everywhere a bar is not a block's own punctuation
{ (a) | b }      the escape: a body opening with a group is a body
```

That is the second place in Proto where a context outranks a declaration, and
the first — `#[k = v]` in 0.12.0 — is the same shape and the same escape. **The
mechanism was in the language four hours before the claim was disproved**, which
is the part of this worth remembering.

**Two things the demonstration had wrong, fixed before landing.**
`@prefix |` was accepted and inert; it is refused now, because a block's
temporaries open with a bar and a prefix one would have nothing to tell them
apart — and a declaration accepted and doing nothing is what `@language` was
deleted for in 0.10.0. And a stray undeclared bar gave *expected '.' after this
statement*; it gives *'|' has no meaning in this module* now, with the note
every other undeclared operator gets.

**What it cost, and it is the reason this waited a version.** 0.13.0 had just
settled the repository on *one spelling per operation*, with `\` for a bitwise
or **because `|` could not be had** — the mnemonic written into four files. So
landing the bar meant redoing that convergence, and the two went in together
rather than a version apart. **A spelling should be changed once**, and this one
was changed twice; the second time is this entry.

Nine lines of code across three files, and the prose in five more. The table is
C's exactly now:

| | logical | bitwise |
| --- | --- | --- |
| and | `&&` | `&` |
| or | `\|\|` | `\|` |
| not | `!` | `~` |
| xor | — | `^` |

**What it did not cost.** The lexer, which was never touched — `|` is still
`PROTO_TOK_BAR` and still not an operator character, so **a tool can tokenise
any `.pro` knowing nothing about its dialect**, which is the property entry 12
was written to defend and which it defends correctly. And `|=` stays
undeclarable, nothing being able to run together with a bar. That is the price
of not touching the lexer and it is the right price.

`\` is free and unused now. Nine checks in `tests/test_reader.c` hold both
halves of the rule and both refusals.

## Settled by a customer rather than by argument

| | |
| --- | --- |
| **Optional parts** | Declined twice. `programs/ember` wanted none; `if`/`else` as two declarations was fine. |
| **Repeated parts** | Declined twice, the second with a reason. `programs/grammar` wants repetition and **a repeated pattern part would not have helped** — a grammar cannot be written as forms at all, so the repetition wanted is one level down in the object language. |
| **A trailing hole binding at unary precedence** | Retracted. It described a fix for a problem that was two programs choosing the wrong shape. See [POSTMORTEM.md](POSTMORTEM.md). |
