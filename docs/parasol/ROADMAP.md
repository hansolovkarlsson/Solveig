# Parasol's roadmap

*Frozen on 2026-09-15. Its open entries were carried to
[Solveig's roadmap](../ROADMAP.md#7-parasol) that day as 7.1 to 7.10, and a
line stands where each one was; what is kept here is what was settled on this
page, the retractions and the refusals, and the plan that made Parasol a
member of the toolkit, as the record of how. Nothing is appended below this
note.*

What is still outstanding, and what has been refused. Each entry says what would
have to be true before it is worth starting.

The work that is finished is in two places: [CHANGELOG.md](CHANGELOG.md) names
what landed and the commit that carried it, and [COMPLETED.md](COMPLETED.md)
keeps the case for each piece as it was argued *before* the work — the problem,
the options, and why the shape chosen was the one taken. What went wrong on the
way is in [POSTMORTEM.md](POSTMORTEM.md); what a day consisted of is in
[journal.md](journal.md).

**Two items on this page have been declined by a customer rather than by
argument**, which is worth more than either, and one has now been **taken** by
one. See *Settled by a customer* at the foot of COMPLETED.md.

**`lib/arith.psol`'s missing `<=`, `>=` and `!=` left this page on 2026-09-02.**
It is the entry the *one customer is not enough* rule was written down against,
and how it closed is worth carrying. `programs/prose` wanted `<=` and wrote
`while i < doc:size + #1` around it; `programs/basic` wanted `<=` and `>=` five
times and `!=` four. That is **two customers for `<=` and one each for the other
two**, so the bar was met for one of three and the family went in whole.

**The rule was applied and not bent.** An arith with `<=` and no `>=` is a worse
trap than an arith with neither, the missing one being missing for no reason a
reader can see. What the case actually shows is that **a customer count is per
surface, and a comparison set is one surface** — which nothing had had to decide
before. `lib/arith.psol` carries the argument at the declarations, and both
customers were rewritten to use them the same day, which is the check that the
customers were real.

## Open, and undecided

*The version entry stood here, and was carried to [Solveig's roadmap](../ROADMAP.md#7-parasol)
as 7.1 on 2026-09-15, the day this page froze. The plan below stays, being
the record of how the move was made; what is left of it is 7.1 and 7.2 there.*

**A member of the toolkit, not a guest.** Hans's direction on 2026-09-14,
said while asking for `--sob` and held apart from it: that Parasol should in
time be a permanent member of Solveig's tools rather than an experiment
lodged in its tree. Concretely, its C source laid out as `solas/`, `solid/`
and the others are, `parasol/{cmd,include,src}` at the root instead of
`parasol/parasol/`; its documents, Makefile, examples, library and tests
folded into the tree's own, or as near to it as their jobs allow; one way to
build and to test and to install, so that working on Parasol feels like
working on the other four and using it feels like using them. The point is
as much the feeling as the layout: *not some outside experiment any more*,
in his words. **Not now**, and `--sob` was built so as not to depend on it,
which is why it runs `solas` and does not link it. The entry above is this
one's first step and its gate: the version question decides `dist` and
`install`, and those decide the Makefile, and the Makefile decides where the
sources can sit. What would have to be decided on the way, in the order they
bite: one version for the tree or two; whether `docs/programs.md`'s counts
take Parasol's documents in or keep them out, since a `docs/` file is
counted and `parasol/docs/` is not; what the `no dependencies` sentence on
Solveig's front page says once the compiler that emits its source is in the
same `make`; and whether the Makefile's first sentence, *the build needs no
Solveig*, survives as a check on a merged build, since it is the sentence
the experiment stands on and the move would be the moment it is easiest to
lose. What would fire it: the version decided, or a third contributor
finding the directory before finding the tools.

**The version was decided the same evening, and Hans asked for the order.**
Five steps, each leaving both suites green and the tree usable, each its own
day or less, and ordered by what each one needs from the one before it. The
rule for the order: **move what the checker cannot see first, and the
documents last**, because `docs/` is counted, `programs/expect.sol` runs
what is fenced there, and the documents should describe the final layout
and be written once.

1. **Version**, at the next Solveig release: `PARASOL_VERSION` becomes the
   tree's, without an include, so either a line in
   [releasing.md](../releasing.md) beside the four files or a `-D`
   from the Makefile; `PARASOL_SOLVEIG_MINIMUM` removed; `dist` removed
   here, the root's tarball of HEAD already holding `parasol/`. Small, and
   independent of the rest; it is first because the roadmap said it gates
   the Makefile, and it does.
2. **Makefile.** Parasol's rules move into the root's under a section of
   their own, paths prefixed `parasol/`; `check`, `SOLVEIG=` and `make -C
   parasol` go, since `solas` is built by the same run; one `test`, one
   `install` (`bin/parasol` beside the four, `lib/*.psol` under the same
   `PREFIX`), one `clean`. The claim the separate file kept mechanical is
   kept mechanical another way: a `PARASOL_INCLUDES` of `-Iparasol/include`
   only, `bin/parasol` linked against `libparasol.a` only, and a check in
   the suite that no file under Parasol's C source includes a `solum/`,
   `solas/`, `solis/` or `solid/` header and that `bin/parasol` exports no
   `sol_` symbol. The comment moves to the rules and says which experiment
   it is guarding. This is second because every later step is tested by the
   merged Makefile, and doing it once means every later path edit is in one
   file. **Done, 2026-09-14, the same evening.** The include check turned
   out not to need a grep: the compile rule *is* the check, since a Parasol
   object is built with Parasol's include path and no other, and a probe
   file with `#include "solum/common.h"` was seen to fail. The symbol check
   is `nm -g` over `bin/parasol` in `test`, seen to match `bin/solas` and
   not `bin/parasol`. One thing the scoping did not know: GNU make 3.81,
   which macOS ships, takes the *first* matching pattern rule rather than
   the shortest stem, so the Parasol section sits above the generic object
   rule and says why. `sanitize` and `examples` came to the root as targets
   for the whole tree; `run` and `check` went; the dialects install beside
   Solveig's library rather than under a directory of their own, so that
   step 4's *look beside the binary* finds one place. Parasol's `dist`
   went with the file, a release early.
3. **The C source and its tests.** `parasol/parasol/{cmd,include,src}` to
   `parasol/{cmd,include,src}`, laid out as `solas/` is, by `git mv`;
   `parasol/tests/*.c` to `tests/`, none of the five names colliding. One
   thing to decide there: root tests link `libsol.a` whole-archive and
   these link `libparasol.a`, so either every test links both, which is
   harmless and simplest, or the five keep a prefix or a subdirectory. A
   pure move with no checker involvement, which is why it is third and not
   fifth. **Done, 2026-09-14, the same evening.** Both halves of the
   decision, as it turned out: every test links both libraries under the
   one rule, *and* the five carry the prefix, `tests/test_parasol_reader.c`
   and so on, because a `test_map` or a `test_use` among forty Solveig
   tests would say nothing about whose map or whose `@use`. The rule
   linking both is not a hole in the boundary, which is about what
   `parasol/` is built from; a test is a check on it. The Parasol
   documents had already been naming `parasol/src/emit.c` relative to
   their own directory, and from the root those paths are simply true
   now. One defect found on the way and fixed: `test_use` removed the
   files it wrote from a hand-kept list that was seven short, so `rmdir`
   failed quietly and fifty-five of its directories were in `/tmp`; it
   reads the directory now.
4. **Examples, library and programs.** `parasol/examples/*.psol` to
   `examples/` and `parasol/lib/*.psol` to `lib/`, no names colliding; the
   root `.gitignore` learns `*.sol.map` and ember's `*.s` and `*.out` (a
   generated `.sol` beside a hand-written one is the trap here, and the
   ignore rule cannot tell them apart by name: the Makefile's `.SECONDARY`
   and a naming rule for generated files decide it). `parasol/programs/*`
   to `programs/`, where **`basic` collides** with the SolaBasic corpus
   already there and one of them is renamed, Hans's call which. With the
   library in `lib/`, `parasol` learns to look beside its own binary the
   way `solas` does, so `PARASOL_PATH` becomes what `SOLUM_PATH` is, a
   fallback rather than a requirement. [programs.md](../programs.md)
   counts `.sol` files in `programs/` and says nothing under `parasol/` is
   counted; seven directories of `.psol` arriving there is a decision for
   that page, a section of their own or a second count, and it is taken in
   step 5 with the page. **Done, 2026-09-14, the same evening.** The naming
   rule the scoping reached for was not needed: **everything `parasol`
   generates goes under `build/`**, `build/examples/` and
   `build/programs/<name>/`, which removes the trap rather than labelling
   it, and for a second reason found on the way that decided it alone:
   `programs/expect.sol` reads every `examples/*.sol` as a file of claims,
   and a generated one, whose `; #14` comments are that syntax exactly,
   would have been counted and checked as documentation. `parasol/.gitignore`
   went with it. `basic` became `minibasic`, Hans's choice of the two names
   put, the files inside renamed with the directory. `parasol` looks beside
   its own binary now, `bin/../lib` and then `PARASOL_LIB_DIR` from the
   generated `config.h`, so `@use "arith.psol"` works from anywhere in a
   checkout or an install and `PARASOL_PATH` is the override it is for
   `solas`. `docs/programs.md` says in a paragraph that the seven are there
   and not counted, ahead of step 5.
5. **Documents.** Fifteen files, six of which collide by name with the
   root's: `CHANGELOG`, `COMPLETED`, `GRAMMAR`, `journal`, `REFERENCE`,
   `ROADMAP`. Two shapes: fold each into its root counterpart (the journal
   interleaves by date, the roadmap and completed become sections, the
   changelog merges once the version is one), or keep them whole under a
   prefix or a `docs/parasol/`. The first is the one that says *member*;
   the second is cheaper and keeps `POSTMORTEM.md`, which the root does not
   have and says it should not. What every file pays on arrival:
   `docs/programs.md`'s counts move; `expect.sol` runs fenced code, and a
   `.psol` fence needs a way through, for which `parasol --sob` is now the
   obvious one, the first customer for it the day after it was built; the
   commit hashes in the changelog verify, since the history came in with
   the directory; relative links change. Also on this step: the root
   `README.md` row and `CLAUDE.md` paragraph that describe `parasol/` as a
   subproject, `editors/vscode/messages.py`, which reads
   `parasol/docs/REFERENCE.md` by path, and the published site's index.
   Last because it is the most entangled with the checker, the least in the
   way of using or developing the tool, and the step that should describe
   the layout the four before it made.

   **Scoped on 2026-09-14, after step 4, in five sub-steps**, each leaving
   the suite green. What the scoping found that the paragraph above did
   not know: Parasol's pages hold about 150 fences with no language word,
   and `expect.sol` runs every such fence as Solveig, so a page cannot
   move into `docs/` until each fence is either tagged or checkable; the
   house convention for a sub-language's pages is already set by
   `SOLABASIC.md`, `SOLABASIC-REFERENCE.md` and `SOLABASIC-CHEATSHEET.md`,
   flat in `docs/` under a prefix, where a `docs/parasol/` subdirectory
   would be read by the checker for links and for nothing else (true when
   written; since sub-step 1 the checker walks `docs/` to the bottom, and
   a subdirectory is read for everything); every one
   of Parasol's changelog hashes resolves in this history; the two
   LICENSE files are identical; and `solas/`, `solum/` hold C and nothing
   else, which is what `parasol/` becomes. And a reason to do it at all
   that step 4 supplied: forty-four links in the program READMEs and
   Parasol's own pages were left pointing at the wrong tree or at nothing
   by the move, and the suite stayed green, because none of those pages is
   one the checker reads.

   1. **The checker first.** `expect.sol` learns a `parasol` fence: the
      block goes through `parasol --sob` and `solvm`, and its `; #14`
      claims are checked as a `sol` block's are, so Parasol's examples in
      prose become claims rather than pictures. The same change makes the
      checker read every `README.md` under `programs/`, so the forty-four
      cannot happen again. Its own step because it can be built and proved
      against the pages where they are now, before any of them moves.
      **Done, 2026-09-15, `ad4e33e`.** Three things the scoping did not
      know: the five `.psol` examples carried 23 claims that `make test`
      ran and never read, and they went in with the fence, four of their
      comments in the convention the checker dropped on 2026-09-01; a
      directory subject is now walked to the bottom, which is what put the
      READMEs in the set and is what makes `extensions` check anything;
      and the pages as they stood produced 3 findings under the checker,
      not 150, because a bare fence with no claim in it is quiet. The tag
      for a Solveig block is no tag, as everywhere else in `docs/`; the
      `sol` below was never one the checker read.
   2. **The reference pages.** `REFERENCE.md`, `GRAMMAR.md` and the front
      page (`parasol/README.md`, 794 lines, with `what-is-parasol.md` read
      against it, since the two overlap and one should become the other's
      section) to `docs/PARASOL.md`, `docs/PARASOL-REFERENCE.md`,
      `docs/PARASOL-GRAMMAR.md`; every fence tagged `parasol`, `sol`, `sh`
      or `text` as it is read; the `<!--count-->` markers re-synced; the
      editor's `messages.py` repointed; the site's nav given a Parasol
      entry. The pages a user reads, first, because they are the ones that
      make the tool feel like a member. **Done, 2026-09-15.** The front
      page and `what-is-parasol.md` became one: the four questions that
      explain the tool are a section of `PARASOL.md`, *How it works, as it
      was asked*, and the first, a status answer at 0.9.0, is not, its
      items being here. `pipeline.html` went with them as
      `PARASOL-PIPELINE.html`. Thirty-three fences on the front page:
      eight `parasol`, of which one carries a claim and is checked, and
      the rest `text`, since a fragment that declares `&&` and uses `>`
      is a picture. *Why it is not a folder inside Solveig* is *Why it
      takes nothing from Solveig* now, the argument unchanged and the
      first paragraph saying where the distance went.
   3. **The essays.** `does-it-pay.md`, `second-reader.md`,
      `rules-and-logic.md`, `targets.md` under the same prefix.
      `conventions.md` is Parasol's `method.md`: the agreements that
      survive being one project (predictions before a program, a claim
      about cost measured, a new check run against the unfixed compiler
      from a clean build) go into `method.md` with their occasions, and
      the ones that were about being a separate repository are retired
      with a line saying so. **Done, 2026-09-15.** `solveig-notes.md`
      went with the essays rather than waiting for sub-step 4, as
      `PARASOL-SOLVEIG-NOTES.md`, and closing the log meant raising it:
      its four open findings are 3.23 to 3.26 on the root roadmap, each
      still reproducing, each pointing back for the account. Nine of
      `conventions.md`'s rules are sections of `method.md` and two are
      second occasions of rules already there; five were retired, named
      in the section that says so. Every link to `conventions.md` in the
      records lands on that section.
   4. **The records.** `journal.md` interleaves into the root's by date,
      each section keeping its words; `COMPLETED.md` becomes section 7 of
      the root's, `7.1` to `7.19`, numbers kept; this page's open entries
      become section 7 of the root roadmap; `CHANGELOG.md` becomes
      `docs/PARASOL-CHANGELOG.md`, closed at the version merge, with every
      later Parasol entry in the root changelog as today's already are;
      `POSTMORTEM.md` becomes `docs/PARASOL-POSTMORTEM.md`, kept whole,
      with the root `CLAUDE.md` saying it is the record of Parasol's
      defects up to the merge and that the rule against a root postmortem
      stands; `solveig-notes.md`'s open items go where they were always
      addressed to, the root roadmap or ideas, and the file is retired.
      Fourth because the records are read least and moved most carefully.
   5. **What is left in `parasol/`.** `CLAUDE.md` folds into the root's as
      a paragraph; `README.md` is gone by sub-step 2; `LICENSE` goes,
      being the root's byte for byte. `parasol/` is `cmd`, `include`,
      `src`, as `solas/` is. The memory notes and the root `README.md`
      table row say so.

   The calls that are the author's, before sub-step 2: whether the records
   fold (sub-step 4 as written) or stay whole under the prefix; and
   whether `POSTMORTEM.md` is kept at all, since the root's position is
   that predictions scored in `ideas.md` do its job. **Both made on
   2026-09-15, before sub-step 1, and neither is what sub-step 4 says
   above.** The five records (`journal`, `COMPLETED`, `ROADMAP`,
   `CHANGELOG`, `POSTMORTEM`) go whole to `docs/parasol/` and freeze
   there, each opening with a note giving the date and saying that from
   it Parasol's record is Solveig's; nothing is appended below the note
   afterwards. `CHANGELOG.md` ends at 0.17.0, which is also the version
   line, and the root's next release entry says Parasol joined there.
   `POSTMORTEM.md` freezes with the rest, its 33 entries readable and
   closed, and a Parasol defect after the freeze is scored in the root's
   `ideas.md` like any other; the root `CLAUDE.md` gets a clause saying
   the archived one was moved in and not created. Open items leave
   before the freeze, this page's to the root roadmap, and each archived
   record ends with a line saying where its open matter went. The
   checker reads `docs/parasol/` for links and fences both. Sub-step 3
   is unchanged; sub-step 5 loses `POSTMORTEM` and the interleave.

What is not in the plan: any change to what Parasol does. The driver, the
reader, the expander and the emitter are the same before and after, and the
only thing about the boundary that moves is which file states it.

*Six entries stood here after the plan: grouping `programs/` into kinds, a
logical xor, postfix operators, a hole's kind with no alternation, a
template's constants never folded, and a dialect that ends at its domain.
Carried to [Solveig's roadmap](../ROADMAP.md#7-parasol) as 7.3, 7.9, 7.9,
7.4, 7.5 and 7.6 on 2026-09-15, the day this page froze.*

## Waiting on a customer — optional and repeated parts

*The entry stood here, and was carried to [Solveig's roadmap](../ROADMAP.md#7-parasol)
as 7.7 on 2026-09-15, the day this page froze.*

### A selector built from a `name` hole

*The entry stood here, and was carried to [Solveig's roadmap](../ROADMAP.md#7-parasol)
as 7.8 on 2026-09-15, the day this page froze.*

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
[GRAMMAR.md](../PARASOL-GRAMMAR.md) under *Which shape a form should have*, which is where
somebody choosing one would look; it had been in a program's README, which is
not.

## Not planned, and why

**A dialect that changes the lexer.** The line between a fixed token stream and
a declared grammar is where this design sits. An extensible grammar over fixed
tokens can still be parsed by something that has not run the file's own
declarations, and every editor, formatter and `grep` downstream depends on that.
Forth and TeX moved the line and became languages no tool can read without
executing them. If it moves, it moves at the module boundary and nowhere else.

A `@token` directive binding a spelling to a named token was proposed against
this and refused in 0.9.0: it would not have crossed the Forth line, the header
still being read rather than run, but it crosses a nearer one — today any tool
can tokenise any `.psol` without knowing what a dialect is. The want behind it
was real and `||` answers it, by growing the fixed vocabulary rather than by
making the vocabulary declarable. That is the shape any future version of this
request should take. See COMPLETED.md 12.

**A rule that begins with a nonterminal.** Left recursion, and therefore an
expression grammar written in `@syntax`. The reader would have to guess,
ambiguity would stop being checkable by looking, and composition would stop
being safe -- and the case that motivates it is already read from the precedence
table. [rules-and-logic.md](../PARASOL-RULES-AND-LOGIC.md) argues all three.

**Emitting bytecode, or machine code.** Parasol would then own the `.sob` format
and Solum's instruction set, and reimplement what Solas already does. The one
thing it would buy — errors from Solas landing on Parasol source — the map buys
instead. [targets.md](../PARASOL-TARGETS.md) works the question through, including what a
native back end would actually cost and why a program *written in* Parasol can
already emit anything it likes. **`--sob`, since 2026-09-14, is not this**: it
runs `solas` on the `.sol` it wrote and owns nothing of the format. The
smaller cousin, linking `libsol.a` and calling `sol_compile_options` on the
emitted text, was scoped the same day and put aside, not because it is large
(forty lines) but because it would make the Makefile's first sentence false;
[COMPLETED.md](COMPLETED.md) 19 has the two side by side.

**`@expr`.** Solveig's fixed infix region is the special case of what `@infix`
generalises. Supporting both would be supporting two. Solveig drew its side of
the same line on 2026-09-14: the region is off there unless `solas --expr`
asks for it, on this sentence, and a `.psol` needs nothing.

**A signed bare number — `-3` rather than `#-3`.** Solveig's scanner gives the
sign to the number outside a `@expr` region and treats it as the operator inside
one. **Parasol can have neither half.** It has no regions, so it cannot be
context-sensitive; and it cannot simply take `-3` as a literal, because then
`a -3` stops being a subtraction in every dialect that declares `-`. A prefix
declaration is the only reading left, and `#-3` — where nothing else can begin
with `#` — is why the *integer* keeps its sign.

This is the extensible-operator line arriving from a direction nothing had come
from: not a dialect wanting to change the lexer, but **Solveig's own number
syntax being uncopyable while Parasol's operators stay declarable.** It means
*everything but `operator` is Solveig's own spelling* was never achievable, and
0.1.0 chose against it without recording that it had.
[COMPLETED.md](COMPLETED.md) 15 has the whole survey — nine differences, seven
closed across 0.11.0 to 0.13.0, and this one and `@expr` left.

## Rough edges

*The list stood here, and was carried to [Solveig's roadmap](../ROADMAP.md#7-parasol)
as 7.10 on 2026-09-15, the day this page froze.*
