# Completed roadmap items

*The case for each piece of work as it was argued before the work was done — the
problem, what the options were, and why the shape chosen was the one taken. This
is where a roadmap entry goes when it is finished, rather than being deleted.*

What actually landed, and when, is in [CHANGELOG.md](CHANGELOG.md), which names
the commit for each. What is still outstanding is in [ROADMAP.md](ROADMAP.md).
What went wrong on the way is in [POSTMORTEM.md](POSTMORTEM.md).

The numbers are the original ones and are never reused.

---

## 1. A tree of Phoenix's own — done, 0.1.0

**The problem.** Expansion and hygiene both want a tree, and Solas has none:
`sol_compile(source, chunk)` runs the parser straight into the emitter, one
pass, nothing in between.

**The options.** Borrow Solas's AST — there is none. Add one to Solas — changes
Solveig to suit Phoenix, and single-pass is the right shape for a compiler with
fixed syntax. Own one.

**Why this shape.** Owning a tree is what makes Phoenix a compiler rather than a
preprocessor, and it settles what Phoenix *is*: not a bolt-on to Solas, but a
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
evaluator, and Phoenix has none on purpose — see
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

## Settled by a customer rather than by argument

| | |
| --- | --- |
| **Optional parts** | Declined twice. `programs/ember` wanted none; `if`/`else` as two declarations was fine. |
| **Repeated parts** | Declined twice, the second with a reason. `programs/grammar` wants repetition and **a repeated pattern part would not have helped** — a grammar cannot be written as forms at all, so the repetition wanted is one level down in the object language. |
| **A trailing hole binding at unary precedence** | Retracted. It described a fix for a problem that was two programs choosing the wrong shape. See [POSTMORTEM.md](POSTMORTEM.md). |
