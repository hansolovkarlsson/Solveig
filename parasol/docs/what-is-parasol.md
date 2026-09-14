# What Parasol is

Asked on 2026-09-02, with 0.9.0 in and three programs written. Five questions in
one session, kept **as they were asked and answered** rather than rewritten,
because the explanation landed and nothing in `docs/` was doing the same job:
[GRAMMAR.md](GRAMMAR.md) says what the syntax is, [ROADMAP.md](ROADMAP.md) says
what is left, and neither says how the parts fit together.

It is a transcript, so it is in the first person and it is dated. The four
pipeline diagrams that came out of the last question are in
[pipeline.html](pipeline.html) — the master pipeline, lockstep pattern matching,
where a span comes from during expansion, and one generated line with two
origins.

---

## 1 · What is next?

> what's next todo?

Working tree is clean, 0.9.0, three programs in. Here's what the documents
actually leave open, ranked:

**1. Constant folding in templates — the only item with a number behind it.**
`programs/digest` measured it: a form gives back 98% of what it saves (2.03
instructions saved per rotation, 2.00 spent on the unfolded `#32:sub(#17)`), so
*a form is a method that costs nothing at run time* is currently false, and
folding would win 5.4% on that program. But the roadmap is explicit that the
next step here is **a rule, not a patch**: which sends may be evaluated at expand
time, and who is allowed to have redefined them — `integer:sub` is a slot a
Solveig program may assign. That's the same question `rules-and-logic.md` asks
about guards, one size smaller, and it belongs in that file before any code.

**2. `@language`, inert for nine versions.** The only directive that acts on
nothing, while every `.psol` writes it as a ritual — in the directive the README
uses to argue a tool can tell what language a file is in. Select the reader,
select the emitter, or delete it. The roadmap flags it as *a decision, and not
one to take unasked* — so it's yours, and it's the cheapest thing on the page
once you've made it.

**3. A dialect that ends at its domain and can't say where.** `digest`'s `+` is
modulo 2³² — right for every line of SHA-256, a trap for the loop counter beside
it, so those lines are written with sends and a comment. One program is an
anecdote; a second with a domain-shaped dialect makes it a pattern. Nothing to
build yet.

**Not next:** optional and repeated parts — declined twice, the second time with
a reason (`grammar` wanted repetition and a repeated part wouldn't have helped,
the repetition being in the object language). It sits below whatever the next
program finds. Postfix operators: no customer blocked.

