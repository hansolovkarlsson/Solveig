# One file per construct, held against both the compiler and the grammar

**The failure this catches is a construct being added to the language and not to
[solum.bnf](../solum.bnf).** That happened twice in three days —
[`@expr{...}`](../../../docs/ideas.md) on 2026-08-29 and `#["key" = value]` on
2026-08-30 — and nothing would have said so, because the only check on the
grammar held it against `GRAMMAR.md`: two documents written by hand from one
understanding, which by this repository's own rule is not a comparison.

Every file here must be accepted by **both** `solas` and `check_syntax` with
`solum.bnf`. `tests/test_cli.c` requires it, so a construct added without the
grammar following fails the build.

**Valid programs only.** The two are allowed to disagree in the other
direction, because a grammar cannot carry a scope rule: `self := #1` is
syntactically an ordinary identifier being assigned and semantically an error,
and `{ | t, t | t }` is a duplicate declaration. Those live in the compiler and
are listed in `docs/` rather than here.

**Adding one.** A new construct in the language gets a file here in the same
commit. It is the smallest program that uses it and nothing else.
