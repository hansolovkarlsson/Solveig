# What Proto targets

Asked on 2026-08-31, while 0.1.0 was the whole of the project:

> Will this language also work to create native machine code? As an example, if
> I wanted to make a BASIC compiler that compiled not to Solveig but to Mac
> Silicon binary? I'm not sure which sequence it would be, would it be a
> compiler I run in Proto (`proto cbasic.pro myprogram.bas -> a.out`) or
> would I create a compiler (`solvm cbasic.sob myprogram.bas -> a.out`)?

**Two questions are tangled in that, and separating them is most of the answer.**

## Proto does not run programs

`bin/proto` is a translator. A `.pro` goes in and Solveig source comes out,
and that is all it does — so `proto cbasic.pro myprogram.bas` is not a
sequence that could exist. **`cbasic.pro` is not a compiler Proto runs. It is
source that becomes a compiler.**

The second sequence is the right one, with one step in front of it:

```sh
proto cbasic.pro -o cbasic.sol      # Proto  -> Solveig source
solas   cbasic.sol -o cbasic.sob      # Solveig  -> bytecode
solvm   cbasic.sob myprogram.bas      # run the BASIC compiler
```

**What `cbasic` writes is `cbasic`'s business.** Text, a `.sob`, ARM64, a `.d64`
image. Solveig has `system:arguments`, `system:readFile`, `system:writeFile` and
`shell:run`, which is everything a compiler needs from its host, so this works
today with nothing added to anything.

**And it needs nothing from Proto at all.** Proto is only the language the
compiler was written in.

## So there are two senses of "target", and only one is a Proto question

| | |
| --- | --- |
| **What Proto's own back end emits** | Solveig source. A Proto question, answered in the README under *What Proto is allowed to know about Solveig*. |
| **What a program written in Proto emits** | Whatever that program writes. Not a Proto question, any more than what a C program writes is a question about C. |

The BASIC compiler is the second. It is a program, and Proto's involvement
ends when the program is compiled.

## Could Proto itself emit machine code?

Architecturally yes, and cleanly. **The front end knows nothing about Solveig.**
The lexer, the dialect table, the tree, the spans and the map are all substrate
-agnostic; `proto/src/emit.c` is the only file that has ever heard of Solveig.
Replacing it is a seam rather than a rewrite.

**It is still not planned, and for the reason ROADMAP.md gives against the
smaller version of it.** Emitting `.sob` and bypassing Solas would mean owning
the instruction set and the file format and reimplementing what Solas does well.
Emitting machine code means owning register allocation, the AAPCS64 calling
convention, stack frames, relocations and Mach-O — none of which says anything
about whether a grammar declared per module is a good idea, which is the only
thing this project exists to find out.
[does-it-pay.md](does-it-pay.md) is what six programs and two readers who had
never seen the language have said about it so far — and the sixth program is a
BASIC *interpreter*, which is the half of this page's own question that had no
program behind it until 2026-09-02.

**On Apple Silicon the surprise is not the instruction encoding.** It is that a
hand-written Mach-O arm64 executable is killed by the kernel until it is at
least ad-hoc signed — `codesign -s -`. `ld` does that quietly on every link,
which is why nobody meets the rule until they stop using `ld`.

Which points at the cheap path, and the one to take:

> **Emit ARM64 assembly text and let `cc` assemble and link it.**

Mach-O, relocations and signing all become somebody else's problem, and the
output is something a person can read.

```sh
proto cbasic.pro -o cbasic.sol && solas cbasic.sol -o cbasic.sob
solvm cbasic.sob myprogram.bas > myprogram.s
cc myprogram.s -o a.out
```

Every step of that works now.

## Where this grows, if it grows

**This page used to argue that `@language` was where it grows** — that the
natural move was for it to choose the reader *and* the emitter, so that a back
end became a declared thing the way the grammar already is, and "Proto targets
ARM64" was a line in a file rather than a fork of the project.

**That sentence names the right feature and the wrong directive**, which is why
`@language` was removed in 0.10.0 rather than grown into it. Read `@language
<name>.` at the top of a file and it says *the body below is written in
`<name>`* — and that is false in every file with a header, because a module that
declares `+` and `while` is exactly not Solveig any more. The only reading under
which it was true, *the substrate is Solveig*, is the same for every `.pro`
there will ever be and is already carried by the extension.

**The thing that could differ between two files is the output.** So the sentence
above already spells its own directive: `@target arm64.`, naming the back end,
which is a thing a file could sensibly disagree with another file about. If a
second emitter is ever built, that is what gets added, and it will name what it
selects from the first commit instead of inheriting a word that misleads.

Selecting a *reader* is a separate and much larger question, and it keeps the
seam it always had: something read before the first statement would have to name
it. `proto/include/proto/lex.h` says so in a sentence now, instead of a
directive standing empty in every file. See COMPLETED.md 14.

## Why a code generator is the right first real program

A BASIC compiler written in Proto is a better test of the whole idea than
another arithmetic example, and it is the one worth doing next.

**A code generator is exactly the kind of program that wants a declared
notation** — instruction patterns, addressing modes, a peephole table. If
declaring a grammar per module does not help there, that is worth knowing early,
and it is not a thing a small example can tell you.