**My recommendation:** write the decision for folding into `rules-and-logic.md`
first — it's the only open item where the case is already made and the
measurement already exists, and the rule is reusable for guards later. If you'd
rather keep the method that has actually been finding things — 11 defects, only
2 from tests, 3 from writing programs — then a fourth program with a domain
dialect settles item 3 and probably finds the next feature the way `ember` found
`/\`.

Two standing items that need you rather than me: the three open Solveig findings
in `docs/solveig-notes.md` (output/error ordering, `--source-name`, an
instruction count) are logged in liftable shape but nobody has taken them; and
Parasol still isn't linked from Solveig — the hold expired 2026-08-31, so that's
now just your call.

---

## 2 · How does it work?

> So exactly how does it work? Parasol runs the rules on the code and replaces the
> parts that matches?

Roughly yes — but the order matters, and it's the thing the design is built
around: **the rules don't scan finished code looking for matches. They change how
the file parses in the first place.**

### The pipeline

`parasol/cmd/main.c:123-173`, in order:

1. **Read the header.** Every `@infix`/`@prefix`/`@syntax`/`@use` at the top of
   the file builds a `ParasolDialect` — a precedence table and a form table
   (`parasol/src/dialect.c`).
2. **Parse the body under that dialect.** The parser consults the table as it
   goes. `parasol/src/reader.c` has holes at exactly three places (`infix`,
   `unary`, `form` in `docs/GRAMMAR.md:22-38`); everything else in the grammar is
   fixed for every `.psol` there will ever be.
3. **Expand.** The tree now has a `PARASOL_NODE_MACRO` at every use of a declared
   form. `parasol_expand` (`parasol/src/expand.c`) replaces each one with an instance
   of its template, in place.
4. **Emit Solveig source**, plus a `.sol.map`.

So the "matching" happens in step 2 — during parsing — and the "replacing" in
step 3, over a tree that already knows which declaration each use matched.
There's no rewrite-and-rescan loop over text.

### How a use is recognised

Two mechanisms, and they're different:

**Operators** are just a precedence table. `@infix + 60 add.` means the `infix`
loop knows `+` binds at 60 and produces `a:add(b)`. Adding an operator can't
change what an expression without it already meant — that's why operators came
first.

**Forms** are names the header declared, and a declared form wins over anything
else the name could be (`reader.c:1022`). A name the header *didn't* declare is
whatever Solveig says it is — `f(x)` is `x:f` until some line above says
otherwise. Two shapes: a call `unless(test, body)`, or a pattern
`if <c> then <a>`.

Pattern matching is the interesting half. All the forms under one word are
matched **at once, in lockstep**, candidates dropping out as the tokens come in
(`reader.c:837-941`) — no backtracking. Two forms can only part company *on a
word*, which is why `if <c> then <a>` and `if <c> then <a> else <b>` coexist with
nothing declaring which is meant: after the second hole, the next token is either
`else` or it isn't. That single property is also why the roadmap's optional-parts
item insists an optional part must begin with a word.

### What expansion actually does

Three things at once (`parasol/include/parasol/expand.h`), because doing any later
means redoing the others:

- **substitution** — the argument is copied in *keeping its own spans*, so an
  error inside an argument points at the argument, not the template;
- **hygiene** — every name the template binds is renamed to one nothing in the
  module uses;
- **provenance** — each produced node remembers the use that produced it, so a
  diagnostic can print the trail.

You can see all three in `examples/forms.psol` → `examples/forms.sol`:

```
swap t and u          ->  { | t__1 | t__1 := t. t := u. u := t__1 }:value.
```

The template binds `t`; the caller also has a `t`. Without the rename that swap
loses a value instead of swapping.

And the reason a form isn't just a method: **its arguments arrive unevaluated.**
`unless(x > #5, y:print)` hands `y:print` over as *code*, and the braces in
`test:not:ifTrue({ body })` are the template's doing. A method can't do that —
which is exactly why `@infix && 30 and.` produces `a:and(b)` and a run-time
refusal, and templates exist.

### Two properties that fall out

**Expansion terminates without a counter.** A template is read under the header
as it stood at its own line, so it can only mention forms declared above it — the
highest form index strictly falls. That's a property of reading the header top to
bottom, not a recursion limit bolted on.

**Parsing never runs anything.** A tool can read any `.psol` top to bottom and
know its syntax. That's the line `docs/ROADMAP.md` refuses to cross ("Not
planned: a dialect that changes the lexer"), and it's the same rule constraining
the two open items I mentioned earlier — a guard must validate and not select,
and constant folding would mean evaluating a send at expand time.

---

## 3 · Would a different body language clash differently?

> So depending on what language is in the body, different pattern works better or
> worse dependig on what they define? For instance, the issue with | that we had
> in the past, which clashes with the syntax of Solveig. So if the body was a
> different programming language, then the clash might not happen with the |, say
> Pascal for instance?

Good question, and it splits into two very different ones. The short answer:
**the `|` clash is a property of the *reader*, not of the body language — so a
different object language changes nothing, and a different host language would
move the clash rather than remove it.**

### Why `|` is reserved

Not because of anything the program is about. Parasol's fixed token set and core
grammar *are* Solveig's spelling, deliberately — `#3` for integers, `'sym` for
symbols, `x:msg` for sends, `{ }` for blocks, `.` between statements.
`docs/GRAMMAR.md:70` puts it as: *everything but `operator` is Solveig's own
spelling, so a file can be read by somebody who knows Solveig without a second
set of habits.*

`|` is load-bearing in that grammar — it's what separates a block's parameters
from its body, and it brackets temporaries. So `|`, `:`, `.` and `,` are not
operator characters and cannot become any. A dialect gets the characters that
mean nothing until it says so, and that set (`+ - * / < > = ! & ^ % ~ ? \`) is
fixed by the lexer, which no `.psol` can change.

### Reading 1: the body is a different language

This is `programs/ember` — a lexer, parser and **ARM64 code generator** written
in Parasol. It emits machine instructions, and that never touched Parasol's token set
once. Same with `programs/grammar`: EBNF rules live in a table as data, not as
forms.

The object language sits one level down, as data the program manipulates. It has
no vote on which characters Parasol's lexer reserves. So a Pascal compiler written
in Parasol would still not be able to declare `|`.

`programs/grammar` is actually the sharpest evidence here: it was written to
settle whether repeated pattern parts were needed, and the finding was that **a
grammar can't be written as forms at all** — a template can't declare a form — so
the repetition it wanted was in the object language, where Parasol's syntax doesn't
reach.

### Reading 2: Parasol emits Pascal instead of Solveig

*Now* the question is real, and it's exactly the unbuilt half of `@language`.
`docs/targets.md` notes the front end knows nothing about Solveig — the lexer,
dialect table, tree, spans and map are all substrate-agnostic, and
`parasol/src/emit.c` is the only file that has ever heard of Solveig. Replacing it
is a seam, not a rewrite.

But swapping *only* the emitter wouldn't free `|`, because `|` is the reader's
constraint, not the emitter's. You'd still be reading Solveig-shaped source and
writing Pascal out the back. That's precisely why targets.md says the growth is
for `@language` to choose **the reader *and* the emitter** — and why the roadmap
files it as a decision rather than a build.

If you did swap the reader for a Pascal-shaped one, then yes: `|` becomes free,
since Pascal doesn't use it. But the budget doesn't get bigger, it gets
redistributed. Pascal would reserve `;` as its separator, `..` for ranges,
`(* *)` for comments, and `^` for pointers — and `^` is currently a *free*
operator character a Parasol dialect can claim today. `..` would be worse than a
swap: `.` isn't an operator character, so a range operator would need a lexer
case rather than a declaration, which is the shape of the `@token` request that
was refused in 0.9.0.

### The rule that survives both readings

Whatever the host, some characters are load-bearing for the reader and can't be
declarable — otherwise you're across the line where a tool has to run a file to
tokenise it, which is where Forth and TeX ended up.

Which is why the answer to the `|` want wasn't to make `|` claimable. It was
`||`: a new token taken by the lexer before the bar, belonging to every dialect
rather than to any declaration. Grow the fixed vocabulary rather than make the
vocabulary declarable — and the roadmap says explicitly that's the shape any
future version of that request should take.

---

## 4 · The process, end to end

> Explain to me the process and steps how Parasol works. I'm still confounded by
> how things tie together.

Let me trace one real file all the way through. I compiled this just now:

```
; trace.psol
@language solveig.
@use "control.psol".

n := #3.
total := #0.
while n > #0 do (total := total + n. n := n - #1).
if total > #5 then total:print else "small":print.
```

### Step 0 — a file is two halves

`module = { directive } { statement }`. Every `@`-directive comes first, then the
code. That split is the whole architecture: **the top of the file decides how the
bottom of it parses.** Nothing after the first statement can change the syntax.

(`@include` is the exception that proves it — it's Solveig's own directive, so
Parasol treats it as a *statement* and passes it through.)

### Step 1 — gather the files

`parasol_unit_read` loads `trace.psol`. The `@use "control.psol"` pulls in
`lib/control.psol`, which itself does `@use "arith.psol"`. Each file is read
**once** — a diamond costs nothing — and they all live in one `ParasolUnit` with a
single shared offset space. That last detail matters in step 5.

A dialect file is directives and nothing else. A statement in one is an error.

### Step 2 — the header builds two tables

Reading top to bottom, the directives fill a `ParasolDialect`:

| from | table | entry |
|---|---|---|
| `@infix + 60 add.` | precedence table | `+`, binds at 60, becomes `:add` |
| `@infix > 40 greaterThan.` | precedence table | `>`, binds at 40, becomes `:greaterThan` |
| `@syntax while <t> do <b> => { t }:whileTrue({ b }).` | form table | word `while`, holes `t` and `b`, plus the template |
| `@syntax if <c> then <a> => …` | form table | word `if`, two parts |
| `@syntax if <c> then <a> else <b> => …` | form table | word `if`, three parts |

Two `if` forms under one word, and nothing declares which is meant. That's fine,
and step 3 says why.

**These tables are all that varies.** Everything else — `#3`, `'sym`,
`x:msg(y)`, `{ }`, `.` between statements — is fixed for every `.psol` there will
ever be.

### Step 3 — parse the body, consulting the tables

The parser has exactly three holes in it (`infix`, `unary`, `form`) and the
dialect fills them.

Hits `while`. The header declared it, and **a declared form beats anything else
that name could be** — otherwise `while` would just be an ordinary identifier.
Now it matches the pattern, and this is the part worth being precise about:

> All the forms under that word advance **in lockstep**, candidates dropping out
> as tokens arrive. No backtracking.

At `if`, both candidates are alive through `<c> then <a>`. Then one token
decides: `else` keeps the long form and kills the short one; anything else does
the reverse. That's why two forms can only part company *on a word* — and it's
why the roadmap's optional-parts item insists an optional part must begin with
one.

What comes out is a tree with an unexpanded `MACRO` node at each use, tagged with
which declaration matched. `n > #0` inside it is already parsed as
`n:greaterThan(#0)` — operators resolve here, in the same pass.

### Step 4 — expand

`parasol_expand` replaces each `MACRO` with its template. Run `--tree` on that file
and you can see all three things it does at once:

```
send whileTrue @1178+9 scope:1 from:while      <- template's span, in control.psol
  block @1172+1 scope:1 from:while
    send greaterThan @70+1                     <- argument's own span, in trace.psol
      name n @68+1
```

- **substitution** — `{ t }` became a block wrapping `n:greaterThan(#0)`, and
  that subtree kept offset `@70`, its position *in trace.psol*. An error inside an
  argument points at the argument, not at the library.
- **hygiene** — `scope:1` and `scope:2` are the two expansions. Any name the
  template binds gets renamed per scope; that's how `swap t and u` emits `t__1`
  instead of destroying the caller's `t`.
- **provenance** — `from:while` on every produced node, so a diagnostic can say
  which form you're inside and where it was written.

And it terminates without a counter: a template is read under the header **as it
stood at its own line**, so it can only mention forms declared above it. The
highest form index strictly falls. That's a consequence of reading the header top
to bottom, not a recursion limit.

### Step 5 — emit, and the map

Only `parasol/src/emit.c` has ever heard of Solveig. It walks the expanded tree and
prints:

```
n := #3.
total := #0.
{ n:greaterThan(#0) }:whileTrue({ (total := total:add(n). n := n:sub(#1)) }).
total:greaterThan(#5):ifElse({ total:print }, { "small":print }).
```

Alongside it, `--map` writes what those spans were for:

```
5:1   24:40  1172  lib/control.psol     <- the whileTrue came from the template
5:3   6:7    68                        <- the condition came from your line 6
```

Generated line 5 has two origins on one line, and the map knows which is which.
**That's the payback for carrying spans through expansion** — without it,
generated code is where the trail goes cold.

Then Solveig takes over, and Parasol is done:

```sh
parasol trace.psol -o trace.sol --map
solas trace.sol -o trace.sob
solvm trace.sob
```

### What ties it together

Three invariants, and every design decision on the roadmap is downstream of one
of them:

**The header is the only thing that varies, and it is read, never run.** Any tool
can tokenise and parse any `.psol` top to bottom. This is what the refused
`@token` directive would have cost, and it's why a guard must validate rather
than select — if a guard could *choose* a parse, reading a file would require
evaluating it.

**Matching happens while parsing, not afterwards.** There's no scan-and-rewrite
pass over finished code. That's what buys single-token decisions and no
backtracking — and what makes *choosing the wrong shape silent*, since a pattern
where a call was meant is also a legal parse.

**Expansion is one pass, and it carries the provenance out with it.** Hygiene
went in the same commit as forms rather than after, because a system that expands
without it grows programs that depend on the capture.

---

## 5 · Is it a precompiler?

> So is it fair to say that in a way Parasol is a very flexible and smart
> precompiler?

**"Smart precompiler" gets the position right and the mechanism wrong.** Parasol
does sit where a precompiler sits — runs before the real compiler, emits source,
never runs your program. But `cpp` and `m4` substitute over *tokens or text*,
with no grammar and no tree, which is why `cpp` can happily emit something that
won't parse. Parasol's matching happens *inside* the parser, and expansion operates
on a tree that already parsed. It's a **hygienic syntax-macro system whose
extension point is the grammar** — closer to `syntax-rules` or `macro_rules!`
than to `#define`. The line it deliberately won't cross is Lisp's: no code runs
at expand time.

|  | a preprocessor (cpp, m4) | Parasol |
| --- | --- | --- |
| operates on | tokens or text, with no grammar | a tree, matched inside the parser |
| bad output | can emit something that will not parse | cannot — expansion is over a parse that succeeded |
| capture | none; `SWAP` eats your `t` | every template-bound name renamed per expansion |
| positions | `#line`, by hand | a span on every node, and a map |
| extension point | a substitution | the grammar itself — precedence and pattern shape |

The nearer relatives are `syntax-rules`, `macro_rules!` and Dylan — hygienic
syntax macros. The line Parasol keeps that Lisp does not is that **nothing runs at
expand time**. A template is a pattern and a tree, never a computation. That
single restriction is what the two hardest open questions are both about:
whether a guard may evaluate anything (it may not, or parsing would depend on
running the file), and whether the expander may fold `#32:sub(#17)` when
`integer:sub` is a slot a program may reassign.

It is also worth saying that Parasol is not "very flexible" in the unbounded sense,
and that this is the point. The lexer is fixed, the core grammar is fixed, there
are three holes and no more, a rule may not begin with a nonterminal, and nothing
evaluates. The flexibility is inside a fence, and the fence is what lets any tool
read a `.psol` without running it.
