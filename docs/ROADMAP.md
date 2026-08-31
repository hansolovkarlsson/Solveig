# Roadmap

What 0.1.0 established, in the order the rest depends on it. Each entry says
what would have to be true before the next one is worth starting.

## Done — 0.5.0, a form that reads as a statement

**`@syntax unless <test> then <body> => ... .`** A hole is `<name>` and
everything else is a literal word. Same holes, same template, same expansion as
the call shape: a pattern changes how a form is written and nothing about what
one is.

**Two forms may share a leading word**, which is what `if <c> then <a>` beside
`if <c> then <a> else <b>` needs and the reason the matcher exists. Matched
together, with no backtracking: a hole is parsed once and shared by every
candidate, so two forms can only part company at a word.

**Which holds because the declaration refuses the pairs that could not.** Two
patterns whose first difference is a hole against a word are an error where they
are written, not a preference rule at every use. `on <w> do <b>` and
`on error do <b>` are both `on error do x`, and no rule about which wins is one
anybody could see from either line.

**A pattern begins with a word and has no two holes in a row**, and a pattern
word is reserved nowhere -- `then` is a form's word in a file that declared one
and an ordinary name everywhere else.

**The prediction that did not hold.** 0.4.0 wondered whether a pattern language
would dissolve the group in `while(t, (a. b))`. It does not: `.` ends the
statement whatever the form around it looks like, so `while t do (a. b)` still
wants its parentheses. Recorded rather than quietly dropped.

## Done — 0.4.0, a dialect that is a file

**`@use "arith.phx".`** A dialect file holds directives and nothing else, and is
read into the header of whoever used it. Looked for beside the file using it,
then `-I`, then `PHOENIX_PATH`. Read once, so a diamond is free; a cycle is an
error with the chain that got there.

**The collision rule, which everything was queuing behind.** Solveig had already
answered it for two files claiming one global -- the later wins and the compiler
says so -- and the four cases differ in who could have known. Both in one module
is an error; the module over a `@use` is silent; either direction between files
warns. The README argues it under *When two dialects collide*.

**A span carries its file.** The refactor the rest needed: a module is several
files now, and a diagnostic three files away shows the line without being told
which file it is about. The map grew a fourth column, printed only for the
lines that came from somewhere else.

**Hygiene did not need to change, and the reason is Solveig's.** 0.3.0 predicted
one `scope` number would stop being enough once a template could be declared
outside the module using it. It does not: globals are one flat namespace, so a
template's free `total` and a caller's global `total` are the same variable by
construction. A `scope` becomes a set the day the substrate has a module system.

## Done — 0.3.0, the other half of hygiene

**A template's free references are protected.** `@syntax bump(n) => total :=
total:add(n).` means the global `total`, and goes on meaning it inside a caller
whose temporary is also called `total`. The caller's local is renamed throughout
its own frame, because the template cannot be -- reaching the global is what it
meant -- and a local is a thing no other frame can see.

**One pass, not a resolver, and Solveig's rule is why.** Only parameters and
`| ... |` temporaries are locals and everything else is a flat global
(REFERENCE.md, *Names and binding*), so the frames are the blocks and a name
that is not a parameter or a temporary needs no protecting at all.

**Demonstrated by running.** The unprotected expansion of the example prints
`#105` and `#0` -- the caller's temporary updated and the global untouched.
Both numbers wrong, neither an error, which is the failure this exists to stop.

## Done — 0.2.0, the expander

**Forms a module declares for itself.** `@syntax name(params) => template.`
Call-shaped, because `name(args)` is a shape the core grammar already had, so
declaring one adds a meaning without adding a production.

**Hygiene, in the same commit rather than after it.** Every name a template
binds is renamed at every expansion, to one nothing in the module uses -- the
set is collected by lexing the source, so *fresh* means fresh rather than
probably fresh. Demonstrated in `examples/forms.phx` by a program that prints
the wrong answer if the renaming is removed, which is what the failure actually
looks like.

**Expansion trails.** `introduced_by` on every node an expansion produced, and
`phx_note_expansion` walking the chain. The case worth having it for is the one
only the template and the use together can be wrong about -- a parameter
substituted into a place that has to be a place.

