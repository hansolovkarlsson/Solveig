# Changelog

Notable changes to Solveig, newest first.

Each entry names the commit it landed in. Dates are the day the work was done.
What is still outstanding is in [ROADMAP.md](ROADMAP.md).

## Unreleased

### A program written to be run by a stranger — `pending`, 2026-08-22

[examples/serve.sol](../examples/serve.sol): a CGI-shaped request handler. It
answers `/`, `/search?q=...` and `/note/<name>` from a directory of files, and
with no CGI variables set it runs seven requests through itself and prints each
response, so it is testable without a socket.

```
$ PATH_INFO=/search QUERY_STRING=q=limit ./bin/solvm examples/serve.sob
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Length: 221
...
```

**The seventh program here written to do a job, and the first whose input does
not come from whoever ran it.** That is the whole reason it exists: every other
program in `examples/` is handed its arguments by the person who started it, and
[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
is about the case where they are not. It asked four things of the language and
one of the machine.

**`fill` is the injection.** It is the natural way to build a page, it reads
well, and it inserts exactly what it is given. Nothing in the language or in
`lib/` escapes HTML — `lib/html.sol` reads entities and cannot write one — so
the escaping is in the program, and the safe twin of `fill` is the one with the
worse name.

**A template with two kinds of hole cannot be written with `fill` at all**,
since it insists the placeholders and the values come to the same number. That
check is what makes `fill` worth trusting, so the answer is not to weaken it —
and the marker-and-`split` habit that replaces it is worse, because a marker is
a string and a value can contain one. What is left is an array of pieces joined,
which has seams a value cannot add to.

**Refusing `/note/../../etc/passwd` is not string cleaning**, and the language
helps by having nothing: no path joining, no basename, nothing that normalises
`..`. The tempting wrong answer is unavailable, and what is left is to say which
names are names.

**A permission per message is not fine enough.** A CGI handler is told what it
was asked entirely through `system:environment`, which 6.32 lists among the
messages that *reveal* the machine — correctly. But the program cannot be
written without it, so a scheme that can only say yes or no to `environment`
must say yes, and has then also handed over every secret the server process
holds. 6.32 now records that: the permission a webserver cannot do without is
the one that gives away its secrets.

### A limit bounds dispatch, not work — `pending`, 2026-08-22

Running the above the way its own case would — as a guest, with an allowance —
found the edge of [6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done),
which shipped the day before. New entry
[3.7](ROADMAP.md#37-a-limit-bounds-dispatch-not-work), and a correction to two
documents that said otherwise.

A request costs 393 instructions for a note, 465 for the index and 798 for a
search, which is the number a host wants. But a step is a unit of *dispatch*,
and a primitive does all of its work between one step and the next:

| program | steps | time |
| --- | --- | --- |
| `nil:print.` | 4 | — |
| `readFile` of 64MB, then `indexOf` over all of it | **8** | 0.27s |
| the same over 256MB | **8** | 1.10s |

The count does not follow the size, because the size is not what it counts.

The memory ceiling is the same fact from the other side. It is checked in
`sol_gc_maybe_collect`, so an allocation is measured after it has been made:
under `--memory=1M` the 256MB read completes and the program is stopped at the
next instruction holding 268,450,673 live bytes. The overshoot is bounded in
time and not in size — the ceiling stops a program carrying on, not going over.

**Neither limit is undone.** A program still cannot loop forever and cannot keep
what it makes, which is what 6.33 was built for. What they do not bound is the
cost of one message, which is the number a webserver actually wants. Both ways
of fixing that — charging a primitive for what it handles, or refusing an
allocation rather than noticing it afterwards — give up something the design
currently leans on, so 3.7 records the choice rather than taking it.

`docs/design.md` said instructions were the one thing a program could not hide
from, and that the overshoot was bounded by one instruction. Both are now said
accurately. 6.33's own entry said it bounded a program's work; it bounds a
program that loops.

## 0.13.0 — 2026-08-21

**A program can be given a limit, and the machine can take it back.**

```
$ solvm --steps=100000 loop.sob
solvm: stopped: the step limit of 100000 was reached
  [loop.sol:3] in script
$ echo $?
124
```

**Limits**, set by whoever runs a program rather than by the program:
`--steps=N` for how many instructions it may execute and `--memory=N` for how
much it may hold at once, and `sol_vm_set_step_limit` / `sol_vm_set_memory_limit`
for a program embedding the machine, which is the case that wanted them. Both
are off unless asked for, so nothing about running a program from a terminal
changes.

The counter lives in the dispatch loop because nowhere else would do. The debug
hook could already stop a running program — Solid quits out of one that way —
but it is offered when the line or the frame changes, and a loop written
literally compiles to jumps, so it saw an inlined loop of three million turns
exactly once. Instructions are the one thing a program cannot hide from, and
counting them costs less than this release could measure.

**A stop is not catchable**, which is the whole of what makes it a limit.
`onError` lets it past and `ensure` does not run its cleanup, because both are
ways of running more code and the allowance for running code is what ran out.
No message reads or changes either limit. A stopped program exits **124** —
neither the 0 of finishing nor the 70 of failing, since it did not fail, it was
taken away.

**Memory is measured after a collection**, so a program is stopped for what it
is holding rather than for what it has been through: of two programs making the
same garbage under the same ceiling, only the one still keeping it is stopped.

**And one decision recorded rather than built**: whether a script should be able
to run with less than the whole machine, now that `system:run` means it can
reach all of it. That entry is
[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine),
and the case behind it — a webserver producing pages, where injection could make
untrusted input into code the server runs — is what turned the limits above from
a footnote into the half worth building first. Permissions are still open.

`.sob` files are format version 13, unchanged from 0.11.0.

### A program can be given a limit — `88a8ab4`, 2026-08-21

[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done),
built. A host may say what a program is allowed to spend before it starts it,
and take it back when it has spent it.

```
$ solvm --steps=100000 loop.sob
solvm: stopped: the step limit of 100000 was reached
  [loop.sol:3] in script
$ echo $?
124
```

From C, which is the case that wanted it:

```c
sol_vm_set_step_limit(&vm, 10000000);
sol_vm_set_memory_limit(&vm, 64 * 1024 * 1024);
if (sol_vm_run(&vm, &chunk) == SOL_STOPPED) { /* neither finished nor asked */ }
```

Both are off unless asked for, so a program run from a terminal is unchanged.

**The counter is in the dispatch loop, and had to be.** The debug hook already
existed and could already stop a running program — Solid quits out of one that
way — but it is offered when the line or the frame changes, and a loop written
literally compiles to jumps, so neither moves. Measured with a breakpoint on
the loop: an inlined loop over 3,000,000 iterations offered one stop and then
ran to completion, where a loop of calls offered one per iteration. What makes
`--trace` bearable makes the program unstoppable, so the count went where every
instruction has to pass.

It costs one post-decrement and one compare, and there is no branch asking
whether a limit was set: with none the counter starts at `UINT64_MAX` and
reaches zero five hundred years from now. Measured on a five-million-turn
inlined loop — around twenty million instructions — 0.74-0.75s with the counter
against 0.76-1.04s without. Which is not a speed-up; it is the cost being below
the noise of the measurement.

**Memory is measured after a collection**, which is the whole difficulty of a
memory limit. Before a sweep the figure counts everything the program has ever
asked for and not had taken back, so a ceiling read off it would stop a program
for litter rather than for what it holds. Going over is now a reason to collect,
and being over once that has happened is a reason to stop — so of two programs
making the same garbage under the same ceiling, only the one still holding it is
stopped.

**A stop cannot be caught.** `onError` lets it past and `ensure` does not run
its cleanup, because both are ways of running more code and the allowance for
running code is what ran out; a handler wrapped around everything would
otherwise turn the limit into a suggestion. No message reads or changes either
limit, so a program cannot find out what it was given or give itself more.

**124 rather than 70**, since the program did not fail — it was taken away.
Which is what `timeout` answers, for the same reason.

A correction found while documenting it: REFERENCE.md still said a runtime error
could not be caught, which stopped being true when `onError` landed.

### The threat model behind the safe-mode decision, and a second decision — `d518aa6`, 2026-08-21

[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine)
was recorded from the command line's point of view: a person about to run a
script somebody sent them. The case it actually came from is an **embedding** —
a webserver producing pages by running Solum, where the risk is injection, and
the one choosing the restriction is the server, protecting itself.

That moves the entry's conclusions rather than confirming them.

**The chooser is a program, not a person.** It decides once, at startup, and
runs that policy over every request for as long as it is up. So the argument
that protection must be on before anybody thinks to ask it for weakens — and
another takes over: the restriction has to be settable **from C, before the
program runs**. A `--unsafe` argument is one front end for it, not the
mechanism. If the mechanism is argv parsing, the case that asked for it cannot
use it. Which makes this partly a decision to have an embedding interface at
all, since no page currently says how to hold a `SolVM` inside another program.

**What is untrusted is the data, not the file.** The server wrote the script.
So the permission cannot attach to where the code came from, or be decided per
file — it is a property of the run.

**`system:exit` came off the dangerous list.** It sets a flag the interpreter
loop unwinds on and `sol_vm_run` answers `SOL_EXIT`, so a script that exits ends
itself and hands the decision back to its caller. A webserver stays up. Already
right, and named in the entry because it is the one an embedding would most
expect to be wrong.

### 6.33, the half that gets forgotten

The entry's quietest caveat — *it is not a sandbox, a restricted script can
still loop forever* — is an annoyance on a command line and is the whole server
in a webserver, with nothing dangerous called and no injection needed. That is
[6.33](COMPLETED.md#633-a-running-program-cannot-be-stopped-from-outside--done): a
running program cannot be stopped from outside.

Some of the mechanism turns out to exist. The VM calls `debug_hook` when it
offers a stop, and a hook may set `exiting` and `had_error` to unwind — which is
how Solid quits out of a running program. But the offer is gated on the line or
the frame changing, and a loop written literally compiles to jumps rather than
calls, so neither moves. Measured with a breakpoint on the loop:

| loop | iterations | times the host was offered a stop |
| --- | --- | --- |
| `{ ... }:whileTrue({ ... })`, one line | 3,000,000 | 1 |
| `#1:toDo(#5, step)` | 5 | 5 |

The inlined loop is offered once and then runs to completion uninterrupted. It
is the same inlining that makes `--trace` quiet on a three-hundred-thousand-turn
loop, seen from the other side: what makes the trace bearable makes the program
unstoppable. So a budget cannot be built on the debug hook — it wants a counter
in the interpreter loop itself, which is cheap but sits on the hot path.

Memory is the easier half: the collector already compares `bytes_allocated`
against `next_gc` on every allocation, so a ceiling is one more comparison at
that same place, against the live total a sweep leaves behind.

Both remain recorded rather than built.

### A decision recorded: restricting what a script may reach — `56408a7`, 2026-08-21

[6.32](ROADMAP.md#632-a-script-cannot-be-run-with-less-than-the-whole-machine),
written down rather than built. Raised by noticing what `system:run` had made
possible rather than by anything going wrong.

Everything a program can reach, it can reach. That is right for a script
somebody wrote for themselves and wrong for one that arrived from elsewhere, and
there is no way to say which this is.

The entry records three things worth deciding before any of it is built.

**Which way round the default goes is the whole question.** Safe-by-default
protects the case that matters — a script you did not write — and breaks every
existing use including this repository's own tests. The deciding question is
*who is choosing the flag*: somebody about to run a script they were sent is
exactly the person who will not think to ask for protection, which argues for
having it on before they think about it.

**"Dangerous" is two sets, not one.** The messages that *change* the machine are
the obvious half; the ones that *reveal* it are the other. Reading
`~/.ssh/id_rsa` and printing it changes nothing, and `environment` alone will
hand over a token from half the CI systems there are. A mode that only stops
writing stops the obvious half — which argues for capabilities rather than a
switch, and that is easier to start with than to retrofit.

**And it is not a sandbox**, which the entry says loudest, because "safe mode"
invites more trust than it can earn. A restricted script can still loop forever,
allocate until the machine swaps, or fill a disk through a file it is allowed to
write. It stops a script reaching for the machine; it does not make a hostile
script harmless, and anything needing that wants a container rather than a flag.
The same honesty as [3.3](ROADMAP.md#33-verification-does-not-promise-termination),
which says the verifier proves a chunk well-formed and not that it stops.

One complication found while writing it: `@include` reads files and the search
path reads the shipped library, so a mode with no reading cannot compile a
program that uses `lib/json.sol`. Reading the *program* is not the same
permission as reading *a file the program names*, and the line runs between them
rather than around `readFile`.

## 0.12.0 — 2026-08-21

**A debugger, and a program can run another program.**

```
$ solid report.sol
(solid) break report.sol:5
(solid) continue
report.sol:5  in block
(solid) locals
  amount           #30
  after            #70
```

**Solid** is the fourth program, and the last entry the roadmap held.
`bin/solid` runs a program, stops before its first line, and takes commands:
step, next, finish, continue, breakpoints, a backtrace, and the locals of a
frame **by name**. It stops where a program *breaks*, with the frames still
standing and the value that caused it still in one — which `solis --interactive`
cannot do, since that begins after the unwind and sees only globals.

The machine knows nothing about debugging: the VM offers a stop before each
instruction that begins a new line or enters a new frame, and Solid decides
whether that stop is interesting. `solum/` gained a function pointer and a
branch, and the branch costs nothing measurable — three million loop turns,
0.43s either way.

**`system:run` and `system:capture`** let a program run another program, which a
language aimed at scripting an OS could not do until now. They take an **array
of arguments rather than a command line**, and that is the decision in them: a
file called `; rm -rf ~` is a *name* when it is one string in an array, and a
sentence when it is text a shell parses. The shell is reachable and spelled out
— `["/bin/sh", "-c", "..."]` — and [lib/shell.sol](../lib/shell.sol) wraps it,
so the convenience is a line away and the hazard is named where it is taken.

`capture` answers a dictionary of `"output"` and `"status"`, because `grep`
finding nothing is not `grep` failing. A missing command answers `#127` and a
killed one 128 plus the signal, neither raising.

**`string:trim`**, wanted within the hour by the first program that read a
command's output: `wc -l` answers `"     100\n"` and `asInteger` will not have
it.

**`.sob` files are format version 13**, unchanged from 0.11.0 — nothing here
touched the format.

**The roadmap emptied and then grew again**, both in this release. Every entry
it held is built, and the two raised since arrived the way it says they should:
something was wanted and could not be had. `ROADMAP.md` now ends with *how it
emptied* rather than what is next, because that is the part that transfers.

### A program can run another program — `d5826a4`, 2026-08-21

[6.30](COMPLETED.md#630-a-program-cannot-run-another-program--done), and the
first entry raised after the roadmap emptied. It arrived the way the list says
entries do: something was wanted and could not be had. A language aimed at
scripting an OS that cannot invoke another program is working with one hand.

```
system:run(["ls", "-l", path]).                  ; the exit status
system:capture(["git", "rev-parse", "HEAD"]).    ; output and status
```

**An array of arguments, not a command line**, and that is the whole decision:

```
system:run(["rm", name]).       ; one argument, whatever `name` holds
```

A file called `; rm -rf ~` is a **name** there, because it is one string. Handed
to a shell as text, the same name is a sentence. Every scripting language that
took the convenient form regrets it, and the regret is a deleted home directory
rather than a lint warning. Demonstrated rather than asserted: a directory
holding a file of exactly that name survives being listed and measured.

**The shell is reachable and spelled out** — `["/bin/sh", "-c", "..."]` — and
[lib/shell.sol](../lib/shell.sol) wraps it with `run`, `capture`, `read` and
`line`, so the convenience is one line away and the hazard is named in the file
that takes it rather than hidden in a primitive.

**`capture` answers a dictionary** of `"output"` and `"status"`, because a
command's output is worth little without knowing whether it worked: `grep`
finding nothing is not `grep` failing.

**Conventions taken from the shell rather than invented.** `#127` for a command
that cannot be run, 128 plus the signal for one that was killed, and **neither
raises** — a script asking whether a tool is installed is asking a question.

`capture` drains the pipe *before* waiting for the child, since a program
writing more than a pipe holds would otherwise block forever against a parent
waiting for it to exit. Tested with 1.3 MB of output.

### And `string:trim` within the hour

[6.31](COMPLETED.md#631-text-from-another-program-arrives-padded--done), wanted
by the first program that read a command's output. `wc -l` answers
`"     100\n"`, and `asInteger` is strict about the whole string being a number
— rightly, since `"12abc"` is a mistake rather than twelve. Every command-line
tool pads a number and every script that reads one trims it.

Space, tab, newline and carriage return, and nothing else: a string is bytes,
and deciding what counts as blank in a text this language cannot otherwise read
would be a promise it could not keep.

[examples/tools.sol](../examples/tools.sol) reports on a directory by asking
other programs, and settles which of the two to reach for — **an array wherever
a name comes from outside the program**, a string when the shell itself is the
point.

### Solid — `d76b94b`, 2026-08-21

[6.29](COMPLETED.md#629-a-stepper--solid--done), the last entry on the roadmap.
`bin/solid` is the fourth program: it runs a program, stops before its first
line, and takes commands.

```
(solid) break report.sol:5
break at report.sol:5
(solid) continue
report.sol:5  in block
    5      after:lessThan(#0):ifTrue({ error:raise("overdrawn") }).
(solid) locals
  self             <object 0x10122e250>
  amount           #30
  after            #70
```

Step, next, finish, continue, breakpoints, a backtrace, and the locals of a
frame **by name** — which is what
[6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done) was
built for, one release before there was anything to spend it on.

**The machine knows nothing about debugging.** The VM offers a stop before each
instruction that begins a new line or enters a new frame, and calls a hook if
one is set; Solid decides whether that stop is interesting. Stepping,
breakpoints, and what a person means by "over" all live in `solid/`. `solum/`
gained a function pointer and a branch — and the branch costs nothing
measurable: three million loop turns, 0.43s either way.

**It stops where a program breaks**, which is the thing `solis --interactive`
cannot do, since that begins after the unwind and sees only globals:

```
-- division by zero in 'div'
breaks.sol:2  in block
(solid) locals
  a                #100
  b                #0
```

Nothing resumes from there, but the frames are standing and the value that
caused it is in one.

**Three bugs, all in deciding when to stop, all found by using it.** `next`
stopped twice on one line, because returning from a call lands on the line the
call was written on. A breakpoint fired twice per visit, for the same reason —
the signal that separates arriving from returning is the frame count *dropping*.
And a breakpoint in a loop fired once: the first fix was too broad, and then the
VM's own gate turned out to be wrong too, since a block whose whole body is one
line never changes line *or* depth. Frames carry an id unique for the life of the
VM, and gating on that is what makes a new frame always a new place to be.

That third one is the one to remember: **two independent off-by-one judgements
about "the same place", one in each component**, both invisible until a loop
body happened to be a single line.

**The roadmap is empty.** Sections 2 and 6 are done and section 3 is the
restrictions kept on purpose. `ROADMAP.md` now ends with how it emptied rather
than what is next, because the how is the part that transfers: almost every
entry after the first dozen came from writing a program and finding out what it
wanted, and the last four came from asking how a program would be debugged.

## 0.11.0 — 2026-08-21

**A frame slot knows what it was called, and the roadmap is down to one entry.**

```
  [locals.sol:7] value(numbers: [#10, #20, #33])
    [locals.sol:4] value(n: #10)
    -> #1
```

The compiler always knew a temporary was called `total` — it had to, to resolve
the name to slot 2 — and threw it away once the index was emitted. A chunk keeps
it now, so `solvm --trace` names its arguments and anything looking at a frame
can say `average` rather than `slot 3`.

**Another `.sob` format change**, 12 to 13, one release after the last. Files
from an earlier build are refused with `unsupported bytecode version` rather
than misread; recompile the `.sol`. The size cost is small — +0.2% on
`numbers.sob`, +3.4% on `page.sob` — because a name is stored once per slot
rather than once per method chunk, which is what made the file table in 0.10.0
dearer.

**The table is indexed by slot rather than filled in the order names arrive**, so
a slot nobody named still takes a place and index N is slot N. That is the
property worth holding: an off-by-one would put the wrong name against the right
value, which is worse than no name, and there is a test that names slots out of
order and leaves a gap to hold it. Naming arguments in the trace is also how the
table was checked — `amount:` lining up with `#30` is visible, where an
assertion at a distance is not.

**One entry left on the whole roadmap**, and it is
[Solid](COMPLETED.md#629-a-stepper--solid--done), the debugger. Everything underneath it
is built: the call tree, the file a frame is in, a name for a local, and the
interactive half in `solis --interactive`. What is left is stopping a program
while it runs, and a front end to drive that.

### A frame slot knows what it was called — `f644c9f`, 2026-08-21

[6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done), and
`--trace` names its arguments:

```
  [locals.sol:7] value(numbers: [#10, #20, #33])
    [locals.sol:4] value(n: #10)
    -> #1
```

**The compiler always knew** — it had to, to resolve `total` to slot 2 — and
threw the name away once the index was emitted. What the runtime had was this:

```
SETLOCL     2
LOCAL       3
```

A slot being an index is right: an access is not a lookup. What was missing is
the name beside it, for anything looking *at* a frame rather than running in it.

**A table per chunk, in slot order**, indexed by slot rather than filled in the
order names arrive — so a slot nobody named, like slot 0 which holds the
receiver, still takes a place and index N is slot N. A test names slots out of
order and leaves a gap, because that is the property worth holding: an
off-by-one would put the wrong name against the right value, which is worse than
no name.

**Naming arguments in the trace is how the table was checked.** `amount:` lining
up with `#30` says the right name is against the right slot, visibly, rather
than asserted at a distance.

**The second `.sob` format change in two releases**, 12 to 13. The entry had said
this should have ridden along with 6.27 and it did not, so the honest accounting
is that a bump costs a recompile, a recompile is cheap and automatic, and
nothing here ships bytecode without its source. The size is far cheaper than the
file table — +0.2% on `numbers.sob`, +3.4% on `page.sob` — because a name is
stored once per slot rather than once per method chunk.

**One entry left on the roadmap**, and it is Solid itself. Everything underneath
it is built: the call tree, the file in a trace, and now a name for a local — so
a stepper can show `average = #180` rather than `slot 3 = #180`, which was the
thing that would have made it most of the work for a fraction of the use.

## 0.10.0 — 2026-08-21

**A stack trace says which file, and the `.sob` format changes for the first
time since 0.1.0.**

```
solvm: index #99 is out of bounds for a string of size 4
  [lib/parse.sol:4] in block
  [main.sol:3] in script
```

**This is the release that breaks bytecode compatibility.** Version 11 stood
through nine releases; this is 12. A `.sob` built by an earlier one is refused
with `unsupported bytecode version` rather than misread, and the remedy is to
recompile the `.sol`. `solvm --version` says which format a build speaks.

**What it buys.** A `.sob` is one chunk, and `@include` compiles a library's
code into the same one — so line numbers came along while the file name did
not. The old trace was **misleading rather than merely thin**: in the case that
prompted this, `main.sol` is three lines long and the trace said `[line 4] in
block`, a line that does not exist in the file anybody would have opened. With
four libraries and `@include` being how a program is meant to be built, that was
going to get worse rather than better.

The chunk already carried a line per byte, run-length encoded because
neighbouring instructions share a line. It carries a file per byte the same way
now, plus a table of paths, and the runs are better here since a method body
comes from one file. `solvm --trace` reads the same table, so the call tree
names files too.

**The cost, measured**: +2.3% on `numbers.sob`, +15.6% on `manifest.sob`, the
spread being the number of method chunks since each carries its own file table.
Sharing one table from the top-level chunk would recover most of it and was not
done — every chunk verifying on its own is worth more than two kilobytes.

**[3.4](ROADMAP.md#34-no-compatibility-across-sob-versions) stops being
hypothetical.** It used to say a compatibility policy was worth having *before*
anything was released. Nine releases later the first break has happened, so the
entry now records what the policy turned out to be: refuse rather than guess,
recompile as the remedy, and `--version` to answer "will this file run" without
trying it.

**The debugger has a name.** *sol-interactive-debugger* reads as **Solid**, and
*solidus* is Latin for firm, whole, sound — a fourth word that looks like the
others and is unrelated to them, which is the pattern the other three names
already play. It is recorded in
[6.29](COMPLETED.md#629-a-stepper--solid--done) rather than the README, which lists
programs that exist.

**Two entries left on the roadmap**, both about looking at a running program: a
name for a local, and Solid itself.

### A trace says which file — `8742f38`, 2026-08-21

[6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done), and the
first `.sob` format change since 0.1.0.

```
solvm: index #99 is out of bounds for a string of size 4
  [lib/parse.sol:4] in block
  [main.sol:3] in script
```

**It was misleading rather than merely thin**, which is what made it worth the
bump. In the example that prompted this, `main.sol` is *three lines long* and
the old trace said `[line 4] in block` — a line that does not exist in the file
anybody would have gone to look at. Had the file been longer it would have
pointed confidently at the wrong line of the wrong one.

A `.sob` is one chunk: `@include` compiles a library's code into the same one,
and the line numbers come along while the file name did not.

**The fix mirrors what was already there.** The chunk carried a line per byte,
run-length encoded because neighbouring instructions share a line. It now
carries a file per byte the same way, plus a table of paths — and the runs are
better here, since a method body comes from one file and is one run. `--trace`
reads the same table, so it names files too, for nothing.

**Version 11 stood for nine releases; this is 12.** Older files are refused with
`unsupported bytecode version` rather than misread, and the remedy is to
recompile. That also makes
[3.4](ROADMAP.md#34-no-compatibility-across-sob-versions) no longer
hypothetical — it used to say a policy was worth having *before* anything was
released, and it now records what the policy turned out to be.

**The size, measured** rather than waved at: +2.3% on `numbers.sob`, +15.6% on
`manifest.sob`. The spread is the number of method chunks, since each carries
its own file table and a program with ninety small methods stores its path
ninety times. Sharing one table from the top-level chunk would recover most of
it and was not done: every chunk verifying on its own is worth more than two
kilobytes.

**Two tests caught things.** The trace-format assertions from last release
failed, which is what they were for. And the serializer's round-trip test
refused a chunk built without a path — the writer was emitting file ids into an
empty table, so the loader rejected its own output. A chunk with no file, like
one compiled at the prompt, prints a bare `[line 1]` exactly as before.

### The debugger has a name: Solid — `00ac10b`, 2026-08-21

*sol-interactive-debugger*, and it belongs to the family better than an acronym
has any right to.

The other names are not abbreviations, they are words: *Solveig* is Old Norse,
*sól* joined to *veig*; *Solum* is Latin twice over, the **ground** as a noun and
**"only"** as an adverb, which is the design principle rather than a decoration;
*SolVM* is how *solum* was written before the alphabet split V into two letters.
The README makes a point of these being separate words that happen to look alike
rather than one word wearing several hats.

*Solidus* is a fourth — Latin for **firm, whole, sound**, usually taken back to a
root meaning "whole", the one behind *salvus*, "safe", and unrelated to either
the ground or the sun however alike they look. A debugger is the tool for
finding out whether a program is sound, standing on ground the language calls
*solum*. The pun is in English and the sense is in the Latin, which is the trick
the other three names play.

Recorded in [6.29](COMPLETED.md#629-a-stepper--solid--done) rather than in the README,
which lists programs that exist.

## 0.9.0 — 2026-08-21

**Bits, and the first tools for looking at a program rather than writing one.**

```
solvm --trace=2 report.sob        # the call tree, two deep
solis --interactive report.sol    # run it, then stay at the prompt with what it left
```

**`solvm --trace`** writes the call tree to stderr: a line entering each frame,
a line leaving it, indented by depth, named by the selector it was **sent as**.

```
  [line 7] <object 0x1027ea980>:describe
    [line 4] <object 0x1027ea980>:double
    -> #42
  -> "x doubled is 42"
```

Frames rather than sends, since a send is arithmetic as often as it is a call —
and **the language suits this unusually well**. Conditionals and loops written
literally compile to jumps, so a `whileTrue` running three hundred thousand
times produces **no trace lines at all**. `--trace=N` follows calls N deep,
which was added after measuring: `page.sol` gives 9,284 lines traced fully, 148
at depth 1.

**`solis --interactive`** runs a file and stays at the prompt afterwards, failure
or not, with everything the program bound still bound. It came from a question —
if a traced program fails, could it fall into the REPL instead of exiting? —
and the answer is worth more here than it would be in most languages, because
**a script's own names are globals** and survive the unwind:

```
-- program failed; its names are here
> tally:print.
[#1, #4, #9, #16]
> { a:withdraw(#500) }:onError({ e | e:message:display }).
not enough
```

A method the program defined can be called again, so the failing call can be
made once more and watched. What is gone is the frames: nothing resumes, and a
block's temporaries go with the stack. A prompt beside the wreck rather than a
break in the middle of it.

**Bit operations** — `bitAnd`, `bitOr`, `bitXor`, `bitNot`, `shiftLeft`,
`shiftRight` — and the case for them was already written down. `lib/text.sol`
encoded UTF-8 with `div(#64)` for a shift and `mod(#64)` for a mask, carrying a
comment saying it did so for want of the real thing. It reads like the RFC now,
and is checked against Python's UTF-8 at every boundary code point.

A shift right **keeps the sign**, which makes it agree exactly with `div` by a
power of two, since that is floored. A shift left **refuses to lose the number**,
the way `mul` refuses to overflow.

**`inc` and `dec`**, which are `add(#1)` and `sub(#1)` under shorter names — a
second spelling, and this language has turned four of those down. What earned
them was the count: **76 of the 256 arithmetic sends** in the examples and
libraries are one or the other. Three in every ten, and that is what having no
binary operators costs the commonest arithmetic there is.

**Three entries written down rather than built**, all about looking at a running
program: [6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done), where a
trace names lines and not files and so reads as though a library's failure were
in your own file; [6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done),
where slots are indices so nothing can show a variable by name; and
[6.29](COMPLETED.md#629-a-stepper--solid--done).

**And an `assert` turned down**, recorded in [ideas.md](ideas.md) with the
reasoning: no to a compile-time switch that strips it, because every hand-rolled
check in this repository is *validation* that must never vanish rather than an
assertion that could, and a switch that removes one kind will be pointed at the
other.

**`.sob` files are still format version 11**, unchanged since 0.1.0.

**One bug caught by the collector rather than by a test.** `--interactive` first
kept the program's chunk in `run_file`'s own frame, so a global still holding a
block pointed into a dead stack frame the moment the prompt allocated — which is
[restriction 3.6](ROADMAP.md#36-a-caller-owned-chunk-must-outlive-blocks-defined-in-it)
exactly, written down years before it was tripped over. Every ordinary test
passed; `SOLUM_GC_STRESS=1` aborted. The chunk belongs to `main` now, and
outlives the prompt.

### `solis --interactive`: a prompt beside the wreck — `38b19d1`, 2026-08-21

Asked for as a question — if a program being traced fails, could it fall into
the REPL rather than exit? — and the answer turned out to be yes, and to be
worth more here than it would be in most languages.

```
$ solis --interactive report.sol
solvm: index #99 is out of bounds for an array of size 4
  [line 7] in script
-- program failed; its names are here
solis 0.8.0 -- ctrl-d to exit
> tally:print.
[#1, #4, #9, #16]
```

**A script's own names are globals**, which is what makes this work. A runtime
error unwinds the frames and leaves the globals alone, so the dictionary the
program built, the array it was filling and the objects it made are all still
there. The check was one line before any code was written:

```
counter := #41.
nil:boom.            ; the program stops
counter:inc:print.   ; #42 -- it is still there
```

And a method the program defined can be **called again**, which is the part that
makes it a half-stepper rather than a post-mortem: the failing call can be made
once more with the same arguments and watched.

```
> a:balance:print.
#70
> { a:withdraw(#500) }:onError({ e | e:message:display }).
not enough
```

What is gone is the frames. Nothing resumes, and a block's temporaries go with
the stack — so this is a prompt beside the wreck rather than a break in the
middle of it. Naming a local would need
[6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done), which is
recorded and not built.

It stays after a program that **finishes** too, which is the other half: `python
-i` is the precedent, and running something to then poke at what it made is as
useful as inspecting a failure.

`solis` also takes `--trace` and `--trace=N` now, the same as `solvm`. The
prompt itself is not traced — what was being watched is the program.

**Not `-i`**, deliberately: `solis` already has `-I` for the include path, and
two flags a shift key apart, one of which takes an argument, is a trap.

One tangent found and left alone: `solis` cannot read a program from an
unseekable file, because `sol_read_file` uses `fseek` to size it. `cat prog.sol
| solis` already works by a different route, so it is a curiosity rather than a
gap.

### `solvm --trace`, and the rest of debugging written down — `a48ac3c`, 2026-08-21

The first thing this project has built for looking at a program rather than
writing one. It came from asking how a program *would* be debugged, which is a
different route to the roadmap than the usual one — every other entry arrived
because a program wanted something and could not have it.

```
  [line 7] <object 0x1027ea980>:describe
    [line 4] <object 0x1027ea980>:double
    -> #42
  -> "x doubled is 42"
```

**Frames rather than sends**, which is what makes it readable: a send is
arithmetic as often as it is a call, and a program does hundreds of thousands of
those. The name is the selector it was **sent as**, threaded through from the
send site — so a block installed in a slot shows as the method it is rather than
as `value`.

**The language turns out to suit this unusually well.** Conditionals and loops
written literally compile to jumps, so they are not calls and do not appear:

```
i := #0.
{ i:lessThan(#300000) }:whileTrue({ i := i:inc }).
```

Three hundred thousand turns, **zero lines of trace**. What shows up is the
calls, which is what was wanted, and it is a property of the inlining rather
than anything the tracer does.

**`--trace=N` follows calls N deep**, added after measuring: `page.sol` produces
9,284 lines traced fully, 1,130 at depth 2 and 148 at depth 1. A trace you have
to grep is much less use than one that shows the shape.

To **stderr**, so a program's own output can still be piped and nothing it
prints changes — asserted rather than assumed. Long values are cut at 48
characters, and rendered without sending `asString`, since a trace that ran the
program it was tracing would not be one.

**Three entries for the rest**, in the order worth doing them:

- [6.27](COMPLETED.md#627-a-stack-trace-does-not-say-which-file--done) — a trace names
  lines and not files, so a failure inside a library reads as though it were in
  the file you are looking at. **Misleading rather than merely thin**, and worse
  with four libraries. A `.sob` format change, and it improves every error
  rather than only a debugging session.
- [6.28](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done) — slots are
  indices, so anything inspecting a running program shows `slot 3` and not
  `count`. The same kind of side table; it should ride along with 6.27.
- [6.29](COMPLETED.md#629-a-stepper--solid--done) — much the largest, wants 6.28 first, and
  worth weighing against `solis`, which already does the interactive half of
  what a debugger is for.

### Bits, and one more, one less — `a7ddf8b`, 2026-08-21

Both asked for, and both with the evidence already in the tree.

**`inc` and `dec`** are `add(#1)` and `sub(#1)` under shorter names — a second
spelling, which this language has turned down four times before. What earns them
is the count: **76 of the 256 arithmetic sends** in the examples and libraries
are one or the other. Three in every ten, and the most common arithmetic there
is, which is what having no binary operators costs.

```
count := count:dec.
```

They answer a new integer rather than changing the receiver, an integer being a
value, so the assignment is the idiom. Integers only: counting by ones in a type
where a one is not exact is a mistake to make deliberately rather than
conveniently. The names are abbreviations, and the objection that this language
does not use them turned out to be wrong — `add`, `sub`, `mul`, `div` and `abs`
are all abbreviated, and `inc` and `dec` sit with them.

**`bitAnd`, `bitOr`, `bitXor`, `bitNot`, `shiftLeft`, `shiftRight`**, and the
case for these was written before they existed. `lib/text.sol` encoded UTF-8
with `div(#64)` for a shift and `mod(#64)` for a mask, carrying a comment saying
it did so for want of the real thing — a workaround in shipped library code,
which is the same signal that got `removeLast` and `indexOf` built. It reads
like the RFC now:

```
integer:utf8Tail := { at | #128:bitOr(self:shiftRight(at):bitAnd(#63)):asCharacter }.
```

Checked against Python's UTF-8 for every boundary code point, `#0` through
`#1114111`.

**Two decisions.** A shift right **keeps the sign**, because there is no
unsigned integer here and a logical shift would turn every negative into a huge
positive — and keeping it makes a shift agree exactly with `div` by a power of
two, which is floored. `#-7:shiftRight(#2)` and `#-7:div(#4)` are both `#-2`,
and that agreement is asserted rather than described. A shift left **refuses to
lose the number**, the way `mul` refuses to overflow.

**The index test earned its keep.** It went in one release ago; adding eight
messages made it fail with `'inc' is a built-in message and the reference's
index does not list it`, which is exactly the drift it was built to catch. The
index is regenerated from the registrations rather than patched by hand.

One test of mine was wrong and the code was right: `#-2:shiftLeft(#62)` is
exactly `INT64_MIN` and fits, where I had expected it to overflow.

Nothing yet.

## 0.8.0 — 2026-08-21

**A program can deal with a filesystem it has to change, and with a keyboard.
The roadmap is empty.**

```
system:makeDirectory(out).                       ; true, or false if it was there
system:writeFile(to, system:readFile(from)).
system:setMode(to, system:modeOf(from)).         ; the executable bit survives
system:setModifiedAt(to, system:modifiedAt(from)).
```

**Five new messages** — `readKey`, `modeOf`, `setMode`, `setModifiedAt`, and a
changed `makeDirectory` — and **every one of them was asked for by a program**
rather than planned. That is the whole method this release ran on, and it is
worth saying plainly because the roadmap had nothing on it when the release
started.

**[examples/mirror.sol](../examples/mirror.sol)** copies one directory tree into
another. The first program here that *writes* to the filesystem, and it could
not do its job: `modifiedAt` answered whole seconds, so *is the source newer
than the copy?* was always no within a second of the last run. The filesystem
records nanoseconds and `time` holds nanoseconds; only that message rounded, in
the middle of the two. **A defect, found by needing it.**

It went on to ask for the rest. A copy lost the executable bit, so a backup of
anything holding scripts would not run — `modeOf` and `setMode`. A copy could
not keep the original's time, so the comparison had to be *newer than* rather
than *the same as*, and a file replaced with an **older** copy of itself went
unnoticed — `setModifiedAt` closed that. And `makeDirectory` refused a directory
that was already there, which made *make sure this exists* a test and a make in
every script that writes anywhere.

**`makeDirectory` answers now** — `true` if it made one, `false` if a directory
was there — and the argument that decided it was not tidiness: refusing could
not be told apart from failing, since `mkdir` reports the same `EEXIST` for a
directory that is there and a **file** in the way. One is fine and the other
never will be, and now they read differently. **A behaviour change**, and a test
asserting the old contract caught it.

**[examples/keys.sol](../examples/keys.sol)** reads one key at a time.
`system:readKey` answers one byte without waiting for return, which closed
[6.10](COMPLETED.md#610-waiting-for-a-single-key--done) — an entry that had been
closed once by mistake, when `solis` grew raw-mode line editing for its own
prompt and the work was filed against it. That was the front end reading its own
keys; this is the message a *program* can send.

**The prompt lists recent lines with ctrl-h**, which is bound where the key was
doing nothing anyway: ctrl-h *is* backspace, and on an empty line there is
nothing to delete.

**The reference has a contents worth the name and a message index.** 56 entries
across two levels, and 110 messages each linked to the types that answer it —
because what a reference is asked is *what has `copyFrom`?* rather than *what
does a string do?*. A test fails the build if a registered message is missing
from the index.

**`.sob` files are still format version 11**, unchanged since 0.1.0. Everything
added here is a primitive or a document.

**Nothing is left on the roadmap.** Sections 2 and 6 are empty and section 3 is
the restrictions kept on purpose, so the document no longer says what to do next
— the way to add to it is to write a program and find out what it wants, which
is what produced every line of this release.

### The reference gets a contents and a message index — `8a5deaf`, 2026-08-21

At 2300 lines the reference had a contents listing 13 of its 68 headings, which
is a contents in the sense that a signpost pointing at a county is directions.

**Two levels now**, generated from the headings themselves, so every `##` and
`###` is in it — 56 entries.

**And a message index**, which is the part that was actually missing. The
question a reference gets asked is *what has `copyFrom`?* rather than *what does
a string do?*, and the sections answer only the second:

```
| `copyFrom` | array, string |
| `indexOf`  | array, string |
| `asByte`   | string |
```

110 messages, each linked to the types that answer it, derived from the
registrations in `builtins.c` rather than written out by hand.

**A test keeps it honest.** A message registered and missing from the index
fails the build — the same bargain that already makes every message appear in an
example. Checked by deleting a row and watching it fail, because a check that
cannot fail is worse than none:

```
`readKey` is a built-in message and the reference's index does not list it
```

It checks presence rather than what is said, since which types answer a message
is prose and prose is not something a test can hold to.

**One wart the contents exposed**: two sections were both called *Errors* — one
about raising and catching, one about what a failure looks like when it is
printed. The second is *How errors are reported* now. Duplicate headings are
invisible until something lists them side by side.

### `system:readKey`, and the roadmap is empty — `9ab2d72`, 2026-08-21

[6.10](COMPLETED.md#610-waiting-for-a-single-key--done), closed this time by the
thing it asked for. A *program* can read a key now, not only the prompt:

```
key := system:readKey.
key:asByte:print.        ; #97 for "a", pressed on its own
```

**The three questions the entry left, answered.**

*One byte, not a whole key.* An arrow is three bytes and a function key can be
more, and which is which belongs to the terminal rather than to the language.
The byte is the smaller promise: a program that wants arrows assembles them, and
one that only wants *any key* is not made to unpick a sequence it never asked
about. A one-character string, so `asByte` gives the number.

*nil at the end of input*, which is `readLine`'s answer and for the same reason.

*No echo*, because raw mode does not, and showing the key would be a second
thing happening.

Raw mode **only on a terminal** — through a pipe a byte is already a byte, so
this reads the same way under `solvm program.sob < input`, which is what makes
the deterministic test possible. `ctrl-c` still interrupts a program waiting for
a key.

**What it cannot do**, and no byte-level reader can: tell the escape key from
the start of a sequence. Escape then tab reads the tab as the byte after the
escape. Telling them apart needs a read that gives up after a few milliseconds.
[examples/keys.sol](../examples/keys.sol) assembles arrow keys out of the bytes
and says this out loud.

**A harness bug came out of testing it.** `session_expect` counted turns of its
loop against a two-second deadline, so it gave up after a hundred reads however
fast they came — which a long line reaches while it is still being echoed, a
keystroke at a time. It counts two seconds of *silence* now. Every test in that
file passed beforehand; the first one with a line long enough to notice found
it.

**The roadmap is empty.** Sections 2 and 6 have nothing in them, and what is
left is section 3: the restrictions the language keeps on purpose. The way to
add to it is to write a program and find out what it wants — which produced
everything in this release.

### `makeDirectory` answers instead of refusing — `a97f0e6`, 2026-08-21

[6.25](COMPLETED.md#625-makedirectory-refuses-one-that-is-already-there--done).
**true** if it made one, **false** if a directory was already there, an error
for anything else.

```
system:makeDirectory("build/out").      ; true  -- made it
system:makeDirectory("build/out").      ; false -- already there
```

**The case was that every script carried the same block.** `mirror.sol` and
`files.sol` both had a version of `isDirectory:ifFalse({ makeDirectory })`, and
both have lost it.

**What decided the shape was something the entry had not noticed.** It offered a
second message or an answer instead of a raise, and the deciding argument turned
out not to be tidiness: **refusing could not be told apart from failing.**
`mkdir` reports `EEXIST` both for a directory that is already there and for a
*file* sitting at that name, so the two arrived with the same words —

```
cannot make directory 'perm/already': File exists
cannot make directory 'perm/afile':   File exists
```

— and the first is fine while the second never will be. A caller wanting to know
which had to catch the error and read its text, and got no answer even then.

So the file case is separated out and says what it is, and the ordinary case
answers rather than raising, which puts the fact where a caller can use it or
ignore it:

```
cannot make directory 'perm/afile': something that is not a directory is already there
```

**A behaviour change**, and the second in two releases: `makeDirectory` answered
nil and raised on an existing directory, and now answers a boolean and does not.
A program that caught that error to mean "already there" will stop seeing it —
which is the point, since it can now ask instead.

One level still. `mkdir -p` is a different message and nothing has asked for it.

**Section 6 is down to 6.10** — a program still cannot read a keypress — which
is the only entry left on the roadmap that is not a limitation kept on purpose.

### A copy keeps its mode and its time — `176e1d1`, 2026-08-21

[6.26](COMPLETED.md#626-a-files-mode-and-time-cannot-be-read-or-set--done):
`system:modeOf`, `system:setMode`, `system:setModifiedAt`. Built the day the
entry was written, because the thing it fixes is a floor rather than a nicety —
a copy that loses the executable bit is a backup that will not run.

```
source:      -rwxr-xr-x  script.sh
destination: -rwxr-xr-x  script.sh      ; was -rw-r--r--
```

**A mode is an integer**, and the alternative was a string of nine letters —
`"rwxr-xr-x"`, what `ls` prints. Turned down because it would be a second
representation of a number, with its own parser and its own refusals, where
`asBase` already crosses that gap for every base:

```
system:modeOf(path):asBase(#8).      ; "755"
"755":asInteger(#8).                 ; #493
```

Solum has no octal literal, so `#493` is what `0755` looks like written down.
That reads badly alone, and the pair above is the thing to know.

The file-type bits are masked off, so `setMode(to, modeOf(from))` — the whole
reason both exist — cannot try to change a file into a directory.

**`setModifiedAt` closed a corner that could not be closed before.** A copy is
stamped *now*, so the only question a mirror could ask was *is the source
newer?* — and a source replaced with an **older** copy of itself is not newer,
so it went unnoticed. With the time carried across, a matching pair compares
**equal**, and `mirror.sol` compares exactly now rather than by "not newer".

The program that asked for these uses them, which is the part worth having: it
can also tell a file whose bytes are right and whose permissions are wrong, and
fix that without reading the file again.

### A mirroring script, and the defect it found in `modifiedAt` — `eac07ab`, 2026-08-21

[examples/mirror.sol](../examples/mirror.sol) copies one directory tree into
another and reports what changed. The fifth program here written to do a job,
and the first that **writes** to the filesystem rather than reading it — walk.sol
lists a tree, files.sol reads and writes one file, and mirroring is the ordinary
job that needs the whole set at once.

It does not delete. A destination file with no counterpart is reported and left
alone: a mirror that deletes is a different and much more dangerous tool, and an
example is a bad place to hide one.

**It could not do its job, and the reason was a defect.** `modifiedAt` answered
whole seconds. The test a mirror makes is *is the source newer than the copy?*,
and within one second the answer was always no — so a file edited just after a
run was never copied:

```
1  #1:print.        ; a same-size edit, then: "nothing to do"
```

The filesystem records nanoseconds and the `time` type holds nanoseconds. Only
this message was rounding, in the middle of the two:

```
modifiedAt:  1787350321.000000   1787350321.000000     ; the same, it said
stat:        1787350321.201807   1787350321.202166     ; what was actually there
```

Fixed — `st_mtimespec` on Apple, `st_mtim` where POSIX.1-2008 says so, and whole
seconds on anything older. It is **the second piece of the runtime that differs
by platform**, after the prompt's raw mode, and the guard is the same shape.

**Three gaps it found besides.** Two are new entries:

- [6.25](COMPLETED.md#625-makedirectory-refuses-one-that-is-already-there--done) —
  `makeDirectory` is an error when the directory is already there, so *make sure
  this exists* is a test and a make. Every script that writes anywhere will
  carry the same three-line block this one does.
- [6.26](COMPLETED.md#626-a-files-mode-and-time-cannot-be-read-or-set--done) — a copy
  loses the executable bit, because `readFile` and `writeFile` carry bytes and
  nothing else. `-rwxr-xr-x` in, `-rw-r--r--` out. For a language aimed at
  scripting an OS that is a floor rather than a nicety: a backup of anything
  holding scripts will not run.

The third is a corner rather than a gap, and worth knowing: since a copy cannot
keep the original's time, the comparison has to be *newer than* rather than *the
same as* — so a source file replaced with an **older** copy of itself goes
unnoticed. Every mirroring tool has that corner; this one has it because the
time cannot be set rather than because it chose to.

### ctrl-h lists the recent lines — `b97b43a`, 2026-08-21

Asked for after using the prompt: a way to see the last few lines rather than
pressing ↑ until the right one turns up.

**ctrl-h is already backspace**, which is the interesting part. It sends byte 8,
and that is what the backspace *key* sends on many terminals — the editor takes
both 8 and 127 for exactly that reason. Binding ctrl-h to something else would
break deleting for anybody whose keyboard sends BS rather than DEL.

So it is bound where the key is doing nothing anyway: **on an empty line**.
There is nothing to delete there, so nothing is lost, and the key that was asked
for is the key that works.

```
> [ctrl-h]
  1  #7:mul(#6):print.
  2  "hello":display.
>
```

The last ten, numbered by their place in the history, oldest of the shown first.
An empty history says `nothing yet` rather than doing nothing, since a key that
appears broken is worse than one that says it has nothing to offer.

Two tests, and the second is the one that matters: that ctrl-h with something
typed still deletes. The listing is only worth having if it costs nothing.

## 0.7.0 — 2026-08-21

**The prompt became a place you can work.**

Up and down through what you have typed, left and right within the line, and
history that is still there tomorrow. It came from using solis and wanting it:
type something wrong, get an error, and want to press ↑ and fix the typo rather
than type the whole line again.

```
> #1:adx(#2):print.
solvm: integer does not understand 'adx'
> #1:add(#2):print.        ↑, then eleven ←, backspace, d
#3
```

**This closed [6.10](COMPLETED.md#610-waiting-for-a-single-key--done)**, the last
entry in section 6, which had been waiting for a program that needed raw
terminal mode. The program was solis. The terminal does line editing itself in
cooked mode — which is why `fgets` was enough to begin with, and why backspace
already worked — but it does not do history, so an arrow key arrived as the
three bytes of its escape sequence and was compiled as though they had been
typed. Getting history means taking the editing over.

**The keys** are the readline ones, [written down](REFERENCE.md#the-keys) with
the two departures from bash: `ctrl-u` discards the whole line rather than the
part before the cursor, matching the terminal's own kill character; and `ctrl-c`
and `ctrl-z` are left to the terminal deliberately, since taking them over would
be a surprise.

**Solis writes a file now, which it never did before.** History goes to
`$HOME/.solis_history` — the most recent 1000 lines, trimmed on the way out, an
ordinary text file that can be read, edited or deleted. With no `HOME` set it
keeps nothing. Failing to write it is ignored, on the grounds that a prompt
which would not exit because it could not save history is worse than one that
quietly forgets.

**It degrades rather than depending on anything.** Through a pipe, a file, or
with `TERM=dumb`, the prompt reads a line exactly as it did before — which is
what keeps `solis < script` and the test suite working. No readline, no libedit;
the build still needs only a C11 compiler and `make`.

**Nothing about the language changed.** `.sob` files are format version 11,
unchanged since 0.1.0, and there are no new messages: this is entirely the front
end.

**The roadmap has nothing left to build.** Sections 2 and 6 are both empty. What
remains is section 3 — the restrictions the language keeps on purpose — so the
document no longer says what to do next. The way to add to it is to write a
program and find out what it wants, which is how this entry arrived.

### History that outlives the session, and the keys written down — `0ebdd2c`, 2026-08-21

What you type at the prompt is kept in **`$HOME/.solis_history`**, so ↑ reaches
the lines from last time as well as this one. The most recent 1000, trimmed on
the way out; with no `HOME` set, history lasts as long as the session and no
longer.

An ordinary text file, one line per entry, readable and editable and deletable
like any other. **Failing to write it is ignored** — a prompt that refused to
exit because it could not save history would be worse than one that quietly
forgets.

**The keys are documented** in [the reference](REFERENCE.md#the-keys), with the
two departures from bash spelled out: `ctrl-u` discards the *whole* line rather
than the part before the cursor, matching the terminal's own kill character; and
`ctrl-c` and `ctrl-z` are left to the terminal deliberately.

**Two mistakes in the test harness, both the same mistake.** Raw mode is entered
with `TCSAFLUSH`, which discards input already received, so a key sent before
solis is ready is thrown away. The first version of this had it at startup and
fixed it by waiting for the prompt. It had the same bug at the *end*: ctrl-d was
sent as soon as the last output appeared, before solis had re-entered raw mode
for the next prompt, so it was flushed — and then the test closed the pty, which
killed the session instead of ending it.

Nothing had noticed, because nothing had needed a clean exit before. Saving
history on the way out does, and the cross-session test failed until
`session_end` waited for the prompt like everything else. **A test that hangs up
on the program under test is testing a crash**, which is worth knowing before it
matters rather than after.

### History and arrow keys at the prompt — `49b5374`, 2026-08-21

[6.10](COMPLETED.md#610-waiting-for-a-single-key--done), and it closes section 6
entirely. The entry had been waiting for a program that needed raw terminal
mode; the program turned out to be `solis`, from using it — type something
wrong, get an error, and want to press up and fix it.

**Why it needed the whole entry rather than a small addition.** The terminal
does line editing itself in cooked mode, which is why `fgets` was enough to
begin with: backspace worked because the tty handled it before solis saw the
line. What the tty does not do is history — so an arrow key arrived as the three
bytes of its escape sequence and was compiled as though they had been typed.
Getting history means taking the editing over, and that is raw mode.

Up and down through history, left and right within the line, home and end,
backspace and delete, ctrl-a, ctrl-e, ctrl-u, ctrl-l. **`ISIG` stays on**, so
ctrl-c still interrupts and ctrl-z still suspends — those belong to the terminal
and taking them over would be a surprise.

Two details that came from thinking about the actual use:

- **A half-typed line survives browsing.** Step away with up and what you were
  writing is kept, so down brings it back rather than an empty line.
- **The same line twice running is one entry**, because re-running something to
  watch it fail again should not mean pressing up twice to get past it.

**It degrades rather than depending on anything.** When stdin and stdout are not
terminals — a pipe, a file, `TERM=dumb` — the prompt reads a line exactly as it
did before. That is what keeps `solis < script` and the test suite working, and
it is why this is a fallback rather than a dependency: no readline, no libedit,
and the build still needs nothing but a C11 compiler and `make`.

**The cursor moves a byte at a time**, so a left arrow steps into the middle of
a multi-byte character. Same limitation as
[2.13](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only) rather than a new
one.

**Testing it needed a terminal**, and two attempts. `tests/test_line.c` opens
one with `posix_openpt` — POSIX, needing no library, where `forkpty` lives in
different headers on different systems. Both mistakes are worth recording:

- **Keys sent before solis starts are lost**, because raw mode is entered with
  `TCSAFLUSH`, which discards input already received. The test waits for the
  prompt — written from inside the reader, after the mode change — before
  sending anything.
- **Assert on what ran, not on what the screen shows.** The first version
  matched painted text, and since the editor paints every keystroke, looking for
  `kept` after typing `"kept":display.` matched the painting rather than the
  running and drifted a keystroke out of step. The values are chosen now so the
  output never appears in the input: nothing in `#100:add(#5):print.` spells
  `#105`.

A third mistake was mine and not the code's: the first cursor-movement test
failed because I had `LEFT` and `RIGHT` swapped in the harness. ANSI `C` is
right and `D` is left. The editor had been correct the whole time, which is an
argument for asserting on program output — `#3` came out means the cursor went
where it was asked.

**Section 6 is empty**, and so is section 2. What is left of the roadmap is
section 3: the restrictions the language keeps on purpose. The document no
longer says what to build next — the way to add to it is to write a program and
find out what it wants.

## 0.6.0 — 2026-08-21

**The language has no open design questions left, and the compiler has a second
warning.**

**2.5 is closed** — class side versus instance side, the last one — and it is
closed by *not* splitting the objects. The line between the two sides is drawn by
the receiver each message requires, which is machinery 1.6 had already built for
another reason and which turned out to be the whole of what the split was wanted
for. Ten registrations changed; a second object per built-in was not needed.

**This is a behaviour change, and the only one in six releases.** Every
class-side message now requires an object receiver, so an instance can no longer
answer for its class:

```
[#1]:new.            ; was []          -- now: 'new' expects an object, got array
[#1]:of(#2, #3).     ; was [#2, #3]    -- now refused
dictionary:new:new.  ; was a dictionary -- now refused
#45:new.             ; refused, as before, and now respondsTo agrees
```

A `.sob` from an earlier release still **loads** — the format is version 11,
unchanged since 0.1.0 — and one that sends a class-side message to an instance
will now fail where it used to answer. Nothing in the examples or libraries did.

What it buys is that **`respondsTo` no longer lies.** Three messages — `new`,
`slots` and `slotAt` — accepted any receiver and then refused a value from
inside the primitive, so `#45:respondsTo('new)` answered true and `#45:new`
failed. It answers false now, and sending and asking agree everywhere.

**A warning when two files claim one global name.** There is no module system, so
an included file binds into the one global namespace and the later binding wins
quietly. `lib/text.sol` proved it the hard way: it bound one object called
`text`, the first program to use it had a variable of that name, and the library
broke from a distance with `string does not understand 'utf8'`.

```
[prog.sol:3:1] solas: warning: 'text' was already bound by lib/text.sol -- this one wins, and nothing else will say so
```

Only a **claim** warns. `count := count:add(#1)` reads the name before writing
it, so it is updating somebody else's global rather than declaring its own —
which files legitimately do across an include. Without that rule the warning
fired on a test fixture; with it, the 28 examples, four libraries and every test
compile silently.

**Section 6 is down to one entry** — a single keypress, still waiting for a
program that needs one — and section 2 is empty. What is left of the roadmap is
the limitations the language keeps on purpose.

### A warning when two files claim one name — `595622f`, 2026-08-21

[6.21](COMPLETED.md#621-two-libraries-binding-one-name-collide-silently--done),
and the second warning the compiler has. There is no module system: an included
file binds into the one global namespace, so two files that both use a name did
not collide — the later one won, quietly, and which one a program got depended
on include order rather than on anything written where the name was used.

**The entry said nothing had tripped over it, and that lasted about ten
minutes.** `lib/text.sol` bound one object called `text`, following the
reference's own advice about claiming one name instead of a dozen; the first
program to use it had a variable of that name, and the library broke from a
distance with `string does not understand 'utf8'` — a run-time message about a
type, for a compile-time collision between two files. That now reads:

```
[prog.sol:3:1] solas: warning: 'text' was already bound by lib/text.sol -- this one wins, and nothing else will say so
  text := v.
  ^^^^
```

**A claim, not an update**, which is the distinction that makes it quiet enough
to keep. `count := count:add(#1)` reads the name before writing it, so it is
working on somebody else's global rather than declaring its own — a thing files
legitimately do across an include. The rule is that **a name you read in the
course of assigning it is one you are updating**, and only a claim warns.

That rule was written because the first version fired once across the whole
tree, on a test fixture that increments a counter from an included file. With it,
28 examples, four libraries and every test compile without a warning — which is
the bar a warning has to clear to be worth having.

**The three tiers this leaves**, which are the working advice for a library now:

| what a library adds | how to bind it | globals claimed |
| --- | --- | --- |
| behaviour on an existing type | a method on the class | **none** |
| a thing with state and its own operations | one object, everything on it | **one** |
| several unrelated names | nothing better than several globals | **several** |

The top tier is the one worth knowing: `integer:asUtf8` and
`integer:timesCollect` need no name of their own, because they extend a class
that already has one. That is a send rather than an assignment, so this warning
never sees them — there is nothing to collide with.

**What it does not fix**, and the entry is closed saying so: this is the cheap
half of a namespace. There is still no export boundary — every slot on `json`
and `html` is public and writable, and `json:digits := "abc"` breaks the parser
from outside it — and no declared dependencies. Both need things the language
does not have.

**Section 6 is down to one entry**, 6.10, waiting for a program that needs a
single keypress.

### 2.5 is closed, and the split was not built — `b74e720`, 2026-08-21

The last open design question. Closed by **not** splitting the objects, because
the thing the split was for turned out to be reachable without it.

**What was actually wrong was smaller and worse than the entry said.** Three
messages — `new`, `slots` and `slotAt` — were registered for *any* receiver and
then refused a value from inside the primitive, so `respondsTo` said one thing
and sending did another. That is exactly what `respondsTo` has a comment saying
it must not do:

```
#45:respondsTo('new).       ; true
#45:new.                    ; an integer is written #45, and there is nothing for 'new' to make
```

The same gap let an instance answer for its class:

```
[#1]:new.                   ; []          -- a fresh empty array
[#1]:of(#2, #3).            ; [#2, #3]
dictionary:new:new.         ; <dictionary>
```

**Every class-side message requires an object receiver now** — `new`, `of`,
`fromSeconds`, `slots`, `slotAt`. Ten registrations changed from `any_receiver`
to `instance(..., SOL_OBJ, ...)`. All four of those sends are refused,
`respondsTo` agrees with sending everywhere, and the teaching errors survive
because they were always for the class rather than for a value.

**The rule the entry said had nowhere to live now lives in the registration
table**, where the dispatcher checks it on every send: a slot that takes
`SOL_OBJ` is class side, a slot that takes a value type is instance side. That
was the whole of what a behaviour object per built-in would have bought, and it
cost ten lines instead of a second object per class with a link that `isKindOf`
and all four reflection messages would have to keep honest.

The two sides are separable from inside the language, and **nothing is on
neither** — there is a test asserting exactly that:

```
integer:slots:size.                                          ; #30
integer:slots:select({ s | integer:respondsTo(s) }):size.    ; #8
integer:slots:select({ s | #45:respondsTo(s) }):size.        ; #27
```

Eight and twenty-seven overlap by five: `isKindOf`, `isNil`, `notNil`, `perform`
and `respondsTo`, reflection that genuinely serves both audiences.

**One correction on the way.** Looking at this again, the first thing I measured
was that 22 of `integer`'s 30 slots are ones the class will not answer, and I
called that noise. It is not — they are the instance side, and a class holding
its instances' messages is the design rather than a defect. The real defect was
the three that lied, which is a much narrower thing and the one worth fixing.

**The trigger to reopen it**: when `slots` on a built-in class is read by a
*program* rather than printed by an example. Across four programs written to do
a job and four libraries, that happens exactly once —
`integer:slots:size:print`, printing a count.

**Section 2 is now empty.** The language has no open design questions, only
deliberate limitations.

## 0.5.0 — 2026-08-21

**An HTML reader, and the frame limit turns out to be about traversal rather
than about data.**

```
@include "html.sol".

page := html:read(system:readFile("page.html")).
page:findAll("a"):do({ a | a:attribute("href"):display }).
html:complaints:do({ c | c:display }).      ; and what was wrong with it
```

**[lib/html.sol](../lib/html.sol)** reads HTML into a tree, with
[examples/page.sol](../examples/page.sol) as a program on it. **It does not
fail.** Every other parser here stops at the first problem, which is right when
a person wrote the input and can fix it; HTML is generated, served, and wrong,
so this one recovers — stray end tags, unclosed elements, implied ends, a bare
`<` in text, a `<` inside a `<script>` — and keeps a list of what it recovered
from. There is **no `onError` in the library at all**: recovery is a branch that
appends to a list, not an exception, and building it on `error:raise` would have
meant unwinding past the stack that holds the recovery state.

**The finding is about 3.5.** The entry asked whether building against a stack
sidesteps the 62-frame limit. It does — and then traversal walked straight back
into it:

| | deepest that works |
| --- | --- |
| `json.sol`, recursive descent | **28** levels |
| `html:read`, an explicit stack | **50,000**, no limit found |
| `text`, `find`, `findAll` — recursive, as first written | **28** |
| the same three, with a stack | **50,000** |

A tree built 50,000 deep could not be *walked* 30 deep. The limit is not a
property of the data, it is a property of how you traverse it — and a library
can be half-safe without anybody noticing, because the constructor is the part
everyone thinks about.

**`array:removeLast` and `array:indexOf`**, and **symbols have an order**. All
three came from workarounds that were already shipped: the HTML library kept a
hand-rolled stack because an array could not be popped, and its element sets
were delimited strings because an array could not be searched;
`examples/manifest.sol` converted symbol keys to strings and back to sort them.
`removeLast` refuses an empty array rather than answering nil, matching `at`;
`indexOf` answers nil when absent, so `indexOf(v):notNil` is `includes` and
there is no second message for it.

**The compiler's first warning.** A file that includes a library of its own name
finds itself, and since a file is compiled once that include does nothing at
all. It was documented and still took a minute to fall into, so the compiler now
says so and names what was shadowed. A warning and not an error: shadowing is
C's rule and stays, the file still compiles, the status is unchanged.

**No more `@` directives.** `@once`, `@define` and `@ifdef` were scoped and none
belongs: a file is already compiled once, a named constant is a binding, a macro
is a block — whose arguments are unevaluated, which is the one thing macros have
over functions in C — and `respondsTo` already answers feature detection at run
time. `@` stays a namespace with one thing in it, which is a result rather than
an oversight.

**`.sob` files are still format version 11**, unchanged since 0.1.0. Everything
added here is a primitive or a library, so a file built by any earlier release
runs on this one.

**Three libraries now**, and one of them is included by another:
[text.sol](../lib/text.sol) holds `integer:asUtf8`, wanted by both the JSON and
HTML readers. It binds **no global at all** — the first draft bound one called
`text`, and the first program to use it had a variable of that name, which broke
the library from a distance. A namespace only helps if the name is one nobody
else wants.

### Two papercuts, and both had their workaround already shipped — `bc677b0`, 2026-08-21

[6.23](COMPLETED.md#623-an-array-cannot-be-popped-or-asked-what-it-holds--done)
and [6.19](COMPLETED.md#619-a-symbol-cannot-be-ordered--done). Neither was
blocking anything; what made the case was that the code written around them was
in `lib/html.sol` and `examples/manifest.sol`, where anyone could read it.

**`array:removeLast`** takes the last element off and answers it, which with
`add` makes an array a stack. `lib/html.sol` had an object carrying its own
`top` index and overwriting with `at_put` — eight lines, written twice in one
file before being factored out. It is a plain array again:

```
html:push := { e | self:open:add(e). e }.
html:pop  := { self:open:removeLast }.
```

**It refuses an empty array** rather than answering nil, matching `at`'s refusal
of an index out of range. Nil would be a second way of saying "nothing" beside
the one the language has, and it would turn a mistake into a value that fails
somewhere further on. Nothing is made harder: a caller that might be empty asks
`size`, which is the shape a stack's loop condition already has.

**`array:indexOf(v)`** answers a one-based position or nil, exactly like
`string:indexOf`. The HTML library's element-name sets had been *strings*
searched with the delimiters kept on so that `p` did not match `pre`; they are
arrays now.

**And no `includes`.** `indexOf(v):notNil` is that question already, so a second
message would answer less with more surface. The entry had argued against
`includes` on the grounds that a dictionary answers set membership in O(1) —
that still holds; what it missed is that `indexOf` earns its place by answering
*where*, which a dictionary cannot.

**Symbols have an order** — `lessThan` and its three companions, comparing the
text. The question was whether it is worth it, since interning is what makes
`equals` a pointer comparison and exactly what makes the addresses say nothing
about order, so these are the only symbol operations that look at characters.

It is worth it for the reason anything gets sorted: a tally kept under symbol
keys needs a stable order to print in, and symbols are values, so tallying by
symbol is the natural thing to write. `manifest.sol` had been converting keys to
strings, sorting those, and converting back with `asSymbol` to look each one up.
Now:

```
kinds:keys:sorted:do({ kind |
    "  {} {}":fill([kinds:at(kind):asString("4"), kind]):display }).
```

Nothing was needed for `sorted` itself: with no block it **sends** `lessThan`,
so defining one on symbols was the whole of it — the same arrangement that lets
a user-defined type order itself.

### An HTML reader, and the frame limit turns out to be about traversal — `a4dc0c2`, 2026-08-21

[6.20](COMPLETED.md#620-an-html-parser--done), written to find out what the
language wanted. [lib/html.sol](../lib/html.sol) reads HTML into a tree;
[examples/page.sol](../examples/page.sol) is a program on it — an outline, a
link list, images without alt text. The entry predicted three things it would
push on, all three happened, and one answered a question open since 3.5 was
written.

**Recovery is not error handling.** Every other parser here stops at the first
problem, which is right when a person wrote the input and can fix it. HTML is
generated, served, and wrong, so this one keeps going and keeps a list:

```
page := html:read("<b>bold</i>").
page:text:display.                              ; bold
; </i> at character 10 closes nothing that is open
; <b> opened at character 1 is never closed
```

There is **no `onError` anywhere in the library**. A stray end tag is not an
exception, it is a branch that appends to a list — and building it on
`error:raise` would have meant unwinding past the stack that holds the recovery
state.

**The stack sidesteps 3.5 completely, and then traversal walked straight back
into it.** That is the finding:

| | deepest that works |
| --- | --- |
| `json.sol`, recursive descent | **28** levels |
| `html:read`, an explicit stack | **50,000**, and no limit found |
| `text`, `find`, `findAll` — recursive, as first written | **28** |
| the same three, with a stack | **50,000** |

A tree built 50,000 deep could not be *walked* 30 deep. **The limit is not a
property of the data, it is a property of how you traverse it** — and a library
can be half-safe without anybody noticing, because the constructor is the part
everyone thinks about.

**`asByte` was the right size of fix**, which this was the first test of.
Numeric entities need a code point to become bytes, so the UTF-8 encoder moved
to [lib/text.sol](../lib/text.sol) unchanged and both libraries include it — the
first library here included by another library rather than by a program.

**6.21 happened, ten minutes after being written down.** `lib/text.sol` first
bound a global called `text`, following the reference's advice to claim one name
instead of a dozen. The first program to use it had a variable called `text`,
and the library broke from a distance with `string does not understand 'utf8'`.
The fix was to bind **no global at all**: `integer:asUtf8` is a method on a
built-in class, which needs no name of its own. A namespace only helps if the
name is one nobody else wants, and `text` is about the most wanted name there
is.

**One new entry.** [6.23](COMPLETED.md#623-an-array-cannot-be-popped-or-asked-what-it-holds--done):
an array cannot be popped and cannot be asked whether it holds something. A
stack notices both immediately. The workarounds are a `top` index (which is
O(1), so arguably better than the message would have been) and sets kept as
delimited strings.

### The compiler's first warning, and no more directives — `2b25dda`, 2026-08-21

[6.22](COMPLETED.md#622-a-file-that-includes-a-library-of-its-own-name-silently-does-nothing--done).
A file that includes a library of its own name finds *itself*, and since a file
is compiled once that include does nothing at all — the program compiles
cleanly and fails at run time with `undefined name`.

**Documenting it was not enough.** The reference already called it *occasionally
a trap*, and it still took about a minute to fall into once `lib/` had a second
file to collide with. So the compiler says it where the line is:

```
[greet.sol:1:10] solas: warning: this file includes itself, so the include does nothing -- a file beside the includer wins, and 'lib/greet.sol' on the search path is what it shadowed
  @include "greet.sol".
           ^^^^^^^^^^^
```

Naming what was shadowed is the useful half: *this does nothing* says something
is wrong, and *`lib/greet.sol` is what it shadowed* says what you were expecting
to get.

**A warning and not an error** — shadowing is C's rule and stays, the file is
still valid, the status is unchanged. It is the compiler's first warning;
`sol_parser_warning` shares the location and the echoed line with
`sol_parser_error` and sets neither `had_error` nor the panic flag. And only the
**direct** case: a diamond is the ordinary reason include-once exists, a cycle is
one it ends on purpose, both stay silent, and both have tests — a warning firing
on either would be worse than the trap it was added for.

### The rest of the preprocessor, ruled out

`@` was reserved for what happens while compiling, and `@include` is still the
only thing in it. Scoped `@once`, `@define` and `@ifdef` and recorded the verdict
in [ideas.md](ideas.md#more--directives-define-ifdef-once). **None of them
belongs, and the reason is the same each time: the job is already done by
something that is not a directive.**

- **`@once` is already the behaviour**, unconditionally. C needs it because C
  compiles an included file every time it is reached; Solum compiles it once,
  keyed by where it lands on disk. There is nothing for the directive to switch
  on.
- **`@define`** has three jobs: a named constant, which is a binding holding a
  value rather than a name standing for text; a function-like macro, which is a
  block — and the one thing macros have over functions in C, arguments that are
  not evaluated before the call, is exactly what a block is; and compile-time
  computation to save run-time cost, where the answer here has consistently been
  to measure and make it a primitive, which speeds up every caller rather than
  the ones who remembered.
- **`@ifdef`** is the arguable one. Platform differences are absorbed by the VM
  in C. Debug builds can read `system:environment`. Feature detection is the real
  use, and `respondsTo` already answers it at run time with no second language:
  `"A":respondsTo('asByte)` is `true` here and `false` on an older build. What
  conditional compilation would cost is out of proportion — a second language
  with its own scoping, and text on the screen that is no longer the program.

So `@` stays a namespace with one thing in it. That is a result rather than an
oversight: if a real compile-time need turns up, the space is ready, and the case
for it will be that nothing in the language already does the job.

### Renumbered: the self-include entry is 6.22, not 6.18

Caught while checking a link. **6.18 was already taken** — *There is no date or
time*, built in 0.3.0 — and the roadmap's own rule is that numbers are never
reused, so that a gap is a record rather than a mistake. The self-include entry
was given 6.18 without checking what the highest number in use was, which is the
one thing the rule exists to prevent.

It is 6.22 now, everywhere it is referred to, including in the 0.4.0 notes above
that were written with the wrong number. The date-and-time 6.18 is untouched.

## 0.4.0 — 2026-08-21

**A byte has a number, and the language reads a format it did not know about.**

```
@include "json.sol".

config := json:read(system:readFile("config.json")).
config:at("server"):at("port"):print.
system:writeFile("config.json", json:write(config)).
```

**`asByte` and `asCharacter`.** A one-character string answers its number, and a
number `#0` to `#255` answers its string. Two primitives and no new type — both
ends already existed. A string is bytes, so they are named for what each
answers: `"é":asByte` is refused rather than answering its first byte, which is
what keeps the two exact inverses.

**A JSON reader and writer**, `lib/json.sol`, on the search path beside
`control.sol`. It reads `\uXXXX` in full, surrogate pairs included, and encodes
UTF-8 — in Solum, on top of `asCharacter`, because encoding a code point is
arithmetic and arithmetic belongs where the format is known. A document reads,
round-trips and writes back with names sorted, so the same document always
produces the same text.

**`--help` and `--version`** on `solas`, `solvm` and `solis`. Both go to stdout
and leave with 0; usage after a mistake goes to stderr and leaves with 64.
`--version` names the `.sob` format as well as the release, since that is the
number that goes wrong in practice.

**`.sob` files are still format 11**, unchanged since 0.1.0. The new messages are
primitives rather than opcodes, so a file built by any earlier release runs here,
and this is the first release where `solvm --version` will tell you the number
itself.

**Two documents.** [dispatch.md](dispatch.md) — a dictionary of blocks is a
switch statement, 18.8× a chain of comparisons, and the two traps that come of
putting closures in a table. [one-hierarchy.md](one-hierarchy.md) — what the
single root means from the outside: one method on `object` answered by every
value, and the line between inheriting the behaviour and being an object.

**Written by writing programs.** `lib/json.sol` and `examples/manifest.sol` were
written to find out what the language wanted, and the answer moved the roadmap
four times: 6.12 got built, 3.5 got a price list for how the dispatch is
written, and 6.22, 6.19 and 6.21 are new entries for papercuts a program tripped
over. Three programs here now exist to do a job rather than to show a feature.

### `--help` on all three binaries — `6542ec3`, 2026-08-21

Each of `solas`, `solvm` and `solis` already had a `usage()`; it was reachable
only by getting the command line wrong. `--help` and `-h` now ask for it.

The distinction worth writing down is **which stream**. Help that was asked for
goes to **stdout** and leaves with **0**, so it can be piped or paged. The same
words after a mistake go to **stderr** and leave with **64**. Same text, two
destinations, and `usage()` takes the `FILE *` to say which.

The help itself names every option rather than listing the shape of the command
line, since the shape was already there and the options were the part a reader
had to find in the source.

**A front end's own flags stay in front of the file**, `--help` included:

```
solvm program.sob --help --dump -h
#3
  --help
  --dump
  -h
```

All three reach the program and `solvm` says nothing, which is the rule that was
already there for `--dump` and is why a script can have a `--help` of its own.
That is the one behaviour here worth protecting, so it is what the new test
mostly checks.

**`--version` came with it** (`ce77764`), and names the `.sob` format as well as
the release:

```
solvm 0.3.0 (.sob format 11)
```

The format number is the useful half. It is the one that goes wrong in practice
— a `.sob` from a build with a different one is refused rather than misread, and
until now there was no way to ask a binary which number it was holding, the
answer being in a header. The test checks it against `SOLUM_VERSION` and
`SOL_SOB_VERSION` rather than against a copy of the text, so a release that
bumps either cannot leave the test passing and wrong.

`tests/test_cli.c` is the first test that runs the **binaries** rather than
linking the library — a `main` is not something `libsol.a` holds, and which
stream text landed on cannot be asked any other way. `make test` now builds the
binaries first.

### A byte has a number: `asByte` and `asCharacter` — `49b0ab1`, 2026-08-21

[6.12](COMPLETED.md#612-taking-a-binary-file-apart--done) waited a long time for
a program to need it and then got needed by the wrong one. The entry was about
taking binary files apart; what actually wanted a byte's number was **text** —
`lib/json.sol` reading `\u0041` and answering `"A"`.

**Two primitives, no new type.**

```
"A":asByte:print.            ; #65
#65:asCharacter:display.     ; A
```

The entry had proposed a byte-buffer type at sixteen bytes a byte. What the
program turned out to want was a one-character string in and an integer out, and
back — both ends already existed, so this is two functions in `builtins.c`
rather than a type with a representation, a printer, a GC visit and a `.sob`
encoding.

**Named for what each answers**, which was the decision in it. A string is bytes,
so `asByte` is honest where `asCode` would have promised a code point:

```
"é":asByte.
solvm: 'asByte' wants one byte, and this string has 2 -- a character outside ASCII is more than one of them
```

Refusing is what keeps the two exact inverses, and the test is the range rather
than a sample of it: every byte `#0` to `#255` survives `asCharacter:asByte`.

**The foundation, not the fix — which is the good part.** A code point above 127
is more than one byte, so encoding one is *arithmetic*, and arithmetic belongs
where the format is known. The UTF-8 encoder is therefore in `lib/json.sol`, in
Solum, and it reaches all of Unicode:

```
json:read("\"caf\u00e9\"").          ; café   -- two bytes
json:read("\"\u4e2d\u6587\"").       ; 中文    -- three bytes each
json:read("\"\ud83d\ude00\"").       ; 😀     -- a surrogate pair, four bytes
```

Solum has no bitwise operators, so the shifts and masks are `div` and `mod` and
the tag bits go on with `add` — exact, the bits being disjoint by construction.
The library lost a 95-character table of printable ASCII and gained the rest of
Unicode, which is the trade this was for. Writing gained the same thing: a
control byte goes out as `\u00XX` now instead of being refused.

`#0:asCharacter` is the **only way to write a NUL** — there is no `\0` in a
literal. Strings are length-counted and already carried one through `readFile`
and `writeFile` byte-for-byte, so it added a spelling rather than a hazard.

**A bug the new test found, twice.** `onError` calls its handler with one
argument and arity is strict, so `onError({ nil })` fails with *'onError' takes
1 argument, got 0* — an arity error **in place of** the recovery it was written
to perform. It was in `lib/json.sol` on the bad-hex-digit path and in
`examples/manifest.sol` on a non-numeric path segment, and both were invisible
because nothing had taken those paths. A handler that ignores the error still
has to accept it.

The library is now tested end to end rather than only compiled: what it answers,
not just that it runs.

### A JSON reader and writer, and the three things it found — `40f2004`, 2026-08-21

The roadmap had emptied of anything a program asked for: the two entries left
both said, in their own text, that they were waiting for a program to need them.
So a program was written to find out.

[lib/json.sol](../lib/json.sol) is a JSON reader and writer in Solum, on the
search path beside `control.sol`, and [examples/manifest.sol](../examples/manifest.sol)
is a program on top of it — describe a document, pull a value out by a dotted
path, edit it, write it back, read it again and prove the text matches. It
claims one global and hangs everything off it, which is what the reference has
always said to do instead of the module system the language does not have.

**6.12 has its program.** The entry was written about binary files; what needed
a number for a byte first was *text*. `\u0041` is a code point that has to
become `"A"`, and there is no `asCode` and no `asCharacter`, so the library
carries the printable ASCII range as a literal to index into and refuses the
rest:

```
json:read("\"\u00e9\"").
solvm: \u00e9 is outside what a Solum string can hold at character 8
```

What is *not* broken is worth as much: UTF-8 in the text passes through
perfectly, because a string is bytes and the parser copies spans of them. It is
the format's escape mechanism that fails, not the encoding — a narrower problem
than it looked, and `asCode`/`asCharacter` would close it without the byte-buffer
type this entry has been asking for.

**3.5 got a second data point and a price list.** A recursive-descent parser
spends the frame budget several times per level, and *how the dispatch is
written* turned out to move the number a long way:

| dispatching on the first character | levels of nesting before the cap |
| --- | --- |
| a dictionary of blocks, which [dispatch.md](dispatch.md) recommends | **18** |
| a chain of `ifElse` | **28** |

Ten levels of document, for one message. Both recommendations are right on their
own and they pull against each other exactly where the cases recurse — the
jump table is for cases that are leaves. The library takes the chain and the
comment says why.

**A third, recorded rather than worked on.** [6.21](ROADMAP.md): two libraries
binding one name do not collide — the second include wins quietly, and swapping
the two lines changes the answer with no diagnostic either way. Nothing has
tripped over it, unlike 6.22. It is the third entry now pointing at the same
absence, so what it records is that **there is no module system** and the shape
of what one would buy — a namespace, which the object idiom approximates; an
export boundary, which privacy would have to become a new concept to provide;
and declared dependencies, which is exactly what would make 6.22 diagnosable.

**Two papercuts, both new entries.** [6.22](ROADMAP.md): a file that includes a
library of its own name finds *itself* first and that include quietly does
nothing — documented, and still about a minute to fall into once `lib/` had a
second file to collide with; the example is called `manifest.sol` for that
reason alone, and a warning would cost one comparison. [6.19](ROADMAP.md): a
symbol has no `lessThan`, so a report tallied under symbol keys converts to
strings to sort and back to look up.

**6.20 is written down rather than built** — an HTML parser, as the next program
whose findings would not overlap with these. Error recovery, which no parser here
has ever had to do; character classification in bulk, which is 6.12 from a second
direction; and a tree built against a stack rather than by recursion, which may
sidestep 3.5 entirely.

Smaller things settled on the way. A whole float prints as `150`, so writing one
plainly would hand back an integer on the next read — the number rule needs
holding up from both sides for a document to round-trip. Names are written
sorted, so the same document always produces the same text and a rewritten file
diffs cleanly. And `asJson` is defined on `object`, so nil answers `"null"`
through the definition every other type uses — which matters because nil's class
has no global for a method to be bound on, and the single root is what makes
that not matter.

6.12 was also made exact on the way. `asCode` and `asCharacter` **do not
exist** — the entry proposes those names. What is good about the pair is that it
needs **no new type**: a one-character string in, an integer out, and back. What
it would *not* do is finish the JSON case, because a string is bytes and `é` is
a code point UTF-8 spells in two of them. UTF-8 encoding is ordinary arithmetic
once a number can become a byte, so it belongs in the library rather than the
VM — the pair is the whole foundation and not the fix. One side effect worth
having: `#0:asCharacter` would be the only way to write a NUL, which no literal
spells today, and a string already carries one through `readFile` and
`writeFile` byte-for-byte.

`lib/` is now checked the way `examples/` is: every file in it compiles and
verifies, and one not listed in the test fails rather than being skipped.

### One hierarchy, written down from the outside — `079d353`, 2026-08-21

`a0b0d41` made every built-in class delegate to `object` and recorded the
decision in class-and-instance.md. That is the *why*; nothing said what it means
for someone writing a program. [docs/one-hierarchy.md](one-hierarchy.md) is the
consequence, and the line it draws is:

**Delegating to `object` gives a value the behaviour. It does not give it the
storage.** One `object:describe := { ... }` is answered by all eleven kinds of
receiver — integer, float, string, symbol, boolean, nil, array, block,
dictionary, time and object — and the nearest slot still wins, because the root
is the end of the search rather than a special case in it. But `#45` is an
immediate, so `#45:x := #1` says *cannot bind 'x' on integer*, and `parent` and
`via` refuse it. A value **is a kind of** object without **being** one.

Writing that up turned up a loose end. Override on a value class a message that
`object` defines, and the override cannot call the one it displaced:

```
integer:describe := { "a number, and then ":concat(self:via(object):describe) }.
#45:describe.
solvm: 'via' expects an object, got integer
```

The check predates the root, from when a value's chain ended at its own class and
there was nothing above to name. Every class delegates to `object` now, so a
value has a chain to walk and the refusal is a leftover rather than a design.
`slotAt(...):boundTo(self)` does the job today — `boundTo` supplies a receiver
instead of searching from one, so it takes a value happily. Recorded as
[2.14](ROADMAP.md).

Also linked from the reference's object section, which stated the hierarchy and
not what follows from it.

### A dictionary is a switch statement — `dc923d0`, 2026-08-21

No code, just writing down something the pieces already did.

A block is a value and a dictionary holds values, so a table of blocks under
keys dispatches on one:

```
action := dictionary:new.
action:atPut('red, { "stop" }).
switch := { light | action:at(light, { "not a light" }):value }.
```

**`at(key, default)` is the whole trick.** It was added so a counter could say
`counts:at(word, #0):add(#1)`, and it turns out to be exactly what a switch
wants — the default case in one message rather than a lookup, a test and a
branch. Usually a sign a thing was shaped right rather than shaped for its first
use.

It is also **18.8× faster** than the predicate `caseOf` in ideas.md over twenty
cases, and the gap grows: a dictionary hashes once whatever the table holds,
where a chain of comparisons walks until it matches.

[docs/dispatch.md](dispatch.md) is the new page, and the reason for a page rather
than a paragraph is the **two traps**, both from the blocks being closures.
Building the table in a loop and capturing a temporary fails loudly — *block
outlived the frame it was written in*. Capturing a **global** instead removes
the failure and not the mistake: every block reads the same name, so all of them
answer whatever the loop left behind. That is the closure-in-a-loop bug every
language with closures has, and nothing here protects you from it.

The page also separates the two shapes of the question. Equality on a value is
the dictionary's; conditions, ranges and guards still need predicates tried in
turn, which is what the `caseOf` in ideas.md is for and why it stays there
rather than in the library.

One thing corrected on the way: ideas.md carried
`integer:caseOf := object:slotAt('caseOf)` with a note about how neatly `slotAt`
binds a method to another class. Still true of `slotAt`, and **the line has not
been needed since the single root** — a method on `object` is found from a
number like anything else. The single root took a paragraph of cleverness and
made it unnecessary, which is the better outcome.

## 0.3.0 — 2026-08-21

**A program can deal with the machine it is running on.** It can look at the
filesystem rather than only be told about it, know what day it is, and be run
directly as a script.

```sh
$ cat report.sol
#!/usr/bin/env solis
system:filesIn("logs"):sorted:do({ name |
    "{}  {}":fill([system:modifiedAt("logs/":concat(name)):asString("%Y-%m-%d"),
                   name]):display }).

$ chmod +x report.sol && ./report.sol
```

**The filesystem.** `filesIn` and `isDirectory` to walk it; `fileSize` and
`modifiedAt` to measure without reading; `appendFile` beside `writeFile`;
`makeDirectory`, `rename` and `remove` to change it; `environment` to read a
variable.

The three that change things take the narrow reading, and the reasoning is in
[the reference](REFERENCE.md#changing-what-is-there): `remove` takes a file or
an **empty** directory with no recursive form, `makeDirectory` makes one level,
and `rename` replaces without asking. Every refusal names the reason the system
gave.

**A time**, as a value type held in nanoseconds since the epoch. `system:time`
for now, `system:modifiedAt` for a file, `time:fromSeconds` for any instant, and
`asTime` on a string to read one back. Comparison, `secondsSince`, `plusSeconds`,
calendar fields, and `strftime`/`strptime` formats.

**Everything is UTC**, which is the decision rather than an omission — a zone is
a political fact that changes, where an instant does not. An offset like
`+01:00` is accepted because an offset is arithmetic; a zone *name* is not, and
will not be.

**Scripts.** `solis` takes a file — source or bytecode, decided by looking at
the bytes rather than the extension — and a `#!` on the first line is skipped,
so `chmod +x` works. `#!/usr/bin/env solis` is the portable form.

`.sob` stays at **format version 11**, unchanged since 0.1.0: the new value
types were appended and cannot be constants, so the file layout never moved. A
`.sob` built by 0.1.0 runs here, which was checked rather than assumed.

The restrictions in [ROADMAP section 3](ROADMAP.md#3-known-limitations) are
unchanged: no non-local return, a capturing block tied to its frame, recursion to
about 62 levels, text is bytes.

Verified for the release: clean build with no warnings, `make test` and
`SOLUM_GC_STRESS=1 make test` both passing, all 26 examples compiled and run,
and zero leaks across every test binary.

### A time can be read back — `2b941f4`, 2026-08-21

```
"2026-08-20T09:14:02":asTime:year:print.        ; #2026
"20/08/2026":asTime("%d/%m/%Y").
```

`asTime` is on **string**, beside `asInteger`, `asFloat` and `asSymbol` — a
conversion *from* text has always lived there. With no argument it reads
ISO-8601, mirroring what `asString` writes; with one, the format is handed to
`strptime`, the counterpart of the `strftime` `asString(format)` uses.

**No zone means UTC**, there being no other kind here. An **offset** is accepted
because an offset is arithmetic — `+01:00` is an exact number of minutes and
says nothing about legislation. A zone *name* is not, and will not be.

**A date that does not exist is refused**, which almost every date parser gets
wrong quietly:

```
"2026-02-29":asTime.
solvm: 'asTime' cannot read that as a date
```

The check is a round trip — convert, split back, and see whether the day came
out the way it went in. February the 30th converts to March the 2nd without
complaining, and a silently wrong date is worse than a refused one. `2024-02-29`
is a real day and is accepted; `2026-02-29` is not.

Two things worth recording from building it.

**A precision bug of mine, caught by testing a fraction.** `asSeconds` turned
int64 nanoseconds into a double and *then* divided — but a present-day instant
is past 1e18, where a double has stopped counting in ones, so `0.25` came back
as `0.249999872`. Both conversions now split the whole seconds from the
fraction, which keeps the seconds exact and asks the double only for the part it
can still hold.

**`timegm` was the obvious call and is not standard C**; `mktime` is standard and
reads the *local* zone, which is the one thing this type does not have. The
civil-date arithmetic is written out instead — ten lines, exact, and beholden to
no zone.

**[examples/log.sol](../examples/log.sol) stops comparing timestamps as text.**
That worked, because ISO-8601 sorts the same as text and as instants — luck
rather than design, true of no other format, and it meant a malformed timestamp
went unnoticed because nothing ever looked at one. The report now says *over 278
seconds*, which text could never have told it, and a bad timestamp is caught
with the line number like any other damaged field.

### A time — `eaa2fa4`, 2026-08-21

Roadmap 6.18. A value type for a point in time, held as nanoseconds since
1970-01-01T00:00:00Z.

```
now := system:time.
now:print.                                   ; 2026-08-21T16:57:41Z
now:year:print.                              ; #2026
now:asString("%Y-%m-%d"):display.            ; 2026-08-21
system:modifiedAt("notes.txt"):asString("%H:%M"):display.
```

**A value, not an object.** Two of the same instant are the same time and
nothing mutates one, so it belongs beside integer and float — which makes
`equals` exact and a time a dictionary key for free, and means `time:new`
refuses like the other value classes.

**Nanoseconds as an integer, not a float of seconds.** A point in time being a
float invites `t:add(1.5)`, a question with two plausible answers. Integers are
exact, `nan` cannot get in, and int64 nanoseconds reach from 1678 to 2262.

**Everything is UTC.** Time zones are where every date library goes wrong, and
the answer here is not to have them: a zone is a political fact that changes by
legislation, twice a year in most places and retroactively in some. An instant
is unambiguous; a wall-clock reading is not, and the trailing `Z` says which of
the two you are looking at.

**`secondsSince`, not `sub`** — a time minus a time is not a time, so `sub`
would have answered a different kind of thing from every other `sub` here.
**`asString(format)` hands the format to `strftime`**, whose alphabet everybody
knows, rather than inventing a third spec language.

**`system:time` is not `system:clock`.** That one is a stopwatch — monotonic,
unspecified epoch, only differences meaningful. This is a calendar. A program
asking how long something took wants the first; one asking when it happened
wants the second.

Two things building it found that the plan had not.

**Nothing could name a particular moment.** With only `system:time` and
`system:modifiedAt`, the only instants a program can have are the current one
and a file's — enough to stamp a log, not enough to say when something is due,
or to test any of this against a date somebody knows. `time:fromSeconds` and
`asSeconds` are the pair that fixes it, and they are also how an instant is
written to a file and read back.

**Splitting an instant has to floor.** C division truncates towards zero, so
half a second before the epoch divides to zero seconds and lands on 1970 rather
than 1969. Tested, in both directions.

`system:modifiedAt` is the companion `fileSize` was waiting for.

### Making, moving and removing — `99b971e`, 2026-08-21

The other half of the filesystem, and the half that cannot be undone.

```
system:isDirectory(p):ifFalse({ system:makeDirectory(p) }).
system:rename(old, new).
system:remove(old).
system:fileSize(path).
```

Three decisions worth having made deliberately, all of them the narrow reading.

**`remove` takes a file or an empty directory, and there is no recursive form.**
Both, because that is the distinction a script does not want to make — it knows
what it is taking away. But deleting a tree is not something to make one message
wide: a program that means it can walk with `filesIn` and remove what it finds,
which at least reads like what it does.

**`makeDirectory` makes one directory, not a path of them.** `mkdir -p` is what
a script usually wants and does more than its name says — asked for `a/b/c` it
may leave `a` and `a/b` behind having failed at `c`. A directory already there
is an error, which makes `isDirectory:ifFalse({ makeDirectory })` the way to say
"make sure of it": longer, and it says which of the two you meant.

**`rename` replaces an existing destination without asking**, as the system call
does and as every `mv` does, and cannot cross a filesystem. There the answer is
read, write, remove — three operations because it is three operations — and the
error says so rather than pretending.

Every refusal names the reason the system gave, so a script can tell a missing
file from a directory that still has something in it:

```
solvm: cannot remove 'build': Directory not empty
```

**`fileSize` and not `modifiedAt`.** Size is unambiguous; a timestamp wants to be
a **date** rather than a number of seconds, and there is no date type here yet —
answering an integer now would be an interface a date type would have to change.
Recorded as [6.18](COMPLETED.md#618-there-is-no-date-or-time--done), which is now
the largest thing missing.

### Directories, and a script you can run directly — `d503612`, 2026-08-21

Two things, in the direction of Solum being worth writing a script in.

**A program can look, rather than only be told.**

```
system:filesIn("examples"):sorted:first(#3).   ; ["arrays.sob", "arrays.sol", "binding.sol"]
system:isDirectory("examples").                ; true
system:appendFile(log, "another line\n").
system:environment("HOME").                    ; the variable, or nil
```

`readFile` needed a path you already had, so a program could be handed something
to work on and could never go and find it. `filesIn` is the missing first step of
most file-processing programs — and it was nameable without writing a program to
discover it, which is why it was named rather than staged.

Four decisions, all the conservative ones. **Names, not paths**, because a path
would bake in a separator and joining is one `concat`. **Everything but `.` and
`..`**, directories included, because leaving them out would make a recursive
walk impossible. **In the directory's order**, which is to say none — the rule
`dictionary:keys` already follows. **An error if it is not a directory**, as a
missing file is to `readFile`.

`appendFile` is `writeFile`'s other half. `environment` answers **nil** when a
variable is not set, that being a legitimate answer rather than a failure.

**A `.sol` file can be marked executable and run.**

```sh
$ cat hello.sol
#!/usr/bin/env solis
"hello":display.

$ chmod +x hello.sol && ./hello.sol
hello
```

`solis` takes a file now — source or bytecode, and it decides which by **looking
at the bytes** rather than the extension, so a script with no extension at all
works, which is the usual way of writing one. Arguments after the file are the
program's, as they are for `solvm`.

The `#!` is skipped only at the very start of the file, and the newline is left
in place so the line after it is line 2 — an error names the line an editor
shows rather than one earlier.

One correction worth making: `#!/bin/solis $*` will not do what it looks like.
The kernel passes at most one argument after the interpreter, literally, so the
`$*` arrives as an argument spelled `$*`. `#!/usr/bin/env solis` is the portable
form, and arguments need no help — they arrive as `system:arguments`.

[examples/walk.sol](../examples/walk.sol) is the program none of this was
possible without: it walks a tree, counts and measures it, and **catches
`call depth exceeded`** when the tree is deeper than the machine's frames allow,
reporting the partial totals rather than dying. Tried against a forty-deep tree
it stops at 31 levels and says so.

The front ends are checked by hand rather than by the suite, which runs
in-process and shells out to nothing: source, bytecode, the prompt, arguments,
an extensionless script and a `chmod +x` one were each run.

### A calculator, and the frame limit met at last — `4bd7c7e`, 2026-08-21

[examples/evaluator.sol](../examples/evaluator.sol) tokenises, parses and
evaluates arithmetic — precedence, brackets, unary minus — and says where it
went wrong when the input is bad.

Deliberately a different **shape** from log.sol, which is line-oriented: read
text, split it, tally it. This one recurses, builds a tree of objects, and has
to report a position. Written because the last program found nothing the
language lacked, and a program that finds nothing is only evidence about
programs of its shape.

**It reached the recursion limit, which nothing had before.** A
recursive-descent parser spends about three frames per level of bracket nesting
— expression calls term calls factor calls expression again — against the
machine's 62. It manages **18 brackets deep** and stops at 19.

**And the failure is catchable**, which was not obvious. `call depth exceeded`
arrives at `onError` like any other, is reported like any other, and the program
keeps working afterwards. Running out of frames is exactly the sort of failure a
machine might not be able to recover from. Recorded against
[ROADMAP 3.5](ROADMAP.md#35-recursion-is-limited-to-about-62-levels), because it
lowers what raising the cap would buy.

Two smaller things, both written into the example where they bit.

**The group-temporary idiom does not compose.** `( | t | ... )` twice in one
block is a compile error, groups sharing the frame they sit in — which is the
documented rule, met for the first time in practice. A constructor block is the
answer and is better code anyway.

**`ifTrue` with two arguments is not caught until it runs**, which happened
twice while writing this. The compiler knows `ifTrue` well enough to inline one
but not what the receiver is, and **any object may define an `ifTrue` of its
own taking two** — which was checked, and works. So it cannot refuse the wrong
count. That is the same ignorance that keeps a counted loop from being inlined,
and it is the price of everything being a message rather than an oversight.

One bug of mine, fixed in the writing: reporting a position past the end of the
input used the token *count* where a *column* was wanted. They agree often
enough on short input to look right.

### The log analyser survives damaged input — `041467d`, 2026-08-21

[examples/log.sol](../examples/log.sol) assumed its input was well-formed:
every line split into exactly six fields and every field parsed. Fed a real
log it would stop at the first truncated line. It does not any more, and three
of the lines in its own sample are now broken on purpose so that running it
shows the recovery:

```
3 lines could not be read
  line 8: wanted 6 fields, got 4
  line 13: 'four' is not an integer
  line 18: wanted 6 fields, got 4
```

**It is the first program here that could not have been written before 0.2.0**,
which was the point of writing it.

Three things it found.

**`parse` should say what is wrong with a line rather than let the first message
that cannot cope fail on its behalf.** `f:at(#4)` on a short line answers `index
#4 is out of bounds for an array of size 3` — true, and no use to somebody
looking at their log. Checking the field count and raising `wanted 6 fields, got
4` costs one line and is the difference between a complaint about the program
and a complaint about the input.

**The machine says what, the program says where.** `'four' is not an integer` is
a good message and a poor report on its own, because it does not say which line.
Only the program is counting lines, so only the program can add that. Neither
half is worth much without the other, and the split falls out naturally rather
than being arranged.

**Surviving a bad line is not the same as surviving a bad file.** Fed pure
rubbish, every line was skipped correctly and then the summary fell over on
`entries:at(#1)` — there was no first entry to ask the time of. Caught by trying
it rather than by thinking about it, which is the argument for trying it.

What did not come up: `ensure`. Nothing in this program acquires anything that
must be given back, which is exactly what
[6.17](COMPLETED.md#617-there-is-no-ensure--done) predicted when it said nothing
needed it yet.

## 0.2.0 — 2026-08-21

**A failure can be recovered from.** That is the whole of this release: raising
one deliberately, catching one, passing on what you did not mean to catch, and
cleaning up either way.

```
{ system:readFile(path) }:onError({ e | "" }).
error:raise("bad input on line 3").
{ working:value }:ensure({ tidyUp:value }).
```

`.sob` stays at **format version 11** — nothing about the instruction set or the
file layout changed, so a `.sob` built by 0.1.0 runs here.

What it does not include: there is still no taxonomy of failures, so `onError`
catches everything and telling one kind from another means checking
`e:message`. Inventing a hierarchy to go with a catch mechanism would have been
inventing it in the wrong order, and the error being an object rather than a
string leaves room to say more later without breaking any handler.

The restrictions in [ROADMAP section 3](ROADMAP.md#3-known-limitations) are
otherwise unchanged: no non-local return, a capturing block tied to its frame,
recursion to about 62 levels, text is bytes.

Verified for the release: clean build with no warnings, `make test` and
`SOLUM_GC_STRESS=1 make test` both passing, all 23 examples compiled and run,
and zero leaks across every test binary.

### `ensure` — cleaning up regardless — `e001b8e`, 2026-08-21

Roadmap 6.17, written down one commit ago on the grounds that nothing needed it
yet.

```
{ working:value }:ensure({ tidyUp:value }).
```

Runs the cleanup whether the body finished or not, then goes on doing whatever
the body was going to do. Answers the **body's** answer.

**The difficulty is that a failure has to be set aside for the cleanup to run at
all.** `had_error` is what stops the machine, and the dispatch loop tests it
after every instruction — so a cleanup started with the flag still up would
manage one instruction and stop. The failure is lifted out complete with its
message and stack, the VM given fresh buffers for the duration, and the whole
thing put back afterwards.

**`system:exit` is set aside the same way**, which the entry did not anticipate.
It travels by the same flag, and giving back a thing you borrowed is as
necessary when a program is stopping as when it is failing. The cleanup runs and
the program still leaves with its status.

**When both fail, the body's failure wins** — the wrinkle the entry named, and
the answer it guessed was right. The first error wins here as it does
everywhere.

An uncaught failure that passed through a cleanup keeps its own message and its
own stack, so it names where it happened rather than where it was tidied up
after.

Unlike `onError`'s handler the cleanup always runs, so one that is not a block is
refused every time rather than only when something fails.

### An error can be caught — `29f358f`, 2026-08-21

```
{ nil:frobnicate }:onError({ e | e:message:display }).
text := { system:readFile(path) }:onError({ e | "" }).
error:raise("bad input on line 3").
```

`onError` answers the receiver's answer when nothing went wrong and the
handler's when something did, so it is an expression. A caught error says
nothing — which is what the previous commit's deferred reporting was for.

**The error is an object**, delegating to a new `error` global, with its message
in a slot. A value rather than a string on purpose: this project rewords its
errors freely, so handing a handler the text and nothing else would make
matching on it the only way to tell failures apart — an idiom these very habits
would keep breaking.

**`error:raise` is the only way to raise**, so re-raising is
`error:raise(e:message)`. Two spellings — one on the class taking a string,
another on an instance taking none — would be one name meaning two things, which
is the mistake this language already made once with `new`. The price is that a
re-raised error's stack points at the re-raise rather than the original failure,
which is honest: it *is* a new raise.

**It catches everything**, including a misspelled message, as decided. The
hazard is real and the way out is one message wide.

`system:exit` is not caught: it travels the same way but is a stop rather than a
failure.

#### The bug this nearly shipped with

`sol_vm_call_block` restored the frame count on failure but **not the stack
pointer**. That was invisible for as long as every error unwound to
`sol_vm_run`, which resets the stack on its way out — so nothing between the
failure and the top ever had to leave things tidy.

Catching stops the unwind part-way, and everything the unwind was allowed to
leave behind is suddenly still there. It showed up as:

```
xs:add({ error:raise("x") }:onError({ e | e })).
solvm: block does not understand 'add'
```

— the failed call's receiver and arguments still on the stack, so the next send
found the wrong thing. `sol_vm_send` had always restored its own stack mark;
`sol_vm_call_block` now does too, which gives every caller the invariant rather
than making each catcher clean up.

There is a test for it, and for 20,000 catches in a loop not creeping the stack
upward a few slots at a time.

Also recorded: **there is no `ensure`**, and roadmap 6.17 says why it was left
out rather than guessed at.

### An error is text the machine holds — `80818f9`, 2026-08-21

Groundwork for catching one, and **nothing about the visible behaviour has
changed** — which is the point of landing it on its own.

`sol_vm_runtime_error` used to write the message and the stack straight to
stderr from wherever the failure was. It builds them into `vm->error_text`
instead, and `sol_vm_run` writes that out before returning, when nothing has
caught it. Nothing catches anything yet.

The reason for the shuffle: **a message already on stderr cannot be taken
back.** A handler has to be able to see an error and decide, and that is
impossible while the report happens at the point of failure.

The whole test suite passed untouched, which is the evidence that the behaviour
is the same, and a program's output was diffed byte-for-byte against the
previous build to be sure the ordering had not shifted either.

One thing did change, for the better. **The first error now wins.** Building a
message can itself fail — a complaint that names a value renders it, and
rendering sends `asString` — and that used to print twice. The failure that
started it is the one worth reporting; the one that followed is a consequence of
trying to report it.

`system:exit` unwinds through the same flag and is not a failure, so it records
nothing and says nothing, as before.

## 0.1.0 — 2026-08-21

**The first release.** Everything below this heading is in it.

What that means and does not mean:

- **The language is settled enough to write programs in.** It has been stable
  for the whole of the work leading here, and everything added has been
  additive except two deliberate breaks, both before this line: `@include` gained
  its `@`, and `new` came off the classes that construct nothing.
- **`.sob` files are version 11 and are not portable across versions.** A file
  from an older build is refused with `unsupported bytecode version` rather than
  misread, and there is no compatibility promise between releases — recompile
  the `.sol`. See [ROADMAP 3.4](ROADMAP.md#34-no-compatibility-across-sob-versions).
- **0.1 rather than 1.0** because the restrictions in
  [ROADMAP section 3](ROADMAP.md#3-known-limitations) are real and deliberate:
  no non-local return, capturing blocks tied to their frame, recursion to about
  62 levels, text is bytes, and no way to recover from an error. Each is
  documented where a program would meet it.

The tests pass under `make test` and under `SOLUM_GC_STRESS=1 make test`, every
one of the 22 examples compiles and runs, and `leaks` reports none across the
whole suite.

### The counted loops are built in — and not by inlining — `c56a3c4`, 2026-08-21

Roadmap 6.6, finished. `repeat`, `toDo` and `toByDo` are primitives now.

```
#3:repeat({ "tick":display }).
{ "tock":display }:repeat(#2).
#1:toByDo(#10, #3, { n | n:display }).       ; 1 4 7 10
```

**The entry asked for inlining and inlining was the wrong answer**, which is
worth recording because the reasoning was not obvious until it was tried.

Per iteration the Solum version pays a block call for the body, plus a
`lessThan` and an `add` send for the counter. Inlining removes the block call
and keeps the two sends. A primitive removes the two sends and keeps the block
call. Over 200,000 iterations:

```
library (Solum)      0.0601 s
inlined by hand      0.0470 s     -- what the entry asked for
primitive            0.0186 s
```

**3.2× the library version, and 2.5× faster than inlining would have been.** The
sends cost more than the block call — the opposite of what the entry assumed.

**Inlining was also the harder half.** A counted loop's receiver is whatever
expression you wrote, and its type is unknown while compiling, so
`1.5:repeat({...})` has to go on saying *float does not understand 'repeat'*
rather than complaining about the counter. Inlined jumps would need a type-guard
instruction carrying the message name — a new opcode, and a `.sob` version with
it. A primitive gets it from dispatch for nothing: `repeat` is installed for
integer receivers, so a float never finds it.

`toByDo` gained two things it could not have in Solum. A step of `#0` is now an
error rather than a printed complaint followed by a silent no-op. And a step
that would carry the index past `INT64_MAX` ends the loop instead of wrapping to
the bottom and running for ever, in both directions.

**The library is nearly empty**, which is the record rather than a regret. It
opened yesterday with five loops; four have been measured and all four were
worth building in. `timesCollect` is what is left — the one nobody has measured.
The search path and `@include` finding a name it was not told the location of
are unchanged, and were always the part that mattered.

Defining any of the four in the library again would be a trap rather than an
override: a slot bound on `integer` shadows the primitive, so the slow version
would quietly win.

### The script has a frame like everything else — `5f69049`, 2026-08-21

`.sob` format **version 11**. `SolChunk` carries a `slot_count`, and
`sol_vm_run` reserves those slots before the first instruction exactly as
`push_frame` reserves a method's.

**A temporary at the top level of a script works now**, and used to be refused:

```
#1:add(( | t | t := #5. t )):print.        ; #6
( | a, b | a := #2. b := #3. a:mul(b) ):print.    ; #6
```

The refusal was real and the reason was real: the script's frame reserved no
slots, so a name declared there was emitted as `OP_SET_LOCAL` against the bottom
of the expression stack, where it overwrote whatever the enclosing expression had
put there. The verifier refused the result, so `solas` failed at the file write
saying the bytecode was inconsistent, while Solis — which runs what it just
compiled without verifying — answered wrongly instead. Refusing it in the
compiler reported one mistake once. Giving the frame slots means there is
nothing left to refuse.

The whole script is **one** frame, so two groups in a file share a namespace and
cannot both declare `t` — the same rule two groups inside one block already
lived by.

**It came out of roadmap 6.6**, which is about inlining the counted loops.
`repeat` needs a counter that survives the iteration and there was nowhere to
keep one; the entry offered two homes, both bad — new opcodes for stack-slot
arithmetic, or a hidden local that works inside a block and not in a script. The
third, found by explaining the first two, was that a script's frame is the only
one that reserves nothing, and that this is also why top-level temporaries were
refused. **One missing field, two problems.**

The header's reserved `u16` at offset 6 is where the count went — the top-level
chunk is the only one whose frame size is not already carried by the method that
owns it, so it is written once rather than on every method's chunk.

Nothing on disk survives the change, and nothing pretends to: a version 10 file
is refused with `unsupported bytecode version` rather than misread.

The counted loops are still unbuilt, but they are now compiler work with no
format change behind them. Whether they are worth building is the question the
measurement already answered — `repeat` costs 1.30x, where `doUntil` cost
2.29x — and the large win was the one that needed no slots.

### `doUntil` is built in, and compiles to jumps — `413c57b`, 2026-08-21

Roadmap 6.6, the half of it that could be had without changing the instruction
set.

```
lines := #0.
{ lines := lines:add(#1) }:doUntil({ lines:greaterOrEqual(#3) }).
```

**The entry sat unbuilt because the wrong construct was measured.** `repeat`
costs one block call an iteration and inlining it buys 1.30x, which is not worth
a change. `doUntil` pays for **two** — its condition is a block as well as its
body — plus the `done:not` send the library version needed. Over 200,000
iterations:

```
library doUntil   0.0706 s
hand-written flag 0.0395 s
inlined doUntil   0.0309 s
```

**2.29× the library version, and 1.28× the loop it replaces.** The second number
is the point: writing that loop by hand needs a `done` flag outside it, and the
flag costs two sends an iteration that jumps do not need. `doUntil` is now the
*fastest* way to write it rather than a convenience paid for.

**The wrinkle was the complaint, not the loop.** The shape is `whileTrue`'s with
the body in front of the test and the sense inverted, and there is no
`OP_EXIT_IF_TRUE`. Adding one meant a new opcode *and* a name index on it, since
`OP_EXIT_IF_FALSE` carries none and words its error as `whileTrue`. Instead
`OP_CHECK_BOOL` — which already carries a name and already refuses a
non-boolean — goes in front, so the unnamed instruction can only ever see a
boolean. No new opcode, no format change.

A test asserts the inlined and sent forms produce the same first line and that
neither says `whileTrue`.

**It left the library.** `lib/control.sol` defined `doUntil` and no longer does:
a definition there would be a trap rather than an override, bypassed exactly
where it was most wanted.

**`repeat` and `toByDo` stay library code**, and building this found out why they
are a different problem. Nothing survives between iterations of `whileTrue` or
`doUntil` — the condition is re-evaluated and the boolean consumed. A counted
loop has an `i` and a limit that must live across passes, and there is nowhere
for them: the value stack has no instruction that compares or increments a slot
in place, and a hidden local works inside a block but not at the top level of a
script, which has no frame. That would make the optimisation apply in some
places and not others, which is worse than being slow. The roadmap entry records
both options.

### An array can be sliced — `b156bcd`, 2026-08-21

Roadmap 6.16, the other thing [log.sol](../examples/log.sol) wanted — twice.

```
[#1, #2, #3, #4, #5]:copyFrom(#2, #4).   ; [#2, #3, #4]
[#1, #2, #3]:first(#2).                  ; [#1, #2]
[#1, #2, #3]:last(#2).                   ; [#2, #3]
```

The example's hand-rolled `firstFew` walk is gone; it says `:first(#5)` now.

**`copyFrom` is the string's rule, transcribed rather than reinvented.** Both
ends included, both one-based, the empty slice spelled with `to` one before
`from`, and out of range an error — following `at`. Two collections disagreeing
about what a slice means would be worse than either rule is good.

**`first` and `last` clamp, and that is a second rule on purpose.** `copyFrom`
names *positions*, and one outside the array is a program wrong about something.
`first` names a *quantity* — give me the top five — which a list of three has
answered correctly by handing over three. Refusing there would make every ranked
report check the size first, which is what these exist to avoid. One rule would
have been tidier and wrong. A negative count is refused by both: clamping is for
asking for more than there is, not for nonsense.

**One thing the change exposed.** `log.sol`'s "busiest paths" ranks by count,
and four paths tie at two apiece for three places — so which three appeared
depended on the order `dictionary:values` handed them back. Arbitrary but not
random, so it was stable per build and looked fine, and it had quietly changed
when the tally became a dictionary. The report breaks ties on the key now, and
is the same every run.

### An include search path, and a library to find on it — `1a783b2`, 2026-08-20

Two halves. `@include` gained a search path, and `lib/control.sol` is the first
thing that ships on it:

```
@include "control.sol".

#3:repeat({ "tick":display }).
{ lines := lines:add(#1) }:doUntil({ lines:greaterOrEqual(#3) }).
#1:toByDo(#10, #3, { n | n:display }).       ; 1 4 7 10
#4:timesCollect({ n | n:mul(n) }):print.     ; [#1, #4, #9, #16]
```

**The library was the easy half.** Its contents have been sitting in
[ideas.md](ideas.md) working for months. What stopped them being a library was
that `@include` resolved only against the file including it, so a shipped file
could be reached only by an absolute path baked into every program or by copying
it next to each one. Neither is a standard library.

**So: `-I dir` on `solas` and `solis`, then `SOLUM_PATH`, then the library
shipped beside the binary** — `bin/solas` looks in `bin/../lib`. A name not
found beside the includer is looked for in each, in order, and the first that
has it wins.

That is C's rule for a quoted include, and for C's reason: your own files are
found without ceremony, and a name you do not have locally comes from the
library. It carries C's cost too — a local file shadows a library one of the
same name — which showed up immediately. The first draft of the example was
`examples/control.sol`, which included `"control.sol"`, found **itself** beside
it, and, a file being compiled once, quietly did nothing. It is
`examples/loops.sol` now, and the trap is written down in both the guide and the
reference.

**What went in, and what did not.** `repeat`, `doUntil`, `toDo`, `toByDo`,
`timesCollect`. Not `caseOf`, which is also in ideas.md and also works: it is a
fine demonstration that the language needs no `switch`, and an array of
two-element arrays of blocks reached into with `pair:at(#1)` is not an interface
worth committing to. A library is a promise and the bar is higher than "it
works".

None of it is language. These are methods bound on `integer` and `block` by an
ordinary Solum file, which is possible only because control flow here is message
sending. `doUntil` earns its place by being the shape `whileTrue` cannot express
— the body before the test — so the flag that needs declaring outside the loop
is written once, in the library, rather than in every program.

Eight new tests: the path finding a file, beside-first beating it, the first
directory winning, an absolute name searching nothing, the not-found message
saying the path was tried, the library compiling and its loops working, and —
because a library that announced itself when you included it would be a poor
guest — that including it writes nothing at all.

This also changes what **roadmap 6.6** is waiting for. Nobody wrote `repeat`
before because writing it out per program was not worth it; it is one
`@include` away now, so if the 30 per cent it costs ever matters, it will be
because a program leaned on the library and noticed.

### A dictionary — `7e0726d`, 2026-08-20

Roadmap 6.15, wanted by [examples/log.sol](../examples/log.sol) and now used by
it.

```
counts := dictionary:new.
"the fox the dog the":split(" "):do({ word |
    counts:atPut(word, counts:at(word, #0):add(#1))
}).
counts:at("the"):print.          ; #3
```

`dictionary:new`, `at`, `at(key, default)`, `atPut`, `includes`, `remove`,
`size`, `keys`, `values`, `do`, `keysAndValuesDo`. Open addressing, tombstones
for removal, and a rebuild that drops them once they crowd the table.

**The entry offered two answers and called the wrong one smaller.** It proposed
`slotAtPut` — completing the reflection triple so an object could serve as a
dictionary — as the cheap option. Checking killed it. A slot name is interned in
the VM's **permanent** name table, so keys read from a file would leak a name
apiece; and slots are a **linked list walked linearly**, so an object-as-
dictionary would have had exactly the complexity of the array of pairs it was
replacing. Not smaller — wrong.

**Keys are values.** Numbers, strings, symbols, booleans and nil are compared by
content, so two keys that look alike are one key. Arrays, blocks, objects and
dictionaries are compared by identity, so two that look alike would be two keys —
right for `equals`, useless here, refused rather than surprising anybody. It is
the line the language already draws between values and references.

Two things fell out of taking that seriously: `-0.0` hashes as `0.0`, since the
two are equal and the table must not disagree with `equals`; and `nan` can be
stored and never found again, since it equals nothing at all.

`sol_value_equals` now exists and `prim_equals` calls it, so the table and
`equals` cannot come to disagree about what one key being another means.

**One bug, and it is the interesting part.** Adding a value type touches six
places. Five are switches with no `default`, and `-Wswitch` named every one at
the first build. The sixth — `mark_value` in the collector — was a chain of
`if (SOL_IS_...)`, compiled silently, and swept live dictionaries. It took a
segfault at 500 keys and a stack trace showing a freed struct to find. It is a
switch now, so the next type cannot slip through the same gap.

`tests/test_dict.c` has eleven groups: growth past several rehashes, churn until
tombstones force a rebuild, a dictionary holding itself, and two hundred freshly
allocated keys and values surviving a collection — that last confirmed to fail
when the marking is taken out.

### A log analyser, and the two things it could not say — `de39331`, 2026-08-20

[examples/log.sol](../examples/log.sol) reads an access log and reports on it:
totals, a breakdown by status, the busiest paths, the slowest requests, and the
failures. It takes a path from `system:arguments`, or writes a sample into
`build/` so it runs anywhere.

**It is the first program here written to do a job rather than to show a
feature**, which was the point. Every entry left in the roadmap was waiting for a
program to want something. This is what one wanted.

Most of it went in without complaint — `split` on the file and again on each
line, a prototype for an entry, `inject` for totals, `select` for the failures,
`sorted` with a block, `fill` with format specs for the columns. Two things did
not.

**There is no dictionary, and no way to build one.** Counting by key is most of
what a log analyser does. An object is a set of named slots and would serve —
except a slot name comes from the compiler. `perform` sends a computed name and
`slotAt` reads a computed slot, but nothing *binds* one, so an object cannot
stand in for a dictionary either. What the example does instead is keep an array
of key/count objects and walk it: O(n) a lookup, O(n²) over a file. Fine over
eighteen lines and the wrong shape over eighteen thousand. Recorded as roadmap
**6.15**, with the two ways to answer it — a `slotAtPut` completing the
reflection triple, or a real dictionary type — and the argument that the first is
smaller and the second is right.

**An array cannot be sliced.** No `first(#n)`, no `last(#n)`, no slice, so taking
the head of a sorted array is a walk with an index. Every report that ranks
anything wants it, and this one wants it twice. Roadmap **6.16**; `copyFrom` on a
string is the shape to follow.

Neither was a guess about what might be missing. Both are things the program
needed and had to work around, and the workarounds are in the example with
comments saying so rather than tidied out of sight.

Worth noting what did *not* come up: the loop constructs (6.6), a single keypress
(6.10) and a byte type (6.12) were all still unwanted at the end of it.

### `new` means one thing — `d58918c`, 2026-08-20

**Breaking.** `integer:new(#45)` and `float:new(1.5)` used to answer their own
argument. They refuse now:

```
integer:new(#45).
solvm: an integer is written #45, and there is nothing for 'new' to make -- #0 is the empty one
```

They constructed nothing — `return args[0]`, type-checked. That is the literal
spelled longer, and it was the last of the design in the original notes, where
you built a mutable integer and then `set` it:

```
integer:new(a)
a:set(#45)
```

Numbers became immutable unboxed values, `set` never existed, and `new` outlived
the thing it constructed.

**The rule that replaces it is mutability.** `new` belongs where something is
*made*, which is where the instances are references, so there is a fresh,
distinct one to hand back:

```
array:new:equals(array:new):print.    ; false -- two arrays
"":equals(""):print.                  ; true  -- one value
```

Two classes construct, `object` and `array`; the other six refuse and say what to
write. That rule sorts all eight correctly, and `class-and-instance.md` had said
no rule was available.

**They could not simply lose the message.** Deleting the registration was tried:
every built-in delegates to `object`, so `integer:new` inherited object's and
answered *an object delegating to `integer`*, which then fails `print`. Worse
than the identity function it replaced, and the same trap that made the other
four shadow rather than inherit. So the two joined the refusers.

`#45:new(#1)` refuses along with it, which removes one of the three symptoms
roadmap 2.5 is about. The other two are untouched — `integer:slots` still lists
`new` beside `add`, because the slot is still there and `slots` reports what is
there.

What this cost: a documented message, four tests, and the closing line of
[examples/hello.sol](../examples/hello.sol), which used `integer:new(#45)` as the
callback to the original notes. The example closes that loop better now, by
showing that *both* of the notes' messages went and why.

### `isNil` and `notNil` — `10ddf25`, 2026-08-20

Roadmap 2.14, the last of the loose ends from 2.8.

```
nil:isNil:print.                 ; true
"":isNil:print.                  ; false -- empty is not absent
```

`x:equals(nil)` said this already and said it awkwardly: a test for absence read
as a comparison against a value.

**Both, rather than `isNil` alone with `not` for the other.** The message that
actually gets written is the negative one — running out of input is how a loop
finishes — and `line:isNil:not` is worse than the `notEquals(nil)` it would be
replacing. A version with only `isNil` would have left the single real use of it
in the codebase no better off. `examples/reading.sol` was that use, and it now
reads:

```
line := system:readLine.
{ line:notNil }:whileTrue({ ... }).
```

**On every type, not on nil.** The receiver is exactly what is not known: the
point of asking is that the answer might be nil, so a message only nil
understood could not be sent to find out.

Neither confuses absence with emptiness — `""`, `#0`, `[]` and `false` all
answer `notNil`, and there is a test that walks every type asserting `isNil` is
the exact complement of `notNil` and agrees with `equals(nil)` on all of them.

`absence.md`, the guide, the reference and three examples now use the new
spelling where they used the comparison.

### Every concept the guide names has an example — `8a2546c`, 2026-08-20

Roadmap 6.9, the example audit. Two new programs,
[binding.sol](../examples/binding.sol) and
[strictness.sol](../examples/strictness.sol), and nineteen in all.

**The audit's answer was not the one the entry assumed.** It supposed the
examples were thin, having been written alongside whatever was being built at
the time. Measured against every selector registered in `builtins.c` — the
sharper question — **exactly one built-in message had never been sent in any
example**: `lessOrEqual`.

The real gaps were conceptual. Five of the guide's nineteen sections pointed at
no example, and two of those five were not gaps at all: `via` was in objects.sol
and `slotAt`/`boundTo` were in reflect.sol, neither pointed at from the section
that teaches them. Those needed a link, not a program.

The three that needed a program got two:

- **binding.sol** for names and binding, and for statements, groups and
  temporaries — the plumbing every other example uses without stopping to look
  at it.
- **strictness.sol** for errors and strictness: every refusal with its real
  error text and what to write instead. It **ends by failing on purpose**, three
  frames deep, because a stack trace is the one thing in that section no working
  program can show you.

**The audit is now a test**, for the same reason the instruction set reference is
one. `tests/test_compile.c` reads the registrations out of `builtins.c` and
checks that each selector is sent by some example, with `;` comments blanked out
first so a message appearing only in an error transcript does not count as
covered — and that blanking respects string literals, since files.sol has a `;`
inside one. A second check walks `examples/` and refuses any `.sol` missing from
the list the file verifies, so an example cannot ship unchecked. Both were
confirmed to fail when they should.

One thing the audit turned up that was nothing to do with examples: index.md
said **"Twelve programs"** and listed twelve, while seventeen shipped. It lists
all nineteen now, and the tutorial's count is right again too.

### The guide contrasts a group with a block — `4001efa`, 2026-08-20

Roadmap 6.8. Both are code in brackets, and nothing put them side by side.

```
m := { x | x:add(#1) }.
(m:value(#42)):print.            ; #43     -- the group ran, and answered
{ m:value(#42) }:print.          ; <block> -- nothing ran
{ m:value(#42) }:value:print.    ; #43     -- now it did
```

That example came from the roadmap entry. Writing it up turned up a better one,
which is the reason the contrast matters rather than a curiosity about brackets.
**An argument is evaluated before the send, like any other argument** — so
handing `ifTrue` a group means the group has already run by the time `ifTrue`
gets to decide anything:

```
false:ifTrue(("the group ran anyway":display. nil)).
false:ifTrue({ "the block did not":display }).
```

Only the first prints. Nothing in the compiler knows what `ifTrue` means; the
block simply has not been run, and `ifTrue` chose not to run it. Every
conditional and every loop rests on that, and a reader who has never seen the
two side by side has no way to see it.

A third difference explains a restriction the guide already described without
saying why: **a block makes a frame, a group borrows the one it is in.** A
group's temporaries are the enclosing block's, which is why one may only be
declared where a frame already exists — and why declaring a temporary at the top
level of a script is refused.

In the guide's §7, in the reference beside `Grouping`, and in
[examples/blocks.sol](../examples/blocks.sol) so the concept has runnable code
and not only prose.

### The instruction set has a reference, and the tests keep it honest — `8d7c558`, 2026-08-20

Roadmap 6.7. [docs/BYTECODE.md](BYTECODE.md) describes all twenty-one opcodes:
operands, instruction length, effect on the stack, and a worked disassembly.

The table in design.md was **missing six** — `OP_JUMP`, `OP_JUMP_IF_FALSE`,
`OP_EXIT_IF_FALSE`, `OP_LOOP`, `OP_CHECK_BOOL` and `OP_SYMBOL`. Every jump plus
the two newest, so it described the machine as it was before 4.1. The material
existed the whole time; `bytecode.h` documents each opcode at its definition and
the disassembler prints all of them. Nothing tied the document to the header, so
nothing said when it stopped being true.

**So the new page is checked rather than trusted**, by `tests/test_bytecode.c`,
three ways: every opcode in the header appears in the document, every `OP_` name
in the document still exists in the header, and every instruction length the
document gives matches `sol_op_length` — which is the one place lengths are
really written down.

The part that makes this hold up is that **the test maintains no list of its
own.** It reads the enum out of the header, and a C enum with no initialisers
numbers from zero upwards, so the order the names are written in is also their
value. Nothing to update, nothing to fall behind.

One mistake worth recording, because it is the kind this whole entry is about.
Taking any `OP_` at the head of a line found twenty-three opcodes instead of
twenty-one: the comments in the header wrap, and `OP_JUMP_IF_FALSE only in the
complaint it makes` starts a line too. The two phantom members shifted every
value after them, which surfaced as `OP_JUMP_IF_FALSE` apparently being three
bytes long. What tells a member from a mention is what follows it — a comma, or
the comment if it is the last one.

All three checks were confirmed to fail when they should, and the three
disassembly listings in the page were diffed against real `--dump` output rather
than transcribed. design.md keeps the operand-width rule and points at the new
page; it has no table of its own any more.

### A block can time itself — `661408d`, 2026-08-20

Roadmap 6.5. `{ ... }:timeToRun` answers the seconds the block took, as a float.

```
{ #20:factorial }:timeToRun:asString(".6"):display.
```

A float of seconds is what the roadmap called for, and for the reason it gave:
it is the only answer that needs no duration type. The block's own answer is
dropped — what was asked for was the time, and `{ ... }:value` is there when the
answer is wanted too.

**The entry missed something that changed the shape of the thing.** The clock has
a floor. Here it is a microsecond, by `clock_getres` and by watching the smallest
step between two readings, while one send and one add costs well under a tenth of
that. So a single run measures the floor rather than the block:

```
{ #1:add(#1) }:timeToRun:print.        ; 0, or 0.000001 -- the floor, either way
```

That is fatal to the entry's own purpose. It exists because every performance
number in this changelog was taken with `/usr/bin/time` around a whole process,
and the numbers it wanted instead are all sub-microsecond. Without a repeat count
the message cannot measure a single one of them.

So there is a count too. `timeToRun(#n)` runs the block `n` times and answers the
**total**:

```
total := { #1:add(#1) }:timeToRun(#200000).
total:div(200000.0):asString(".9"):display.      ; 0.000000088 -- or thereabouts
```

The total rather than the average, because the total is the measurement and the
average is a division you can do — and keeping the count in view is what tells
you whether the floor was cleared. A count below `#1` is refused: the answer
would be `0.0` whatever the block.

What is measured includes the cost of calling the block, a frame pushed and
popped. That is not overhead to subtract; it is what running the block costs.

This is what roadmap 6.6 has been waiting for. Inlining the loop constructs buys
speed rather than expressiveness, so it was never worth doing on a guess — and
now the Solum-written version and the inlined `whileTrue` can be measured against
each other first.

### Arrays fold, and strings go back together — `72df16b`, 2026-08-20

Roadmap 6.14. `inject` and `join`.

```
[#1, #2, #3, #4]:inject(#0, { total, n | total:add(n) }).   ; #10
"a,,b":split(","):join(",").                                ; "a,,b"
```

The entry set these against each other — a fold answers the gap once, where
`join` is the case that keeps coming up. **That was a false choice**, and
building one showed why. A fold cannot express `join` well: the separator goes
*between* pieces rather than before each, so folding one needs a flag or a test
for the empty accumulation — which is exactly the six lines being replaced. They
are not the general and the specific case of one thing; they are two things, and
both are built.

**`inject(start, block)`** completes the iteration messages. `do` throws its
answers away, `collect` and `select` each answer an array, and this answers one
value. An empty array answers `start` without ever calling the block, so a fold
is safe to write without asking first whether there is anything to fold. What
accumulates need not be the elements' type.

The cost of not having it was sharper than "a few extra lines": every reduction
had to be a `do` with an accumulator declared outside it, which works only at
the top of a frame. `inject` is an expression, so a reduction can stand in the
middle of one:

```
[#1, #2, #3, #4, #5, #6]
    :select({ x | x:mod(#2):equals(#0) })
    :inject(#0, { total, n | total:add(n) }).      ; #12
```

**`join(separator)`** is on array rather than string — it is the array that has
the pieces. Strict about them: an array holding anything but a string is an error
rather than a silent `asString` on each, since `asString` and `fill` are already
the messages that render things.

Its separator **may** be empty where `split`'s may not, and that asymmetry is
deliberate. Nothing can be looked for, since every position in every string
contains the empty string — but putting nothing between the pieces is exactly
concatenation.

`s:split(sep):join(sep)` is `s`, for every string and every separator. That round
trip is what `split` keeping its empty pieces was for, and it is now tested
rather than only argued.

One note on the collector, since the project's habit is to prove these
load-bearing: `inject` holds its accumulated value on the value stack, because
`sol_gc_push_temp` cannot hold an integer or a nil — neither has a header to
push. **That root is defensive, not load-bearing.** Taking it out passes under
`SOLUM_GC_STRESS=1`, because `sol_vm_call_block` pushes the receiver and
arguments before it can allocate, so the value is already rooted wherever a
collection can happen. It is kept anyway, and labelled: one stack slot against
relying on what another function does with its arguments, across an unbounded
number of calls back into the language.

Unrelated and found on the way: `test_nesting` in `tests/test_array.c` ran a
second chunk over the first without freeing it, leaking 800 bytes. It is a test,
not the VM, but it made `leaks` useless on that binary. Fixed.

### A string can be taken apart — `4d35540`, 2026-08-20

Roadmap 6.11. `split`, `indexOf` and `copyFrom`.

```
"a,b,c":split(",").              ; ["a", "b", "c"]
"hello":indexOf("ll").           ; #3
"hello":copyFrom(#2, #4).        ; "ell"
```

`readFile` answering a whole file as one string is what made this visible.
Counting the lines in a file was a character-at-a-time loop, and it was the least
pleasant code in the examples; it is now `text:split("\n")`.

**`split` keeps every piece.** There are always occurrences + 1 of them, so a
separator at either end or two together leaves an empty string where the missing
piece would be:

```
"a,,b":split(",").       ; ["a", "", "b"]
",a":split(",").         ; ["", "a"]
"abc":split(",").        ; ["abc"]   -- no occurrence, so one piece
```

That is what makes it predictable: the pieces put back together with the
separator between them are the string you started with, whatever it was.
Dropping empties would read more kindly on `" a  b "` and would lose the
difference between `"a,,b"` and `"a,b"` — usually the one thing a program
parsing a file needs to keep.

**`indexOf` answers nil when there is no match**, not `#0`, which is what the
roadmap called for. Indices start at `#1`, so `#0` would be out-of-band, and more
to the point it would be a second spelling of something the language already
spells: `text:indexOf(","):equals(nil)` is the same question an unset slot and
the end of input are already asked.

**`copyFrom` includes both ends**, both one-based, so `copyFrom(#i, #i)` is
exactly `at(#i)`. The thing the roadmap did not anticipate was needing to say
*nothing* — cutting a string at a mark has no answer for the front half when the
mark is the first character. An empty result is spelled with `to` one before
`from`, and only that far:

```
"hello":copyFrom(#3, #2).    ; ""
"hello":copyFrom(#4, #2).    ; error: ends at #2, more than one before its start #4
```

Neither `split` nor `indexOf` will look for the empty string: every position in
every string contains it, so the answer would be arbitrary.

All three go by the length rather than stopping at the first NUL. That was not
free — `strstr` was the obvious implementation and would have been wrong on
exactly the binary files 6.12 is about — and a test reads a file holding a NUL
and splits it.

**The inverse is missing.** There is no `join`, so putting pieces back together
is a walk with `do` and a flag, which [examples/strings.sol](../examples/strings.sol)
now shows in six lines that ought to be one. Underneath it there is no `inject`
or `fold` either, so every reduction over an array is that same walk. Recorded as
roadmap 6.14, and it is the next thing to do.

### `include` is a directive and now looks like one — `e215440`, 2026-08-20

Roadmap 6.13. `@include "library.sol".` replaces `"library.sol":include.`

```
@include "library.sol".

temperature:cToF(100.0):print.          ; 212
```

**The old spelling was a disguise.** It read as a message sent to a string and
never was one: no string was pushed, nothing was sent, and the whole thing had
vanished before the program ran. It was written that way because the language
had no directive syntax and no keyword to spare, and that shape already parsed.

The compiler paid for the disguise three times over — a two-token lookahead in
`statement` to spot one, a special error in `primary` to refuse the same shape
everywhere else it parsed, and a probe function nothing else in the grammar
needed. All three are gone. `@include` is one token, `@` and all, so a directive
announces itself at its first character.

But the cost that mattered was to the reader. A construct that looks like
ordinary syntax and obeys different rules teaches the wrong model: accept
`"lib.sol":include` as a send and you have learned that a send might happen at
compile time, which is true of no other send in the language. That is the
objection that sank the trailing-block shorthand, and it applies harder here.

**`@` names a space, not a word.** What follows it happens while compiling, and
nothing in that space is a message to anything. An unknown directive is refused
rather than passed through:

```
[prog.sol:1:1] solas: unknown directive at '@compile'
  @compile "library.sol".
  ^^^^^^^^
```

`@include` is the only member, and may stay the only one. It earns the sigil
with one, by marking the single construct in the language that is not run time.

A sigil also costs nothing that a keyword would have cost. No identifier can
begin with `@`, so `include` is not reserved and any object may still use it as
a slot name. One argument for a bare `include` keyword nearly held — that
everything happening at run time in Solum has a colon in it, so a colon-free
statement already reads as not-a-send — but it is false: `x.` is a legal
statement, colon-free and entirely a run-time one.

Semantics are untouched: the same splice into the includer's scope, the same
resolution relative to the including file, the same once-per-compilation keying,
the same cycle stop. Three new tests cover the new refusals, and the lexer test
that used `@` as its example of an unexpected character now uses `%`, `@` no
longer being one.

One consequence elsewhere. The entry below gives three reasons for putting
`readFile` on `system` rather than on a string, and the third was that
`"lib.sol":include` would look identical beside `"lib.sol":readFile`. That
collision is now gone. The first two reasons were the load-bearing ones and the
decision stands.

### A program can read and write files — `63bb836`, 2026-08-20

Roadmap 6.4, whole files as strings.

```
system:writeFile("notes.txt", "apples 3\npears 12\n").
system:readFile("notes.txt"):size:print.         ; #18
system:fileExists("notes.txt"):print.            ; true
```

**They are on `system`, not on the string naming the file.** The roadmap
sketched `"notes.txt":readFile`, which reads better, and three things decided
against it: a string knows nothing about files, and putting them there gives
every string in the program a message about the filesystem; `system` is already
defined as what belongs to the process rather than to any value, and a file is
the world outside; and `"lib.sol":include` already means something on a string
literal — a compile-time directive — so `"lib.sol":readFile` beside it would be
two identical-looking sends that are not the same kind of thing at all.

**A missing file is an error, not nil**, which the roadmap called the real design
work and got right. It is the answer an out-of-range index gets, for the same
reason: a program asking for a file it has not got is wrong about something.
`readLine` answering nil at the end of input is not the precedent it looks like —
running out of input is how a loop *finishes*.

`system:fileExists(path)` is how to ask first, and it answers **false for a
directory**, because that is what `readFile` says about one too. A `fileExists`
that disagreed with `readFile` would be a trap rather than a way to look before
leaping.

`writeFile` replaces what is there, creates the file if it is not, and answers
nil. It reports failure from `fclose` as well as `fwrite`: a buffered write fails
when the buffer is flushed, so a full disk announces itself at the close and not
at the write that filled it.

**Binary already round-trips.** A string is bytes, a NUL is a byte like any
other, `size` counts it, and reading a file and writing it back copies it
exactly. Taking one *apart* still does not work, `at` answering a
one-character string rather than a number, and that half of the entry stayed
behind as roadmap 6.12 with a number of its own.

Writing this opened a gap worth its own entry. A file arrives as one string and
**there is no way to split it** — no `split`, no `indexOf`, no substring — so
counting lines is a character-at-a-time loop, which
[examples/files.sol](../examples/files.sol) has and which is the least pleasant
code in the examples. That is roadmap 6.11, and it is now the next thing to do:
a file you cannot take apart is half of file handling.

`tests/test_system.c` gains seven cases — the round trip, replacing rather than
appending, an empty file being a file, bytes surviving with a NUL among them, a
20,000-byte file, the eight ways a bad call is refused, and `fileExists`
declining a directory.

### A program can read its input — `4aefa0c`, 2026-08-20

Roadmap 6.3. `system:readLine` answers one line of standard input without its
terminator, or **nil** when there is no more.

```
line := system:readLine.
{ line:notEquals(nil) }:whileTrue({
    line:display.
    line := system:readLine
}).
```

**Nil at the end is the one place absence is not treated as a mistake here.**
Everywhere else the language would rather refuse than answer nothing — an
out-of-range index is an error, an unset slot is a miss. Running out of input is
different: it is how a loop that reads to the end *finishes*, not something that
went wrong, and a program that has to check for it on every pass anyway loses
nothing by checking for nil. An empty line is `""` and is not the end, so the
two never get confused.

Three details that are only visible when they are wrong, and are tested:

- A last line carrying no newline of its own still counts as a line.
- `\r\n` is one terminator, so a file written on another system reads the same
  as one written here.
- A line of any length comes back whole. It is read in 256-byte chunks and
  grown, which is the bug Solis had before 5.1 — a long line severed mid-token,
  its tail arriving as if it were the next line.

The reader is not shared with Solis', which keeps the newline because its scanner
needs it and appends to a buffer that outlives the call. Different enough that
sharing would have meant parameterising both.

At the prompt, `readLine` reads the next line you type and Solis does not see it
— the program and the prompt are reading the same input, and there is no third
thing for them to disagree about.

**Waiting for a single keypress was split out rather than carried along**, and is
now roadmap 6.10 with a number of its own. It needs raw terminal mode, which
would be the first piece of the runtime that behaves differently by platform, and
that deserves its own decision rather than arriving as a footnote to line input.

`tests/test_system.c` gains five cases, driving stdin from a file:
`examples/reading.sol` numbers what it is given and reports the longest line.

### A program can stop, and knows what it was given — `e8d4fe8`, 2026-08-20

Roadmap 6.2. `system` is a global holding one object — not a class, since there
is one process and it has no instances — and it is where what belongs to the
program rather than to any value now lives.

```
system:exit(#0)          ; stop, with a status
system:arguments         ; an array of strings
system:clock             ; monotonic seconds as a float
```

**`exit` unwinds rather than leaving from under the machine.** Every frame is
discarded the way an error discards them, control returns through `main`, and
whatever the C library was holding is flushed on the way out. Calling `exit(3)`
from the primitive would have skipped all of that, and would have made a
program's last line of output depend on whether stdout happened to be a
terminal. Nothing after the exit runs, including the rest of a loop it was called
inside:

```
[#1, #2, #3]:do({ n | n:print. n:equals(#2):ifTrue({ system:exit(#3) }) }).
```
```
#1
#2
```

That works because the VM already had a flag every loop tests before continuing
— the one an error sets. An exit has to unwind through exactly those loops, so it
sets the same flag rather than adding a second test to each of them, and a
second flag beside it says which of the two reasons it was. The cost was one
enumerator, `SOL_EXIT`, and one `?:` at the bottom of the dispatch loop.

**A status is #0 to #255**, and anything else is an error rather than a number
quietly adjusted to fit. POSIX keeps only the low eight bits, so `#256` would
otherwise leave with 0 and look like success — the quiet mistake the language
refuses everywhere else.

**`arguments` needed no primitive.** It is a data slot holding an array, because
that is what it is: the same array every time, not a fresh one, so
`system:arguments:equals(system:arguments)` is true. It is the *empty* array when
there were none rather than nil, so a program can walk it without first asking
whether it is there. solvm hands it over with `sol_vm_set_arguments`, which
builds the array the way every array of fresh values is built here — nils first,
so the backing store grows while nothing new is live.

**`clock` is monotonic seconds as a float**, and its epoch is deliberately
unspecified: the only useful thing to do with two readings is subtract them, and
a wall clock can go backwards in between. It is what 6.5 was waiting for.

Everything after the `.sob` on the command line now belongs to the program, so
solvm's own flags have to come first — `solvm --dump prog.sob` rather than
`solvm prog.sob --dump`, which now passes `--dump` to the program. And
`system:exit` works at the prompt for the same reason it works in a program:
Solis runs the same machine, so `system:exit(#4)` leaves Solis with status 4.

`tests/test_system.c` covers the eight behaviours — the status arriving, nothing
running after, unwinding out of both a `do` and a `whileTrue`, the six ways a
status is refused, the empty default, the strings arriving in order as one array,
the clock being a float that does not go backwards, and `system` being an
ordinary object. `examples/system.sol` is the runnable version. Clean under GC
stress, no leaks.

### The trailing-block verdict, argued properly this time — `8b4cf3a`, 2026-08-20

Documentation. No code, and that is the decision.

`a:equals(b):ifTrue{ dosomething }` — a lone block argument dropping its
parentheses. [ideas.md](ideas.md) already said no, and said it badly enough to be
worth redoing rather than leaving.

**The old entry called it a special case**: it works for `ifTrue` and `whileTrue`
and not for `ifElse`. That misread the proposal. The rule is *a lone block
argument may drop its parentheses*, and `ifElse` is not an exception to it but
outside it, having two arguments. The rule is uniform, and it reaches most of the
language rather than a corner: of the ten messages that take a block, nine take
exactly one — `and`, `collect`, `do`, `ifFalse`, `ifTrue`, `or`, `select`,
`sorted`, `whileTrue` — and only `ifElse` does not.

**The old entry's other objection was cost**, which is also not it. A block
cannot follow a send today, so the grammar has room and nothing becomes
ambiguous; it is one branch in the argument parser and one in the inlining probe.
Nor does "a second spelling for one thing" distinguish it from `[...]`, which is
a second spelling for `array:of(...)` and was accepted, both being byte-identical
sugar.

What the entry now says instead:

**It makes a message send look like syntax, exactly where the language works
hardest to prove it is not one.** Every document here says there is no `if`, and
the parenthesised form is the proof of that at every use site. The objection is
use-site specific, which is what makes it awkward — on `stock:do{ e | ... }`
nothing is pretending to be syntax — so the rule is least costly where it is
least needed and most costly on the conditionals, where it reads best. One rule
cannot tell those apart without becoming the special case it set out not to be.

**And it teaches a rule that does not generalise**, which is the decisive one and
Hans's. A reader meeting `ifTrue{ ... }` in a snippet has no way to see where the
rule stops. The next guess is `ifElse{ ... }{ ... }`, which is not valid and never
will be, and the one after that is that braces attach to selectors generally. The
cost is not paid by whoever learns the rule properly from the reference; it is
paid by whoever infers it from an example and infers something wider than what is
there. The parenthesised form has no edge to fall off.

### Finished roadmap entries moved to a document of their own — `1feb449`, 2026-08-20

Documentation. No code.

The roadmap was 1062 lines and most of it was done. It is now 365, and
**[COMPLETED.md](COMPLETED.md)** holds the rest — every finished entry as it was
written, which is the case for the work *before* the work was done: what the
problem was, what the options were, and why the shape chosen was the one taken.
That is not what a changelog entry says. A changelog says what landed and when;
these say why it was worth doing, and deleting them would have thrown the
argument away and kept only the outcome.

Sections **1** (blocking real programs), **4** (performance) and **5** (tooling)
left the roadmap entire, along with 3.9, the settled table from section 2, and
6.1, which was deleted three commits ago and is restored there rather than lost.
What stays behind is what is still live: **2.5** and the loose ends in 2.14,
section 3's limitations, and section 6.

Two entries were split rather than moved. **1.1d** — collection is stop-the-world
and non-incremental — is not work but a standing restriction, so it moved *into*
section 3 instead, joining 2.13 as an entry filed under a heading that is not its
number. And **1.1c** was still open when 1.1 was written and is not any more,
which the entry now says.

**Numbers are never reused**, which the new document says at the top and is worth
stating: the changelog cites them by number, and one number meaning two things at
two times would make every one of those citations ambiguous. So the gaps in the
roadmap — no section 1, no 4, no 5 — are a record rather than a mistake, and
prose that cites 4.1 or 1.6 still points somewhere exact.

### nil, empty, and unset, written down — `6d0c43c`, 2026-08-20

Documentation. No code.

The question was whether a fundamental type can be made without a value —
`mystring := string:nil.`, or `myint := integer:nil.`. It cannot, and the reason
turned out to be worth a page.

```
> a := string:nil.
solvm: object does not understand 'nil'
```

There is one nil and it carries **no type**. `nil` names the value rather than a
class: every other built-in type has a class object bound to a global, and nil
has none, so there is nothing for `string:nil` to reach. Nor would a typed nil
have anywhere to live — a name holds a value and never a type, so `mystring` is
not "a string that is currently empty" but a name bound to nil, indistinguishable
from one meant for an integer. Which is why what a value is gets asked of the
value: `isKindOf(string)` is false for nil.

**[absence.md](absence.md)** is new, and holds the whole of it: absence against
emptiness (`""`, `#0` and `[]` are values that answer their type's messages,
where nil answers a short fixed list and errors at everything else); the places a
nil arrives without being written — a branch that did not run, a loop's answer,
`parent` at the root, a temporary before assignment; and the asymmetry that
catches people, which is that **an unset slot is an error rather than a nil**:

```
> o := object:new.
> o:missing:print.
solvm: object does not understand 'missing'
```

A temporary is a slot in a frame that exists and holds nil, where a slot that
was never bound does not exist — so the lookup walks the prototype chain, finds
nothing, and reports the miss like any unknown message, because it is the same
thing. A prototype with an optional field therefore binds `nil` as its default,
the same defaulting any prototype slot does.

The last section is why a typed null is not wanted rather than merely missing.
It would have to answer a value that claims to be a string and answers no string
message — the quiet mistake the language refuses everywhere else — and without a
checker reading the program before it runs, it would be caught at the same send
an untyped nil is caught at. The version worth something is static, and that is
a type system rather than a value.

[REFERENCE.md](REFERENCE.md#nil) gained the rules in short form, the guide a
paragraph in §6 where values and references are settled, and the tutorial and
index a link. Two example counts were stale after the include commit added two,
and now say fourteen.

### A program can be split across files — `8922138`, 2026-08-20

Roadmap 6.1, and the first item of section 6 to be built. One line brings
another file in:

```
"library.sol":include.
```

That file is compiled into this one at that point, as though its text had been
written there. Nothing above a few hundred lines wants to live in a single file,
and until now there was no way to split one.

**Spelled as a send to a string because there was nothing else to spend.** An
include has to happen while compiling, so it is a directive and not a message —
but the language has no directive syntax and no keyword to spare, and
`"file":include` already parses. The compiler recognises the shape before the
send is emitted. That is also why it may only stand alone as a statement:
anywhere inside an expression there is nowhere for a file to go, and it is a
compile error rather than a send that would fail at run time. Sent to anything
but a string literal, `include` stays an ordinary selector anyone may define.

**The file is found beside the file including it**, not beside the working
directory, so a program can be moved as a piece. Source that is not a file — the
prompt, or a string handed to the compiler — has nothing to be relative to, and
uses the working directory. This works at the prompt, which makes `include` also
the way to load a file into a session.

**A file is compiled once per compilation**, keyed by `realpath` so that two
spellings of one file are one file. C compiles it every time and leaves each
file to guard itself, which needs conditional compilation that Solum has not
got; and a second copy could only rebind names already bound and repeat whatever
the file did on the way. So two files may each include what they need without
arranging between themselves who includes what — and a cycle ends instead of
recurring, which is the same rule doing the work.

**The namespace stays flat.** Globals were one space and remain one: an included
file's names are indistinguishable from the including file's, and two files
binding the same name collide exactly as two `:=` in one file already do. A
module system is a much larger change to the object model, and a library that
wants a namespace can claim one global and hang the rest off it, an object being
a namespace already — [examples/library.sol](../examples/library.sol) does that.

**Compile errors name their file now**, which they did not need to when there
was only ever one:

```
[lib/broken.sol:2:6] solas: expected an expression at ':'
  y := :.
       ^
  ... included from lib/middle.sol, line 1
  ... included from prog.sol, line 3
```

The chain is printed by each level on the way out, so it accumulates without
anyone holding a stack. Source compiled without a file still reports `[line
2:6]`, exactly as before.

Under the hood: `SolParser` gained the path it is reading; `sol_compile_source`
takes one and `sol_compile` is now a call to it with none; `sol_read_file` moved
out of solas' `main` into the compiler, which needs it too; and the escape
decoding split out of `string_literal` into `decode_string`, since an include
needs the text of a file name and emits nothing at all. Includes nest 64 deep.

A `.sob` is still one chunk with no record of which file a line came from, so a
run-time trace gives a line number without saying which file counted it. That is
the one thing this leaves behind.

`tests/test_include.c` covers the nine behaviours — definitions arriving,
resolution against the including file, the diamond compiling once, a cycle
ending, a missing file, an error inside an included file naming both, an include
buried in an expression, the no-file case, and `include` surviving as an
ordinary slot name. `examples/library.sol` and `examples/include.sol` are the
pair, and both compile in the suite. No leaks.

### Assessed a notebook of ideas, and the roadmap has a section 6 — `2a348f0`, 2026-08-20

Documentation. No code.

Twenty-three ideas from a notes file, each with a verdict in
[ideas.md](ideas.md) and the ones worth building written up as roadmap section
6. The list had run out last week; this is what replaced it, and it came from a
better place than the old one — notes about what a program would want, rather
than a plan written before there were any programs.

**The largest finding is how little of it needs the language to change.** There
is no control-flow syntax, so `repeat`, `doUntil`, a stepped `for` and a
switch/case are all library code. They are written out and working in ideas.md:

```
#3:repeat({ "tick":display }).
{ i := i:add(#1) }:doUntil({ i:greaterOrEqual(#3) }).
#1:toByDo(#10, #3, { n | n:display }).
#2:caseOf([[{ n | n:equals(#2) }, { "two" }], [{ n | true }, { "many" }]]).
```

`forIn` is `do`. `do` is `forEach`, `collect` is map, `select` is filter.
`['red, 'green, 'blue]` already is an enum, since symbols compare by pointer.
Building the loops in would buy inlining rather than expressiveness, which is
6.6 and not urgent.

**What is actually missing is everything around the language.** A program has to
be split across files, read input, write files and stop with a status, and none
of that exists. `include` (6.1) is the item a real program hits first; a `system`
object with `exit`, arguments and a clock (6.2) is the smallest thing standing
between a script and a program.

**Two documentation gaps turned up while checking.** design.md's instruction
table is **missing six opcodes** — `OP_JUMP`, `OP_JUMP_IF_FALSE`,
`OP_EXIT_IF_FALSE`, `OP_LOOP`, `OP_CHECK_BOOL` and `OP_SYMBOL`, which is every
jump and the two newest, so it describes the machine as it was before 4.1. And
`(group)` and `{block}` are introduced separately and never contrasted, which is
where the difference lands:

```
m := { x | x:add(#1) }.
(m:value(#42)):print.        ; #43
{ m:value(#42) }:print.      ; <block>
```

**Six ideas are recommended against, with the reasoning recorded** so it does not
have to be re-argued: integer widths and a separate 32-bit float, both of which
reintroduce the coercion the language refuses everywhere; a JIT, which is
possible and would be larger than the rest of the project combined, with nothing
to specialise on until there are inline caches; cascades, which Smalltalk needs
because its setters answer the argument and Solum does not, since `add` answers
the array; a trailing-block syntax, which can be made uniform but is a second
spelling for two saved characters; and Go-style concurrency, which is a rewrite
rather than a feature — one heap, one stop-the-world collector, frames in a
fixed array on the VM.

**One is deferred rather than refused.** `$character` literals cannot be decided
apart from what a string is: today a string is bytes, so a character is either a
code point — which is the whole Unicode job — or a byte, in which case `$😊`
cannot exist and the type buys little. Adding an ASCII-only one now would make
the later decision harder.

### The last item on the roadmap was already done — `ee43086`, 2026-08-20

Roadmap 5.2 ended by saying `sol_value_print` prints `<object 0x...>` instead of
sending `print` to the object, and wants dispatch from inside the printer or a
`printOn:`-style protocol. That was the one concrete thing left on the list.

It had not been true since `f55e105`, and the entry had been read off the
function's name rather than off what it is handed. `print` the message goes
through `prim_print`, which has a VM and does send `asString` — which is what
`5.2` was, and why an object defining `asString` is shown that way by `print`,
`display`, `fill` and array rendering alike.

`sol_value_print` had exactly one caller: the disassembler, rendering a pooled
constant. And a constant is only ever an immutable scalar — `check_constants`
refuses objects, blocks, arrays, strings, delegates and symbols outright — so
there was never a receiver there to ask. Passing no VM was correct by
construction.

So there was nothing to build, and the fix is to stop the name inviting the
misreading a third time: it is now a static `print_constant` in `bytecode.c`
beside its only caller, named for what it prints, and `value.h` is one public
symbol smaller.

**Sections 1, 3, 4 and 5 of the roadmap are now done**, and the list has run
out. What is left is 2.5 — smaller than it was, since the single root turned out
not to be waiting on it — and whatever the first real program written in Solum
asks for.

### Why a built-in cannot be subclassed — `6d89cac`, 2026-08-20

Documentation. No code.

`class-and-instance.md` says a value type cannot be subclassed and gives the
reason in one line of `sol_vm_class_of`. That leaves the obvious next thought
unanswered: surely this is just a missing constructor, and if `integer:new`
answered an object delegating to `integer` — the way `object:new` answers one
delegating to its receiver — you would have a subclass and could add to it.

It is a reasonable thought, and for user-defined objects it is exactly right:
`p := point:new` and `tip := point:new` are the same operation, and which one is
a subclass is how you use it. So the document now shows why it does not carry
over, by building it. On a throwaway copy, `integer:new` with no argument
answering `sol_object_new(vm, vm->integer_class)`:

```
a := integer:new.
a:isKindOf(integer):print.       ; true
a:tag := #7.                     ; a real object, slots and all

a:add(#1).       solvm: 'add' expects an integer, got object
a:double := { self:mul(#2) }.
a:double.        solvm: 'mul' expects an integer, got object
```

It inherits every method name and can run none of them — including a method you
wrote yourself, the moment it touches anything inherited. `integer`'s methods are
C primitives that read an 8-byte payload an object does not have, so a built-in
class hands down an **interface and no implementation**. It is the same inert
object `string:new` would have produced, which is why those four refuse.

Two independent things stop it and either would suffice: an unboxed value
carries no class pointer, and the inherited methods need the exact
representation. A behaviour object per built-in would not help, since `#45`
would still dispatch by type tag.

### One hierarchy: every built-in class delegates to `object` — `a0b0d41`, 2026-08-20

No `.sob` change. `#45:isKindOf(object)` is true now, and "everything is an
object" holds of the type graph rather than only of the slogan.

```
#45:isKindOf(object):print.            ; true
"s":isKindOf(object):print.            ; true
nil:isKindOf(object):print.            ; true
integer:parent:equals(object):print.   ; true
object:parent:print.                   ; nil   -- the chain ends here
```

**This was believed to need the class-side/instance-side split first**, on the
grounds that a built-in inheriting object's `new` would answer a plain object
rather than a value. Two earlier commits had already removed that and nobody
noticed: `7ac6be6` gave `float` its own `new` — `integer` and `array` have
theirs — so those shadow object's; and `1.6` gave every primitive a receiver
requirement, so `via` and `parent`, the only two messages `integer` does not
already define, are refused for any receiver that is not an object. Roadmap 2.5
is corrected.

So the change is eight lines setting each class's prototype, plus the one thing
that really was in the way.

**Four classes cannot make their instances, and now say so.** `string`,
`symbol`, `block` and `boolean` have no `new` of their own and would have
inherited object's, which answers a fresh object delegating to the receiver —
for `string`, an object that refuses every message a string understands. Inert
rather than wrong, and no use to anybody. They shadow it:

```
string:new.
solvm: a string is written as a literal, not made with 'new' -- "" is the empty one

symbol:new.
solvm: a symbol is written 'name, or made from a string with asSymbol -- not with 'new'

block:new.
solvm: a block is written { ... } and compiled -- there is nothing for 'new' to make

boolean:new.
solvm: there are only two booleans, true and false -- 'new' makes neither
```

The rule underneath, stated once: **`new` means "make an object delegating to
me", and these four have instances that are not objects delegating to them.**
That asymmetry is inherent to unboxing rather than a wart, so it is said where
each class is defined and `object:new` stays general. Nothing was built to
succeed instead, because there is nothing better for them to do — `""` is
already the empty string, `asSymbol` already names its direction, a block comes
from the compiler, and there are exactly two booleans. The error is all such a
class has to offer here, so it teaches.

**Nothing leaked onto the values.** `#45:parent` and `#45:via(...)` are refused
by the receiver check — the work 1.6 did for an unrelated reason, three commits
before anyone thought about a root.

The cost is on the **miss** path only: a send that hits is unchanged, and a
lookup that fails now walks object's thirteen slots before giving up, which
measured about 10% over 200,000 failed lookups. That is the path that ends in
*does not understand*.

Three tests in `tests/test_object.c`: every value and every class answering
`isKindOf(object)` with the chain ending at `object:parent`, the messages that
must stay refused for a value, and the four refusals beside the constructors
that still construct.

### Extending a built-in, and a single root that was not blocked — `0a17b99`, 2026-08-20

Documentation. No code.

**Adding methods to a built-in class** now has a section in the reference. It
needs no new rule — a class is an object and a slot holding a block is a method,
so `integer:double := { self:mul(#2) }` is the same binding as everything else,
and every built-in takes them. Written down because nothing said so outside the
README's opening example, along with the two things worth knowing before
overriding a message that already exists: the primitive you displace is gone and
`via` cannot reach it, and building the text with `fill` inside an `asString`
override recurses until the call-depth cap, since `fill` renders its values by
*sending* `asString`.

**And a correction, from an experiment.** This entry and roadmap 2.5 have both
been saying that a single root — the built-in classes delegating to `object` —
waits on the class-side/instance-side split, because `float` inheriting object's
`new` would answer a plain object rather than a float.

That stopped being true and nobody noticed. `7ac6be6` gave `float` its own `new`,
so it shadows object's; `integer` and `array` have theirs. And 1.6 gave every
primitive a receiver requirement, so the two messages `integer` would actually
inherit — `via` and `parent`, the only two it does not already define — are
refused for a non-object receiver before they run.

So it was tried, on a throwaway copy: eight lines setting each built-in class's
`proto`, **and the whole test suite passes untouched.** Every `isKindOf(object)`
becomes true, `integer:parent` answers `object`, `#45:add(#1)` is still `#46`,
and `#45:parent` and `#45:via(...)` are refused by the receiver check — three
commits before anyone thought about a root.

What is left in the way is one message. `string`, `symbol`, `block` and
`boolean` have no `new` of their own and would inherit object's, which answers an
object delegating to the class — inert rather than wrong, since it errors on
every message a string understands, but still bad. So the open question is not
*how do we build a metaclass level* but **what should `new` do on a class that
cannot construct anything**, which is where the document's closing section
already arrives from the other end.

The two are separable. The split is still worth doing for `slots` and for
`#45:new(#1)`; it is not what the root is waiting on. Nothing is committed here
but the writing — the experiment stayed in a scratch tree.

### Wrote down the class-side question — `bb5f077`, 2026-08-20

Documentation. No code.

**[class-and-instance.md](class-and-instance.md)** is the long version of roadmap
2.5, the one design question still open. It was a paragraph that said `integer`
holds `new` and `print` in one object and that separating them "needs a metaclass
level", which is true as far as it goes and leaves out the two things that
actually decide the question.

The first is that **this is only a problem for the built-ins.** A user-defined
object has one side and delegation, which is coherent: `point:make` and
`point:sum` sit together, and an instance seeing both is prototypes working as
described. The built-ins are welded by one line — `sol_vm_class_of` has to hand
an unboxed `#45` some object to dispatch to, and the only candidate is the object
the global `integer` names.

The second is that **metaclasses are the Smalltalk answer to a question this
language does not ask.** design.md says whether an object is a class or an
instance is how it is used, not what it is; a metaclass tower would import a
class-based concept to fix something only the built-ins have. The document
proposes a smaller shape instead — one behaviour object per built-in, holding the
instance side, with `sol_vm_class_of` returning it — and works through what that
fixes, what it would make 1.6's receiver check redundant for, and the one wrinkle
worth designing carefully, which is keeping `#45:isKindOf(integer)` true when
`#45` no longer dispatches to the object `integer` names.

A closing section asks the same question one level down — given that there is a
class side, what belongs on it? `new` turns out to be **three operations sharing
a spelling**: identity on `integer` and `float`, an allocation on `array`, an
allocation and a delegation on `object`. Not even a uniform protocol, since the
arities disagree, so nothing generic could send it anyway.

None of the four missing classes wants one. A string is immutable, so unlike an
array there is nothing to allocate and fill; `symbol:new("foo")` is `asSymbol`
under a worse name; a block cannot be constructed at run time at all; and there
are exactly two booleans.

The interesting direction is the opposite: `integer:new` and `float:new` are the
identity function, and they are a **vestige of the abandoned design**. The
original sketch had `integer:new(a)` followed by `a:set(#45)` — a mutable integer
object you construct and then fill. Numbers became immutable unboxed values,
`set` never existed, and `new` outlived the model it was for.

And it records a **trigger** rather than a recommendation to do it now: the
symptoms are cosmetic — `#45:new(#1)` answers, `slots` mixes the sides — but the
single root is not, and `integer:isKindOf(object)` being false is what should
set this going.

The roadmap entry itself was also wrong on a detail and is corrected in
`7beb07e`: it claimed `integer` has `new` where `float` does not, which
`7ac6be6` half fixed. `new` is on `integer`, `float`, `array` and `object`;
`string`, `symbol`, `block` and `boolean` have no class side at all.

### Compile errors point at the column — `0e48e5d`, 2026-08-20

Roadmap 5.4. No `.sob` change and no change to the language.

```
[line 2:9] solas: expected '.' between statements at ','
  b := #2 , .
          ^
```

A line number left the reader scanning the line. The error now names the
column, echoes the line, and underlines the offending token — a caret per
character, so a misplaced name is underlined rather than merely pointed at.

**A token records where it began**, not where the scanner stopped. That is the
change that matters beyond the printing: a string may span lines, and it used to
be reported at whatever line it ran out on rather than at its opening quote.

**Error tokens changed shape.** `error_token` used to put its complaint in
`start` — the field that otherwise points into the source — so an error was the
one kind of token that could not be pointed at. The complaint moved to a
`message` field, and now `start` and `length` locate the offending characters
for every token, which is why `unterminated string` can underline the string it
means.

Two details that are easy to get wrong, both pinned by tests:

- The pad before the caret is built from the **line's own characters**, so a tab
  in the source is a tab in the pad and the two line up whatever width the
  terminal gives it. Spaces would drift the moment anyone indented with tabs.
- A long line is **windowed** around the token rather than spilled whole. That
  matters more since `5.1`: Solis will now read a line of any length, so an
  error in a 5000-character line would otherwise have printed all of it.

**Runtime errors stay at line granularity**, and that is a size question rather
than an oversight. A chunk records a line per byte of bytecode; a column would
be a second table in every `.sob`, carried always and read only when something
has already gone wrong. Worth revisiting if a debugger ever wants it, and
recorded in the roadmap so it stays a decision.

Three tests in `tests/test_lexer.c` — that every token carries a column locating
its first character, that a multi-line string is placed where it opens, and that
an error token points into the source — and four in `tests/test_compile.c`, for
the reported position, the caret landing under the token rather than beside it,
the tab pad, and the windowing.

### Solis reads until the input could compile — `edccb90`, 2026-08-20

Roadmap 5.1. No `.sob` change and no change to the language.

```
> integer:double := {
..     self:mul(#2)
.. }.
> #21:double:print.
#42
```

A line was never a unit of anything in this language — `.` separates statements
and a newline is ordinary whitespace — so reading one at a time was the REPL
imposing a rule the language does not have. A method body spanning three lines
used to produce three unrelated errors. Solis now reads until what has been
typed could compile, with `.. ` for the continuation prompt.

Two things say the input could still be finished: **an unclosed bracket, and an
unclosed string**. Both outlive a line, so the state carries across them.
Counting brackets naively would have been wrong twice over, and neither case is
theoretical:

- A brace inside a string is not a bracket. `fill` templates are made of braces,
  so `"{}":fill([#1])` would have hung the prompt waiting for a close.
- A `;` comment runs to the end of its line, so a `{` inside one is text. It
  counts again on the next line.

A backslash claims the character after it, so `"\""` does not close the string —
the same rule the lexer scans by. And a stray closer does not take the depth
below zero: a mistyped `)` is a mistake for the compiler to report, not a reason
to wait for input that could never balance it.

**The 1024-byte cap is gone rather than reported**, which the entry had asked for
as a minimum. The buffer grows, and a line is read in pieces until its newline
arrives. That cap caused the confusing session the roadmap recorded — a generated
255-element array literal looked like it had failed to compile when it had merely
been severed mid-token, and the tail arrived as if it were the next line. A
5000-byte line now arrives whole, and a test checks the next line is still the
next line.

Deciding when input is finished moved to `solis/src/input.c` so it could be
tested, which also gave Solis the `cmd/` and `src/` split the other two
components already had — it was the only one with its entry point in `src/`.
`tests/test_solis.c` is new: eleven finished forms and seven unfinished ones, the
state carrying across lines, a comment hiding a brace only to the end of its own
line, a stray closer leaving the depth at zero, and the buffer growing past where
the old one stopped.

Not done, and not obviously wanted: a way to abandon a half-typed submission.
Ctrl-D at a continuation prompt leaves, and typing the closing bracket gets a
compile error, which are two workable ways out. A blank line would be the usual
third, but a blank line inside a method body is ordinary formatting here.

### The verifier computes stack heights — `bf2fffd`, 2026-08-20

No `.sob` change and no change a program can see. Roadmap 3.9, the last item
that had real substance left in it.

The machine is a stack machine, so **every instruction runs at a definite
height**: `SEND 'add' (1 args)` always has exactly two values beneath it,
whatever the program computed to get there. Nothing computed that, which left
one operand unguardable at load. `argc` is a byte the *file* supplies, and
whether that many arguments are really present depends on the height — so no
structural check could tell a real count from a corrupted one. Fuzzing the loop
work found the shape it takes: a send claiming 227 arguments on a stack one
deep, reading its receiver from below the frame.

The verifier walks control flow from the entry now, following each branch and
carrying the height. The rule that makes it work is the JVM's: **the paths into
a point must agree.** An instruction reached from two places at two different
heights has no height, and that is exactly what corruption looks like.

This came last of the four checks rather than first because it needed the other
three. Every opcode's length has to be known, and every branch target has to be
established as an instruction boundary, before a walk that follows jumps can
trust where it lands.

Measured over 1,750 single-byte corruptions of one `.sob`, under ASan and UBSan:

| | before | after |
| --- | --- | --- |
| refused at load | 1031 | **1066** |
| failed part-way through a run | 236 | **208** |
| ran to completion | 483 | **476** |

The last row is the one worth having. Those seven were corrupt files that passed
every check *and* that the runtime never objected to — they ran, on an
inconsistent stack, and produced output. Twenty-eight more moved from failing
mid-run to being refused at the door. Load costs about 5% more, paid once.

**The runtime check stays**, which is where this departs from what the roadmap
expected — it had guessed the analysis would let the runtime checks go. It does
not, because the two cover different populations rather than one being redundant:
the verifier runs when a `.sob` is loaded, Solis runs what it just compiled
without verifying — deliberately, since verifying every REPL line to catch the
compiler's own bugs is the wrong shape — and the C API will run any chunk it is
handed. One comparison per send is a cheap floor to keep under all of that. The
two tests that used to assert *"the verifier lets this through, the send catches
it"* now assert both ends catch it.

Code no path reaches is never given a height, and is not required to have one:
it cannot run. Its operands are still checked by the structural pass, and a jump
into it would make it reachable, at which point it is checked like anything
else. There is a test pinning that, so it stays a decision rather than a gap.

Five tests in `tests/test_serialize.c` for the shapes it rejects — branches
disagreeing at a join, `POP`/`RETURN`/`SET_SLOT` with nothing beneath them, a
back edge arriving one value higher than it left — and one for what it must keep
accepting, an inlined loop with `and`/`or` and a conditional in it.
`tests/test_compile.c` hands all twelve examples and 29 accepted forms to the
verifier, so *whatever Solas accepts, the verifier accepts* still has a test
behind it.

### A tutorial, and a site to read it on — `61162cb`, 2026-08-20

Documentation. No code, no behaviour change.

**[TUTORIAL.md](TUTORIAL.md)** is new, and is the third shape the documentation
wanted. REFERENCE.md is for looking a message up and GUIDE.md surveys the
concepts in order; neither has you *writing* anything. The tutorial builds one
program — a stock report — from an empty file to a working thing, introducing
each idea at the moment it is needed rather than because it comes next in a
list. By the end it has used objects and slots, methods and `self`, blocks,
parameters and temporaries, arrays, `do`/`collect`/`select`/`sorted`, format
specs, `fill`, an object rendering itself, delegation, and `via` — without ever
presenting them as a syllabus.

Two moments in it are load-bearing rather than decorative. The `asFloat` in
`self:price:mul(self:qty:asFloat)` is introduced by *removing* it and showing
the error, because strict arithmetic is easier to accept once you have seen what
it refuses. And the last step overrides one method on a delegating object and
then shows that the inherited maker, the report row, and `isKindOf` all keep
working — which is the argument for prototypes made by demonstration instead of
assertion.

**examples/stock.sol** is the finished program, so the tutorial's claims and a
runnable file cannot drift apart. `tests/test_compile.c` compiles all twelve
examples now.

**The site is at <https://hansolovkarlsson.github.io/solveig/>**, built from the
markdown already in the repository. There is no generated copy of any document,
so a page cannot fall out of step with the file it came from: editing
`docs/GUIDE.md` is editing the Guide page. Three plugins do it —
`optional-front-matter` renders files that have none, which is all of them, since
they are read on GitHub too; `relative-links` rewrites `[x](GUIDE.md)` to the
page it becomes; `titles-from-headings` takes each title from the first heading.

**The first build failed, and the reason is worth keeping.** Jekyll runs Liquid
over every markdown page, and Liquid's syntax is `{{ }}` — while Solum's `fill`
writes placeholders as `{}` and escapes a literal brace as `{{`. So every
document that explains `fill` is a Liquid syntax error, and the sentence that
broke it was this changelog's own description of the escape. Not a typo in one
file: a landmine under every document this project will write about templates.

Wrapping the passages in `{% raw %}` would have fixed the build and broken the
files, which are read unrendered on GitHub where the tags would show as literal
clutter. The fix is to stop pretending these are templates — they interpolate
nothing — so `render_with_liquid: false` turns Liquid off for pages while leaving
layouts alone. That needs Jekyll 4, and the built-in Pages build pins 3.10, so
the site is built by a workflow in `.github/workflows/pages.yml` instead. Two
things came with that: the build logs are visible, and the failure above was
reported by the Pages API as `building` for ten minutes after the run had already
failed in thirty-five seconds.

`_layouts/default.html` and `assets/css/solveig.css` are the whole of the
presentation — one layout, one stylesheet, no framework, light and dark both
defined explicitly. `examples/` is deliberately not excluded from the build, so
the links the guide and tutorial make to `.sol` files resolve to the files
themselves. The `Gemfile` is read by the workflow and by nothing else: `make`
still needs a C11 compiler and nothing more.

### A guide, and examples for the concepts that had none — `e2ff82c`, 2026-08-20

Documentation and examples. No code, no behaviour change.

**[GUIDE.md](GUIDE.md)** is new: a tour of every concept in the language in an
order that builds, each section pointing at a runnable example. REFERENCE.md is
organised for looking a message up, which is the wrong shape for meeting the
language, and design.md answers "why" rather than "what" — so there was nowhere
to send someone who wanted to learn it. Seventeen sections, from message sending
through to the restrictions worth carrying around.

**[fetched-methods.md](fetched-methods.md)** is new: the long explanation of what
`slotAt` gives you, why a fetched method cannot be called as it stands, and what
`boundTo` is for — including the honest answer that most code should reach for
`{ c:bump }` instead, and that it earns its place when the method is chosen at
run time. It has the comparison against `perform` and the two things binding
deliberately does not do.

Three examples for concepts that had none:

- **numbers.sol** — the two numeric types and why the literal says which, strict
  arithmetic, trapping overflow, floored division and what it does to `mod`, the
  narrowing messages, bases, and floats that read back.
- **format.sol** — `print` against `display` against `asString`, the format spec,
  digit grouping, `fill`, and an object rendered by asking it. It builds a column
  of figures, which is what the spec was designed for.
- **values.sol** — values against references, head-on: what `equals` means for
  each, what `a := b` does, and why the split falls where it does. Mutability is
  what makes identity matter; if a thing cannot change, equality can be about
  contents instead.

Every snippet in both documents and all three examples was run, and the outputs
shown are what the VM prints. That includes the errors quoted in comments, which
is where a claim usually goes stale: two were wrong when first written —
`decimals are for floats` is really `decimals mean nothing for an integer`, and a
brace escape was shown through `display`, which does not have escapes, rather
than through `fill`, which does.

`tests/test_compile.c` compiles all eleven examples now and hands each to the
verifier, so the new ones are covered by the same invariant as the old.

### `boundTo`: calling the method you fetched — `be19104`, 2026-08-20

No `.sob` change — a primitive, not an opcode. Roadmap 2.14, the last item that
was ahead of the verifier work.

```
m := point:slotAt('sum).
m:value.                 ; solvm: nil does not understand 'x'

m:boundTo(p):value:print.        ; #7
```

A slot holding a block is a method, so `slotAt` is the only way to hold one as
a value — and what comes back is unbound, because `self` is supplied by a send
rather than carried by the block. A method written at the top level has `self`
nil, so calling a fetched one asked nil for the receiver's slots.

**It answers a block rather than calling one**, which was the decision here.
The alternative was `valueWith(receiver, ...)`, running immediately with the
receiver as the first argument. Answering a block follows `via`, which answers a
delegating view rather than doing the send — binding and calling are two things,
and keeping them two has three consequences worth having:

- `value` goes on meaning exactly what it meant, arity included. The arguments
  are the block's own and the receiver is not among them, so
  `m:boundTo(#10):value(#3, #7)` has no ambiguity about which is which, where
  `valueWith(p)` on a one-argument block would have been an arity error that
  reads like a one-argument call.
- A bound method is a value. It can be passed around, and bound once and called
  many times.
- The original is untouched, so one fetched method binds to each of several
  receivers in turn: `[p, q]:collect({ e | m:boundTo(e):value })`.

Any value may be the receiver, since `self` may be.

**Two things it deliberately does not do.** It does not lift the frame
restriction: the home frame comes across unchanged, so a block that reads it is
no freer for being bound — binding chooses a receiver, not a lifetime (3.1). And
it does not survive a send. Installing a bound block in a slot makes an ordinary
method, and a send supplies its own receiver, which is what makes an installed
block a method at all:

```
b:show := m:boundTo(a).
b:show.                  ; self is b -- the send wins, not the binding
```

That last one is the one place binding looks like it ought to win and does not,
so there is a test holding it there.

No temp root, and the reasoning is worth recording because the rule elsewhere
has been the opposite. `sol_block_new` allocates and so may collect, but the
receiver of the send and its argument are both still on the value stack — the
dispatch loop drops them *after* the primitive returns — and the stack is a
root. Under `SOLUM_GC_STRESS=1` a collection happens between entering the
primitive and the new block being registered, so a hundred bindings in a loop
under ASan is what would catch that reasoning being wrong. It is clean.

Seven tests in `tests/test_reflect.c`, and `examples/reflect.sol` grew a
section. Every snippet in the reference was run.

### Dispatch by pointer, and a hash over the side tables — `1bc0e56`, 2026-08-20

No `.sob` change, and no change a program can see: same bytes out of the
compiler, same answers out of the VM. Roadmap 4.3, which was the last item in
section 4.

**A send used to `strcmp`.** `sol_object_lookup` walks a proto chain comparing
slot names, and every send did that character by character. Now every slot name
and every selector goes through one table on the VM, which answers the same
address for the same characters, so the walk compares pointers.

The hash has to be paid somewhere, and the trick is where: a chunk's name table
is resolved through the table **once, before the chunk first runs**, so it is
paid per name per chunk rather than per send. The dispatch loop reads a pointer
that is already resolved.

| | before | after |
|---|---|---|
| 3M sends in a loop | 1.36s | **0.74s** |
| 1M sends to a user-defined method | 0.51s | **0.29s** |
| 1M sends four levels up a proto chain | 0.38s | **0.21s** |

**The obvious place to put this was the symbol table, and it was the wrong
place.** `'foo` is already interned, and the roadmap had been assuming symbols
would serve. But that table is *weak* on purpose — `5a15fc9` measured a program
interning twenty thousand names taking over a minute with a strong table and
running instantly with a weak one, because every collection had to mark every
symbol ever interned. Slot names are pointed at by objects and by chunks, which
have no way to announce they are done with one, so they would have had to be
marked — reintroducing exactly the cost the weak table exists to avoid. So these
are a second table, strong, immortal for the life of the VM and freed with it.
A symbol is a value a program can drop; a name is the VM's own atom. Same job,
different lifetime, and the lifetime is the reason.

Two lookups now, deliberately named apart. `sol_object_lookup` compares spelling
and is what C callers and tests hold literals for; `sol_object_lookup_interned`
compares pointers. Handing the second one a string that never went through the
table would answer NULL rather than fail — an equal string that is not *the*
string — so `-DSOLUM_CHECK_INTERNED` compiles in an assertion that it did. That
is the `SOLUM_GC_STRESS` bargain: too expensive to leave on, too useful never to
run. The whole suite passes under it, and a test pins the silent-NULL shape so
it stays known rather than surprising.

### The side tables no longer scan

The other half of 4.3, and the half that had begun to hurt. `4.2` raised the
tables from 256 entries to 65536 without touching the linear scan that filled
them, so interning was quadratic:

| | before | after |
|---|---|---|
| 10,000 distinct names and constants | 0.43s | **0.01s** |
| 20,000 | 1.44s | **0.02s** |
| 40,000 | 6.17s | **0.04s** |

A chunk keeps a hash index over each side table. **Below sixteen entries there
is no index at all** and the scan stands — which is where a scan was always
cheaper, and is what keeps this from costing memory: a method body, a block, or
a REPL line never builds one. That mattered. The first version indexed every
table from the first entry and pushed 60,000 REPL lines from 1.9 MB to 2.2 MB,
because a two-name chunk was allocating two 64-slot indexes; with the threshold
it is 1.9 MB again, unchanged.

Hashing a constant has to fold exactly what `same_constant` folds, which
compares bits rather than values so that `-0.0` stays distinct from `0.0` and a
NaN still finds itself. The hash reads the same bits, and a test walks both.

The emitted bytecode is byte-identical: every example, and a 20,000-name program,
compile to the same `.sob` as before. Verified past the unit tests by the suite
under ASan and UBSan with `SOLUM_GC_STRESS=1`, the suite again with
`-DSOLUM_CHECK_INTERNED`, and 1,750 single-byte corruptions of a `.sob` through
the loader, which fills the index as it appends.

`tests/test_names.c` is new: the table, slots sharing one name, the two lookups
agreeing on a chain, a chunk resolving, a chunk re-resolving when a second VM
runs it, interning either side of the threshold, the constant-hash corners, and
a slot's name outliving a collection of its neighbours.

### Inlined `and` and `or` — `de226a8`, 2026-08-20

**`.sob` goes to version 10.**

```
x := #3.
x:greaterThan(#0):and({ x:lessThan(#10) }).    ; jumps now, no block, no frame
x:lessThan(#0):or({ x:equals(#3) }).
```

The last two selectors that short-circuited through a real block. Conditionals
and loops were inlined in `54e2ae1` and `0fd9a75`; these finish roadmap 4.1, and
the jumps were all in place — but they needed one thing the other four did not.

**A new opcode, `OP_CHECK_BOOL`.** `ifTrue` answers nil on the path it does not
take and anything at all on the path it does. `and` answers a boolean either
way, and on the long path that boolean is *whatever the block said* — so the
block's answer is both the reply and something that has to be checked. Neither
existing test does that: `OP_JUMP_IF_FALSE` and `OP_EXIT_IF_FALSE` both consume
the value they branch on. The new one examines the top of the stack and leaves
it there, carrying the message name so the complaint is the one the send would
have made.

```
        and:                            or:
          JUMP_IF_FALSE -> false          JUMP_IF_FALSE -> run
          <body>                          CONST true
          CHECK_BOOL                      JUMP -> end
          JUMP -> end                   run:
        false:                            <body>
          CONST false                     CHECK_BOOL
        end:                            end:
```

**The shortcut answers a constant, not the global `true` or `false`.** Those are
ordinary globals and a program can rebind them; reading one would let the short
path and the long path disagree about what `and` answers. A test rebinds both
and requires the shortcut to keep answering booleans.

| | before | after |
|---|---|---|
| a two-million-pass loop, mostly `and`/`or` | 2.31s | **1.83s** |
| recursion through an `and`/`or` block | 31 | **62** |

The depth is again worth more than the seconds, and for the reason the earlier
entries gave: the block was costing a frame, and the jumps do not. Recursion
that runs inside an `and` now reaches as far as recursion that does not.

Everything else is the shape already established. The restrictions are
unchanged — the block must be written on the spot with no parameters and no
temporaries, or it falls back to an ordinary send, which still means `true:and({
a | a })` is an arity error rather than being quietly made to work. Both forms
raise the non-boolean-answer complaint from one function in `vm.c`, so the
inlined form and the primitive cannot word it differently; the primitive's own
message moved there rather than being copied.

Checked three ways past the unit tests: 1,750 single-byte corruptions of a
`.sob` using both messages, run under ASan and UBSan, none of which crashed the
loader; the suite under `SOLUM_GC_STRESS=1` with both sanitizers; and a
hand-built chunk reaching `OP_CHECK_BOOL` with an empty stack, which passes
verification — the verifier still does not compute stack heights (3.9) — and is
refused at run time rather than read below the frame.

The six accepted forms this adds to the compiler are in `tests/test_compile.c`,
which now checks 29 of them against the verifier: whatever Solas accepts, the
verifier accepts.

### A temporary needs a frame, and the compiler says so — `a57632c`, 2026-08-19

`( | t | ... )` declares temporaries of the frame the group sits in. Inside a
block or a method there is a frame, and it worked. At the top level of a script
there is none — the script's chunk reserves no slots — and the compiler emitted
`OP_SET_LOCAL 0` anyway, writing over the bottom of the expression stack.

```
#1:add(( | t | t := #5. t )):print.
```

The receiver `#1` was sitting in that slot. `t := #5` overwrote it, and the
answer came back **#10** instead of #6 — no error, just arithmetic on the wrong
number. Roadmap 1.7.

**Refused in the compiler**, at the `|` where the mistake is:

```
[line 1] solas: a temporary needs a frame, so declare it inside a block at '|'
```

Both front ends now say that, which they did not before. Compiled, the verifier
had always caught it, so `sol_chunk_save` refused to write the file and reported
`bytecode is internally inconsistent` — true, and useless, since the problem was
three tokens of source. Solis never verifies, because it runs what it just
compiled and trusts its own compiler, so there the wrong answer simply appeared.

That trust is the larger half. Solis is right to hold it — verifying every REPL
line to catch the compiler's own bugs is the wrong shape — but nothing was
checking it was earned. **`tests/test_compile.c` now checks it**: every shipped
example and 23 accepted forms are compiled and handed to `sol_chunk_verify`, so
*whatever Solas accepts, the verifier accepts* has a test behind it instead of
being an assumption. Anything the compiler learns to accept belongs in that
list.

Recovery needed care too. Reporting and returning left the parser on the `|`, so
it resumed inside the group, cleared the panic flag at the `.` between the
group's statements, and complained again about the `)` — two messages for one
mistake, where every other error here produces exactly one. The refusal now
steps over the declaration list, and a test counts the messages.

Found by auditing REFERENCE.md against the implementation: the reference said
declarations may open any group, and they could not.

### Side-table operands are two bytes, and constants intern — `9b81fd3`, 2026-08-19

A chunk could hold 256 constants and 256 names, because the operands that index
them were one byte each. A literal-heavy program stopped compiling well before
it stopped making sense: sorting two thousand numbers was not possible without
generating them at run time. Roadmap 4.2.

```
x0 := #1000. x1 := #1001. ... x399 := #1399.
[line 1] solas: too many constants in one chunk at '#1256'    ; was
```

**Every index into a side table is now a big-endian u16.** That covers the
constant pool, the name table, and the nested-method table — `OP_CONST`,
`OP_GLOBAL`, `OP_SET_GLOBAL`, `OP_BLOCK`, `OP_STRING`, `OP_SYMBOL`,
`OP_SET_SLOT`, `OP_SEND`, and the selector `OP_JUMP_IF_FALSE` carries. The
ceiling is 65536.

Not a `CONST_LONG`-style pair, which is what the roadmap had pencilled in. The
rule 4.1 arrived at was that an opcode should mean something — `OP_LOOP` is its
own instruction because a backward jump is a different thing, `OP_EXIT_IF_FALSE`
because it complains differently. A `CONST_LONG` means what `OP_CONST` means and
differs only in operand width, and it would not have come alone: nine
instructions carry an index, so it would have been nine more opcodes across the
length table, the verifier, the disassembler, and the dispatch loop. That is
four more copies of exactly the agreement 4.1 collapsed into one.

So width belongs to the operand, under one rule. **An index into a side table is
a u16; a frame slot, a nesting depth, an argument count stays a u8**, because
those are bounded by the machine rather than by the source — a frame of more
than 255 slots is refused before it runs. Jump offsets were u16 already, so
sixteen bits is now the only width the format has, and `sol_read_u16` is the
one place it is decoded.

**The constant pool interns**, which it never did. `#1` written three times was
three slots and is now one; the name table has always worked this way. The
loader appends to both instead, for the reason the names already had: a file
refers to these tables by position, so folding a duplicate on load would shift
every index after it. Constants are compared by their bits rather than by `==`,
which keeps `-0.0` distinct from `0.0` and stops a NaN folding onto itself.

Interning paid for much of the widening:

| | before | after |
|---|---|---|
| constants and names per chunk | 256 | 65536 |
| the eight examples, total `.sob` bytes | 9934 | 10250 |
| `arrays.sol` top-level constants | 41 | 12 |
| a tight two-million-pass loop | 0.251s | 0.252s |
| the same loop with a conditional in it | 0.457s | 0.455s |
| a million sends of a user-defined method | 0.159s | 0.158s |

`arrays.sol` came out 3.9% *smaller*. Run time did not move; the extra byte is
read by the same helper the jumps already used.

The verifier checks both bytes of every index, so an index of 256 into a table
of one entry is caught rather than read as slot 0 — a test asserts exactly that.
A 400-constant, 400-name program is compiled, verified, run, written to a file,
loaded back, and run again, checking the value bound to the last name: an index
that lost its high byte anywhere on that path would answer wrongly rather than
crash.

**`.sob` goes to version 9.** Files written by an earlier build are refused, as
usual.

One thing the old cap was hiding: both tables intern by walking themselves,
which costs nothing at 256 entries and is quadratic at 65536 — 16000 distinct
names and constants compile in 0.87s, 32000 in 3.52s. The scan was always this
shape; the cap meant it could never be reached. Noted in the roadmap against
4.3, which wants the same hash table for dispatch.

What is left at 255 is the argument count, and through it an array literal.
That one is not an operand-width problem: a longer literal needs `array:new`
and repeated `add` rather than a wider `argc`.

Re-fuzzed: 3302 single-byte corruptions of a `.sob`, zero sanitizer reports,
35 semantic timeouts of the kind 3.3 describes.

### A class object no longer answers its instances' messages — `ab5dd96`, 2026-08-19

Two crashes, both reachable from three words of ordinary source, both fixed by
one check. Roadmap 1.5 and 1.6.

```
array:add(#1).      ; was: abort
array:print.        ; was: segmentation fault
array:size.         ; was: #0, read from whatever `array` is not
```

`array` is an object whose slots are the messages an *array* understands, and it
answers them itself. `prim_array_add` then did `SOL_AS_ARRAY(self)` on the class
object, because a primitive reached through a class had always been entitled to
assume its receiver's type. That holds for every instance and fails for the one
object that is not one. `array:print` was the same bug wearing the renderer:
rendering asks an object for `asString`, found the one meant for arrays, and
went round again — C recursion, so the call-depth cap never saw it.

**Each primitive now records the receiver it needs, and the dispatcher checks
before entering it.** One check in one place rather than 64 copies of the same
`if`, and both dispatch sites go through it, so `perform` and the renderer are
covered along with `OP_SEND`.

```
array:add(#1).
solvm: 'add' expects an array, got object
```

The requirement is per message, not per class, because a class object is the
genuine receiver of some of them — `array:of`, `array:new`, `integer:new`,
`float:new`, and reflection, which reads either side. The installation lists now
say which is which, one message at a time:

```c
instance(vm->array_class, SOL_ARRAY, "add", prim_array_add);
any_receiver(vm->array_class, "of", prim_array_of);
```

That is 2.5 answered in the small. Splitting the two sides into separate objects
still wants a metaclass level and is still open; what had to be settled first was
which side each message is on.

**`respondsTo` asks the same question the dispatcher does**, so it cannot claim a
message that sending would refuse: `array:respondsTo('add)` is now false, and
`array:respondsTo('of)` true. Binding a block over a primitive clears the
requirement along with it, so a class can be given messages of its own:

```
array:describe := { "arrays, in a list" }.
array:describe:display.        ; arrays, in a list
```

**One thing had to move in the renderer.** A class object nested inside
something being printed — `[array]:print` — would otherwise have raised the new
error from inside a `print`, which is not the renderer's business. It now asks
only an object that can answer, and shows one that cannot as its address,
exactly as it already showed an object with no `asString` at all.

What is left of 1.5 is that `render`'s depth counter restarts when the recursion
leaves through `sol_value_render`. That is still wrong in principle and is now
unreachable: closing the loop needs a primitive that renders a receiver it did
not check, and there is no longer one. Left alone rather than carrying state on
the VM for a case nothing can produce.

One comparison per primitive send, which costs **4.0%** on the tight loop from
the entry below and **2.1%** on the same loop with a conditional in it — the
first is nearly all sends, so it is close to the worst case.

Both crashes were found by fuzzing the inlined loops (4.1) and are older than
that work. The same sweep — 3205 single-byte corruptions under ASan and UBSan —
now reports nothing at all, where it had reported these two. Thirty-four runs
still time out, which is the spin 3.3 describes and the expected answer.
`tests/test_class_side.c` covers every built-in class.

### Inlined loops — `0fd9a75`, 2026-08-19

**`.sob` goes to version 8.**

`whileTrue` written literally now compiles to jumps too. There is no block and
no frame; the condition is re-run in place, and a backward jump closes the loop:

```
0005 GLOBAL      0 'i'
0007 CONST       1 '#5'
0009 SEND        1 'lessThan' (1 args)
0012 EXITIFF    13 -> 28
0015 GLOBAL      0 'i'
0017 CONST       2 '#1'
0019 SEND        2 'add' (1 args)
0022 SETGLOB     0 'i'
0024 POP
0025 LOOP       23 -> 5
0028 NIL
```

| | before 4.1 | inlined conditionals | and now loops |
| --- | --- | --- | --- |
| Recursion, plain | 30 | **62** | 62 |
| Recursion through a loop body | 20 | 30 | **62** |
| A tight 2,000,000-pass loop | 0.53s | 0.52s | **0.44s** |
| The same loop with a conditional in it | 1.44s | 1.13s | **1.06s** |

All three builds were timed together on one machine, so the columns compare;
the 1.60s in the entry below was measured on another day.

The depth is the result worth having. A level of that second row used to cost
three frames — the method, the `ifTrue` branch, and the `whileTrue` body — and
now costs one, so recursion that happens to run inside a loop reaches exactly as
far as recursion that does not. The seconds are worth less than they look: 15%
off a loop that does nothing but count.

**`whileTrue` is the awkward one to inline, because its condition is the
receiver.** By the time the selector has been read, an ordinary compile has
already emitted an OP_BLOCK for it. So the compiler now reads ahead over the
whole `{ ... }:whileTrue({ ... })` before compiling any of it. The parser stays
single-pass in the sense that matters: it never revisits a token it has already
emitted for.

The same two restrictions as the conditionals, and now on the receiver as well —
both blocks must be written on the spot with no parameters and no temporaries.
`whileTrue` calls each with no arguments, so a parameter is an arity error that
inlining would quietly fix, and a temporary belongs to a frame that inlining
would take away. Anything else is an ordinary send. `examples/blocks.sol` runs
the same loop both ways and prints both answers.

**Two opcodes, not one.** `OP_LOOP` jumps backward, and is deliberately separate
from `OP_JUMP` so that forward remains the default and the one instruction that
can move the ip towards zero is easy to find. `OP_EXIT_IF_FALSE` tests the
condition, and is separate from `OP_JUMP_IF_FALSE` because the two complain
differently: for `ifTrue` the boolean is the receiver, so a non-boolean does not
understand the message; for `whileTrue` it is what a block answered, which is a
different sentence.

```
{ #1 }:whileTrue({ #2 }).
solvm: whileTrue expects the condition block to answer a boolean, got integer
```

Both sentences now come from one function, so the inlined form and the send
cannot drift apart — the failure 5.3 records, avoided in advance this time. A
test captures stderr from both and compares them.

**What a backward jump costs the verifier**, which was the open question: a
verified chunk can now run forever. It is not a new capability. `{ true
}:whileTrue({})` is a legal program, and before this a corrupted file could
already spin through a loop built from real sends — the earlier fuzz runs
recorded exactly that, as semantic timeouts rather than memory faults. So the
verifier does not try to prevent it. It checks that every branch target, forward
or backward, lands on the start of an instruction inside the chunk, and stops
there. There are tests for a backward target one byte into an instruction, for
one before the start of the chunk, and one asserting that a loop jumping to
itself is *accepted* — a spin is a bad program, not a broken VM.

Fuzzed: 3205 single-byte corruptions of a loop-bearing `.sob`, run under
ASan and UBSan. Two sanitizer reports, neither from the jumps and both
reproducible from ordinary source — 1.5 and 1.6 in the roadmap. Thirty-four
runs timed out, which is the spin, and is the expected answer rather than a
fault. The same sweep against the previous commit, 4276 variants, found the
argument count fixed below and nothing else.

Instruction lengths are down to one table, `sol_op_length`, read by the emitter,
the verifier, the disassembler, and the tests. There had been four copies, and
two of them disagreeing is precisely how a jump comes to land mid-instruction.

**Also fixed here, because the fuzzing found it: a send with a corrupted
argument count read below the frame.** `OP_SEND` carries `argc` in a byte, and
nothing checked that many arguments were on the stack — a `sub` claiming 227 of
them on a stack one deep read the receiver from 3.6 KB below. Whether a count is
honest depends on the stack height at that instruction, which the verifier does
not compute (3.9), so the send now refuses to reach below its own frame. Not a
new fault: the same fuzzing against the previous commit reproduces it, and the
regression test is a stack-buffer-overflow without the check.

**Found here and deliberately not fixed here: `array:print` crashes the VM.**

```
array:print.        ; segmentation fault
```

Three words of ordinary source, and the REPL goes the same way. Rendering an
object asks it for `asString`; on the class objects `array` and `block` that
finds the one they define for their instances, which renders the same value
again, and the depth `render` carries restarts at zero each time round. Bisected
to `f55e105`, which is where rendering began asking — it has nothing to do with
jumps. Written up as 1.5 with the fix it wants, which is its own commit.

The second report is the same shape by a different route, and also from source:

```
array:add(#1).      ; abort
```

`array` is an object whose slots are the messages an array understands, so
sending one to `array` itself finds it, and `prim_array_add` then reads the
class object as if it were an array. Written up as 1.6. Both wait on a decision
rather than on work — 2.5 is the design question under them — so neither is
fixed here.

### Inlined conditionals — `54e2ae1`, 2026-08-19

**`.sob` goes to version 7.**

`ifTrue`, `ifFalse`, and `ifElse` written literally now compile to jumps — no
block allocated, no frame entered:

```
0000 CONST       0 '#1'
0002 CONST       1 '#2'
0004 SEND        0 'lessThan' (1 args)
0007 JUMP_IF_FALSE    5 -> 16 (ifElse)
0011 STRING      2 'yes'
0013 JUMP        2 -> 18
0016 STRING      3 'no'
```

| | before | after |
| --- | --- | --- |
| Recursion depth | 30 | **62** |
| 2,000,000 conditionals | 1.60s | **1.12s** |

They are still ordinary messages on a boolean, still reachable through `perform`
or with a block held in a variable. Inlining applies only when every argument is
a block written on the spot with no parameters and no temporaries — a block with
parameters is an arity error when `ifElse` calls it with none, and inlining
would quietly make it work; a block's temporaries belong to its own frame, and
inlining would declare them in the enclosing one where they could collide.
Everything else falls back to a real send, and there are tests that the two
forms agree on every combination.

**The verifier changed, as 4.1 predicted it would have to.** Execution is no
longer linear, so it records where each instruction begins and checks every
branch target lands on one, in range. A crafted target one byte into a send
would otherwise have its operands executed as opcodes; there is a test for
exactly that. Offsets are unsigned and so forward-only, which is also why
verified bytecode cannot loop through a jump — 1798 corrupted variants of a
jump-bearing file gave no sanitizer report and no timeout.

The remaining cost in that loop is `whileTrue`, still a send with a block call
per iteration. It needs a backward jump, and is now first on the list.

### Sorting — `113745f`, 2026-08-19

```
[#3, #1, #2]:sorted:print.                            ; [#1, #2, #3]
[#1, #3, #2]:sorted({ a, b | b:lessThan(a) }):print.  ; [#3, #2, #1]
```

`sorted` answers a **new array**, like `collect` and `select`; nothing sorts in
place. With no block the order comes from *sending* `lessThan`, so a type that
defines one sorts itself, the way `fill` honours an overridden `asString`
instead of going around it. Mixed types are an error rather than an arbitrary
order — `lessThan` has no coercion to fall back on.

**Stable**, and tested as such: sorting twice orders by two keys, minor first.

Merge sort, chosen for two reasons past the O(n log n). It is stable. And it
cannot be walked off the end by a comparison that contradicts itself — a program
is free to write `{ a, b | true }`, and the indices are bounded by the halves
rather than by what the comparison claims. A quicksort partition trusting the
comparison would not be. There is a test that a self-contradicting comparison
loses no element.

The comparison calls back into the VM, so it can allocate and collect mid-merge.
Removing the root on the result array gives `heap-use-after-free` in
`merge_sort` under stress. What makes it safe is that a value is *copied* into
the scratch array and never moved, so until the copy back it is still in the
rooted result — an invariant of how merging works, now written down where the
next person will need it.

Checked against a reference sort on 2000 runtime-generated values, and under
ASan with GC stress on every comparison.

No `.sob` change: `sorted` is a primitive, so the format stays at version 6.

### Reflection — `a7310a7`, 2026-08-19

```
point:slots:print.               ; ['x, 'y, 'show]
p:isKindOf(point):print.         ; true
p:respondsTo('show):print.       ; true
p:perform('show):display.        ; (3, 4)
```

Five messages, on every type: `slots`, `slotAt`, `respondsTo`, `isKindOf`,
`perform`. Names are given as symbols, which is what symbols were wanted for.

`slots` answers own slots in **definition order** — the slot list is kept newest
first, so it is filled backwards. Inherited names are not yours; `parent:slots`
asks about those. The rest search the chain as a send does. A value answers for
the class it dispatches to, so `#45:isKindOf(integer)` holds, and since the
built-in classes are objects whose slots hold primitives, `integer:slots` lists
what an integer understands.

Installed in a loop over every class rather than nine times over. That is not
brevity: a message that answers what an object understands is wrong the moment
one class quietly lacks it.

**A fetched method is unbound**, and this is documented rather than papered
over. `slotAt` answers the plain block; `self` comes from a send, so `m:value`
runs with `self` nil. Fetching is for passing a method around; to call one, send
it. Binding a receiver to a fetched block is now item 3 in the suggested order.

Building the `slots` array interns a symbol per slot, and interning allocates —
so the half-built array is a temp root. Removing it gives
`heap-use-after-free at builtins.c:1562` under stress, which is what the new
test in `tests/test_reflect.c` guards.

No `.sob` change: these are all primitives, so the format stays at version 6.

### Symbols — `5a15fc9`, 2026-08-19

**`.sob` goes to version 6.**

```
a := 'foo.
"foo":asSymbol:equals('foo)      ; true  -- the very same symbol

state := 'running.
state:equals('running):ifElse({ "go" }, { "stop" }):display.
```

An interned name. Two symbols spelling the same thing are the *same* symbol, so
equality is a pointer comparison rather than a walk over characters — which is
the whole reason to have them apart from strings, a name being compared far more
often than it is read. A symbol never equals a string; `asString` gives its name.

**The intern table is weak, and that mattered more than memory.** Measured by
disabling the pruning:

| | 20,000 interned names |
| --- | --- |
| strong table | did not finish in 60 seconds |
| weak table | instant, 1.7 MB |

With a strong table every collection has to mark every symbol ever interned, so
the work grows with the total rather than the live set. Pruning runs between
marking and sweeping, so the table never names a cell the sweep is about to free
— and there is a test that a kept symbol survives a collection *and* that
re-interning afterwards finds the same one back.

This also gives 4.3 its mechanism: interned names are exactly what selector
dispatch wants instead of a `strcmp` per send.

### `asUppercase` and `asLowercase` — `91d413c`, 2026-08-19

```
#255:asBase(#16):asUppercase     ; "FF"    -- uppercase hex at last
"Hello, World!":asLowercase      ; "hello, world!"
```

ASCII letters only, and **by explicit range rather than `toupper`**, which
follows the C locale: under a Turkish locale `toupper('i')` is a dotted capital
I, so the same program would answer differently on two machines. Predictability
is worth more than the locales this cannot serve anyway.

Every other byte passes through untouched, so `"café":asUppercase` is `"CAFé"`
rather than mangled.

A string with nothing to change answers itself. Strings are immutable, so nothing
can tell the difference, and it saves an allocation.

This closes the gap integer bases left — `asBase` writes lowercase digits, and a
case message is a more general answer than an uppercase variant of it would have
been.

Also records what the language thinks text is (roadmap 2.13): a string is bytes,
`size` counts bytes, `at` answers a byte, and `"café":size` is 5. Real Unicode is
a different piece of work, not a larger version of this one.

### Integer bases — `f4b909d`, 2026-08-19

```
#255:asBase(#16)                    ; "ff"
#255:asBase(#2)                     ; "11111111"
#255:asBase(#16):asString("08")     ; "000000ff"
"ff":asInteger(#16)                 ; #255
```

**A message, not a letter in the format spec.** The roadmap had sketched
`#255:asString("x")`, which is exactly what the spec was designed without — a
letter that looks like printf's conversion character and invites a reader to try
`f` and `d`. A number covers every base from 2 to 36 where a letter covers one,
and padding still comes from the spec by chaining.

- The most negative integer converts like any other. Its magnitude is taken
  unsigned, so there is no negation to overflow.
- `asInteger(#n)` reads it back, and every base round-trips — there is a test
  walking 2 through 36 over a set of values including `INT64_MIN + 1`.
- Strict: no `0x` prefix, no leading whitespace, and a digit outside the base is
  an error rather than a truncated parse. `strtoll` would have accepted the first
  two.
- Digits above nine are lowercase. Uppercase hex wants `asUppercase` on strings,
  which is a more general thing to have than a second base message, and is now
  the noted gap.

### Digit grouping in format specs — `95074c9`, 2026-08-19

```
#1234567:asString(",")       ; "1,234,567"
1234.5:asString(",10.2")     ; "  1,234.50"
#-1234567:asString(",")      ; "-1,234,567"
```

`,` groups whole-number digits in threes, and **only** those — a sign, a
fraction, and an exponent all pass through untouched, so `1234567.891` becomes
`1,234,567.89` and `1e20` stays `1e+20`.

- **Fixed at `,`.** A separator that varies by locale is a much larger door to
  open than a report column is worth.
- **Cannot be combined with zero fill.** The leading zeros would not themselves
  be grouped — Python renders that as `001,234.50` — which reads as a mistake, so
  it is refused rather than produced.
- The flags have one order, so there is one way to write a given spec.
- Grouping belongs to numbers; asking a string, boolean, nil, array, or object
  for it is an error.

Two extensions were considered and deliberately **not** built, both recorded in
the roadmap: forcing exponent form (`"10.2e"`), which the renderer already does
on magnitude, and integer bases (`"x"`). Both reintroduce something that looks
like the conversion letter the spec was designed without, and invite a reader to
try letters that do not exist.

### Format specs — `3524c70`, 2026-08-19

`asString` takes an optional spec:

```
[align] ['0'] [width] ['.' decimals]

45.8:asString("6.2")     ; " 45.80"
45.8:asString("08.2")    ; "00045.80"
#-45:asString("06")      ; "-00045"
"ab":asString(">6")      ; "    ab"

row := { n, v | "{}{}":fill([n:asString("<8"), v:asString("8.2")]) }.
row:value("apples", 3.5).     ; apples      3.50
row:value("pears", 12.25).    ; pears      12.25
```

Deliberately smaller than printf:

- **No conversion letter.** The receiver knows its own type, so there is nothing
  that could contradict it.
- **No sign mode.** A leading space for a positive number falls out of the width,
  numbers aligning right — which removed a whole mode from the design.
- Numbers align right and text aligns left; `<` `>` `^` override.
- Decimals belong to floats. Asking an integer, string, boolean, or array for
  them is an error rather than a no-op.
- Zero fill must align right — padding a number on the left with zeros would
  change what it says — and goes after any sign.
- A value wider than the width is never cut. Losing digits would be worse than a
  ragged column.

Put on `asString` rather than a separate `format` message, so one message answers
"the text of this value" and there is no second one to drift from it. **No
argument means what it always meant**, so `display`, `fill`, and array rendering
are untouched.

### `format` is now `fill` — `4a70ef0`, 2026-08-19

**Breaking: `"...":format([...])` is now `"...":fill([...])`.**

```
"you have {} apples":fill([#3]):display.    ; you have 3 apples
```

The behaviour is unchanged. The name was wrong: the placeholders are blanks and
the message fills them, whereas `format` belongs to formatting a *single value*
against a spec — where the value is the receiver, not the template.

`"...":fill(...)` is a template acting on values; `45.8:asString("5.2")` is a
value being formatted. Two jobs, and `format` was the wrong word for the first.

Not `replace`, which `string:replace(old, new)` will want.

Formatting a single value is recorded as an open decision (roadmap 2.12). The
shape is settled — a spec argument to the existing `asString`, so one message
answers "the text of this value" and there is no second one to drift from it —
but the spec language itself is not.

### The virtual machine is `bin/solvm` — `efbdf2c`, 2026-08-19

**Breaking: the command changed.** `./bin/solum program.sob` is now
`./bin/solvm program.sob`.

The machine has been called SolVM in prose since the project was named, while the
program on disk was still `solum`. Now they agree.

Its own messages agree too — a runtime error reads `solvm:` rather than `solum:`,
as do the fatal allocation failures in the runtime library.

The **sources stay under `solum/`**, and the include paths and `SOLUM_*` macros
with them. `solum` and `SOLVM` are the same word in two hands, so the directory
keeps the modern spelling and the program the older one. Renaming the tree as
well would touch every `#include` in the project for no gain a reader would feel.

### An object is rendered by asking it — `f55e105`, 2026-08-19

```
point:asString := { "point({}, {})":format([self:x, self:y]) }.

p:print.                     ; point(3, 4)
[p, q]:print.                ; [point(3, 4), point(0, 0)]
"at {}":format([p]):display. ; at point(3, 4)
```

One definition serves `print`, `display`, `format`, and an enclosing array,
because the renderer sends `asString` rather than reaching for a pointer.

The seam had to move: `sol_value_render` now takes a VM, which may be null. The
disassembler passes null — its constants are never objects — and falls back to
the address, which is also what an object without its own `asString` shows.

The recursion this invites is cut at the source: `object`'s default `asString`
writes the address directly instead of calling the renderer back. An `asString`
a user writes to render itself still recurses, but through real frames, so it
stops at the call-depth cap like any other runaway recursion.

### Fixed: error recovery could loop forever — `f55e105`

`synchronise` checked whether the previous token was a `.` *before* advancing, so
a statement that failed without consuming anything — `primary` reports an
unexpected token without taking it — was retried forever when the token before it
happened to be a `.`.

`b := { #1. | q | q }.` produced **three million identical error lines in three
seconds**. Recovery now advances before testing, so it always consumes at least
one token.

Pre-existing, and found by a typo in a test rather than by looking for it. Six
malformed inputs that used to hang are now regression tests.

### String escapes, and `display` — `c04cdca`, 2026-08-19

```
q := "she said \"hi\"".
q:print.                                     ; "she said \"hi\"" -- literal form
q:display.                                   ; she said "hi"      -- the text
"you have {} apples":format([#3]):display.   ; you have 3 apples
```

`\"`, `\\`, `\n`, `\t`, `\r`. An unknown escape is an error rather than a
literal backslash, so a typo is caught where it is written. There is no `\0`:
the chunk's text table is NUL-terminated in memory and one would truncate the
string.

The scanner only learns that a backslash claims the next character, so that `\"`
does not end the string. Which escapes are legal is decided once, in the
compiler, where they are decoded.

**Rendering puts the escapes back**, or a string holding a quote would render as
text that no longer reads as one string. A rendered string now compiles back to
the same string, the same round-trip floats hold to.

**`display`** was the gap escapes exposed. `print` shows the literal form, which
is right for reading a value back but wrong for output — a formatted string could
only be shown wearing quotes, and a string with newlines could not be written as
lines at all. `display` sends `asString` and writes those characters raw. Every
type answers it.

### Float exponents, and text that reads back — `c8cef1b`, 2026-08-19

```
a := 1.5e-3.  b := 1e308.        ; exponents scan now
1234567.0:print.                 ; 1234567   -- was 1.23457e+06
1.0:div(3.0):print.              ; 0.3333333333333333
infinity:print.  nan:print.
```

**This was a correctness bug, not only a cosmetic one.** `%g` gives six
significant digits, so `1234567.0` printed as `1.23457e+06` — a *different
number* — and `asString` baked that into a string. Printing could quietly show
the wrong value.

- A float now renders as the **shortest decimal that reads back as the same
  bits**, found by trying increasing precision until the text parses back
  identically.
- Shortest is not always clearest, so where a number has few enough whole digits
  the renderer keeps `%g` in fixed notation: `1000` rather than `1e+03`. More
  digits can never stop it round-tripping.
- Exponent notation scans: `1e3`, `1E+3`, `1.5e-3`. A bare `e` is left alone
  rather than claimed, so `1e` is a float and an identifier — which the statement
  rule then rejects, a clearer failure than a malformed number. `#` is exact, so
  an integer takes no exponent.
- Infinity and not-a-number are written by name, and `infinity` and `nan` are now
  globals, so those two read back. `-infinity` has no literal form; `asFloat`
  parses it.

The fix caught a drift it was meant to prevent: `prim_float_as_string` had its own
`snprintf("%g")` instead of using the renderer, so `print` and `asString`
disagreed about the same value until it was routed through.

Tested by rendering fifteen awkward doubles, feeding the text back in as source,
and requiring the result to be bit-identical.

### `.` is required between statements — `be13b07`, 2026-08-19

**Breaking, though nothing in the repository changed: every example and test
already wrote the dots.**

`.` separates statements rather than terminating them — required between two,
optional after the last:

```
a := #1
b := #2          ; solas: expected '.' between statements at 'b'

a := #1. b := #2 ; fine, the last needs none
```

This is what groups and blocks already enforced. The top level accepted its
absence anywhere, which meant a missing separator could never be reported, and
the same code stopped compiling merely by being moved into a method body.

Groups and blocks now name the missing separator as well, where they used to
complain about the closing bracket and send the reader looking in the wrong
place.

**It does not catch everything.** A line beginning with `:` continues the
expression above it, so `total := #10` followed by `:add(#5).` is genuinely one
statement with no separator missing. Only a newline-sensitive rule would see two,
and this is not that language. There is a test pinning the behaviour so it stays
a known limit rather than a surprise.

### Formatted output — `ca1369b`, 2026-08-19

```
"you have {} apples and {} pears":format([#3, #4]).
```

`{}` takes the next value and renders it by **sending** it `asString`, so a type
that overrides `asString` is honoured rather than bypassed:

```
point:asString := { "point(":concat(self:x:asString):concat(")") }.
"the answer is {}":format([p]).        ; "the answer is point(7)"
```

- **Both directions of mismatch are errors.** Too few values and too many are
  each reported with the counts. Filling a gap with blanks, or dropping extras,
  would turn a mistake into output that looks deliberate.
- `{{` writes a literal brace. `}` is never special and needs no escape, so `}}`
  is two of them — unlike Python, where `}` closes a placeholder that can carry
  content. Here a placeholder is exactly `{}`, so one escape rule is enough.
- Kept as its own message rather than an argument to `print`, so `print` goes on
  meaning one thing and the text can be used without printing it.

This needed **`sol_vm_send`**, a way for a primitive to call back into the
language. That also unblocks a better default `print` (5.2), which wants to send
`print` to an object rather than showing its address.

### The remaining operations — `7ac6be6`, 2026-08-19

```
x:greaterThan(#0):and({ x:lessThan(#10) }).   ; short-circuit
"abc":lessThan("abd").                        ; strings order
#-5:abs.  #5:negated.  #1:notEquals(#2).
[#1, "a", [#2]]:asString.                     ; "[#1, \"a\", [#2]]"
```

- **`and` and `or` take a block**, so the answer can be settled without running
  it — the same shape as `ifTrue`, and the reason they cannot simply take
  booleans. Strict about what the block answers, as `whileTrue` is.
- **`notEquals` is defined as the negation of `equals`**, so it inherits whatever
  equality means for each type: by value for strings, by identity for arrays.
- **Strings order** by characters, shorter first when one is a prefix — what
  sorting will want. `lessOrEqual` and `greaterOrEqual` on numbers and strings.
- `negated` and `abs`, trapping on the most negative integer, which has no
  positive counterpart — the same edge that guards `INT64_MIN div #-1`.
- `float:new`, for symmetry with `integer:new`.
- **Rendering moved into one place**, a text buffer in `value.c`, so `print` and a
  composite's `asString` produce the same text by construction rather than by
  two implementations agreeing.

Also records **formatted output** (2.11) as an open decision: building a sentence
is currently a chain of `concat` and `asString`, workable for two pieces and
unreadable for five.

### Conversions — `246ae8e`, 2026-08-19

```
"you have ":concat(#45:asString):concat(" apples").   ; "you have 45 apples"
#7:asFloat:div(#2:asFloat).                           ; 3.5
2.7:floor. 2.7:ceiling. 2.7:rounded. 2.7:truncated.   ; #2 #3 #3 #2
"45":asInteger.  "2.5":asFloat.
```

- **`asString` answers plain text; `print` shows the literal form.** `#45:asString`
  is `"45"`, not `"#45"` — the point of it is building text, and "you have #45
  apples" would be wrong. Two jobs, kept apart, as Smalltalk separates
  displayString from printString.
- **Narrowing names its direction.** There is no `asInteger` on a float: `floor`,
  `ceiling`, `rounded`, and `truncated` each say what they do, so there is no
  default to remember. Each can fail, since most floats have no integer
  counterpart — infinity, not-a-number, and anything out of range are errors.
- **Parsing is strict at both ends.** The whole string must be a number and
  nothing else, so `"12abc"`, `""`, `" 45"` and `"45 "` are all errors. The
  leading-space case needed an explicit check, since `strtoll` skips whitespace
  of its own accord and the two ends would otherwise have behaved differently.
- Widening an integer past 2^53 loses precision silently, which is what binary64
  is; erroring would be unlike every other language.

This also fills the gap floored division left: `#7:div(#2)` is `#3`, and
`#7:asFloat:div(#2:asFloat)` is `3.5`.

### `via`: calling the method you override — `a5aa9e0`, 2026-08-19

```
animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro.        ; "I am rex!"
```

Before this, an override could reach the ancestor's *code* but not with the right
receiver — naming the ancestor sends to it, so `self` inside became the ancestor
and `rex:intro` answered `"I am animal!"`. An overriding method could therefore
only extend one that never consulted `self`.

`self:via(ancestor)` answers a delegating view: a send to it begins the lookup at
the ancestor and runs what it finds with `self` still the receiver.

- **The ancestor is named rather than inferred.** A `super` keyword would have to
  resolve against the object where the running method was *defined*, which is
  bookkeeping no frame carried. Naming it needs none of that, stays correct
  however deep the receiver is, and cannot find the method again and recurse.
- `parent` reads the delegation link so a chain can be walked. Read-only: the
  link stays an internal pointer, so nothing a program writes can corrupt
  dispatch.
- Dispatch needed one change — a delegate receiver rewrites its own stack slot to
  the real receiver before lookup, after which every existing path reads `self`
  correctly without knowing delegates exist.

### User-defined objects — `d27176f`, 2026-08-19

```
point := object:new.
point:x := #0.                          ; a default every instance sees
point:sum := { self:x:add(self:y) }.    ; a method: a slot holding a block
point:make := { a, b | | p | p := self:new. p:x := a. p:y := b. p }.

p := point:make(#3, #4).
p:sum:print.                            ; #7
```

One primitive — `object:new`, answering a fresh object that delegates to the
receiver. That was the whole gap: slot assignment, proto-chain lookup, and
block-in-a-slot-is-a-method already existed, so this needed a primitive rather
than a mechanism.

- **There is no separate notion of a class.** An object given slots, and an
  object created from *that*, differ only in how you use them.
- Assigning on an instance always makes the instance's own slot, so it shadows
  the prototype rather than writing through — one instance cannot change all of
  them.
- Delegation chains, and the nearest slot wins, so overriding works at any depth.
- Equality is identity: two objects with the same slots are still two objects.
- The default `print` is overridable, since a `print` slot on the prototype is
  found before the primitive.

The built-in classes deliberately do not delegate to `object`: `float` inheriting
its `new` would answer a plain object rather than a float. That leaves two
hierarchies that do not meet, which is the class-side/instance-side question in
the roadmap.

### Division — `9ad8039`, 2026-08-19

`div` and `mod`, on integers and floats.

```
#7:div(#2):print.     ; #3
#-7:div(#2):print.    ; #-4   floored, not truncated
#-7:mod(#2):print.    ; #1    the divisor's sign, not the dividend's
```

- **Answering an integer was forced rather than chosen.** A float result would
  let two integers leave their type silently, which is the coercion the language
  refuses everywhere else. A fractional answer needs an explicit conversion —
  which does not exist yet, and is now the most-missed missing operation.
- **Floored, for what it does to `mod`.** A floored remainder always lands in
  `[0, n)` for positive `n`; a truncated one takes the dividend's sign and needs
  correcting at every use site. `quo`/`rem` stay free for the truncating pair.
- **Division by zero splits along a line the language already had.** Integers
  trap, having no infinity; floats answer one, since float multiplication already
  overflows to infinity where integer multiplication traps.
- `INT64_MIN div #-1` is guarded separately — the one division that overflows,
  and undefined behaviour in C rather than merely wrong, raising SIGFPE on x86.

Also recorded two gaps found while checking the above: float literals have no
exponent notation (`1e308` does not scan), and `print` emits float text the
scanner cannot read back (`1e+256`, `inf`).

### Strings — `e454192`, 2026-08-19

```
s := "hello".
s:concat(", world"):print.        ; "hello, world"
"hi":equals("hi"):print.          ; true
["ada", "grace"]:collect({ n | n:concat("!") }).
```

`SolString` and the `string` class: `print`, `size`, `equals`, `concat`, `at`.

- **Immutable, and therefore a value rather than a reference.** `equals` compares
  characters, where an array compares identity. That completes the split the
  language already had: numbers and strings are values, objects and blocks and
  arrays are references.
- One-based `at`, answering a one-character string since there is no character
  type. Strict `concat`: joining a string to a number is an error, not a
  conversion.
- Printed as it would be written — `"hello"`, not `hello` — the way `#45` prints
  as `#45`.
- **No `.sob` change was needed after all.** A literal's bytes ride in the chunk's
  interned text table beside selectors and global names, and `OP_STRING` builds
  the string at run time — which is also how the compiler emits one without
  having a VM to allocate in. Only the opcode set changed, so the format went to
  version 5.
- A string holds bytes, not values, so it has no outgoing edges for the collector
  — the difference from an array that made arrays the better first heap type.

Left open, each independent: escape sequences, interning, ordering, and
conversions to and from numbers.

### collect and select — `b9b9702`, 2026-08-19

```
[#1, #2, #3, #4, #5]:collect({ x | x:mul(x) }).      ; [#1, #4, #9, #16, #25]
[#1, #2, #3, #4, #5]:select({ x | x:greaterThan(#2) }).  ; [#3, #4, #5]
```

Both answer a new array and leave the receiver alone, so they chain into a
pipeline that reads left to right.

These are the first primitives to need a **temporary root**, and it turned out to
be load-bearing rather than cautious. They allocate a result array and then call
a block per element, and a block can allocate; between calls the result is
reachable only from a C local. Removing the root and running under
`SOLUM_GC_STRESS=1` with ASan turns the loop into a heap-use-after-free in
`sol_array_add` — the result is swept while it is still being filled.

`select` appends each element *before* testing it and winds the count back on
rejection, so the element is never held only in a C local across a block call.

`select` is strict about its block answering a boolean, as `whileTrue` is.

### Array literals — `63749ee`, 2026-08-19

```
xs := [#1, #2, #3].
n := [[#1, #2], [#3]].
e := [].
```

`[...]` is sugar for `array:of(...)` in the strict sense: the two forms compile
to byte-identical `.sob` files, and a test asserts it rather than trusting the
claim. Two lexer tokens and one compiler branch — no new opcode, no verifier
change, nothing the VM has to learn.

Because the desugaring is real rather than a lookalike, the `array` it sends to
is the ordinary global; rebinding that name moves both spellings together. They
cannot drift apart, which is the point.

A literal is a construction, not a pooled constant, so every evaluation answers a
fresh array — two calls to a method containing one do not share it. Capped at 255
elements by `OP_SEND`'s one-byte argument count.

**Rejected: making `[...]` immutable so it could be pooled.** Pooling would only
ever apply where every element is itself a compile-time constant — `[a, b]` must
be built at run time regardless — so the price is a rule the reader has to
re-check at every use site, for a saving that most literals would not get. Two
spellings mean one thing, which is the principle this was weighed against.

### The project is named Solveig — `7db2b27`, 2026-08-19

The repository had no name distinct from its parts: "Solum" was serving as the
project, the virtual machine, and the language at once.

**Solveig** now names the project. The language stays **Solum**, and the programs
stay **Solas**, **SolVM**, and **Solis**. Old Norse *Sólveig*, from *sól* "sun"
and *veig*, usually read as "strength" -- the Norse cousin of the *sol-* root the
rest of the family already shares. The README carries the longer note, including
why *SolVM* and *solum* are the same word: classical Latin wrote V where we now
write U, so Roman inscriptions give SOLVM.

Documentation only. No code, no file names, and no behaviour changed.

### Arrays — `1d8c573`, 2026-08-19

Nothing in the language could hold more than one value, so no program could
accumulate a result.

```
a := array:of(#10, #20, #30).
a:at(#1):print.              ; #10 -- indices are one-based

b := array:new.
b:add(#1):add(#2):add(#3).   ; add answers the array, so it chains
b:do({ e | sum := sum:add(e) }).
```

- A `SolArray` heap type joins the collector, and **every element is a tracing
  edge** — the reason arrays were built before strings, whose bytes are not.
- One-based indices: an index is an ordinal, not an offset — there is no pointer
  arithmetic here and no address for it to be a displacement from, so what makes
  zero-based natural in C does not apply. It also matches the Smalltalk lineage
  the object model already came from. `at(#0)` is out of bounds and therefore
  caught rather than silently off by one.
- Strictness carried through: an index must be an integer, and out of range is an
  error rather than nil.
- Arrays are references, like objects. `equals` is identity; comparing contents
  is a different question and will get its own name.
- `do` bounds the count once and re-reads the backing store each pass, since the
  block may grow the array and move the store underneath it.
- Printing is depth-limited, because `a:add(a)` is legal.
- No `.sob` change: an array is built at run time, never pooled as a constant.

Still to come: the `[...]` literal sugar, and `collect`/`select`.

### Roadmap audit — `470c6d3`, 2026-08-18

No code change. Audited the roadmap against the source and against everything
raised in review, and added the two real gaps it was missing:

- **Recursion is limited to about 30 levels** (3.5). `SOL_FRAMES_MAX` is 64 and
  each recursion level costs two frames in the idiomatic form -- the method's
  block, and the `ifElse` branch block carrying the recursive call. Measured: 30
  succeeds, 31 reports "call depth exceeded". Low enough for ordinary code to
  hit.
- **A caller-owned chunk must outlive blocks defined in it** (3.6). Freeing one
  while a reachable block points into it leaves that block undefined to call. The
  collector is safe -- a block caches its owning cell, so tracing never touches a
  freed chunk -- but nothing detects the call.

Also corrected a comment in the compiler claiming there were no blocks yet.

### The collector owns compiled code — `104a5e0`, 2026-08-18

Solis no longer retains every line's chunk. Over 60,000 REPL lines, peak resident
set went from **25.5 MB growing linearly to 1.9 MB flat**.

Ownership is dual rather than wholesale, because Solas has no VM to own a chunk
on its behalf. A chunk from `sol_chunk_init` is caller-owned and freed by hand;
one from `sol_code_new` belongs to a `SolCode` cell the collector sweeps.
`sol_chunk_add_method` propagates ownership as each subtree is added, so a caller
cannot forget to.

- Added `sol_gc_push_temp` / `sol_gc_pop_temp` for cells held only in a C local
  across an allocation. Solis uses them to protect a fresh code cell while it
  compiles into it.
- A chunk's constants are traced, since they will hold heap values as soon as
  strings exist.
- A block caches its owning cell rather than reading it back through
  `block->code->chunk`. A caller-owned chunk can be freed while blocks pointing
  into it are still on the heap — calling such a block was always wrong, but the
  tracer must not fault merely for walking past one. Stress mode under ASan found
  this as a use-after-free in `mark_code`.

### A garbage collector — `29d011a`, 2026-08-18

Mark–sweep, non-moving, stop-the-world. Objects and blocks are reclaimed while a
program runs; before this nothing was freed until the VM exited.

The motivating case — a block literal allocated once per loop iteration — over
two million allocations:

| | Peak RSS |
| --- | --- |
| before | 98 MB, growing linearly |
| after | 1.5 MB, flat |

- Both heap types now begin with a shared `SolGCHeader`, so one list threads the
  whole heap and one sweep loop walks it. A new heap type joins by embedding the
  header rather than adding another list.
- Marking uses an explicit worklist, not recursion, so a graph deeper than the C
  stack traces without overflowing it — a 200,000-link proto chain is a test.
- Collection happens *before* an allocation, so the new cell cannot be swept.
  `sol_vm_init` nulls the roots before its first allocation for the same reason.
- `SOLUM_GC_STRESS=1` collects on every allocation. The whole suite passes under
  it with ASan and UBSan.

Code is still owned by the chunk that compiled it, so Solis continues to retain
every line's chunk; that is roadmap 1.1b.

### `:=` became one operator — `7029d27`, 2026-08-18

**Breaking: method definitions changed shape, and `.sob` went to version 4.**

`:=` used to mean two different things depending on what stood to its left. In
`a := #45:add(#32)` it evaluated the right-hand side; in
`integer:fun() := #45:add(#32)` it did not — that was a definition form the
compiler pattern-matched, whose right-hand side was compiled to run later,
freshly, on every call.

Now there is one rule: `obj:name := value` evaluates and binds, exactly as
`a := value` does.

```
integer:double := { self:mul(#2) }.
integer:poly := { a, b | self:mul(a):add(b) }.
integer:quadruple := { | d | d := self:double. d:double }.
```

- A slot holds a value. A slot holding a **block** is a method: sending its name
  runs the block with the receiver as `self`. A slot holding anything else
  answers that value, so methods and data slots are no longer different kinds of
  thing.
- Because `:=` evaluates, a method can be **computed**:
  `integer:double := maker:value()`.
- Blocks gained parameters: `{ a, b | ... }`. A leading `|` still means
  temporaries.
- Capture now **chains**. With no separate notion of a method, every frame is a
  block's, so `OP_OUTER` carries a depth and the runtime walks the lexical chain,
  checking liveness at each hop.
- `self` is no longer resolved lexically at compile time — which block ends up
  invoked as a method is not knowable there. It compiles to slot 0 of the frame
  being entered; the VM captures the receiver into a block at creation, and a
  send to a slot holding it overrides slot 0.
- The method-definition special form left the compiler, and about 100 lines with
  it.

### Method temporaries must be declared — `343d776`, 2026-08-18

**Breaking: bodies that relied on implicit locals need `| ... |`.**

Fixes a real defect. Assignment inside a method used to declare a local for any
new name, so a global could not be updated from a method at all, and because the
local was declared before its own initializer was compiled,
`counter := counter:add(#1)` read the fresh nil local and failed with
"nil does not understand 'add'".

- Only parameters and names declared with `| a, b |` are locals. Everything else
  is a global, read or written.
- Only the script's top level may **create** a global, so an undeclared name
  inside a method or block must already exist — a typo is reported instead of
  quietly becoming a variable that looks local.
- Declarations may open any group or block body. A duplicate name in one frame is
  a compile error.

### Documented what verification does not promise — `be7fdca`, 2026-08-18

Verification guarantees a loaded chunk is safe to execute; it does not guarantee
the program terminates, and it should not. Established by fuzzing rather than
assumed: every hang seen while corrupting a `.sob` mapped to a constant payload
or code byte, never to a name, count, or length the loader parses, and a control
run over a program with no loop produced zero hangs.

### Blocks, booleans, and message-based control flow — `284d015`, 2026-08-18

**`.sob` went to version 3.**

```
#5:lessThan(#10):ifElse({ #100:print }, { #200:print }).
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
```

- `{ ... }` makes a block: code as a value, deferred rather than run.
- Control flow is ordinary message sending. `ifTrue`, `ifElse`, and `whileTrue`
  are plain primitives receiving an unevaluated block, so **the language has no
  control-flow syntax** and a user can add control structures the same way.
- The interpreter became re-entrant so a primitive can invoke a block.
- Added a boolean type with `true`/`false` and `not`, and `equals`, `lessThan`,
  `greaterThan` on numbers. Comparisons are as strict as arithmetic; `equals` is
  the exception, answering false across types rather than erroring.
- Capture is lexical, with two cheap measures instead of heap promotion: a block
  that does not touch its home frame may escape freely, and one that does records
  a frame id so calling it after that frame returned is reported.
- With conditionals, recursion can terminate — the language became
  Turing-complete.

### Methods, call frames, and locals — `dd31244`, 2026-08-18

**`.sob` went to version 2.**

Methods could be written in Solum source rather than only as C primitives, and
the VM grew call frames. A frame's slots point into the value stack at the
receiver, so nothing is copied to make a call. Solis began retaining every line's
chunk, because a class holds only a pointer to a method the chunk owns.

### The `.sob` bytecode file format — `2b2bea2`, 2026-08-18

Solas writes bytecode to a file and Solum loads and runs it. Little-endian and
host-independent; floats survive bit-identical; line numbers are run-length
encoded.

A `.sob` file is treated as untrusted input: the loader bounds-checks every read
and rejects a count that could not fit in the bytes remaining, and what survives
is verified before it can execute — every instruction fits, every operand indexes
something real, and the final instruction stops the machine so the dispatch loop
cannot run off the buffer.

### Initial commit — `52f2f01`, 2026-08-18

Solas (compiler), Solum (VM), and Solis (REPL) as three components sharing one
static library, with `solum/include/solum/bytecode.h` as the single contract
between compiler and VM.

Design decisions taken here: a name is a binding rather than an object and values
are immutable; `#` is a type tag, so `#45` is an integer and a bare `45` is a
float; arithmetic is strict and integer overflow traps rather than wrapping.
