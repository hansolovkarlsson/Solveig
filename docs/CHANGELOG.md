# Changelog

Notable changes to Proto, newest first.

Each entry names the commit it landed in. Dates are the day the work was done.
What is still outstanding is in [ROADMAP.md](ROADMAP.md); the case for each
piece of work as it was argued *before* the work is in
[COMPLETED.md](COMPLETED.md); what a day actually consisted of is in
[journal.md](journal.md).

---

### `programs/prose` — 2026-09-02

**The fifth program, and the one [does-it-pay.md](does-it-pay.md) asked for.**
A document language, with the document itself written in the dialect and
rendered to text — the first program here whose dialect writes the **data**
rather than the processing.

**26 lines of document, 36 lines of renderer.** The dialect reaches 26 of 64
lines and none of the rest. Even in the most content-heavy program that could be
written, the code is larger than the content.

**It found no third category.** It was picked as a domain that was neither
arithmetic nor instructions, to see whether *steps want forms, values want
operators* had a case outside it. `prose.pro` declares **no operators and seven
forms** — `ember`'s and `grammar`'s shape exactly. A document is a domain of
steps.

**It moved the ceiling down a level, and one prediction was wrong.** Nesting
was predicted to be the wall, on `grammar`'s finding that a rule cannot be a
form. It is not: a form takes a **block**, a block holds statements, and
statements are content forms, so `indent { … }` nests to any depth and
Solveig's braces carry the structure. `grammar`'s wall was narrower than
*nesting* — a template cannot **declare** a form, and a grammar's rules are
definitions. What a form still cannot do is contain part of a line:

> **A form can contain content. A form cannot contain half a line.**

Which is the answer to *could Proto do a markup language*: the block structure
yes, the inline structure no, and not by any arrangement of words and holes.

**And it split "carrying a rule" in two.** `indent { … }` cannot be left
unbalanced — but the dialect did not invent that rule, it borrowed one Solveig
already enforces. `sha2.pro` invented its own; nothing in Solveig makes `+` mask
to 2³². **Only the invented kind is evidence that a declared grammar does
something a fixed one cannot**, and it is still the one clear instance in five
programs.

**Unpredicted, and it reverses an answer given the same morning.**
`lib/arith.pro` has no `<=`, and the renderer wanted one — it writes
`while i < doc:size + #1` instead. Asked hours earlier whether arith should be
completed, the answer was no, on the evidence that `<=`, `>=` and `!=` had *no
customer at all*. This is the customer. One is still not enough, and
[ROADMAP.md](ROADMAP.md) records it so the second settles it.

### `|` can be declared after all — a retraction — 2026-09-02

**No version, and nothing in the compiler changed.** Three documents said
something that is not true, and now say what is.

`README.md`, `proto/src/lex.c` and [COMPLETED.md](COMPLETED.md) 12 all held, in
nearly the same words, that a dialect cannot declare `|` because `{ a | b }`
would then have two readings. Entry 12 put it as *"naming the ambiguity does not
decide it"*. **A rule decides it**, and Proto had the mechanism: a block reads
its parameters and temporaries first, so `{ a | b }` is a parameter and a body
*by rule*, a declared `|` is an operator everywhere a block is not reading a bar
of its own, and `{ (a) | b }` escapes — which is `#[(b = c) = d]` in a different
bracket, landed in 0.12.0 **four hours earlier**.

**Two questions had been run together and given one answer.** *May `|` join the
operator characters?* — no, and that stands: characters in that set run
together, so a `|` there would make `|=` a spelling and `{ a | b }` a guess.
*May `|` be declared?* — a different question, since a bar is a token of its own
and a parser may look one up without it entering the set at all.

