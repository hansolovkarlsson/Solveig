# Solveig

A small object-oriented language, its bytecode virtual machine, and a REPL.

Everything is an object, including classes, and work happens by sending
messages to them:

```
a := #45         ; ':=' binds a name; '#' tags an integer ( bare 45 is a float )
a:print.         ; ':' sends a message, '.' ends the statement

xs := [#1, #2, #3].            ; sugar for array:of(#1, #2, #3)
xs:do({ x | x:print }).        ; { } is a block: code as a value
```

## The names

**Solveig** is the project. The language it holds is **Solum**, compiled by
**Solas**, run by **SolVM**, and explored through **Solis**. The program is
`bin/solvm` and its sources are under `solum/` -- the same word in two hands, as
below.

*Solveig* is Old Norse -- *Sólveig*, from *sól*, "sun", joined to *veig*, which
is usually read as "strength", though the second element is not settled and has
also been glossed as "draught" or "power". It is still an ordinary given name
across Norway, Sweden, and Denmark. Most people who recognise it will recognise
it from Ibsen's *Peer Gynt*, where Solveig is the one who waits, and from
Grieg's setting of her song.

**SolVM** reads two ways, and both are meant. It is the Sol virtual machine --
and it is *SOLVM*, which is how *solum* was written before the alphabet split V
into two letters. Classical Latin had a single **V** standing for both the vowel
and the consonant; U is a much later invention, which is why Roman inscriptions
give us SOLVM and not SOLUM. So the machine is not named *after* the language it
runs. It is the same word, cut in stone.

The rest keep the *sol-* root, so the whole family turns on the sun: *solum*,
the ground underfoot; *solis*, of the sun; and Solveig, the Norse cousin among
them -- the same star, in a different language.

## Layout

| Path      | What                                                             |
| --------- | ---------------------------------------------------------------- |
| `solas/`  | **Solas** -- the compiler: source text to bytecode                |
| `solum/`  | **SolVM** -- the virtual machine, built as `bin/solvm`               |
| `solis/`  | **Solis** -- the REPL: compiles and runs one line at a time       |
| `docs/`   | [REFERENCE.md](docs/REFERENCE.md), [design.md](docs/design.md), [ROADMAP.md](docs/ROADMAP.md), [CHANGELOG.md](docs/CHANGELOG.md) |
| `tests/`  | Test suite                                                        |
| `examples/` | Sample `.sol` programs                                          |

Each component keeps its public headers in `<component>/include/<component>/`
and its implementation in `<component>/src/`. `solum/include/solum/bytecode.h`
is the contract between the compiler and the VM -- it is the one file both
sides include, so the instruction set is defined exactly once.

## Build

```sh
make          # builds bin/solas, bin/solvm, bin/solis
make test     # builds and runs the test suite
make clean
```

No dependencies beyond a C11 compiler and `make`.

## Status

The first vertical slice runs -- source text through the scanner, compiler, and
dispatch loop:

```
$ ./bin/solis
> a := #45.
> a:add(#5):print.
#50
> a:print.
#45
> #45:add(1.5).
solum: 'add' expects integer, got float (no implicit coercion)
```

Working: the scanner, the single-pass compiler, the VM dispatch loop, and
built-in `integer` and `float` classes with `new`, `print`, `add`, `sub`, `mul`.
Arithmetic is strict -- integers and floats never coerce, and integer overflow
traps rather than wrapping.

Compiling to a file and running it separately works too:

```
$ ./bin/solas examples/hello.sol      # writes examples/hello.sob
$ ./bin/solvm examples/hello.sob
#45
```

`.sob` files are little-endian and portable, and are verified before they run --
see [docs/design.md](docs/design.md) for the layout and what the verifier
checks.

A method is a name bound on a class, just as a variable is a name bound in the
globals -- so it uses the same `:=`. The right-hand side is evaluated, and a
slot holding a block is what makes a method:

```
> integer:double := { self:mul(#2) }.
> #21:double:print.
#42
> integer:poly := { a, b | self:mul(a):add(b) }.
> #10:poly(#3, #7):print.
#37
```

A slot holding anything else is data, evaluated once when bound. And because
`:=` evaluates, a method can be computed rather than written out:

```
> maker := { { self:mul(#2) } }.
> integer:double := maker:value().
> #21:double:print.
#42
```

See [examples/methods.sol](examples/methods.sol).

Braces make a block -- code as a value. Control flow is then ordinary message
sending, with no control-flow syntax in the language at all:

```
> #5:lessThan(#10):ifElse({ #100:print }, { #200:print }).
#100
> i := #0.
> { i:lessThan(#5) }:whileTrue({ i := i:add(#1) }).
> i:print.
#5
```

Which is enough to be Turing-complete:

```
integer:factorial := {
    self:lessThan(#2):ifElse({ #1 }, { self:mul( self:sub(#1):factorial ) })
}.
#20:factorial:print.      ; #2432902008176640000
```

See [examples/blocks.sol](examples/blocks.sol).

Still to do:

- [ ] inlining `whileTrue` -- the jump machinery is in place; it needs a backward jump
- [ ] sorting -- strings and numbers order, but arrays have no `sort`

## License

MIT -- see [LICENSE](LICENSE).

[docs/REFERENCE.md](docs/REFERENCE.md) is the language reference: syntax,
semantics, and every built-in message.

The full list of what is left -- open design questions, known limitations, and
unbuilt work -- is in [docs/ROADMAP.md](docs/ROADMAP.md).

See [docs/design.md](docs/design.md) for the object model and the instruction
set, and [docs/CHANGELOG.md](docs/CHANGELOG.md) for what has changed.
