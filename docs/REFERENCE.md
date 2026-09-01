# Solveig — language reference

Solveig is the language; **Solas** compiles it, **SolVM** runs the **Solum** bytecode it produces, and
**Solis** is the REPL. This document describes the language as it is, message by
message, for looking things up.

If you are meeting the language for the first time, read [GUIDE.md](GUIDE.md)
instead — the same ground in an order that builds, with a runnable example behind
each concept. For why the language is this way see [design.md](design.md); for
what is still missing see [ROADMAP.md](ROADMAP.md). For the same surface as this
document compressed onto one page, a line each, see
[CHEATSHEET.md](CHEATSHEET.md).

Everything is an object and all work happens by sending messages.

```
a := #45.
a:print.
```

## Contents

- **[Running a program](#running-a-program)**
  - [The prompt](#the-prompt)
  - [Stopping a program: Solid](#stopping-a-program-solid)
  - [What a file exports](#what-a-file-exports)
  - [Watching a program run](#watching-a-program-run)
  - [Staying after a program](#staying-after-a-program)
  - [Running a script directly](#running-a-script-directly)
- **[Splitting a program across files](#splitting-a-program-across-files)**
  - [Loading a compiled file](#loading-a-compiled-file)
  - [The library](#the-library)
- **[The program and its process](#the-program-and-its-process)**
  - [Stopping](#stopping)
  - [Arguments](#arguments)
  - [Reading input](#reading-input)
  - [Files](#files)
  - [Running another program](#running-another-program)
  - [The clock](#the-clock)
- **[Lexical structure](#lexical-structure)**
  - [Comments](#comments)
  - [Statements](#statements)
  - [Literals](#literals)
  - [String escapes](#string-escapes)
  - [Identifiers](#identifiers)
  - [Reserved names](#reserved-names)
- **[Values](#values)**
  - [Strictness](#strictness)
- **[Names and binding](#names-and-binding)**
- **[Messages](#messages)**
  - [Grouping](#grouping)
  - [Infix operators](#infix-operators)
- **[Blocks](#blocks)**
  - [Capture](#capture)
- **[Control flow](#control-flow)**
  - [What the compiler does with them](#what-the-compiler-does-with-them)
- **[Objects](#objects)**
  - [The built-in classes are objects too](#the-built-in-classes-are-objects-too)
  - [Adding methods to a built-in class](#adding-methods-to-a-built-in-class)
  - [Calling what you override](#calling-what-you-override)
  - [Showing an object](#showing-an-object)
- **[Asking whether a value is there](#asking-whether-a-value-is-there)**
- **[Errors](#errors)**
  - [Raising one](#raising-one)
  - [The error](#the-error)
  - [What it catches](#what-it-catches)
  - [Cleaning up regardless](#cleaning-up-regardless)
- **[Reflection](#reflection)**
  - [Fetching a method](#fetching-a-method)
- **[Message reference](#message-reference)**
  - [Every type](#every-type)
  - [integer](#integer)
    - [Bits](#bits)
  - [float](#float)
  - [string](#string)
  - [array](#array)
  - [symbol](#symbol)
  - [boolean](#boolean)
  - [dictionary](#dictionary)
  - [time](#time)
  - [block](#block)
  - [object](#object)
  - [system](#system)
  - [random](#random)
  - [nil](#nil)
- **[How errors are reported](#how-errors-are-reported)**
- **[Limits](#limits)**

And an alphabetical **[message index](#message-index)** at the end: every built-in message and the types that answer it.

---

## Running a program

```sh
./bin/solas program.sol             # compiles to program.sob
./bin/solvm program.sob             # runs it
./bin/solvm program.sob a b c       # ...with arguments, which system:arguments answers
./bin/solis                         # a prompt; input may span lines
./bin/solis program.sol             # compiles and runs it, without the two steps
./bin/solis program.sob a b c       # runs compiled bytecode, with arguments
./bin/solid program.sol             # runs it under the debugger
```

Each takes `--help` (or `-h`), which lists its options and stops, and
`--version`:

```sh
$ ./bin/solas --help
usage: solas [options] <file.sol>
...

$ ./bin/solvm --version
solvm 0.3.0 (.sob format 11)
```

Both go to **stdout** and leave with 0, since they are what was asked for. The
usage text after a *mistake* goes to stderr and leaves with 64.

`--version` names the `.sob` format as well as the release, because that is the
number that goes wrong in practice: a file built by a different one is refused
rather than misread, and this is where you find out which one you are holding.

Everything after the file belongs to the program, so a front end's own flags
have to come first — including `--help` itself. `solvm program.sob --help` hands
`--help` to the program, which is what lets a script have one of its own.

`solis` decides what it was given by **looking at the bytes**: a file beginning
with `SOLB` is bytecode and anything else is source. Not the extension, so a
script with no extension at all works — which is the point of the next part.

### The prompt

`solis` with no file reads from a prompt, and input may span lines: it reads
until what has been typed *could* compile, showing `..` while it waits.

#### The keys

Editing and history, when standard input is a terminal. They are the readline
bindings, so they are the ones bash has taught you.

| key | does |
| --- | --- |
| **↑ ↓** | back and forward through the lines already entered |
| **← →** | one character within the line |
| **home**, **ctrl-a** | to the start of the line |
| **end**, **ctrl-e** | to the end of it |
| **backspace** | delete the character before the cursor |
| **delete** | delete the character under it |
| **ctrl-h** | on an **empty** line, list the last 10 entered; otherwise backspace |
| **ctrl-u** | discard the whole line and start it again |
| **ctrl-l** | clear the screen, keeping the line being typed |
| **ctrl-d** | **end the session** on an empty line; delete forwards otherwise |
| **ctrl-c** | interrupt |
| **ctrl-z** | suspend |
| **return** | run it, if what has been typed could compile — otherwise a `..` prompt and keep going |

**`ctrl-h` is backspace**, and on many keyboards it is the byte the backspace
key sends. It lists history only on an empty line, where there is nothing to
delete and the key is otherwise doing nothing:

```
> [ctrl-h]
  1  #7:mul(#6):print.
  2  "hello":display.
>
```

Two departures from bash worth knowing. **`ctrl-u` discards the whole line**
rather than only the part before the cursor, which is what the terminal's own
kill character has always done here. And **`ctrl-c` and `ctrl-z` are the
terminal's**, not the prompt's: they are left alone deliberately, since taking
them over would be a surprise.

A line stepped away from with ↑ is kept, so ↓ brings back what you were typing
rather than an empty line. The same line twice running is one entry, so
re-running something to watch it fail again does not mean pressing ↑ twice to
get past it.

#### History between sessions

What you type is kept in **`$HOME/.solis_history`**, so ↑ reaches the lines from
the last time as well as this one. It holds the most recent 1000 and is trimmed
on the way out; with no `HOME` set, history lasts as long as the session and no
longer.

It is an ordinary text file, one line per entry, so it can be read, edited or
deleted like any other. Failing to write it is ignored — a prompt that refused
to exit because it could not save history would be worse than one that quietly
forgets.

**Through a pipe or a file** — `solis < script.sol`, or anywhere `TERM` is
`dumb` or unset — the prompt reads a line at a time with no editing, exactly as
it did before there was any. Nothing is required to be installed for either: the
editing is `termios`, and the build still needs only a C11 compiler and `make`.

The cursor moves a byte at a time, so a left arrow steps into the middle of a
multi-byte character rather than over it. That is
[the same thing](ROADMAP.md#213-text-is-bytes-and-case-is-ascii-only) as a
string being bytes rather than characters, and it will be answered when that is.

### Running a script directly

A `#!` on the very first line is skipped, so a `.sol` file can be marked
executable and run like any other script:

```sh
$ cat hello.sol
#!/usr/bin/env solis
"hello":display.

$ chmod +x hello.sol
$ ./hello.sol
hello
```

`#!/usr/bin/env solis` is the portable form. Writing `#!/bin/solis $*` will not
do what it looks like: the kernel passes at most one argument after the
interpreter and passes it literally, so the `$*` would arrive as an argument
spelled `$*`. Arguments to the script are handled without it — they arrive as
`system:arguments`, as they do for `solvm`.

Only at the very start, and only `#!`. Anywhere else `#` begins an integer
literal, including on line 1 after column 0. The newline is left in place, so
the line after the shebang is line 2 and an error names the line an editor
shows.

The program is `solvm`; its sources live under `solum/`. The two are the same
word -- `SOLVM` is how *solum* was written before the alphabet split V into two
letters -- so the directory keeps the modern spelling and the program the older
one.

`solas --dump` also prints the disassembly. `solvm --dump` prints it for a
compiled file before running.

#### Staying after a program

`solis --interactive file.sol` runs the file and then stays at the prompt, with
everything the program bound still bound — **including after it fails**:

```sh
$ solis --interactive report.sol
solvm: index #99 is out of bounds for an array of size 4
  [line 7] in script
-- program failed; its names are here
solis 0.8.0 -- ctrl-d to exit
> tally:print.
[#1, #4, #9, #16]
> config:at("host"):display.
localhost
```

**A script's own names are globals**, so they survive the unwind: the dictionary
it built, the array it was filling, the objects it made. A method it defined can
be called again, which is how the failing call gets looked at:

```
> a:balance:print.
#70
> { a:withdraw(#500) }:onError({ e | e:message:display }).
not enough
```

What is gone is the **frames**. Nothing can be resumed and a block's temporaries
are lost with the stack, so this is a prompt beside the wreck rather than a
break in the middle of it. That is most of what is available: a stepper would
need [names for locals](COMPLETED.md#628-local-variables-have-no-names-at-run-time--done),
which the chunk does not carry.

It stays after a program that *finishes*, too, which is the other half of being
able to look at what one did.

`solis` also takes `--trace` and `--trace=N`, which do what they do for `solvm`.
The prompt itself is not traced — what was being watched is the program.

#### Stopping a program: Solid

`solid file.sol` runs a program and stops before its first line, ready for
commands. It is the debugger — the fourth program, after Solas, SolVM and Solis.

```
$ solid report.sol
solid 0.11.0 -- `help` for commands, `quit` to leave
report.sol:1  in script
    1  account := object:new.
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

| command | does |
| --- | --- |
| `step`, `s` | run to the next line, **into** calls |
| `next`, `n` | run to the next line, **over** calls |
| `finish`, `f` | run until this frame returns |
| `continue`, `c` | run to the next breakpoint |
| `where`, `w` | the frames, innermost first, with file and line |
| `locals`, `l` | this frame's slots, **by name** |
| `globals`, `g` | what this program bound; `globals all` adds the built-in names |
| `print NAME`, `p` | a local, or a global, saying which |
| `list [N]` | source around here, or from line N |
| `break F:L`, `b` | stop at that line; `break L` for any file |
| `breaks`, `delete N` | what is set, and dropping one |
| `quit`, `q` | stop the program and leave |

**`globals` is the one question a program cannot ask itself.** The globals are
slots on an object with no name in the language, so neither `slots` nor
`perform` reaches them — see
[design.md](design.md#why-binding-is-syntax-and-not-a-message) and 2.10 in
[ROADMAP.md](ROADMAP.md). A debugger holds the root object directly, so here it
is answerable:

```text
(solid) globals
  account          <object 0x10122e250>
  rate             0.05
  -- and 18 built in; `globals all` for those too
```

Listed **in the order they were bound**, which is not the order they are stored
in — a new name goes on the front of the slot list, so reading it straight
through would put the last line of the program first. And a method is a slot on
a class rather than a global, so `integer:double := { ... }` is not in this
list; `integer:slots` is where that lives.

**A breakpoint's file is matched at the end of a path**, so `break json.sol:150`
finds `lib/json.sol` without anybody having to type the include path it was
found on. It fires on **arriving** at its line: a call written on line 10
returns to line 10, and stopping twice would make one breakpoint look like two.

**A file brought in by [`system:load`](#loading-a-compiled-file) is debugged
like any other.** It runs in an ordinary frame, so `step` goes into it, `next`
goes over the load, `finish` comes back out, and `where` shows it above the
frame that loaded it — with each frame naming its own file. A breakpoint may be
set in a file that has not been loaded yet, which is the only order that is any
use, since by the time it has loaded it has run. A failure inside one stops
there, in that file, with the loading frame still underneath and both files'
globals readable.

`list` is the one thing that can fail, and it fails politely: a library shipped
as bytecode without its source has nothing to show, so it says `cannot read` and
everything else keeps working.

**It stops where a program breaks**, with the frames still standing — which is
the thing [`solis --interactive`](#staying-after-a-program) cannot do, since
that starts after the unwind and sees only globals:

```
-- division by zero in 'div'
breaks.sol:2  in block
    2      result := a:div(b).
   (it cannot go on from here; look around, then `quit`)
(solid) locals
  a                #100
  b                #0
```

Nothing can be resumed from there — the unwind is already decided — but the
values that caused it are still in the frame.

**What it can show is what the chunk carries**: the file and line of every frame,
and what each slot was called. Both were built before the debugger was, for it.
A chunk compiled at the prompt has no file, and says so rather than guessing.

#### What a file exports

`solid --exports` does not stop. It runs the file, then says what is in the
machine that was not there before -- the names it bound, and what may be sent to
each of them.

```
$ solid --exports lib/json.sob
lib/json.sob
  json
    read                 takes 1 argument
    write                takes 1 argument
    quote                takes 1 argument
    keyText              takes 1 argument
    -- and 19 behind an `exports` boundary; `--exports=all` for those too
```

**It reads a `.so` the same way**, which is the case with no other answer at
all: an extension's surface is not written down anywhere, and exists only once
`sol_extension_init` has run. With one named there need be no file to give.

```
$ solid --exports --extension=build/extensions/net.so
build/extensions/net.so
  net
    udp                  a primitive
    port                 a primitive
    send                 a primitive
    receive              a primitive
    waitFor              a primitive
```

A primitive has no arity to report, because it checks `argc` itself and nothing
records what it will accept. Name both a bundle and a file and you get **two
reports**, one under each name, so which of them bound what is never a guess.

**A file that binds nothing may still have added something.** `lib/text.sol`
binds no name at all -- it hangs `asUtf8` on `integer` -- so every built-in class
is measured before the run and again after:

```
$ solid --exports lib/text.sob
lib/text.sob
  integer   (extended)
    utf8Tail             takes 1 argument
    asUtf8               takes 0 arguments
```

That is also why this reads the file by **running** it rather than by reading
its bytecode. A reader of `OP_SET_GLOBAL` would print nothing for `text.sob` and
be wrong, and would have nothing at all to read in a `.so`. The cost is that the
file runs, with whatever else it does on the way: a library binds its names and
stops, which is all it does, but a program does whatever it was written to do
first. A file that fails part-way reports what it had bound by then and says
that is what it is, leaving with status 70.

**The [`exports` boundary](#the-export-boundary) is honoured**, because it is the
answer to the question being asked. Names it keeps private are counted rather
than listed; `--exports=all` lists them, marked. An object that never drew one
has every name listed, which is the truth about it.

**This is a mode of the debugger and could not have been a program.** The
globals are slots on an object with no name in the language, so `slots` cannot
reach them and neither can `perform` -- `globals` above says the same thing about
itself. Solid holds the root object, so both questions are answerable from here
and from nowhere else. Once you *have* a name, the language answers the rest:
`json:slots`, `json:exports` and `json:respondsTo` are ordinary sends, and are
under [Reflection](#reflection).

#### Watching a program run

`solvm --trace` writes the **call tree** to stderr as the program runs: a line
entering each frame, a line leaving it, indented by depth.

```
  [report.sol:7] <object 0x1027ea980>:describe
    [lib/shapes.sol:4] <object 0x1027ea980>:double
    -> #42
  -> "x doubled is 42"
```

Arguments are **named**, when the chunk remembers what the parameter was called:

```
  [locals.sol:7] value(numbers: [#10, #20, #33])
    [locals.sol:4] value(n: #10)
    -> #1
```

The place is where the **call** is written — file and line, since a chunk holds
code from every file an `@include` reached — and the name is the selector it was
**sent as** — so a block installed in a slot shows as the method it is, and a
block called with `value` shows as that.

**Frames rather than sends**, which is what makes it readable: a send is
arithmetic as often as it is a call. And because conditionals and loops written
literally [compile to jumps](#what-the-compiler-does-with-them), a loop running
three hundred thousand times produces **no trace lines at all** — what shows up
is the calls, which is what was wanted.

`--trace=N` follows calls only `N` deep, which is where a program's shape is.
On `programs/page.sol`:

| | lines of trace |
| --- | --- |
| `--trace=1` | 148 |
| `--trace=2` | 1,130 |
| `--trace` | 9,284 |

It goes to **stderr**, so a program's own output can still be piped somewhere
and nothing it prints changes. Values longer than 48 characters are cut, since a
trace is read by eye. They are rendered without sending `asString`, so an object
shows as its address rather than however it describes itself — a trace that ran
the program it was tracing would not be one. `solas -o <file>` chooses where the bytecode goes,
the default being the source name with `.sob` in place of `.sol`; `-I <dir>` on
`solas` and `solis` adds to the include search path and is described
[below](#splitting-a-program-across-files).

A `.sob` file is verified before it runs: every instruction must fit, every
operand must index something that exists, every jump must land on the start of
an instruction inside the chunk, and the last instruction must stop the machine.
A corrupt file is refused rather than executed.

The file also carries a format version, and a build reads only its own: a `.sob`
left over from an earlier one is refused with `unsupported bytecode version`
rather than misread. Recompile the `.sol`. `solvm --version` says which format
this build speaks.

---

## Splitting a program across files

```
@include "library.sol".
```

compiles that file into this one at that point, as though its text had been
written there. Globals are one flat namespace and stay one: two files binding
the same name collide exactly as two `:=` in one file do, and the later wins.

**`@` marks a directive**, and a directive is not a message. What follows the
`@` happens while compiling; by the time the program runs there is nothing left
of it to run. That is the whole of what the sigil is for, and it is why nothing
in the `@` space is written as a send.

The file name has to be a literal string, because the file is found while
compiling and a name holding one has no value yet.

**It stands alone.** A file compiled in at that point has nowhere to go inside
an expression, so anywhere other than on its own as a statement a directive is a
compile error:

```
[prog.sol:1:7] solas: a directive must stand alone as a statement at '@include'
  x := (@include "library.sol").
        ^^^^^^^^
```

**`@expr` is the exception, and it is the only one.** It answers a value, so it
is an expression and may stand wherever one may — as a receiver, an argument, an
array element, a statement of its own. `@include` cannot be any of those because
a file compiled in has nowhere to go inside an expression; `@expr` has nowhere
*else* to be. See [infix operators](#infix-operators) below.

There are two directives, and an unknown one is refused rather than passed
through, since `@` is the compiler's own space and a name in it that the
compiler does not know is a mistake:

```
[prog.sol:1:1] solas: unknown directive at '@compile'
  @compile "library.sol".
  ^^^^^^^^
```

A directive is one token, `@` and all, so the bare word stays free: `include` is
an ordinary name that any object may use for a slot.

**The file is found beside the file including it**, not beside the directory you
happened to be standing in, so a program can be moved without its includes
breaking. An absolute path is taken as it stands. Source that is not a file at
all — the prompt, or a string handed to the compiler — has nothing to be
relative to, and the working directory is used.

**Failing that, the search path.** A name not found beside the includer is
looked for in each directory of the search path, in order, and the first that
has it wins:

- `-I dir` arguments to `solas` or `solis`, in the order given;
- then the entries of `SOLUM_PATH`, colon-separated;
- then the library shipped beside the binary — `bin/solas` looks in `bin/../lib`;
- then where `make install` put it, which is how a binary found on `PATH`
  finds a library at all: `argv[0]` names no directory then, so the location is
  written into the build rather than worked out at run time.

That is C's rule for a quoted include, and for C's reason: your own files are
found without saying where they are, and a name you do not have locally comes
from the library. It carries C's cost too — a local file **shadows** a library
one of the same name — which is usually what you want and occasionally a trap.
A file that includes a library file of its own name finds *itself* beside it
first, and, a file being compiled once, that include does nothing at all.

**That one is warned about**, since it is never what anybody meant and the
compiler is holding both halves of the question:

```
[greet.sol:1:10] solas: warning: this file includes itself, so the include does nothing -- a file beside the includer wins, and 'lib/greet.sol' on the search path is what it shadowed
  @include "greet.sol".
           ^^^^^^^^^^^
```

A warning rather than an error: shadowing is the rule and stays, the file still
compiles, and the status is unchanged. Only the **direct** case is warned about
— a file reached twice by different routes is the ordinary reason a file is
compiled once, and two files including each other is a cycle that ends on
purpose. Neither is a mistake.

An absolute name searches nothing. A file found nowhere says so:

```
[prog.sol:1:10] solas: cannot read the included file 'prog/missing.sol', and it is not on the search path either
```

### Loading a compiled file

```
system:load("library.sob").
```

runs a `.sob` that was compiled separately, in the machine that is already
running, and the names it binds are there afterwards. It is `@include`'s
run-time twin, and it shares the namespace rule exactly: globals are one flat
namespace, the loaded file binds into it, and nothing marks a name as having
come from somewhere else. That sharing is the whole of the connection between
the two files, which is why the loader compiles on its own and only finds out at
run time that a name was never bound.

**A message, not a directive**, and every difference follows from that.

| | `@include "f.sol"` | `system:load("f.sob")` |
| --- | --- | --- |
| when | while compiling | while running |
| takes | source | bytecode |
| found | beside the including file, then the search path | relative to the working directory |
| repeats | compiled once however many ways you reach it | run once however many ways you reach it |
| name | must be a literal string | any expression answering a string |
| where | alone, as a statement | anywhere a message can be sent |

The path rule is the one that catches people. An `@include` is resolved while a
file is being read, so there is a file to be beside; a message has only the
process, and a process has a working directory.

Because it runs when it is reached, it can be sent conditionally, inside a
block, or from a file that was itself loaded. A file that loads itself is a
runaway and ends as any other does, with `call depth exceeded`.

**It runs the file once.** `@include` compiles a file once however many ways you
reach it, so two files may each include what they need without arranging between
themselves who includes what; this makes the same bargain. The memory is the
machine's and is keyed by identity rather than by spelling — the realpath, so
`lib.sob`, `./lib.sob` and the absolute name are one file.

Asking a second time is therefore not an error and not a second run. **The
answer says which happened**: true for a file that ran, false for one already
there, on the model of `makeDirectory`, which answers the same question about
the same kind of idempotence.

```text
system:load("lib.sob"):print.        ; true
system:load("lib.sob"):print.        ; false
```

It is also why a cycle ends. A file is written down before it runs, so one that
reaches itself — directly, or round through others — finds itself already listed
and does nothing. A file that could not be loaded at all is not written down,
so a machine that refused one is still willing to take it later.

The memory holds what `system:load` ran, and the program the machine was
*started* with did not arrive that way. So a program that loads itself runs its
top level twice: once because it was started, once because the load inside it is
the first time that file is asked for. The second one stops.

Nothing unloads a file, in the same way and for the same reason that nothing
unbinds a global.

A loaded file is debuggable like any other — see
[Solid](#stopping-a-program-solid).

A `.sob` is untrusted input and is verified before it runs, so a missing,
truncated or corrupt file is an ordinary failure the program can catch:

```
solvm: cannot load 'library.sob': not a Solum bytecode file
```

A failure inside the loaded file is an ordinary failure too. It unwinds through
the load, and the trace names both files — the line that failed and the line
that loaded it.

**The name is an expression**, which is the difference that outlives all the
others. `@include` needs a literal string: the file is found while the includer
is being compiled, so a name holding the file's name has no value yet. A message
takes whatever you hand it, so a program can load a file it worked out while
running — read from a configuration, taken from `system:arguments`, or found by
looking in a directory. [examples/plugins.sol](../examples/plugins.sol) does the
last of those, and names none of the files it runs.

Bytecode has to exist for this to find, which is the other thing including does
not ask of you: compiling the file that loads is not enough, and the file it
loads must be compiled too.

See [examples/load.sol](../examples/load.sol), and
[3.10](ROADMAP.md#310-a-vm-cannot-be-reused-across-runs) for the
namespace this shares and the cost of its being flat.

### The library

`lib/control.sol` ships with the language and is on the search path, so a
program asks for it by name:

```
@include "control.sol".

#3:repeat({ "tick":display }).               ; tick tick tick
lines := #0.
{ lines := lines:add(#1) }:doUntil({ lines:greaterOrEqual(#3) }).
lines:print.                                 ; #3
[#1,#10,#3]:loop({ n | n:display }).      ; 1 4 7 10
#4:timesCollect({ n | n:mul(n) }):print.     ; [#1, #4, #9, #16]
```

| Message | Answers |
| --- | --- |
| `#n:timesCollect(block)` | an array of `n` answers, the block given the pass number |
| `array:ifElseIf` | the first matching alternative's answer; see below |

**None of it is language.** These are methods bound on `integer`, `array` and
`block` by an ordinary Solum file, because control flow is message sending and a
loop — or a chain of alternatives — is therefore something a library can add.

`ifElseIf` is that chain, written flat instead of nested:

```
@include "control.sol".

c := "'".
[{ c:equals("#") },  { "integer" },
 { c:equals("\"") }, { "string" },
 { c:equals("'") },  { "symbol" },
                     { "something else" }]:ifElseIf:display.   ; symbol
[{ false }, { "no" }]:ifElseIf:print.                          ; nil
```

Pairs of blocks — a condition and what to do when it holds. The first condition
answering true wins and nothing after it runs. **An odd number of blocks means
the last is the else**; an even number with no match answers nil. Lisp calls
this `cond`.

**It costs what nesting does not, and the numbers decide where to use it.** A
nested `ifElse` written literally compiles to jumps; this makes a block call per
condition tested. Measured: 200,000 six-way dispatches take 0.145s as a chain
and 0.835s here, **5.8×**; and recursion *through* it costs three frames a level
rather than none, so a method reaching 254 levels as a chain reaches 84. So it
is for a flat dispatch — a scanner deciding what a character starts, a reader
deciding what a tag means — and not for the inside of a recursion.
[disasm.sol](../programs/disasm.sol) reads its constant tags with it.

**Four things were here once and are not any more.** `doUntil`, `repeat` and
the counted loop all started as Solum in this file, all were measured, and all
four turned out to be worth building into the VM — see
[integer](#integer) and [block](#block). Defining any of them here again would be
a trap rather than an override: a slot bound on `integer` shadows the primitive,
so the slow version would quietly win, and `doUntil` is spliced in by the
compiler anyway.

That leaves one function in the library, which is a fair record of what
measuring does. The machinery around it — the search path, `@include` finding a
name it was not told the location of — is unchanged and is the part that
matters.

A step of `#0` would never finish, so `loop` says so rather than hanging.

Written in Solum, they cost a block call per iteration — about 1.30× a literal
`whileTrue`, which compiles to jumps. See
[6.6](COMPLETED.md#66-the-loop-constructs-are-library-code-and-pay-for-it--done).

#### text.sol

What more than one program wanted for handling text:

```
@include "text.sol".

#233:asUtf8:display.                  ; é
"notes.md":endsWith(".md"):print.     ; true
"render-loud":startsWith("render-"):print.   ; true
```

| Message | Answers |
| --- | --- |
| `integer:asUtf8` | the bytes UTF-8 spells that code point with |
| `string:startsWith(prefix)` | a boolean |
| `string:endsWith(suffix)` | a boolean |

`asUtf8` is built on [`asCharacter`](#a-byte-and-its-number).

**`startsWith` is not `indexOf(x):equals(#1)`**, which is what three programs
wrote before this existed. `indexOf` *searches*, so a test that fails has read
the whole string, and failing is the case a prefix test is written for — on 128
KB of text without the needle in it that is the difference between 308 µs and
150 ns. `endsWith` is the same question at the other end, and asking it with
`indexOf` is a defect rather than a slowdown: `.md` is in `draft.md.orig`.

**An empty affix answers true**, both ways, and a prefix longer than the text
answers false rather than raising.

The file binds **no global** — a method on a built-in class needs no name of its
own, and the first draft, which bound an object called `text`, was shadowed by
the first program that had a variable of that name.

**A program that counts a class's slots must count before including this**, or
any library that adds to a built-in: `asUtf8` and `utf8Tail` land on `integer`,
and [expect.sol](../programs/expect.sol) reports that count as the language's.
It caught its own contamination the first time this file was included there.

#### math.sol

The comparisons a program keeps writing out by hand. It binds **no global**
either, for the same reason.

```
@include "math.sol".

#3:min(#7):print.               ; #3
2.5:max(1.5):print.             ; 2.5
#5:between(#1, #10):print.      ; true
[4.0, 1.0, 9.0]:min:print.      ; 1
["pear", "apple"]:max:print.    ; "pear"
```

| Message | Answers |
| --- | --- |
| `min(other)` `max(other)` | on `integer` and `float`: the smaller or larger of the two |
| `between(low, high)` | a boolean, **inclusive** at both ends |
| `array:min` `array:max` | the smallest or largest element; raises on an empty array |

The array pair names no type, so it works on anything that answers `lessThan` —
strings sort, so an array of them has a smallest.

**Every one of these was written out longhand somewhere first**, which is the
whole case for the file: `min` and `max` twice over in
[bench.sol](../programs/bench.sol), and `between` three times in
[json.sol](../lib/json.sol) as a surrogate range plus once more in `bench.sol`
as *does this interval contain 1*. They are ordinary Solum methods bound on
`integer`, `float` and `array`, and they cost a block call and a frame each —
the measured lesson `control.sol` records above. Nothing here is in a hot loop;
the moment something is, measure before promoting it.

`sqrt` is not here. It is a message on [float](#float), because it is the one
piece of this arithmetic a program cannot write for itself and get right.

#### Not here any more: the self-hosting libraries

`lexer.sol`, `parser.sol` and `compiler.sol` were on the search path while Solum
was being taught to compile itself. That is done — it compiles its own source and
reaches a fixpoint — and they now live in [experiment/](../experiment/), off the
search path, because keeping them in step with `solas` was a tax on every change
to the real compiler and the proof does not need repeating.
[experiment/README.md](../experiment/README.md) says what they are and how to run
the proof again.

**`sob.sol` went with them and came back**, and the split is the useful part.
The tax is that a second compiler has to be taught every construct the first one
learns, which is a cost the three above pay on every change to the *language*.
`sob.sol` writes the *file format*, which changes on a version bump — a
deliberate act, already held to `serialize.h` by the test suite — and not when
Solum gains a construct. Those are different rates, and they were conflated only
because all four files arrived on the same day.

#### sob.sol

Writing a `.sob` file, which is what a compiler does last.

```
@include "sob.sol".

system:writeFile("out.sob", sob:file(chunk)).
```

A chunk is a **dictionary**, because it is data being written out rather than
behaviour — `"names"`, `"constants"`, `"code"`, `"lines"`, `"files"`,
`"fileRuns"`, `"slotNames"`, `"methods"` and the frame's `"slots"`. The layout is
[serialize.h](../solum/include/solum/serialize.h) field for field, and
[disasm.sol](../programs/disasm.sol) is the same format read rather than written.

It binds one global, `sob`, which is the file extension and so is unlikely to be
a name a program wants for something else.

**The float encoder is the part that is real work.** Nothing reinterprets a
float's bits as an integer, so a double is taken apart by arithmetic — sign, the
exponent by halving and doubling into `[1, 2)`, then 52 bits of mantissa — and
reassembled as two 32-bit halves so nothing has to reach bit 63, which would
overflow on the way in exactly as it does when reading. Checked against the C
library at twelve values including `-0.0`, `DBL_MAX` and infinity, bit for bit.

Three files want it: [programs/sola.sol](../programs/sola.sol), which compiles
another language into a `.sob`, and `emit.sol` and `compile.sol` in
[experiment/](../experiment/), which are how it came to exist.

#### shell.sol

Running a command through `/bin/sh`, when the shell is the point.

```
@include "shell.sol".

shell:run("ls *.sol | wc -l").                  ; the status
shell:capture("git status --porcelain").        ; output and status
shell:read("date").                             ; the output, raising on failure
shell:line("git rev-parse --short HEAD").       ; the same, without the newline
```

**It gives up what `system:run` protects**, and says so: a command line is text
the shell parses, so a name that came from outside the program can be read as
syntax there. Build the command out of things you wrote; where any part of it
came from a file, an argument or a user, use `system:run` with an array and let
the strings stay strings.

`read` raises when the command fails where `capture` reports it — one asks, the
other insists — and `line` is `read` with the trailing newline taken off, which
is what a command's one-line answer wants.

#### json.sol

The second file on the search path, and a much larger one: a JSON reader and
writer, written in Solum.

```
@include "json.sol".

v := json:read("{\"server\": {\"port\": 8080}, \"tags\": [\"a\", \"b\"]}").
v:at("server"):at("port"):print.       ; #8080
v:asJson:display.                      ; {"server":{"port":8080},"tags":["a","b"]}
json:write(v):display.                 ; -- the same, indented over lines
```

| Message | Answers |
| --- | --- |
| `json:read(text)` | the value the text describes; raises on anything malformed |
| `json:write(value)` | indented JSON text |
| `value:asJson` | the same document with no spaces in it |

The mapping is the obvious one. A JSON object is a **dictionary**, an array is
an **array**, `null` is **nil**, and a number is an **integer** unless it is
written with a `.` or an exponent, in which case it is a float — going by the
spelling is what makes a document read and write back unchanged. `asJson` is
defined on `object`, so every type answers it; `nil` answers `"null"` through
that same definition, which matters because nil's class has no global for a
method to be bound on.

Names are written **sorted**, so the same document always produces the same
text and a rewritten file diffs cleanly.

`\uXXXX` is read in full, including surrogate pairs, and encoded as UTF-8 —
which is Solum arithmetic on top of `asCharacter` rather than anything the VM
knows about JSON. Raw UTF-8 in the text passes through unchanged, and the two
forms answer the same string:

```
json:read("\"caf\u00e9\"").          ; café
json:read("\"\ud83d\ude00\"").       ; 😀
```

Two things it will not do, each for a reason worth knowing:

- **Documents nest about 28 deep** before `call depth exceeded`, which is
  catchable like any other error. See
  [ROADMAP 3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels).
- **`null` and a missing name are both nil**, so `at(name, nil)` cannot separate
  them. Ask `includes(name)` when the difference matters.

[programs/manifest.sol](../programs/manifest.sol) is a program built on it —
describing a document, pulling a value out by a dotted path, editing it and
writing it back.

#### scan.sol

A cursor over text: a position, and the questions you ask at one. It is not a
pattern language — what repeated across the five files that each wrote one of
these was never a pattern, it was a position.

```
@include "scan.sol".

digit := { c | c:greaterOrEqual("0"):and({ c:lessOrEqual("9") }) }.
s := scan:on("8080ab").
s:takeWhile(digit):display.           ; 8080
s:rest:display.                       ; ab
```

| Message | Answers |
| --- | --- |
| `scan:on(text)` | a new cursor at the first character |
| `pos` | where it is, **one-based** — and assignable, which is how a scanner backtracks |
| `atEnd` | whether there is nothing left |
| `peek` | the character here, or **nil** at the end |
| `peekAt(#n)` | `#0` is `peek`, `#1` the one after; nil past either end |
| `looksLike(text)` | whether the text from here starts with it, **without moving** |
| `step` | **the cursor**, so it chains, one further on |
| `next` | the character passed, or nil at the end — where it stays put |
| `match(text)` | true and consumed if it was here; false and unmoved if not |
| `skipWhile(block)` | the cursor, moved past every character the block accepts |
| `takeWhile(block)` | the text it moved over |
| `takeUntil(block)` | the same, stopping where the block *accepts* — or at the end |
| `take(#n)` | the next `#n` characters, or fewer if the text runs out |
| `since(#start)` | everything between a remembered `pos` and here |
| `rest` | everything left, leaving the cursor at the end |

**The block is never handed nil.** Every hand-written version of this loop
opened `peek:notNil:and({ ... })`, which is the cursor's business: a predicate
here is a question about a character, and running out is not a character.

**`since` is what `takeWhile` cannot say.** One predicate describes a run of one
kind of character, which is most of them, and not a grammar in parts — JSON's
number is a sign, then digits, then perhaps a fraction and an exponent, and what
the caller wants at the end is all of it. `pos` is the mark; there is no `mark`
message because it would do nothing reading `pos` does not.

**Two cursors can be in flight at once.** `on` answers a new object rather than
resetting a shared one.

**`pos` is written as well as read**, because scanners backtrack: `html.sol`
reads `&notanentity;` as far as the `;` before deciding it is not an entity
after all, and puts the cursor back. Saving `pos` and restoring it is the whole
mechanism, and it is why there is no separate `mark`.

#### pattern.sol

Regular expressions, in the subset vi searches with. It needs `scan.sol`, which
it includes itself.

```
@include "pattern.sol".

p := pattern:on("^[a-z]*ing$").
p:find("everything"):print.           ; #1
p:find("thingy"):print.               ; nil
pattern:on("[0-9]"):find("port 80"):print.   ; #6
```

| Message | Answers |
| --- | --- |
| `pattern:on(text)` | a compiled pattern; **raises** on one it cannot read |
| `find(text)` | where the first match begins, **one-based**, or nil |
| `findFrom(text, #at)` | the same, starting at `#at` rather than at the beginning |
| `findLast(text, #before)` | where the last match beginning before `#before` is, or nil |
| `matches(text)` | whether there is a match anywhere — `find:notNil` |
| `endOfMatchAt(text, #at)` | where a match beginning at `#at` ends, or nil |
| `replaceIn(text, with)` | the text with the **first** match replaced |
| `replaceAllIn(text, with)` | the same, for every match |
| `countIn(text)` | how many non-overlapping matches there are |
| `substitutionIn(text, with, all)` | a dictionary of the new `"text"` and the `"count"` of changes, in one walk |

The language is seven things: a character matching itself, `.` for any one, `*`
for zero or more of the item before it, `[abc]` `[a-z]` `[^abc]` for a class,
`^` and `$` for the ends, and `\` to escape any of them. `^` and `$` are
ordinary characters anywhere but the ends of the pattern, and a `*` with nothing
before it is ordinary too — which is vi's rule, and is what lets a price or a
shell variable be searched for unescaped.

**What is not here**: groups, alternation, `+`, `?`, captures, counted
repetition. Those want a backtracker over a tree rather than over a list, and
nothing has wanted one.

**`&` in a replacement is what was matched**, which is sed's rule and vi's;
`\&` is an ampersand and `\\` is a backslash. A replacement ending in a
backslash is refused the way a pattern ending in one is — it is always a typing
mistake.

```
@include "pattern.sol".

pattern:on("an"):replaceAllIn("banana", "[&]"):display.   ; b[an][an]a
pattern:on("x*"):replaceAllIn("abc", "-"):display.        ; -a-b-c-
```

**A match that consumed nothing gets out of its own way.** `x*` matches the
empty string at every position, and a replace that searched again from where it
started would never finish — so a zero-width match carries the character it
stood on across and moves one further. That is what `sed` answers, and it is the
only answer that terminates.

**`countIn` exists because a substitution has to report a number** and cannot
get it by comparing the text with itself: replacing `a` with `a` changes nothing
and is still a substitution. **`substitutionIn` answers both in one walk**, the
way `capture` answers `"output"` and `"status"` — counting the matches and then
replacing them walks every line twice, which over fifty thousand lines is
seconds rather than milliseconds.

**A pattern that begins with a plain literal searches by `indexOf`.** Every
match must start with that character, so the search asks a primitive where the
next candidate is instead of trying `matchFrom` at every position — 2.45s to
1.08s over fifty thousand lines for `alpha`, and 2.20s to 0.27s for `zeta`, the
difference between those two being how often the first character turns up as a
candidate that still has to be checked. A pattern beginning with `.`, a class or
anything starred has no such character and searches as it always did. A pattern
also knows the shortest match it can make, and stops looking when fewer
characters than that are left.

**The pattern is compiled once**, because the caller is usually a search — the
same pattern against a hundred thousand lines, and re-reading `[a-z]` at every
one of them is the work worth not doing.

**It recurses once per `*` and nowhere else**, which is what makes it fit inside
[3.5](ROADMAP.md#35-recursion-is-limited-to-about-254-levels). 250 stars in one
pattern work and 251 answers `call depth exceeded`; the length of the pattern
and the length of the text cost no depth at all, so a 2,001-character line is
searched at a depth of two. The textbook shape — a star that recurses over the
*text* — would have spent a frame per character of the line, and a line is
longer than a pattern by a factor nobody controls.

**`find` and `findFrom` are two names for one idea**, because a block has one
parameter list and a slot holds one block: a library written in Solum cannot
answer one message at two arities the way `at(key)` and `at(key, default)` do.
Primitives can; Solum cannot, and two names are the honest way round it.

[programs/edit.sol](../programs/edit.sol) is the program built on it: `/`, `?`,
`n` and `N` are this library plus a walk over the buffer's lines, which is why
`^` and `$` mean the ends of a *line* there without anybody having decided so.

#### html.sol

Reads HTML into a tree of elements. It needs `text.sol`, which it includes
itself.

```
@include "html.sol".

page := html:read("<ul><li>one<li>two</ul>").
page:findAll("li"):size:print.        ; #2
page:find("li"):text:display.         ; one
```

| Message | Answers |
| --- | --- |
| `html:read(text)` | the document element; **never raises** |
| `html:complaints` | an array of strings, from the last `read` |
| `element:name` | the tag name, lowercased |
| `element:text` | all the text under it, tags removed |
| `element:attribute(name)` | the value, or **nil** when absent |
| `element:attributes` | a dictionary, names lowercased |
| `element:children` | an array of elements **and strings** |
| `element:parent` | the element above, or nil at the top |
| `element:find(name)` | the first descendant with that name, or nil |
| `element:findAll(name)` | every one, in document order |
| `element:selectNodes(block)` | every descendant the block accepts |

**It does not fail.** Every other parser here stops at the first problem, which
is right when the input is written by somebody who can fix it. HTML is
generated, served, and wrong, so this one recovers — implied end tags, stray end
tags, unclosed elements, unquoted attributes, a bare `<` in text, and a `<`
inside a `<script>` are all handled — and records what it recovered from:

```
page := html:read("<b>bold</i>").
page:text:display.                              ; bold
html:complaints:do({ c | c:display }).
; </i> at character 10 closes nothing that is open
; <b> opened at character 1 is never closed
```

Text is not wrapped in a node: a child is either an element or a plain string,
so a walk asks `isKindOf(string)`. An element points back at its `parent`, so
the tree has cycles in it — which is safe because the collector traces from the
roots rather than counting references.

**Nesting is not limited.** The reader builds against a stack of open elements
rather than by recursion, and `text`, `find`, `findAll` and `selectNodes` walk
with one too, so [the frame limit](ROADMAP.md#35-recursion-is-limited-to-about-254-levels)
that stops a recursive-descent parser at 124 levels does not apply. Measured at
50,000 levels, built and walked.

[programs/page.sol](../programs/page.sol) is a program on it — an outline, a
link list, images without alt text, and the complaints.

**A file is compiled once** per compilation, however many ways it is reached,
keyed by where it turns out to be on disk so that two spellings of one file are
one file. C compiles it every time and leaves each file to guard itself, which
needs conditional compilation that Solum has not got; and a second copy could
only rebind names already bound and repeat whatever the file did on the way. So
two files may each include what they need without arranging between themselves
who includes what — and a cycle ends instead of recurring.

**Errors name the file**, and the chain that reached it:

```
[lib/broken.sol:2:6] solas: expected an expression at ':'
  y := :.
       ^
  ... included from lib/middle.sol, line 1
  ... included from prog.sol, line 3
```

Includes may nest 64 deep.

Two things this is not. There is no module system: an included file gets no
namespace of its own, so **two files binding one name do not collide — the later
one wins**, and the compiler warns rather than letting it pass:

```
[prog.sol:3:1] solas: warning: 'text' was already bound by lib/text.sol -- this one wins, and nothing else will say so
  text := v.
  ^^^^
```

A warning, not an error: rebinding is legal and sometimes meant. Only a *claim*
warns — `count := count:add(#1)` reads the name before writing it, so it is
updating somebody else's global rather than claiming its own, which files
legitimately do across an include.

If you want a namespace, the tiers are: **behaviour on an existing type is a
method on the class and claims no name at all** — `lib/control.sol` and
`lib/text.sol` do that; a thing with state binds **one** object and hangs the
rest off it, which `json` and `html` do and
[examples/library.sol](../examples/library.sol) shows. A `.sob` file is still
**one chunk** — an included file's code is compiled into the same one — but it
records which file each stretch of code came from, so a stack trace names both:

```
solvm: index #99 is out of bounds for a string of size 4
  [lib/parse.sol:4] in block
  [main.sol:3] in script
```

Without that a line number named a line in a file nobody had said, and read as a
line of the file being looked at.

---

## The program and its process

`system` is a global holding one object. It is not a class and has no
instances — there is one process, and this is where what belongs to it lives
rather than to any value. Its messages are in
[the reference below](#system).

```
system:arguments:do({ a | a:display }).
system:exit(#0).
```

### Stopping

`system:exit(status)` stops the program and hands `status` back to whatever ran
it. It **unwinds** rather than leaving from under the machine: every frame is
discarded the way an error discards them, and control returns through `main`, so
everything already written is flushed on the way out. Nothing after the `exit`
runs, including the rest of a loop it was called inside:

```
[#1, #2, #3]:do({ n | n:print. n:equals(#2):ifTrue({ system:exit(#3) }) }).
```
```
#1
#2
```

A status is an integer from **#0 to #255**, and anything else is an error rather
than a value quietly adjusted to fit — POSIX keeps only the low eight bits, so
`system:exit(#256)` would otherwise leave with 0 and look like success.

At the prompt it does the same thing: Solis runs the same machine, so
`system:exit(#4)` leaves Solis with status 4.

### Arguments

`system:arguments` answers an array of strings: everything on the command line
after the `.sob` file, in order, and neither solvm's name nor the file's is among
them. With none given it is the **empty array** rather than nil, so it can be
walked without first asking whether it is there.

It is a data slot rather than a method, because it is data — the same array every
time, not a fresh one:

```
system:arguments:equals(system:arguments):print.     ; true
```

Being an ordinary array, a program can add to it or sort it. That changes the
program's copy and nothing else.

### Reading input

`system:write` is the other half of the terminal. `display` and `print` end the
line, which is right for output and wrong for a question — a prompt and the
answer typed after it belong on one line. It takes a **string** and not any
value, so there is no second rule about how things become text; `#42:asString`
says which form it wants.

It writes to the same stream `display` does, so the two interleave in the order
they were written — including when the output is a pipe or a file. Anything that
opened its own stream on the same output would not: the two buffer differently
away from a terminal, and the unbuffered one arrives first
([3.18](COMPLETED.md#318-a-program-cannot-write-without-ending-the-line--done) records
what that looked like).

```
system:write("how many? ").
"none":display.                  ; how many? none
```

`system:writeError` is the other stream, and the only way to reach it: a
diagnostic says something went wrong *producing* the output and is not part of
it, so a reader redirecting one should still see the other. There is no variant
of `display` or `print` that goes there, and there should not be — those are
about rendering a value and serve every type, and a second one pointing
elsewhere is the second mechanism behind the first that this language refuses.

`system:readLine` answers one line from standard input **without its
terminator**, or **nil** when there is no more. A **NUL** in the input is a byte
like any other and stays in the line, the same way `readFile` keeps one.

```
line := system:readLine.
{ line:notNil }:whileTrue({
    line:display.
    line := system:readLine
}).
```

Nil is the end and `""` is an empty line, so the two are never confused. A last
line carrying no newline of its own still counts as a line, and `\r\n` is one
terminator, so a file written on another system reads the same as one written
here.

Nil rather than an error is the one place absence is not treated as a mistake:
running out of input is how a loop that reads to the end finishes, not something
that went wrong.

At the prompt it reads the next line you type, which Solis then does not see —
the program and the prompt are reading the same input.

Waiting for a single keypress is a different job. It needs raw terminal mode,
which is the first thing in the runtime that would differ by platform, and it is
not here.

#### One key at a time

`system:readKey` answers **one byte** as a one-character string, or **nil** at
the end of input, and does not wait for return:

```text
key := system:readKey.
key:asByte:print.        ; #97 for "a", pressed on its own
```

That is what anything interactive needs — a menu, a pager, a prompt that redraws
as you type. `readLine` waits for a line; this does not.

**A byte, not a key.** An arrow is three bytes and a function key can be more,
and which is which belongs to the terminal rather than to the language. A
program that wants arrows assembles them:

```
escape := #27:asCharacter.
key:equals(escape):ifTrue({
    system:readKey.                       ; the "["
    ["up", "down", "right", "left"]:at("ABCD":indexOf(system:readKey)) }).
```

[examples/keys.sol](../examples/keys.sol) does that. A byte-level reader on its
own **cannot tell the escape key from the start of a sequence** — telling them
apart needs a read that gives up after a few milliseconds, which is the next
message.

#### Whether a key is coming

`system:keyWaiting(seconds)` answers **true or false**: is there a byte to read,
waiting up to that long for one to arrive.

```
escape := #27:asCharacter.
key:equals(escape):and({ system:keyWaiting(0.05) }):ifTrue({
    system:readKey.                       ; the "["
    ["up", "down", "right", "left"]:at("ABCD":indexOf(system:readKey)) }).
```

**The escape key is why it exists.** An arrow arrives as three bytes and the
escape key as one, and `readKey` blocks until a byte is there — so a program
that has just read an escape cannot tell a sequence from a keypress without
reading on, and reading on is exactly what it must not do if nothing is coming.
Nothing follows an escape within fifty milliseconds except a machine.

**A question rather than a second reader.** `readKey(seconds)` answering the
byte or nil was the other shape, and **nil already means the end of input** —
which is how every read loop here finishes. Overloading it with *nothing yet*
would leave a program unable to tell *there is nobody there* from *they have not
typed yet*, where the first is final and the second is normal.

**True at the end of input**, where the `readKey` after it answers nil: there is
something to read, and what is there is the end. `0.0` asks about right now and
waits for nothing. Seconds are a **float**, like every other duration here, and
a negative one is refused rather than taken for *wait for ever*.

**On a terminal it looks past the line discipline.** A terminal in its ordinary
mode holds what is typed until a newline, so a program that asked this between
two `readKey`s would be told nothing had been typed however much had — and the
arrow keys it exists to recognise would stop working, their `[` and `B` sitting
in the driver's buffer. It sets the same non-canonical mode `readKey` does for
the length of the question, and puts it back.

**It knows nothing about `readLine`'s buffer**, which is the limitation
`readKey` has and for the same reason — see below.

#### Spending time rather than measuring it

`system:sleep(seconds)` waits, and answers nil.

```
system:sleep(0.25).
```

Seconds are a **float**, like every other duration here; a negative wait and
`nan` are refused, because there is no length of time either could mean, and
`0.0` returns at once. Interrupted by a signal it sleeps out the remainder,
since a caller that asked for a second wants a second and has no way to learn it
was cut short.

**It is not `keyWaiting`**, and the difference is the stream. `keyWaiting` waits
on *standard input* and answers **true at the end of it** — so a program that
used it to pace itself would spin the moment standard input was a closed pipe,
which is how most programs are run. Twenty asks of `keyWaiting(0.5)` take 10.02 s
against an idle terminal and 56 microseconds against a finished one; twenty
`sleep(0.5)`s take ten seconds wherever they are run.

[tail.sol](../programs/tail.sol) asked for it, following a growing file:
`fileSize` notices the growth and a [ranged read](#a-range-of-a-file) collects
what is new, and waiting was the whole of what was missing.

#### One window over standard input

`readLine`, `readKey` and `keyWaiting` **all take from one window**, so a program
may use whichever suits each moment and lose nothing between them:

```text
printf 'one\nXY\n' | solvm program.sob     # readLine → "one";  readKey → "X"
```

That is worth saying because it was not always true and the failure was silent.
`readLine` used to read through the C library, which reads a **block** ahead;
`readKey` read the descriptor underneath it; and everything that arrived in the
same block as the line was held where nothing else could reach it —
[6.36](COMPLETED.md#636-readline-and-readkey-did-not-share-an-input-buffer--done).

**Solis reads through the same window**, which is what makes *the program and
the prompt are reading the same input* exact rather than nearly so: a script run
at the prompt asking for a key gets the key you typed, not the one after
whatever the prompt read ahead.

**A byte already in the window is not read again**, so `keyWaiting` answers true
for one without asking the system anything, and `readKey` takes it without
touching the terminal's mode.

**What reads ahead still reads ahead**: up to four kilobytes at a time from a
pipe or a file, which matters only if another *process* is waiting on the same
input. A program that reads a line and then hands standard input to a child with
`run` may find the child short of what the window is holding. A terminal is
unaffected — it delivers a line at a time, so nothing is taken that was not
asked for.

**No echo**, because raw mode does not; a program that wants the key shown
prints it. **Raw mode only on a terminal** — through a pipe or a file a byte is
already a byte, so this reads the same way under `solvm program.sob < input`,
which is also what makes it testable. `ctrl-c` still interrupts a program
waiting for a key.

#### Whether a stream is a terminal

`system:isTerminal(which)` answers whether one of the three standard streams is
a terminal. `which` is `'input`, `'output` or `'error`:

```
system:isTerminal('input):ifElse({ "a person is typing" },
                                 { "something is piping" }):display.
```

**Three symbols rather than three messages**, because the stream is the thing
that varies and the question is one question. `'input` rather than `'stdin`
follows `readLine`, `write` and `writeError`, which spell them out; `run`'s
options array is the one place the C names appear, and there they are keys a
child process cares about. A symbol that is none of the three is an error rather
than a false — there is no stream it could be answering about.

**What it is for** is a program whose no-argument case means two things.
[tail.sol](../programs/tail.sol) and
[sha256sum.sol](../programs/sha256sum.sol) both demonstrate themselves when run
with nothing, and both are also real invocations at the end of a pipe, which is
the same empty command line meaning the opposite thing. `'output` is the other
common ask: whether to colour, or draw a progress line, or write a `\r` at all.

**It is not `keyWaiting(0.0):not`**, which is what both programs used before it
existed and which is wrong in a way worth knowing about. `keyWaiting` answers
*is there a byte right now*: an idle terminal says false, and so does **a pipe
that is open, empty and not yet finished**. So `{ sleep 1; echo hi; } | prog`
took the terminal branch. See
[6.40](COMPLETED.md#640-a-program-cannot-ask-whether-a-stream-is-a-terminal--done).

#### How big the screen is

`system:terminalSize` answers a dictionary of `"rows"` and `"columns"`, or
**nil** when the output is not a terminal:

```
size := system:terminalSize.
size:isNil:ifElse({ "no screen" }, {
    "{} by {}":fill([size:at("rows"), size:at("columns")]) }):display.
```

It is the third thing a full-screen program needs, after `readKey` and `write`,
and [programs/edit.sol](../programs/edit.sol) is the program that asked for it:
an editor cannot draw a screen it cannot measure.

**One message for both numbers**, rather than `rows` and `columns` separately.
Two asks can straddle a resize and give a screen that never existed — an old
width with a new height — and one ask cannot.

**Nil rather than 24 by 80** when there is no terminal, which is the same answer
`readLine` and `environment` give for absence. A default would be a lie a
program cannot see through, and what to do instead belongs to the program: an
editor picks a size, a pager gives up, a report ignores the question. `tput
lines` is the counter-example — down a pipe it answers the terminfo default,
confidently and wrongly.

**The output's size**, because that is where the drawing goes. A program whose
input is a script and whose output is a terminal still gets an answer, which is
what makes a full-screen program testable at all; one whose output is a file
gets nil, which is the truth about the file.

**There is no notification that it changed.** Asking costs one system call —
about a microsecond, against 7ms for `stty size` through a shell, which is what
a program had to do before this existed — so a program that draws can ask every
time it draws, and then a resize needs no telling. That is the whole reason this
is a message and not a signal.

### Files

Whole files, as strings.

```
system:writeFile("notes.txt", "apples 3\npears 12\n").
system:readFile("notes.txt"):size:print.         ; #18
```

`readFile` answers the whole file as one string. `writeFile` replaces what is
there, creates the file if it is not, and answers nil — there is nothing useful
to chain from a write.

#### A range of a file

`readFile(path, from, count)` answers `count` bytes starting at `from`, which is
a **one-based byte position** like every other index in this language:

```
system:writeFile("notes.txt", "apples 3\npears 12\n").
system:readFile("notes.txt", #1, #6):print.      ; "apples"
system:readFile("notes.txt", #10, #5):print.     ; "pears"
```

**It is a range and not a handle**, and that is the whole design: there is
nothing to open, nothing to close, nothing to leak and no question about what a
handle used after closing should do. A position is an argument, so two parts of
a program can read two parts of a file without agreeing about anything.

**A short range is the answer, not a failure.** Asking for more bytes than are
left answers what was there, and asking from past the end answers `""` — because
*the last four kilobytes* of a file that turns out to be one kilobyte is a
reasonable question, and the string that comes back says its own size:

```
system:readFile("notes.txt", #10, #999):size:print.   ; #9
system:readFile("notes.txt", #99, #10):print.         ; ""
```

That is the one place the two forms part. A whole-file read that comes up short
is a **failure**, since its length came from the file a moment earlier and
anything less means a fault. A range coming up short is the end of the file.

**`#0` is not a position** and is refused, as it is on a string, and so is a
negative count. Past the end is a position; before the start is not.

**With [`fileSize`](#changing-what-is-there), this is how a program works on a file
it could never hold:**

```
size := system:fileSize("huge.log").
system:readFile("huge.log", size:sub(#4095), #4096).   ; the last 4 KB
```

A 3 GB file answers that in 7 ms with under 2 MB resident — reading it whole is
refused, and does not have to be attempted.

**What a call costs, which matters when a program makes many of them.** Having
no handle means no file is held open, so every call opens the file again: a read
costs **about 30 microseconds whatever its size** — one byte and sixty-four
kilobytes measure the same, because the cost is the open and not the bytes.
`fileSize`, `fileExists` and `modifiedAt` cost **0.65 microseconds** beside it,
having only to `stat`.

So a program reading a file in pieces is choosing how often to pay that. Hashing
a megabyte 64 bytes at a time is 62% slower than doing it 64 kilobytes at a
time, and the difference is flat from about four kilobytes upward. A poll loop
should ask `fileSize` and read only when the answer changed, which is what
[tail.sol](../programs/tail.sol) does and why following an idle file costs no
measurable CPU.

It is the machine's price rather than this language's: plain C doing the same
`fopen`, `fread` and `fclose` measures 28 microseconds on the same machine.

#### Reading it whole, and what that costs

**Two gigabytes is the hard limit** for the whole-file form, a string's length
being a signed 32-bit count, and it is refused rather than truncated:

```text
system:readFile("huge.dat").
solvm: 'huge.dat' is too large to read into a string
```

The size is checked before anything is allocated, so that answer is immediate
whatever the file's size. **A range has no such limit on the file** — only on
the `count`, which is one string's worth.

**And the peak cost is twice the file**, because the bytes are read into a
buffer and then copied into the string, which is what makes the string
immutable. A 256 MB file peaks at 514 MB resident and takes 0.17 s here. A
*copy* costs the same and not more — `writeFile` streams from the string it was
handed — so `readFile` is the whole of the expense either way.

**A program that works line by line pays more than twice**, because it splits
what it read and then holds a string per line. Measured with
[sed.sol](../programs/sed.sol), which does the same work by both routes: about
4.7 times the file by name, against a flat 2.5 MB through a pipe. Whole-file is
right when the program wants the whole file — the editor loads a file to edit
it, `solas` loads a source to compile it — and a range is what the others want.

`system:fileSize` answers without reading, which is how to ask before committing
to either.

**A missing file is an error to `readFile`, not nil**, which is the same answer
an out-of-range index gets and for the same reason: a program asking to *read* a
file it has not got is wrong about something. `readLine` answering nil at the end
of input is not the precedent, since running out of input is how a loop
*finishes*.

**Asking about a path is a different question from reading it**, and the five
messages that ask now agree. `fileExists` and `isDirectory` answer false for a
path that is not there; `fileSize`, `modifiedAt` and `fileId` answer **nil**.
All five go on raising for a path that cannot be looked at — a permission that
stops the question being asked is not an answer to it.

That last part is not a nicety. `fileSize` used to raise for both, and `tail -f`
polls it once per file per interval, so a log rotation ended the program with
*cannot measure* and status 1 where the tool on the machine waits and picks up
the replacement.
[6.41](COMPLETED.md#641-a-path-that-stops-existing-is-an-error-rather-than-an-answer--done).

`system:fileExists(path)` is how to ask whether a read would work, and it is
about a **file**: a directory answers false, because that is what `readFile`
would say about one too.

#### Which file is at this path

`system:fileId(path)` answers the device and inode as a string —
`"16777234:231399178"` — and **only `equals` is promised of it**. It is what
lets a program tell a *rotation* from a *write*, which nothing else here can:
a log and the log that replaced it can agree on size and on time, and until
this existed [tail.sol](../programs/tail.sol) lost a line to exactly that,
silently. [6.39](COMPLETED.md#639-a-program-cannot-tell-whether-two-paths-are-the-same-file--done).

```
before := system:fileId("app.log").
; ... a rotation happens ...
before:equals(system:fileId("app.log")).   ; false -- a different file now
```

A string because the pair does not fit an integer: `dev_t` here is a signed
four-byte integer and `ino_t` an unsigned eight, and on Linux both are unsigned
eight. The format is readable rather than opaque so that an id means something
in a trace, and the sign of the device number is the platform's — `/dev/null`
has a negative one here. Two ids are only ever compared with each other.

**A hard link is the same file** and answers the same id; a **rename** carries
the id with it, since the identity is the file's and not the path's; `stat` is
followed through a symbolic link, agreeing with `fileSize` and `modifiedAt`.
And an inode can be **reused** after a delete, so two ids equal across a long
gap is not quite proof — the question this answers is *has the file under this
path been replaced since a moment ago*, and reuse does not reach that.

`system:modifiedAt` carries the **sub-second** part of the time, which matters
for the job it exists for: a script asking *is the source newer than the copy?*
gets the wrong answer from whole seconds for anything changed within a second of
the last run.

**A copy carries neither the mode nor the time on its own** — `readFile` and
`writeFile` move bytes and nothing else — so `setMode` and `setModifiedAt` are
how a copy is made to match its original:

```
system:writeFile(to, system:readFile(from)).
system:setMode(to, system:modeOf(from)).
system:setModifiedAt(to, system:modifiedAt(from)).
```

The mode before the time, since writing sets the time and would undo it.

A **mode is an integer**, because that is what a mode is. There is no octal
literal, but there is a binary one, and permissions are three triples of bits —
so `%111101101` is what `0755` looks like written down, with the triples where
you can see them. `asBase` and `asInteger` cross to the text people recognise:

```
system:modeOf(path):asBase(#8).      ; "755"
"755":asInteger(#8).                 ; #493
```

And `%111101101` is `#493` written so the triples show:

```
%111101101:asBase(#8):display.       ; 755
```

The file-type bits are masked off, so what comes back is permissions alone and
`setMode(to, modeOf(from))` cannot try to change what a thing *is*. A mode
outside `#0` to `#4095` is refused rather than partly applied.

`system:makeDirectory` makes **one level** and answers whether it made one:
**true** if it did, **false** if a directory was already there. So "make sure
this exists" is the one message, and a caller who wants to know which it was
still finds out.

```
system:makeDirectory("build/out").      ; true  -- made it
system:makeDirectory("build/out").      ; false -- already there
```

Anything else is an error: no permission, no parent, or **something that is not
a directory** already at that name. That last one matters — `mkdir` reports it
the same way as "already there", and the two are not the same news, since one is
fine and the other never will be.

A string is bytes, so a file of them survives the round trip — a NUL is a byte
like any other, `size` counts it, and reading a file and writing it back copies
it exactly. `split`, `indexOf` and `copyFrom` work on it too, all three going by
the length rather than stopping at the first NUL, and `asByte` gives the number
of one so there is something to do arithmetic on. `readLine` keeps a NUL as
well, so a line and a file agree about what a string may hold.

**That is about a file's contents, and the opposite is true of its *path*.** A
path goes to the operating system as a C string, so every message on this page
stops at the first NUL in the name it is given: `system:fileExists`,
`readFile`, `fileSize` and the rest all read `"notes.txt\0zzz"` as
`"notes.txt"` and answer about that file, without complaining. A Unix filename
cannot contain a NUL, so no name is lost — but a string built by a program can,
and the message answers about a different path rather than refusing. Stated here
because the paragraph above invites exactly the wrong conclusion; whether it
should refuse instead is
[in ideas.md](ideas.md#a-path-with-a-nul-in-it-is-silently-a-different-path).

These are on `system` rather than on the string naming the file, though
`"notes.txt":readFile` reads well. A string knows nothing about files, and
`system` is already where what belongs to the world outside the program lives.

#### Directories

Reading a file needs its path. `filesIn` is how a program finds one out:

```
system:filesIn("examples"):sorted:first(#3).   ; ["arrays.sob", "arrays.sol", "binding.sol"]
system:isDirectory("examples").                ; true
```

**Names, not paths.** A path would have to choose a separator and would make
the answer awkward to show; joining is the caller's, and one `concat` wide.

**Everything but `.` and `..`**, directories included — leaving subdirectories
out would make a recursive walk impossible, and `isDirectory` is what tells them
apart. `fileExists` and `isDirectory` deliberately disagree about a directory:
`fileExists` answers what `readFile` would say.

**In the order the directory gives them**, which is to say none worth relying
on. The same rule `dictionary:keys` follows, and `sorted` is one message away.

A path that is not a directory is an error, as a missing file is to `readFile`.

#### Changing what is there

`remove`, `makeDirectory` and `rename` do something that cannot be undone.
Nothing asks twice or keeps a copy.

```
system:isDirectory(p):ifFalse({ system:makeDirectory(p) }).
system:rename(old, new).
system:remove(old).
```

**`remove` takes a file or an empty directory**, both, because that is the
distinction a script does not want to make — it knows what it is taking away. A
directory with anything in it is refused, and there is deliberately **no
recursive form**: deleting a tree is not something to make one message wide. A
program that means it can walk with `filesIn` and remove what it finds, which at
least reads like what it does.

**`makeDirectory` makes one directory**, not a path of them. `mkdir -p` is what
a script usually wants and does more than its name says: asked for `a/b/c` it
may leave `a` and `a/b` behind having failed at `c`. Making each level in turn
is a loop a program can write and a reader can follow. A directory already there
is an error, which makes the two-message form above the way to say "make sure of
it" — longer, and it says which of the two you meant.

**`rename` replaces an existing destination** without asking, as the system call
does and as every `mv` does. It cannot cross a filesystem: there the answer is
read, write, remove, which is three operations because it *is* three
operations, and the error says so rather than pretending otherwise.

Every refusal names the reason the system gave, so a script can tell a missing
file from a directory that still has something in it:

```
system:makeDirectory("build").
system:writeFile("build/kept.txt", "something").
system:remove("build").
solvm: cannot remove 'build': Directory not empty
```

`fileSize` answers what `readFile(path):size` would, without reading the file —
which is the only way to ask about a large one, and the half that
[a range](#a-range-of-a-file) composes with. It is size and not the
modification time, the other thing the system knows: a timestamp wants to be a
**date** rather than a number of seconds, and there is no date type here yet.

`appendFile` is `writeFile`'s other half — it adds to the end rather than
replacing, and creates the file when it is not there. `environment(name)`
answers a variable or **nil** when it is not set, nil rather than an error
because a variable nobody set is a legitimate answer to a legitimate question.

There was a third reason once: include was spelled `"lib.sol":include` then, and
`"lib.sol":readFile` beside it would have been two identical-looking sends that
were nothing alike. That collision is gone — an include is `@include "lib.sol"`
now and looks like nothing else — but the first two reasons were the load-bearing
ones and they still hold.

### Running another program

`system:run` takes the program and its arguments as an **array**, and answers
the exit status. The child shares this program's output, so what it writes
appears as it runs.

```
system:run(["ls", "-l", path]).            ; #0, or whatever it answered
system:capture(["git", "rev-parse", "HEAD"]).
```

`system:capture` keeps what the command wrote instead, answering a **dictionary**
of `"output"` and `"status"` — because a command's output is worth little
without knowing whether it worked, and `grep` finding nothing is not `grep`
failing.

**An array rather than a command line**, and that is the design rather than a
detail. An array is a list of arguments and nothing in it is ever read as
syntax:

```
system:run(["rm", name]).       ; one argument, whatever `name` holds
```

A file called `; rm -rf ~` is a *name* there, because it is one string. Handed to
a shell as text, the same name is a sentence. So anything that came from
outside the program — an argument, a directory listing, a line of input — goes
in the array and stays a string.

**The shell is reachable and spelled out**, which is how it should look:

```
system:run(["/bin/sh", "-c", "ls *.sol | wc -l"]).
```

[lib/shell.sol](../lib/shell.sol) wraps that for programs where pipes and globs
are the point, so the convenience is a line away and the hazard is named where
it is taken.

**A command that is not there answers `#127`**, which is what a shell answers,
rather than raising: a script asking whether a tool is installed is asking a
question. A command killed by a signal answers 128 plus the signal, the same
convention. Neither is an error, so both are the caller's to notice.

Output arrives as bytes, padding and all — `wc -l` answers `"     100\n"` — and
[`trim`](#string) is what stands between that and `asInteger`.

#### Where the child's streams go

Both take an optional second argument saying what the child's `stdin`, `stdout`
and `stderr` should be. It is an **array of alternating name and value** — the
options bag this language can spell, since there is an array literal and no
dictionary literal.

```
noisy := ["/bin/sh", "-c", "echo out; echo err 1>&2"].

system:capture(noisy, ["stderr", 'discard]):at("output"):print.   ; "out\n"
system:capture(noisy, ["stderr", 'merge]):at("output"):print.     ; "out\nerr\n"
```

The names are the same strings `capture` answers with. A value is either a
**manner, as a symbol**, or a **path, as a string** — and the type is what tells
them apart, which is what keeps a file called `discard` a file.

| Value | Means |
| --- | --- |
| `'share` | the child gets ours, which is what happens when nothing is said |
| `'discard` | `/dev/null` |
| `'merge` | **`"stderr"` only** — wherever stdout ended up |
| `"a/path"` | the file, truncated for a stream going out, read for `"stdin"` |

```
system:run(["/bin/sh", "-c", "echo out; echo err 1>&2"],
           ["stdout", "log.txt", "stderr", 'merge]).
system:readFile("log.txt"):print.                    ; "out\nerr\n"
system:remove("log.txt").

system:writeFile("in.txt", "fed in").
system:capture(["cat"], ["stdin", "in.txt"]):at("output"):print.  ; "fed in"
system:remove("in.txt").
```

**`'merge` follows stdout to where it is now**, not to where it was. That is
`>file 2>&1` and not `2>&1 >file`, which are the two orders a shell distinguishes
and the classic way to get this wrong. For `capture` it means stderr lands in the
answer, because the pipe is where stdout already is.

**`capture` refuses `"stdout"`**, whatever the value, since keeping stdout is
what the message is for; `run` is the one that can send it elsewhere. A stream
named twice is refused too, and so is a path that cannot be opened — the files
are opened **before** the fork, so a bad path is this program's error to report
rather than a child that silently did nothing.

Anything not said is inherited, so `system:run(argv)` is exactly what it always
was.

### The clock

`system:clock` answers **monotonic seconds as a float**. The epoch is
deliberately unspecified: the only useful thing to do with two readings is
subtract them, and a wall clock can go backwards in between.

```
start := system:clock.
i := #0. { i:lessThan(#100000) }:whileTrue({ i := i:add(#1) }).
system:clock:sub(start):asString("0.4"):display.     ; -- 0.0147, or thereabouts -- whatever it took
```

`{ ... }:timeToRun` does the same without the bookkeeping, answering the seconds
the block took. The block's own answer is dropped — what was asked for was the
time, and `{ ... }:value` is there when the answer is wanted too.

**The clock has a floor**, and it decides how this message is used. On the
machine this was written on it is a microsecond, by `clock_getres` and by
watching the smallest step between two readings. One send and one add costs
well under a tenth of that, so a single run answers the floor rather than the
block — `0` most times, one whole microsecond when the two readings happen to
fall either side of a tick:

```
{ #1:add(#1) }:timeToRun:print.        ; -- 0, or 0.000001: the floor
```

`timeToRun(#n)` runs the block `n` times and answers the **total**, which is how
anything smaller than a microsecond gets measured:

```
total := { #1:add(#1) }:timeToRun(#200000).
total:div(200000.0):asString(".9"):display.      ; -- 0.000000088, thereabouts -- or thereabouts
```

The total rather than the average, because the total is the measurement and the
average is a division you can do — and keeping the count in view is what tells
you whether the floor was cleared. A count below `#1` is an error.

What is measured includes the cost of calling the block, a frame pushed and
popped. That is not overhead to subtract; it is what running the block costs.

---

## Lexical structure

### Comments

`;` begins a comment, which runs to the end of the line.

```
a := #45.        ; this is a comment
```

### Statements

`.` separates statements. It is required between two and optional after the
last, in a script and inside a group or block alike.

```
a := #1. b := #2      ; the last needs no '.'
```

A line beginning with `:` continues the expression above it, so

```
total := #10
:add(#5).
```

is one statement, not two.

### Literals

| Form | Type | Notes |
| --- | --- | --- |
| `#45`, `#-45` | integer | `#` is a type tag, not a marker |
| `$FF08`, `$ff08` | integer | hexadecimal; either case |
| `%10101100` | integer | binary |
| `45`, `45.5` | float | a bare number is a float |
| `1e3`, `1.5e-3`, `1E+3` | float | exponent optional, sign optional |
| `"hello"` | string | see escapes below |
| `[#1, #2]` | array | sugar for `array:of(#1, #2)` |
| `#["a" = #1]` | dictionary | sugar for `dictionary:of("a", #1)`; the `[` follows the `#` immediately |
| `{ #1 }` | block | code as a value |
| `'foo` | symbol | an interned name; no closing quote |

`#` marks an integer and its absence marks a float, so `#45` and `45` are
different values of different types. There is no exponent on an integer, `#`
meaning exact.

A `.` only continues a number when a digit follows it, so `45.` is the float
`45` followed by a statement separator.

#### Bases

`$` and `%` write the same integer in the base you are thinking in. A colour, a
file mode and a set of flags are all patterns of bits, and `#493` does not look
like `rwxr-xr-x` to anybody:

```
%111101101:asBase(#8):display.   ; 755
$FF08:print.                     ; #65288
$ff:equals(#255):print.          ; true
```

**They carry no `#`.** That tag is there because `45` and `#45` are the same
characters with two readings and it says which; `$FF` has one reading, there
being no hexadecimal float, so a tag would be noise.

**And they take no sign.** `#-3` is allowed because a decimal integer is a
number you may want the negative of. These are for looking at bits, and this
language already declines to reach a negative that way —
[no shift produces one](ROADMAP.md#312-no-shift-can-produce-a-negative-integer).
`#0:sub($FF)` is how to ask.

A digit or letter the base does not use ends the literal with an error rather
than starting the next token, so `%1012` is refused instead of quietly being the
binary `%101` followed by the float `2`. `$FF.5` is refused for the same reason
`#45.5` is.

Nothing downstream knows there were three spellings: all of them reach the same
constant, and `.sob` files are unchanged.

### String escapes

`\"`, `\\`, `\n`, `\t`, `\r`. Any other escape is an error rather than a literal
backslash. There is no `\0`.

```
"she said \"hi\"".
"one\ntwo".
```

A literal newline inside the quotes also works.

### Identifiers

`[A-Za-z_][A-Za-z0-9_]*`. Message selectors are identifiers, which is why `=`
cannot be one: `a:=(b)` would otherwise be both an assignment and a send.

### Reserved names

None are keywords, but these are bound as globals at startup and shadowing them
will surprise you: `integer`, `float`, `string`, `array`, `dictionary`, `time`,
`symbol`, `block`, `boolean`, `object`, `error`, `foreign`, `system`, `nil`,
`true`, `false`, `infinity`, `nan`.

The first twelve are the class objects, `system` is
[the process](#the-program-and-its-process), and the rest are values.

`foreign` is the odd one. Nothing in the language makes one — a foreign handle
is a resource an extension owns, a socket or a window, and only a primitive can
hand one over. It is named so that a program given one can ask
`held:isKindOf(foreign)`. See [extensions.md](extensions.md).

`self` is not a global; it is recognised by the compiler inside a block.

`include` is not reserved at all. The directive is `@include`, one token, and no
identifier can begin with `@` — so the language has no keywords in the ordinary
sense and the `@` space cannot collide with a name you might want.

---

## Values

| Type | Literal | Semantics |
| --- | --- | --- |
| nil | `nil` | the absent value |
| boolean | `true`, `false` | |
| integer | `#45` | signed 64-bit, **immutable** |
| float | `45.5` | IEEE-754 binary64, **immutable** |
| string | `"hi"` | **immutable** |
| array | `[#1]` | growable, **mutable** |
| dictionary | *none* — `dictionary:new` | values under keys, **mutable** |
| time | *none* — `system:time` | an instant, **immutable** |
| symbol | `'foo` | an interned name, **immutable** |
| block | `{ #1 }` | code as a value |
| object | `object:new` | slots plus a prototype, **mutable** |

**Values and references divide on mutability.** Numbers and strings are
immutable, so they are values: two are equal when they say the same thing, and
sharing is always safe. Arrays, blocks, and objects are references: two are equal
only when they are the same one, and `a := b` makes two names for one thing.

```
a := "hi". b := "hi". a:equals(b):print.      ; true  -- same characters
a := [#1]. b := [#1]. a:equals(b):print.      ; false -- two arrays
```

### Strictness

Types never coerce. An integer does not combine with a float, and a string does
not join to a number.

```
#45:add(1.5).        ; solvm: 'add' expects integer, got float (no implicit coercion)
"a":concat(#1).      ; solvm: 'concat' expects a string, got integer
#45:asFloat:add(1.5) ; the conversion is written out
```

Integer arithmetic traps rather than wrapping: overflow, division by zero, and
`INT64_MIN div #-1` are all errors. Floats follow IEEE, so they overflow to
`infinity` and divide by zero to it, infinity being a representable float where
there is no such integer.

---

## Names and binding

`:=` binds a name to an evaluated value. It means the same thing everywhere —
and it is the one thing in the language that is **not** a message, so it cannot
be overridden the way `add` or `print` can.
[design.md](design.md#why-binding-is-syntax-and-not-a-message) says why: it
compiles to four different instructions depending on what the name turns out to
be, and two of them address a numbered slot in a frame rather than a slot on any
object there would be a way to name.

```
a := #45.                            ; a global
integer:double := { self:mul(#2) }.  ; a slot on a class
p:x := #3.                           ; a slot on an object
```

Only **parameters** and names declared with `| ... |` are locals. Everything else
is a global, read or written.

```
counter := #0.
integer:bump := {
    counter := counter:add(#1).      ; updates the global
    counter
}.

integer:quadruple := { | d |         ; a temporary of this frame
    d := self:double.
    d:double
}.
```

Only the top level of a script may **create** a global. An undeclared name
assigned inside a block must already exist, so a typo is reported rather than
quietly becoming a variable that looks local.

Declarations may open a block or a method body, and a duplicate name in one
frame is a compile error.

A group may open with them too, **anywhere**, the top level of a script
included:

```
( | t | t := #5. t ):print.      ; #5
```

A group borrows the frame it sits in rather than making one, so its temporaries
belong to that frame — and the whole script is one frame. Two groups in a file
therefore share a namespace and cannot both declare `t`, exactly as two groups
inside one block cannot.

This was refused until the script's frame had slots to declare into. See
[6.6](COMPLETED.md#66-the-loop-constructs-are-library-code-and-pay-for-it--done)
for the other thing that was waiting on the same field.

---

## Messages

`:` is the send operator. Parentheses group a message's arguments.

```
receiver:selector.
receiver:selector(a).
receiver:selector(a, b).
```

Sends chain left to right:

```
#2:add(#3):mul(#4):print.     ; #20, being (2+3)*4
```

There are no operators and no precedence to remember; `a:add(b:mul(c))` is
written out. The one exception is a `@expr(...)` region, which is
[infix operators](#infix-operators) and lowers to these same sends.

A bare identifier resolves to a local, then to an enclosing frame's local, then
to a global. It is a lookup, not a send.

### Grouping

`( ... )` groups an expression, which is how a chain is redirected:

```
#1:add(#2):mul(#3):print.       ; #9, being (1+2)*3
#1:add((#2:mul(#3))):print.     ; #7, being 1+(2*3)
```

A group may hold several statements separated by `.`. The earlier ones are
discarded and the last is the group's value.

```
( #1. #2 ):print.               ; #2
```

It may also open with `| a, b |`, declaring temporaries of the frame it sits in
-- the script's own frame included. Two groups sharing a frame share one
namespace; see [Names and binding](#names-and-binding).

**A group is not a block.** Both are code in brackets, both hold statements
separated by `.`, both answer their last one, and both may declare temporaries.
Everything else differs: a group runs where it is written, exactly once, and a
block runs only when something sends it `value`, then as many times as it is
sent.

```
(#1:add(#2)):print.             ; #3      -- the group ran
{ #1:add(#2) }:print.           ; <block> -- nothing ran
```

A group also borrows the frame it sits in, where a block makes one -- which is
why a group can only declare temporaries somewhere that already has a frame.

That the argument to `ifTrue` is a block and not a group is the whole of how
control flow works here: an argument is evaluated before the send, so a group
would have run before `ifTrue` could decide anything. See
[Control flow](#control-flow).

---

### Infix operators

`@expr( ... )` writes an expression the way it is written on paper. It is
notation and nothing else: every operator lowers to the send it reads as, and the region
compiles to the bytes the chain would have compiled to.

```
@expr( #1 + #2 * #3 ):print.        ; #7
#1:add(#2:mul(#3)):print.           ; #7 -- the same bytecode, not just the same answer
```

| | | |
| --- | --- | --- |
| `a + b` | `a:add(b)` | groups to the left |
| `a - b` | `a:sub(b)` | groups to the left |
| `a * b` | `a:mul(b)` | groups to the left, tighter than `+` and `-` |
| `a / b` | `a:div(b)` | groups to the left, tighter than `+` and `-` |
| `a ^ b` | `a:pow(b)` | groups to the **right**, tighter than everything |
| `-a` | `a:negated` | looser than `^`, so `-2^2` is `-(2^2)` |
| `a = b` `a <> b` | `equals` `notEquals` | looser than `+` and `-` |
| `a < b` `a > b` | `lessThan` `greaterThan` | and does **not** chain |
| `a <= b` `a >= b` | `lessOrEqual` `greaterOrEqual` | |
| `~a` | `a:not` | looser than a comparison, so `~a = b` is `~(a = b)` |
| `a & b` | `a:and({ b })` | stops early; looser than `~` |
| `a \| b` | `a:or({ b })` | stops early; the loosest of all |

**What it is for** is a formula you are transcribing. A send chain reads strictly
left to right and arithmetic precedence does not, so the outermost operation of
a nested formula ends up in the middle of the line and the reader cannot check
it against the page it came from:

```
5.0:pow(2.0):add(3:mul(5.0:div(2.0):sin:add(9.0:sqrt))):print.
;                                                     ; 35.79541643231187
@expr( 5.0^2 + 3 * (sin(5.0/2) + sqrt(9.0)) ):print.  ; 35.79541643231187
```

**`sin(x)` is `x:sin`.** Prefix application is a send to its argument, and that
is the whole rule. It takes **exactly one** argument, which is what leaves the
rule with no exceptions: the two-argument cases would have needed them —
`float:atan2` is class-side, so `atan2(y, x)` could never have meant
`y:atan2(x)`, and `pow` already has `^` — and neither can enter a rule that has
no two-argument form to enter. Both are written out, as terms like any other.

The name is an ordinary identifier and not a blessed list, so `sin` and `cos`
stay names any object may use for a slot. That is the reason the rule is general
rather than restricted to the mathematical functions: a list would have had to
appear in the grammar as word literals, and the language's *no reserved words at
all* is a claim the test suite checks.

```
@expr( sqrt(9.0 + 7) ):print.   ; 4    -- the argument is a whole expression
@expr( sqrt(9.0):abs ):print.   ; 3    -- and a call chains like any receiver
```

**It is a send, not a block call.** A global holding a block is called with
`value`, so `f(3)` is `3:f` and not `f:value(3)`. That is the one thing to know
about the form, and getting it wrong says so:

```
f := { x | x:mul(x) }.
@expr( f(3) ).          ; solvm: float does not understand 'f'
```

**Comparison does not chain.** `a < b < c` would compare a boolean to `c`, so it
is refused while compiling rather than left to fail while running:

```
[prog.sol:1:19] solas: comparisons do not chain; the left of this one is a boolean at '<'
  x := @expr( 1 < 2 < 3 ).
                    ^
```

**`&` and `|` stop early**, because `and` and `or` take a block so that they
can — `a:and({ b })`. They are the only two operators whose right-hand side is
not compiled where it stands: it goes where the block's body would have gone,
behind the jump. The bytes are still the block form's bytes.

**`~` is looser than a comparison**, so `~a = b` is `~(a = b)` — the reading the
words have, and the one BASIC makes, its `NOT` sitting below the comparisons and
above `AND`. C and Pascal both bind it tightest and would have read `(~a) = b`,
so this is the one place here where a habit from either misleads.

**`|` is the one operator the language already used**, for a block's parameters
and a group's temporaries. Those are taken before a body is, so a `|` reaching
the operators is one standing where an operator may stand — a block inside a
region still reads exactly as it does outside one:

```
@expr( [1.0, 2.0]:inject(0.0, { t, e | t + e }) ):print.    ; 3
```

**A term is an ordinary expression** either way. Anything that is an expression
outside a region is one inside it, sends and all, so `(a/2):sin` and `b:sqrt`
are still written as they always were — and compile to the same bytes as
`sin(a/2)` and `sqrt(b)`.

**A region is lexical**, so it covers what is nested inside it: an argument, an
array element, a group and a block body all read as infix within one.

```
@expr( [1.0, -3.0, 2.5]:inject(0.0, { t, e | t + e }) ):print.   ; 0.5
```

**A region may be a block rather than a group.** `@expr{...}` is the same
region over `{...}`: it answers a block whose body reads infix, where
`@expr(...)` answers what its expression comes to. That is the language's own
pair — a group runs now, a block is code held as a value — and the block form
compiles to exactly what `{ @expr(...) }` compiles to, inlining included where a
literal block inlines.

```
i := #0. total := #0.
@expr{ i < #5 }:whileTrue(@expr{ i := i + #1. total := total + i }).
total:print.                                   ; #15
```

A region is lexical, so wrapping the whole send works too — `@expr( { i < #5
}:whileTrue({ ... }) )` reads the same way. What the block form buys is the
*width*: the region is the block and nothing else, where wrapping puts the
receiver and every other argument inside a mode that changes what `-` means.

**`-` is the one character that means two things**, and which it means is
decided by the region rather than by what follows it. Outside, a leading `-`
belongs to the number and `a - 3` is the error *'-' must be followed by digits*;
inside, `-` is always the operator and `-3` is the operator applied to `3`. The
compiler folds that back to the one constant, so the two readings are the same
value and the same byte.

**It hides nothing about the two numeric types.** The notation is the send, so
it is the same refusal: there is no coercion, and `pow`, `sqrt` and the
trigonometry are float-only.

```
[prog.sol:1:1] solvm: 'add' expects integer, got float (no implicit coercion)
```

**And outside a region there are no operators at all**, which the compiler says
by name rather than leaving you to guess:

```
[prog.sol:2:8] solas: arithmetic is written as sends here; '@expr(...)' is where the operators are
  b := a + 2.
         ^
```

## Blocks

`{ ... }` makes a block: code as a value. Writing one runs nothing.

```
b := { #21:add(#21) }.
b:value():print.              ; #42
```

Parameters come before `|`. A leading `|` declares temporaries, and a block may
have both -- the parameters, then a temporaries list of its own:

```
{ k | | t | t := k:add(#1). t }
```

```
add := { a, b | a:add(b) }.
add:value(#3, #4):print.      ; #7

{ | t | t := #5. t:add(#1) }:value():print.   ; #6
```

A block's body may hold several statements separated by `.`; the last is its
value.

### Capture

A block reads the frame it was written in, lexically, however many blocks deep.

```
integer:sumTo := { | total, i |
    total := #0.
    i := #1.
    { i:greaterThan(self):not }:whileTrue({
        total := total:add(i).
        i := i:add(#1)
    }).
    total
}.
```

`self` is the receiver the block was written under, captured when the block is
created — so a block inside a method still answers the right object.

A block that reads or writes its enclosing frame cannot outlive it. Calling one
after that frame has returned is reported, not left to read whatever now sits
there. A block that touches nothing outside itself may escape freely.

---

## Control flow

There is no control-flow syntax. `ifTrue`, `ifElse`, and `whileTrue` are ordinary
messages that take unevaluated blocks, so a user can add control structures the
same way.

```
#5:lessThan(#10):ifTrue({ "small":display }).
#5:lessThan(#10):ifElse({ "small" }, { "large" }):display.

i := #0.
{ i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
```

`and` and `or` take a block for the same reason — so the answer can be settled
without running it.

```
x:greaterThan(#0):and({ x:lessThan(#10) }).
```

`whileTrue` and `and`/`or` are strict about the block answering a boolean.

**A block argument is checked when the message is sent**, not when the block is
run — and the two are different moments for every message that might not run
what it is given. `false:and(#45)` never reaches its argument, so a version that
checked only on the way into the block accepted it and answered `false`. That
made the complaint depend on the data: `[]:collect(#45)` answered `[]` where
`[#1]:collect(#45)` failed, from the same line of source, and a mistyped
`a:and(b)` was correct for exactly as long as `a` kept coming out false.

So all of these are refused, whatever the receiver, the count or the collection
holds:

```
false:and(#45).                 ; solvm: 'and' expects a block, got integer
true:ifElse({ #1 }, #45).       ; solvm: 'ifElse' expects a block, got integer
[]:collect(#45).                ; solvm: 'collect' expects a block, got integer
{ #1 }:onError(#45).            ; solvm: 'onError' expects a block, got integer
```

The rule is a **block value**, not the literal `{ … }`: a block reached through
a name is a block, which is the form these primitives see at all, since a
literal one written on the spot is inlined to jumps and never sent.

```
x := #3.
c := { x:lessThan(#10) }.
x:greaterThan(#0):and(c):print.          ; true
```

### What the compiler does with them

Written literally, `ifTrue`, `ifFalse`, `ifElse`, `whileTrue`, `doUntil`, `and`,
and `or` compile to jumps: no block is allocated and no frame is entered.

`repeat` and `loop` are **not** in that list and deliberately so. They
are primitives, which is faster here than inlining would have been: inlining
removes the block call an iteration and keeps two bytecode sends for the
counter, where a primitive removes the two sends and keeps the block call. The
sends cost more — measured, the primitive is 2.5× what inlined jumps produced. This is an optimisation
only — the meaning is exactly that of the message, and the message is still
there, reachable through `perform` or with a block held in a variable.

It applies when every block involved is written on the spot with no parameters
and no temporaries. For `whileTrue` that includes the receiver, since the
condition is the receiver. Anything else is compiled as an ordinary send, so
these still mean what they say rather than being quietly rewritten:

```
true:ifElse({ a | a }, { #2 }).      ; still an arity error, as a send would be
true:ifElse({ | t | t := #1. t }, { #0 }).   ; t stays in a frame of its own
{ a | a }:whileTrue({ #1 }).         ; the condition is a block like any other
```

A non-boolean receiver reports the same error either way:

```
#45:ifElse({ #1 }, { #2 }).
solvm: integer does not understand 'ifElse'
```

A condition that answers something other than a boolean is `whileTrue`
complaining about the answer, not a receiver failing to understand a message,
and it reads the same either way:

```
{ #1 }:whileTrue({ #2 }).
solvm: whileTrue expects the condition block to answer a boolean, got integer
```

`doUntil` names itself too, its condition being a block like `and`'s:

```
{ #1 }:doUntil({ #5 }).
solvm: 'doUntil' expects the block to answer a boolean, got integer
```

**`doUntil` is the loop `whileTrue` cannot write.** `whileTrue` tests before the
body runs, so a loop that must run at least once needs a flag declared outside
it. Inlined, `doUntil` needs no flag — which makes it **faster than the loop it
replaces**, not a convenience paid for: 1.28× the hand-written flag version,
because that flag costs two sends an iteration the jumps do not need.

`and` and `or` say the same thing about their block, naming themselves, since
what the block answered is what they answer:

```
true:and({ #5 }).
solvm: 'and' expects the block to answer a boolean, got integer
```

A loop compiles to a jump backwards, which is the only way the machine can run
the same instruction twice. It therefore need not terminate — but neither need
the loop it was compiled from, so nothing is reachable that was not before.

Recursion works, and with conditionals it terminates:

```
integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul(self:sub(#1):factorial) })
}.
```

---

## Objects

There is no separate notion of a class. `object:new` answers a fresh object
delegating to the receiver; whether something is a class or an instance is how
you use it.

```
point := object:new.
point:x := #0.                       ; a default every instance sees
point:y := #0.
point:sum := { self:x:add(self:y) }. ; a method: a slot holding a block

point:make := { a, b | | p |
    p := self:new.                   ; self, so it survives inheritance
    p:x := a.
    p:y := b.
    p
}.

p := point:make(#3, #4).
p:sum:print.                         ; #7
```

- A slot holding a **block** is a method; sending its name runs it with the
  receiver as `self`. A slot holding anything else answers that value.
- Assigning on an instance always makes the **instance's own** slot, so it
  shadows the prototype rather than writing through.
- Delegation chains, and the nearest slot wins.

### The built-in classes are objects too

`integer`, `array`, `string` and the rest are ordinary objects holding the
messages their *instances* understand. Sending one of those to the class itself
is an error, not a shortcut:

```
[#1, #2]:add(#3).    ; the array grows
array:add(#3).       ; solvm: 'add' expects an array, got object
```

The messages a class answers for itself are the ones that make instances —
`array:of(...)`, `array:new`, `object:new` — plus reflection, which reads either
side. `respondsTo` agrees with sending, so `array:respondsTo('add)` is false and
`array:respondsTo('of)` is true.

**The line is the receiver each message requires**, not which object holds it.
A class-side message wants an object, so a class answers it and an instance does
not:

```
array:of(#1, #2).      ; [#1, #2]
[#1]:of(#2).           ; solvm: 'of' expects an object, got array
```

Which makes the two sides separable, with nothing on neither:

```
integer:slots:size.                                          ; #30
integer:slots:select({ s | integer:respondsTo(s) }):size.    ; #8   -- class side
integer:slots:select({ s | #45:respondsTo(s) }):size.        ; #27  -- instance side
```

The five in both are `isKindOf`, `isNil`, `notNil`, `perform` and `respondsTo` —
reflection serves either side. See
[class-and-instance.md](class-and-instance.md#how-it-was-settled).

**Only three classes construct** — `object`, `array` and `dictionary` — and the
rule is mutability: `new` belongs where something is *made*, which is where the
instances are references, so there is a fresh, distinct one to hand back.

```
array:new:equals(array:new):print.    ; false -- two arrays
"":equals(""):print.                  ; true  -- one value
```

A value class has no fresh distinct thing to answer with, so the seven that are
left refuse and say what to write instead:

```
integer:new(#45).
solvm: an integer is written #45, and there is nothing for 'new' to make -- #0 is the empty one
```

They refuse rather than going missing because every built-in delegates to
`object`, whose `new` would otherwise answer an object delegating to `integer` —
a thing that fails every message an integer understands.

`integer:new` and `float:new` used to answer their own argument, which was the
literal spelled longer. See
[class-and-instance.md](class-and-instance.md#new-used-to-mean-three-things).

Every built-in class delegates to `object`, so there is one hierarchy and
everything is an object in the type graph as well as in the slogan:

```
#45:isKindOf(object):print.      ; true
"s":isKindOf(object):print.      ; true
integer:parent:equals(object):print.   ; true
object:parent:print.             ; nil  -- the chain ends here
```

So a method bound on `object` is answered by every value, which is what the root
is for. What a value does *not* get is storage: it has no slots of its own, so
`#45:x := #1`, `#45:parent` and `#45:via(object)` are all refused. See
[one-hierarchy.md](one-hierarchy.md) for the difference between inheriting the
behaviour and being an object.

Four classes cannot make their instances, because those instances are not
objects, and they say so rather than inheriting a `new` that would answer
something useless:

```
string:new.
solvm: a string is written as a literal, not made with 'new' -- "" is the empty one
```

`symbol`, `block`, `boolean` and `foreign` refuse in the same way, each naming
what to write instead — or, for `foreign`, that there is nothing to write,
because a resource comes from an extension.

Binding a block over one of these replaces the requirement along with the
primitive, so a class can be given messages of its own:

```
array:describe := { "arrays, in a list" }.
array:describe:display.
```

### Adding methods to a built-in class

A built-in class is an object and a slot holding a block is a method, so
extending one needs no new rule — it is the same `:=` used everywhere:

```
integer:double := { self:mul(#2) }.
#21:double:print.                    ; #42
```

Every built-in takes them, arguments and recursion included:

```
integer:between := { lo, hi | self:greaterOrEqual(lo):and({ self:lessOrEqual(hi) }) }.
#5:between(#1, #10):print.           ; true

string:shout   := { self:asUppercase:concat("!") }.   ; "hey":shout   -> "HEY!"
array:second   := { self:at(#2) }.                    ; [#1,#2,#3]:second -> #2
boolean:toggle := { self:not }.                       ; true:toggle  -> false
block:twice    := { self:value. self:value }.
```

The addition is global: every integer gains `double`, because there is one
`integer` and that is where the method now lives. To give a *distinct* type its
own behaviour, build an object that holds a value rather than extending the
class — a value type cannot be subclassed, since an unboxed number's class is
chosen by its type tag and there is nowhere to record a different one.

Two things to know before overriding a message that already exists.

**The primitive is gone.** A slot wins over a primitive of the same name, and
nothing keeps the displaced one. `via` cannot reach it either: a built-in class
has no ancestor holding the version you replaced.

**Do not build the text with `fill` inside an `asString` override.** `fill`
renders each of its values by *sending* `asString`, so it re-enters the override
and recurses until the call-depth cap:

```
integer:asString := { "<{}>":fill([self:abs]) }.
#42:asString.
solvm: call depth exceeded
```

Use `concat` there instead. The recursion is bounded rather than fatal, but it
is an easy loop to write.

### Calling what you override

`self:via(ancestor)` begins the lookup at the ancestor but keeps the receiver, so
`self` inside the ancestor's method is still the instance.

```
animal := object:new.
dog := animal:new.

animal:intro := { "I am ":concat(self:name) }.
dog:intro := { self:via(animal):intro:concat("!") }.

rex := dog:new. rex:name := "rex".
rex:intro:display.            ; I am rex!
```

The ancestor is named rather than inferred, so a method extends the object it was
written against however deep the receiver is.

`parent` reads the delegation link and is read-only.

**Assigning it does not re-parent.** `o:parent := other` binds an ordinary slot
named `parent`, which shadows the message — the delegation link is an internal
pointer rather than a slot, so nothing a program writes can corrupt dispatch.
The assignment succeeds, `o:parent` then answers `other`, and what `o` actually
delegates to is unchanged:

```
a := object:new. a:tag := #1.
b := object:new. b:tag := #2.
kid := a:new.

kid:parent := b.
kid:parent:equals(b):print.      ; true   -- the slot answers
kid:tag:print.                   ; #1     -- but the chain still runs to a
```

This is the ordinary shadowing rule rather than a special case: a slot always
wins over a primitive of the same name, which is what lets an object define its
own `asString`. It is worth knowing because it is the one assignment that looks
like it did something and did not.

There is no way to re-parent at run time. It would need the link to become a
real slot, which is a separate question — see [ROADMAP.md](ROADMAP.md) 2.14.

### Showing an object

Define `asString` and it serves `print`, `display`, `fill`, and an enclosing
array alike.

```
point:asString := { "point({}, {})":fill([self:x, self:y]) }.
p:print.                      ; point(3, 4)
[p]:print.                    ; [point(3, 4)]
```

Without one, an object shows its address.

---

## Asking whether a value is there

`isNil` and `notNil` are on **every type**, and they have to be: the point of
asking is that you do not know what the receiver is, so a message only nil
understood could not be sent to find out.

```
system:readLine:isNil:print.     ; true at the end of input
"":isNil:print.                  ; false -- empty is not absent
```

`notNil` exists rather than leaving `isNil:not` to say it, because the negative
is the form that gets written: running out of input is how a loop finishes.

```
line := system:readLine.
{ line:notNil }:whileTrue({ ... }).
```

`x:equals(nil)` says the same thing and is what the language had before these.
It reads as a comparison against a value rather than a question about absence,
and its negative is three concepts deep to ask one thing.

Absence is not emptiness: `""`, `#0`, `[]` and `false` all answer `notNil`. See
[absence.md](absence.md).

---

## Errors

Every failure stops the program unless something catches it.

```
{ nil:frobnicate }:onError({ e | e:message:display }).
        ; nil does not understand 'frobnicate'
```

`onError` runs the receiver, and if it fails runs the handler with the error
instead. It answers **the receiver's answer when nothing went wrong, and the
handler's when something did** — so it is an expression:

```
text := { system:readFile(path) }:onError({ e | "" }).
```

A caught error says nothing: the message never reaches stderr, and the program
carries on.

### Raising one

```
error:raise("bad input on line 3").
```

`error:raise` is the only way to raise, so **re-raising is
`error:raise(e:message)`**. Two spellings — one on the class taking a string,
another on an instance taking none — would be one name meaning two things, which
is a mistake this language has made once already with `new`. The price of having
one is that a re-raised error's stack points at where it was re-raised rather
than where it first failed. That is honest: it *is* a new raise.

### The error

An ordinary object delegating to `error`, with its message in a slot.

| Message | Answers |
| --- | --- |
| `message` | the text, as a string; nil on an error made some other way |

It is a value rather than a string on purpose. This project rewords its errors
freely, so handing a handler the text and nothing else would make matching on it
the only way to tell failures apart — an idiom these very habits would keep
breaking. An object leaves room to say more about a failure later without
breaking every handler that already exists.

There is no taxonomy of failures. Inventing one to go with a catch mechanism
would be inventing it in the wrong order.

### What it catches

**Everything** — including a message misspelled into one the receiver does not
understand. That is the deliberate choice and the familiar hazard: a handler
wrapped around too much hides mistakes. What makes it bearable is that passing
one on is a single message:

```
{ risky:value }:onError({ e |
    e:message:equals("empty"):ifElse(
        { "(nothing given)" },
        { error:raise(e:message) })       ; not ours -- pass it on
}).
```

Two things it does not catch. **`system:exit`** travels the same way, being a
stop rather than a failure, and a program asking to stop should not be argued
with by something that was only watching for errors. And an error raised **inside
the handler** is not caught by that handler — it propagates, like any other
failure.

The handler is checked when it is run, not when `onError` is sent, so
`{ #1 }:onError(#2)` is quiet when nothing fails. That is how every block
argument here behaves: `false:ifTrue(#5)` says nothing either.

### Cleaning up regardless

`ensure` runs its second block whether the first finished or not, and then goes
on doing whatever the first was going to do:

```
{ working:value }:ensure({ tidyUp:value }).
```

It answers **the body's** answer. The cleanup's is discarded, the cleanup not
being what the expression is about.

The cleanup runs on the way out of a failure *and* on the way out of a
`system:exit` — giving back a thing you borrowed is as necessary when a program
is stopping as when it is failing. Nested, the cleanups run innermost first as
the failure travels outward.

**When both fail, the body's failure is the one that carries on.** That is the
rule everywhere here: the first error wins, and the second is usually a
consequence of the first. A cleanup that fails on its own, with nothing to
compete with, fails normally.

An uncaught failure that passed through a cleanup keeps its own message and its
own stack, so it still names where it happened rather than where it was tidied
up after.

Unlike `onError`'s handler, the cleanup **always** runs, so one that is not a
block is refused every time rather than only when something fails.

---

## Reflection

Six messages let a program ask about itself. Names are given as symbols,
because a symbol is what a name is and comparing one is a pointer comparison.

| Message | Answers |
| --- | --- |
| `slots` | an array of symbols naming the receiver's **own** slots |
| `exports` | the object's export list, or **nil** where it has drawn none |
| `exports(names)` | draws one — see [The export boundary](#the-export-boundary) |
| `slotAt(name)` | the value in that slot, searching the chain like a send |
| `respondsTo(name)` | whether a send of that name would find anything |
| `isKindOf(class)` | whether the receiver delegates to `class`, at any depth |
| `perform(name, ...)` | the answer to a send whose name is decided at run time |

Continuing the `point` above -- which by now carries the `asString` the section
before gave it, and `slots` says so:

```
point:slots:print.               ; ['x, 'y, 'sum, 'make, 'asString]
p:isKindOf(point):print.         ; true
p:respondsTo('sum):print.        ; true
p:perform('sum):print.           ; #7
```

`slots` answers own slots in the order they were defined; inherited names are
not yours, and `parent:slots` is how you ask about those. `respondsTo` and
`slotAt` search the whole chain, as a send does.

### The export boundary

An object with slots is already a namespace: one name in the flat global space,
with everything else reached through it. What that does not give you is a way to
say which of those slots are anybody else's business. `lib/json.sol` binds one
global and hangs two dozen slots on it, of which four are the library and the
rest are one parser taken apart — and until this existed, `json:digits := "abc"`
from outside broke the parser.

```
counter := object:new.
counter:n := #0.
counter:bump  := { self:n := self:n:add(#1) }.
counter:total := { self:n }.
counter:exports(['bump, 'total]).
```

**From outside, an object that has drawn a boundary *is* its export list.** A
name off the list can be neither sent nor bound:

| from outside | |
| --- | --- |
| `counter:total` | works |
| `counter:n` | `'n' is not exported by object` |
| `counter:n := #99` | refused — the failure this exists to stop |
| `counter:fresh := #1` | refused; an unlisted name cannot be added either |

That last row is not extra strictness but the same rule. Were binding an
unlisted name allowed, a name that happened to collide with something private
would quietly overwrite a slot the binder is not permitted to read.

**From inside, nothing changes**, which is the only reason a boundary is usable
— `bump` goes on reaching `self:n`. Inside means the frame doing the sending is
running with that very object as its `self`. A program's top level has no self,
so it stands outside every object, which is the intent.

**The boundary belongs to the object, not to how the object arrived.**
`@include` and [`system:load`](#loading-a-compiled-file) are two ways of getting
a library into your globals; once it is there the line is the same one, because
what decides the question is `self` and neither mechanism touches that. An
included file's text is compiled into yours, so its top level and yours are one
chunk with one `self` of nil — there is no sense in which an includer is further
inside than a loader.

Which has a sharper consequence: **the file that draws the line is outside it
too**, from the next statement on.

```
o := object:new.
o:n := #1.
o:get := { self:n }.
o:exports(['get]).

o:get:print.                                   ; #1
{ o:n }:onError({ e | e:message:display }).    ; 'n' is not exported by object
```

`get` still reaches `n`, because it runs with `o` as its self whenever it is
called. The line below `exports` does not, because the top level has no self and
never did.

**So `exports` goes last in a library**, after whatever it sets up while
loading. [lib/json.sol](../lib/json.sol) builds its escape tables with
`json:escapes:atPut(...)` at its top level, and those are outside sends: they
work because the boundary is not drawn until the final line of the file. Drawn
first, a library would lock itself out of its own construction.

**The boundary is inherited**, and this is what makes it worth drawing on a
prototype at all. Every piece of state a program holds lives on an object made
*from* a prototype rather than on the prototype itself — a cursor's text, a
counter's count — so a line that stopped at the object which drew it would hide
the default and leave every real one public. An object under a boundary is that
boundary's export list, whether it drew the line or inherited it.

**A method on a prototype may reach into an object made from it**, which is what
a constructor is: `scan:on` runs with `scan` as its self and has to put the text
into a cursor that is not itself yet. Only downward — a method on a child
reaches its inherited privates through `self`, which the ordinary rule covers,
while naming the prototype and reaching up into it stays refused.

**Privacy is inherited.** The check compares the *receiver* against the sender's
self rather than against whichever object in the chain holds the slot, so a
child's own method reaches what it inherited while an unrelated object does not.

**Reflection keeps the line rather than walking around it.** From outside,
`slots` answers the exports and nothing else, `slotAt` refuses an unlisted name,
and `respondsTo` answers false for one — that last because `respondsTo` must
agree with what sending would actually do.

**It is opt-in, and an object that never calls `exports` is unchanged in every
respect.** Every slot stays readable, writable, addable and listed by `slots`,
and `exports` answers **nil**. Not drawing a line is not a weaker line; it is
the absence of one, exactly as before this message existed.

So a boundary is something a library *chooses*, not a default it opts out of.
Of the nine shipped libraries, **five have drawn one** — `json`, `scan`,
`pattern`, `sob` and `html`, the last twice, since it binds both a parser and
the node prototype a read answers.

`shell` has not, and deliberately: it has four slots and all four are the API,
so a line there would list everything and hide nothing. The remaining three bind
no object at all — `control`, `math` and `text` add methods to built-in classes,
so there is nothing for a boundary to go around.

That is also the compatibility promise, and it is what lets
[examples/include.sol](../examples/include.sol) go on extending an included
object from outside on purpose.

Nothing takes a boundary back down. `exports` may be called once from anywhere,
and after that only from inside; a boundary any caller could widen would be a
note about intent rather than a boundary.

**What it costs is not measurable.** A slot carries a bit saying whether it is
exported, set true unless a boundary leaves it out, and the dispatch loop tests
that bit before anything else — so the sender's `self` is not even built unless
the bit is clear. Written the other way round, building that value on every send
and letting the check discard it, it cost 8.7% of a loop that does nothing but
send. Tested bit-first, thirty runs cannot tell the two builds apart, on that
loop or on a real program.

See [examples/exports.sol](../examples/exports.sol).

A value answers for the class it dispatches to, so `#45:isKindOf(integer)` is
true and `#45:respondsTo('add)` is true. `slots` and `slotAt` want an object to
look inside and say so on anything else.

The built-in classes are objects whose slots hold primitives, so
`integer:slots` lists what an integer understands. `slotAt` on one of those is
an error: a primitive is C, and has no value to answer.

### Fetching a method

A slot holding a block **is** a method, so `slotAt` is the only way to get at
one as a value. What comes back is the plain block, and `self` is supplied by a
send rather than carried by the block:

```
m := point:slotAt('sum).
m:value.                 ; solvm: nil does not understand 'x'
p:perform('sum):print.   ; #7 -- the receiver comes from the send
```

`boundTo` chooses one. It answers a **second block** over the same code with
`self` set, which you then call like any other block. The longer explanation,
including what it is for, is in [fetched-methods.md](fetched-methods.md):

```
m := point:slotAt('sum).
bound := m:boundTo(p).
bound:value:print.       ; #7
```

Binding and calling stay two things, as `via` keeps them two things. So `value`
means exactly what it always meant -- the arguments are the block's own, and the
receiver is not one of them:

```
integer:poly := { a, b | self:mul(a):add(b) }.
n := integer:slotAt('poly):boundTo(#10).
n:value(#3, #7):print.   ; #37
```

The receiver may be any value, since `self` may be. The original block is
untouched: binding answers a new one, and binding that one binds again.

Two things it does **not** do. It does not lift the frame restriction — a block
that reads its home frame is no freer for being bound, so binding chooses a
receiver, not a lifetime. And it does not survive a send: installing a bound
block in a slot still makes an ordinary method, and a send supplies its own
receiver, which is what makes an installed block a method at all.

```
b:show := m:boundTo(a).
b:show.                  ; the send wins -- self is b, not a
```

---

## Message reference

Every built-in message. `print` shows the **literal** form (`#45`, `"a\"b"`);
`display` writes the **text** (`45`, `a"b`); `asString` answers that text as a
string.

Elements inside an array are always shown in literal form, so that a printed
array reads back as one: `["a"]:display` writes `["a"]`, quotes and all, where
`"a":display` writes `a`.

### Every type

`print`, `display`, `asString`, `equals`, `notEquals`, `isNil`, `notNil` (see
[Asking whether a value is there](#asking-whether-a-value-is-there)), and the
reflection messages `perform`, `respondsTo`, `isKindOf`, `slots`, `slotAt` (see
[Reflection](#reflection)).

`asString` takes an optional format spec:

```
[align] [','] ['0'] [width] ['.' decimals]

45.8:asString("6.2")         ; " 45.80"
45.8:asString("08.2")        ; "00045.80"
#1234567:asString(",")       ; "1,234,567"
1234.5:asString(",10.2")     ; "  1,234.50"
#45:asString("<6")           ; "45    "
"ab":asString(">6")          ; "    ab"
```

`<` `>` `^` align left, right, centre. Numbers align right by default and
everything else left. A value wider than the width is never cut.

`,` groups whole-number digits in threes, and only those -- a sign, a fraction,
and an exponent pass through. Decimals and grouping belong to numbers; asking a
string, a boolean, or an array for either is an error.

Zero fill must align right and goes after any sign, so `#-45:asString("06")` is
`-00045`. It cannot be combined with `,`. The flags have one order, so there is
one way to write a given spec.

With no argument it answers the plain text, which is what `display`, `fill`, and
array rendering ask for.

`equals` compares characters for strings and identity for arrays, blocks, and
objects.

### integer

| Message | Answers |
| --- | --- |
| `add(n)` `sub(n)` `mul(n)` | an integer; traps on overflow |
| `div(n)` `mod(n)` | **floored**; traps on zero and on `INT64_MIN div #-1` |
| `inc` `dec` | one more, one less; traps at the ends |
| `negated` `abs` | an integer; traps on the most negative |
| `bitAnd(n)` `bitOr(n)` `bitXor(n)` | an integer, bit by bit |
| `bitNot` | every bit flipped |
| `shiftLeft(#n)` `shiftRight(#n)` | an integer; `#0` to `#63`, and see below |
| `lessThan(n)` `greaterThan(n)` | a boolean |
| `lessOrEqual(n)` `greaterOrEqual(n)` | a boolean |
| `asFloat` | a float; loses precision above 2^53 |
| `asString` | the digits, without the `#` |
| `asBase(#n)` | the digits in base `n`, 2 to 36, as a string |
| `asCharacter` | the one-byte string that byte spells; `#0` to `#255` |
| `repeat(block)` | nil, having run the block that many times |


`#-7:div(#2)` is `#-4` and `#-7:mod(#2)` is `#1`: division floors, so the
remainder takes the divisor's sign and stays in `[0, n)` for positive `n`.

**`inc` and `dec`** are `add(#1)` and `sub(#1)` under shorter names, which this
language does not usually hand out. What earns them is how often they are
written: **76 of the 256 arithmetic sends** in the examples and libraries are
one or the other, three in every ten. That is what having no binary operators
costs the commonest arithmetic there is.

They answer a new integer rather than changing the receiver, an integer being a
value — so the idiom is the assignment:

```
count := count:dec.        ; and `count:dec` on its own does nothing
```

Integers only. Counting by ones in a type where a one is not exact is a mistake
to make deliberately rather than conveniently.

#### Bits

An integer is a signed 64-bit two's-complement number, and these treat it as
one. They are for the places a number is really a row of flags — a file mode, a
UTF-8 byte, a set packed into a word.

```
#12:bitAnd(#10).       ; #8    -- 1100 and 1010
#12:bitOr(#10).        ; #14
#12:bitXor(#10).       ; #6
#0:bitNot.             ; #-1   -- every bit set
#1:shiftLeft(#10).     ; #1024
#1024:shiftRight(#3).  ; #128
```

**A shift right keeps the sign.** There is no unsigned integer here, so a
logical shift would turn every negative number into a huge positive one — and
keeping the sign makes a shift agree exactly with `div` by a power of two, which
is **floored**:

```
#-7:shiftRight(#2).    ; #-2
#-7:div(#4).           ; #-2, the same
```

**A shift left refuses to lose the number**, the way `mul` refuses to overflow,
rather than dropping the bits that go off the end. The count must be `#0` to
`#63`; anything else is refused rather than answering whatever the hardware
does with it.

```
#1:shiftLeft(#63).     ; integer overflow in 'shiftLeft'
#1:shiftLeft(#64).     ; 'shiftLeft' wants #0 to #63, got #64
```

Which is how a mode gets its executable bit without arithmetic:

```
system:setMode(path, system:modeOf(path):bitOr("111":asInteger(#8))).
```


### float

Everything integer has, minus `asFloat`, `asBase`, and the overflow traps, plus:

| Message | Answers |
| --- | --- |
| `floor` `ceiling` `rounded` `truncated` | an **integer**; errors on infinity, not-a-number, or out of range |
| `sqrt` | a float; `nan` for a negative |
| `pow(other)` | self raised to `other` |
| `exp` `log` | e to the self, and the **natural** logarithm |
| `sin` `cos` `tan` | **radians** |
| `asin` `acos` `atan` | radians; `nan` outside the domain |

And two on the class rather than on a float, because neither has a receiver
that reads as the subject:

| Message | Answers |
| --- | --- |
| `float:pi` | 3.141592653589793 |
| `float:atan2(y, x)` | the angle to the point, radians, all four quadrants |

There is no `asInteger`: narrowing names its direction so there is no default to
remember. `rounded` is half away from zero. Bases are an integer's business, so
`asBase` is not here.

Dividing by zero answers a float rather than erring: `1:div(0)` is `infinity`,
`-1:div(0)` is `-infinity`, and `0:div(0)` is `nan`, which is IEEE rather than a
choice made here. `nan:equals(nan)` is false for the same reason. `sqrt` of a
negative falls on the same line and answers `nan` rather than raising.

**The mathematics is float only and radians only.** `#2:asFloat:sqrt` is how an
integer asks, since no arithmetic message here crosses the two types. Degrees
are a multiplication, and a multiplication is not something the machine has to
supply — `lib/math.sol` is where that would go if a program wanted it.

`pi` and `atan2` are on the class. `infinity` and `nan` are globals because they
are values this arithmetic *reaches* and has no other way to name; `pi` is a
constant, and `pi` is a name a program is entitled to want. `atan2` takes two
coordinates and neither of them is what the angle is about, so `y:atan2(x)`
would read as though the y were the subject.

`sqrt` is the one piece of arithmetic here that a program cannot write for
itself and get right. Newton's method converges quadratically only once the
guess is near, and from `x` itself the approach is one halving per octave, so a
fixed iteration count is wrong for large `x` and a capped loop is wrong by
orders of magnitude — both were written in this repository and both were silent
about it ([3.14](COMPLETED.md#314-the-mathematics-that-is-not-here--done)). It is float
only: `#2:asFloat:sqrt` is how an integer asks, since no arithmetic message here
crosses the two types.

A float is written as the shortest text that reads back as the same value, so
`0.1` prints as `0.1` and not as the seventeen digits it really is. A whole
float prints without a point, which is how the two number types are told apart
on the page: the `#` marks the integer.

```
45:print.            ; 45
#45:print.           ; #45
1:div(3):print.      ; 0.3333333333333333
1e21:print.          ; 1e+21
0.000001:print.      ; 1e-06
```

A hand-written `sin` fails the same way and fails harder, which is why these are
here rather than in a library: the series is the easy half, and reducing an
angle modulo 2π needs π to far more bits than a double holds. The obvious
reduction loses a digit per octave of the argument and is returning noise well
before 1e16, silently. `1e17:sin` here agrees with the C library to the last
bit.

`infinity` and `nan` are written by name, and both read back — `infinity` and
`nan` are globals, and `asFloat` parses either. `-infinity` has no literal;
`"-infinity":asFloat` gives it.

### string

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `at(#i)` | a one-character string; **one-based** |
| `concat(s)` | a new string; strict about its argument |
| `split(s)` | an array of the pieces between occurrences of `s` |
| `replace(s, t)` | a new string with **every** `s` replaced by `t` |
| `indexOf(s)` | where `s` first appears, **one-based**, or nil |
| `indexOf(s, #from)` | the same, looking from `#from` — for the second occurrence and the ones after it |
| `copyFrom(#a, #b)` | the characters `#a` to `#b`, both ends included |
| `fill([...])` | a new string with the blanks filled; see below |
| `lessThan(s)` `greaterThan(s)` | a boolean, comparing characters |
| `lessOrEqual(s)` `greaterOrEqual(s)` | a boolean |
| `asInteger` `asFloat` | strict: the whole string must be a number |
| `asInteger(#n)` | reads base `n`, 2 to 36; the digits alone, no `0x` |
| `asByte` | the number of the one byte in it; strict about there being one |
| `trim` | the same text without the space around it |
| `asUppercase` `asLowercase` | a new string; ASCII letters only |
| `asSymbol` | the interned symbol for these characters |
| `asTime` | an instant, read as ISO-8601; strict |
| `asTime(format)` | the same, the format handed to `strptime` |
| `asString` | itself |
| `asString(spec)` | padded text; see the spec below |

#### Taking a string apart

`split` answers **occurrences + 1 pieces**, always, and never drops one. A
separator at either end, or two together, gives an empty string where the
missing piece would be:

```
"a,b,c":split(",").      ; ["a", "b", "c"]
"a,,b":split(",").       ; ["a", "", "b"]
",a":split(",").         ; ["", "a"]
"abc":split(",").        ; ["abc"]   -- no occurrence, so one piece
"":split(",").           ; [""]
```

`replace` is the pair of them in one message, and replaces **every**
occurrence for that reason: `split` then `join` is how it was written before,
and that pair replaces all of them. A `replace` that did only the first would
not be shorter than the idiom it replaces — it would mean something different,
and tidying an old program up would change what it did.

```
"a-b-c":replace("-", "+").        ; "a+b+c"
"one two one":replace("one", "1"). ; "1 two 1"
"aaa":replace("aa", "b").         ; "ba"  -- forward, and non-overlapping
"a,b,c":replace(",", "").         ; "abc" -- an empty replacement deletes
"hello":replace("z", "!").        ; "hello" -- nothing found, so itself
```

An empty *needle* is refused, the way `split` and `indexOf` refuse one:
replacing nothing everywhere has no answer worth guessing at. A first-only
replace is `indexOf` and two `copyFrom`s, which is what wanting it looks like
and is rare enough not to have a name here.

Strings are immutable, so this answers a new one and the receiver is untouched
— and a receiver with nothing to replace *is* the answer, with nothing
allocated.

That is what makes the answer predictable: the pieces put back together with the
separator between them are the string you started with, whatever it was.
Dropping empties would read more kindly on `" a  b "` and would lose the
difference between `"a,,b"` and `"a,b"` — usually the one thing a program
parsing a file needs to keep.

Occurrences are taken left to right and not reconsidered, so `"aaaa":split("aa")`
is three empty pieces rather than two.

`indexOf` answers **nil when there is no match**, not `#0`. Indices start at
`#1`, so `#0` would be an out-of-band value and a second way of saying "nothing"
beside the one the language already has; `text:indexOf(","):isNil` is the
same question asked of an unset slot or the end of input.

**`indexOf(s, #from)` asks the same question from a position**, which is how the
second occurrence is found and every one after it:

```
at := "a-b-c":indexOf("-").
at := "a-b-c":indexOf("-", at:add(#1)).
at:print.                    ; #4
```

Without it a second search meant copying what was left of the string — which is
quadratic in a loop, and is what
[lib/pattern.sol](../lib/pattern.sol) and [programs/expect.sol](../programs/expect.sol)
were both doing ([6.37](COMPLETED.md#637-indexof-cannot-say-where-to-start--done)).
`#from` may be **one past the end**, where the answer is nil rather than an
error — the rule `copyFrom` has, so a walk that runs off the end gets an answer
instead of a fault. Further out is a mistake and says so.

`copyFrom` includes both ends and both are one-based, so `copyFrom(#i, #i)` is
exactly `at(#i)`. An empty result is spelled with `to` **one** before `from`, and
that is the only spelling — anything further apart is a mistake rather than a
wider empty. `from` may be one past the end for the same reason: that is where
the empty tail is.

```
"hello":copyFrom(#2, #4).    ; "ell"
"hello":copyFrom(#3, #2).    ; ""
"hello":copyFrom(#6, #5).    ; ""
"hello":copyFrom(#4, #2).    ; error: ends at #2, more than one before its start #4
"hello":copyFrom(#2, #6).    ; error: ends at #6, past a string of size 5
```

Neither `split` nor `indexOf` will look for the empty string: every position in
every string contains it, so the answer would be arbitrary rather than useful.
Both refuse it.

All three respect the length rather than stopping at the first NUL, so they work
on a file read with `readFile` whatever is in it.

[`join`](#array) puts the pieces back: `s:split(sep):join(sep)` is `s`, for
every string and every separator.

#### Filling in blanks

`fill` puts the array's values into the `{}` blanks, rendering each by sending
it `asString`. `{{`
writes a literal brace; `}` is never special. Placeholders and values must match
exactly — too few and too many are both errors.

```
"you have {} apples":fill([#3]):display.    ; you have 3 apples
```

Parsing is strict at both ends: `" 45"` and `"45 "` are errors, not `45`.

Bases go through `asBase` and `asInteger(#n)` rather than a letter in the format
spec, so one message covers every base from 2 to 36 and nothing in the spec
starts looking like a conversion character. Digits above nine are lowercase, and
padding comes from the spec by chaining:

```
#255:asBase(#16)                    ; "ff"
#255:asBase(#16):asString("08")     ; "000000ff"
"ff":asInteger(#16)                 ; #255
```

#### A byte and its number

`asByte` and `asCharacter` are inverses over the whole range `#0` to `#255`:

```
"A":asByte:print.            ; #65
#65:asCharacter:display.     ; A
```

They are named for **what each answers**. A string is bytes, so `asByte` is a
byte and not a character, and it is strict about its receiver holding exactly
one:

```
"é":size:print.              ; #2  -- one character, two bytes
"é":asByte.
solvm: 'asByte' wants one byte, and this string has 2 -- a character outside ASCII is more than one of them
```

Refusing is what keeps the two exact inverses. It also means a code point above
127 is not something `asCharacter` makes on its own — UTF-8 spells one with two
bytes or more, and putting them together is arithmetic. That arithmetic belongs
where the format is known rather than in the VM;
[lib/json.sol](../lib/json.sol) has it, and
[examples/strings.sol](../examples/strings.sol) has the two-byte case written
out.

`#0:asCharacter` is the **only way to write a NUL**: there is no `\0` in a
literal. A string is length-counted rather than NUL-terminated, so it carries
one like any other byte.

### array

| Message | Answers |
| --- | --- |
| `new` | an empty array |
| `of(...)` | an array of the arguments — what `[...]` compiles to |
| `size` | an integer |
| `at(#i)` | the element; **one-based**, out of range is an error |
| `atPut(#i, v)` | the value stored |
| `add(v)` | **the array**, so it chains |
| `removeLast` | the last element, taken off; **an error** when empty |
| `indexOf(v)` | where `v` first is, **one-based**, or nil |
| `do(block)` | the array, having run the block per element |
| `loop(block)` | nil; a *counted loop* over `[#a, #b]` or `[#a, #b, #step]` — the bounds, not the elements, both ends included |
| `collect(block)` | a new array of the block's answers |
| `select(block)` | a new array of the elements the block accepted |
| `inject(start, block)` | one value, folded left to right |
| `copyFrom(#a, #b)` | a new array, `#a` to `#b`, both ends included |
| `first(#n)` `last(#n)` | a new array of up to `n`; **clamps** |
| `join(s)` | the strings with `s` between them; strict |
| `sorted` | a new array in ascending order |
| `sorted(block)` | a new array ordered by the block |

`collect`, `select`, `inject`, `join` and `sorted` all leave the receiver
untouched. `select` and the comparison block are both strict about answering a
boolean.

**A stack.** `add` and `removeLast` are the two ends of one, which is what
parsing anything nested wants — [lib/html.sol](../lib/html.sol) keeps one of
open elements. `removeLast` **refuses an empty array** rather than answering
nil, the same choice `at` makes about an index out of range: nil would be a
second way of saying "nothing" beside the one the language has, and it would
turn a mistake into a value that fails further on. Ask `size` first, which is
the shape a stack's loop condition already has.

`indexOf` answers **nil when there is no match**, like [`string:indexOf`](#string),
so `xs:indexOf(v):notNil` is how to ask whether it is there — which is why there
is no `includes`. One message that answers *where* is worth more than two, one
of which only answers *whether*. It compares the way `equals` does: by content
for values, by identity for arrays, blocks, objects and dictionaries.

```
["a", "b", "c"]:indexOf("b").    ; #2
["a", "b", "c"]:indexOf("z").    ; nil
[[#1]]:indexOf([#1]).            ; nil  -- an equal-looking array is a different one
```

**Folding.** `inject` gives the block what has accumulated so far and one
element, and takes its answer as the next accumulation:

```
[#1, #2, #3, #4]:inject(#0, { total, n | total:add(n) }).   ; #10
[#1, #2, #3]:inject("", { s, n | s:concat(n:asString) }).   ; "123"
```

An empty array answers `start` without calling the block, so a fold is safe to
write without asking first whether there is anything to fold. What accumulates
need not be the elements' type, and the order is left to right.

It completes the four iteration messages: `do` throws its answers away,
`collect` and `select` each answer an array, and `inject` answers one value.
Unlike `do` it is an expression, so it can stand in the middle of one rather
than only at the top of a frame where an accumulator could be declared.

**Slicing.** `copyFrom` is the string's rule exactly: both ends included, both
one-based, an empty slice spelled with `to` one before `from`, and out of range
an **error** — following `at`. Two collections disagreeing about what a slice
means would be worse than either rule is good.

```
[#1, #2, #3, #4, #5]:copyFrom(#2, #4).   ; [#2, #3, #4]
[#1, #2, #3, #4, #5]:copyFrom(#3, #2).   ; []
[#1, #2, #3]:copyFrom(#1, #4).           ; error: ends at #4, past an array of size 3
```

`first` and `last` **clamp** where `copyFrom` refuses, and that is two rules on
purpose, because they are two questions. `copyFrom` names *positions*, and a
position outside the array is a program wrong about something. `first` names a
*quantity* — give me the top five — which a list of three has answered correctly
by handing over three. Refusing there would make every ranked report check the
size first, which is the whole of what these exist to avoid.

```
[#1, #2, #3]:first(#2).      ; [#1, #2]
[#1, #2, #3]:last(#2).       ; [#2, #3]
[#1, #2, #3]:first(#99).     ; [#1, #2, #3]  -- everything there is
[#1, #2, #3]:first(#0).      ; []
```

A negative count is refused by both: clamping is for asking for more than there
is, not for asking for nonsense.

All three answer a new array and share its elements, an array holding references
— so a slice of an array of arrays sees the same inner arrays.

**Joining.** `join` is `split` backwards, and the round trip holds for every
string and every separator — which is what `split` keeping its empty pieces buys:

```
"a,,b":split(","):join(",").     ; "a,,b"
[]:join(",").                    ; ""
["only"]:join(",").              ; "only"
```

It is strict about what it joins: an array holding anything but a string is an
error rather than a silent `asString` on each element, rendering being what
`asString` and `fill` are for.

The separator **may** be empty, where `split`'s may not. The two are not the
same question: nothing cannot be looked for, since every position contains it,
but putting nothing between the pieces is exactly concatenation.

**Sorting.** With no argument the order comes from *sending* `lessThan`, so a
type that defines one sorts itself:

```
[#3, #1, #2]:sorted:print.                            ; [#1, #2, #3]
["pear", "apple"]:sorted:print.                       ; ["apple", "pear"]
[#1, #3, #2]:sorted({ a, b | b:lessThan(a) }):print.  ; [#3, #2, #1]
```

The comparison answers whether `a` comes strictly before `b`. Mixed types are an
error rather than an arbitrary order, for the same reason arithmetic on them is:
`lessThan` has no coercion to fall back on.

The sort is **stable** -- equal elements keep the order they were in -- which is
what makes sorting twice a way to order by two keys: sort by the minor key
first, then by the major one.

### symbol

| Message | Answers |
| --- | --- |
| `size` | an integer |
| `lessThan(s)` `greaterThan(s)` | a boolean, comparing the text |
| `lessOrEqual(s)` `greaterOrEqual(s)` | a boolean |
| `asString` | the name, as a string |

`'foo` is an interned name: two symbols spelling the same thing are the same
symbol, so `equals` is a pointer comparison. `"foo":asSymbol` finds the existing
one. A symbol never equals a string.

Useful as a tag where a string would be compared character by character:

```
state := 'running.
state:equals('running):ifTrue({ "go":display }).
```

**Symbols have an order**, and it is the text's. Interning is what makes
`equals` a pointer comparison and exactly what makes the pointers say nothing
about order, so these four are the only symbol operations that look at the
characters. It is what lets an array of symbols sort — `sorted` with no block
sends `lessThan` — which a tally kept under symbol keys needs to print in a
stable order.

```
['pear, 'apple, 'fig]:sorted.    ; ['apple, 'fig, 'pear]
```

### boolean

| Message | Answers |
| --- | --- |
| `not` | a boolean |
| `and(block)` `or(block)` | short-circuit; the block runs only if needed |
| `ifTrue(block)` `ifFalse(block)` | the block's answer, or nil |
| `ifElse(t, f)` | the chosen block's answer |

### dictionary

Values kept under keys, found by hashing. There is no literal — `dictionary:new`
makes an empty one.

| Message | Answers |
| --- | --- |
| `new` | an empty dictionary |
| `of(...)` | a dictionary of the arguments, **key then value**; an odd count is an error |
| `size` | an integer |
| `at(key)` | the value; **an error** when the key is not there |
| `at(key, default)` | the value, or `default` when the key is not there |
| `atPut(key, value)` | **the value stored**, so it chains |
| `includes(key)` | a boolean |
| `remove(key)` | the value removed; an error when the key is not there |
| `keys` `values` | an array, in **no order worth relying on** |
| `do(block)` | the dictionary, having run the block once per **value** |
| `keysAndValuesDo(block)` | the same, the block taking a key and a value |

#### Building one in a single expression

`of` is to `dictionary` what it is to `array`, and `#[...]` is its literal the
way `[...]` is the array's — both being real desugaring rather than a form the
compiler knows, so rebinding `dictionary` changes the two together.

```
sizes := #["small" = #1, "large" = #9].
sizes:at("large"):print.        ; #9
#[]:size:print.                 ; #0   -- the empty one

dictionary:of("small", #1):at("small"):print.    ; #1   -- what it lowers to
```

**`=` pairs a key with its value**, and it costs nothing elsewhere: the token is
scanned always and given meaning by whoever is parsing, so it is still equality
inside [`@expr`](#infix-operators) and still refused as a
stray operator outside one. The pairing is the reason to have the literal at
all — alternating elements pair up positionally and a reader has to count.

**`#[` is one token**: the `[` follows the `#` immediately, as a digit must, and
that is what makes it unambiguous. A digit was the only thing that could ever
follow a `#`, so `#[` was an error in every file written before it existed and
cannot now mean something it used to.

**Which is what lets a dictionary be written where it is used.** One could
always be *passed*; what it could not be was built as an argument, and three
statements and a name for a value wanted once is why an options bag is spelled
as an array of alternating names elsewhere in this document.

**A repeated key takes the last value**, as a repeated `atPut` does, and a key
must be a value for the reason [`at`](#dictionary) gives. The pairing is the one
thing `of` can get wrong and it is refused rather than rounded off:

```
dictionary:of("small").
solvm: 'of' takes a key and a value for each entry, and got 1 argument -- the odd one has no value to go with it
```

**Keys are values.** Integers, floats, strings, symbols, booleans and nil are
compared by content, so two keys that look alike are one key. Arrays, blocks,
objects and other dictionaries are compared by identity, where two that look
alike would be two keys — the right answer for `equals` and a useless one here,
so they are refused rather than quietly behaving that way:

```
d := dictionary:new.
d:atPut([#1], "nope").
solvm: 'atPut' wants a value for a key, got array -- those are compared by identity, so two that look alike would be two keys
```

It is the same line the language draws between
[values and references](#values) everywhere else.

`at(key, default)` is the form a counter wants, since it needs no separate
question first:

```
counts:atPut(word, counts:at(word, #0):add(#1)).
```

`do` takes a one-argument block over the values, exactly as an array's does: the
same selector should not want a different shape of block depending on what it is
sent to. `keysAndValuesDo` is the two-argument form, and it beats `keys:do` with
an `at` inside because it does not look each key up a second time.

Both walk a **snapshot of the keys**, so a block that adds to the dictionary it
is walking does not rehash the table underneath itself; one that removes a key
it has not reached yet will not see it.

`keys` and `values` are snapshots too, and their order is the table's, which is
to say arbitrary. Sort before showing anything.

A dictionary is a reference, like an array: `equals` is identity, so two with
equal contents are two dictionaries. It cannot be a constant in a `.sob` for the
same reason an array cannot — it is built at run time.

`nan` is accepted as a key and can never be found again, since `nan:equals(nan)`
is false. That is IEEE showing through rather than a decision made here.

**A dictionary of blocks is a switch statement**, and `at(key, default)` is what
makes the default case one message:

```
action := dictionary:new.
action:atPut('red, { "stop" }).
switch := { light | action:at(light, { "not a light" }):value }.
```

One hash whatever the number of cases, against a walk for a chain of
comparisons. See [dispatch.md](dispatch.md), which also has the two traps that
come of putting closures in a table.

---

### time

A point in time, held as nanoseconds since 1970-01-01T00:00:00Z. A **value**
like a number: two of the same instant are the same time, nothing mutates one,
and there is no literal — an instant comes from a clock or a file.

| Message | Answers |
| --- | --- |
| `fromSeconds(f)` | an instant, from seconds since the epoch *(on the class)* |
| `asSeconds` | seconds since the epoch, as a float |
| `secondsSince(other)` | a float; negative when `other` is later |
| `plusSeconds(f)` | another instant, `f` seconds along |
| `lessThan(t)` `greaterThan(t)` | a boolean |
| `lessOrEqual(t)` `greaterOrEqual(t)` | a boolean |
| `year` `month` `day` | integers; **January is `#1`** |
| `hour` `minute` `second` | integers |
| `weekday` | an integer; **Monday is `#1`**, Sunday `#7` |
| `asString` | ISO-8601 in UTC — `2000-01-01T00:00:00Z` |
| `asString(format)` | the format handed to C's `strftime` |

`asTime` on a string is the way back, and lives there beside `asInteger` and
`asFloat` — a conversion *from* text has always been the string's. It reads a
deliberately narrow slice of ISO-8601:

```
"2026-08-20"                      midnight
"2026-08-20T09:14:02"             T or a space between them
"2026-08-20 09:14:02.5"           a fraction of a second
"2026-08-20T09:14:02Z"            explicitly UTC
"2026-08-20T09:14:02+01:00"       an offset, which is taken off
```

**No zone means UTC**, there being no other kind here. An **offset** is accepted
because an offset is arithmetic — `+01:00` is an exact number of minutes and
says nothing about legislation. A zone *name* is not, and will not be.

Strict, as `asInteger` is: the whole string is the timestamp or it is not one.
**A date that does not exist is refused** rather than rolled forward, which is
what almost every date parser does quietly:

```
"2026-02-29":asTime.
solvm: 'asTime' cannot read that as a date
```

What `asString` writes, `asTime` reads — to the second, that being all
`asString` writes. Through `fromSeconds` and `asSeconds` a fraction survives
too.

**Everything is UTC**, and that is the decision rather than an omission. There
is no local time and no zone. A zone is a political fact that changes by
legislation, twice a year in most places and retroactively in some; an instant
is unambiguous where a wall-clock reading is not. The trailing `Z` is what says
which of the two you are looking at.

**`system:clock` is not this.** That one is a stopwatch — monotonic, unspecified
epoch, only differences meaningful. This is a calendar. A program asking how
long something took wants the first; one asking when it happened wants the
second.

`secondsSince` rather than `sub`: a time minus a time is not a time, and the
name says the direction and the unit, which is what a bare subtraction leaves
you guessing. It answers a float, as `clock` differences do.

`fromSeconds` and `plusSeconds` take a **float**, strictly — `#n:asFloat` is the
conversion, and being asked for it is the point of being strict.

`asString(format)` hands the format to the C library's `strftime`, whose
alphabet is the one everybody already knows. The number-formatting spec is about
width and digits and has nothing to say about a Tuesday, and inventing a third
spec language would have been worse than having two.

Time is a value, so it may be a dictionary key, and `equals` compares instants
rather than identity.

---

### block

| Message | Answers |
| --- | --- |
| `value(...)` | the block's answer; the count must match its parameters |
| `boundTo(receiver)` | a new block over the same code, with `self` set |
| `whileTrue(body)` | nil, having run `body` while the receiver answers true |
| `doUntil(condition)` | nil, having run the receiver **until** the condition is true — the body first, so always at least once |
| `repeat(#n)` | nil, having run the receiver `n` times |
| `onError(handler)` | the block's answer, or the handler's if it failed |
| `ensure(cleanUp)` | the block's answer, having run `cleanUp` either way |
| `timeToRun` | seconds the block took, as a float |
| `timeToRun(#n)` | seconds `n` runs took, as a float |

### object

| Message | Answers |
| --- | --- |
| `new` | a fresh object delegating to the receiver |
| `via(ancestor)` | a delegating view: lookup starts there, `self` stays |
| `parent` | the prototype, or nil at the root; read-only — assigning it shadows the message rather than re-parenting |

`slots` and `slotAt` are listed under [Reflection](#reflection); they are on
every type but answer only for objects.

### system

One object, bound to the global `system`. Not a class: it has no instances, and
it delegates to `object` like everything else. See
[The program and its process](#the-program-and-its-process).

| Message | Answers |
| --- | --- |
| `exit(status)` | nothing — the program stops, with `status` from #0 to #255 |
| `arguments` | an array of strings; the empty array when there were none |
| `write(text)` | writes `text` to standard output and adds nothing — no newline, no rendering |
| `writeError(text)` | the same, to standard **error** |
| `readLine` | one line of standard input without its terminator, or nil at the end |
| `readKey` | one byte as a one-character string, or nil at the end; no wait for return |
| `isTerminal(which)` | whether `'input`, `'output` or `'error` is a terminal |
| `terminalSize` | a dictionary of `"rows"` and `"columns"`, or **nil** when the output is not a terminal |
| `keyWaiting(seconds)` | whether a byte is there to read, waiting up to that long for one |
| `sleep(seconds)` | nil, having waited that long; a float, and a negative one or `nan` is refused |
| `readFile(path)` | the whole file as a string; an error if it is not there |
| `load(path)` | **true** having run a compiled `.sob` here, **false** if it was already loaded |
| `writeFile(path, text)` | nil, having replaced the file's contents |
| `fileExists(path)` | true if a file — not a directory — is at that path |
| `isDirectory(path)` | true if a directory is at that path |
| `filesIn(path)` | an array of the names in a directory; an error if it is not one |
| `appendFile(path, text)` | nil, having added to the end; creates the file |
| `environment(name)` | the variable, or **nil** when it is not set |
| `run(argv)` `run(argv, streams)` | the exit status of another program; `argv` is an array |
| `capture(argv)` `capture(argv, streams)` | a dictionary of `"output"` and `"status"` |
| `fileSize(path)` | an integer, without reading the file; **nil** if nothing is there |
| `fileId(path)` | what the filesystem calls this file, as a string; **nil** if nothing is there |
| `remove(path)` | nil, having deleted a file or an **empty** directory |
| `makeDirectory(path)` | **true** if it made one, **false** if a directory was there; the parent must exist |
| `rename(from, to)` | nil, having moved it; **replaces** an existing `to` |
| `clock` | monotonic seconds as a float; only differences are meaningful |
| `time` | the current instant, as a [time](#time) |
| `modifiedAt(path)` | when a file was last written, as a [time](#time); sub-second; **nil** if nothing is there |
| `setModifiedAt(path, time)` | nil, having set it |
| `modeOf(path)` | the permission bits, as an integer |
| `setMode(path, #mode)` | nil, having set them; `#0` to `#4095` |

### random

A generator, and **you make one**: `random:new` is seeded by the machine and
`random:new(#seed)` is seeded by you and repeats. The prototype answers neither
`upTo` nor `fraction` — a generator has to be something `new` made, because one
shared by everything that reached for it is what having `new` avoids.

| Message | Answers |
| --- | --- |
| `new` | a generator, seeded by the machine |
| `new(#seed)` | a generator seeded by you, which repeats exactly |
| `seed` | the integer it was made with — a **slot**, so `slots` shows it |
| `upTo(#n)` | an integer from `#1` to `#n`, both included |
| `between(#a, #b)` | an integer from `#a` to `#b`, both included |
| `fraction` | a float, at least `0.0` and always less than `1.0` |

```
r := random:new(#20260824).
r:upTo(#6):print.                ; #3
r:between(#-3, #3):print.        ; #0
r:seed:print.                    ; #20260824

colours := ["red", "green", "blue"].
colours:at(r:upTo(colours:size)):display.        ; red
```

**`upTo` counts from #1** because an array is indexed from #1 and picking one of
something is what it is mostly for: `xs:at(r:upTo(xs:size))` needs no
adjustment, and an off-by-one there is the mistake this shape removes.

**Where the state lives is the decision.** It is in the object, so a program
that never says `random:new` is exactly as deterministic as it was before this
existed, and two runs of one chunk still produce the same bytes. That matters
to an embedder: [embedding.md](embedding.md) promises *one chunk, any number of
machines*, and a chunk carrying a generator's state would not be that. A
generator on `system` would have given the machine a history instead.

**The seed is a slot rather than a message**, because it is data: it records
what this generator was made with, so a run seeded by the machine can be had
again by writing the number down. Assigning to it records something untrue
rather than reseeding; there is no message that reseeds, since a generator you
can restart from the middle is one nobody can reason about.

```
machine := random:new.
machine:seed:print.              ; -- whatever the machine chose
random:new(machine:seed).        ; -- and that run again
```

**Why this is in the machine and not a library.** Lehmer's generator is eight
lines of Solum, and [bench.sol](../programs/bench.sol) carried one for four
releases. Every part around those eight lines is a trap:

- The textbook generator needs multiplication that **wraps**, and integer
  arithmetic here traps on overflow instead — so the one everybody knows cannot
  be written in this language at all.
- A seed could only come from `system:clock`, and a clock's low bits are not
  entropy. Measured on the generator `bench.sol` carried: two runs a microsecond
  apart get consecutive seeds, and the **first coin flip is then exactly the
  parity of the start time**, while the first index into 21 takes three values
  out of 21 — forever, in every run.
- `mod n` on the way out is biased toward the low values, by the fraction of the
  word that does not divide evenly.

None of the three shows in the output, which is the same argument that made
`sqrt` a primitive: a thing every program gets wrong the same way belongs in the
machine. The generator is PCG XSH RR 32/64, its state is the object's payload,
and `upTo` draws again rather than taking a remainder.

### nil

`print`, `display`, `asString`, `equals`, `notEquals`, `isNil`, `notNil`, and the
five reflection messages every type carries. Nothing else — asking nil for
anything more is an error rather than nil again, so a missing value is reported
where it is used rather than propagating.

`nil:isNil` is the only receiver that answers true, which is what makes the pair
worth having on every type rather than on nil alone.

`nil` names the value, not a class: there is no global for the class it
dispatches to. `nil:isKindOf(object)` is true, like every other value, but
`nil:slots` says an object is what has slots.

There is one nil and it carries no type, so `string:nil` and `integer:nil` are
not messages anything understands. A name holds a value and never a type, so
what a value is gets asked of the value: `isKindOf(string)` is false for nil and
true for a string. Absence and emptiness are different — `""`, `#0` and `[]` are
values that answer their type's messages, and nil answers almost nothing.

A declared temporary holds nil before it is assigned. A slot that was never
bound is a *miss* rather than a nil, reported like any unknown message, so a
prototype with an optional field binds `nil` as the default. The whole of it,
with the reasoning, is in [absence.md](absence.md).

---

## How errors are reported

**A compile error** names the line and column, then shows the line with the
offending text underlined:

```
[line 2:9] solas: expected '.' between statements at ','
  b := #2 , .
          ^
```

A long line is windowed around the token rather than shown whole. Only the
first error in a statement is reported; the parser then resynchronises at the
next `.` and carries on, so one mistake gives one message.

**A runtime error** stops the program and reports the line of each frame,
innermost first — unless a handler catches it first, which is
[Errors](#errors).

```
solvm: integer does not understand 'frobnicate'
  [line 1] in script
```

A running frame knows its line but not its column: the chunk records a line per
byte of bytecode, and a column would be a second table in every `.sob` for a
message only printed when something has already gone wrong.

Errors, rather than silent answers, are the rule: unknown messages, wrong
argument counts, type mismatches, out-of-range indices, integer overflow,
division by zero, undeclared names, and a block outliving its frame.

**A program may also be stopped**, which is neither of the above. Whoever runs
it may say how many instructions it is allowed and how much it may hold at
once — `solvm --steps=N` and `--memory=N`, or the same two settings from a
program embedding the machine. Reaching either ends the program where it stands,
with a status of 124 rather than the 0 of finishing or the 70 of failing.

```
solvm: stopped: the step limit of 100000 was reached
  [loop.sol:3] in script
```

Neither limit is set unless somebody asks for one, so a program run from a
terminal is not affected. **A stop cannot be caught.** `onError` does not see
it and `ensure` does not run its cleanup, because both of those are ways of
running more code and the allowance for running code is what ran out. There is
no message that reads or changes either limit: a program cannot find out what it
has been given, and cannot give itself more.

---

## Message index

Every built-in message and the types that answer it. The question a reference
gets asked is usually *what has `copyFrom`?* rather than *what does a string
do?*, and the sections above answer only the second — so this answers the first.
144 messages across 247 registrations.

**A test keeps it honest**: a message registered in `builtins.c` and missing
from here fails the build, which is the same bargain that makes every message
appear in an example.

| Message | Answered by |
| --- | --- |
| `abs` | [float](#float), [integer](#integer) |
| `acos` | [float](#float) |
| `add` | [array](#array), [float](#float), [integer](#integer) |
| `and` | [boolean](#boolean) |
| `appendFile` | [system](#system) |
| `asBase` | [integer](#integer) |
| `asByte` | [string](#string) |
| `asCharacter` | [integer](#integer) |
| `asFloat` | [integer](#integer), [string](#string) |
| `asin` | [float](#float) |
| `asInteger` | [string](#string) |
| `asLowercase` | [string](#string) |
| `asSeconds` | [time](#time) |
| `asString` | [every type](#every-type) |
| `asSymbol` | [string](#string) |
| `asTime` | [string](#string) |
| `asUppercase` | [string](#string) |
| `at` | [array](#array), [dictionary](#dictionary), [string](#string) |
| `atan` | [float](#float) |
| `atan2` | [float](#float) |
| `atPut` | [array](#array), [dictionary](#dictionary) |
| `between` | [random](#random) |
| `bitAnd` | [integer](#integer) |
| `bitNot` | [integer](#integer) |
| `bitOr` | [integer](#integer) |
| `bitXor` | [integer](#integer) |
| `boundTo` | [block](#block) |
| `capture` | [system](#system) |
| `ceiling` | [float](#float) |
| `clock` | [system](#system) |
| `collect` | [array](#array) |
| `concat` | [string](#string) |
| `copyFrom` | [array](#array), [string](#string) |
| `cos` | [float](#float) |
| `day` | [time](#time) |
| `dec` | [integer](#integer) |
| `display` | [every type](#every-type) |
| `div` | [float](#float), [integer](#integer) |
| `do` | [array](#array), [dictionary](#dictionary) |
| `doUntil` | [block](#block) |
| `ensure` | [block](#block) |
| `environment` | [system](#system) |
| `equals` | [every type](#every-type) |
| `exit` | [system](#system) |
| `exports` | [every type](#every-type) |
| `exp` | [float](#float) |
| `fileExists` | [system](#system) |
| `fileId` | [system](#system) |
| `filesIn` | [system](#system) |
| `fileSize` | [system](#system) |
| `fill` | [string](#string) |
| `first` | [array](#array) |
| `floor` | [float](#float) |
| `fraction` | [random](#random) |
| `fromSeconds` | [time](#time) |
| `greaterOrEqual` | [float](#float), [integer](#integer), [string](#string), [symbol](#symbol), [time](#time) |
| `greaterThan` | [float](#float), [integer](#integer), [string](#string), [symbol](#symbol), [time](#time) |
| `hour` | [time](#time) |
| `ifElse` | [boolean](#boolean) |
| `ifFalse` | [boolean](#boolean) |
| `ifTrue` | [boolean](#boolean) |
| `inc` | [integer](#integer) |
| `includes` | [dictionary](#dictionary) |
| `indexOf` | [array](#array), [string](#string) |
| `inject` | [array](#array) |
| `isDirectory` | [system](#system) |
| `isKindOf` | [every type](#every-type) |
| `keyWaiting` | [system](#system) |
| `sleep` | [system](#system) |
| `isNil` | [every type](#every-type) |
| `join` | [array](#array) |
| `keys` | [dictionary](#dictionary) |
| `keysAndValuesDo` | [dictionary](#dictionary) |
| `last` | [array](#array) |
| `lessOrEqual` | [float](#float), [integer](#integer), [string](#string), [symbol](#symbol), [time](#time) |
| `lessThan` | [float](#float), [integer](#integer), [string](#string), [symbol](#symbol), [time](#time) |
| `load` | [system](#system) |
| `log` | [float](#float) |
| `loop` | [array](#array) |
| `makeDirectory` | [system](#system) |
| `minute` | [time](#time) |
| `mod` | [float](#float), [integer](#integer) |
| `modeOf` | [system](#system) |
| `modifiedAt` | [system](#system) |
| `month` | [time](#time) |
| `mul` | [float](#float), [integer](#integer) |
| `negated` | [float](#float), [integer](#integer) |
| `new` | [object](#object), [array](#array), [dictionary](#dictionary), [random](#random) — the rest refuse and say what to write |
| `not` | [boolean](#boolean) |
| `notEquals` | [every type](#every-type) |
| `notNil` | [every type](#every-type) |
| `of` | [array](#array), [dictionary](#dictionary) |
| `onError` | [block](#block) |
| `or` | [boolean](#boolean) |
| `parent` | [object](#object) |
| `perform` | [every type](#every-type) |
| `pi` | [float](#float) |
| `plusSeconds` | [time](#time) |
| `pow` | [float](#float) |
| `print` | [every type](#every-type) |
| `raise` | [error](#errors) |
| `readFile` | [system](#system) |
| `readKey` | [system](#system) |
| `readLine` | [system](#system) |
| `remove` | [dictionary](#dictionary), [system](#system) |
| `removeLast` | [array](#array) |
| `rename` | [system](#system) |
| `repeat` | [block](#block), [integer](#integer) |
| `replace` | [string](#string) |
| `respondsTo` | [every type](#every-type) |
| `rounded` | [float](#float) |
| `run` | [system](#system) |
| `second` | [time](#time) |
| `secondsSince` | [time](#time) |
| `select` | [array](#array) |
| `setMode` | [system](#system) |
| `setModifiedAt` | [system](#system) |
| `shiftLeft` | [integer](#integer) |
| `shiftRight` | [integer](#integer) |
| `sin` | [float](#float) |
| `size` | [array](#array), [dictionary](#dictionary), [string](#string), [symbol](#symbol) |
| `slotAt` | [every type](#every-type) |
| `slots` | [every type](#every-type) |
| `sorted` | [array](#array) |
| `split` | [string](#string) |
| `sqrt` | [float](#float) |
| `sub` | [float](#float), [integer](#integer) |
| `tan` | [float](#float) |
| `isTerminal` | [system](#system) |
| `terminalSize` | [system](#system) |
| `time` | [system](#system) |
| `timeToRun` | [block](#block) |
| `trim` | [string](#string) |
| `truncated` | [float](#float) |
| `upTo` | [random](#random) |
| `value` | [block](#block) |
| `values` | [dictionary](#dictionary) |
| `via` | [object](#object) |
| `weekday` | [time](#time) |
| `whileTrue` | [block](#block) |
| `write` | [system](#system) |
| `writeError` | [system](#system) |
| `writeFile` | [system](#system) |
| `year` | [time](#time) |
## Limits

| | |
| --- | --- |
| Recursion | about **254 levels** — the frame cap is 256 and a level costs one frame, now that an `ifElse` branch, a `whileTrue` body, and an `and`/`or` block are inlined rather than called |
| Constants, names, blocks per chunk | **65536** — a two-byte index, and both tables intern, so repeats cost nothing |
| Arguments, parameters, array literal elements | 255 — an argument count is one byte |
| Dictionary literal pairs | **127** — the same byte, two arguments to a pair |
| Locals per frame | 255 |
| Reading a file | whole, or a **range** — `readFile(path, from, count)`; still no handle and no line at a time. A whole read is capped at **2 GiB**, a string's length being a signed 32-bit count, with a peak of **twice the file's size**; a range is capped only on its `count`, so the file itself may be any size |
| Solis input | no limit — the buffer grows, and reading continues while a bracket or a string is open |
| Strings | bytes, not characters: `size` counts bytes, `at` answers a byte, and `"café":size` is 5 |
| Case | ASCII only, and by explicit range rather than the C locale |
| Strings | no `\0`, no unicode escapes |
| Symbols | read-only: `perform`, `respondsTo`, and `slotAt` take one to *name* something, but nothing takes one to *create* a slot — there is no `slotAtPut` |

Collection is mark-and-sweep and stop-the-world. `SOLUM_GC_STRESS=1` collects on
every allocation, which is how the collector is tested.
