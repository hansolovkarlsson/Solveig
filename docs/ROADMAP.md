# Roadmap

What 0.1.0 established, in the order the rest depends on it. Each entry says
what would have to be true before the next one is worth starting.

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

## Next — the expander

The point of the project, and the first thing that makes `introduced_by` and
`scope` carry anything.

**1. A statement form a module can declare.** Something in the shape of
`@syntax unless (test) (body) => test:not:ifTrue(body).` — a pattern over the
core tree, and a template. The hard part is not the rewrite; it is that the
template's names have to mean what they meant where the template was written.

**2. Hygiene, in the same commit.** Scope sets, per Flatt. Not after: a system
that expands without hygiene grows programs that depend on the capture, and
those programs are what make hygiene impossible to add. `scope` is on every node
already so that this is a change to the expander and to nothing else.

**3. Expansion trails in diagnostics.** `introduced_by` filled in, and an error
inside an expansion reporting both the form and the use — *in the expansion of
`unless`, from here*. Without this, step 1 makes the language worse.

Nothing about a dialect being shareable belongs in this stage. One file, its own
header, its own macros.

## After that — the open question

**Two dialects meeting.** Today nothing collides, because a dialect is a file's
header and there is no way to import one. `@language` records a name and acts on
nothing, which is honest for now and stops being honest the moment a library can
publish a dialect.

Before writing any of it: read how Racket does it. Modules and scoped bindings
are a worked answer to exactly this, arrived at over twenty years, and a
different answer should be different on purpose.

The shape of the question, in the order it has to be answered:

| | |
| --- | --- |
| Can two imported dialects declare the same operator? | If yes, which wins, and can the file say? If no, a program can be broken by a library it does not use directly. |
| Is a dialect a value or a name? | A name is simpler and makes a dialect unversioned. |
| What does a tool see? | The reason `@language` is at the top of the file: whatever the answer is, it has to be findable without running anything. |

## Not planned, and why

**A dialect that changes the lexer.** The line between a fixed token stream and
a declared grammar is where this design sits. An extensible grammar over fixed
tokens can still be parsed by something that has not run the file's own
declarations, and every editor, formatter and `grep` downstream depends on that.
Forth and TeX moved the line and became languages no tool can read without
executing them. If it moves, it moves at the module boundary and nowhere else.

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