**Demonstrated rather than argued**, by a second session: two hunks in
`reader.c`, no change to the lexer, the suite green and every block form intact.
Reverted rather than kept — it arrived uncommitted in a shared checkout, and
what it costs had not been looked at. [ROADMAP.md](ROADMAP.md) is that looking,
including the reason not to hurry: 0.13.0 has just settled the repository on one
spelling per operation with `\` for bitwise or *because* `|` was unavailable,
and **a spelling should be changed once.**

**And the cause was misattributed in both directions.** The entry blamed the
ambiguity and stopped; the session that built it reported removing *Solveig's*
constraint and had removed nothing of Solveig's — Solveig has the identical
`{ a | b }` and settles it the identical way. What stands in the way of `|` is
**Proto's own block syntax**. [POSTMORTEM.md](POSTMORTEM.md) 18.

### Seven templates that Solveig already had messages for — 2026-09-02

**No version, and nothing in the compiler changed.** Two dialect files were
writing out sends that Solveig provides directly.

| was | is |
| --- | --- |
| `@infix != … => left:equals(right):not.` | `notEquals` |
| `@infix <= … => left:greaterThan(right):not.` | `lessOrEqual` |
| `@infix >= … => left:lessThan(right):not.` | `greaterOrEqual` |
| `@prefix ! => operand:not.` | `not` |

Six in `lib/clike.pro` and `programs/digest/sha2.pro`, plus the prefix, which
`lib/arith.pro` had been spelling as a plain message all along.

**Asked as a question about whether `lib/arith.pro` should be completed**, and
the answer to that was no — see below — but the neighbourhood turned this up.

**It reads better and costs less.** The generated Solveig says what it means:

```
n:equals(#9):not                ->  n:notEquals(#9)
(shift:lessThan(#0)):not        ->  shift:greaterOrEqual(#0)
{ (i:greaterThan(s:size)):not } ->  { i:lessOrEqual(s:size) }
```

`programs/digest` runs **272,398 instructions against 273,318** — 920 fewer,
0.34%, two of the four sites being loop conditions. Small, and it is the
readability that earns it: a template was standing in for a message, which is
the one thing `lib/clike.pro`'s own header says templates are not for.

**Checked for a correctness difference and there is none.** `<=` as
`not (a > b)` and `a:lessOrEqual(b)` could disagree on a partial order, so NaN
was the case to try: Solveig answers `true` to both. This is a simplification
rather than a fix.

**What is left in `lib/clike.pro` is three templates, and each is one a message
cannot be**: `=`, because assignment is not a send, and `&&` and `||`, because
their right side has to arrive in a block or it is evaluated whether or not it
is wanted.

**And the question that prompted it: no, `lib/arith.pro` should not be
completed.** Bitwise has one usable customer, not two — `examples/utf8.pro`
could share a file, and `programs/digest/sha2.pro` could not, its `<<` being
masked and the file standalone because it redefines `+`. The two also chose
different rungs for `&` (60 against 50) and `>>` (80 against 55), each against
its own neighbours, which is the per-module argument showing up as evidence.
`<=`, `>=` and `!=` have **no** customer: the two files declaring them are both
standalone, and every one of arith's five users declares no operator of its own.
*One customer, satisfied in three lines, is not a reason to grow a surface* —
and completeness is the wrong test for a dialect, which is a notation rather
than an API.

### `%1011`, and the first spelling that cost a dialect something — 0.13.0, 2026-09-02

**Binary integers**, the last of the nine differences
[POSTMORTEM.md](POSTMORTEM.md) 16 found that could be closed at all.

```
%1011           is #11
$FF08           is #65288
#-45            is #-45
```

**Solveig can give the whole `%` to the literal because it has no `%`
operator.** Its `product` is `unary { ( "*" | "/" ) unary }` and nothing else,
so `%2` there is simply an error. Proto made `%` an operator character in
0.1.0, so the two have to share, and the split is **immediately followed by a
binary digit**:

| | |
| --- | --- |
| `%1011` | a number |
| `a % #2`, `a %#2`, `a % 2`, `a %2` | the operator, unchanged |
| `a %1`, `a %10` | **the number now**, and a loud error where it stands |
| `a +%1011` | the run `+%` is one operator; only a leading `%` starts a literal |

**No declaration is consulted**, so a tool can still tokenise any `.pro` knowing
nothing about its dialect. That is the line that matters and it has not moved.

**What it cost, which is worth naming as a shape.** `||` in 0.9.0 grew the fixed
vocabulary and took only `{ || … }` out of the *core*, and
[COMPLETED.md](COMPLETED.md) 12 held that up as the form any future request
should take. This is the second instance and the first with a different bill:
**growing the fixed vocabulary took something from what a dialect may declare.**
A module declaring `%` can no longer write `a %1` without a space. Nothing here
does — `%` as mod is written `n % #2`, because mod wants an integer and a bare
digit is a float — and it fails loudly rather than quietly. Small, and the next
one might not be.

Six checks in `tests/test_reader.c`, one of which is the cost written down as a
rejection so that it is a decision rather than a surprise.

**Two differences left, and neither is an oversight**: `@expr` is refused, and
`-3` cannot be had while `-` is declarable.

### `#[a = b]`, and the first rule where a context outranks a declaration — 0.12.0, 2026-09-02

**Dictionary literals**, which is the eighth of the nine differences
[POSTMORTEM.md](POSTMORTEM.md) 16 found and the one that had been mis-sorted as
free.

```
#[#1 = "one", #2 = "two"]
```

**The lexer was never the obstacle.** Solveig writes `pair = sum "=" expression`
and settles what `=` means in a key by *level* — a key parses below where `=`
lives, so it cannot swallow one. Proto has no fixed levels to parse below: a
dialect may declare `=` at any precedence, and `lib/clike.pro` puts it at 10 for
assignment.

**So the rule is that a top-level `=` inside `#[…]` is the separator, whatever
the header said.** That is the first place in this language where a context
outranks a declaration, which is why it took a decision rather than a lexer
case. What keeps it a rule rather than `=` being taken away is that it stops at
the first bracket:

```
@infix = 10 => left := right.
#[k = #1]              is a pair, not an assignment

@infix = 40 equals.
#[(b = c) = d]         is  #[(b:equals(c)) = d]
```

It is a *parser* rule and not a lexer one, so nothing about reading a `.pro`
without running it has changed: `#[` is one token, taken where `#` is already
consumed, and `# [` is still the error it looks like.

**Emitted as Solveig writes it.** Proto turns every operator into a send, so a
key always reaches `solas` as a send chain or a literal — well inside the `sum`
its grammar asks for.

Nine checks in `tests/test_reader.c`, including the two halves of the rule and
the three ways to get it wrong: no `=`, a trailing comma, and a space between
`#` and `[`. Solveig refuses the trailing comma too, which is why Proto does.

**Three differences left, and one of them is the only decision:** `%1011`.
`@expr` is refused on purpose, and `-3` cannot be had while `-` is declarable.

### Four of Solveig's spellings, and one Proto had too many — 0.11.0, 2026-09-02

**Five of the nine differences [POSTMORTEM.md](POSTMORTEM.md) 16 found, now
closed.**

| | |
| --- | --- |
| `#-45` | The sign belongs to the number, which is Solveig's rule. Safe here for a reason a signed *float* is not: nothing but an integer can begin with `#`, so `-` has no second reading to be confused with. |
| `$FF08` | Hexadecimal. `$` was not an operator character or anything else. |
| `1e10`, `2.5E-3` | Float exponents, taken only when the digits are there — `2 e` is still two tokens, and `45.` is still a float and a separator. |
| `"\q"` | **Narrowed.** Solveig has five escapes; Proto took any character after a backslash. |

**An integer now travels as written.** It used to be stored without its `#` and
have one put back on the way out, which cannot survive `$FF08` or `#-45` — and
normalising `$428a2f98` to `#1116352408` would throw away the base the formula
was transcribed in, which is the only reason to write hexadecimal at all.

**The escape one is the defect rather than the gap.** Every other difference was
Proto refusing something Solveig takes, which is a smaller language and an
honest error. That one went the other way: `x := "a\qb".` compiled here and
produced a `.sol` that `solas` refused, with the error landing on generated
code. **Proto emitting invalid Solveig** is the single failure the map and the
run-every-example discipline exist to prevent, and neither caught it, because no
example has a bad escape. [POSTMORTEM.md](POSTMORTEM.md) 17.

**Four differences are left, and one of them was mis-sorted when the nine were
first written up.** `#[a = b]` was called free on the strength of the lexer. The
lexer was never the obstacle: Solveig writes `pair = sum "=" expression` and
resolves it by precedence *level*, which Proto cannot copy because a dialect may
declare `=` anywhere — `lib/clike.pro` puts it at 10. It needs a rule saying a
context shadows a declaration, which nothing here has ever allowed, so it is a
decision and joins `%1011` on [ROADMAP.md](ROADMAP.md). `@expr` stays refused,
and `-3` stays impossible while `-` is declarable.

Eleven checks in `tests/test_reader.c` hold the new spellings, including the two
that must *not* change: a name after a number, and `45.` as a float and then a
separator.

### `programs/ledger` — 2026-09-02

**The fourth program, and the first that is a value type** — a statement in
fixed-point decimal, checked against figures produced independently in exact
decimal arithmetic. Written to answer two roadmap entries, and it answers both
against the grain.

**The domain-boundary entry has its second instance, so it is a pattern.**
`digest` declares `+` as addition modulo 2³² and is trapped on its loop
counters; `ledger` declares `/` as rounding to the nearest hundredth and is
trapped taking `-1225` apart into `-12.25`, which wants floored division. Both
write those lines as sends with a comment. Two narrowings came with it: **which
operator turns traitor is not predictable from outside the domain** — this
program predicted `*` and was bitten by `/` — and the boundary is not only at
the domain's edge, since `ratio interest to subtotal` answers `0.07` where the
exact value is `0.074995…`. A ledger has amounts wanting two places and rates
wanting five, and a dialect has one scale.

**The folding entry has its second customer, and the customer argues the other
way.**

| | instructions |
| --- | ---: |
| as written | 4,258 |
| every constant folded by hand | 4,250 |
| saved | 8 — **0.19%**, against digest's 5.4% |

A dialect's constants cost per *use*, and this dialect's uses are outside the
loop: `*` and `percent` are written once and stay written once whether the
ledger has five transactions or five thousand. The case for folding rests on the
claim rather than on the number.

**And it found that Proto has one of Solveig's three integer literals.** `#-5`,
`$FF08` and `%1011` are all integers in Solveig; only the last form of the first
is one here. A ledger is the first program with an ordinary negative value.
[POSTMORTEM.md](POSTMORTEM.md) 16, and [ROADMAP.md](ROADMAP.md) for the third of
it that is a decision: `%` is an operator character, so `a %1011` would have
two readings.

Two smaller things: **one spelling may be both infix and prefix** — `@infix - 60
sub.` beside `@prefix - negated.`, so `#10 - -#5` is `#10:sub(#5:negated)` —
which nothing here had done. And **hygiene has now gone unmentioned by four
programs in a row**, which is the only evidence the 0.2.0 argument for shipping
it early could ever have.

### `make sanitize` — 2026-09-02

**A tool nobody runs is not a tool.** `SANITIZE=` has been in the Makefile since
the first commit, with the invocation written in a comment beside it, and
nothing had ever been run under it — which is how
[POSTMORTEM.md](POSTMORTEM.md) 15 stayed latent from 0.1.0 to 0.10.0.

```sh
make sanitize      # clean, then the whole suite under address + undefined
```

It cleans first, because the sanitizers have to be in every object and the tree
caches objects. It leaves an instrumented `bin/proto` behind and says so;
`make clean` restores a normal build.

**Checked by reintroducing the defect.** With `proto_dialect_add_infix` put back
the way it was before `f8b219a`, `make sanitize` exits 2 and names it —
*heap-use-after-free, reader.c:316 in directive\_operator* — and is clean with
the fix in. That is the one class of defect this suite structurally cannot catch
on its own: whether a read of freed memory is a crash is the allocator's
decision, so `tests/test_use.c` can hold the exact shape of the bug and pass.

[conventions.md](conventions.md) now carries it as a standing agreement rather
than a good intention: **before a release, and after anything that touches the
dialect tables.**

### One spelling per operation — 2026-09-02

**Nothing in the compiler changed**, and no version with it. This is the shipped
dialects agreeing with each other.

`\/` had been doing two jobs: logical *or* in `lib/arith.pro` at precedence 25,
and bitwise *or* in `examples/utf8.pro` at 50 and `programs/digest/sha2.pro` at
40. `~` had been doing two as well — logical *not* in arith, bitwise *not* in
sha2, which is C's meaning. A reader had to know which file they were in before
they could read a line.

| | logical | bitwise |
| --- | --- | --- |
| and | `&&` | `&` |
| or | `\|\|` | `\` |
| not | `!` | `~` |
| xor | — | `^` |

**C's table, with one substitution: `\` where C writes `|`.** That is the one
character a dialect can never have, `|` being what separates a block's
parameters from its body — so the single irregularity left is forced by the
design rather than chosen, and points at the constraint instead of hiding it.
`\` was already an operator character; it needed nothing added.

**The language is untouched.** `/\` and `\/` lex and declare exactly as before,
and a module that prefers them may still say so. What changed is this
repository's usage. `lib/arith.pro` and `lib/clike.pro` now spell the logical
operators identically, so clike's stated reason for standing alone is restated
around what actually still distinguishes it: `=` for assignment, `!=`/`<=`/`>=`,
and control flow with C's parentheses and braces.

**Checked rather than assumed:** every generated `.sol` in the tree is
byte-identical across the change — the messages are the same, only the source
spelling moved — and the suite reports the same 58, 6, 34 and 11 checks. A
side effect worth naming: `programs/digest/sha2.pro` beside `lib/control.pro`
now collides on seven operators rather than nine, `~` and `\/` having stopped
overlapping. Counting them is what turned up
[POSTMORTEM.md](POSTMORTEM.md) 15.

### A use-after-free composing two dialects — 2026-09-02

**`proto` segfaulted on `@use "sha2.pro"` beside `lib/control.pro`** — two real
dialects in this repository, composed the way the collision rules exist to
allow. Latent since 0.1.0.

`proto_dialect_add_infix` answers the entry a redeclaration displaced, so the
reader can say *previously declared here*. It looked that entry up **before**
growing the array, and `realloc` may move the block — so the caller read
`clash->spelling` out of freed memory. `add_prefix` and `add_macro` had it too;
`add_template` did not, answering no pointer. The lookup now happens after the
growth: realloc changes where the entries are, never what they say.

**It needed a collision, a growth, and a relocating realloc in the same call**,
which is why nine versions and three programs missed it — all three compose
dialects that agree. `tests/test_use.c` gains the shape, and is honest that it
guards only under `make test SANITIZE="-fsanitize=address"`: whether a stale
pointer lands on freed memory is the allocator's business, and in that process it
does not. **The suite is now clean under `-fsanitize=address,undefined`**, an
invocation the Makefile has documented since 0.1.0 and which nothing had been run
under. [POSTMORTEM.md](POSTMORTEM.md) 15.

### `@language`, removed — 0.10.0, 2026-09-02

**The only directive that did nothing, gone.** It parsed, recorded a name in
`ProtoDialect`, and nothing ever read it back. It was optional, ignored and
written by every `.pro` in the tree, which is a ritual rather than a feature.

**It was removed rather than made to act on something.** The roadmap had wanted
it to select a reader or an emitter for nine versions, and neither exists to be
selected. The near-miss option was to make it *assert* — one reader, one
emitter, any other name an error — and that was rejected because it prices the
change without asking whether the directive is right:

> `@language solveig.` at the top of `examples/forms.pro` says the body below is
> Solveig. That file declares `+`, `<`, `>`, `unless`, `while` and `swap`. Its
> body is not Solveig and Solveig cannot read it.

The reading under which the line was true — *the substrate is Solveig* — is the
same for every `.pro` and is already carried by the extension. The thing that
could differ between two files is the output, and the word for that is
`@target`, which is what gets added if a second emitter is ever built.
COMPLETED.md 14 carries the whole argument; [targets.md](targets.md) is amended
where it used to argue the other way.

| | |
| --- | --- |
| the header now takes | `@use`, `@infix`, `@infixr`, `@prefix`, `@syntax` |
| an old file gets | `'@language' is not a directive Proto knows`, and a note naming the five |
| `ProtoDialect` loses | `name` and `declared_at` |

**Nothing else in the language changed.** The suite reports the same 58, 6, 34
and 10 checks over the same ten examples and programs. `tests/test_map.c` needed
its line-number comments renumbered and nothing else: a directive emits nothing,
so dropping a header line moves no generated line.

### Phoenix is Proto — 2026-09-01

**No version, and nothing in the language changed.** The compiler, the library,
the headers, the repository and the source extension are spelled differently and
do the same things in the same order: the suite reports the same 58, 6, 34 and
10 checks over the same ten examples and programs it reported the day before.

**The name was already promised elsewhere.** Solveig's `docs/ideas.md` has held
it since 2026-08-28 for a deferred idea — *a second language whose output Solum
uses* — closing that entry with *the name, should it happen, is Phoenix*. That
language is not this one: it would earn its place by publishing a **library**
Solum consumes, and the entry explicitly refuses *a nicer skin on this one*.
Proto emits a program's source and always has. Until today the word named both,
and the one that had shipped was holding it.

The scheme the code already had is kept, and only respelled:

| | |
| --- | --- |
| `PhxToken` | `ProtoToken` |
| `phx_lex_init` | `proto_lex_init` |
| `PHX_TOK_BAR` | `PROTO_TOK_BAR` |
| `phoenix/include/phoenix/` | `proto/include/proto/` |
| `bin/phoenix`, `libphoenix.a` | `bin/proto`, `libproto.a` |
| `PHOENIX_PATH` | `PROTO_PATH` |
| `.phx` | `.pro` |

**A module is `.pro` and not `.proto`**, which is the one choice here that is not
mechanical. `.proto` belongs to Protocol Buffers, and Linguist and most editors
would have highlighted every module in this tree as protobuf — against a README
that opens by arguing a tool can tell what language a file is in. The extension
is four characters either way, so the suffix arithmetic in `default_output_path`
is untouched.

**The replacement asserted its match**, as [conventions.md](conventions.md)
requires and as three recorded defects come from skipping. The suite
was run green *before* the rename, to compare against a number rather than an
impression; the staged diff is **1,435 lines out and 1,435 back in**, which is
the only shape a pure respelling can have; and a case-insensitive search for the
old name returns nothing outside `scratch/`, which is Hans's.

`7ccd6bc`. The repository is `hansolovkarlsson/Proto` now, and the four commits
that had been sitting unpushed since 2026-08-31 went up with it.

### `programs/digest` — 2026-08-31

**No version.** SHA-256, and the third program written in Proto. It agrees
with `shasum -a 256` on the three FIPS 180-4 vectors and five block-boundary
cases, all eight checked against an independent oracle before the expected file
was written, and its file mode is byte-identical to the system tool.

**The first customer for the operator half.** `ember` and `grammar` both leaned
on `@syntax` patterns; this is nothing but shifts, rotations, exclusive-ors and
masked additions. It was chosen because Solveig's own `programs/sha256sum` wrote
the gap down — *`@expr` has no bit operators, so the one file here that is
nothing but shifts, xors and masks is the one file that cannot use the notation
at all* — and Proto has claimed the answer to that in the abstract since
0.1.0 with nothing to point at.

**What it found**, in full in [its README](../programs/digest/README.md):

- **A dialect can carry a rule rather than a spelling.** Solveig's version needs
  twenty-three `bitAnd`s written by hand because integers trap rather than
  wrapping. This one needs none: `+` *is* addition modulo 2³², declared once in
  a header. That is new in kind — ember's and grammar's dialects only ever saved
  typing.
- **A template costs less than a method, and not much less.** Measured by binary
  search on `--steps`: 1,362,533 instructions against 1,437,417. The template
  saves 2.03 instructions per rotation by not calling, and spends 2.00
  recomputing the `#32:sub(#17)` that nothing folds. **It gives back 98% of what
  it saves**, which is now an open roadmap item with a number attached.
- **A wrong precedence is silent.** `*` declared on `+`'s rung made `at + i * #4`
  into `(at + i) * #4`; it compiled, ran, and failed as an array index four
  calls deep. The operator half's version of *choosing the shape wrongly is
  silent*.
- **The 0.4.0 collision rules got their first real customer**, and the answer was
  not to compose: `sha2.pro` beside `lib/control.pro` collides on four operators
  and the losing order hashes wrongly.

### `||`, in the fixed lexer — 0.9.0, 2026-08-31

**`|` is still the block's own and always will be; `||` is two bars and not a
bar.** The lexer takes it before the bar and hands it to every dialect, so
`lib/clike.pro` now spells C's *or* the way C spells it and the paragraph
apologising for `\/` is gone from that file.

The proposal this answers was a `@token` directive letting a file bind a
spelling to a named token. Refused: it does not decide the ambiguity that
actually blocks `|`, and a declarable token stream would make every downstream
tool implement the directive before it could lex at all. The vocabulary grew
instead of becoming declarable, which is the same answer *a dialect that changes
the lexer* has always had in [ROADMAP.md](ROADMAP.md).

`\/` keeps its job: single `|` is still unavailable, so a bitwise *or* is still
spelled that way, as `examples/utf8.pro` does. `lib/arith.pro` keeps `/\` and
`\/` by choice now rather than by force, and says so.

**What it cost**, checked by compiling it: `{ || … }` used to parse as an empty
list of temporaries and emit nothing. It is `{ | | … }` now. It appeared nowhere
in the repository, and `{ a || b }` was an error before this existed, so nothing
else changed meaning. Five checks in `test_reader.c` hold the line, one of them
on the thing that was taken away.

### The trailing-hole finding, retracted — `d90ea08`, 2026-08-31

**No version.** Two programs had reported that a form's trailing hole swallows
what follows it, and both were the same mistake: a form declared as a *pattern*
when it was an *application*. A call ends at its closing parenthesis and has no
such behaviour. Five forms in `programs/grammar/peg.pro` and one in
`programs/ember/asm.pro` moved to the call shape; the parentheses that existed
only to work around it are gone from both grammars.

The rule — *a pattern for something that reads as a step, a call for something
that reads as an application* — moved from a program's README into
[GRAMMAR.md](GRAMMAR.md), where somebody choosing a shape would look. The real
finding is that **choosing wrongly is silent**: both readings are legal, so
nothing at the declaration can warn.

### `programs/grammar` — `ec302d8`, 2026-08-31

A grammar toolkit, and the second program written in Proto. `examples/calc`
evaluates `100 / 5 - 3 * 4` with precedence; `examples/sexpr` parses
`(a (b c) d)` into nested arrays. Five predictions recorded before it was
written; three right, one right and sharper, one right about the want and wrong
about the level.

**Declined the roadmap's repetition item a second time, with a reason**: a
grammar cannot be written as forms at all, because a template cannot declare a
form, so the rules live in a table as data and the repetition wanted is one
level down in the object language.

### 0.8.0 — two holes in a row when the second is a block — `bed7b37`, 2026-08-31

`@syntax while <c> <b: block> => { c }:whileTrue(b).`, so `while (n < #20) { … }`
is a form. The ban was justified as *no boundary between them*, which was wrong;
the rule is really about **greed**, and a delimited hole has no such problem.
Could not have been relaxed before 0.6.0 gave holes kinds.

`lib/clike.pro` and `examples/clike.pro` land with it.

### A diagnostic for a pattern that read no parts — `f489359`, 2026-08-31

`@syntax vec { <x> }` got *needs `=>`* rather than the message about patterns,
because the better message only fired once a part had been read.

### `/\` and `\/`, and the fix for what that broke — `31d0ffc`, `f0af7c0`, 2026-08-31

A spelling change in `lib/arith.pro`. The first commit replaced `&&` in
`emberc.pro` with a blind global substitution and caught a shell command inside
a comment; the second fixed that and four documents that still spelled the new
operator the old way.

### 0.7.0 — an operator that stands for a template — `23f0cbe`, 2026-08-31

`@infix /\ 30 => left:and({ right }).` The only way to declare an operator whose
right-hand side must not always be evaluated — Solveig's `and` takes a block, and
an operator naming a *message* hands over an argument already evaluated.

**The two extension points did not compose and this is the seam.** `programs/ember`
is what found it.

### `programs/ember` — `e3f1288`, 2026-08-31

The first program written in Proto. A small language compiled to ARM64
assembly, all the way to a running binary. Five predictions recorded first;
three right, one did not bite, one wrong. Two things nobody predicted, one of
which became 0.7.0.

### 0.6.0 — a hole that says what it wants — `f1c8c36`, 2026-08-31

`<a: place>`, `<n: name>`, `<l: literal>`, `<b: block>`, `expression` by default.
All decided by looking at what was parsed, so none needs an evaluator.

Also fixed an infinite loop present since 0.1.0: `synchronize` halts *at* a
closing bracket without consuming it, and the statement loop read it, failed,
synchronised to it and read it again.

### The roadmap, four versions stale — `5bf83af`, 2026-08-31

Three edits to `ROADMAP.md` between 0.2.0 and 0.5.0 had silently done nothing.
The file still called the expander *next*, four versions after it shipped.

### Two design notes — `5c631b8`, `410b8e4`, 2026-08-31

[rules-and-logic.md](rules-and-logic.md): how much of EBNF `@syntax` could grow,
what it must refuse, and why a guard on a rule is the tower question rather than
a feature. Then the other half: if the evaluator is Solveig, `solum/embed.h` is
the door, and **a guard validates, it does not select.**

### 0.5.0 — a form that reads as a statement — `60e6d95`, 2026-08-31

`@syntax unless <test> then <body> => … .` Two forms may share a leading word —
`if <c> then <a>` beside `if <c> then <a> else <b>` — matched together with no
backtracking, because a hole is parsed once and shared.

### 0.4.0 — a dialect that is a file — `c63e1d2`, 2026-08-31

`@use "arith.pro".` **The collision rule, which everything was queuing behind**,
and the answer was Solveig's: the later wins and the compiler says so. A span
carries its file, which is the refactor the rest needed.

### 0.3.0 — the other half of hygiene — `8101c11`, 2026-08-31

A template's *free* references are protected: the caller's local is renamed
throughout its own frame. One pass rather than a resolver, because only
parameters and `| … |` temporaries are locals in Solveig.

### `docs/solveig-notes.md` — `ef43f60`, 2026-08-31

A running log of what Proto finds in Solveig. Two entries at the time; a third
added later recording a prediction about Solveig that was wrong.

### 0.2.0 — forms, hygiene and expansion trails — `2af48cf`, 2026-08-31

`@syntax unless(test, body) => … .` Hygiene in the same commit rather than after
it. Expansion terminates without a counter, because a template may mention only
the forms declared above it.

### `docs/targets.md` — `55dbd72`, 2026-08-31

What Proto targets, and what a program written in Proto targets — two
unrelated questions, and only the first is a Proto question.

### 0.1.0 — the first commit — `5d332a2`, 2026-08-31

A tree of Proto's own, spans on every node, the map, a grammar declared per
module, and a build that takes nothing from Solveig.
