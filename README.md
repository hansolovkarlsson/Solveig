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

Still to do:

- [ ] bytecode methods and call frames (every method is a C primitive today)
- [ ] strings and symbols -- both scan, but neither has a runtime type
- [ ] a garbage collector (objects are freed en masse at shutdown)

See [docs/design.md](docs/design.md) for the object model, the instruction set,
and the design questions still open.