**Expansion terminates without a limit.** A template is read under the header as
it stood at its own line, so form N can mention only forms below N and the
highest index strictly falls. A property of the header reading top to bottom
rather than a counter.

What is *not* here: a form that reads as a statement rather than a call, and
referential transparency for a template's free names. Both are below.

## Done — 0.1.0

**A tree of Phoenix's own.** Solas has none: `sol_compile` runs the parser into
the emitter in one pass. Expansion and hygiene both want a tree, so Phoenix owns
one, and that is what makes Phoenix a compiler rather than a preprocessor.

**Spans on every node, and the map.** Not a feature — the thing that decides
whether anybody but the author can use the language. Tested in
`tests/test_map.c` against positions inside tokens, not only at their starts.

**A grammar declared per module.** `@infix`, `@infixr`, `@prefix`. Operators
first because a precedence table composes: adding one cannot change what an
expression that does not use it already meant.

**A build that takes nothing from Solveig.** No header, no archive, no symbol.
The coupling is a file format and a command line.

## Next — what a hole may ask for

**Every hole takes an expression, and cannot say otherwise.**

```
@syntax while <test> do <body> => { test }:whileTrue({ body }).
```

`test` wants something that answers a boolean and `body` wants something worth
running, and neither can say so. A use that gets it wrong expands into Solveig
that fails somewhere further down — which is the failure the spans and the trail
were built to stop, one level up from where they stop it now.

| | |
| --- | --- |
| What a hole may ask for | An expression, a block, a name, a literal. `<body: block>` is the obvious spelling. The useful part is not the check but the message: *`while` wants a block here* beats an error inside the expansion. |
| Whether a hole may ask for a *place* | `swap <a> and <b>` assigns to both, and gets `this cannot be assigned to` after expansion with a trail. Asking at the use is better, and it is the same information the expander already computes afterwards. |
| Whether asking is optional | It has to be. A form that says nothing about its holes must keep working, or every dialect written so far breaks. |

**Then a handful of named predicates** — `place`, `literal`, `block`, `name` —
decidable by looking at what was parsed, needing no evaluator, and between them
probably covering most of what a guard would have been used for.

**Optional and repeated parts.** `if <c> then <a> else <b>` is a second
declaration rather than an optional tail, which is honest and costs a line.
Repetition — a form taking a list — has no spelling at all, and wants one before
anybody writes `sum of <a> <b> <c>` three times.

**Beyond a hole's type is a guard, and the evaluator it needs is Solveig.**
`solum/embed.h` was built for it — one of the three cases it names is *a tool
scripted in Solum* — and `embed/host.c` already wrote the loop: compile one
script once, run it many times, each under its own allowance. Compile the guard
once, run it per use, and `serve_one` becomes `check_one`.

It costs *the build needs no Solveig*, which is real. It does not cost *no
privileged access*, which is the claim that matters: `embed.h` is a declared
surface, and using it is the mirror of solveig-sdl using `extend.h`. **The rule
to fix before any of it is written: a guard validates, it does not select** —
otherwise parsing depends on evaluation and no tool can read a `.phx` without
running it. [rules-and-logic.md](rules-and-logic.md) argues all of it.

## Answered — two dialects meeting

Done in 0.4.0. The three questions this section used to ask, and what they came
out as:

| | |
| --- | --- |
| Can two imported dialects declare the same operator? | Yes. The later wins and the compiler warns, which is Solveig's answer for two files claiming one global. A warning rather than an error, because rebinding is legal and sometimes meant. |
| Is a dialect a value or a name? | A path, like `@include`. Unversioned, and found on a search path. |
| What does a tool see? | `@use` at the top of the file, naming a file. Still nothing to run. |

Racket answers it with modules and scoped bindings and it was worth reading how,
but the answer taken is Solveig's — because Solveig had already made the choice
for globals, and a language should not hold two philosophies about one question.

**`@language` still records a name and acts on nothing.** It is now the only
directive that does, and what it should select is the *reader* — the same shape
as selecting an emitter, in [targets.md](targets.md). Neither is worth doing
until there is a second of either.

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
