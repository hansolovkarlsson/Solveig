# Solum

A small object-oriented language, its bytecode virtual machine, and a REPL.

Everything is an object, including classes, and work happens by sending
messages to them:

```
a := #45         ; ':=' binds a name; '#' tags an integer ( bare 45 is a float )
a:print.         ; ':' sends a message, '.' ends the statement
```

## Layout

| Path      | What                                                             |
| --------- | ---------------------------------------------------------------- |
| `solas/`  | **Solas** -- the compiler: source text to bytecode                |
| `solum/`  | **Solum** -- the virtual machine: executes bytecode and loads `.sob` |
| `solis/`  | **Solis** -- the REPL: compiles and runs one line at a time       |
| `docs/`   | Design notes, instruction set, open questions                     |
| `tests/`  | Test suite                                                        |
| `examples/` | Sample `.sol` programs                                          |

Each component keeps its public headers in `<component>/include/<component>/`
and its implementation in `<component>/src/`. `solum/include/solum/bytecode.h`
is the contract between the compiler and the VM -- it is the one file both
sides include, so the instruction set is defined exactly once.

## Build

```sh
make          # builds bin/solas, bin/solum, bin/solis
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
$ ./bin/solum examples/hello.sob
#45
```

`.sob` files are little-endian and portable, and are verified before they run --
see [docs/design.md](docs/design.md) for the layout and what the verifier
checks.

Methods are defined with `:=`, the same operator that binds a name -- a method
is a name bound on a class, just as a variable is a name bound in the globals:

```
> integer:double() := self:mul(#2).
> #21:double():print.
#42
> integer:poly(a, b) := self:mul(a):add(b).
> #10:poly(#3, #7):print.
#37
```

See [examples/methods.sol](examples/methods.sol) for parameters, locals, and
multi-statement bodies.

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
integer:factorial() := (
    self:lessThan(#2):ifElse({ #1 }, { self:mul( self:sub(#1):factorial() ) })
).
#20:factorial():print.      ; #2432902008176640000
```

See [examples/blocks.sol](examples/blocks.sol).

Still to do:

- [ ] block parameters (enough for control flow without them; iteration wants them)
- [ ] user-defined classes (methods can only be added to the built-in ones)
- [ ] strings and symbols -- both scan, but neither has a runtime type
- [ ] a garbage collector (objects are freed en masse at shutdown)

See [docs/design.md](docs/design.md) for the object model, the instruction set,
and the design questions still open.
